// ignore_for_file: avoid_relative_lib_imports
//
// Lectura puntual de un documento Firestore (solo lectura, sin escritura).
// Usado para depurar el CONFLICT detectado en el idempotency check de B6.2.
//
// Uso:
//   dart run tool/inspect_b6_2_doc.dart <path/al/doc>

import 'dart:convert';
import 'dart:io';

const String _defaultServiceAccountPath = 'backend/config/service-account.json';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Uso: dart run tool/inspect_b6_2_doc.dart <path/al/doc>');
    exit(64);
  }
  final String docPath = args.first;
  final Map<String, dynamic> serviceAccount =
      jsonDecode(File(_defaultServiceAccountPath).readAsStringSync())
          as Map<String, dynamic>;
  final String projectId = serviceAccount['project_id'] as String;
  final String token = await _getAccessToken(serviceAccount);
  final HttpClient client = HttpClient();

  final HttpClientRequest req = await client.getUrl(
    Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$docPath',
    ),
  );
  req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  final HttpClientResponse resp = await req.close();
  final String body = await resp.transform(utf8.decoder).join();
  stdout.writeln('status=${resp.statusCode}');
  final dynamic decoded = jsonDecode(body);
  const JsonEncoder encoder = JsonEncoder.withIndent('  ');
  stdout.writeln(encoder.convert(decoded));

  // Mostrar tambien los code units del displayName para detectar
  // diferencias de normalizacion Unicode (NFC vs NFD) que no se ven a
  // simple vista en la terminal.
  if (decoded is Map && decoded['fields'] is Map) {
    final Map fields = decoded['fields'] as Map;
    final Object? displayNameField = fields['displayName'];
    if (displayNameField is Map && displayNameField['stringValue'] is String) {
      final String s = displayNameField['stringValue'] as String;
      stdout.writeln('displayName="$s" codeUnits=${s.codeUnits}');
    }
  }

  client.close(force: true);
}

Future<String> _getAccessToken(Map<String, dynamic> serviceAccount) async {
  final String clientEmail = serviceAccount['client_email'] as String;
  final String privateKey = serviceAccount['private_key'] as String;
  final int now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

  final String header = _b64Url(
    utf8.encode(jsonEncode(<String, Object?>{'alg': 'RS256', 'typ': 'JWT'})),
  );
  final String claim = _b64Url(
    utf8.encode(
      jsonEncode(<String, Object?>{
        'iss': clientEmail,
        'scope':
            'https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/cloud-platform',
        'aud': 'https://oauth2.googleapis.com/token',
        'iat': now,
        'exp': now + 3600,
      }),
    ),
  );
  final String signingInput = '$header.$claim';

  final Directory tempDir = await Directory.systemTemp.createTemp(
    'b6-2-inspect-',
  );
  final File keyFile = File('${tempDir.path}/sa_key.pem');
  try {
    await keyFile.writeAsString(privateKey);
    final Process process = await Process.start('openssl', <String>[
      'dgst',
      '-sha256',
      '-sign',
      keyFile.path,
    ]);
    process.stdin.add(utf8.encode(signingInput));
    await process.stdin.close();
    final List<int> signatureBytes = await process.stdout.fold<List<int>>(
      <int>[],
      (List<int> acc, List<int> chunk) => acc..addAll(chunk),
    );
    final String stderrText = await process.stderr
        .transform(utf8.decoder)
        .join();
    final int exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw StateError('openssl signing failed exit=$exitCode $stderrText');
    }
    final String jwt = '$signingInput.${_b64Url(signatureBytes)}';
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.postUrl(
        Uri.parse('https://oauth2.googleapis.com/token'),
      );
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/x-www-form-urlencoded',
      );
      request.write(
        'grant_type=${Uri.encodeComponent('urn:ietf:params:oauth:grant-type:jwt-bearer')}'
        '&assertion=${Uri.encodeComponent(jwt)}',
      );
      final HttpClientResponse response = await request.close();
      final String body = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('token exchange failed ${response.statusCode}: $body');
      }
      final Map<String, dynamic> json =
          jsonDecode(body) as Map<String, dynamic>;
      final String? token = json['access_token'] as String?;
      if (token == null || token.isEmpty) {
        throw StateError('token exchange response missing access_token');
      }
      return token;
    } finally {
      client.close(force: true);
    }
  } finally {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

String _b64Url(List<int> bytes) {
  return base64UrlEncode(bytes).replaceAll('=', '');
}
