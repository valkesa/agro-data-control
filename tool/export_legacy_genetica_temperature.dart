// Extracción PUNTUAL y de una sola vez de históricos legacy de temperatura
// (Sala 1 / Sala 2, site genetica-1, tenant the-gene-pig) — exactamente lo
// que PROMPT_exportacion_historicos_excel.md anticipa como "los históricos
// legacy se resolverán externamente mediante una extracción puntual": NO es
// parte de la funcionalidad de exportación que ve el usuario en la App (esa
// sigue sin ningún camino legacy, ver lib/pages/historical_export_page.dart)
// y no se integra a ella.
//
// Lee directamente tenants/the-gene-pig/sites/genetica-1/plcs/{munters1,
// munters2}/metrics/temperature/hourly (el mismo path legacy que ya usa
// TemperatureHistoryRepository para el gráfico en vivo), para todo el
// historial ANTERIOR al 25/09/2026 ART (cuando empezó a escribir datos la
// colección moderna historyHourly que ya cubre el exportador nuevo).
// Humedad no existía en este esquema legacy — por eso solo se exporta
// temperatura, como pidió el usuario.
//
// Reutiliza el armado del .xlsx ya construido/testeado para el exportador
// nuevo (HistoricalExportVariable/HistoricalExportPoint/
// buildHistoricalExportWorkbook son puros — no les importa si el dato vino
// de Firestore REST o del SDK), así el archivo resultante tiene el mismo
// formato que el que ya recibiste para el período moderno.
//
// Requiere backend/config/service-account.json (mismo mecanismo de lectura
// ya usado en este repo — ver tool/normalize_la_payana_device.dart).
// Deliberadamente sin `cloud_firestore`: un `dart run` plano no puede cargar
// plugins de Flutter.
//
// Uso:
//   dart run tool/export_legacy_genetica_temperature.dart

import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control/services/historical_export_point.dart';
import 'package:agro_data_control/services/historical_export_variable.dart';
import 'package:agro_data_control/services/historical_export_workbook.dart';

const _tenantId = 'the-gene-pig';
const _siteId = 'genetica-1'; // siteId legacy real de este path (distinto del siteId "las-heras" que usa la arquitectura nueva)
const _siteDisplayName = 'Las Heras (legacy genetica-1)';
const _clientDisplayName = 'Gene Pig';

// plcId legacy -> nombre a mostrar en el Excel.
const _plcDisplayNames = {'munters1': 'Sala 1', 'munters2': 'Sala 2'};

// Exclusivo: el corte real de cuando historyHourly (la colección moderna)
// empezó a tener datos — confirmado por el usuario ("pude exportar todo
// desde el 25/09").
final DateTime _cutoffUtcExclusive = DateTime.utc(2026, 9, 25, 3); // 25/09 00:00 ART

const _temperatureOnly = [
  HistoricalExportVariable(key: 'temperature', label: 'Temperatura interior', unit: '°C'),
];

