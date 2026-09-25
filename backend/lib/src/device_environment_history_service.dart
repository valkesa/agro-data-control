import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control_backend/src/firestore_device_environment_history_repository.dart';
import 'package:agro_data_control_backend/src/plc_installation_config.dart';

enum DeviceHistorySiteState {
  unverified,
  verified,
  mismatch,
  temporarilyUnavailable,
}

/// Serialized local transactions precede every remote write. On local failure
/// the mutation rolls back and remote writes stop until the disk is healthy.
class DeviceEnvironmentHistoryService {
  DeviceEnvironmentHistoryService({
    required this.config,
    required FirestoreDeviceEnvironmentHistoryRepository repository,
  }) : _repository = repository;
  final DeviceEnvironmentHistoryConfig config;
  final FirestoreDeviceEnvironmentHistoryRepository _repository;
  Future<void> _queue = Future<void>.value();
  _HourlyAccumulator? _currentHour;
  _DailyAccumulator? _currentDaily;
  DateTime? _lastSampleSlot;
  final List<DeviceEnvironmentHourlyRecord> _pendingHourly = [];
  final List<DeviceEnvironmentDailyRecord> _pendingDaily = [];
  bool _recovered = false;
  bool _durabilityDegraded = false;
  DeviceHistorySiteState _siteState = DeviceHistorySiteState.unverified;
  DeviceHistorySiteState get siteState => _siteState;
  bool get durabilityDegraded => _durabilityDegraded;
  bool get writesBlocked => _siteState == DeviceHistorySiteState.mismatch;
  bool get isEnabled => config.enabled && _repository.isConfigured;
  List<DeviceEnvironmentHourlyRecord> get pendingHourlyPeriods =>
      List.unmodifiable(_pendingHourly);
  List<DeviceEnvironmentDailyRecord> get pendingDailyPeriods =>
      List.unmodifiable(_pendingDaily);

  /// Collision-free encoding of every effective identity component.
  String get checkpointPath {
    final dir = config.checkpointDirectoryPath.trim();
    if (dir.isEmpty)
      throw StateError('Durable checkpoint directory is required');
    String part(String value) =>
        base64Url.encode(utf8.encode(value)).replaceAll('=', '');
    final identity = [
      _repository.effectiveProjectId,
      config.firestoreDatabaseId,
      config.tenantId,
      config.siteId,
      config.deviceId,
    ].map(part).join('.');
    return '$dir/env_history_$identity.json';
  }

  void handleSnapshot({
    required Map<String, Object?> unitsJson,
    required DateTime observedAtUtc,
  }) {
    if (!isEnabled) return;
    _queue = _queue.then((_) => _process(unitsJson, observedAtUtc)).catchError((
      Object error,
      StackTrace stack,
    ) {
      _log('processing error=$error');
    });
  }

  Future<void> dispose() => _queue;

  Future<void> _process(
    Map<String, Object?> units,
    DateTime observedUtc,
  ) async {
    if (!_recovered) {
      // Load only; recovery must never write before Site verification.
      try {
        final checkpoint = _loadCheckpoint();
        if (checkpoint != null) _restore(checkpoint);
        _recovered = true;
      } catch (error) {
        _durabilityDegraded = true;
        _log(
          'CRITICAL checkpoint unavailable; no sampling or writes error=$error',
        );
        return;
      }
    }
    if (_durabilityDegraded && !_commitLocal(() {})) return;
    if (_siteState == DeviceHistorySiteState.unverified ||
        _siteState == DeviceHistorySiteState.temporarilyUnavailable) {
      await _checkDeviceSite();
    }
    await _retryPending();
    if (_durabilityDegraded || writesBlocked) return;
    final local = observedUtc.toUtc().subtract(const Duration(hours: 3));
    final hour = _hourStart(local);
    // Out-of-order clocks/snapshots must not reopen a completed period.
    if (_currentHour != null && hour.isBefore(_currentHour!.hourStart)) return;
    var closedPeriod = false;
    if (_currentHour != null && !_isSameHour(_currentHour!.hourStart, hour)) {
      if (!_commitLocal(_closeHour)) return;
      closedPeriod = true;
    }
    final day = _formatDate(hour);
    if (_currentDaily != null && _currentDaily!.dateKey != day) {
      if (!_commitLocal(_closeDay)) return;
      closedPeriod = true;
    }
    if (closedPeriod) await _retryPending();
    if (_durabilityDegraded) return;
    final slot = _resolveSampleSlot(local);
    if (slot == null ||
        (_lastSampleSlot != null && !slot.isAfter(_lastSampleSlot!)))
      return;
    final tempFresh = _checkFreshness(units, config.temperatureSourcePath);
    final humFresh = _checkFreshness(units, config.humiditySourcePath);
    final temp = tempFresh.fresh
        ? _extractDouble(units, config.temperatureSourcePath)
        : null;
    final hum = humFresh.fresh
        ? _extractDouble(units, config.humiditySourcePath)
        : null;
    if (!_commitLocal(() {
      _currentHour ??= _HourlyAccumulator(hourStart: hour);
      _currentDaily ??= _DailyAccumulator(dateKey: day);
      _lastSampleSlot = slot;
      if (temp != null) _currentHour!.addTemperature(temp);
      if (hum != null) _currentHour!.addHumidity(hum);
    }))
      return;
    _log(
      temp == null && hum == null
          ? 'sample skipped slot=$slot reason=invalid_or_not_fresh'
          : 'history sample accepted slot=$slot temp=$temp humidity=$hum',
    );
  }

