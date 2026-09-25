// ignore_for_file: avoid_relative_lib_imports
//
// Etapa B6 — migracion controlada de configuracion y recipients reales.
//
// Uso seguro:
//   dart run tool/migrate_alerts_b6_the_gene_pig.dart
//   dart run tool/migrate_alerts_b6_the_gene_pig.dart --apply \
//     --confirm-rules-deployed --confirm-b5-manual-ok --admin-uid <uid>
//
// Default: dry-run. No escribe por defecto.

import 'dart:convert';
import 'dart:io';

import '../backend/lib/src/alert_configuration_contracts.dart';
import '../backend/lib/src/alert_settings_cache.dart';
import '../backend/lib/src/whatsapp_alert_recipients.dart' as legacy;

const String _tenantId = 'the-gene-pig';
const String _siteId = 'las-heras';
const String _databaseId = '(default)';
const String _defaultServiceAccountPath = 'backend/config/service-account.json';
const String _outputDir = 'no_git/informes_de_codigo';

Future<void> main(List<String> args) async {
  final _Args parsed = _Args.parse(args);
  if (parsed.help) {
    _printUsage();
    return;
  }
  if (parsed.apply) {
    final List<String> missing = <String>[
      if (!parsed.confirmRulesDeployed) '--confirm-rules-deployed',
      if (!parsed.confirmB5ManualOk) '--confirm-b5-manual-ok',
      if (parsed.adminUid.trim().isEmpty) '--admin-uid',
    ];
    if (missing.isNotEmpty) {
      stderr.writeln('DETENER B6: falta ${missing.join(', ')} para --apply.');
      exit(64);
    }
  }

  final FirestoreRest firestore = await FirestoreRest.fromServiceAccount(
    serviceAccountPath: parsed.serviceAccountPath,
  );
  final DateTime now = DateTime.now().toUtc();
  final String stamp = _timestampForFile(now);
  final String backupPath = '$_outputDir/b6_backup_the_gene_pig_$stamp.json';
  final String comparisonPath =
      '$_outputDir/b6_comparacion_alertas_the_gene_pig_$stamp.json';
  final String rollbackPath =
      '$_outputDir/b6_rollback_manifest_the_gene_pig_$stamp.json';

  stdout.writeln(
    'B6 mode=${parsed.apply ? 'APPLY' : 'DRY-RUN'} tenant=$_tenantId site=$_siteId',
  );

  await _preflightReadModern(firestore);

  final Map<String, Object?>? legacyRaw = await firestore.getDoc(
    'tenants/$_tenantId/sites/$_siteId/settings/controlDashboard',
  );
  if (legacyRaw == null) {
    stderr.writeln('DETENER B6: no existe settings/controlDashboard legacy.');
    exit(65);
  }
  final CachedAlertSettings legacySettings = CachedAlertSettings.fromRaw(
    tenantId: _tenantId,
    siteId: _siteId,
    raw: legacyRaw,
    loadedAt: now,
    source: 'firestore-b6',
  );

  final String laboratorioDeviceId = await _resolveLaboratorioDeviceId(
    firestore,
  );
  final List<_PlannedWrite> plannedWrites = <_PlannedWrite>[
    ..._planConfigWrites(legacySettings),
    ..._planRecipientWrites(laboratorioDeviceId: laboratorioDeviceId),
  ];

  final List<String> modernPathsToBackup = <String>[
    for (final _PlannedWrite write in plannedWrites) write.path,
    'tenants/$_tenantId/alertConfig',
    'tenants/$_tenantId/sites/$_siteId/alertConfig',
    'tenants/$_tenantId/devices/$laboratorioDeviceId/alertRecipients',
  ];
  final Map<String, Object?> backup = <String, Object?>{
    'timestamp': now.toIso8601String(),
    'tenantId': _tenantId,
    'siteId': _siteId,
    'mode': parsed.apply ? 'apply' : 'dry-run',
    'adminUid': parsed.adminUid.isEmpty ? null : parsed.adminUid,
    'legacyConfigPath':
        'tenants/$_tenantId/sites/$_siteId/settings/controlDashboard',
    'legacyConfig': legacyRaw,
    'legacyRecipientsInventory': _legacyRecipientsInventory(maskPhones: true),
    'modernExisting': await _readExistingForBackup(
      firestore,
      modernPathsToBackup,
    ),
  };
  await _writeJsonFile(backupPath, backup);
  stdout.writeln('BACKUP $backupPath');

  final List<_PlanResult> planResults = <_PlanResult>[];
  for (final _PlannedWrite write in plannedWrites) {
    final Map<String, Object?>? existing = await firestore.getDoc(write.path);
    final _PlanResult result = _classifyPlan(
      write,
      existing,
      allowUpdateConflicts: parsed.allowUpdateConflicts,
    );
    planResults.add(result);
    stdout.writeln(result.summary(maskPhones: true));
  }

  final bool hasConflict = planResults.any(
    (_PlanResult result) => result.action == _PlanAction.conflict,
  );
  if (hasConflict && !parsed.allowUpdateConflicts) {
    stdout.writeln(
      'DETENER B6: hay CONFLICT. Re-ejecutar con --allow-update-conflicts solo si fue revisado.',
    );
  }

  final List<_PlannedWrite> appliedCreates = <_PlannedWrite>[];
  final List<_PlannedWrite> appliedUpdates = <_PlannedWrite>[];
  if (parsed.apply && (!hasConflict || parsed.allowUpdateConflicts)) {
    for (final _PlanResult result in planResults) {
      if (result.action == _PlanAction.create) {
        final Map<String, Object?> payload = buildCreatePayload(
          functionalFields: result.write.functionalFields,
          now: now,
          adminUid: parsed.adminUidOrDryRun,
        );
        // CREATE: sin updateMask. El doc todavia no existe, asi que un
        // PATCH sin mask (reemplazo completo) equivale a un create y es
        // seguro — no hay campos previos que pisar.
        await firestore.patchDoc(result.write.path, payload);
        final Map<String, Object?>? reread = await firestore.getDoc(
          result.write.path,
        );
        _verifyWrittenDoc(result.write, reread);
        appliedCreates.add(result.write);
      } else if (result.action == _PlanAction.updateAllowed) {
        final FieldDiff diff = diffFunctionalFields(
          result.write.functionalFields,
          result.existing!,
        );
        final Map<String, Object?> payload = buildUpdatePayload(
          diff: diff,
          now: now,
          adminUid: parsed.adminUidOrDryRun,
        );
        // UPDATE (Etapa B6.1): updateMask explicito con solo los campos
        // que cambian + updatedAt/updatedBy. Nunca incluye createdAt ni
        // createdBy, asi que un PATCH parcial no puede pisarlos ni borrar
        // campos hermanos que no forman parte de este diff.
        await firestore.patchDoc(
          result.write.path,
          payload,
          updateMask: buildUpdateMask(diff),
        );
        final Map<String, Object?>? reread = await firestore.getDoc(
          result.write.path,
        );
        _verifyWrittenDoc(
          result.write,
          reread,
          preUpdateExisting: result.existing,
        );
        appliedUpdates.add(result.write);
      }
    }
  }

  await _writeJsonFile(rollbackPath, <String, Object?>{
    'timestamp': now.toIso8601String(),
    'tenantId': _tenantId,
    'siteId': _siteId,
    'createdByB6': [
      for (final _PlannedWrite write in appliedCreates) write.path,
    ],
    'updatedByB6': [
      for (final _PlannedWrite write in appliedUpdates) write.path,
    ],
    'rollback':
        'DELETE createdByB6 paths only; restore updatedByB6 from backup if conflict updates were explicitly allowed.',
  });
  stdout.writeln('ROLLBACK_MANIFEST $rollbackPath');

  final Map<String, Object?> comparison = await _buildComparison(
    firestore: firestore,
    legacySettings: legacySettings,
    plannedWrites: plannedWrites,
    laboratorioDeviceId: laboratorioDeviceId,
    applied: parsed.apply && (!hasConflict || parsed.allowUpdateConflicts),
  );
  await _writeJsonFile(comparisonPath, comparison);
  stdout.writeln('COMPARISON $comparisonPath');

  final _RecipientValidation recipientValidation = await _validateRecipients(
    firestore: firestore,
    laboratorioDeviceId: laboratorioDeviceId,
    plannedWrites: plannedWrites,
    useFirestoreAfterApply:
        parsed.apply && (!hasConflict || parsed.allowUpdateConflicts),
  );

  stdout.writeln(recipientValidation.summary);
  stdout.writeln(
    parsed.apply && (!hasConflict || parsed.allowUpdateConflicts)
        ? 'B6 APPLY COMPLETADO: modern data present, legacy sender untouched.'
        : 'B6 DRY-RUN COMPLETADO: sin escrituras productivas.',
  );
}

