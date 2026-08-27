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
    _ => Icons.device_unknown_outlined,
  };
}
