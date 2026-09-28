import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/agro_device.dart';
import '../models/agro_device_room.dart';
import 'agro_device_room_service.dart';
import 'agro_device_service.dart';
import 'temperature_history_repository.dart';

enum EnvironmentHistoryMode { hourly, daily }

/// `both` is presentation-only: the widget draws two series from the same
/// already-fetched points, never a third repository call.
enum EnvironmentHistoryMetric { temperature, humidity, both }

/// Diagnostic-only marker; the widget never branches on this.
enum EnvironmentHistorySource { legacy, modern }

class EnvironmentHistoryScope {
  const EnvironmentHistoryScope(this.tenantId, this.siteId, this.deviceId);
  final String tenantId, siteId, deviceId;
  String get key => '$tenantId/$siteId/$deviceId';
}

/// Human-readable labels for the card's header. [deviceName] is always
/// present (falls back to the raw id if the Device doc has no `name`);
/// [roomName] is only set when a distinct Room document actually matches
/// this scope's unit — most Devices today (e.g. each Gene Pig Sala) expose
/// no Room subcollection at all and are their own implicit Room, in which
/// case the caller should just show [deviceName] once, not repeat it.
class DeviceDisplayNames {
  const DeviceDisplayNames(this.deviceName, this.roomName);
  final String deviceName;
  final String? roomName;
}

/// One ART calendar day (paginación por día — solo Horario, ver class docs
/// de [DeviceEnvironmentHistoryRepository.fetchDay]).
class EnvironmentHistoryDay {
  const EnvironmentHistoryDay(this.year, this.month, this.day);
  final int year;
  final int month;
  final int day;

  EnvironmentHistoryDay get previous {
    final d = DateTime.utc(year, month, day).subtract(const Duration(days: 1));
    return EnvironmentHistoryDay(d.year, d.month, d.day);
  }

  @override
  bool operator ==(Object other) =>
      other is EnvironmentHistoryDay &&
      other.year == year &&
      other.month == month &&
      other.day == day;
  @override
  int get hashCode => Object.hash(year, month, day);
  @override
  String toString() =>
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}

/// One ART calendar month (Etapa 2/2 paginación por mes — solo Diario, ver
/// class docs de [DeviceEnvironmentHistoryRepository.fetchMonth]).
class EnvironmentHistoryMonth {
  const EnvironmentHistoryMonth(this.year, this.month);
  final int year;
  final int month;

  EnvironmentHistoryMonth get previous =>
      month == 1 ? EnvironmentHistoryMonth(year - 1, 12) : EnvironmentHistoryMonth(year, month - 1);

  @override
  bool operator ==(Object other) =>
      other is EnvironmentHistoryMonth && other.year == year && other.month == month;
  @override
  int get hashCode => Object.hash(year, month);
  @override
  String toString() => '$year-${month.toString().padLeft(2, '0')}';
}

class EnvironmentHistoryStats {
  const EnvironmentHistoryStats(this.avg, this.min, this.max, this.sampleCount);
  factory EnvironmentHistoryStats.parse(dynamic raw) {
    final m = raw is Map ? raw : const {};
    double? number(String k) =>
        m[k] is num && (m[k] as num).isFinite ? (m[k] as num).toDouble() : null;
    return EnvironmentHistoryStats(
      number('avg'),
      number('min'),
      number('max'),
      m['sampleCount'] is num ? (m['sampleCount'] as num).toInt() : 0,
    );
  }
  final double? avg, min, max;
  final int sampleCount;
  double? get value => sampleCount > 0 ? avg : null;
}

class EnvironmentHistoryPoint {
  const EnvironmentHistoryPoint(
    this.start,
    this.temperature,
    this.humidity, {
    this.temperatureSource = EnvironmentHistorySource.modern,
  });
  final DateTime start;
  final EnvironmentHistoryStats temperature, humidity;
  // Diagnostic only (see EnvironmentHistorySource); the widget ignores this.
  final EnvironmentHistorySource temperatureSource;
  /// Only for [EnvironmentHistoryMetric.temperature]/[.humidity] — `both`
  /// draws temperature and humidity together and has no single series, so
  /// callers must read [temperature]/[humidity] directly for that mode.
  EnvironmentHistoryStats stats(EnvironmentHistoryMetric metric) {
    assert(metric != EnvironmentHistoryMetric.both);
    return metric == EnvironmentHistoryMetric.temperature
        ? temperature
        : humidity;
  }
}

