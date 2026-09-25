// ignore_for_file: avoid_print
//
// N7.1 §17 — idempotent seed of the 6 new global config collections
// (layoutTemplates, cellLayoutPresets, capabilityMetrics,
// capabilityIndicators, capabilityProfiles, boardPresets) into Firestore
// from this project's reference/default data — a manual/admin action,
// never run automatically on app startup (§17 "no sembrar
// automáticamente en cada arranque").
//
// Run with:
//   dart run tool/seed_n7_1_global_config.dart --dry-run       # preview only, touches nothing
//   dart run tool/seed_n7_1_global_config.dart                 # non-destructive
//   dart run tool/seed_n7_1_global_config.dart --overwrite     # bumps existing docs
//
// Non-destructive by default: a document that already exists in Firestore
// is left untouched and skipped, unless --overwrite is passed (same
// convention as tool/seed_device_templates.dart, which this script mirrors
// for the REST-via-service-account technique and the
// _encodeFirestoreValue/_getAccessToken/_getDoc/_putDoc helpers,
// duplicated rather than shared per that file's own established
// precedent).
//
// IMPORTANT — why this doesn't just import the app's shared in-memory
// stores (`sharedMetricLibraryStore`, `sharedBoardPresetCatalog`, ...):
// every one of them is a `ChangeNotifier`
// (`lib/device_capabilities/capability_library_store.dart`,
// `lib/board_presets/board_preset_catalog.dart`, ...), and importing
// `package:flutter/foundation.dart` — even transitively, even if this
// script never touches a widget — pulls in `dart:ui`, which does not
// exist outside a running Flutter engine and makes the whole file
// impossible to compile under plain `dart run` (verified: attempting it
// fails with "Dart library 'dart:ui' is not available on this
// platform"). This script instead reconstructs the exact same reference
// data these stores seed themselves from
// (`lib/device_metric_catalogs/reference_metric_catalogs.dart`,
// `lib/board_content/reference_content_boards.dart`,
// `lib/device_board_layouts/reference_board_layouts.dart` — all
// genuinely Flutter-free) using the same pure model constructors and the
// same dedup logic as
// `lib/device_capabilities/reference_capability_seeds.dart`'s
// `seedCapabilityLibrariesAndProfiles()` and
// `lib/board_presets/board_preset_catalog.dart`'s `_seedPresets()`,
// duplicated here rather than shared for that reason. If those two
// functions' reference data ever changes, this script's copy must be
// updated to match (there is no way to avoid that duplication while
// keeping this a plain, dependency-light `dart run` script).
//
// Never prints the service account contents, tokens, or any credential.

import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control/board_content/board_content_layout.dart';
import 'package:agro_data_control/board_content/reference_content_boards.dart';
import 'package:agro_data_control/board_presets/board_preset.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_catalog.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_preset.dart';
import 'package:agro_data_control/device_board_layouts/reference_board_layouts.dart';
import 'package:agro_data_control/device_capabilities/capability_indicator_definition.dart';
import 'package:agro_data_control/device_capabilities/capability_metric_definition.dart';
import 'package:agro_data_control/device_capabilities/indicator_binding.dart';
import 'package:agro_data_control/device_capabilities/metric_binding.dart';
import 'package:agro_data_control/device_metric_catalogs/reference_metric_catalogs.dart';
import 'package:agro_data_control/layout_templates/layout_template.dart';
import 'package:agro_data_control/layout_templates/layout_template_catalog.dart';

typedef _PlannedDoc = ({
  String collection,
  String id,
  String versionField,
  Map<String, Object?> fields,
});

Future<void> main(List<String> args) async {
  final bool overwrite = args.contains('--overwrite');
  final bool dryRun = args.contains('--dry-run');
  print(
    '=== N7.1 — seed de config global (overwrite=$overwrite, dry-run=$dryRun) ===',
  );

  final List<_PlannedDoc> planned = _buildPlan();

  if (dryRun) {
    print(
      '--dry-run: no se toca Firestore. ${planned.length} documento(s) '
      'candidatos:',
    );
    for (final item in planned) {
      print('  ${item.collection}/${item.id}');
    }
    print('=== Dry-run completo ===');
    return;
  }

  final Map<String, dynamic> serviceAccount =
      jsonDecode(File('backend/config/service-account.json').readAsStringSync())
          as Map<String, dynamic>;
  final String projectId = serviceAccount['project_id'] as String;
  final String accessToken = await _getAccessToken(serviceAccount);
  final HttpClient client = HttpClient();

  try {
    for (final item in planned) {
      await _seedOne(
        client: client,
        projectId: projectId,
        accessToken: accessToken,
        collection: item.collection,
        id: item.id,
        versionField: item.versionField,
        fields: item.fields,
        overwrite: overwrite,
      );
    }
    print('=== Seed completo ===');
  } finally {
    client.close(force: true);
  }
}

