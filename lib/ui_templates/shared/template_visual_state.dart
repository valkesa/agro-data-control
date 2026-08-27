import 'package:flutter/material.dart';

import '../../models/dashboard_range_settings.dart';
import '../../models/munters_model.dart';
import '../../models/room_wash_event.dart';
import '../enums/metric_display_type.dart';
import '../models/metric_definition.dart';
import '../models/template_data_context.dart';
import '../transforms/environment_calculations.dart';
import '../board/template_data_resolver.dart';
import '../board/template_value_formatter.dart';

/// Semantic alarm level for a resolved metric value. Shared by TABLERO
/// (`DeviceBoardRenderer`) and TABLA (`DeviceTableRenderer`) so the same
/// data always gets the same visual meaning in both views.
enum TemplateAlarmLevel { unavailable, normal, warning, alarm, sensorFailure }

TemplateAlarmLevel resolveTemplateAlarmLevel({
  required MetricDefinition metric,
  required Object? value,
  required Object? deviceData,
  required DashboardRangeSettings rangeSettings,
}) {
  if (metric.displayType == MetricDisplayType.boolean && value is bool) {
    return value == true ? TemplateAlarmLevel.alarm : TemplateAlarmLevel.normal;
  }
  final double? number = value is num ? value.toDouble() : null;
  if (number == null) {
    return TemplateAlarmLevel.unavailable;
  }
  return switch (metric.key) {
    'tempInterior' =>
      number < rangeSettings.temperatureSensorFailureMin
          ? TemplateAlarmLevel.sensorFailure
          : number < rangeSettings.temperatureMin ||
                number > rangeSettings.temperatureMax
          ? TemplateAlarmLevel.alarm
          : TemplateAlarmLevel.normal,
    'humedadInterior' =>
      number > rangeSettings.humidityAlarmRedMinExclusive
          ? _highHumidityExplainedByRecentWash(deviceData, rangeSettings)
                ? TemplateAlarmLevel.warning
                : TemplateAlarmLevel.alarm
          : number >= rangeSettings.humidityAlarmYellowMin
          ? TemplateAlarmLevel.warning
          : TemplateAlarmLevel.normal,
    'dewPointDelta' => _dewPointLevel(deviceData, rangeSettings),
    'presion' =>
      number > rangeSettings.filterPressureMax
          ? TemplateAlarmLevel.alarm
          : TemplateAlarmLevel.normal,
    _ => TemplateAlarmLevel.unavailable,
  };
}

TemplateAlarmLevel _dewPointLevel(
  Object? deviceData,
  DashboardRangeSettings rangeSettings,
) {
  final double? temperature = readTemplateDouble(deviceData, 'tempInterior');
  final double? humidity = readTemplateDouble(deviceData, 'humInterior');
  if (temperature == null || humidity == null) {
    return TemplateAlarmLevel.unavailable;
  }
  final double? dewPoint = calculateDewPointC(
    temperatureC: temperature,
    relativeHumidityPercent: humidity,
  );
  if (dewPoint == null) {
    return TemplateAlarmLevel.unavailable;
  }
  final double margin = temperature - dewPoint;
  if (margin <= rangeSettings.dewPointMarginAlarmRedMax) {
    return TemplateAlarmLevel.alarm;
  }
  if (margin < rangeSettings.dewPointMarginAlarmYellowMaxExclusive) {
    return TemplateAlarmLevel.warning;
  }
  return TemplateAlarmLevel.normal;
}

Color templateAlarmLevelColor(TemplateAlarmLevel level) {
  return switch (level) {
    TemplateAlarmLevel.normal => const Color(0xFF22C55E),
    TemplateAlarmLevel.warning => const Color(0xFFFACC15),
    TemplateAlarmLevel.alarm => const Color(0xFFEF4444),
    TemplateAlarmLevel.sensorFailure => const Color(0xFFEF4444),
    TemplateAlarmLevel.unavailable => const Color(0xFFE5E7EB),
  };
}

bool _highHumidityExplainedByRecentWash(
  Object? deviceData,
  DashboardRangeSettings rangeSettings,
) {
  final double? humidity = readTemplateDouble(deviceData, 'humInterior');
  if (humidity == null || humidity <= rangeSettings.humidityMax) {
    return false;
  }
  RoomWashEvent? event;
  if (deviceData is MuntersModel) {
    event = deviceData.recentRoomWashEvent;
  } else {
    final Object? value = readTemplateValue(deviceData, 'recentRoomWashEvent');
    if (value is RoomWashEvent) {
      event = value;
    }
  }
  if (event == null) {
    return false;
  }
  final DateTime now = DateTime.now();
  return !event.washedAt.isAfter(now) &&
      event.washedAt
          .add(RoomWashEvent.defaultHumidityShadingWindow)
          .isAfter(now);
}

/// Whether a fan should be shown as spinning. Prefers the discrete PLC fan
/// outputs (`fanQ5`..`fanQ10`) when known; falls back to the resolved
/// (already-transformed) speed value when no discrete output is available.
bool? resolveFanRunning(Object? deviceData, Object? value) {
  const List<String> fanFields = <String>[
    'fanQ5',
    'fanQ6',
    'fanQ7',
    'fanQ8',
    'fanQ9',
    'fanQ10',
  ];
  bool hasKnownFan = false;
  for (final String field in fanFields) {
    final bool? active = readTemplateBool(deviceData, field);
    if (active == true) {
      return true;
    }
    hasKnownFan = hasKnownFan || active != null;
  }
  if (hasKnownFan) {
    return false;
  }
  if (value is num) {
    return value > 0;
  }
  return null;
}

double? readTemplateDouble(Object? data, String field) {
  final Object? value = readTemplateValue(data, field);
  return value is num ? value.toDouble() : null;
}

bool? readTemplateBool(Object? data, String field) {
  final Object? value = readTemplateValue(data, field);
  return value is bool ? value : null;
}

String? readTemplateText(Object? data, String field) {
  final Object? value = readTemplateValue(data, field);
  return value is String ? value : null;
}

String formatSensorFailureCode(Object? value) {
  if (value is num) {
    if (value.isFinite && value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1);
  }
  return templateNoDataLabel;
}

Object? readTemplateValue(Object? data, String field) {
  if (data is Map<String, Object?>) {
    return data[field];
  }
  if (data is TemplateDataContext) {
    if (data.extras.containsKey(field)) {
      return data.extras[field];
    }
    return readTemplateValue(data.source, field);
  }
  if (data is MuntersModel) {
    return const TemplateDataResolver().resolveSourceField(field, data);
  }
  return null;
}
