import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control_backend/src/plc_installation_config.dart';
import 'package:agro_data_control_backend/src/service_account_auth.dart';
import 'package:args/args.dart';

const List<String> _defaultPlcIds = <String>['munters1', 'munters2'];

Future<void> main(List<String> arguments) async {
  final ArgParser parser = ArgParser()
    ..addOption(
      'config',
      defaultsTo: _defaultConfigPath(),
      help: 'Ruta al JSON de configuracion del backend.',
    )
    ..addOption(
      'output',
      abbr: 'o',
      help: 'Archivo CSV de salida. Si se omite, imprime en stdout.',
    )
    ..addOption('from', help: 'Fecha inicial incluida, formato YYYY-MM-DD.')
    ..addOption('to', help: 'Fecha final incluida, formato YYYY-MM-DD.')
    ..addOption(
      'limit',
      defaultsTo: '30',
      help: 'Cantidad maxima de dias por Munters cuando no se indica --from.',
    )
    ..addOption(
      'service-account',
      help: 'Ruta al service account JSON. Pisa la ruta de la config.',
    )
    ..addOption(
      'plcs',
      defaultsTo: _defaultPlcIds.join(','),
      help: 'Lista separada por coma de PLC IDs a exportar.',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Muestra ayuda.');

  final ArgResults args = parser.parse(arguments);
  if (args.flag('help')) {
    _printUsage(parser);
    return;
  }

  final String configPath = args.option('config')!;
  final PlcInstallationConfig installationConfig = _loadInstallationConfig(
    configPath,
  );
  final List<String> plcIds = args
      .option('plcs')!
      .split(',')
      .map((String value) => value.trim())
      .where((String value) => value.isNotEmpty)
      .toList(growable: false);
  final int limit = _parsePositiveInt(args.option('limit')!, '--limit');
  final String? fromDate = _parseOptionalDate(args.option('from'), '--from');
  final String? toDate = _parseOptionalDate(args.option('to'), '--to');
  _validateDateRange(fromDate: fromDate, toDate: toDate);

  final Map<String, Map<String, _DailyTemperature>> byPlc =
      <String, Map<String, _DailyTemperature>>{};

  for (final String plcId in plcIds) {
    final TemperatureHistoryConfig historyConfig = _historyConfigForPlc(
      installationConfig,
      plcId,
      serviceAccountOverride: args.option('service-account'),
    );
    final _FirestoreDailyTemperatureClient client =
        _FirestoreDailyTemperatureClient(config: historyConfig);
    byPlc[plcId] = await client.fetchDailyTemperatures(
      fromDate: fromDate,
      toDate: toDate,
      limit: fromDate == null ? limit : null,
    );
  }

  final String csv = _buildCsv(plcIds: plcIds, dailyByPlc: byPlc);
  final String? outputPath = args.option('output');
  if (outputPath == null || outputPath.trim().isEmpty) {
    stdout.write(csv);
    return;
  }

  final File outputFile = File(outputPath);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(csv);
  stdout.writeln('CSV generado: ${outputFile.path}');
}

void _printUsage(ArgParser parser) {
  stdout.writeln('Exporta temperaturas diarias promedio de los Munters a CSV.');
  stdout.writeln('');
  stdout.writeln('Uso:');
  stdout.writeln(
    '  ./scripts/export_munters_daily_temperatures.sh '
    '--output scripts/munters_daily_temperatures.csv',
  );
  stdout.writeln('');
  stdout.writeln(parser.usage);
}

String _defaultConfigPath() {
  if (File('config/sites/default.json').existsSync()) {
    return 'config/sites/default.json';
  }
  return 'backend/config/sites/default.json';
}

PlcInstallationConfig _loadInstallationConfig(String path) {
  final File file = File(path);
  if (!file.existsSync()) {
    throw ArgumentError('No existe el archivo de config: $path');
  }
  final Map<String, dynamic> json =
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return PlcInstallationConfig.fromJson(json);
}

TemperatureHistoryConfig _historyConfigForPlc(
  PlcInstallationConfig installationConfig,
  String plcId, {
  required String? serviceAccountOverride,
}) {
  TemperatureHistoryConfig? config;
  for (final TemperatureHistoryConfig item
      in installationConfig.temperatureHistories) {
    if (item.plcId == plcId) {
      config = item;
      break;
    }
  }
  if (config == null) {
    throw ArgumentError(
      'No hay temperatureHistory configurado para plcId=$plcId',
    );
  }

  final String serviceAccountPath =
      serviceAccountOverride ??
      Platform.environment['GOOGLE_APPLICATION_CREDENTIALS'] ??
      _localServiceAccountPath() ??
      config.firestoreServiceAccountPath;

  return TemperatureHistoryConfig(
    enabled: config.enabled,
    sourcePath: config.sourcePath,
    tenantId: config.tenantId,
    siteId: config.siteId,
    plcId: config.plcId,
    firestoreProjectId: config.firestoreProjectId,
    firestoreDatabaseId: config.firestoreDatabaseId,
    firestoreServiceAccountPath: serviceAccountPath,
  );
}

String? _localServiceAccountPath() {
  const List<String> candidates = <String>[
    'config/service-account.json',
    'backend/config/service-account.json',
  ];
  for (final String path in candidates) {
    if (File(path).existsSync()) {
      return path;
    }
  }
  return null;
}

int _parsePositiveInt(String value, String optionName) {
  final int? parsed = int.tryParse(value);
  if (parsed == null || parsed <= 0) {
    throw ArgumentError('$optionName debe ser un entero mayor a cero.');
  }
  return parsed;
}

String? _parseOptionalDate(String? value, String optionName) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  final String trimmed = value.trim();
  final RegExp datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  if (!datePattern.hasMatch(trimmed)) {
    throw ArgumentError('$optionName debe tener formato YYYY-MM-DD.');
  }
  final DateTime parsed = DateTime.parse(trimmed);
  final String normalized =
      '${parsed.year.toString().padLeft(4, '0')}-'
      '${parsed.month.toString().padLeft(2, '0')}-'
      '${parsed.day.toString().padLeft(2, '0')}';
  if (normalized != trimmed) {
    throw ArgumentError('$optionName no es una fecha valida: $trimmed');
  }
  return trimmed;
}

