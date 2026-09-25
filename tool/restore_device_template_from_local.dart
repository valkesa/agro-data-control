// ignore_for_file: avoid_print
//
// Restaura un único deviceTemplates/{id} desde la definición local incluida en
// la app. Preserva metadata operativa del documento remoto existente
// (createdAt/enabled/description/tags) e incrementa templateVersion.
//
// Uso:
//   dart run tool/restore_device_template_from_local.dart disinfection_arch --confirm

import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control/ui_templates/catalog/agro_ui_templates.dart';
import 'package:agro_data_control/ui_templates/models/device_template.dart';

const int _schemaVersion = 1;
const String _serviceAccountPath = 'backend/config/service-account.json';

Future<void> main(List<String> args) async {
  if (args.length != 2 || args[1] != '--confirm') {
    stderr.writeln(
      'Uso: dart run tool/restore_device_template_from_local.dart <templateId> --confirm',
    );
    exit(64);
  }

  final String templateId = args.first;
  final DeviceTemplate? template = getTemplateById(templateId);
  if (template == null) {
    stderr.writeln('Template local inexistente: $templateId');
    exit(66);
  }

  final Map<String, dynamic> serviceAccount =
      jsonDecode(File(_serviceAccountPath).readAsStringSync())
          as Map<String, dynamic>;
  final String projectId = serviceAccount['project_id'] as String;
  final String accessToken = await _getAccessToken(serviceAccount);
  final HttpClient client = HttpClient();

  try {
    final String path = 'deviceTemplates/$templateId';
    final _Doc? existing = await _getDoc(client, projectId, accessToken, path);
    final int previousTemplateVersion = existing == null
        ? 0
        : _int(existing.fields['templateVersion']) ?? 0;
    final int nextTemplateVersion = previousTemplateVersion + 1;
    final DateTime now = DateTime.now().toUtc();

    final Map<String, Object?> envelope = <String, Object?>{
      ...template.toMap(),
      'schemaVersion': _schemaVersion,
      'templateVersion': nextTemplateVersion,
      'enabled': _bool(existing?.fields['enabled']) ?? true,
      'createdAt': existing == null
          ? now
          : _DoNotEncode(existing.fields['createdAt']),
      'updatedAt': now,
      if (_string(existing?.fields['description']) case final String value)
        'description': value,
      'tags': _strings(existing?.fields['tags']),
    };

    await _putDoc(client, projectId, accessToken, path, envelope);
    print(
      'RESTORED $templateId templateVersion '
      '$previousTemplateVersion -> $nextTemplateVersion',
    );
    print('name=${template.name}');
    print('tableSection=${template.tableSection}');
  } finally {
    client.close(force: true);
  }
}

class _DoNotEncode {
  const _DoNotEncode(this.rawFirestoreValue);
  final Object? rawFirestoreValue;
}

class _Doc {
  const _Doc({required this.id, required this.fields});
  final String id;
  final Map<String, dynamic> fields;
}

int? _int(dynamic value) {
  if (value is Map && value['integerValue'] != null) {
    return int.tryParse(value['integerValue'].toString());
  }
  return null;
}

bool? _bool(dynamic value) {
  if (value is Map && value['booleanValue'] is bool) {
    return value['booleanValue'] as bool;
  }
  return null;
}

String? _string(dynamic value) {
  if (value is Map && value['stringValue'] is String) {
    final String raw = (value['stringValue'] as String).trim();
    return raw.isEmpty ? null : raw;
  }
  return null;
}

List<String> _strings(dynamic value) {
  if (value is! Map) return const <String>[];
  final dynamic arrayValue = value['arrayValue'];
  if (arrayValue is! Map) return const <String>[];
  final dynamic values = arrayValue['values'];
  if (values is! List) return const <String>[];
  return <String>[
    for (final dynamic entry in values)
      if (_string(entry) case final String value) value,
  ];
}