/// Page-session cache, including in-flight requests. No listeners or polling.
class DeviceEnvironmentHistoryRepository {
  DeviceEnvironmentHistoryRepository({
    FirebaseFirestore? firestore,
    AgroDeviceService devices = const AgroDeviceService(),
    AgroDeviceRoomService rooms = const AgroDeviceRoomService(),
    TemperatureHistoryRepository? legacyTemperature,
  }) : _firestore = firestore,
       _devices = devices,
       _rooms = rooms,
       _legacyTemperature =
           legacyTemperature ?? TemperatureHistoryRepository(firestore: firestore);
  final FirebaseFirestore? _firestore;
  final AgroDeviceService _devices;
  final AgroDeviceRoomService _rooms;
  final TemperatureHistoryRepository _legacyTemperature;
  final _scopes = <String, Future<EnvironmentHistoryScope>>{};
  final _cache = <String, Future<List<EnvironmentHistoryPoint>>>{};
  final _displayNames = <String, Future<DeviceDisplayNames>>{};

  // These aliases exist in backend/config/sites/default.json. Legacy Device
  // documents predate snapshotUnitKey; never infer identity from display names.
  static const legacyGenePigAliases = {
    'munters1': 'plc-genetica-sala1',
    'munters2': 'plc-genetica-sala2',
  };

  // Reverse of legacyGenePigAliases: real deviceId -> legacy runtime alias.
  // Used only to read the OLD temperature path below; never widen to other
  // tenants (see resolveFromDevices' tenant gate).
  static final Map<String, String> _legacyGenePigAliasesByDevice = {
    for (final entry in legacyGenePigAliases.entries) entry.value: entry.key,
  };

  // The legacy temperature writer still uses this structural siteId for
  // Gene Pig (tenants/the-gene-pig/sites/genetica-1/plcs/{plcId}/metrics/
  // temperature/...), distinct from the real siteId (las-heras) the modern
  // history now uses. Bridging this is read-only compatibility, not a
  // Firestore migration — see Prompt_Unificar_Temperatura_Legacy_y_Moderna.
  static const _legacyGenePigTenant = 'the-gene-pig';
  static const _legacyGenePigSiteId = 'genetica-1';

  static EnvironmentHistoryScope resolveFromDevices(
    String tenant,
    String unit,
    List<AgroDevice> devices,
  ) {
    final id = tenant == 'the-gene-pig' ? legacyGenePigAliases[unit] : null;
    final matches = devices
        .where(
          (d) =>
              d.tenantId == tenant &&
              d.enabled &&
              (d.effectiveSnapshotUnitKey == unit || d.id == id),
        )
        .toList();
    if (matches.length != 1 || matches.single.siteId.isEmpty) {
      throw StateError('No unique Device for history');
    }
    final d = matches.single;
    return EnvironmentHistoryScope(tenant, d.siteId, d.id);
  }

  Future<EnvironmentHistoryScope> resolve(String tenant, String unit) async {
    final key = '$tenant/$unit';
    final future = _scopes.putIfAbsent(
      key,
      () async =>
          resolveFromDevices(tenant, unit, await _devices.listByTenant(tenant)),
    );
    try {
      return await future;
    } catch (_) {
      _scopes.remove(key);
      rethrow;
    }
  }

  Future<List<EnvironmentHistoryPoint>> fetch(
    EnvironmentHistoryScope scope,
    EnvironmentHistoryMode mode,
  ) async {
    final limit = mode == EnvironmentHistoryMode.hourly ? 24 : 30;
    final key = '${scope.key}/${mode.name}/latest-$limit';
    final future = _cache.putIfAbsent(key, () => load(scope, mode, limit));
    try {
      return await future;
    } catch (_) {
      _cache.remove(key);
      rethrow;
    }
  }