// ---------------------------------------------------------------------
// Reference data reconstruction (Flutter-free duplicate of
// reference_capability_seeds.dart / board_preset_catalog.dart — see the
// file header for why this can't just import those).
// ---------------------------------------------------------------------

List<_PlannedDoc> _buildPlan() {
  final List<_PlannedDoc> planned = [];

  for (final LayoutTemplate template
      in initialLayoutTemplateCatalog.templates) {
    planned.add((
      collection: 'layoutTemplates',
      id: template.id,
      versionField: 'templateVersion',
      fields: template.toMap(),
    ));
  }

  for (final CellLayoutPreset preset in initialCellLayoutCatalog.presets) {
    planned.add((
      collection: 'cellLayoutPresets',
      id: preset.id,
      versionField: 'presetVersion',
      fields: preset.toMap(),
    ));
  }

  final Map<String, CapabilityMetricDefinition> metrics = {};
  final Map<String, CapabilityIndicatorDefinition> indicators = {};
  final List<_ProfileBuilder> profiles = _seedCapabilityProfiles(
    metrics: metrics,
    indicators: indicators,
  );

  for (final metric in metrics.values) {
    planned.add((
      collection: 'capabilityMetrics',
      id: metric.key,
      versionField: 'recordVersion',
      fields: <String, Object?>{...metric.toMap(), 'schemaVersion': 1},
    ));
  }
  for (final indicator in indicators.values) {
    planned.add((
      collection: 'capabilityIndicators',
      id: indicator.key,
      versionField: 'recordVersion',
      fields: <String, Object?>{...indicator.toMap(), 'schemaVersion': 1},
    ));
  }
  for (final profile in profiles) {
    planned.add((
      collection: 'capabilityProfiles',
      id: profile.id,
      versionField: 'profileVersion',
      fields: profile.toMap(),
    ));
  }

  for (final BoardPreset preset in _seedBoardPresets()) {
    planned.add((
      collection: 'boardPresets',
      id: preset.id,
      versionField: 'presetVersion',
      fields: preset.toMap(),
    ));
  }

  return planned;
}

/// Plain-`Map`-building stand-in for `DeviceCapabilityProfile`
/// (`lib/device_capabilities/device_capability_profile.dart`) — that class
/// can't be imported here (see the file header): it imports
/// `capability_library_store.dart` for its `resolve()` method's parameter
/// types alone, which is enough to drag in `dart:ui` transitively. This
/// produces the exact same `toMap()` shape by hand instead.
class _ProfileBuilder {
  _ProfileBuilder({
    required this.id,
    required this.name,
    required this.description,
    required this.enabled,
  });

  final String id;
  final String name;
  final String description;
  final bool enabled;
  final List<String> metricKeys = [];
  final List<String> indicatorKeys = [];
  final Map<String, MetricBinding> metricBindings = {};
  final Map<String, IndicatorBinding> indicatorBindings = {};
  final Map<String, List<String>> suggestedIndicatorsByMetric = {};

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'enabled': enabled,
    'metricKeys': metricKeys,
    'indicatorKeys': indicatorKeys,
    'metricBindings': {
      for (final entry in metricBindings.entries)
        entry.key: entry.value.toMap(),
    },
    'indicatorBindings': {
      for (final entry in indicatorBindings.entries)
        entry.key: entry.value.toMap(),
    },
    'suggestedIndicatorsByMetric': suggestedIndicatorsByMetric,
    'profileVersion': 1,
  };
}

/// Same algorithm as `seedCapabilityLibrariesAndProfiles()` in
/// `reference_capability_seeds.dart`: derives the 3 reference profiles
/// from `referenceMetricCatalogs`, upserting into [metrics]/[indicators]
/// only the first time a key is seen — the same dedup guarantee
/// (`tempInterior`/`humedadInterior` end up as ONE entry each, not
/// duplicated per catalog).
List<_ProfileBuilder> _seedCapabilityProfiles({
  required Map<String, CapabilityMetricDefinition> metrics,
  required Map<String, CapabilityIndicatorDefinition> indicators,
}) {
  final List<_ProfileBuilder> profiles = [];
  for (final catalog in referenceMetricCatalogs) {
    final profile = _ProfileBuilder(
      id: catalog.id,
      name: catalog.name,
      description: catalog.description,
      enabled: catalog.enabled,
    );
    for (final metric in catalog.metrics) {
      metrics.putIfAbsent(
        metric.key,
        () => CapabilityMetricDefinition(
          key: metric.key,
          label: metric.label,
          shortLabel: metric.shortLabel,
          defaultUnit: metric.unit,
          icon: metric.icon,
          displayType: metric.displayType,
          decimals: metric.decimals,
          statusBehavior: metric.statusBehavior,
        ),
      );
      profile.metricKeys.add(metric.key);
      profile.metricBindings[metric.key] = MetricBinding(
        sourceField: metric.sourceField,
        transform: metric.transform,
        valueLabelSourceField: metric.valueLabelSourceField,
      );
    }
    for (final indicator in catalog.indicators) {
      indicators.putIfAbsent(
        indicator.key,
        () => CapabilityIndicatorDefinition(
          key: indicator.key,
          label: _referenceIndicatorLabel(indicator.key),
          defaultIcon: indicator.icon,
        ),
      );
      profile.indicatorKeys.add(indicator.key);
      profile.indicatorBindings[indicator.key] = IndicatorBinding(
        sourceField: indicator.sourceField,
        condition: indicator.condition,
      );
    }
    if (catalog.availableIndicators.isNotEmpty) {
      profile.suggestedIndicatorsByMetric.addAll(catalog.availableIndicators);
    }
    profiles.add(profile);
  }
  return profiles;
}