Future<void> main() async {
  print('=== Extracción puntual: temperatura legacy genetica-1 (Sala 1 / Sala 2) ===');
  print('Rango: todo lo disponible antes de ${_cutoffUtcExclusive.toIso8601String()} (UTC)');

  final Map<String, dynamic> serviceAccount =
      jsonDecode(File('backend/config/service-account.json').readAsStringSync())
          as Map<String, dynamic>;
  final String projectId = serviceAccount['project_id'] as String;
  final String accessToken = await _getAccessToken(serviceAccount);
  final HttpClient client = HttpClient();

  try {
    final devices = <HistoricalExportDeviceData>[];
    DateTime? overallFrom;
    DateTime? overallTo;

    for (final entry in _plcDisplayNames.entries) {
      final plcId = entry.key;
      final displayName = entry.value;
      print('--- $displayName ($plcId) ---');
      final points = await _fetchAllLegacyHourlyTemperature(
        client: client,
        projectId: projectId,
        accessToken: accessToken,
        plcId: plcId,
      );
      print('  ${points.length} horas encontradas.');
      if (points.isNotEmpty) {
        final first = points.first.periodStartUtc;
        final last = points.last.periodStartUtc;
        print('  Rango real: ${first.toIso8601String()} .. ${last.toIso8601String()}');
        if (overallFrom == null || first.isBefore(overallFrom)) overallFrom = first;
        if (overallTo == null || last.isAfter(overallTo)) overallTo = last;
      }
      devices.add(HistoricalExportDeviceData(deviceName: displayName, points: points));
    }

    if (overallFrom == null || overallTo == null) {
      print('Sin datos legacy encontrados — no se generó ningún archivo.');
      return;
    }

    final request = HistoricalExportRequest(
      clientName: _clientDisplayName,
      establishmentName: _siteDisplayName,
      fromDate: DateTime(overallFrom.year, overallFrom.month, overallFrom.day),
      toDate: DateTime(overallTo.year, overallTo.month, overallTo.day),
      variables: _temperatureOnly,
      devices: devices,
    );
    final bytes = buildHistoricalExportWorkbook(request);
    final outPath =
        'no_git/AgroData_GenePig_Genetica1_Legacy_Temperatura_hasta_2026-09-24.xlsx';
    await File(outPath).writeAsBytes(bytes);
    print('=== Archivo generado: $outPath (${bytes.length} bytes) ===');
  } finally {
    client.close(force: true);
  }
}

/// Pagina hacia adelante (orden ascendente por `timestampHourStart`) hasta
/// agotar el historial legacy disponible antes de [_cutoffUtcExclusive] — sin
/// límite inferior: se trae TODO lo que exista, cualquiera sea cuán atrás
/// llegue (extracción puntual, no una query recurrente).
Future<List<HistoricalExportPoint>> _fetchAllLegacyHourlyTemperature({
  required HttpClient client,
  required String projectId,
  required String accessToken,
  required String plcId,
}) async {
  const pageSize = 500;
  final parent =
      'tenants/$_tenantId/sites/$_siteId/plcs/$plcId/metrics/temperature';
  final points = <HistoricalExportPoint>[];
  String? cursorIso;

  while (true) {
    final structuredQuery = <String, dynamic>{
      'from': [
        {'collectionId': 'hourly'},
      ],
      'where': {
        'fieldFilter': {
          'field': {'fieldPath': 'timestampHourStart'},
          'op': 'LESS_THAN',
          'value': {'timestampValue': _cutoffUtcExclusive.toIso8601String()},
        },
      },
      'orderBy': [
        {
          'field': {'fieldPath': 'timestampHourStart'},
          'direction': 'ASCENDING',
        },
      ],
      'limit': pageSize,
      if (cursorIso != null)
        'startAt': {
          'values': [
            {'timestampValue': cursorIso},
          ],
          'before': false,
        },
    };

    final body = await _runQuery(
      client,
      projectId,
      accessToken,
      parent,
      structuredQuery,
    );
    if (body.isEmpty) break;

    for (final entry in body) {
      final doc = entry['document'];
      if (doc == null) continue; // entradas de solo "progreso", sin doc.
      final fields = (doc['fields'] as Map<String, dynamic>?) ?? const {};
      final ts = _timestamp(fields['timestampHourStart']);
      if (ts == null) continue;
      final avg = _double(fields['avgTemp']);
      final samples = _int(fields['samplesCount']) ?? 0;
      points.add(
        HistoricalExportPoint(ts, {
          if (avg != null) 'temperature': {'avg': avg, 'sampleCount': samples},
        }),
      );
    }

    if (body.length < pageSize) break;
    final lastDoc = body.last['document'];
    final lastFields = (lastDoc['fields'] as Map<String, dynamic>?) ?? const {};
    final lastTs = _timestamp(lastFields['timestampHourStart']);
    if (lastTs == null) break;
    cursorIso = lastTs.toIso8601String();
  }

  return points;
}