  /// Device/Room display names for the card's header (never technical ids
  /// when a real name is set). Cached per scope — same 0-extra-reads intent
  /// as [resolve]'s own scope cache.
  Future<DeviceDisplayNames> resolveDisplayNames(
    String tenantId,
    EnvironmentHistoryScope scope,
    String unitId,
  ) async {
    final future = _displayNames.putIfAbsent(
      scope.key,
      () => _loadDisplayNames(tenantId, scope, unitId),
    );
    try {
      return await future;
    } catch (_) {
      _displayNames.remove(scope.key);
      rethrow;
    }
  }

  Future<DeviceDisplayNames> _loadDisplayNames(
    String tenantId,
    EnvironmentHistoryScope scope,
    String unitId,
  ) async {
    final device = await _devices.getById(
      tenantId: tenantId,
      deviceId: scope.deviceId,
    );
    final deviceName = device != null && device.name.trim().isNotEmpty
        ? device.name
        : scope.deviceId;
    final rooms = await _rooms.listByDevice(
      tenantId: tenantId,
      deviceId: scope.deviceId,
    );
    AgroDeviceRoom? room;
    for (final r in rooms) {
      if (r.effectiveSnapshotUnitKey == unitId) {
        room = r;
        break;
      }
    }
    final roomName = room != null && room.name.trim().isNotEmpty
        ? room.name
        : null;
    return DeviceDisplayNames(
      deviceName,
      roomName != null && roomName != deviceName ? roomName : null,
    );
  }

  /// Orchestrates one cache miss: modern first, then only as much legacy
  /// temperature as needed to fill the window (see class docs). Override
  /// [loadModern] in tests to fake the modern Firestore read; inject a fake
  /// [TemperatureHistoryRepository] via the constructor for legacy.
  ///
  /// [beforeUtc], when set, bounds the window to periods strictly before
  /// that instant instead of "the latest [limit]" — used by
  /// [fetchHourlyPage] for Horario's backward pagination.
  Future<List<EnvironmentHistoryPoint>> load(
    EnvironmentHistoryScope scope,
    EnvironmentHistoryMode mode,
    int limit, {
    DateTime? beforeUtc,
  }) async {
    final modern = await loadModern(scope, mode, limit, beforeUtc: beforeUtc);
    // Humidity only ever comes from the modern source (see class docs), so
    // the legacy bridge below only ever contributes temperature points for
    // periods modern doesn't have yet — never a second, colliding humidity.
    if (scope.tenantId != _legacyGenePigTenant) return modern;
    final unit = _legacyGenePigAliasesByDevice[scope.deviceId];
    if (unit == null) return modern;
    final needed = limit - modern.length;
    if (needed <= 0) return modern;
    final DateTime? oldestModern = modern.isEmpty
        ? beforeUtc
        : modern.map((p) => p.start).reduce((a, b) => a.isBefore(b) ? a : b);
    final legacy = await _loadLegacyTemperature(
      unit,
      mode,
      needed,
      oldestModern,
    );
    // modern gana: insertar legacy primero, luego modern, así una colisión
    // de período (mismo instante en ambas fuentes) queda resuelta por modern.
    final merged = <DateTime, EnvironmentHistoryPoint>{};
    for (final p in legacy) {
      merged[p.start] = p;
    }
    for (final p in modern) {
      merged[p.start] = p;
    }
    final result = merged.values.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return result.length > limit
        ? result.sublist(result.length - limit)
        : result;
  }

