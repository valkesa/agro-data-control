// Etapa 5B — ONE-TIME, hardcoded maintenance script. NOT a general
// migration tool: every id is hardcoded (see
// lib/services/la_payana_normalization.dart), and every precondition is
// validated before any write. Run with:
//
//   dart run tool/normalize_la_payana_device.dart
//
// Requires backend/config/service-account.json (already used elsewhere in
// this repo for read-only Firestore verification via REST — this is the
// one place in the project that also uses it to WRITE, and only ever to
// this single hardcoded document). Uses only `dart:core`/`dart:io`/
// `dart:convert` plus the pure validation logic in
// lib/services/la_payana_normalization.dart — deliberately no
// `cloud_firestore`/Flutter import, since a plain `dart run` script cannot
// load Flutter plugins.
//
// Never prints the service account contents, tokens, or any credential.

import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control/services/la_payana_normalization.dart';

Future<void> main() async {
  print(
    '=== Etapa 5B — normalización La Payana '
    '(tenant=$laPayanaTenantId site=$laPayanaSiteId device=$laPayanaDeviceId) ===',
  );

  final Map<String, dynamic> serviceAccount =
      jsonDecode(File('backend/config/service-account.json').readAsStringSync())
          as Map<String, dynamic>;
  final String projectId = serviceAccount['project_id'] as String;
  final String accessToken = await _getAccessToken(serviceAccount);
  final HttpClient client = HttpClient();

  try {
    // A. Lectura y snapshot previo.
    final _Doc? tenant = await _getDoc(
      client,
      projectId,
      accessToken,
      'tenants/$laPayanaTenantId',
    );
    final _Doc? site = await _getDoc(
      client,
      projectId,
      accessToken,
      'tenants/$laPayanaTenantId/sites/$laPayanaSiteId',
    );
    final _Doc? sector = await _getDoc(
      client,
      projectId,
      accessToken,
      'tenants/$laPayanaTenantId/sectors/$laPayanaSectorId',
    );
    final _Doc? device = await _getDoc(
      client,
      projectId,
      accessToken,
      'tenants/$laPayanaTenantId/devices/$laPayanaDeviceId',
    );
    final List<_Doc> roomDocs = await _listCollection(
      client,
      projectId,
      accessToken,
      'tenants/$laPayanaTenantId/devices/$laPayanaDeviceId/rooms',
    );

    final List<String> currentSectorIds = device == null
        ? const <String>[]
        : _stringList(device.fields['sectorIds']);
    final List<LaPayanaRoomSnapshot> rooms = [
      for (final _Doc room in roomDocs)
        LaPayanaRoomSnapshot(
          id: room.id,
          snapshotUnitKey: _string(room.fields['snapshotUnitKey']),
        ),
    ];

    // B. Validación completa — nada se escribe si esto falla.
    final LaPayanaValidationResult validation = validateLaPayanaNormalization(
      LaPayanaNormalizationInput(
        tenantExists: tenant != null,
        siteExists: site != null,
        sectorExists: sector != null,
        sectorSiteId: sector == null ? null : _string(sector.fields['siteId']),
        deviceExists: device != null,
        deviceSiteId: device == null ? null : _string(device.fields['siteId']),
        deviceType: device == null ? null : _string(device.fields['type']),
        deviceSectorIds: currentSectorIds,
        rooms: rooms,
      ),
    );

    if (!validation.isValid) {
      stderr.writeln('ABORTADO: ${validation.error}');
      exitCode = 1;
      return;
    }
    print('Validación completa: tenant/site/sector/device/8 rooms OK.');

    if (validation.alreadyNormalized) {
      print(
        'El device ya tiene type=$laPayanaNewType y '
        'sectorIds=[$laPayanaSectorId] — sin cambios.',
      );
      return;
    }

    print('--- ANTES ---');
    print('type: ${_string(device!.fields['type'])}');
    print('sectorIds: $currentSectorIds');

    // C. Actualización parcial — SOLO type/sectorIds/updatedAt
    // (laPayanaNormalizationUpdateMask), nunca las rooms.
    await _patchDoc(
      client,
      projectId,
      accessToken,
      'tenants/$laPayanaTenantId/devices/$laPayanaDeviceId',
      updateMask: laPayanaNormalizationUpdateMask,
      fields: {
        'type': {'stringValue': laPayanaNewType},
        'sectorIds': {
          'arrayValue': {
            'values': [
              {'stringValue': laPayanaSectorId},
            ],
          },
        },
        'updatedAt': {
          'timestampValue': DateTime.now().toUtc().toIso8601String(),
        },
      },
    );
    print('Update aplicado (updateMask: $laPayanaNormalizationUpdateMask).');

    // D. Relectura del device.
    final _Doc deviceAfter = (await _getDoc(
      client,
      projectId,
      accessToken,
      'tenants/$laPayanaTenantId/devices/$laPayanaDeviceId',
    ))!;
    print('--- DESPUÉS ---');
    print('type: ${_string(deviceAfter.fields['type'])}');
    print('sectorIds: ${_stringList(deviceAfter.fields['sectorIds'])}');

    // E. Relectura de las 8 rooms + F. comparación antes/después.
    final List<_Doc> roomDocsAfter = await _listCollection(
      client,
      projectId,
      accessToken,
      'tenants/$laPayanaTenantId/devices/$laPayanaDeviceId/rooms',
    );
    if (roomDocsAfter.length != laPayanaExpectedRoomCount) {
      stderr.writeln(
        'POST-CHECK FALLÓ: cantidad de rooms cambió a ${roomDocsAfter.length}.',
      );
      exitCode = 1;
      return;
    }
    final Map<String, _Doc> roomsByIdBefore = {
      for (final _Doc r in roomDocs) r.id: r,
    };
    final Map<String, _Doc> roomsByIdAfter = {
      for (final _Doc r in roomDocsAfter) r.id: r,
    };
    for (final String id in laPayanaExpectedRoomIds) {
      final _Doc before = roomsByIdBefore[id]!;
      final _Doc after = roomsByIdAfter[id]!;
      for (final String field in [
        'name',
        'enabled',
        'sortOrder',
        'snapshotUnitKey',
        'createdAt',
      ]) {
        final String beforeVal = jsonEncode(before.fields[field]);
        final String afterVal = jsonEncode(after.fields[field]);
        if (beforeVal != afterVal) {
          stderr.writeln(
            'POST-CHECK FALLÓ: room "$id".$field cambió '
            '($beforeVal -> $afterVal).',
          );
          exitCode = 1;
          return;
        }
      }
    }
    print('Post-check de las 8 rooms: sin cambios, OK.');

    for (final String field in [
      'siteId',
      'name',
      'model',
      'description',
      'enabled',
      'sortOrder',
      'createdAt',
    ]) {
      final String beforeVal = jsonEncode(device.fields[field]);
      final String afterVal = jsonEncode(deviceAfter.fields[field]);
      if (beforeVal != afterVal) {
        stderr.writeln(
          'POST-CHECK FALLÓ: device.$field cambió ($beforeVal -> $afterVal).',
        );
        exitCode = 1;
        return;
      }
    }
    print('Post-check de campos no tocados del device: OK.');
    print('=== Normalización completa ===');
  } finally {
    client.close(force: true);
  }
}

