// Etapa B5 — adapta el modelo legacy site-scoped (`AlertSettings` +
// `ControlDashboardThresholds`, de `tenants/{t}/sites/{s}/settings/
// controlDashboard`) al formato `AlertConfigOverride` para que el resolver
// jerárquico lo trate como el nivel más bajo de precedencia (legacy),
// igual que `LegacyAlertSettingsAdapter` en el backend (Etapa B2/B3).
//
// El legacy es inherentemente site-scoped: no existe legacy a nivel Tenant
// ni Device/Room. Cuando el scope actual es solo Tenant, no hay capa
// legacy que ofrecer — el catálogo es la única base.

import '../models/alert_settings.dart';
import '../models/hierarchical_alert_config.dart';
import 'control_dashboard_config_service.dart';

const Map<AlertSettingKey, String> _legacyKeyToAlertId =
    <AlertSettingKey, String>{
      AlertSettingKey.muntersDoorOpen: 'munters_door_open',
      AlertSettingKey.roomDoorOpen: 'room_door_open',
      AlertSettingKey.sensorFailure: 'sensor_failure',
      AlertSettingKey.temperatureInterior: 'temperature_interior',
      AlertSettingKey.highTemperatureHeatingActive:
          'high_temperature_heating_active',
      AlertSettingKey.lowTemperatureHumidifierActive:
          'low_temperature_humidifier_active',
      AlertSettingKey.highDifferentialPressure: 'high_differential_pressure',
      AlertSettingKey.highHumidity: 'high_humidity',
      AlertSettingKey.dewPointRisk: 'dew_point_risk',
    };

Map<String, AlertConfigOverride>
legacyAlertConfigOverridesFromControlDashboard({
  required AlertSettings alertSettings,
  required ControlDashboardThresholds thresholds,
}) {
  return <String, AlertConfigOverride>{
    for (final MapEntry<AlertSettingKey, String> entry
        in _legacyKeyToAlertId.entries)
      entry.value: _overrideFor(
        entry.key,
        alertSettings.toggleFor(entry.key),
        thresholds,
      ),
  };
}

AlertConfigOverride _overrideFor(
  AlertSettingKey key,
  AlertToggleSettings toggle,
  ControlDashboardThresholds thresholds,
) {
  return AlertConfigOverride(
    enabled: toggle.enabled,
    visualEnabled: toggle.enabled,
    whatsappEnabled: toggle.sendWhatsapp,
    whatsappDelayMinutes: toggle.whatsappDelayMinutes,
    order: toggle.order,
    thresholds: _thresholdsFor(key, thresholds),
  );
}

AlertThresholds _thresholdsFor(
  AlertSettingKey key,
  ControlDashboardThresholds t,
) {
  return switch (key) {
    AlertSettingKey.muntersDoorOpen ||
    AlertSettingKey.roomDoorOpen => AlertThresholds.empty,
    AlertSettingKey.sensorFailure => AlertThresholds(
      sensorFailureMin: t.tempInteriorSensorFailureMin,
    ),
    AlertSettingKey.temperatureInterior => AlertThresholds(
      min: t.tempInteriorMin,
      max: t.tempInteriorMax,
      sensorFailureMin: t.tempInteriorSensorFailureMin,
    ),
    AlertSettingKey.highTemperatureHeatingActive => AlertThresholds(
      max: t.tempInteriorMax,
    ),
    AlertSettingKey.lowTemperatureHumidifierActive => AlertThresholds(
      min: t.tempInteriorMin,
    ),
    AlertSettingKey.highDifferentialPressure => AlertThresholds(
      max: t.filterPressureMax,
    ),
    AlertSettingKey.highHumidity => AlertThresholds(
      max: t.humidityAlarmRedMinExclusive,
    ),
    AlertSettingKey.dewPointRisk => AlertThresholds(
      margin: t.dewPointMarginAlarmRedMaxInclusive,
    ),
  };
}
