import 'package:flutter/material.dart';

IconData resolveTemplateIcon(String icon) {
  return switch (icon.trim()) {
    'ammonia' => Icons.science_outlined,
    'co2' => Icons.cloud_outlined,
    'dewPoint' => Icons.water_drop_outlined,
    'door' => Icons.door_front_door_outlined,
    'equipment' => Icons.memory,
    'equipmentDoor' => Icons.door_sliding_outlined,
    'fan' => Icons.air,
    'flame' => Icons.local_fire_department,
    'humidity' => Icons.water_drop,
    'humidityOutdoor' => Icons.water_drop_outlined,
    'pig' => Icons.pets,
    'pressure' => Icons.grid_on_rounded,
    'room' => Icons.cottage_outlined,
    'snowflake' => Icons.ac_unit,
    'tank' => Icons.propane_tank_outlined,
    'thermometer' => Icons.thermostat,
    'thermometerOutdoor' => Icons.thermostat_outlined,
    'vehicle' => Icons.local_shipping_outlined,
    'vehicleTotal' => Icons.directions_car_filled_outlined,
    'water' => Icons.local_drink_outlined,
    'weight' => Icons.monitor_weight_outlined,
    // N6.4 §10: generic semantic categories for freeform design (icon/
    // placeholder items with no MetricDefinition behind them) — same
    // reusable switch, never a second icon catalog.
    'warning' => Icons.warning_amber_outlined,
    'check' => Icons.check_circle_outline,
    'power' => Icons.power_settings_new,
    'camera' => Icons.camera_alt_outlined,
    'lab' => Icons.biotech_outlined,
    'generic' => Icons.widgets_outlined,
    _ => Icons.device_unknown_outlined,
  };
}

/// Canonical, ordered key list for the reusable icon picker (N6.4 §10) —
/// every key [resolveTemplateIcon] recognizes explicitly, so the picker and
/// the resolver can never drift apart. `generic` is listed last as the
/// deliberate custom/fallback choice.
const List<String> templateIconKeys = [
  'thermometer',
  'thermometerOutdoor',
  'humidity',
  'humidityOutdoor',
  'dewPoint',
  'pressure',
  'fan',
  'flame',
  'snowflake',
  'water',
  'tank',
  'door',
  'equipmentDoor',
  'vehicle',
  'vehicleTotal',
  'weight',
  'pig',
  'ammonia',
  'co2',
  'equipment',
  'room',
  'warning',
  'check',
  'power',
  'camera',
  'lab',
  'generic',
];
