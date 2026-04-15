class AppConfig {
  const AppConfig._();

  static const String backendSnapshotUrl = String.fromEnvironment(
    'PLC_API_URL',
    defaultValue: 'https://agrodata-control.valke.com.ar/api/snapshot',
  );

  static const String currentBackendSnapshotUrl = String.fromEnvironment(
    'PLC_API_URL_CURRENT',
    defaultValue: 'https://agrodata-control.valke.com.ar/api/current/snapshot',
  );

  static const String candidateBackendSnapshotUrl = String.fromEnvironment(
    'PLC_API_URL_CANDIDATE',
    defaultValue: 'https://agrodata-control.valke.com.ar/api/candidate/snapshot',
  );
}