  Future<List<EnvironmentHistoryPoint>> loadModern(
    EnvironmentHistoryScope scope,
    EnvironmentHistoryMode mode,
    int limit, {
    DateTime? beforeUtc,
  }) async {
    final collection = mode == EnvironmentHistoryMode.hourly
        ? 'historyHourly'
        : 'historyDaily';
    Query<Map<String, dynamic>> query = (_firestore ?? FirebaseFirestore.instance)
        .collection(
          'tenants/${scope.tenantId}/devices/${scope.deviceId}/$collection',
        )
        .orderBy('periodStart', descending: true);
    if (beforeUtc != null) {
      query = query.where(
        'periodStart',
        isLessThan: Timestamp.fromDate(beforeUtc),
      );
    }
    final result = await query.limit(limit).get();
    final points = <EnvironmentHistoryPoint>[];
    for (final doc in result.docs) {
      final d = doc.data();
      if (d['tenantId'] != scope.tenantId ||
          d['siteId'] != scope.siteId ||
          d['deviceId'] != scope.deviceId ||
          d['periodStart'] is! Timestamp) {
        continue;
      }
      points.add(
        EnvironmentHistoryPoint(
          (d['periodStart'] as Timestamp).toDate(),
          EnvironmentHistoryStats.parse(d['temperature']),
          EnvironmentHistoryStats.parse(d['humidity']),
        ),
      );
    }
    return points..sort((a, b) => a.start.compareTo(b.start));
  }

  /// Read-only compatibility bridge: fills the window with OLD temperature
  /// history (tenants/{tenant}/sites/genetica-1/plcs/{unit}/metrics/
  /// temperature/...) for periods the modern collection doesn't cover yet.
  /// Never touches Firestore, never moves/copies documents. Humidity is
  /// deliberately absent (empty stats) since it never existed in that path.
  Future<List<EnvironmentHistoryPoint>> _loadLegacyTemperature(
    String unit,
    EnvironmentHistoryMode mode,
    int needed,
    DateTime? before,
  ) async {
    const emptyHumidity = EnvironmentHistoryStats(null, null, null, 0);
    if (mode == EnvironmentHistoryMode.hourly) {
      final points = await _legacyTemperature.fetchTemperatureHourlyHistory(
        tenantId: _legacyGenePigTenant,
        siteId: _legacyGenePigSiteId,
        plcId: unit,
        limit: needed,
        before: before,
      );
      return [
        for (final p in points)
          EnvironmentHistoryPoint(
            p.timestampHourStart,
            EnvironmentHistoryStats(p.avgTemp, p.minTemp, p.maxTemp, p.samplesCount),
            emptyHumidity,
            temperatureSource: EnvironmentHistorySource.legacy,
          ),
      ];
    }
    final points = await _legacyTemperature.fetchTemperatureDailyHistory(
      tenantId: _legacyGenePigTenant,
      siteId: _legacyGenePigSiteId,
      plcId: unit,
      limit: needed,
      beforeDateKey: before == null ? null : _formatDateKey(before),
    );
    return [
      for (final p in points)
        EnvironmentHistoryPoint(
          p.timestampDayStart,
          EnvironmentHistoryStats(p.avgTemp, p.minTemp, p.maxTemp, p.hoursCount),
          emptyHumidity,
          temperatureSource: EnvironmentHistorySource.legacy,
        ),
    ];
  }

  // ---------------------------------------------------------------------
  // Paginación por día (solo Horario) y por mes (solo Diario). Por default
  // cada uno carga exactamente un período: el día ART en curso para
  // Horario, el mes ART en curso para Diario — nunca más que eso sin que el
  // usuario lo pida explícitamente ("Día anterior"/"Mes anterior"). Cada
  // período es una query genuinamente acotada (como mucho 24 horas o 31
  // días, nunca "toda la historia"), cacheada de forma independiente para
  // que moverse entre períodos ya pedidos cueste 0 reads.
  // ---------------------------------------------------------------------

  /// Fetches (or returns from cache) one ART calendar day of Horario,
  /// already merged legacy+modern with modern precedence. Concurrent/
  /// duplicate calls for the same scope+day share one in-flight Future.
  Future<List<EnvironmentHistoryPoint>> fetchDay(
    EnvironmentHistoryScope scope,
    EnvironmentHistoryDay day,
  ) async {
    final key = '${scope.key}/hourly-day/$day';
    final future = _cache.putIfAbsent(key, () => loadDay(scope, day));
    try {
      return await future;
    } catch (_) {
      _cache.remove(key);
      rethrow;
    }
  }

