import '../models/hierarchical_alert_catalog.dart';
import '../models/hierarchical_alert_config.dart';
import 'control_dashboard_config_service.dart';
import 'device_environment_history_repository.dart';
import 'hierarchical_alert_config_service.dart';
import 'legacy_alert_config_adapter.dart';

class EnvironmentAlertThresholds {
  const EnvironmentAlertThresholds({
    this.temperature = AlertThresholds.empty,
    this.humidity = AlertThresholds.empty,
  });

  final AlertThresholds temperature;
  final AlertThresholds humidity;
}

/// Reads the same hierarchy used by Configuración → Alertas and resolves
/// field-by-field inheritance for the Device represented by a history scope.
class EnvironmentAlertThresholdRepository {
  const EnvironmentAlertThresholdRepository({
    this.configService = const HierarchicalAlertConfigService(),
    this.controlDashboardConfigService = const ControlDashboardConfigService(),
  });

  final HierarchicalAlertConfigService configService;
  final ControlDashboardConfigService controlDashboardConfigService;

  Future<EnvironmentAlertThresholds> load(EnvironmentHistoryScope scope) async {
    final tenant = await configService.loadScopeOverrides(
      AlertConfigScopeTarget(
        tenantId: scope.tenantId,
        scope: AlertConfigScope.tenant,
      ),
    );
    final site = await configService.loadScopeOverrides(
      AlertConfigScopeTarget(
        tenantId: scope.tenantId,
        siteId: scope.siteId,
        scope: AlertConfigScope.site,
      ),
    );
    final device = await configService.loadScopeOverrides(
      AlertConfigScopeTarget(
        tenantId: scope.tenantId,
        deviceId: scope.deviceId,
        scope: AlertConfigScope.device,
      ),
    );

    Map<String, AlertConfigOverride>? legacy;
    final legacyResult = await controlDashboardConfigService.readConfig(
      tenantId: scope.tenantId,
      siteId: scope.siteId,
    );
    if (legacyResult.exists && legacyResult.errorMessage == null) {
      legacy = legacyAlertConfigOverridesFromControlDashboard(
        alertSettings: legacyResult.alertSettings,
        thresholds: legacyResult.thresholds,
      );
    }

    EffectiveAlertConfig effective(String alertId) {
      final definition = AlertDefinitionCatalog.byId(alertId);
      return resolveEffectiveAlertConfig(
        alertId: alertId,
        catalogOrder: definition.order,
        legacy: legacy?[alertId],
        tenant: tenant[alertId],
        site: site[alertId],
        device: device[alertId],
      );
    }

    return EnvironmentAlertThresholds(
      temperature: effective('temperature_interior').thresholds,
      humidity: effective('high_humidity').thresholds,
    );
  }
}