String _referenceIndicatorLabel(String key) =>
    const {
      'calefaccionEtapa1': 'Calefacción etapa 1',
      'calefaccionEtapa2': 'Calefacción etapa 2',
      'humidificacion': 'Humidificación',
    }[key] ??
    key;

/// Same 3 presets as `_seedPresets()` in `board_preset_catalog.dart`.
List<BoardPreset> _seedBoardPresets() => [
  BoardPreset(
    id: 'preset-sala-clima-estandar',
    name: 'Sala clima estándar',
    description:
        'Temperatura/humedad interior y exterior, ventilación, presión '
        'diferencial, puertas, cerdas, NH3 y agua — geometría de referencia '
        'para una sala climatizada típica.',
    layoutTemplateId: roomContentExample.template.id,
    items: roomContentExample.board.items,
    requiredMetricKeys: const ['tempInterior', 'humedadInterior'],
    optionalMetricKeys: const [
      'fan',
      'presion',
      'nh3',
      'tempExterior',
      'humedadExterior',
    ],
    capabilityProfileId: 'environment_room_v1',
  ),
  BoardPreset(
    id: 'preset-laboratorio-estandar',
    name: 'Laboratorio estándar',
    description: 'Temperatura y humedad de laboratorio, geometría mínima.',
    layoutTemplateId: referenceBoardLayouts[1].template.id,
    items: referenceBoardLayouts[1].board.items.map(
      BoardContentItem.fromLegacy,
    ),
    requiredMetricKeys: const ['tempInterior'],
    optionalMetricKeys: const ['humedadInterior'],
    capabilityProfileId: 'laboratory_v1',
  ),
  BoardPreset(
    id: 'preset-arco-estandar',
    name: 'Arco estándar',
    description:
        'Imagen del dispositivo, contadores de desinfección, estado '
        'operativo, último evento y tabla de registros recientes.',
    layoutTemplateId: disinfectionContentExample.template.id,
    items: disinfectionContentExample.board.items,
    requiredMetricKeys: const [
      'vehiclesDisinfectedDaily',
      'vehiclesTotalDaily',
      'disinfectantLevel',
    ],
    capabilityProfileId: 'disinfection_arch_v1',
  ),
];

// ---------------------------------------------------------------------
// Firestore REST plumbing (verbatim copy of tool/seed_device_templates.dart)
// ---------------------------------------------------------------------

Future<void> _seedOne({
  required HttpClient client,
  required String projectId,
  required String accessToken,
  required String collection,
  required String id,
  required String versionField,
  required Map<String, Object?> fields,
  required bool overwrite,
}) async {
  final String path = '$collection/$id';
  final _Doc? existing = await _getDoc(client, projectId, accessToken, path);

  if (existing != null && !overwrite) {
    print('SKIP $path: ya existe (usá --overwrite para pisarlo).');
    return;
  }

  final int previousVersion = existing == null
      ? 0
      : _int(existing.fields[versionField]) ?? 0;
  final int nextVersion = previousVersion + 1;
  final DateTime now = DateTime.now().toUtc();

  final Map<String, Object?> envelope = <String, Object?>{
    ...fields,
    versionField: nextVersion,
    'createdAt': existing == null
        ? now
        : _DoNotEncode(existing.fields['createdAt']),
    'updatedAt': now,
  };

  await _putDoc(client, projectId, accessToken, path, envelope);
  print(
    existing == null
        ? 'CREADO $path ($versionField=$nextVersion).'
        : 'SOBRESCRITO $path ($versionField $previousVersion -> $nextVersion).',
  );
}

/// Marker so `createdAt` can reuse the exact previously-stored Firestore
/// value instead of re-encoding a parsed DateTime — avoids any precision
/// loss on overwrite.
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
  request.headers.set('Content-Type', 'application/json; charset=utf-8');
  request.add(
    utf8.encode(
      jsonEncode({
        'fields': {
          for (final MapEntry<String, Object?> entry in fields.entries)
            entry.key: _encodeFirestoreValue(entry.value),
        },
      }),
    ),
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
    'seed-n7-1-global-config-',
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
