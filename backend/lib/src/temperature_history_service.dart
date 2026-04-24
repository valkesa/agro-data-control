import 'dart:async';
import 'dart:io';

import 'package:agro_data_control_backend/src/firestore_temperature_history_repository.dart';
import 'package:agro_data_control_backend/src/plc_installation_config.dart';

class TemperatureHistoryService {
  TemperatureHistoryService({
    required this.config,
    required FirestoreTemperatureHistoryRepository repository,
  }) : _repository = repository {
    if (!config.enabled) {
      _log('disabled by config');
    } else if (!_repository.isConfigured) {
      _log('disabled: ${_repository.missingConfigurationReason}');
    } else {
      _log(
        'enabled source=${config.sourcePath} '
        'path=tenants/${config.tenantId}/sites/${config.siteId}/plcs/${config.plcId}/metrics/temperature',
      );
    }
  }

  final TemperatureHistoryConfig config;
  final FirestoreTemperatureHistoryRepository _repository;

  Future<void> _queue = Future<void>.value();
  _HourlyAccumulator? _currentHour;
  DateTime? _lastSampleSlot;

  bool get isEnabled => config.enabled && _repository.isConfigured;

  void handleSnapshot({
    required Map<String, Object?> unitsJson,
    required DateTime observedAtUtc,
  }) {
    if (!isEnabled) {
      return;
    }

    _queue = _queue
        .then<void>(
          (_) => _handleSnapshotInternal(
            unitsJson: unitsJson,
            observedAtUtc: observedAtUtc,
          ),
        )
        .catchError((Object error, StackTrace stackTrace) {
          _log('error processing snapshot error=$error');
          _log('error processing snapshot stack=$stackTrace');
        });
  }

  Future<void> dispose() => _queue;

  Future<void> _handleSnapshotInternal({
    required Map<String, Object?> unitsJson,
    required DateTime observedAtUtc,
  }) async {
    final DateTime observedAtLocal = observedAtUtc.toLocal();
    final DateTime currentHourStart = _hourStartLocal(observedAtLocal);

    if (_currentHour != null &&
        !_isSameHour(_currentHour!.hourStartLocal, currentHourStart)) {
      await _finalizeCurrentHour();
    }

    _currentHour ??= _HourlyAccumulator(hourStartLocal: currentHourStart);

    final DateTime? sampleSlot = _resolveSampleSlotLocal(observedAtLocal);
    if (sampleSlot == null) {
      return;
    }
    if (_lastSampleSlot != null &&
        _lastSampleSlot!.millisecondsSinceEpoch ==
            sampleSlot.millisecondsSinceEpoch) {
      return;
    }
    _lastSampleSlot = sampleSlot;

    final double? temperature = extractIndoorTemperature(unitsJson);
    if (temperature == null) {
      _log(
        'sample discarded source=${config.sourcePath} '
        'slot=${sampleSlot.toIso8601String()} reason=invalid_tempInterior',
      );
      return;
    }

    final double? exterior = extractExteriorTemperature(unitsJson);
    _currentHour!.addSample(temperature, exterior);
    _log(
      'sample taken source=${config.sourcePath} '
      'slot=${sampleSlot.toIso8601String()} tempInterior=${temperature.toStringAsFixed(2)} '
      '${exterior != null ? "tempExterior=${exterior.toStringAsFixed(2)} " : ""}'
      'samplesInHour=${_currentHour!.count}',
    );
  }