void _validateDateRange({required String? fromDate, required String? toDate}) {
  if (fromDate != null && toDate != null && fromDate.compareTo(toDate) > 0) {
    throw ArgumentError('--from no puede ser posterior a --to.');
  }
}

String _buildCsv({
  required List<String> plcIds,
  required Map<String, Map<String, _DailyTemperature>> dailyByPlc,
}) {
  final Set<String> dates = <String>{};
  for (final Map<String, _DailyTemperature> daily in dailyByPlc.values) {
    dates.addAll(daily.keys);
  }
  final List<String> sortedDates = dates.toList(growable: false)..sort();

  final StringBuffer buffer = StringBuffer();
  buffer.writeln(
    <String>[
      'dia',
      for (final String plcId in plcIds) '${plcId}_temp_promedio',
    ].join(','),
  );

  for (final String date in sortedDates) {
    buffer.writeln(
      <String>[
        date,
        for (final String plcId in plcIds)
          _formatCsvNumber(dailyByPlc[plcId]?[date]?.avgTemp),
      ].join(','),
    );
  }
  return buffer.toString();
}

String _formatCsvNumber(double? value) {
  if (value == null) {
    return '';
  }
  return value.toStringAsFixed(2);
}

class _FirestoreDailyTemperatureClient {
  _FirestoreDailyTemperatureClient({required this.config})
    : _auth = ServiceAccountAuth(
        serviceAccountJsonPath: config.firestoreServiceAccountPath,
      );

  final TemperatureHistoryConfig config;
  final ServiceAccountAuth _auth;

