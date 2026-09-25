// ignore_for_file: avoid_relative_lib_imports
//
// Etapa B6.1 — borrado controlado de los 2 documentos alertConfig creados
// durante pruebas manuales de la UI nueva (identificados en el Refuerzo de
// la auditoria de la Etapa B6):
//
//   tenants/the-gene-pig/sites/las-heras/alertConfig/temperature_interior
//   tenants/the-gene-pig/sites/las-heras/alertConfig/high_humidity
//
// No son configuracion productiva: fueron creados por gerardo@valke.com.ar
// (UID rS0bFhxmJ8ORDSBDP0Bmzj5RPaI2) minutos antes del dry-run de B6,
// probando la tabla nueva de Configuracion -> Alertas, con un valor
// (temperature_interior.thresholds.min=14) que no coincide con el legacy
// real (15).
//
// Uso seguro:
//   dart run tool/cleanup_b6_1_residuos_ui_the_gene_pig.dart
//   dart run tool/cleanup_b6_1_residuos_ui_the_gene_pig.dart --apply
//
// Default: dry-run. No borra por defecto. Solo borra un documento si su
// createdBy y su thresholds.min coinciden exactamente con lo esperado; en
// cualquier otro caso lo deja intacto y lo reporta como MISMATCH.

import 'dart:convert';
import 'dart:io';

import 'migrate_alerts_b6_the_gene_pig.dart' show FirestoreRest;

const String _tenantId = 'the-gene-pig';
const String _siteId = 'las-heras';
const String _defaultServiceAccountPath = 'backend/config/service-account.json';
const String _outputDir = 'no_git/informes_de_codigo';

const List<_KnownResidue> _knownResidues = <_KnownResidue>[
  _KnownResidue(
    alertId: 'temperature_interior',
    expectedCreatedBy: 'rS0bFhxmJ8ORDSBDP0Bmzj5RPaI2',
    expectedThresholdMin: 14,
  ),
  _KnownResidue(
    alertId: 'high_humidity',
    expectedCreatedBy: 'rS0bFhxmJ8ORDSBDP0Bmzj5RPaI2',
    expectedThresholdMin: 30,
  ),
];

Future<void> main(List<String> args) async {
  final bool apply = args.contains('--apply');

  final FirestoreRest firestore = await FirestoreRest.fromServiceAccount(
    serviceAccountPath: _defaultServiceAccountPath,
  );

  final DateTime now = DateTime.now().toUtc();
  final String stamp = _timestampForFile(now);
  final String backupPath =
      '$_outputDir/b6_1_backup_residuos_ui_the_gene_pig_$stamp.json';

  stdout.writeln(
    'B6.1 cleanup mode=${apply ? 'APPLY' : 'DRY-RUN'} tenant=$_tenantId site=$_siteId',
  );

  final List<Map<String, Object?>> records = <Map<String, Object?>>[];
  final List<String> confirmedPaths = <String>[];

  for (final _KnownResidue residue in _knownResidues) {
    final String path =
        'tenants/$_tenantId/sites/$_siteId/alertConfig/${residue.alertId}';
    final Map<String, Object?>? doc = await firestore.getDoc(path);
    if (doc == null) {
      stdout.writeln('SKIP $path (no existe; ya fue limpiado o nunca existio)');
      continue;
    }
    final String createdBy = doc['createdBy']?.toString() ?? '';
    final Object? thresholds = doc['thresholds'];
    final Object? minValue = thresholds is Map ? thresholds['min'] : null;
    final bool matches =
        createdBy == residue.expectedCreatedBy &&
        _numEquals(minValue, residue.expectedThresholdMin);
    stdout.writeln(
      '${matches ? 'CONFIRMED' : 'MISMATCH'} $path createdBy=$createdBy '
      'thresholds.min=$minValue',
    );
    records.add(<String, Object?>{
      'path': path,
      'documentData': doc,
      'createdAt': doc['createdAt'],
      'createdBy': doc['createdBy'],
      'updatedAt': doc['updatedAt'],
      'updatedBy': doc['updatedBy'],
      'matchesKnownResidue': matches,
    });
    if (matches) confirmedPaths.add(path);
  }

  await File(backupPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert(
      _canonicalJsonValue(<String, Object?>{
        'timestamp': now.toIso8601String(),
        'tenantId': _tenantId,
        'siteId': _siteId,
        'mode': apply ? 'apply' : 'dry-run',
        'records': records,
      }),
    ),
  );
  stdout.writeln('BACKUP $backupPath');

  if (confirmedPaths.isEmpty) {
    stdout.writeln(
      'B6.1 CLEANUP: nada para borrar (0 documentos confirmados).',
    );
    return;
  }

  if (!apply) {
    for (final String path in confirmedPaths) {
      stdout.writeln('DRY-RUN DELETE $path');
    }
    stdout.writeln('B6.1 DRY-RUN COMPLETADO: sin borrados productivos.');
    return;
  }

  for (final String path in confirmedPaths) {
    await firestore.deleteDoc(path);
    final Map<String, Object?>? reread = await firestore.getDoc(path);
    if (reread != null) {
      throw StateError(
        'Post-delete verification failed: $path sigue existiendo',
      );
    }
    stdout.writeln('DELETED $path (verificado: ya no existe)');
  }
  stdout.writeln(
    'B6.1 APPLY COMPLETADO: ${confirmedPaths.length} residuos de prueba '
    'eliminados, legacy intacto.',
  );
}

class _KnownResidue {
  const _KnownResidue({
    required this.alertId,
    required this.expectedCreatedBy,
    required this.expectedThresholdMin,
  });

  final String alertId;
  final String expectedCreatedBy;
  final num expectedThresholdMin;
}

bool _numEquals(Object? value, num expected) {
  if (value is num) return value == expected;
  return false;
}

String _timestampForFile(DateTime now) {
  final String iso = now.toIso8601String();
  return iso.replaceAll('-', '').replaceAll(':', '').replaceAll('.', '');
}

Object? _canonicalJsonValue(Object? value) {
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (value is Map) {
    final Map<String, Object?> mapped = value.map(
      (Object? key, Object? val) => MapEntry(key.toString(), val),
    );
    final List<String> keys = mapped.keys.toList()..sort();
    return <String, Object?>{
      for (final String key in keys) key: _canonicalJsonValue(mapped[key]),
    };
  }
  if (value is Iterable) {
    return value.map(_canonicalJsonValue).toList(growable: false);
  }
  return value;
}