  Future<void> _finalizeCurrentHour() async {
    final _HourlyAccumulator accumulator = _currentHour!;
    _currentHour = null;

    if (accumulator.count == 0) {
      _log(
        'hour closed hour=${accumulator.hourStartLocal.toIso8601String()} samples=0 skipped',
      );
      return;
    }

    final TemperatureHourlyRecord hourlyRecord = TemperatureHourlyRecord(
      timestampHourStartUtc: accumulator.hourStartLocal.toUtc(),
      dateKey: _formatDateKey(accumulator.hourStartLocal),
      hourKey: _formatHourKey(accumulator.hourStartLocal),
      hour: accumulator.hourStartLocal.hour,
      avgTemp: accumulator.average,
      minTemp: accumulator.minTemp!,
      maxTemp: accumulator.maxTemp!,
      samplesCount: accumulator.count,
      avgExteriorTemp: accumulator.exteriorCount > 0
          ? accumulator.exteriorAverage
          : null,
      minExteriorTemp: accumulator.minExteriorTemp,
      maxExteriorTemp: accumulator.maxExteriorTemp,
    );

    _log(
      'hour closed hour=${hourlyRecord.hourKey} '
      'avg=${hourlyRecord.avgTemp.toStringAsFixed(2)} '
      'min=${hourlyRecord.minTemp.toStringAsFixed(2)} '
      'max=${hourlyRecord.maxTemp.toStringAsFixed(2)} '
      'samples=${hourlyRecord.samplesCount}',
    );

    try {
      await _repository.saveHourly(hourlyRecord);
      _log('hourly saved hour=${hourlyRecord.hourKey}');
    } on Object catch (error) {
      _log(
        'firestore error saving hourly hour=${hourlyRecord.hourKey} error=$error',
      );
      return;
    }

    try {
      final List<TemperatureHourlyRecord> dayRecords = await _repository
          .loadHourlyForDate(hourlyRecord.dateKey);
      final TemperatureDailyRecord? dailyRecord = _buildDailyRecord(
        hourlyRecord.dateKey,
        dayRecords,
      );
      if (dailyRecord == null) {
        _log(
          'daily skipped date=${hourlyRecord.dateKey} reason=no_hourly_records',
        );
        return;
      }
      await _repository.saveDaily(dailyRecord);
      _log(
        'daily recalculated date=${dailyRecord.dateKey} '
        'avg=${dailyRecord.avgTemp.toStringAsFixed(2)} '
        'min=${dailyRecord.minTemp.toStringAsFixed(2)} '
        'max=${dailyRecord.maxTemp.toStringAsFixed(2)} '
        'hours=${dailyRecord.hoursCount}',
      );
    } on Object catch (error) {
      _log(
        'firestore error recalculating daily date=${hourlyRecord.dateKey} error=$error',
      );
    }
  }

  TemperatureDailyRecord? _buildDailyRecord(
    String dateKey,
    List<TemperatureHourlyRecord> hourlyRecords,
  ) {
    if (hourlyRecords.isEmpty) {
      return null;
    }

    double weightedSum = 0;
    int totalSamples = 0;
    double minTemp = hourlyRecords.first.minTemp;
    double maxTemp = hourlyRecords.first.maxTemp;

    for (final TemperatureHourlyRecord record in hourlyRecords) {
      weightedSum += record.avgTemp * record.samplesCount;
      totalSamples += record.samplesCount;
      if (record.minTemp < minTemp) {
        minTemp = record.minTemp;
      }
      if (record.maxTemp > maxTemp) {
        maxTemp = record.maxTemp;
      }
    }

    if (totalSamples == 0) {
      return null;
    }

    // Aggregate exterior temperatures from hours that have exterior data.
    final List<TemperatureHourlyRecord> withExterior = hourlyRecords
        .where((TemperatureHourlyRecord r) => r.avgExteriorTemp != null)
        .toList();

    double? avgExteriorTemp;
    double? minExteriorTemp;
    double? maxExteriorTemp;

    if (withExterior.isNotEmpty) {
      double extWeightedSum = 0;
      int extTotalSamples = 0;
      double extMin = withExterior.first.minExteriorTemp!;
      double extMax = withExterior.first.maxExteriorTemp!;
      for (final TemperatureHourlyRecord record in withExterior) {
        extWeightedSum += record.avgExteriorTemp! * record.samplesCount;
        extTotalSamples += record.samplesCount;
        if (record.minExteriorTemp! < extMin) {
          extMin = record.minExteriorTemp!;
        }
        if (record.maxExteriorTemp! > extMax) {
          extMax = record.maxExteriorTemp!;
        }
      }
      avgExteriorTemp = extWeightedSum / extTotalSamples;
      minExteriorTemp = extMin;
      maxExteriorTemp = extMax;
    }

    return TemperatureDailyRecord(
      timestampDayStartUtc: DateTime(
        hourlyRecords.first.timestampHourStartUtc.toLocal().year,
        hourlyRecords.first.timestampHourStartUtc.toLocal().month,
        hourlyRecords.first.timestampHourStartUtc.toLocal().day,
      ).toUtc(),
      dateKey: dateKey,
      avgTemp: weightedSum / totalSamples,
      minTemp: minTemp,
      maxTemp: maxTemp,
      hoursCount: hourlyRecords.length,
      avgExteriorTemp: avgExteriorTemp,
      minExteriorTemp: minExteriorTemp,
      maxExteriorTemp: maxExteriorTemp,
    );
  }