  Future<Map<String, _DailyTemperature>> fetchDailyTemperatures({
    required String? fromDate,
    required String? toDate,
    required int? limit,
  }) async {
    if (!config.enabled) {
      return <String, _DailyTemperature>{};
    }
    if (_effectiveProjectId.isEmpty) {
      throw StateError('Falta firestoreProjectId para plcId=${config.plcId}.');
    }
    if (config.firestoreServiceAccountPath.trim().isEmpty) {
      throw StateError(
        'Falta service account para plcId=${config.plcId}. Use '
        '--service-account o GOOGLE_APPLICATION_CREDENTIALS.',
      );
    }

    final Map<String, _DailyTemperature> records =
        <String, _DailyTemperature>{};
    String? pageToken;
    do {
      final Uri uri = _dailyCollectionUri(
        pageToken: pageToken,
        pageSize: limit ?? 100,
      );
      final Map<String, dynamic> response = await _getJson(uri);
      final List<dynamic> documents =
          response['documents'] as List<dynamic>? ?? <dynamic>[];

      for (final Object? rawDocument in documents) {
        final _DailyTemperature? daily = _parseDaily(rawDocument);
        if (daily == null) {
          continue;
        }
        if (toDate != null && daily.dateKey.compareTo(toDate) > 0) {
          continue;
        }
        if (fromDate != null && daily.dateKey.compareTo(fromDate) < 0) {
          return records;
        }
        records[daily.dateKey] = daily;
        if (limit != null && records.length >= limit) {
          return records;
        }
      }

      pageToken = response['nextPageToken'] as String?;
    } while (pageToken != null && pageToken.isNotEmpty);

    return records;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.getUrl(uri);
      final String token = await _auth.getAccessToken();
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');

      final HttpClientResponse response = await request.close();
      final String body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Firestore GET fallo status=${response.statusCode} body=$body',
          uri: uri,
        );
      }
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  Uri _dailyCollectionUri({required String? pageToken, required int pageSize}) {
    final Map<String, String> query = <String, String>{
      'orderBy': 'dateKey desc',
      'pageSize': pageSize.toString(),
      if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
    };
    return Uri.https(
      'firestore.googleapis.com',
      '/v1/projects/$_effectiveProjectId/databases/'
          '${config.firestoreDatabaseId}/documents/$_dailyCollectionPath',
      query,
    );
  }

  String get _dailyCollectionPath =>
      'tenants/${config.tenantId}/sites/${config.siteId}/plcs/'
      '${config.plcId}/metrics/temperature/daily';

  String get _effectiveProjectId =>
      config.firestoreProjectId ??
      Platform.environment['FIRESTORE_PROJECT_ID'] ??
      '';
}

_DailyTemperature? _parseDaily(Object? rawDocument) {
  if (rawDocument is! Map<String, dynamic>) {
    return null;
  }
  final Map<String, dynamic> fields =
      rawDocument['fields'] as Map<String, dynamic>? ?? <String, dynamic>{};
  final String dateKey = _readString(fields, 'dateKey');
  final double? avgTemp = _readDouble(fields, 'avgTemp');
  if (dateKey.isEmpty || avgTemp == null) {
    return null;
  }
  return _DailyTemperature(dateKey: dateKey, avgTemp: avgTemp);
}

String _readString(Map<String, dynamic> fields, String key) {
  final Map<String, dynamic> value =
      fields[key] as Map<String, dynamic>? ?? <String, dynamic>{};
  return (value['stringValue'] ?? value['timestampValue'] ?? '').toString();
}

double? _readDouble(Map<String, dynamic> fields, String key) {
  final Map<String, dynamic>? value = fields[key] as Map<String, dynamic>?;
  if (value == null) {
    return null;
  }
  final Object? raw = value['doubleValue'] ?? value['integerValue'];
  if (raw is num) {
    return raw.toDouble();
  }
  if (raw is String) {
    return double.tryParse(raw);
  }
  return null;
}

class _DailyTemperature {
  const _DailyTemperature({required this.dateKey, required this.avgTemp});

  final String dateKey;
  final double avgTemp;
}
