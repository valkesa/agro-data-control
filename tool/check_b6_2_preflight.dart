// ignore_for_file: avoid_relative_lib_imports
//
// Etapa B6.2 — preflight de solo lectura contra produccion.
//
// Verifica, SIN escribir nada:
//   1. Que el ruleset de Firestore actualmente publicado (no el archivo
//      local) contenga bloques match /alertConfig/ y match /alertRecipients/.
//   2. El UID real del usuario admin (por email) en la coleccion `users`,
//      para poder pasar --admin-uid <UID_REAL> al migrador (nunca inventado).
//
// Uso:
//   dart run tool/check_b6_2_preflight.dart --email <email>

import 'dart:convert';
import 'dart:io';

const String _defaultServiceAccountPath = 'backend/config/service-account.json';

Future<void> main(List<String> args) async {
  String email = '';
  String serviceAccountPath = _defaultServiceAccountPath;
  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--email') {
      i += 1;
      email = i < args.length ? args[i] : '';
    } else if (args[i] == '--service-account') {
      i += 1;
      serviceAccountPath = i < args.length ? args[i] : serviceAccountPath;
    }
  }
  if (email.isEmpty) {
    stderr.writeln(
      'Uso: dart run tool/check_b6_2_preflight.dart --email <email>',
    );
    exit(64);
  }

  final Map<String, dynamic> serviceAccount =
      jsonDecode(File(serviceAccountPath).readAsStringSync())
          as Map<String, dynamic>;
  final String projectId = serviceAccount['project_id'] as String;
  final String token = await _getAccessToken(serviceAccount);
  final HttpClient client = HttpClient();

  stdout.writeln('== A. Rules publicadas (produccion, proyecto=$projectId) ==');
  await _checkRules(client, projectId, token);

  stdout.writeln('');
  stdout.writeln('== B. Resolver admin UID por email=$email ==');
  await _resolveAdminUid(client, projectId, token, email);

  client.close(force: true);
}

Future<void> _checkRules(
  HttpClient client,
  String projectId,
  String token,
) async {
  final HttpClientRequest releaseReq = await client.getUrl(
    Uri.parse(
      'https://firebaserules.googleapis.com/v1/projects/$projectId/releases/cloud.firestore',
    ),
  );
  releaseReq.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  final HttpClientResponse releaseResp = await releaseReq.close();
  final String releaseBody = await releaseResp.transform(utf8.decoder).join();
  if (releaseResp.statusCode != HttpStatus.ok) {
    stdout.writeln(
      'ERROR leyendo release: ${releaseResp.statusCode} $releaseBody',
    );
    return;
  }
  final Map<String, dynamic> releaseJson =
      jsonDecode(releaseBody) as Map<String, dynamic>;
  final String rulesetName = releaseJson['rulesetName'] as String;
  final String updateTime = releaseJson['updateTime']?.toString() ?? '';
  stdout.writeln('rulesetName=$rulesetName');
  stdout.writeln('release.updateTime=$updateTime');

  final HttpClientRequest rulesetReq = await client.getUrl(
    Uri.parse('https://firebaserules.googleapis.com/v1/$rulesetName'),
  );
  rulesetReq.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  final HttpClientResponse rulesetResp = await rulesetReq.close();
  final String rulesetBody = await rulesetResp.transform(utf8.decoder).join();
  if (rulesetResp.statusCode != HttpStatus.ok) {
    stdout.writeln(
      'ERROR leyendo ruleset: ${rulesetResp.statusCode} $rulesetBody',
    );
    return;
  }
  final Map<String, dynamic> rulesetJson =
      jsonDecode(rulesetBody) as Map<String, dynamic>;
  final Map<String, dynamic> source =
      rulesetJson['source'] as Map<String, dynamic>;
  final List<dynamic> files = source['files'] as List<dynamic>;
  final String content = files
      .map((f) => (f as Map)['content'] as String)
      .join('\n');
  final int alertConfigMatches = 'match /alertConfig/'
      .allMatches(content)
      .length;
  final int alertRecipientsMatches = 'match /alertRecipients/'
      .allMatches(content)
      .length;
  stdout.writeln('createTime=${rulesetJson['createTime']}');
  stdout.writeln(
    'match /alertConfig/{...} bloques encontrados=$alertConfigMatches',
  );
  stdout.writeln(
    'match /alertRecipients/{...} bloques encontrados=$alertRecipientsMatches',
  );
  stdout.writeln(
    (alertConfigMatches > 0 && alertRecipientsMatches > 0)
        ? 'RESULTADO: RULES B4/B4.5 DESPLEGADAS EN PRODUCCION'
        : 'RESULTADO: RULES NO CONTIENEN alertConfig/alertRecipients — DETENER B6.2',
  );
}

Future<void> _resolveAdminUid(
  HttpClient client,
  String projectId,
  String token,
  String email,
) async {
  final Uri uri = Uri.parse(
    'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents:runQuery',
  );
  final HttpClientRequest req = await client.postUrl(uri);
  req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
  req.write(
    jsonEncode(<String, Object?>{
      'structuredQuery': <String, Object?>{
        'from': <Object?>[
          <String, Object?>{'collectionId': 'users'},
        ],
        'where': <String, Object?>{
          'fieldFilter': <String, Object?>{
            'field': <String, Object?>{'fieldPath': 'email'},
            'op': 'EQUAL',
            'value': <String, Object?>{'stringValue': email},
          },
        },
        'limit': 5,
      },
    }),
  );
  final HttpClientResponse resp = await req.close();
  final String body = await resp.transform(utf8.decoder).join();
  if (resp.statusCode != HttpStatus.ok) {
    stdout.writeln('ERROR runQuery users: ${resp.statusCode} $body');
    return;
  }
  final List<dynamic> rows = jsonDecode(body) as List<dynamic>;
  final List<String> uids = <String>[];
  for (final dynamic row in rows) {
    final Map<String, dynamic>? doc =
        (row as Map<String, dynamic>)['document'] as Map<String, dynamic>?;
    if (doc == null) continue;
    final String name = doc['name'] as String;
    uids.add(name.split('/').last);
  }
  if (uids.isEmpty) {
    stdout.writeln(
      'RESULTADO: no se encontro ningun users/{uid} con email=$email',
    );
  } else if (uids.length > 1) {
    stdout.writeln(
      'RESULTADO: AMBIGUO — multiples UID para email=$email: ${uids.join(', ')}',
    );
  } else {
    stdout.writeln('RESULTADO: admin-uid=${uids.single}');
  }
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
            'https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/firebase',
        'aud': 'https://oauth2.googleapis.com/token',
        'iat': now,
        'exp': now + 3600,
      }),
    ),
  );
  final String signingInput = '$header.$claim';

  final Directory tempDir = await Directory.systemTemp.createTemp(
    'b6-2-preflight-',
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