  double? extractIndoorTemperature(Map<String, Object?> unitsJson) {
    final _MetricSourcePath source = _MetricSourcePath.parse(config.sourcePath);
    final Map<String, Object?>? unit = _asObjectMap(unitsJson[source.unitKey]);
    if (unit == null) {
      return null;
    }

    final Object? raw = unit[source.signalKey];
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

  double? extractExteriorTemperature(Map<String, Object?> unitsJson) {
    final _MetricSourcePath source = _MetricSourcePath.parse(config.sourcePath);
    final Map<String, Object?>? unit = _asObjectMap(unitsJson[source.unitKey]);
    if (unit == null) {
      return null;
    }

    final Object? raw = unit['tempExterior'];
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

  DateTime? _resolveSampleSlotLocal(DateTime observedAtLocal) {
    final int minute = observedAtLocal.minute;
    if (minute % 20 != 0) {
      return null;
    }
    return DateTime(
      observedAtLocal.year,
      observedAtLocal.month,
      observedAtLocal.day,
      observedAtLocal.hour,
      minute,
    );
  }
}

class _HourlyAccumulator {
  _HourlyAccumulator({required this.hourStartLocal});

  final DateTime hourStartLocal;
  double sumTemp = 0;
  int count = 0;
  double? minTemp;
  double? maxTemp;

  double sumExteriorTemp = 0;
  int exteriorCount = 0;
  double? minExteriorTemp;
  double? maxExteriorTemp;

  void addSample(double interior, double? exterior) {
    sumTemp += interior;
    count += 1;
    minTemp = minTemp == null || interior < minTemp! ? interior : minTemp;
    maxTemp = maxTemp == null || interior > maxTemp! ? interior : maxTemp;

    if (exterior != null) {
      sumExteriorTemp += exterior;
      exteriorCount += 1;
      minExteriorTemp = minExteriorTemp == null || exterior < minExteriorTemp!
          ? exterior
          : minExteriorTemp;
      maxExteriorTemp = maxExteriorTemp == null || exterior > maxExteriorTemp!
          ? exterior
          : maxExteriorTemp;
    }
  }

  double get average => sumTemp / count;
  double get exteriorAverage => sumExteriorTemp / exteriorCount;
}

Map<String, Object?>? _asObjectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (Object? key, Object? entryValue) => MapEntry(key.toString(), entryValue),
    );
  }
  return null;
}

DateTime _hourStartLocal(DateTime value) {
  return DateTime(value.year, value.month, value.day, value.hour);
}

bool _isSameHour(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day &&
      left.hour == right.hour;
}

String _formatDateKey(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

String _formatHourKey(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}_'
      '${value.hour.toString().padLeft(2, '0')}';
}

void _log(String message) {
  stdout.writeln('[temperature-history] $message');
}

class _MetricSourcePath {
  const _MetricSourcePath({required this.unitKey, required this.signalKey});

  factory _MetricSourcePath.parse(String raw) {
    final List<String> parts = raw.split('.');
    if (parts.length >= 2) {
      return _MetricSourcePath(
        unitKey: parts.first.trim(),
        signalKey: parts.sublist(1).join('.').trim(),
      );
    }
    return const _MetricSourcePath(
      unitKey: 'munters2',
      signalKey: 'tempInterior',
    );
  }

  final String unitKey;
  final String signalKey;
}
