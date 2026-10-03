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
//   dart run tool/seed_n7_1_global_config.dart            # remote audit only
//   dart run tool/seed_n7_1_global_config.dart --audit    # same, explicit
//   dart run tool/seed_n7_1_global_config.dart --apply    # create missing only
//
// The apply path is strictly create-only. Every write carries the Firestore
// precondition `currentDocument.exists=false`, so even a document created by
// another process between audit and apply is never overwritten.
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

enum _AuditStatus { missing, matching, conflict }

class _AuditEntry {
  const _AuditEntry({
    required this.planned,
    required this.status,
    required this.existing,
    required this.differences,
  });

  final _PlannedDoc planned;
  final _AuditStatus status;
  final _Doc? existing;
  final List<String> differences;
}

class _AuditResult {
  const _AuditResult({required this.entries, required this.remoteByCollection});

  final List<_AuditEntry> entries;
  final Map<String, List<_Doc>> remoteByCollection;

  Iterable<_AuditEntry> get missing =>
      entries.where((entry) => entry.status == _AuditStatus.missing);
  Iterable<_AuditEntry> get conflicts =>
      entries.where((entry) => entry.status == _AuditStatus.conflict);
}

Future<void> main(List<String> args) async {
  const allowed = {'--audit', '--dry-run', '--apply'};
  final unknown = args.where((arg) => !allowed.contains(arg)).toList();
  if (unknown.isNotEmpty || args.contains('--overwrite')) {
    stderr.writeln(
      'Argumento no permitido: ${unknown.join(', ')}. Este seed no admite '
      'overwrite. Usá --audit o --apply.',
    );
    exitCode = 64;
    return;
  }
  final bool apply = args.contains('--apply');
  print(
    '=== N7.1 — configuración global (modo=${apply ? 'APPLY' : 'AUDIT'}) ===',
  );

  final List<_PlannedDoc> planned = _buildPlan();
  final planIssues = _validatePlannedReferences(planned);
  if (planIssues.isNotEmpty) {
    for (final issue in planIssues) {
      stderr.writeln('PLAN_INVALID $issue');
    }
    exitCode = 65;
    return;
  }
  _printInventory(planned);

  final Map<String, dynamic> serviceAccount =
      jsonDecode(File('backend/config/service-account.json').readAsStringSync())
          as Map<String, dynamic>;
  final String projectId = serviceAccount['project_id'] as String;
  final String accessToken = await _getAccessToken(serviceAccount);
  final HttpClient client = HttpClient();

  try {
    final before = await _audit(
      client: client,
      projectId: projectId,
      accessToken: accessToken,
      planned: planned,
    );
    _printAudit('ANTES', before, planned);

    if (!apply) {
      print('=== Auditoría completa; no se realizaron escrituras ===');
      return;
    }

    var created = 0;
    var concurrentExisting = 0;
    for (final entry in before.missing) {
      final item = entry.planned;
      final wasCreated = await _createOnly(
        client: client,
        projectId: projectId,
        accessToken: accessToken,
        collection: item.collection,
        id: item.id,
        versionField: item.versionField,
        fields: item.fields,
      );
      if (wasCreated) {
        created++;
      } else {
        concurrentExisting++;
      }
    }

    final after = await _audit(
      client: client,
      projectId: projectId,
      accessToken: accessToken,
      planned: planned,
    );
    _printAudit('DESPUÉS', after, planned);
    print(
      'RESULTADO created=$created concurrentExisting=$concurrentExisting '
      'missing=${after.missing.length} conflicts=${after.conflicts.length}',
    );
    if (after.missing.isNotEmpty) {
      exitCode = 2;
    } else if (_remoteReferenceIssues(after).isNotEmpty) {
      exitCode = 3;
    }
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

  final layouts = <String, LayoutTemplate>{
    for (final template in initialLayoutTemplateCatalog.templates)
      template.id: template,
    // The official Arco BoardPreset uses its complete 6x7 fixture. Persist
    // that referenced template too, otherwise the seed graph is dangling.
    disinfectionContentExample.template.id: disinfectionContentExample.template,
  };
  for (final LayoutTemplate template in layouts.values) {
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

void _printInventory(List<_PlannedDoc> planned) {
  print('--- INVENTARIO OFICIAL (${planned.length} documentos) ---');
  for (final item in planned) {
    final relations = <String>[];
    if (item.collection == 'capabilityProfiles') {
      relations.add(
        'metrics=${(item.fields['metricKeys'] as List?)?.length ?? 0}',
      );
      relations.add(
        'indicators=${(item.fields['indicatorKeys'] as List?)?.length ?? 0}',
      );
    }
    if (item.collection == 'boardPresets') {
      relations.add('layout=${item.fields['layoutTemplateId']}');
      relations.add('profile=${item.fields['capabilityProfileId'] ?? '-'}');
    }
    print(
      'SEED ${item.collection}/${item.id} '
      '${item.versionField}(source=${item.fields[item.versionField] ?? 1}, '
      'create=1)'
      '${relations.isEmpty ? '' : ' ${relations.join(' ')}'}',
    );
  }
}

List<String> _validatePlannedReferences(List<_PlannedDoc> planned) {
  Set<String> ids(String collection) => planned
      .where((item) => item.collection == collection)
      .map((item) => item.id)
      .toSet();

  final layouts = ids('layoutTemplates');
  final cells = ids('cellLayoutPresets');
  final metrics = ids('capabilityMetrics');
  final indicators = ids('capabilityIndicators');
  final profiles = ids('capabilityProfiles');
  final issues = <String>[];

  for (final entry in initialCellLayoutCatalog.defaults.entries) {
    if (!cells.contains(entry.value)) {
      issues.add('default ${entry.key} -> ${entry.value} inexistente');
    }
    final preset = initialCellLayoutCatalog.byId(entry.value);
    if (preset == null ||
        '${preset.widthCells}x${preset.heightCells}' != entry.key ||
        !preset.enabled) {
      issues.add('default ${entry.key} -> ${entry.value} no resoluble');
    }
  }

  for (final profile in planned.where(
    (item) => item.collection == 'capabilityProfiles',
  )) {
    for (final key in (profile.fields['metricKeys'] as List).cast<String>()) {
      if (!metrics.contains(key)) {
        issues.add('${profile.id} -> metric $key inexistente');
      }
    }
    for (final key
        in (profile.fields['indicatorKeys'] as List).cast<String>()) {
      if (!indicators.contains(key)) {
        issues.add('${profile.id} -> indicator $key inexistente');
      }
    }
  }

  for (final board in planned.where(
    (item) => item.collection == 'boardPresets',
  )) {
    final layout = board.fields['layoutTemplateId'] as String;
    final profile = board.fields['capabilityProfileId'] as String?;
    if (!layouts.contains(layout)) {
      issues.add('${board.id} -> layout $layout inexistente');
    }
    if (profile != null && !profiles.contains(profile)) {
      issues.add('${board.id} -> profile $profile inexistente');
    }
    final boardMetrics = <String>{
      ...(board.fields['requiredMetricKeys'] as List).cast<String>(),
      ...(board.fields['optionalMetricKeys'] as List).cast<String>(),
    };
    for (final key in boardMetrics) {
      if (!metrics.contains(key)) {
        issues.add('${board.id} -> metric $key inexistente');
      }
    }
  }
  return issues;
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
// Remote audit and create-only Firestore REST plumbing.
// ---------------------------------------------------------------------

Future<_AuditResult> _audit({
  required HttpClient client,
  required String projectId,
  required String accessToken,
  required List<_PlannedDoc> planned,
}) async {
  final collections = planned.map((item) => item.collection).toSet();
  final remoteByCollection = <String, List<_Doc>>{};
  for (final collection in collections) {
    remoteByCollection[collection] = await _listCollection(
      client,
      projectId,
      accessToken,
      collection,
    );
  }

  final entries = <_AuditEntry>[];
  for (final item in planned) {
    _Doc? existing;
    for (final doc in remoteByCollection[item.collection]!) {
      if (doc.id == item.id) {
        existing = doc;
        break;
      }
    }
    if (existing == null) {
      entries.add(
        _AuditEntry(
          planned: item,
          status: _AuditStatus.missing,
          existing: null,
          differences: const [],
        ),
      );
      continue;
    }
    final differences = _seedDifferences(item, existing);
    entries.add(
      _AuditEntry(
        planned: item,
        status: differences.isEmpty
            ? _AuditStatus.matching
            : _AuditStatus.conflict,
        existing: existing,
        differences: differences,
      ),
    );
  }
  return _AuditResult(entries: entries, remoteByCollection: remoteByCollection);
}

void _printAudit(String label, _AuditResult audit, List<_PlannedDoc> planned) {
  print('--- AUDITORÍA $label ---');
  for (final collection in audit.remoteByCollection.keys) {
    final expected = planned.where((item) => item.collection == collection);
    print(
      'COUNT $collection remote=${audit.remoteByCollection[collection]!.length} '
      'seed=${expected.length}',
    );
  }
  for (final entry in audit.entries) {
    final item = entry.planned;
    final path = '${item.collection}/${item.id}';
    final version = entry.existing == null
        ? '-'
        : _int(entry.existing!.fields[item.versionField])?.toString() ??
              'inválida';
    switch (entry.status) {
      case _AuditStatus.missing:
        print('MISSING $path (create ${item.versionField}=1)');
      case _AuditStatus.matching:
        print('MATCH $path (${item.versionField}=$version)');
      case _AuditStatus.conflict:
        print(
          'CONFLICT $path (${item.versionField}=$version; '
          '${entry.differences.join(', ')})',
        );
    }
  }

  final expectedPaths = {
    for (final item in planned) '${item.collection}/${item.id}',
  };
  for (final entry in audit.remoteByCollection.entries) {
    for (final doc in entry.value) {
      final path = '${entry.key}/${doc.id}';
      if (!expectedPaths.contains(path)) print('PRESERVED_EXTRA $path');
    }
  }
  final referenceIssues = _remoteReferenceIssues(audit);
  if (referenceIssues.isEmpty) {
    print('REFERENCES_OK');
  } else {
    for (final issue in referenceIssues) {
      print('BROKEN_REFERENCE $issue');
    }
  }
}

List<String> _remoteReferenceIssues(_AuditResult audit) {
  Map<String, Map<String, Object?>> docs(String collection) => {
    for (final doc in audit.remoteByCollection[collection] ?? const <_Doc>[])
      doc.id: <String, Object?>{
        for (final entry in doc.fields.entries)
          entry.key: _decodeFirestoreValue(entry.value),
      },
  };

  final layouts = docs('layoutTemplates');
  final cells = docs('cellLayoutPresets');
  final metrics = docs('capabilityMetrics');
  final indicators = docs('capabilityIndicators');
  final profiles = docs('capabilityProfiles');
  final boards = docs('boardPresets');
  final issues = <String>[];

  for (final entry in initialCellLayoutCatalog.defaults.entries) {
    final cell = cells[entry.value];
    final parts = entry.key.split('x');
    if (cell == null ||
        cell['enabled'] != true ||
        cell['widthCells'] != int.parse(parts[0]) ||
        cell['heightCells'] != int.parse(parts[1])) {
      issues.add('default ${entry.key} -> ${entry.value} no resoluble');
    }
  }

  for (final entry in profiles.entries) {
    for (final key in (entry.value['metricKeys'] as List?) ?? const []) {
      if (!metrics.containsKey(key)) {
        issues.add('profile ${entry.key} -> metric $key inexistente');
      }
    }
    for (final key in (entry.value['indicatorKeys'] as List?) ?? const []) {
      if (!indicators.containsKey(key)) {
        issues.add('profile ${entry.key} -> indicator $key inexistente');
      }
    }
  }

  for (final entry in boards.entries) {
    final board = entry.value;
    final layout = board['layoutTemplateId'];
    final profile = board['capabilityProfileId'];
    if (!layouts.containsKey(layout)) {
      issues.add('board ${entry.key} -> layout $layout inexistente');
    }
    if (profile != null && !profiles.containsKey(profile)) {
      issues.add('board ${entry.key} -> profile $profile inexistente');
    }
    final boardMetrics = <Object?>{
      ...?board['requiredMetricKeys'] as List?,
      ...?board['optionalMetricKeys'] as List?,
    };
    for (final item in (board['items'] as List?) ?? const []) {
      if (item is! Map) continue;
      final content = item['content'];
      if (content is Map) {
        if (content['metricKey'] != null) {
          boardMetrics.add(content['metricKey']);
        }
        final cellId = content['cellLayoutPresetId'];
        if (cellId != null && !cells.containsKey(cellId)) {
          issues.add('board ${entry.key} -> cell preset $cellId inexistente');
        }
      }
    }
    for (final key in boardMetrics) {
      if (!metrics.containsKey(key)) {
        issues.add('board ${entry.key} -> metric $key inexistente');
      }
    }
  }
  return issues;
}

List<String> _seedDifferences(_PlannedDoc planned, _Doc existing) {
  final expected = _normalizedSeedContent(planned.fields, planned.versionField);
  final actual = <String, Object?>{
    for (final entry in existing.fields.entries)
      entry.key: _decodeFirestoreValue(entry.value),
  };
  actual.remove('createdAt');
  actual.remove('updatedAt');
  actual.remove(planned.versionField);

  final keys = {...expected.keys, ...actual.keys}.toList()..sort();
  return [
    for (final key in keys)
      if (_canonicalJson(expected[key]) != _canonicalJson(actual[key])) key,
  ];
}

Map<String, Object?> _normalizedSeedContent(
  Map<String, Object?> fields,
  String versionField,
) {
  final result = <String, Object?>{...fields};
  result.remove('createdAt');
  result.remove('updatedAt');
  result.remove(versionField);
  return result;
}

String _canonicalJson(Object? value) => jsonEncode(_canonicalize(value));

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is Iterable) return value.map(_canonicalize).toList();
  return value;
}

Object? _decodeFirestoreValue(Object? raw) {
  if (raw is! Map) return raw;
  if (raw.containsKey('nullValue')) return null;
  if (raw.containsKey('booleanValue')) return raw['booleanValue'];
  if (raw.containsKey('integerValue')) {
    return int.parse(raw['integerValue'].toString());
  }
  if (raw.containsKey('doubleValue')) return raw['doubleValue'];
  if (raw.containsKey('stringValue')) return raw['stringValue'];
  if (raw.containsKey('timestampValue')) return raw['timestampValue'];
  if (raw.containsKey('arrayValue')) {
    final array = raw['arrayValue'] as Map?;
    return ((array?['values'] as List?) ?? const [])
        .map(_decodeFirestoreValue)
        .toList();
  }
  if (raw.containsKey('mapValue')) {
    final map = raw['mapValue'] as Map?;
    final fields = (map?['fields'] as Map?) ?? const {};
    return <String, Object?>{
      for (final entry in fields.entries)
        entry.key.toString(): _decodeFirestoreValue(entry.value),
    };
  }
  return raw;
}

Future<bool> _createOnly({
  required HttpClient client,
  required String projectId,
  required String accessToken,
  required String collection,
  required String id,
  required String versionField,
  required Map<String, Object?> fields,
}) async {
  final String path = '$collection/$id';
  final now = DateTime.now().toUtc();

  final Map<String, Object?> envelope = <String, Object?>{
    ...fields,
    versionField: 1,
    'createdAt': now,
    'updatedAt': now,
  };

  final created = await _putCreateOnly(
    client,
    projectId,
    accessToken,
    path,
    envelope,
  );
  print(created ? 'CREATED $path ($versionField=1)' : 'RACE_PRESERVED $path');
  return created;
}

int? _int(dynamic value) {
  if (value is Map && value['integerValue'] != null) {
    return int.tryParse(value['integerValue'].toString());
  }
  return null;
}

Map<String, dynamic> _encodeFirestoreValue(Object? value) {
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

Future<List<_Doc>> _listCollection(
  HttpClient client,
  String projectId,
  String accessToken,
  String collection,
) async {
  final docs = <_Doc>[];
  String? pageToken;
  do {
    final query = <String, String>{'pageSize': '100'};
    if (pageToken != null) query['pageToken'] = pageToken;
    final uri = Uri.https(
      'firestore.googleapis.com',
      '/v1/projects/$projectId/databases/(default)/documents/$collection',
      query,
    );
    final request = await client.getUrl(uri);
    request.headers.set('Authorization', 'Bearer $accessToken');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw StateError(
        'LIST $collection failed (${response.statusCode}): $body',
      );
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    for (final raw in (json['documents'] as List?) ?? const []) {
      final doc = raw as Map<String, dynamic>;
      docs.add(
        _Doc(
          id: (doc['name'] as String).split('/').last,
          fields:
              (doc['fields'] as Map<String, dynamic>?) ??
              const <String, dynamic>{},
        ),
      );
    }
    pageToken = json['nextPageToken'] as String?;
  } while (pageToken != null && pageToken.isNotEmpty);
  docs.sort((a, b) => a.id.compareTo(b.id));
  return docs;
}

Future<bool> _putCreateOnly(
  HttpClient client,
  String projectId,
  String accessToken,
  String path,
  Map<String, Object?> fields,
) async {
  final Uri uri = Uri.https(
    'firestore.googleapis.com',
    '/v1/projects/$projectId/databases/(default)/documents/$path',
    {'currentDocument.exists': 'false'},
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
  if (response.statusCode == 409) return false;
  if (response.statusCode != 200) {
    throw StateError('PATCH $path failed (${response.statusCode}): $body');
  }
  return true;
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
