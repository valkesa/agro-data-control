class FirestorePaths {
  const FirestorePaths._();

  static String userProfile(String uid) => 'users/$uid';

  static String workspacePresenceCollection(String workspaceId) =>
      'workspaces/$workspaceId/presence';

  static String workspacePresenceDoc(String workspaceId, String uid) =>
      '${workspacePresenceCollection(workspaceId)}/$uid';

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

  static String plcsCollection(String tenantId, String siteId) =>
      'tenants/$tenantId/sites/$siteId/plcs';

  static String plcConfigDoc(String tenantId, String siteId, String plcId) =>
      'tenants/$tenantId/sites/$siteId/plcs/$plcId';
}