  /// Separate seam for instrumented tests, mirroring [loadMonth]. Reuses
  /// the existing cursor-based [loadModern]/[_loadLegacyTemperature] (same
  /// ones [load] already uses) with `beforeUtc` = the day's own end, then
  /// filters to just that day — a day has at most 24 hourly points, so the
  /// "top 24 before tomorrow" query is always guaranteed to include every
  /// point that actually belongs to it, from both sources independently.
  Future<List<EnvironmentHistoryPoint>> loadDay(
    EnvironmentHistoryScope scope,
    EnvironmentHistoryDay day,
  ) async {
    const hoursPerDay = 24;
    final fromUtc = _artDayStartUtc(day.year, day.month, day.day);
    final toUtc = fromUtc.add(const Duration(hours: hoursPerDay));
    bool withinDay(EnvironmentHistoryPoint p) =>
        !p.start.isBefore(fromUtc) && p.start.isBefore(toUtc);

    final modernAll = await loadModern(
      scope,
      EnvironmentHistoryMode.hourly,
      hoursPerDay,
      beforeUtc: toUtc,
    );
    final modern = modernAll.where(withinDay).toList();
    if (scope.tenantId != _legacyGenePigTenant || modern.length >= hoursPerDay) {
      return modern;
    }
    final unit = _legacyGenePigAliasesByDevice[scope.deviceId];
    if (unit == null) return modern;
    final legacyAll = await _loadLegacyTemperature(
      unit,
      EnvironmentHistoryMode.hourly,
      hoursPerDay,
      toUtc,
    );
    final merged = <DateTime, EnvironmentHistoryPoint>{};
    for (final p in legacyAll.where(withinDay)) {
      merged[p.start] = p;
    }
    for (final p in modern) {
      merged[p.start] = p; // modern gana ante solapamiento, igual que load().
    }
    return merged.values.toList()..sort((a, b) => a.start.compareTo(b.start));
  }

  /// Fetches (or returns from cache) one ART calendar month of Diario,
  /// already merged legacy+modern with modern precedence — the widget never
  /// has to know where a point came from. Concurrent/duplicate calls for the
  /// same scope+month share one in-flight Future (no duplicate query even
  /// on a rapid double-tap of "mes anterior").
  Future<List<EnvironmentHistoryPoint>> fetchMonth(
    EnvironmentHistoryScope scope,
    EnvironmentHistoryMonth month,
  ) async {
    final key = '${scope.key}/daily-month/$month';
    final future = _cache.putIfAbsent(key, () => loadMonth(scope, month));
    try {
      return await future;
    } catch (_) {
      _cache.remove(key);
      rethrow;
    }
  }

  /// Separate seam for instrumented tests, mirroring [load]/[loadModern].
  Future<List<EnvironmentHistoryPoint>> loadMonth(
    EnvironmentHistoryScope scope,
    EnvironmentHistoryMonth month,
  ) async {
    final fromUtc = _artMonthStartUtc(month.year, month.month);
    final toUtc = _artMonthStartUtc(month.year, month.month + 1);
    final modern = await loadModernRange(scope, fromUtc, toUtc);
    final expectedDays = _daysInMonth(month.year, month.month);
    if (scope.tenantId != _legacyGenePigTenant || modern.length >= expectedDays) {
      return modern;
    }
    final unit = _legacyGenePigAliasesByDevice[scope.deviceId];
    if (unit == null) return modern;
    final legacy = await _loadLegacyTemperatureMonth(unit, month);
    final merged = <DateTime, EnvironmentHistoryPoint>{};
    for (final p in legacy) {
      merged[p.start] = p;
    }
    for (final p in modern) {
      merged[p.start] = p; // modern gana ante solapamiento, igual que load().
    }
    return merged.values.toList()..sort((a, b) => a.start.compareTo(b.start));
  }

