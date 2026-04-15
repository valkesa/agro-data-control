class FirestorePaths {
  const FirestorePaths._();

  static const String defaultSiteId = 'genetica-1';

  static String userProfile(String uid) => 'users/$uid';

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
  }) => '${temperatureMetricsRoot(tenantId: tenantId, siteId: siteId, plcId: plcId)}/hourly';

  static String temperatureDailyHistoryCollection({
    required String tenantId,
    required String siteId,
    required String plcId,
  }) => '${temperatureMetricsRoot(tenantId: tenantId, siteId: siteId, plcId: plcId)}/daily';

  static String waterShortageMetricsRoot({
    required String tenantId,
    required String siteId,
    required String plcId,
  }) => 'tenants/$tenantId/sites/$siteId/plcs/$plcId/metrics/waterShortage';

  static String waterShortageEventsCollection({
    required String tenantId,
    required String siteId,
    required String plcId,
  }) => '${waterShortageMetricsRoot(tenantId: tenantId, siteId: siteId, plcId: plcId)}/events';

  static String waterShortageMonthlyCollection({
    required String tenantId,
    required String siteId,
    required String plcId,
  }) => '${waterShortageMetricsRoot(tenantId: tenantId, siteId: siteId, plcId: plcId)}/monthly';
}