Future<void> _writeJsonFile(String path, Object? value) async {
  await File(path).writeAsString(
    const JsonEncoder.withIndent('  ').convert(_canonicalJsonValue(value)),
  );
}

List<_PlannedWrite> _planConfigWrites(CachedAlertSettings settings) {
  final AlertConfigurationTarget target = AlertConfigurationTarget(
    tenantId: _tenantId,
    siteId: _siteId,
    scope: AlertConfigurationScope.site,
  );
  final EffectiveAlertConfiguration legacyEffective =
      const LegacyAlertSettingsAdapter().fromCachedSettings(
        settings: settings,
        target: target,
      );
  return <_PlannedWrite>[
    for (final EffectiveAlertConfig alert in legacyEffective.alerts)
      _PlannedWrite(
        kind: _PlannedWriteKind.alertConfig,
        path: 'tenants/$_tenantId/sites/$_siteId/alertConfig/${alert.alertId}',
        functionalFields: <String, Object?>{
          'enabled': alert.enabled,
          'visualEnabled': alert.visualEnabled,
          'whatsappEnabled': alert.whatsappEnabled,
          if (alert.whatsappDelay.inMinutes > 0)
            'whatsappDelayMinutes': alert.whatsappDelay.inMinutes,
          if (_thresholdsMap(alert.thresholds).isNotEmpty)
            'thresholds': _thresholdsMap(alert.thresholds),
          'cooldownMinutes': alert.cooldown.inMinutes,
          'order': alert.order,
        },
      ),
  ];
}

List<_PlannedWrite> _planRecipientWrites({
  required String laboratorioDeviceId,
}) {
  Map<String, Object?> recipient(String displayName, String phone) {
    return <String, Object?>{
      'displayName': displayName,
      'phoneE164': _normalizePhoneE164(phone),
      'enabled': true,
    };
  }

  return <_PlannedWrite>[
    _PlannedWrite(
      kind: _PlannedWriteKind.alertRecipient,
      path: 'tenants/$_tenantId/alertRecipients/nicolas-rivas',
      functionalFields: recipient('Nicolás Rivas', '5491169384562'),
    ),
    _PlannedWrite(
      kind: _PlannedWriteKind.alertRecipient,
      path:
          'tenants/$_tenantId/devices/$laboratorioDeviceId/alertRecipients/enzo',
      functionalFields: recipient('Enzo', '5491123040959'),
    ),
    _PlannedWrite(
      kind: _PlannedWriteKind.alertRecipient,
      path:
          'tenants/$_tenantId/devices/$laboratorioDeviceId/alertRecipients/mauro',
      functionalFields: recipient('Mauro', '5492227516703'),
    ),
  ];
}

