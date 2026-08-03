class FirestorePaths {
  const FirestorePaths._();

  static String userProfile(String uid) => 'users/$uid';

  static String siteDoc(String tenantId, String siteId) =>
      'tenants/$tenantId/sites/$siteId';

  static String tenantMemberDoc(String tenantId, String uid) =>
      'tenants/$tenantId/members/$uid';

  static String controlDashboardSettings(String tenantId, String siteId) =>
      'tenants/$tenantId/sites/$siteId/settings/controlDashboard';

  static String temperatureMetricsRoot({
    required String tenantId,
    required String siteId,
    required String plcId,
  }) => 'tenants/$tenantId/sites/$siteId/plcs/$plcId/metrics/temperature';

  static String temperatureHourlyHistoryCollection({
    required String tenantId,
    required String siteId,
    required String plcId,
  }) =>
      '${temperatureMetricsRoot(tenantId: tenantId, siteId: siteId, plcId: plcId)}/hourly';

  static String temperatureDailyHistoryCollection({
    required String tenantId,
    required String siteId,
    required String plcId,
  }) =>
      '${temperatureMetricsRoot(tenantId: tenantId, siteId: siteId, plcId: plcId)}/daily';

  static String differentialPressureMetricsRoot({
    required String tenantId,
    required String siteId,
    required String plcId,
  }) =>
      'tenants/$tenantId/sites/$siteId/plcs/$plcId/metrics/differentialPressure';

  static String differentialPressureDailyHistoryCollection({
    required String tenantId,
    required String siteId,
    required String plcId,
  }) =>
      '${differentialPressureMetricsRoot(tenantId: tenantId, siteId: siteId, plcId: plcId)}/daily';

  static String waterShortageMetricsRoot({
    required String tenantId,
    required String siteId,
    required String plcId,
  }) => 'tenants/$tenantId/sites/$siteId/plcs/$plcId/metrics/waterShortage';

  static String waterShortageEventsCollection({
    required String tenantId,
    required String siteId,
    required String plcId,
  }) =>
      '${waterShortageMetricsRoot(tenantId: tenantId, siteId: siteId, plcId: plcId)}/events';

  static String waterShortageMonthlyCollection({
    required String tenantId,
    required String siteId,
    required String plcId,
  }) =>
      '${waterShortageMetricsRoot(tenantId: tenantId, siteId: siteId, plcId: plcId)}/monthly';

  static String doorStateDoc({
    required String tenantId,
    required String siteId,
    required String doorId,
  }) => 'tenants/$tenantId/sites/$siteId/doors/$doorId';

  static String doorOpeningsCollection({
    required String tenantId,
    required String siteId,
    required String doorId,
  }) =>
      '${doorStateDoc(tenantId: tenantId, siteId: siteId, doorId: doorId)}/openings';

  static String tenantsCollection() => 'tenants';

  static String tenantSitesCollection(String tenantId) =>
      'tenants/$tenantId/sites';

  // Current structural schema. New tenants and new features must use these
  // tenant-level collections.
  static String tenantSectorsCollection(String tenantId) =>
      'tenants/$tenantId/sectors';

  static String sectorDoc(String tenantId, String sectorId) =>
      'tenants/$tenantId/sectors/$sectorId';

  static String tenantDevicesCollection(String tenantId) =>
      'tenants/$tenantId/devices';

  static String deviceDoc(String tenantId, String deviceId) =>
      'tenants/$tenantId/devices/$deviceId';

  // LEGACY SCHEMA:
  // The collection `tenants/{tenantId}/sites/{siteId}/plcs/{plcId}` is kept
  // only for backward compatibility with existing tenants.
  //
  // New tenants and new features MUST use the current structure:
  //
  // tenants/{tenantId}/sites/{siteId}
  // tenants/{tenantId}/sectors/{sectorId}
  // tenants/{tenantId}/devices/{deviceId}
  //
  // Do not create new documents under `/plcs`.
  // Do not reuse the legacy PLC schema as the basis for new implementations.
  static String plcsCollection(String tenantId, String siteId) =>
      'tenants/$tenantId/sites/$siteId/plcs';

  static String plcConfigDoc(String tenantId, String siteId, String plcId) =>
      'tenants/$tenantId/sites/$siteId/plcs/$plcId';

  static String plcElectricalConsumptionSettings({
    required String tenantId,
    required String siteId,
    required String plcId,
  }) =>
      '${plcConfigDoc(tenantId, siteId, plcId)}/settings/electricalConsumption';

  static String runtimeEventsCollection({
    required String tenantId,
    required String siteId,
    required String plcId,
  }) => 'tenants/$tenantId/sites/$siteId/plcs/$plcId/runtimeEvents';

  static String roomWashEventsCollection({
    required String tenantId,
    required String siteId,
  }) => 'tenants/$tenantId/sites/$siteId/room_wash_events';

  static String electricalCostSettings(String tenantId, String siteId) =>
      'tenants/$tenantId/sites/$siteId/settings/electricalCost';

  static String pigStatsDoc({
    required String tenantId,
    required String siteId,
    required String plcId,
  }) => 'tenants/$tenantId/sites/$siteId/plcs/$plcId/plcStats/pigs';

  static String pigMovementsCollection({
    required String tenantId,
    required String siteId,
    required String plcId,
  }) => 'tenants/$tenantId/sites/$siteId/plcs/$plcId/pigMovements';

  static String pigExitReasonsCollection({
    required String tenantId,
    required String siteId,
  }) => 'tenants/$tenantId/sites/$siteId/pigExitReasons';
}