class _Doc {
  _Doc({required this.id, required this.fields});
  final String id;
  final Map<String, dynamic> fields;
}

String? _string(dynamic value) {
  if (value is Map && value['stringValue'] is String) {
    return value['stringValue'] as String;
  }
  return null;
}

List<String> _stringList(dynamic value) {
  if (value is Map && value['arrayValue'] is Map) {
    final List<dynamic> values =
        (value['arrayValue'] as Map)['values'] as List<dynamic>? ?? const [];
    return [
      for (final v in values)
        if (_string(v) != null) _string(v)!,
    ];
  }
  return const <String>[];
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

Future<List<_Doc>> _listCollection(
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
  if (response.statusCode != 200) {
    throw StateError('GET $path failed (${response.statusCode}): $body');
  }
  final Map<String, dynamic> json = jsonDecode(body) as Map<String, dynamic>;
  final List<dynamic> docs = (json['documents'] as List<dynamic>?) ?? const [];
  return [
    for (final d in docs)
      _Doc(
        id: ((d as Map<String, dynamic>)['name'] as String).split('/').last,
        fields: (d['fields'] as Map<String, dynamic>?) ?? const {},
      ),
  ];
}

Future<void> _patchDoc(
  HttpClient client,
  String projectId,
  String accessToken,
  String path, {
  required List<String> updateMask,
  required Map<String, dynamic> fields,
}) async {
  final String maskQuery = updateMask
      .map((f) => 'updateMask.fieldPaths=$f')
      .join('&');
  final Uri uri = Uri.parse(
    'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$path'
    '?$maskQuery&currentDocument.exists=true',
  );
  final HttpClientRequest request = await client.openUrl('PATCH', uri);
  request.headers.set('Authorization', 'Bearer $accessToken');
  request.headers.set('Content-Type', 'application/json');
  request.write(jsonEncode({'fields': fields}));
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
    'la-payana-normalize-',
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