Map<String, dynamic> _encodeFirestoreValue(Object? value) {
  if (value is _DoNotEncode) {
    return (value.rawFirestoreValue as Map?)?.cast<String, dynamic>() ??
        _encodeFirestoreValue(null);
  }
  if (value == null) return <String, dynamic>{'nullValue': null};
  if (value is bool) return <String, dynamic>{'booleanValue': value};
  if (value is int) return <String, dynamic>{'integerValue': value.toString()};
  if (value is double) return <String, dynamic>{'doubleValue': value};
  if (value is DateTime) {
    return <String, dynamic>{'timestampValue': value.toUtc().toIso8601String()};
  }
  if (value is String) return <String, dynamic>{'stringValue': value};
  if (value is Iterable) {
    return <String, dynamic>{
      'arrayValue': <String, dynamic>{
        'values': <Map<String, dynamic>>[
          for (final Object? item in value) _encodeFirestoreValue(item),
        ],
      },
    };
  }
  if (value is Map) {
    return <String, dynamic>{
      'mapValue': <String, dynamic>{
        'fields': <String, dynamic>{
          for (final MapEntry<Object?, Object?> entry in value.entries)
            entry.key.toString(): _encodeFirestoreValue(entry.value),
        },
      },
    };
  }
  throw ArgumentError.value(
    value,
    'value',
    'Unsupported type for Firestore encoding',
  );
}

Future<_Doc?> _getDoc(
  HttpClient client,
  String projectId,
  String accessToken,
  String path,
) async {
  final Uri uri = Uri.parse(
    'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$path',
  );
  final HttpClientRequest request = await client.getUrl(uri);
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
  final HttpClientResponse response = await request.close();
  final String body = await response.transform(utf8.decoder).join();
  if (response.statusCode == HttpStatus.notFound) return null;
  if (response.statusCode != HttpStatus.ok) {
    throw StateError('GET $path failed ${response.statusCode}: $body');
  }
  final Map<String, dynamic> json = jsonDecode(body) as Map<String, dynamic>;
  return _Doc(
    id: (json['name'] as String).split('/').last,
    fields: (json['fields'] as Map<String, dynamic>?) ?? <String, dynamic>{},
  );
}

Future<void> _putDoc(
  HttpClient client,
  String projectId,
  String accessToken,
  String path,
  Map<String, Object?> fields,
) async {
  final Uri uri = Uri.parse(
    'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$path',
  );
  final HttpClientRequest request = await client.openUrl('PATCH', uri);
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
  request.headers.set(
    HttpHeaders.contentTypeHeader,
    'application/json; charset=utf-8',
  );
  request.add(
    utf8.encode(
      jsonEncode(<String, Object?>{
        'fields': <String, Object?>{
          for (final MapEntry<String, Object?> entry in fields.entries)
            entry.key: _encodeFirestoreValue(entry.value),
        },
      }),
    ),
  );
  final HttpClientResponse response = await request.close();
  final String body = await response.transform(utf8.decoder).join();
  if (response.statusCode != HttpStatus.ok) {
    throw StateError('PATCH $path failed ${response.statusCode}: $body');
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
        'scope': 'https://www.googleapis.com/auth/datastore',
        'aud': 'https://oauth2.googleapis.com/token',
        'iat': now,
        'exp': now + 3600,
      }),
    ),
  );
  final String signingInput = '$header.$claim';
  final Directory tempDir = await Directory.systemTemp.createTemp(
    'restore-device-template-',
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
        HttpHeaders.contentTypeHeader,
        'application/x-www-form-urlencoded',
      );
      tokenRequest.write(
        'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=$jwt',
      );
      final HttpClientResponse tokenResponse = await tokenRequest.close();
      final String tokenBody = await tokenResponse
          .transform(utf8.decoder)
          .join();
      if (tokenResponse.statusCode != HttpStatus.ok) {
        throw StateError(
          'Token exchange failed: status ${tokenResponse.statusCode}',
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