Future<void> _preflightReadModern(FirestoreRest firestore) async {
  try {
    await firestore.listDocs('tenants/$_tenantId/alertConfig');
    await firestore.listDocs('tenants/$_tenantId/alertRecipients');
    await firestore.listDocs('tenants/$_tenantId/sites/$_siteId/alertConfig');
    await firestore.listDocs(
      'tenants/$_tenantId/sites/$_siteId/alertRecipients',
    );
  } on Object catch (error) {
    stderr.writeln(
      'DETENER B6: no se pudieron leer alertConfig/alertRecipients modernos. $error',
    );
    exit(66);
  }
}

Future<String> _resolveLaboratorioDeviceId(FirestoreRest firestore) async {
  final List<FirestoreDoc> devices = await firestore.listDocs(
    'tenants/$_tenantId/devices',
  );
  final List<FirestoreDoc> candidates = devices
      .where((FirestoreDoc doc) {
        final String siteId = doc.fields['siteId']?.toString() ?? '';
        final String id = doc.id.toLowerCase();
        final String name = (doc.fields['name']?.toString() ?? '')
            .toLowerCase();
        return siteId == _siteId &&
            (id.contains('laboratorio') ||
                id == 'laboratorio' ||
                name.contains('laboratorio') ||
                name == 'lab');
      })
      .toList(growable: false);
  if (candidates.length != 1) {
    throw StateError(
      'No se pudo resolver un unico device Laboratorio para $_tenantId/$_siteId. Candidatos=${candidates.map((d) => d.id).join(', ')}',
    );
  }
  return candidates.single.id;
}

_PlanResult _classifyPlan(
  _PlannedWrite write,
  Map<String, Object?>? existing, {
  required bool allowUpdateConflicts,
}) {
  if (existing == null) {
    return _PlanResult(action: _PlanAction.create, write: write);
  }
  final FieldDiff diff = diffFunctionalFields(write.functionalFields, existing);
  if (diff.maskPaths.isEmpty) {
    return _PlanResult(
      action: _PlanAction.skip,
      write: write,
      existing: existing,
    );
  }
  return _PlanResult(
    action: allowUpdateConflicts
        ? _PlanAction.updateAllowed
        : _PlanAction.conflict,
    write: write,
    existing: existing,
  );
}

/// Resultado de comparar los campos de negocio planificados contra un
/// documento moderno existente. `maskPaths` son los field paths exactos
/// (dotted para subcampos de `thresholds`) que efectivamente cambiaron —
/// eso es lo que se manda como `updateMask.fieldPaths` en un PATCH real,
/// para que Firestore fusione en vez de reemplazar el documento entero
/// (Etapa B6.1, hardening del hallazgo de la auditoria de B6).
class FieldDiff {
  const FieldDiff({required this.maskPaths, required this.updateFields});

  final List<String> maskPaths;
  final Map<String, Object?> updateFields;
}

FieldDiff diffFunctionalFields(
  Map<String, Object?> functionalFields,
  Map<String, Object?> existing,
) {
  final List<String> maskPaths = <String>[];
  final Map<String, Object?> updateFields = <String, Object?>{};
  for (final MapEntry<String, Object?> entry in functionalFields.entries) {
    final String key = entry.key;
    final Object? plannedValue = entry.value;
    if (key == 'thresholds' && plannedValue is Map) {
      final Object? existingRaw = existing['thresholds'];
      final Map<Object?, Object?> existingThresholds = existingRaw is Map
          ? existingRaw
          : const <Object?, Object?>{};
      final Map<String, Object?> changedThresholds = <String, Object?>{};
      for (final MapEntry<Object?, Object?> tEntry
          in plannedValue.cast<Object?, Object?>().entries) {
        final String thresholdKey = tEntry.key.toString();
        if (!_jsonEqual(existingThresholds[tEntry.key], tEntry.value)) {
          maskPaths.add('thresholds.$thresholdKey');
          changedThresholds[thresholdKey] = tEntry.value;
        }
      }
      if (changedThresholds.isNotEmpty) {
        updateFields['thresholds'] = changedThresholds;
      }
      continue;
    }
    if (!_jsonEqual(existing[key], plannedValue)) {
      maskPaths.add(key);
      updateFields[key] = plannedValue;
    }
  }
  return FieldDiff(maskPaths: maskPaths, updateFields: updateFields);
}

/// CREATE (Etapa B6.1 §7): incluye `schemaVersion`, todos los campos de
/// negocio, y auditoria completa (`createdAt`/`createdBy` reales, no
/// placeholders).
Map<String, Object?> buildCreatePayload({
  required Map<String, Object?> functionalFields,
  required DateTime now,
  required String adminUid,
}) {
  return <String, Object?>{
    'schemaVersion': 1,
    ...functionalFields,
    'createdAt': now,
    'createdBy': adminUid,
    'updatedAt': now,
    'updatedBy': adminUid,
  };
}