  /// One synchronous mutation: no observable intermediate checkpoint between
  /// adding pending, folding the daily and retiring currentHour (C1).
  void _closeHour() {
    final acc = _currentHour!;
    _currentHour = null;
    if (acc.temperatureCount == 0 && acc.humidityCount == 0) return;
    final id =
        '${_formatDate(acc.hourStart)}T${acc.hourStart.hour.toString().padLeft(2, '0')}';
    final record = DeviceEnvironmentHourlyRecord(
      periodId: id,
      tenantId: config.tenantId,
      siteId: config.siteId,
      deviceId: config.deviceId,
      periodStartUtc: _fromArgentinaLocal(acc.hourStart),
      periodEndUtc: _fromArgentinaLocal(
        acc.hourStart.add(const Duration(hours: 1)),
      ),
      schemaVersion: schemaVersion,
      createdAtUtc: DateTime.now().toUtc(),
      temperature: acc.temperatureStats,
      humidity: acc.humidityStats,
    );
    _currentDaily ??= _DailyAccumulator(dateKey: _formatDate(acc.hourStart));
    _currentDaily!.foldHourly(record);
    if (!_pendingHourly.any((r) => r.periodId == id))
      _pendingHourly.add(record);
  }

  void _closeDay() {
    final acc = _currentDaily!;
    _currentDaily = null;
    if (acc.temperatureCount == 0 && acc.humidityCount == 0) return;
    final start = DateTime.parse('${acc.dateKey}T00:00:00Z');
    final record = DeviceEnvironmentDailyRecord(
      periodId: acc.dateKey,
      tenantId: config.tenantId,
      siteId: config.siteId,
      deviceId: config.deviceId,
      periodStartUtc: _fromArgentinaLocal(start),
      periodEndUtc: _fromArgentinaLocal(start.add(const Duration(days: 1))),
      schemaVersion: schemaVersion,
      createdAtUtc: DateTime.now().toUtc(),
      temperature: acc.temperatureStats,
      humidity: acc.humidityStats,
    );
    if (!_pendingDaily.any((r) => r.periodId == record.periodId))
      _pendingDaily.add(record);
  }

  Future<void> _retryPending() async {
    if (_siteState != DeviceHistorySiteState.verified || _durabilityDegraded)
      return;
    for (final record in List<DeviceEnvironmentHourlyRecord>.of(
      _pendingHourly,
    )) {
      try {
        await _repository.saveHourly(record);
      } catch (error) {
        _log('hourly kept pending period=${record.periodId} error=$error');
        continue;
      }
      // If this checkpoint fails the previous durable pending remains intact.
      // Replaying a confirmed write has the same id, content and createdAt.
      if (!_commitLocal(
        () => _pendingHourly.removeWhere((r) => r.periodId == record.periodId),
      ))
        return;
      _log('hourly aggregate written period=${record.periodId}');
    }
    for (final record in List<DeviceEnvironmentDailyRecord>.of(_pendingDaily)) {
      try {
        await _repository.saveDaily(record);
      } catch (error) {
        _log('daily kept pending period=${record.periodId} error=$error');
        continue;
      }
      if (!_commitLocal(
        () => _pendingDaily.removeWhere((r) => r.periodId == record.periodId),
      ))
        return;
      _log('daily aggregate written period=${record.periodId}');
    }
  }

