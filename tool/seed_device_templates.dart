// Etapa 6A — seeds the 3 local DeviceTemplates (room_climate,
// laboratory_basic, disinfection_arch) into Firestore's `deviceTemplates`
// collection, so DeviceTemplateRegistry has something to load once the app
// is wired up to prefer remote over local.
//
// Run with:
//   dart run tool/seed_device_templates.dart               # non-destructive
//   dart run tool/seed_device_templates.dart --overwrite    # bumps existing docs
//
// Non-destructive by default (Etapa 6A §16): a template that already exists
// in Firestore is left untouched and skipped, unless --overwrite is passed.
//
// Same pattern as tool/normalize_la_payana_device.dart (the only other
// Firestore-writing script in this repo): plain `dart run`, no
// `cloud_firestore`/Flutter import (a pure-Dart script cannot load Flutter
// plugins), reads backend/config/service-account.json, talks to the
// Firestore REST API directly via dart:io HttpClient. Unlike that script,
// this one writes a nested structure (metrics/boardSlots/tableColumns
// arrays of maps) — see `_encodeFirestoreValue`, a small generic Dart-value
// -> Firestore-REST-typed-JSON encoder that didn't exist anywhere in this
// repo before (the existing script only ever hand-wrote a couple of
// scalar/array-of-string fields).
//
// Never prints the service account contents, tokens, or any credential.

import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control/ui_templates/catalog/agro_ui_templates.dart';
import 'package:agro_data_control/ui_templates/models/device_template.dart';

const int _schemaVersion = 1;

Future<void> main(List<String> args) async {
  final bool overwrite = args.contains('--overwrite');
  print('=== Etapa 6A — seed de deviceTemplates (overwrite=$overwrite) ===');

  final Map<String, dynamic> serviceAccount =
      jsonDecode(File('backend/config/service-account.json').readAsStringSync())
          as Map<String, dynamic>;
  final String projectId = serviceAccount['project_id'] as String;
  final String accessToken = await _getAccessToken(serviceAccount);
  final HttpClient client = HttpClient();

  try {
    for (final DeviceTemplate template in agroUiTemplates) {
      await _seedOne(
        client: client,
        projectId: projectId,
        accessToken: accessToken,
        template: template,
        overwrite: overwrite,
      );
    }
    print('=== Seed completo ===');
  } finally {
    client.close(force: true);
  }
}

Future<void> _seedOne({
  required HttpClient client,
  required String projectId,
  required String accessToken,
  required DeviceTemplate template,
  required bool overwrite,
}) async {
  final String path = 'deviceTemplates/${template.id}';
  final _Doc? existing = await _getDoc(client, projectId, accessToken, path);

  if (existing != null && !overwrite) {
    print('SKIP ${template.id}: ya existe (usá --overwrite para pisarlo).');
    return;
  }

  final int previousTemplateVersion = existing == null
      ? 0
      : _int(existing.fields['templateVersion']) ?? 0;
  final int templateVersion = previousTemplateVersion + 1;
  final DateTime now = DateTime.now().toUtc();

  final Map<String, Object?> envelope = <String, Object?>{
    ...template.toMap(),
    'schemaVersion': _schemaVersion,
    'templateVersion': templateVersion,
    'enabled': true,
    'createdAt': existing == null
        ? now
        : _DoNotEncode(existing.fields['createdAt']),
    'updatedAt': now,
  };

  await _putDoc(client, projectId, accessToken, path, envelope);
  print(
    existing == null
        ? 'CREADO ${template.id} (schemaVersion=$_schemaVersion, templateVersion=$templateVersion).'
        : 'SOBRESCRITO ${template.id} '
              '(templateVersion $previousTemplateVersion -> $templateVersion).',
  );
}

/// Marker so `createdAt` can reuse the exact previously-stored Firestore
/// value (already REST-typed JSON) instead of re-encoding a parsed
/// DateTime — avoids any precision loss on overwrite.
class _DoNotEncode {
  const _DoNotEncode(this.rawFirestoreValue);
  final Object? rawFirestoreValue;
}

int? _int(dynamic value) {
  if (value is Map && value['integerValue'] != null) {
    return int.tryParse(value['integerValue'].toString());
  }
  return null;
}

/// Recursive Dart value -> Firestore REST typed-value JSON encoder. No
/// generic version of this existed in the repo before this script — see
/// the file header.
Map<String, dynamic> _encodeFirestoreValue(Object? value) {
  if (value is _DoNotEncode) {
    return (value.rawFirestoreValue as Map?)?.cast<String, dynamic>() ??
        _encodeFirestoreValue(null);
  }
  if (value == null) {
    return {'nullValue': null};
  }
  if (value is bool) {
    return {'booleanValue': value};
  }
  if (value is int) {
    return {'integerValue': value.toString()};
  }
  if (value is double) {
    return {'doubleValue': value};
  }
  if (value is DateTime) {
    return {'timestampValue': value.toUtc().toIso8601String()};
  }
  if (value is String) {
    return {'stringValue': value};
  }
  if (value is Iterable) {
    return {
      'arrayValue': {
        'values': [
          for (final Object? item in value) _encodeFirestoreValue(item),
        ],
      },
    };
  }
  if (value is Map) {
    return {
      'mapValue': {
        'fields': {
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

class _Doc {
  _Doc({required this.id, required this.fields});
  final String id;
  final Map<String, dynamic> fields;
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
  request.headers.set('Authorization', 'Bearer $accessToken');
  final HttpClientResponse response = await request.close();
  final String body = await response.transform(utf8.decoder).join();
  if (response.statusCode == 404) return null;
  if (response.statusCode != 200) {
    throw StateError('GET $path failed (${response.statusCode}): $body');
  }
  final Map<String, dynamic> json = jsonDecode(body) as Map<String, dynamic>;
  return _Doc(
    id: (json['name'] as String).split('/').last,
    fields: (json['fields'] as Map<String, dynamic>?) ?? const {},
  );
}

/// Full-document upsert (no `updateMask`): creates the doc if it doesn't
/// exist, otherwise replaces every field with exactly what's given here —
/// intentional for a seed script (the whole envelope is always the single
/// source of truth for this doc), unlike normalize_la_payana_device.dart's
/// `_patchDoc`, which deliberately touches only a few fields on an existing
/// device doc it doesn't fully own.
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
  request.headers.set('Authorization', 'Bearer $accessToken');
  request.headers.set('Content-Type', 'application/json');
  request.write(
    jsonEncode({
      'fields': {
        for (final MapEntry<String, Object?> entry in fields.entries)
          entry.key: _encodeFirestoreValue(entry.value),
      },
    }),
  );
  final HttpClientResponse response = await request.close();
  final String body = await response.transform(utf8.decoder).join();
  if (response.statusCode != 200) {
    throw StateError('PATCH $path failed (${response.statusCode}): $body');
  }
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
    'seed-device-templates-',
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
          'Token exchange failed: (status ${tokenResponse.statusCode})',
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