/// UPDATE (Etapa B6.1 §7): solo los campos de negocio que cambiaron +
/// `updatedAt`/`updatedBy`. Nunca incluye `createdAt`/`createdBy` — la
/// inmutabilidad se logra por omision, igual que en el modelo Flutter
/// (`buildAlertConfigUpdatePayload`) desde la Etapa B5.
Map<String, Object?> buildUpdatePayload({
  required FieldDiff diff,
  required DateTime now,
  required String adminUid,
}) {
  return <String, Object?>{
    ...diff.updateFields,
    'updatedAt': now,
    'updatedBy': adminUid,
  };
}

/// Field paths para `updateMask.fieldPaths` — exactamente los campos que
/// cambian, mas `updatedAt`/`updatedBy`. Deliberadamente NUNCA incluye
/// `createdAt`/`createdBy`.
List<String> buildUpdateMask(FieldDiff diff) => <String>[
  ...diff.maskPaths,
  'updatedAt',
  'updatedBy',
];

void _verifyWrittenDoc(
  _PlannedWrite write,
  Map<String, Object?>? reread, {
  Map<String, Object?>? preUpdateExisting,
}) {
  if (reread == null) {
    throw StateError('Post-write verification failed: missing ${write.path}');
  }
  if (reread['schemaVersion'] != 1) {
    throw StateError(
      'Post-write verification failed: schemaVersion ${write.path}',
    );
  }
  if ((reread['updatedBy']?.toString() ?? '').isEmpty) {
    throw StateError('Post-write verification failed: updatedBy ${write.path}');
  }
  if ((reread['createdBy']?.toString() ?? '').isEmpty) {
    throw StateError('Post-write verification failed: createdBy ${write.path}');
  }
  if (preUpdateExisting != null) {
    if (!_jsonEqual(reread['createdAt'], preUpdateExisting['createdAt'])) {
      throw StateError(
        'Post-write verification failed: createdAt fue pisado en update '
        '${write.path}',
      );
    }
    if (!_jsonEqual(reread['createdBy'], preUpdateExisting['createdBy'])) {
      throw StateError(
        'Post-write verification failed: createdBy fue pisado en update '
        '${write.path}',
      );
    }
  }
}

Future<Map<String, Object?>> _buildComparison({
  required FirestoreRest firestore,
  required CachedAlertSettings legacySettings,
  required List<_PlannedWrite> plannedWrites,
  required String laboratorioDeviceId,
  required bool applied,
}) async {
  final AlertConfigurationTarget target = AlertConfigurationTarget(
    tenantId: _tenantId,
    siteId: _siteId,
    scope: AlertConfigurationScope.site,
  );
  final EffectiveAlertConfiguration legacyEffective =
      const LegacyAlertSettingsAdapter().fromCachedSettings(
        settings: legacySettings,
        target: target,
      );
  int readCount = 0;
  final Map<String, Map<String, Object?>> modernByAlertId =
      <String, Map<String, Object?>>{};
  for (final _PlannedWrite write in plannedWrites.where(
    (_PlannedWrite write) => write.kind == _PlannedWriteKind.alertConfig,
  )) {
    final String alertId = write.path.split('/').last;
    if (applied) {
      readCount += 1;
      modernByAlertId[alertId] =
          await firestore.getDoc(write.path) ?? <String, Object?>{};
    } else {
      modernByAlertId[alertId] = write.fields;
    }
  }

  return <String, Object?>{
    'tenantId': _tenantId,
    'siteId': _siteId,
    'laboratorioDeviceId': laboratorioDeviceId,
    'applied': applied,
    'readCount': readCount,
    'alerts': <Map<String, Object?>>[
      for (final EffectiveAlertConfig legacyAlert in legacyEffective.alerts)
        _compareAlert(
          legacyAlert,
          modernByAlertId[legacyAlert.alertId] ?? <String, Object?>{},
        ),
    ],
  };
}

Map<String, Object?> _compareAlert(
  EffectiveAlertConfig legacyAlert,
  Map<String, Object?> modernFields,
) {
  final Map<String, Object?> legacyComparable = _effectiveAlertComparableJson(
    legacyAlert,
  );
  final Map<String, Object?> modernComparable = _modernAlertComparableJson(
    modernFields,
  );
  return <String, Object?>{
    'alertId': legacyAlert.alertId,
    'legacy': _effectiveAlertJson(legacyAlert),
    'modern': modernComparable,
    'equivalent': _jsonEqual(legacyComparable, modernComparable),
  };
}

Map<String, Object?> _effectiveAlertJson(EffectiveAlertConfig alert) {
  return <String, Object?>{
    'enabled': alert.enabled,
    'visualEnabled': alert.visualEnabled,
    'whatsappEnabled': alert.whatsappEnabled,
    'whatsappDelayMinutes': alert.whatsappDelay.inMinutes,
    'thresholds': _thresholdsMap(alert.thresholds),
    'cooldownMinutes': alert.cooldown.inMinutes,
    'order': alert.order,
    'origin': alert.origin.name,
  };
}

Map<String, Object?> _effectiveAlertComparableJson(EffectiveAlertConfig alert) {
  return <String, Object?>{
    'enabled': alert.enabled,
    'visualEnabled': alert.visualEnabled,
    'whatsappEnabled': alert.whatsappEnabled,
    'whatsappDelayMinutes': alert.whatsappDelay.inMinutes,
    'thresholds': _thresholdsMap(alert.thresholds),
    'cooldownMinutes': alert.cooldown.inMinutes,
    'order': alert.order,
  };
}

Map<String, Object?> _modernAlertComparableJson(Map<String, Object?> fields) {
  return <String, Object?>{
    'enabled': fields['enabled'],
    'visualEnabled': fields['visualEnabled'],
    'whatsappEnabled': fields['whatsappEnabled'],
    'whatsappDelayMinutes': fields['whatsappDelayMinutes'] ?? 0,
    'thresholds': fields['thresholds'] ?? const <String, Object?>{},
    'cooldownMinutes': fields['cooldownMinutes'],
    'order': fields['order'],
  };
}