Future<List<Map<String, dynamic>>> _runQuery(
  HttpClient client,
  String projectId,
  String accessToken,
  String parentPath,
  Map<String, dynamic> structuredQuery,
) async {
  final uri = Uri.parse(
    'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$parentPath:runQuery',
  );
  final request = await client.postUrl(uri);
  request.headers.set('Authorization', 'Bearer $accessToken');
  request.headers.set('Content-Type', 'application/json');
  request.write(jsonEncode({'structuredQuery': structuredQuery}));
  final response = await request.close();
  final responseBody = await response.transform(utf8.decoder).join();
  if (response.statusCode != 200) {
    throw StateError('runQuery $parentPath failed (${response.statusCode}): $responseBody');
  }
  final decoded = jsonDecode(responseBody) as List<dynamic>;
  return decoded.cast<Map<String, dynamic>>();
}

DateTime? _timestamp(Object? value) {
  if (value is Map && value['timestampValue'] is String) {
    return DateTime.parse(value['timestampValue'] as String).toUtc();
  }
  return null;
}

double? _double(Object? value) {
  if (value is Map) {
    if (value['doubleValue'] is num) return (value['doubleValue'] as num).toDouble();
    if (value['integerValue'] != null) {
      return double.tryParse(value['integerValue'].toString());
    }
  }
  return null;
}

int? _int(Object? value) {
  if (value is Map && value['integerValue'] != null) {
    return int.tryParse(value['integerValue'].toString());
  }
  return null;
}

Future<String> _getAccessToken(Map<String, dynamic> serviceAccount) async {
  final String clientEmail = serviceAccount['client_email'] as String;
  final String privateKey = serviceAccount['private_key'] as String;
  final int now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

  final String header = _b64Url(
    utf8.encode(jsonEncode({'alg': 'RS256', 'typ': 'JWT'})),
  );
  final String claim = _b64Url(
    utf8.encode(
      jsonEncode({
        'iss': clientEmail,
        'scope': 'https://www.googleapis.com/auth/datastore',
        'aud': 'https://oauth2.googleapis.com/token',
        'iat': now,
        'exp': now + 3600,
      }),
    ),
  );
  final String signingInput = '$header.$claim';

  final Directory tempDir = await Directory.systemTemp.createTemp(
    'export-legacy-temp-',
  );
  final File keyFile = File('${tempDir.path}/sa_key.pem');
  try {
    await keyFile.writeAsString(privateKey);
    final Process process = await Process.start('openssl', [
      'dgst',
      '-sha256',
      '-sign',
      keyFile.path,
    ]);
    process.stdin.add(utf8.encode(signingInput));
    await process.stdin.close();
    final List<int> signatureBytes = await process.stdout.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
    final int exit = await process.exitCode;
    if (exit != 0) {
      throw StateError('openssl signing failed with exit code $exit');
    }
    final String jwt = '$signingInput.${_b64Url(signatureBytes)}';

    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest tokenRequest = await client.postUrl(
        Uri.parse('https://oauth2.googleapis.com/token'),
      );
      tokenRequest.headers.set(
        'Content-Type',
        'application/x-www-form-urlencoded',
      );
      tokenRequest.write(
        'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=$jwt',
      );
      final HttpClientResponse tokenResponse = await tokenRequest.close();
      final String tokenBody = await tokenResponse
          .transform(utf8.decoder)
          .join();
      if (tokenResponse.statusCode != 200) {
        throw StateError(
          'Token exchange failed: (status ${tokenResponse.statusCode}): $tokenBody',
        );
      }
      final Map<String, dynamic> tokenJson =
          jsonDecode(tokenBody) as Map<String, dynamic>;
      return tokenJson['access_token'] as String;
    } finally {
      client.close(force: true);
    }
  } finally {
    await tempDir.delete(recursive: true);
  }
}

String _b64Url(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}