  /// Bounded two-sided range query — never "toda la historia disponible".
  /// At most ~31 documents for a calendar month.
  Future<List<EnvironmentHistoryPoint>> loadModernRange(
    EnvironmentHistoryScope scope,
    DateTime fromUtc,
    DateTime toUtcExclusive,
  ) async {
    final result = await (_firestore ?? FirebaseFirestore.instance)
        .collection(
          'tenants/${scope.tenantId}/devices/${scope.deviceId}/historyDaily',
        )
        .where('periodStart', isGreaterThanOrEqualTo: Timestamp.fromDate(fromUtc))
        .where('periodStart', isLessThan: Timestamp.fromDate(toUtcExclusive))
        .orderBy('periodStart')
        .get();
    final points = <EnvironmentHistoryPoint>[];
    for (final doc in result.docs) {
      final d = doc.data();
      if (d['tenantId'] != scope.tenantId ||
          d['siteId'] != scope.siteId ||
          d['deviceId'] != scope.deviceId ||
          d['periodStart'] is! Timestamp) {
        continue;
      }
      points.add(
        EnvironmentHistoryPoint(
          (d['periodStart'] as Timestamp).toDate(),
          EnvironmentHistoryStats.parse(d['temperature']),
          EnvironmentHistoryStats.parse(d['humidity']),
        ),
      );
    }
    return points..sort((a, b) => a.start.compareTo(b.start));
  }

  Future<List<EnvironmentHistoryPoint>> _loadLegacyTemperatureMonth(
    String unit,
    EnvironmentHistoryMonth month,
  ) async {
    const emptyHumidity = EnvironmentHistoryStats(null, null, null, 0);
    final fromKey = _artDateKey(month.year, month.month, 1);
    final next = EnvironmentHistoryMonth(month.year, month.month + 1);
    final toKeyExclusive = _artDateKey(next.year, next.month, 1);
    final points = await _legacyTemperature.fetchTemperatureDailyHistory(
      tenantId: _legacyGenePigTenant,
      siteId: _legacyGenePigSiteId,
      plcId: unit,
      limit: 31,
      fromDateKeyInclusive: fromKey,
      beforeDateKey: toKeyExclusive,
    );
    return [
      for (final p in points)
        EnvironmentHistoryPoint(
          p.timestampDayStart,
          EnvironmentHistoryStats(p.avgTemp, p.minTemp, p.maxTemp, p.hoursCount),
          emptyHumidity,
          temperatureSource: EnvironmentHistorySource.legacy,
        ),
    ];
  }
}

/// ART midnight of day 1 of [month] (1-12, may be passed as 0 or 13 to mean
/// the previous/next month — [DateTime] normalizes that for us), expressed
/// as the equivalent UTC instant (ART = UTC-3, so ART 00:00 = UTC 03:00).
DateTime _artMonthStartUtc(int year, int month) => DateTime.utc(year, month, 1, 3);

/// ART midnight of [year]/[month]/[day], expressed as the equivalent UTC
/// instant — same convention as [_artMonthStartUtc], one calendar day
/// instead of one calendar month.
DateTime _artDayStartUtc(int year, int month, int day) => DateTime.utc(year, month, day, 3);

int _daysInMonth(int year, int month) =>
    DateTime.utc(year, month + 1, 1).difference(DateTime.utc(year, month, 1)).inDays;

String _artDateKey(int year, int month, int day) {
  final normalized = DateTime.utc(year, month, day);
  return '${normalized.year.toString().padLeft(4, '0')}-'
      '${normalized.month.toString().padLeft(2, '0')}-'
      '${normalized.day.toString().padLeft(2, '0')}';
}

String _formatDateKey(DateTime value) {
  final art = value.toUtc().subtract(const Duration(hours: 3));
  return '${art.year.toString().padLeft(4, '0')}-'
      '${art.month.toString().padLeft(2, '0')}-'
      '${art.day.toString().padLeft(2, '0')}';
}
