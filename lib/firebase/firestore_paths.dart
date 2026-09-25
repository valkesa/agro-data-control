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

  static String tenantDoc(String tenantId) => 'tenants/$tenantId';

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

  static String deviceRoomsCollection(String tenantId, String deviceId) =>
      '${deviceDoc(tenantId, deviceId)}/rooms';

  static String deviceRoomDoc(
    String tenantId,
    String deviceId,
    String roomId,
  ) => '${deviceRoomsCollection(tenantId, deviceId)}/$roomId';

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

  static String devicePigStatsDoc({
    required String tenantId,
    required String deviceId,
  }) => 'tenants/$tenantId/devices/$deviceId/pigStats/pigs';

  static String deviceRoomPigStatsDoc({
    required String tenantId,
    required String deviceId,
    required String roomId,
  }) => 'tenants/$tenantId/devices/$deviceId/rooms/$roomId/pigStats/pigs';

  static String pigMovementsCollection({
    required String tenantId,
    required String siteId,
    required String plcId,
  }) => 'tenants/$tenantId/sites/$siteId/plcs/$plcId/pigMovements';

  static String devicePigMovementsCollection({
    required String tenantId,
    required String deviceId,
  }) => 'tenants/$tenantId/devices/$deviceId/pigMovements';

  static String deviceRoomPigMovementsCollection({
    required String tenantId,
    required String deviceId,
    required String roomId,
  }) => 'tenants/$tenantId/devices/$deviceId/rooms/$roomId/pigMovements';

  static String pigExitReasonsCollection({
    required String tenantId,
    required String siteId,
  }) => 'tenants/$tenantId/sites/$siteId/pigExitReasons';

  // Global, not tenant-scoped: room_climate/laboratory_basic/
  // disinfection_arch are reusable presentation types shared across every
  // tenant, not data that varies per tenant — see Etapa 6A.
  static String deviceTemplatesCollection() => 'deviceTemplates';

  static String deviceTemplateDoc(String templateId) =>
      'deviceTemplates/$templateId';

  // Etapa B5: hierarchical alert configuration/recipients, matching the
  // backend paths from Etapa B4/B4.5 (`backend/firestore.rules`,
  // `AlertConfigFirestoreDocument`, `AlertRecipientFirestoreDocument`).
  // Never write under `/plcs` for these — see Etapa B4 §A.
  static String tenantAlertConfigCollection(String tenantId) =>
      'tenants/$tenantId/alertConfig';

  static String siteAlertConfigCollection(String tenantId, String siteId) =>
      'tenants/$tenantId/sites/$siteId/alertConfig';

  static String deviceAlertConfigCollection(String tenantId, String deviceId) =>
      'tenants/$tenantId/devices/$deviceId/alertConfig';

  static String roomAlertConfigCollection(
    String tenantId,
    String deviceId,
    String roomId,
  ) => 'tenants/$tenantId/devices/$deviceId/rooms/$roomId/alertConfig';

  static String tenantAlertRecipientsCollection(String tenantId) =>
      'tenants/$tenantId/alertRecipients';

  static String siteAlertRecipientsCollection(String tenantId, String siteId) =>
      'tenants/$tenantId/sites/$siteId/alertRecipients';

  static String deviceAlertRecipientsCollection(
    String tenantId,
    String deviceId,
  ) => 'tenants/$tenantId/devices/$deviceId/alertRecipients';

  static String roomAlertRecipientsCollection(
    String tenantId,
    String deviceId,
    String roomId,
  ) => 'tenants/$tenantId/devices/$deviceId/rooms/$roomId/alertRecipients';

  // Etapa N7.1: global, not tenant-scoped — same rationale as
  // `deviceTemplatesCollection` (Etapa 6A): LayoutTemplate/CellLayoutPreset/
  // CapabilityMetric/CapabilityIndicator/CapabilityProfile/BoardPreset are
  // reusable design-time configuration shared across every tenant, never
  // data that varies per tenant. IDs are caller-chosen slugs
  // (`normalizeStructuralId`), never Firestore auto-IDs — same convention
  // as every structural collection in this file. Do not nest these under
  // `/tenants/{tenantId}` — see N7.1 §1/§2.
  static String layoutTemplatesCollection() => 'layoutTemplates';

  static String layoutTemplateDoc(String templateId) =>
      'layoutTemplates/$templateId';

  static String cellLayoutPresetsCollection() => 'cellLayoutPresets';

  static String cellLayoutPresetDoc(String presetId) =>
      'cellLayoutPresets/$presetId';

  static String capabilityMetricsCollection() => 'capabilityMetrics';

  static String capabilityMetricDoc(String metricKey) =>
      'capabilityMetrics/$metricKey';

  static String capabilityIndicatorsCollection() => 'capabilityIndicators';

  static String capabilityIndicatorDoc(String indicatorKey) =>
      'capabilityIndicators/$indicatorKey';

  static String capabilityProfilesCollection() => 'capabilityProfiles';

  static String capabilityProfileDoc(String profileId) =>
      'capabilityProfiles/$profileId';

  // Unlike the other N7.1 global collections above, a BoardPreset can
  // actually be deleted (N7.1 §10) — never physically deleting is a
  // deliberate exception in this file, not the default.
  static String boardPresetsCollection() => 'boardPresets';

  static String boardPresetDoc(String presetId) => 'boardPresets/$presetId';

  // Etapa N7.1 §3/§8/§9: per-Device board configuration — deliberately its
  // own singleton doc under a `settings`-style subcollection (mirrors
  // `controlDashboardSettings`/`plcElectricalConsumptionSettings` above),
  // NOT a new field on `devices/{deviceId}` itself. This keeps every N7.1
  // write scoped to a brand new path with its own rules block, so the
  // already-in-production `devices/{deviceId}` document/rules are never
  // touched by this etapa (N7.1 §18 "no tocar producción legacy todavía").
  // Holds: capabilityProfileId + the persisted DeviceBoardLayout (schema-2
  // `BoardContentLayout` shape, including `sourceBoardPresetId`/
  // `sourceBoardPresetVersion` trazability) as ONE document, so opening
  // "Configuración de Board" for a Device costs exactly one read (N7.1 §5).
  static String deviceBoardConfigDoc(String tenantId, String deviceId) =>
      'tenants/$tenantId/devices/$deviceId/settings/boardConfig';
}