Future<_RecipientValidation> _validateRecipients({
  required FirestoreRest firestore,
  required String laboratorioDeviceId,
  required List<_PlannedWrite> plannedWrites,
  required bool useFirestoreAfterApply,
}) async {
  final List<legacy.AlertRecipient> legacyRecipients =
      const legacy.WhatsAppAlertRecipientsConfig().recipientsFor(
        tenantId: _tenantId,
        siteId: _siteId,
      );
  final List<_RecipientDoc> tenantRecipients = useFirestoreAfterApply
      ? await _readRecipientDocs(
          firestore,
          'tenants/$_tenantId/alertRecipients',
        )
      : _plannedRecipientDocs(plannedWrites, 'tenants/$_tenantId');
  final List<_RecipientDoc> labDeviceRecipients = useFirestoreAfterApply
      ? await _readRecipientDocs(
          firestore,
          'tenants/$_tenantId/devices/$laboratorioDeviceId/alertRecipients',
        )
      : _plannedRecipientDocs(
          plannedWrites,
          'tenants/$_tenantId/devices/$laboratorioDeviceId',
        );
  final List<_RecipientDoc> labRecipients = _resolveRecipients(
    tenantRecipients,
    labDeviceRecipients,
  );
  final List<_RecipientDoc> salaRecipients = _resolveRecipients(
    tenantRecipients,
    const <_RecipientDoc>[],
  );
  final _PhoneComparison labComparison = _compareRecipientPhones(
    legacyRecipients: legacyRecipients,
    modernRecipients: labRecipients,
  );
  return _RecipientValidation(
    labHasNicolas: _containsRecipient(labRecipients, 'Nicolás Rivas'),
    labHasEnzo: _containsRecipient(labRecipients, 'Enzo'),
    labHasMauro: _containsRecipient(labRecipients, 'Mauro'),
    salaHasEnzo: _containsRecipient(salaRecipients, 'Enzo'),
    salaHasMauro: _containsRecipient(salaRecipients, 'Mauro'),
    legacyOnly: labComparison.legacyOnly,
    modernOnly: labComparison.modernOnly,
    both: labComparison.both,
    invalid: labComparison.invalid,
  );
}

Future<List<_RecipientDoc>> _readRecipientDocs(
  FirestoreRest firestore,
  String collectionPath,
) async {
  return <_RecipientDoc>[
    for (final FirestoreDoc doc in await firestore.listDocs(collectionPath))
      _recipientDocFromFields(doc.id, doc.fields),
  ];
}

List<_RecipientDoc> _plannedRecipientDocs(
  List<_PlannedWrite> writes,
  String ownerPath,
) {
  final String prefix = '$ownerPath/alertRecipients/';
  final List<_RecipientDoc> recipients = <_RecipientDoc>[];
  for (final _PlannedWrite write in writes.where(
    (_PlannedWrite write) => write.kind == _PlannedWriteKind.alertRecipient,
  )) {
    if (!write.path.startsWith(prefix)) continue;
    recipients.add(
      _recipientDocFromFields(write.path.split('/').last, write.fields),
    );
  }
  return recipients;
}

_RecipientDoc _recipientDocFromFields(String id, Map<String, Object?> fields) {
  return _RecipientDoc(
    id: id,
    displayName: fields['displayName']?.toString() ?? '',
    phoneE164: _normalizePhoneE164(fields['phoneE164']?.toString() ?? ''),
    enabled: fields['enabled'] == true,
  );
}

List<_RecipientDoc> _resolveRecipients(
  List<_RecipientDoc> tenantRecipients,
  List<_RecipientDoc> deviceRecipients,
) {
  final Map<String, _RecipientDoc> byPhone = <String, _RecipientDoc>{};
  for (final _RecipientDoc recipient in <_RecipientDoc>[
    ...tenantRecipients,
    ...deviceRecipients,
  ]) {
    if (!recipient.enabled || recipient.phoneE164.isEmpty) continue;
    byPhone[recipient.phoneE164] = recipient;
  }
  return byPhone.values.toList(growable: false);
}

_PhoneComparison _compareRecipientPhones({
  required List<legacy.AlertRecipient> legacyRecipients,
  required List<_RecipientDoc> modernRecipients,
}) {
  final Set<String> legacyPhones = <String>{};
  final Set<String> modernPhones = <String>{};
  int invalid = 0;
  for (final legacy.AlertRecipient recipient in legacyRecipients) {
    final String phone = _normalizePhoneE164(recipient.phone);
    if (phone.isEmpty) {
      invalid += 1;
    } else {
      legacyPhones.add(phone);
    }
  }
  for (final _RecipientDoc recipient in modernRecipients) {
    final String phone = _normalizePhoneE164(recipient.phoneE164);
    if (phone.isEmpty) {
      invalid += 1;
    } else {
      modernPhones.add(phone);
    }
  }
  return _PhoneComparison(
    legacyOnly: legacyPhones.difference(modernPhones).length,
    modernOnly: modernPhones.difference(legacyPhones).length,
    both: legacyPhones.intersection(modernPhones).length,
    invalid: invalid,
  );
}

bool _containsRecipient(List<_RecipientDoc> recipients, String name) {
  return recipients.any(
    (_RecipientDoc recipient) => recipient.displayName == name,
  );
}