  Future<void> _checkDeviceSite() async {
    try {
      final actual = await _repository.fetchDeviceSiteId();
      _siteState = actual == null
          ? DeviceHistorySiteState.temporarilyUnavailable
          : actual == config.siteId
          ? DeviceHistorySiteState.verified
          : DeviceHistorySiteState.mismatch;
      _log(
        'site validation state=${_siteState.name} expected=${config.siteId} actual=$actual',
      );
    } catch (error) {
      _siteState = DeviceHistorySiteState.temporarilyUnavailable;
      _log('site temporarily unavailable; writes deferred error=$error');
    }
  }

  _Checkpoint _snapshot() => _Checkpoint(
    tenantId: config.tenantId,
    siteId: config.siteId,
    deviceId: config.deviceId,
    firestoreProjectId: _repository.effectiveProjectId,
    firestoreDatabaseId: config.firestoreDatabaseId,
    lastSampleSlot: _lastSampleSlot,
    currentHour: _currentHour,
    dailyAccumulator: _currentDaily,
    pendingHourly: _pendingHourly,
    pendingDaily: _pendingDaily,
  );

  void _restore(_Checkpoint state) {
    _currentHour = state.currentHour;
    _currentDaily = state.dailyAccumulator;
    _lastSampleSlot = state.lastSampleSlot;
    _pendingHourly
      ..clear()
      ..addAll(state.pendingHourly);
    _pendingDaily
      ..clear()
      ..addAll(state.pendingDaily);
  }

  bool _commitLocal(void Function() mutate) {
    final before = _Checkpoint.fromJson(
      jsonDecode(jsonEncode(_snapshot().toJson())) as Map<String, dynamic>,
    );
    try {
      mutate();
      final file = File(checkpointPath);
      file.parent.createSync(recursive: true);
      final tmp = File('${file.path}.tmp');
      tmp.writeAsStringSync(jsonEncode(_snapshot().toJson()), flush: true);
      tmp.renameSync(file.path);
      _durabilityDegraded = false;
      return true;
    } catch (error) {
      _restore(before);
      _durabilityDegraded = true;
      _log(
        'CRITICAL durability degraded; transition rolled back, writes stopped error=$error',
      );
      return false;
    }
  }

  _Checkpoint? _loadCheckpoint() {
    final file = File(checkpointPath);
    if (!file.existsSync()) return null;
    try {
      final state = _Checkpoint.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      );
      if (state.tenantId != config.tenantId ||
          state.siteId != config.siteId ||
          state.deviceId != config.deviceId ||
          state.firestoreProjectId != _repository.effectiveProjectId ||
          state.firestoreDatabaseId != config.firestoreDatabaseId) {
        throw const FormatException('checkpoint identity mismatch');
      }
      return state;
    } catch (error) {
      _log(
        'CRITICAL checkpoint rejected; preserving for diagnosis error=$error',
      );
      // A failure to quarantine propagates: never overwrite unexamined state.
      file.renameSync(
        '${file.path}.rejected.${DateTime.now().microsecondsSinceEpoch}',
      );
      return null;
    }
  }

  DateTime _fromArgentinaLocal(DateTime v) => DateTime.utc(
    v.year,
    v.month,
    v.day,
    v.hour,
    v.minute,
    v.second,
  ).add(const Duration(hours: 3));
  String _formatDate(DateTime v) =>
      '${v.year.toString().padLeft(4, '0')}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
  void _log(String message) => stdout.writeln(
    '[device-environment-history] tenant=${config.tenantId} device=${config.deviceId} $message',
  );
  _FreshnessResult _checkFreshness(
    Map<String, Object?> unitsJson,
    String sourcePath,
  ) {
    final Map<String, Object?>? unit = _resolveUnit(unitsJson, sourcePath);
    if (unit == null) {
      return const _FreshnessResult(fresh: false, reason: 'unit_missing');
    }
    if (unit['dataFresh'] != true) {
      return const _FreshnessResult(fresh: false, reason: 'data_not_fresh');
    }
    if (unit['plcOnline'] != true) {
      return const _FreshnessResult(fresh: false, reason: 'plc_offline');
    }
    if (unit['plcRunning'] == false) {
      return const _FreshnessResult(fresh: false, reason: 'plc_stopped');
    }
    return const _FreshnessResult(fresh: true, reason: null);
  }

  DateTime? _resolveSampleSlot(DateTime observedLocal) {
    final int minute = observedLocal.minute;
    if (minute % sampleIntervalMinutes != 0) {
      return null;
    }
    return DateTime.utc(
      observedLocal.year,
      observedLocal.month,
      observedLocal.day,
      observedLocal.hour,
      minute,
    );
  }
}

