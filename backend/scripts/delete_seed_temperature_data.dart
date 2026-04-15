// Script de limpieza: borra los 3 registros horarios y el diario de prueba
// que se grabaron con seed_temperature_data.dart el 2026-04-13.
//
// Uso:
//   cd backend
//   dart scripts/delete_seed_temperature_data.dart

import 'dart:io';

import 'package:agro_data_control_backend/src/service_account_auth.dart';

const String _projectId = 'agro-data-control';
const String _databaseId = '(default)';
const String _basePath =
    'tenants/the-gene-pig/sites/genetica-1/plcs/munters2/metrics/temperature';

final List<String> _documentPaths = <String>[
  '$_basePath/hourly/20260413_08',
  '$_basePath/hourly/20260413_12',
  '$_basePath/hourly/20260413_17',
  '$_basePath/daily/2026-04-13',
];

void main() async {
  stdout.writeln('=== delete_seed_temperature_data ===');
  stdout.writeln('Borrando ${_documentPaths.length} documentos de prueba...\n');

  final String scriptDir = File(Platform.script.toFilePath()).parent.parent.path;
  final String serviceAccountPath = '$scriptDir/config/service-account.json';

  final ServiceAccountAuth auth = ServiceAccountAuth(
    serviceAccountJsonPath: serviceAccountPath,
  );

  final HttpClient client = HttpClient();
  try {
    for (final String docPath in _documentPaths) {
      stdout.write('Borrando $docPath ... ');
      try {
        final String token = await auth.getAccessToken();
        final Uri uri = Uri.parse(
          'https://firestore.googleapis.com/v1/projects/$_projectId'
          '/databases/$_databaseId/documents/$docPath',
        );
        final HttpClientRequest request = await client.openUrl('DELETE', uri);
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        final HttpClientResponse response = await request.close();
        await response.drain<void>();

        if (response.statusCode == HttpStatus.ok ||
            response.statusCode == HttpStatus.notFound) {
          stdout.writeln('OK');
        } else {
          stdout.writeln('ERROR status=${response.statusCode}');
        }
      } on Object catch (e) {
        stdout.writeln('ERROR: $e');
      }
    }
  } finally {
    client.close(force: true);
  }

  stdout.writeln('\n✓ Limpieza completada.');
}