Map<String, Object?> _thresholdsMap(AlertThresholdConfig thresholds) {
  return <String, Object?>{
    if (thresholds.min != null) 'min': thresholds.min,
    if (thresholds.max != null) 'max': thresholds.max,
    if (thresholds.threshold != null) 'threshold': thresholds.threshold,
    if (thresholds.margin != null) 'margin': thresholds.margin,
    if (thresholds.sensorFailureMin != null)
      'sensorFailureMin': thresholds.sensorFailureMin,
  };
}

Future<Map<String, Object?>> _readExistingForBackup(
  FirestoreRest firestore,
  List<String> paths,
) async {
  final Map<String, Object?> result = <String, Object?>{};
  for (final String path in paths.toSet()) {
    if (path.split('/').length.isEven) {
      result[path] = await firestore.getDoc(path);
    } else {
      result[path] = <String, Object?>{
        for (final FirestoreDoc doc in await firestore.listDocs(path))
          doc.id: doc.fields,
      };
    }
  }
  // Etapa B6.1 §12/§13: recipients modernos existentes no deben volcar
  // phoneE164 completo al backup — mismo criterio ya aplicado a
  // _legacyRecipientsInventory(maskPhones: true).
  return result.map(
    (String path, Object? value) => MapEntry(path, _maskPhonesDeep(value)),
  );
}

Object? _maskPhonesDeep(Object? value) {
  if (value is Map) {
    return value.map((Object? key, Object? nested) {
      if (key == 'phoneE164' && nested is String) {
        return MapEntry(key, legacy.maskWhatsAppPhone(nested));
      }
      return MapEntry(key, _maskPhonesDeep(nested));
    });
  }
  if (value is Iterable) {
    return value.map(_maskPhonesDeep).toList(growable: false);
  }
  return value;
}

List<Map<String, Object?>> _legacyRecipientsInventory({
  required bool maskPhones,
}) {
  final legacy.WhatsAppAlertRecipientsConfig config =
      const legacy.WhatsAppAlertRecipientsConfig();
  final List<legacy.AlertRecipient> all = <legacy.AlertRecipient>[
    ...config.globalRecipients(),
    ...config.siteRecipientsFor(tenantId: _tenantId, siteId: _siteId),
  ];
  return <Map<String, Object?>>[
    for (final legacy.AlertRecipient recipient in all)
      <String, Object?>{
        'scope': recipient.scope.name,
        'tenantId': recipient.tenantId,
        'siteId': recipient.siteId,
        'contactName': recipient.contactName,
        'phone': maskPhones
            ? legacy.maskWhatsAppPhone(recipient.phone)
            : _normalizePhoneE164(recipient.phone),
        'migrationDecision': _recipientDecision(recipient),
      },
  ];
}

String _recipientDecision(legacy.AlertRecipient recipient) {
  return switch (recipient.contactName) {
    'Nicolás Rivas' => 'migrate tenant-level the-gene-pig',
    'Enzo' || 'Mauro' => 'migrate device-level laboratorio',
    'Gerardo' || 'Demián' =>
      'keep legacy global technical Valke; no global modern scope in B6',
    _ => 'legacy ignored for migration',
  };
}

String _normalizePhoneE164(String phone) {
  final String digits = phone.replaceAll(RegExp(r'\D'), '');
  return digits.isEmpty ? '' : '+$digits';
}

bool _jsonEqual(Object? a, Object? b) {
  return jsonEncode(_canonicalJsonValue(a)) ==
      jsonEncode(_canonicalJsonValue(b));
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

String _timestampForFile(DateTime now) {
  final String iso = now.toIso8601String();
  return iso
      .replaceAll('-', '')
      .replaceAll(':', '')
      .replaceAll('.', '')
      .replaceAll('Z', 'Z');
}

void _printUsage() {
  stdout.writeln('''
Etapa B6 — migracion controlada The Gene Pig / Las Heras

Flags:
  --dry-run                         Default. No escribe.
  --apply                           Escribe documentos planificados.
  --confirm-rules-deployed          Requerido para --apply.
  --confirm-b5-manual-ok            Requerido para --apply.
  --admin-uid <uid>                 Requerido para --apply; auditoria real.
  --service-account <path>          Default: $_defaultServiceAccountPath.
  --allow-update-conflicts          Permite actualizar conflictos revisados.
  --help
''');
}

class _Args {
  const _Args({
    required this.apply,
    required this.confirmRulesDeployed,
    required this.confirmB5ManualOk,
    required this.allowUpdateConflicts,
    required this.adminUid,
    required this.serviceAccountPath,
    required this.help,
  });

  factory _Args.parse(List<String> args) {
    bool apply = false;
    bool confirmRules = false;
    bool confirmB5 = false;
    bool allowUpdateConflicts = false;
    bool help = false;
    String adminUid = '';
    String serviceAccountPath = _defaultServiceAccountPath;
    for (int i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--apply':
          apply = true;
        case '--dry-run':
          apply = false;
        case '--confirm-rules-deployed':
          confirmRules = true;
        case '--confirm-b5-manual-ok':
          confirmB5 = true;
        case '--allow-update-conflicts':
          allowUpdateConflicts = true;
        case '--admin-uid':
          i += 1;
          adminUid = i < args.length ? args[i] : '';
        case '--service-account':
          i += 1;
          serviceAccountPath = i < args.length ? args[i] : '';
        case '--help':
        case '-h':
          help = true;
        default:
          throw ArgumentError('Argumento no reconocido: ${args[i]}');
      }
    }
    return _Args(
      apply: apply,
      confirmRulesDeployed: confirmRules,
      confirmB5ManualOk: confirmB5,
      allowUpdateConflicts: allowUpdateConflicts,
      adminUid: adminUid,
      serviceAccountPath: serviceAccountPath,
      help: help,
    );
  }

  final bool apply;
  final bool confirmRulesDeployed;
  final bool confirmB5ManualOk;
  final bool allowUpdateConflicts;
  final String adminUid;
  final String serviceAccountPath;
  final bool help;

  String get adminUidOrDryRun => adminUid.trim().isEmpty ? 'dry-run' : adminUid;
}