/// §2 — same cadence [TemperatureHistoryService] already uses.
const int sampleIntervalMinutes = 20;

/// §3/§4 — bump if the hourly/daily document shape ever changes
/// incompatibly.
const int schemaVersion = 1;

/// H13 — bump if the local checkpoint file's own shape ever changes
/// incompatibly (independent from the Firestore document `schemaVersion`).
const int checkpointSchemaVersion = 3;

/// §11 — Argentina has not observed DST since 2009 (Ley 25.155 effectively
/// froze it at UTC-3 year-round), so a fixed offset is exact for every
/// client this backend serves today, not an approximation.
const Duration argentinaUtcOffset = Duration(hours: -3);

DateTime _hourStart(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day, value.hour);

bool _isSameHour(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day &&
    left.hour == right.hour;

class _FreshnessResult {
  const _FreshnessResult({required this.fresh, required this.reason});
  final bool fresh;
  final String? reason;
}

Map<String, Object?>? _resolveUnit(
  Map<String, Object?> unitsJson,
  String sourcePath,
) {
  final List<String> parts = sourcePath.split('.');
  if (parts.isEmpty) {
    return null;
  }
  final String unitKey = parts.first.trim();
  final Object? unitRaw = unitsJson[unitKey];
  if (unitRaw is Map<String, Object?>) {
    return unitRaw;
  }
  if (unitRaw is Map) {
    return unitRaw.map(
      (Object? key, Object? value) => MapEntry(key.toString(), value),
    );
  }
  return null;
}

double? _extractDouble(Map<String, Object?> unitsJson, String sourcePath) {
  final List<String> parts = sourcePath.split('.');
  if (parts.length < 2) {
    return null;
  }
  final String signalKey = parts.sublist(1).join('.').trim();
  final Map<String, Object?>? unit = _resolveUnit(unitsJson, sourcePath);
  if (unit == null) {
    return null;
  }
  final Object? raw = unit[signalKey];
  if (raw is num) {
    final double value = raw.toDouble();
    return value.isFinite ? value : null;
  }
  if (raw is String) {
    final double? parsed = double.tryParse(raw);
    if (parsed != null && parsed.isFinite) {
      return parsed;
    }
  }
  return null;
}

class _HourlyAccumulator {
  _HourlyAccumulator({required this.hourStart});

  final DateTime hourStart;

  double tempSum = 0;
  int temperatureCount = 0;
  double? minTemp;
  double? maxTemp;

  double humSum = 0;
  int humidityCount = 0;
  double? minHum;
  double? maxHum;

  void addTemperature(double value) {
    tempSum += value;
    temperatureCount += 1;
    minTemp = minTemp == null || value < minTemp! ? value : minTemp;
    maxTemp = maxTemp == null || value > maxTemp! ? value : maxTemp;
  }

  void addHumidity(double value) {
    humSum += value;
    humidityCount += 1;
    minHum = minHum == null || value < minHum! ? value : minHum;
    maxHum = maxHum == null || value > maxHum! ? value : maxHum;
  }

  DeviceEnvironmentStats get temperatureStats => temperatureCount == 0
      ? DeviceEnvironmentStats.empty
      : DeviceEnvironmentStats(
          avg: tempSum / temperatureCount,
          min: minTemp!,
          max: maxTemp!,
          sampleCount: temperatureCount,
        );

  DeviceEnvironmentStats get humidityStats => humidityCount == 0
      ? DeviceEnvironmentStats.empty
      : DeviceEnvironmentStats(
          avg: humSum / humidityCount,
          min: minHum!,
          max: maxHum!,
          sampleCount: humidityCount,
        );

  Map<String, Object?> toJson() => <String, Object?>{
    'hourStart': hourStart.toIso8601String(),
    'tempSum': tempSum,
    'tempCount': temperatureCount,
    'tempMin': minTemp,
    'tempMax': maxTemp,
    'humSum': humSum,
    'humCount': humidityCount,
    'humMin': minHum,
    'humMax': maxHum,
  };

  static _HourlyAccumulator fromJson(Map<String, dynamic> json) {
    final _HourlyAccumulator acc = _HourlyAccumulator(
      hourStart: DateTime.parse(json['hourStart'] as String),
    );
    acc
      ..tempSum = (json['tempSum'] as num).toDouble()
      ..temperatureCount = json['tempCount'] as int
      ..minTemp = (json['tempMin'] as num?)?.toDouble()
      ..maxTemp = (json['tempMax'] as num?)?.toDouble()
      ..humSum = (json['humSum'] as num).toDouble()
      ..humidityCount = json['humCount'] as int
      ..minHum = (json['humMin'] as num?)?.toDouble()
      ..maxHum = (json['humMax'] as num?)?.toDouble();
    return acc;
  }
}

/// §8/§9 hardening — O(1)-updatable running daily aggregate, folded from
/// each hour's already-computed stats (never rereads Firestore). Written to
/// Firestore exactly once, when the day rolls over (`_closeDay`) — not
/// recomputed/rewritten on every hourly close like the pre-hardening
/// version did.
class _DailyAccumulator {
  _DailyAccumulator({required this.dateKey});

  final String dateKey;

  double tempSum = 0;
  int temperatureCount = 0;
  double? minTemp;
  double? maxTemp;

  double humSum = 0;
  int humidityCount = 0;
  double? minHum;
  double? maxHum;

  final Set<String> hoursIncluded = <String>{};

  void foldHourly(DeviceEnvironmentHourlyRecord hourly) {
    if (!hourly.periodId.startsWith('${dateKey}T'))
      throw StateError('Daily hour belongs to another date');
    if (!hoursIncluded.add(hourly.periodId)) return;
    final DeviceEnvironmentStats temp = hourly.temperature;
    if (temp.hasData) {
      tempSum += temp.avg! * temp.sampleCount;
      temperatureCount += temp.sampleCount;
      minTemp = minTemp == null || temp.min! < minTemp! ? temp.min : minTemp;
      maxTemp = maxTemp == null || temp.max! > maxTemp! ? temp.max : maxTemp;
    }
    final DeviceEnvironmentStats hum = hourly.humidity;
    if (hum.hasData) {
      humSum += hum.avg! * hum.sampleCount;
      humidityCount += hum.sampleCount;
      minHum = minHum == null || hum.min! < minHum! ? hum.min : minHum;
      maxHum = maxHum == null || hum.max! > maxHum! ? hum.max : maxHum;
    }
  }

  DeviceEnvironmentStats get temperatureStats => temperatureCount == 0
      ? DeviceEnvironmentStats.empty
      : DeviceEnvironmentStats(
          avg: tempSum / temperatureCount,
          min: minTemp,
          max: maxTemp,
          sampleCount: temperatureCount,
        );

  DeviceEnvironmentStats get humidityStats => humidityCount == 0
      ? DeviceEnvironmentStats.empty
      : DeviceEnvironmentStats(
          avg: humSum / humidityCount,
          min: minHum,
          max: maxHum,
          sampleCount: humidityCount,
        );

  Map<String, Object?> toJson() => <String, Object?>{
    'dateKey': dateKey,
    'tempSum': tempSum,
    'tempCount': temperatureCount,
    'tempMin': minTemp,
    'tempMax': maxTemp,
    'humSum': humSum,
    'humCount': humidityCount,
    'humMin': minHum,
    'humMax': maxHum,
    'hoursIncluded': hoursIncluded.toList(),
  };

  static _DailyAccumulator fromJson(Map<String, dynamic> json) {
    final _DailyAccumulator acc = _DailyAccumulator(
      dateKey: json['dateKey'] as String,
    );
    acc
      ..tempSum = (json['tempSum'] as num).toDouble()
      ..temperatureCount = json['tempCount'] as int
      ..minTemp = (json['tempMin'] as num?)?.toDouble()
      ..maxTemp = (json['tempMax'] as num?)?.toDouble()
      ..humSum = (json['humSum'] as num).toDouble()
      ..humidityCount = json['humCount'] as int
      ..minHum = (json['humMin'] as num?)?.toDouble()
      ..maxHum = (json['humMax'] as num?)?.toDouble()
      ..hoursIncluded.addAll((json['hoursIncluded'] as List).cast<String>());
    return acc;
  }
}

/// H13 — the full local checkpoint contract: identity (H3), the in-progress
/// hour/day accumulators, `lastSampleSlot` (H2), and both durable pending
/// lists (H1/H6).
class _Checkpoint {
  const _Checkpoint({
    required this.tenantId,
    required this.siteId,
    required this.deviceId,
    required this.firestoreProjectId,
    required this.firestoreDatabaseId,
    required this.lastSampleSlot,
    required this.currentHour,
    required this.dailyAccumulator,
    required this.pendingHourly,
    required this.pendingDaily,
  });

  final String tenantId;
  final String siteId;
  final String deviceId;
  final String firestoreProjectId;
  final String firestoreDatabaseId;
  final DateTime? lastSampleSlot;
  final _HourlyAccumulator? currentHour;
  final _DailyAccumulator? dailyAccumulator;
  final List<DeviceEnvironmentHourlyRecord> pendingHourly;
  final List<DeviceEnvironmentDailyRecord> pendingDaily;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': checkpointSchemaVersion,
    'tenantId': tenantId,
    'siteId': siteId,
    'deviceId': deviceId,
    'firestoreProjectId': firestoreProjectId,
    'firestoreDatabaseId': firestoreDatabaseId,
    'lastSampleSlot': lastSampleSlot?.toIso8601String(),
    'currentHour': currentHour?.toJson(),
    'dailyAccumulator': dailyAccumulator?.toJson(),
    'pendingHourlyPeriods': pendingHourly
        .map(
          (r) => {
            ..._hourlyRecordToJson(r),
            'firestoreProjectId': firestoreProjectId,
            'firestoreDatabaseId': firestoreDatabaseId,
          },
        )
        .toList(),
    'pendingDailyPeriods': pendingDaily
        .map(
          (r) => {
            ..._dailyRecordToJson(r),
            'firestoreProjectId': firestoreProjectId,
            'firestoreDatabaseId': firestoreDatabaseId,
          },
        )
        .toList(),
  };

  static _Checkpoint fromJson(Map<String, dynamic> json) {
    _validateCheckpoint(json);
    final Map<String, dynamic>? currentHourJson =
        json['currentHour'] as Map<String, dynamic>?;
    final Map<String, dynamic>? dailyJson =
        json['dailyAccumulator'] as Map<String, dynamic>?;
    final List<dynamic> pendingHourlyRaw =
        json['pendingHourlyPeriods'] as List<dynamic>? ?? <dynamic>[];
    final List<dynamic> pendingDailyRaw =
        json['pendingDailyPeriods'] as List<dynamic>? ?? <dynamic>[];
    return _Checkpoint(
      tenantId: json['tenantId'] as String,
      siteId: json['siteId'] as String,
      deviceId: json['deviceId'] as String,
      firestoreProjectId: json['firestoreProjectId'] as String,
      firestoreDatabaseId: json['firestoreDatabaseId'] as String,
      lastSampleSlot: json['lastSampleSlot'] != null
          ? DateTime.parse(json['lastSampleSlot'] as String)
          : null,
      currentHour: currentHourJson != null
          ? _HourlyAccumulator.fromJson(currentHourJson)
          : null,
      dailyAccumulator: dailyJson != null
          ? _DailyAccumulator.fromJson(dailyJson)
          : null,
      pendingHourly: pendingHourlyRaw
          .map((Object? e) => _hourlyRecordFromJson(e as Map<String, dynamic>))
          .toList(),
      pendingDaily: pendingDailyRaw
          .map((Object? e) => _dailyRecordFromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

Map<String, Object?> _statsToJson(DeviceEnvironmentStats stats) =>
    <String, Object?>{
      'avg': stats.avg,
      'min': stats.min,
      'max': stats.max,
      'sampleCount': stats.sampleCount,
    };

DeviceEnvironmentStats _statsFromJson(Map<String, dynamic> json) {
  final int sampleCount = json['sampleCount'] as int;
  if (sampleCount == 0) {
    return DeviceEnvironmentStats.empty;
  }
  return DeviceEnvironmentStats(
    avg: (json['avg'] as num?)?.toDouble(),
    min: (json['min'] as num?)?.toDouble(),
    max: (json['max'] as num?)?.toDouble(),
    sampleCount: sampleCount,
  );
}

Map<String, Object?> _hourlyRecordToJson(DeviceEnvironmentHourlyRecord r) =>
    <String, Object?>{
      'periodId': r.periodId,
      'tenantId': r.tenantId,
      'siteId': r.siteId,
      'deviceId': r.deviceId,
      'periodStart': r.periodStartUtc.toIso8601String(),
      'periodEnd': r.periodEndUtc.toIso8601String(),
      'schemaVersion': r.schemaVersion,
      'createdAt': r.createdAtUtc.toIso8601String(),
      'temperature': _statsToJson(r.temperature),
      'humidity': _statsToJson(r.humidity),
    };

DeviceEnvironmentHourlyRecord _hourlyRecordFromJson(Map<String, dynamic> json) {
  return DeviceEnvironmentHourlyRecord(
    periodId: json['periodId'] as String,
    tenantId: json['tenantId'] as String,
    siteId: json['siteId'] as String,
    deviceId: json['deviceId'] as String,
    periodStartUtc: DateTime.parse(json['periodStart'] as String),
    periodEndUtc: DateTime.parse(json['periodEnd'] as String),
    schemaVersion: json['schemaVersion'] as int,
    createdAtUtc: DateTime.parse(json['createdAt'] as String),
    temperature: _statsFromJson(json['temperature'] as Map<String, dynamic>),
    humidity: _statsFromJson(json['humidity'] as Map<String, dynamic>),
  );
}

Map<String, Object?> _dailyRecordToJson(DeviceEnvironmentDailyRecord r) =>
    <String, Object?>{
      'periodId': r.periodId,
      'tenantId': r.tenantId,
      'siteId': r.siteId,
      'deviceId': r.deviceId,
      'periodStart': r.periodStartUtc.toIso8601String(),
      'periodEnd': r.periodEndUtc.toIso8601String(),
      'schemaVersion': r.schemaVersion,
      'createdAt': r.createdAtUtc.toIso8601String(),
      'temperature': _statsToJson(r.temperature),
      'humidity': _statsToJson(r.humidity),
    };

DeviceEnvironmentDailyRecord _dailyRecordFromJson(Map<String, dynamic> json) {
  return DeviceEnvironmentDailyRecord(
    periodId: json['periodId'] as String,
    tenantId: json['tenantId'] as String,
    siteId: json['siteId'] as String,
    deviceId: json['deviceId'] as String,
    periodStartUtc: DateTime.parse(json['periodStart'] as String),
    periodEndUtc: DateTime.parse(json['periodEnd'] as String),
    schemaVersion: json['schemaVersion'] as int,
    createdAtUtc: DateTime.parse(json['createdAt'] as String),
    temperature: _statsFromJson(json['temperature'] as Map<String, dynamic>),
    humidity: _statsFromJson(json['humidity'] as Map<String, dynamic>),
  );
}

/// Strict local-state boundary. Missing fields never mean an empty pending
/// queue; an incompatible checkpoint is preserved and rejected as a whole.
void _validateCheckpoint(Map<String, dynamic> j) {
  void require(bool ok, String field) {
    if (!ok) throw FormatException('Invalid checkpoint: $field');
  }

  void fields(Map m, List<String> keys) {
    for (final k in keys) {
      require(m.containsKey(k), k);
    }
  }

  fields(j, [
    'schemaVersion',
    'tenantId',
    'siteId',
    'deviceId',
    'firestoreProjectId',
    'firestoreDatabaseId',
    'currentHour',
    'dailyAccumulator',
    'lastSampleSlot',
    'pendingHourlyPeriods',
    'pendingDailyPeriods',
  ]);
  require(
    j['schemaVersion'] is int && j['schemaVersion'] == checkpointSchemaVersion,
    'schemaVersion (supported=$checkpointSchemaVersion)',
  );
  final identities = [
    'tenantId',
    'siteId',
    'deviceId',
    'firestoreProjectId',
    'firestoreDatabaseId',
  ];
  for (final k in identities) {
    require(j[k] is String && (j[k] as String).trim().isNotEmpty, k);
  }
  DateTime stamp(Object? raw) {
    require(raw is String, 'timestamp type');
    final value = DateTime.tryParse(raw as String);
    require(value != null && value.isUtc, 'timestamp UTC');
    return value!;
  }

  bool number(Object? n) => n is num && n.isFinite;
  void stats(Map m) {
    fields(m, ['avg', 'min', 'max', 'sampleCount']);
    final n = m['sampleCount'];
    require(n is int && n >= 0, 'sampleCount');
    if (n == 0) {
      require(
        m['avg'] == null && m['min'] == null && m['max'] == null,
        'empty stats',
      );
    } else {
      require(
        number(m['avg']) && number(m['min']) && number(m['max']),
        'stats finite',
      );
      require(m['min'] <= m['avg'] && m['avg'] <= m['max'], 'stats bounds');
    }
  }

  void accumulator(Map m) {
    for (final prefix in ['temp', 'hum']) {
      fields(m, [
        '${prefix}Sum',
        '${prefix}Count',
        '${prefix}Min',
        '${prefix}Max',
      ]);
      final n = m['${prefix}Count'];
      final sum = m['${prefix}Sum'];
      require(n is int && n >= 0 && number(sum), 'accumulator count/sum');
      if (n == 0) {
        require(
          sum == 0 && m['${prefix}Min'] == null && m['${prefix}Max'] == null,
          'empty accumulator',
        );
      } else {
        final min = m['${prefix}Min'], max = m['${prefix}Max'];
        require(number(min) && number(max) && min <= max, 'accumulator bounds');
        require(
          sum >= min * n - 0.000001 && sum <= max * n + 0.000001,
          'accumulator sum',
        );
      }
    }
  }

  String date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String hourId(DateTime d) =>
      '${date(d)}T${d.hour.toString().padLeft(2, '0')}';
  if (j['lastSampleSlot'] != null) {
    final slot = stamp(j['lastSampleSlot']);
    require(
      slot.minute % 20 == 0 && slot.second == 0 && slot.millisecond == 0,
      'lastSampleSlot',
    );
  }
  if (j['currentHour'] != null) {
    require(j['currentHour'] is Map, 'currentHour');
    final m = j['currentHour'] as Map;
    accumulator(m);
    final h = stamp(m['hourStart']);
    require(
      h.minute == 0 && h.second == 0 && h.millisecond == 0,
      'hour boundary',
    );
  }
  if (j['dailyAccumulator'] != null) {
    require(j['dailyAccumulator'] is Map, 'dailyAccumulator');
    final m = j['dailyAccumulator'] as Map;
    accumulator(m);
    require(m['dateKey'] is String, 'dateKey');
    final d = DateTime.tryParse('${m['dateKey']}T00:00:00Z');
    require(d != null && date(d) == m['dateKey'], 'dateKey');
    require(m['hoursIncluded'] is List, 'hoursIncluded');
    final hours = m['hoursIncluded'] as List;
    require(
      hours.toSet().length == hours.length && hours.length <= 24,
      'unique hoursIncluded',
    );
    for (final h in hours) {
      require(
        h is String && RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}$').hasMatch(h),
        'hour ID',
      );
      final hd = DateTime.tryParse('${h}:00:00Z');
      require(
        hd != null && hourId(hd) == h && date(hd) == m['dateKey'],
        'included hour date',
      );
    }
  }
  for (final kind in ['Hourly', 'Daily']) {
    final key = 'pending${kind}Periods';
    require(j[key] is List, key);
    final ids = <String>{};
    for (final raw in j[key] as List) {
      require(raw is Map, 'pending record');
      final m = raw as Map;
      fields(m, [
        ...identities,
        'schemaVersion',
        'periodId',
        'periodStart',
        'periodEnd',
        'createdAt',
        'temperature',
        'humidity',
      ]);
      for (final k in identities) {
        require(m[k] == j[k], 'pending $k identity');
      }
      require(
        m['schemaVersion'] is int && m['schemaVersion'] == schemaVersion,
        'pending schema',
      );
      final start = stamp(m['periodStart']), end = stamp(m['periodEnd']);
      stamp(m['createdAt']);
      final art = start.subtract(const Duration(hours: 3));
      final expected = kind == 'Hourly' ? hourId(art) : date(art);
      require(
        m['periodId'] == expected && ids.add(expected),
        'pending period ID',
      );
      require(
        start.minute == 0 && start.second == 0 && start.millisecond == 0,
        'period boundary',
      );
      require(
        end.difference(start) == Duration(hours: kind == 'Hourly' ? 1 : 24),
        'period duration',
      );
      if (kind == 'Daily') require(art.hour == 0, 'daily boundary');
      require(m['temperature'] is Map && m['humidity'] is Map, 'pending stats');
      stats(m['temperature'] as Map);
      stats(m['humidity'] as Map);
      if (kind == 'Daily' && j['dailyAccumulator'] is Map) {
        require(
          (j['dailyAccumulator'] as Map)['dateKey'] != expected,
          'active/pending daily overlap',
        );
      }
    }
  }
}
