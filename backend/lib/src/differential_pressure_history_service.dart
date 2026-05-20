import 'dart:async';
import 'dart:io';

import 'package:agro_data_control_backend/src/firestore_differential_pressure_history_repository.dart';
import 'package:agro_data_control_backend/src/plc_installation_config.dart';

class DifferentialPressureHistoryService {
  DifferentialPressureHistoryService({
    required this.config,
    required FirestoreDifferentialPressureHistoryRepository repository,
  }) : _repository = repository {
    if (!config.enabled) {
      _log('disabled by config');
    } else if (!_repository.isConfigured) {
      _log('disabled: ${_repository.missingConfigurationReason}');
    } else {
      _log(
        'enabled source=${config.sourcePath} '
        'path=tenants/${config.tenantId}/sites/${config.siteId}/plcs/${config.plcId}/metrics/differentialPressure',
      );
    }
  }

  final DifferentialPressureHistoryConfig config;
  final FirestoreDifferentialPressureHistoryRepository _repository;

  Future<void> _queue = Future<void>.value();
  final Set<String> _sampledWindowKeys = <String>{};

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
    final DateTime windowStart = _sampleWindowStartLocal(observedAtLocal);
    final String dateKey = _formatDateKey(windowStart);
    final String sampleWindowKey = _formatSampleWindowKey(windowStart);
    if (_sampledWindowKeys.contains(sampleWindowKey)) {
      return;
    }

    final double? pressure = extractPressureDifferential(unitsJson);
    if (pressure == null) {
      _log(
        'sample discarded source=${config.sourcePath} '
        'window=$sampleWindowKey reason=invalid_pressureDifferential',
      );
      return;
    }

    DifferentialPressureDailyRecord? existing;
    try {
      existing = await _repository.loadDaily(dateKey);
    } on Object catch (error) {
      _log('firestore error loading daily date=$dateKey error=$error');
      return;
    }

    if (existing?.sampleWindowKeys.contains(sampleWindowKey) == true) {
      _sampledWindowKeys.add(sampleWindowKey);
      _log(
        'sample skipped source=${config.sourcePath} window=$sampleWindowKey reason=duplicate_window',
      );
      return;
    }

    final DifferentialPressureDailyRecord record = existing == null
        ? DifferentialPressureDailyRecord.firstSample(
            timestampDayStartUtc: DateTime(
              windowStart.year,
              windowStart.month,
              windowStart.day,
            ).toUtc(),
            dateKey: dateKey,
            sampleWindowKey: sampleWindowKey,
            pressure: pressure,
          )
        : existing.addSample(
            sampleWindowKey: sampleWindowKey,
            pressure: pressure,
          );

    try {
      await _repository.saveDaily(record);
      _sampledWindowKeys.add(sampleWindowKey);
      _log(
        'sample saved source=${config.sourcePath} window=$sampleWindowKey '
        'pressure=${pressure.toStringAsFixed(2)} samples=${record.samplesCount}',
      );
    } on Object catch (error) {
      _log('firestore error saving daily date=$dateKey error=$error');
    }
  }

  double? extractPressureDifferential(Map<String, Object?> unitsJson) {
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

DateTime _sampleWindowStartLocal(DateTime value) {
  final int hour = value.hour - (value.hour % 4);
  return DateTime(value.year, value.month, value.day, hour);
}

String _formatDateKey(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

String _formatSampleWindowKey(DateTime value) {
  return '${_formatDateKey(value)}_${value.hour.toString().padLeft(2, '0')}';
}

void _log(String message) {
  stdout.writeln('[differential-pressure-history] $message');
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
      signalKey: 'presionDiferencial',
    );
  }

  final String unitKey;
  final String signalKey;
}