enum _PlannedWriteKind { alertConfig, alertRecipient }

class _PlannedWrite {
  const _PlannedWrite({
    required this.kind,
    required this.path,
    required this.functionalFields,
  });

  final _PlannedWriteKind kind;
  final String path;

  /// Campos de negocio puros: sin `schemaVersion` ni auditoria. La
  /// auditoria (`createdAt`/`createdBy`/`updatedAt`/`updatedBy`) se agrega
  /// recien al momento de escribir, vía [buildCreatePayload] o
  /// [buildUpdatePayload], para que un update nunca pueda reenviar
  /// `createdAt`/`createdBy` por accidente (Etapa B6.1).
  final Map<String, Object?> functionalFields;

  /// Vista "create" de solo lectura, usada para comparacion/backup/summary
  /// cuando todavia no se escribio nada (dry-run). No incluye auditoria.
  Map<String, Object?> get fields => <String, Object?>{
    'schemaVersion': 1,
    ...functionalFields,
  };
}

enum _PlanAction { create, updateAllowed, skip, conflict }

class _PlanResult {
  const _PlanResult({required this.action, required this.write, this.existing});

  final _PlanAction action;
  final _PlannedWrite write;
  final Map<String, Object?>? existing;

  String summary({required bool maskPhones}) {
    final String actionText = switch (action) {
      _PlanAction.create => 'CREATE',
      _PlanAction.updateAllowed => 'UPDATE',
      _PlanAction.skip => 'SKIP',
      _PlanAction.conflict => 'CONFLICT',
    };
    final String detail = write.kind == _PlannedWriteKind.alertRecipient
        ? ' ${write.fields['displayName']} ${maskPhones ? legacy.maskWhatsAppPhone(write.fields['phoneE164'].toString()) : write.fields['phoneE164']}'
        : '';
    return '$actionText ${write.path}$detail';
  }
}

class _RecipientDoc {
  const _RecipientDoc({
    required this.id,
    required this.displayName,
    required this.phoneE164,
    required this.enabled,
  });

  final String id;
  final String displayName;
  final String phoneE164;
  final bool enabled;
}

class _PhoneComparison {
  const _PhoneComparison({
    required this.legacyOnly,
    required this.modernOnly,
    required this.both,
    required this.invalid,
  });

  final int legacyOnly;
  final int modernOnly;
  final int both;
  final int invalid;
}

class _RecipientValidation {
  const _RecipientValidation({
    required this.labHasNicolas,
    required this.labHasEnzo,
    required this.labHasMauro,
    required this.salaHasEnzo,
    required this.salaHasMauro,
    required this.legacyOnly,
    required this.modernOnly,
    required this.both,
    required this.invalid,
  });

  final bool labHasNicolas;
  final bool labHasEnzo;
  final bool labHasMauro;
  final bool salaHasEnzo;
  final bool salaHasMauro;
  final int legacyOnly;
  final int modernOnly;
  final int both;
  final int invalid;

  String get summary =>
      'VALIDATE recipients laboratorio(nicolas=$labHasNicolas enzo=$labHasEnzo mauro=$labHasMauro) '
      'sala1(enzo=$salaHasEnzo mauro=$salaHasMauro) '
      'comparison(legacyOnly=$legacyOnly modernOnly=$modernOnly both=$both invalid=$invalid)';
}

class FirestoreDoc {
  const FirestoreDoc({required this.id, required this.fields});

  final String id;
  final Map<String, Object?> fields;
}

class FirestoreRest {
  FirestoreRest({
    required this.projectId,
    required this.serviceAccountPath,
    required this.accessToken,
    this.baseUrl = 'https://firestore.googleapis.com',
  });

  final String projectId;
  final String serviceAccountPath;
  final String accessToken;

  /// Configurable solo para tests (apuntar a un Firestore Emulator local).
  /// El script de migracion real siempre usa el default de produccion.
  final String baseUrl;
  final HttpClient _client = HttpClient();

  static Future<FirestoreRest> fromServiceAccount({
    required String serviceAccountPath,
  }) async {
    final Map<String, dynamic> serviceAccount =
        jsonDecode(File(serviceAccountPath).readAsStringSync())
            as Map<String, dynamic>;
    final String projectId = serviceAccount['project_id'] as String;
    final String token = await _getAccessToken(serviceAccount);
    return FirestoreRest(
      projectId: projectId,
      serviceAccountPath: serviceAccountPath,
      accessToken: token,
    );
  }

  Future<Map<String, Object?>?> getDoc(String path) async {
    final HttpClientRequest request = await _client.getUrl(_uri(path));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode == HttpStatus.notFound) return null;
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'GET $path failed ${response.statusCode}: $_compactBody(body)',
      );
    }
    final Map<String, dynamic> json = jsonDecode(body) as Map<String, dynamic>;
    return _decodeFields(json);
  }

  Future<List<FirestoreDoc>> listDocs(String collectionPath) async {
    final HttpClientRequest request = await _client.getUrl(
      _uri(collectionPath),
    );
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode == HttpStatus.notFound) {
      return const <FirestoreDoc>[];
    }
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'LIST $collectionPath failed ${response.statusCode}: ${_compactBody(body)}',
      );
    }
    final Map<String, dynamic> json = jsonDecode(body) as Map<String, dynamic>;
    final Object? documents = json['documents'];
    if (documents is! List) return const <FirestoreDoc>[];
    return <FirestoreDoc>[
      for (final Map<String, dynamic> doc
          in documents.whereType<Map<String, dynamic>>())
        FirestoreDoc(
          id: (doc['name'] as String).split('/').last,
          fields: _decodeFields(doc),
        ),
    ];
  }

  /// [updateMask] es la lista de field paths (`updateMask.fieldPaths`) a
  /// fusionar. Cuando es `null`/vacio, el PATCH REEMPLAZA el documento
  /// entero (semantica real de la REST API de Firestore) — solo seguro
  /// para un CREATE, nunca para actualizar un doc existente (Etapa B6.1,
  /// hardening del hallazgo de la auditoria de B6).
  Future<void> patchDoc(
    String path,
    Map<String, Object?> fields, {
    List<String>? updateMask,
  }) async {
    final Uri baseUri = _uri(path);
    final Uri uri = (updateMask == null || updateMask.isEmpty)
        ? baseUri
        : baseUri.replace(
            queryParameters: <String, Object?>{
              'updateMask.fieldPaths': updateMask,
            },
          );
    final HttpClientRequest request = await _client.openUrl('PATCH', uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/json; charset=utf-8',
    );
    // Bug B6.2: sin esto, HttpClientRequest usa latin1 por default (al no
    // haber charset en el Content-Type original), lo que corrompe
    // silenciosamente cualquier caracter no-ASCII (p.ej. "Nicolás" -> "Nicol
    // s") al mandarlo a la REST API de Firestore. add() con bytes UTF-8
    // explicitos evita depender de la encoding mutable del request.
    request.add(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'fields': <String, Object?>{
            for (final MapEntry<String, Object?> entry in fields.entries)
              entry.key: _encodeValue(entry.value),
          },
        }),
      ),
    );
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'PATCH $path failed ${response.statusCode}: ${_compactBody(body)}',
      );
    }
  }

  /// Borra un documento. Usado por la limpieza de residuos de la Etapa
  /// B6.1 — nunca por el flujo normal de migracion (que solo CREATE/UPDATE).
  Future<void> deleteDoc(String path) async {
    final HttpClientRequest request = await _client.openUrl(
      'DELETE',
      _uri(path),
    );
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'DELETE $path failed ${response.statusCode}: ${_compactBody(body)}',
      );
    }
  }

  Uri _uri(String path) {
    return Uri.parse(
      '$baseUrl/v1/projects/$projectId/databases/$_databaseId/documents/$path',
    );
  }
}

Map<String, Object?> _decodeFields(Map<String, dynamic> document) {
  final Object? raw = document['fields'];
  if (raw is! Map) return const <String, Object?>{};
  return raw.map(
    (Object? key, Object? value) =>
        MapEntry(key.toString(), _decodeValue(value)),
  );
}

Object? _decodeValue(Object? value) {
  if (value is! Map) return null;
  if (value.containsKey('nullValue')) return null;
  if (value.containsKey('stringValue')) return value['stringValue']?.toString();
  if (value.containsKey('booleanValue')) return value['booleanValue'] == true;
  if (value.containsKey('integerValue')) {
    return int.tryParse(value['integerValue'].toString());
  }
  if (value.containsKey('doubleValue')) {
    return double.tryParse(value['doubleValue'].toString());
  }
  if (value.containsKey('timestampValue')) {
    return DateTime.tryParse(value['timestampValue'].toString());
  }
  final Object? mapValue = value['mapValue'];
  if (mapValue is Map) {
    final Object? fields = mapValue['fields'];
    if (fields is! Map) return const <String, Object?>{};
    return fields.map(
      (Object? key, Object? nested) =>
          MapEntry(key.toString(), _decodeValue(nested)),
    );
  }
  final Object? arrayValue = value['arrayValue'];
  if (arrayValue is Map) {
    final Object? values = arrayValue['values'];
    if (values is! List) return const <Object?>[];
    return values.map(_decodeValue).toList(growable: false);
  }
  return null;
}

Map<String, Object?> _encodeValue(Object? value) {
  if (value == null) return <String, Object?>{'nullValue': null};
  if (value is bool) return <String, Object?>{'booleanValue': value};
  if (value is int) return <String, Object?>{'integerValue': value.toString()};
  if (value is double) return <String, Object?>{'doubleValue': value};
  if (value is DateTime) {
    return <String, Object?>{'timestampValue': value.toUtc().toIso8601String()};
  }
  if (value is String) return <String, Object?>{'stringValue': value};
  if (value is Iterable) {
    return <String, Object?>{
      'arrayValue': <String, Object?>{
        'values': [for (final Object? item in value) _encodeValue(item)],
      },
    };
  }
  if (value is Map) {
    return <String, Object?>{
      'mapValue': <String, Object?>{
        'fields': <String, Object?>{
          for (final MapEntry<Object?, Object?> entry in value.entries)
            entry.key.toString(): _encodeValue(entry.value),
        },
      },
    };
  }
  throw ArgumentError.value(value, 'value', 'Unsupported Firestore value');
}

String _compactBody(String body) {
  final String compacted = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  return compacted.length <= 240
      ? compacted
      : '${compacted.substring(0, 240)}...';
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
    'b6-alert-migration-',
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
        throw StateError(
          'token exchange failed ${response.statusCode}: ${_compactBody(body)}',
        );
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
