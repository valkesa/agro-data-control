import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control_backend/src/alert_configuration_contracts.dart';
import 'package:agro_data_control_backend/src/alert_models.dart';
import 'package:agro_data_control_backend/src/alert_notifications.dart';
import 'package:agro_data_control_backend/src/alert_priority.dart';
import 'package:agro_data_control_backend/src/alert_recipient_validation.dart';
import 'package:agro_data_control_backend/src/hierarchical_alert_recipients.dart';
import 'package:agro_data_control_backend/src/whatsapp_alert_recipients.dart';

const String _projectId = 'demo-alert-recipients-rules-test';
const int _port = 8110;
const String _baseUrl = 'http://127.0.0.1:$_port';

Future<void> main() async {
  _testResolverPrecedenceAndDisabledDuplicates();
  await _testCacheHitTtlRefreshAndError();
  await _testProviderValidateFallbackAndHierarchicalSendList();

  final Directory emulatorProjectDir = await _writeEmulatorProject();
  final StringBuffer emulatorLog = StringBuffer();
  Process? emulatorProcess;

  try {
    emulatorProcess = await _startEmulator(emulatorProjectDir, emulatorLog);
    await _waitForReady(emulatorLog);
    await _waitForRestApi();
    await _seedAuthContext();

    await _testRulesOwnerCreate();
    await _testRulesTenantAdminOwnTenantCreate();
    await _testRulesTenantAdminOtherTenantDenied();
    await _testRulesUnknownFieldDenied();
    await _testRulesInvalidPhoneDenied();
    await _testRulesInvalidSchemaVersionDenied();
    await _testRulesEnabledFalseAccepted();
    await _testRulesSecondAdminUpdatesCreatedByOther();
    await _testRulesCreatedByMutationDenied();
    await _testRulesWrongUpdatedByDenied();
    await _testRulesDeleteAllowedOnlyForAuthorizedWriter();
    await _testPatchUpdateMaskPreservesAuditAndPhone();
    await _testFirestoreLoaderResolverEffectiveRecipients();
    await _testB63ValidateProviderEndToEndAgainstRealFirestore();

    // ignore: avoid_print
    print(
      'hierarchical_alert_recipients_firestore_emulator_test: all expectations passed',
    );
  } finally {
    if (emulatorProcess != null) {
      emulatorProcess.kill(ProcessSignal.sigterm);
      try {
        await emulatorProcess.exitCode.timeout(const Duration(seconds: 15));
      } on TimeoutException {
        emulatorProcess.kill(ProcessSignal.sigkill);
      }
    }
    if (await emulatorProjectDir.exists()) {
      await emulatorProjectDir.delete(recursive: true);
    }
  }
}

void _testResolverPrecedenceAndDisabledDuplicates() {
  final List<HierarchicalAlertRecipient> resolved =
      const HierarchicalAlertRecipientResolver().resolve(
        legacyRecipients: <HierarchicalAlertRecipient>[
          _recipient(
            id: 'legacy-gerardo',
            name: 'Gerardo Legacy',
            phone: '+5491138267368',
            scope: AlertRecipientConfigScope.legacyGlobal,
            origin: AlertConfigOrigin.legacy,
          ),
        ],
        tenantRecipients: <HierarchicalAlertRecipient>[
          _recipient(
            id: 'tenant-gerardo',
            name: 'Gerardo Moderno',
            phone: '+5491138267368',
            scope: AlertRecipientConfigScope.tenant,
            origin: AlertConfigOrigin.tenant,
          ),
          _recipient(
            id: 'tenant-active',
            name: 'Tenant Activo',
            phone: '+5491111111111',
            scope: AlertRecipientConfigScope.tenant,
            origin: AlertConfigOrigin.tenant,
          ),
        ],
        deviceRecipients: <HierarchicalAlertRecipient>[
          _recipient(
            id: 'device-disabled-duplicate',
            name: 'No bloquea heredado',
            phone: '+5491111111111',
            enabled: false,
            scope: AlertRecipientConfigScope.device,
            origin: AlertConfigOrigin.device,
          ),
        ],
        roomRecipients: <HierarchicalAlertRecipient>[
          _recipient(
            id: 'room-gerardo',
            name: 'Gerardo Room',
            phone: '+5491138267368',
            scope: AlertRecipientConfigScope.room,
            origin: AlertConfigOrigin.room,
          ),
        ],
      );
  _expect(resolved.length == 2, 'additive union deduplicates by phone');
  _expect(
    resolved.first.id == 'room-gerardo',
    'room metadata wins over tenant and legacy duplicate',
  );
  _expect(
    resolved.any((HierarchicalAlertRecipient r) => r.id == 'tenant-active'),
    'disabled duplicate does not block inherited tenant recipient',
  );
}

Future<void> _testCacheHitTtlRefreshAndError() async {
  DateTime now = DateTime.utc(2026, 9, 7, 12);
  final _FakeRecipientLoader loader = _FakeRecipientLoader();
  final HierarchicalAlertRecipientsCache cache =
      HierarchicalAlertRecipientsCache(
        loader: loader,
        ttl: const Duration(minutes: 5),
        now: () => now,
      );
  final AlertConfigurationTarget target = _target(
    tenantId: 'the-gene-pig',
    siteId: 'las-heras',
    deviceId: 'laboratorio',
  );

  loader.device = <HierarchicalAlertRecipient>[
    _recipient(id: 'enzo', name: 'Enzo', phone: '+5491123040959'),
  ];
  final List<HierarchicalAlertRecipient> first = await cache.getOrLoad(
    target: target,
  );
  _expect(first.length == 1, 'first cache load returns recipients');
  _expect(loader.loadCount == 1, 'first cache load hits loader');
  _expect(cache.lastReadCount == 3, 'device target reads tenant/site/device');

  loader.device = <HierarchicalAlertRecipient>[
    _recipient(id: 'mauro', name: 'Mauro', phone: '+5492227516703'),
  ];
  final List<HierarchicalAlertRecipient> hit = await cache.getOrLoad(
    target: target,
  );
  _expect(hit.single.id == 'enzo', 'cache hit keeps previous value');
  _expect(loader.loadCount == 1, 'cache hit does not reload');
  _expect(cache.lastReadCount == 0, 'cache hit reports zero reads');

  now = now.add(const Duration(minutes: 6));
  final List<HierarchicalAlertRecipient> afterTtl = await cache.getOrLoad(
    target: target,
  );
  _expect(afterTtl.single.id == 'mauro', 'TTL reloads fresh recipients');
  _expect(loader.loadCount == 2, 'TTL reload hits loader');

  loader.device = <HierarchicalAlertRecipient>[
    _recipient(id: 'enzo', name: 'Enzo', phone: '+5491123040959'),
  ];
  await cache.refreshTargets(targets: <AlertConfigurationTarget>[target]);
  _expect(cache.get(target)!.single.id == 'enzo', 'explicit refresh updates');

  loader.throwOnLoad = true;
  try {
    await cache.getOrLoad(
      target: _target(
        tenantId: 'la-payana',
        siteId: 'roque-perez',
        deviceId: 'arco-desinfeccion',
      ),
    );
    _expect(false, 'loader error should throw');
  } catch (_) {
    _expect(cache.lastError != null, 'cache stores last error');
  }
}

Future<void> _testProviderValidateFallbackAndHierarchicalSendList() async {
  final _FakeRecipientLoader loader = _FakeRecipientLoader(throwOnLoad: true);
  final HierarchicalAlertRecipientsCache failingCache =
      HierarchicalAlertRecipientsCache(loader: loader);
  final HierarchicalAlertRecipientProvider validateProvider =
      HierarchicalAlertRecipientProvider(
        mode: AlertRecipientProviderMode.validate,
        legacyConfig: const WhatsAppAlertRecipientsConfig(),
        cache: failingCache,
      );
  final PendingNotificationBatch legacyBatch = _batch(
    tenantId: 'the_good_pig',
    siteId: 'main_site',
    muntersId: 'munters1',
  )..close(DateTime.utc(2026, 9, 7, 12));
  final List<AlertRecipient> fallback = await validateProvider
      .recipientsForBatch(
        legacyBatch,
        clientName: 'The Good Pig',
        siteName: 'Sitio principal',
      );
  _expect(fallback.length == 2, 'validate mode falls back to legacy on error');

  final _FakeRecipientLoader hierarchicalLoader = _FakeRecipientLoader(
    device: <HierarchicalAlertRecipient>[
      _recipient(id: 'enzo', name: 'Enzo', phone: '+5491123040959'),
      _recipient(id: 'mauro', name: 'Mauro', phone: '+5492227516703'),
    ],
  );
  final HierarchicalAlertRecipientProvider hierarchicalProvider =
      HierarchicalAlertRecipientProvider(
        mode: AlertRecipientProviderMode.hierarchical,
        legacyConfig: const WhatsAppAlertRecipientsConfig(),
        cache: HierarchicalAlertRecipientsCache(loader: hierarchicalLoader),
      );
  final List<AlertRecipient> modern = await hierarchicalProvider
      .recipientsForBatch(
        _batch(
          tenantId: 'the-gene-pig',
          siteId: 'las-heras',
          muntersId: 'laboratorio',
        )..close(DateTime.utc(2026, 9, 7, 12)),
        clientName: 'Gene Pig',
        siteName: 'Las Heras',
      );
  // Legacy para the-gene-pig/las-heras: Gerardo, Demián (global) + Nicolás
  // Rivas, Enzo, Mauro (site) = 5, deduplicados por telefono contra los 2
  // device recipients del fake loader (mismos numeros que Enzo/Mauro) -> 5.
  _expect(modern.length == 5, 'hierarchical mode sends modern + legacy union');
  _expect(
    modern.any((AlertRecipient r) => r.contactName == 'Enzo') &&
        modern.any((AlertRecipient r) => r.contactName == 'Mauro'),
    'hierarchical mode includes device recipients',
  );
}

Future<void> _testRulesOwnerCreate() async {
  final int status = await _patchAs(
    uid: 'owner-uid',
    path: 'tenants/the-gene-pig/alertRecipients/gerardo',
    fields: _recipientFields(
      displayName: 'Gerardo',
      phoneE164: '+5491100000001',
      updatedBy: 'owner-uid',
    ),
  );
  _expect(status == 200, 'owner can create tenant alert recipient');
}

Future<void> _testRulesTenantAdminOwnTenantCreate() async {
  final int status = await _patchAs(
    uid: 'admin-a',
    path: 'tenants/the-gene-pig/sites/las-heras/alertRecipients/site-resp',
    fields: _recipientFields(
      displayName: 'Responsable Las Heras',
      phoneE164: '+5491111111111',
      updatedBy: 'admin-a',
    ),
  );
  _expect(status == 200, 'tenant_admin can create own tenant recipient');
}

Future<void> _testRulesTenantAdminOtherTenantDenied() async {
  final int status = await _patchAs(
    uid: 'admin-a',
    path: 'tenants/la-payana/alertRecipients/cross',
    fields: _recipientFields(
      displayName: 'Cross Tenant',
      phoneE164: '+5492222222222',
      updatedBy: 'admin-a',
    ),
  );
  _expect(status == 403, 'tenant_admin cannot write another tenant recipient');
}

Future<void> _testRulesUnknownFieldDenied() async {
  final int status = await _patchAs(
    uid: 'owner-uid',
    path: 'tenants/the-gene-pig/alertRecipients/unknown-field',
    fields: _recipientFields(
      displayName: 'Unknown',
      phoneE164: '+5491133333333',
      updatedBy: 'owner-uid',
      extra: <String, Object?>{'debug': true},
    ),
  );
  _expect(status == 403, 'unknown alert recipient field is denied');
}

Future<void> _testRulesInvalidPhoneDenied() async {
  final int status = await _patchAs(
    uid: 'owner-uid',
    path: 'tenants/the-gene-pig/alertRecipients/invalid-phone',
    fields: _recipientFields(
      displayName: 'Invalid Phone',
      phoneE164: '5491138267368',
      updatedBy: 'owner-uid',
    ),
  );
  _expect(status == 403, 'invalid phoneE164 is denied');
}

Future<void> _testRulesInvalidSchemaVersionDenied() async {
  final int status = await _patchAs(
    uid: 'owner-uid',
    path: 'tenants/the-gene-pig/alertRecipients/invalid-schema',
    fields: _recipientFields(
      displayName: 'Invalid Schema',
      phoneE164: '+5491138267368',
      updatedBy: 'owner-uid',
      schemaVersion: 2,
    ),
  );
  _expect(status == 403, 'invalid schemaVersion is denied');
}

Future<void> _testRulesEnabledFalseAccepted() async {
  final int status = await _patchAs(
    uid: 'owner-uid',
    path: 'tenants/the-gene-pig/alertRecipients/disabled',
    fields: _recipientFields(
      displayName: 'Disabled',
      phoneE164: '+5491144444444',
      enabled: false,
      updatedBy: 'owner-uid',
    ),
  );
  _expect(status == 200, 'enabled=false is accepted');
}

Future<void> _testRulesSecondAdminUpdatesCreatedByOther() async {
  const String path = 'tenants/the-gene-pig/alertRecipients/audit-shared';
  final int createStatus = await _patchAs(
    uid: 'admin-a',
    path: path,
    fields: _recipientFields(
      displayName: 'Creado Por A',
      phoneE164: '+5491155555555',
      updatedBy: 'admin-a',
      createdBy: 'admin-a',
    ),
  );
  _expect(createStatus == 200, 'admin-a creates recipient audit fixture');

  final int updateStatus = await _patchAs(
    uid: 'admin-b',
    path: path,
    fields: _recipientFields(
      displayName: 'Actualizado Por B',
      phoneE164: '+5491155555555',
      updatedBy: 'admin-b',
      createdBy: 'admin-a',
    ),
  );
  _expect(updateStatus == 200, 'admin-b can update preserving createdBy');
}

Future<void> _testRulesCreatedByMutationDenied() async {
  const String path = 'tenants/the-gene-pig/alertRecipients/audit-mutation';
  final int createStatus = await _patchAs(
    uid: 'admin-a',
    path: path,
    fields: _recipientFields(
      displayName: 'No Mutar',
      phoneE164: '+5491166666666',
      updatedBy: 'admin-a',
      createdBy: 'admin-a',
    ),
  );
  _expect(createStatus == 200, 'admin-a creates mutation fixture');

  final int updateStatus = await _patchAs(
    uid: 'admin-b',
    path: path,
    fields: _recipientFields(
      displayName: 'Intento Mutar',
      phoneE164: '+5491166666666',
      updatedBy: 'admin-b',
      createdBy: 'admin-b',
    ),
  );
  _expect(updateStatus == 403, 'createdBy mutation is denied');
}

Future<void> _testRulesWrongUpdatedByDenied() async {
  final int status = await _patchAs(
    uid: 'admin-a',
    path: 'tenants/the-gene-pig/alertRecipients/wrong-updated-by',
    fields: _recipientFields(
      displayName: 'Wrong UpdatedBy',
      phoneE164: '+5491177777777',
      updatedBy: 'admin-b',
      createdBy: 'admin-a',
    ),
  );
  _expect(status == 403, 'wrong updatedBy is denied');
}

Future<void> _testRulesDeleteAllowedOnlyForAuthorizedWriter() async {
  const String path =
      'tenants/the-gene-pig/devices/laboratorio/alertRecipients/delete-me';
  final int createStatus = await _patchAs(
    uid: 'owner-uid',
    path: path,
    fields: _recipientFields(
      displayName: 'Delete Me',
      phoneE164: '+5491188888888',
      updatedBy: 'owner-uid',
    ),
  );
  _expect(createStatus == 200, 'owner creates delete fixture');
  final int denied = await _deleteAs(uid: 'admin-other', path: path);
  _expect(denied == 403, 'other tenant admin cannot delete');
  final int allowed = await _deleteAs(uid: 'admin-a', path: path);
  _expect(allowed == 200, 'own tenant admin can delete');
}

Future<void> _testPatchUpdateMaskPreservesAuditAndPhone() async {
  const String path = 'tenants/the-gene-pig/alertRecipients/update-mask';
  final int createStatus = await _patchAs(
    uid: 'admin-a',
    path: path,
    fields: _recipientFields(
      displayName: 'Update Mask',
      phoneE164: '+5491199999999',
      updatedBy: 'admin-a',
      createdBy: 'admin-a',
    ),
  );
  _expect(createStatus == 200, 'admin-a creates updateMask fixture');

  final int updateStatus = await _patchAs(
    uid: 'admin-b',
    path: path,
    fields: <String, Object?>{
      'enabled': false,
      'updatedAt': DateTime.utc(2026, 9, 7, 13),
      'updatedBy': 'admin-b',
    },
    updateMask: <String>['enabled', 'updatedAt', 'updatedBy'],
  );
  _expect(updateStatus == 200, 'updateMask partial update is accepted');

  final Map<String, Object?> loaded = await _getAs(uid: 'admin-b', path: path);
  _expect(loaded['enabled'] == false, 'updateMask changes enabled');
  _expect(loaded['createdBy'] == 'admin-a', 'updateMask preserves createdBy');
  _expect(
    loaded['phoneE164'] == '+5491199999999',
    'updateMask preserves phoneE164',
  );
}

Future<void> _testFirestoreLoaderResolverEffectiveRecipients() async {
  await _patchAs(
    uid: 'owner-uid',
    path: 'tenants/the-gene-pig/alertRecipients/gerardo-modern',
    fields: _recipientFields(
      displayName: 'Gerardo Moderno',
      phoneE164: '+5491138267368',
      updatedBy: 'owner-uid',
    ),
  );
  await _patchAs(
    uid: 'admin-a',
    path: 'tenants/the-gene-pig/sites/las-heras/alertRecipients/site-resp-2',
    fields: _recipientFields(
      displayName: 'Responsable Las Heras',
      phoneE164: '+5491112121212',
      updatedBy: 'admin-a',
    ),
  );
  await _patchAs(
    uid: 'admin-a',
    path: 'tenants/the-gene-pig/devices/laboratorio/alertRecipients/enzo',
    fields: _recipientFields(
      displayName: 'Enzo',
      phoneE164: '+5491123040959',
      updatedBy: 'admin-a',
    ),
  );
  await _patchAs(
    uid: 'admin-a',
    path: 'tenants/the-gene-pig/devices/laboratorio/alertRecipients/mauro',
    fields: _recipientFields(
      displayName: 'Mauro',
      phoneE164: '+5492227516703',
      updatedBy: 'admin-a',
    ),
  );
  await _patchAs(
    uid: 'admin-other',
    path:
        'tenants/la-payana/devices/arco-desinfeccion/alertRecipients/arco-resp',
    fields: _recipientFields(
      displayName: 'Responsable Arco',
      phoneE164: '+5492227000001',
      updatedBy: 'admin-other',
    ),
  );

  final HierarchicalAlertRecipientsCache cache =
      HierarchicalAlertRecipientsCache(loader: _loaderFor('owner-uid'));
  final List<HierarchicalAlertRecipient> laboratorio = await cache.getOrLoad(
    target: _target(
      tenantId: 'the-gene-pig',
      siteId: 'las-heras',
      deviceId: 'laboratorio',
    ),
    legacyRecipients: const LegacyAlertRecipientAdapter().fromLegacyRecipients(
      const WhatsAppAlertRecipientsConfig().recipientsFor(
        tenantId: 'the-gene-pig',
        siteId: 'las-heras',
      ),
    ),
  );
  _expect(cache.lastReadCount == 3, 'device target reads three collections');
  _expect(
    laboratorio.any(
          (HierarchicalAlertRecipient r) => r.displayName == 'Enzo',
        ) &&
        laboratorio.any(
          (HierarchicalAlertRecipient r) => r.displayName == 'Mauro',
        ),
    'laboratorio includes Enzo and Mauro device recipients',
  );
  _expect(
    laboratorio
            .where(
              (HierarchicalAlertRecipient r) => r.phoneE164 == '+5491138267368',
            )
            .single
            .displayName ==
        'Gerardo Moderno',
    'modern tenant metadata wins over legacy duplicate',
  );

  final List<HierarchicalAlertRecipient> otroDevice = await cache.getOrLoad(
    target: _target(
      tenantId: 'the-gene-pig',
      siteId: 'las-heras',
      deviceId: 'otro-device',
    ),
  );
  _expect(
    !otroDevice.any(
          (HierarchicalAlertRecipient r) => r.displayName == 'Enzo',
        ) &&
        !otroDevice.any(
          (HierarchicalAlertRecipient r) => r.displayName == 'Mauro',
        ),
    'other device in same site does not include laboratorio recipients',
  );

  final List<HierarchicalAlertRecipient> laPayana = await cache.getOrLoad(
    target: _target(
      tenantId: 'la-payana',
      siteId: 'roque-perez',
      deviceId: 'arco-desinfeccion',
    ),
  );
  _expect(
    laPayana.any(
      (HierarchicalAlertRecipient r) => r.displayName == 'Responsable Arco',
    ),
    'la payana arco device recipient is included',
  );

  final List<HierarchicalAlertRecipient> otroArco = await cache.getOrLoad(
    target: _target(
      tenantId: 'la-payana',
      siteId: 'roque-perez',
      deviceId: 'otro-arco',
    ),
  );
  _expect(
    !otroArco.any(
      (HierarchicalAlertRecipient r) => r.displayName == 'Responsable Arco',
    ),
    'la payana device recipient does not leak to another device',
  );

  final List<HierarchicalAlertRecipient> cached = await cache.getOrLoad(
    target: _target(
      tenantId: 'the-gene-pig',
      siteId: 'las-heras',
      deviceId: 'laboratorio',
    ),
  );
  _expect(cached.length == laboratorio.length, 'cache hit returns same list');
  _expect(cache.lastReadCount == 0, 'cache hit has zero reads');
}

/// Etapa B6.3 §35 — integración real end-to-end: Firestore real (emulador)
/// → cache → `HierarchicalAlertRecipientProvider` en modo `validate` →
/// comparación → selección del sender (debe seguir siendo legacy). Usa el
/// mismo Enzo/Mauro ya sembrados por
/// `_testFirestoreLoaderResolverEffectiveRecipients` en
/// `tenants/the-gene-pig/devices/laboratorio/alertRecipients`.
Future<void> _testB63ValidateProviderEndToEndAgainstRealFirestore() async {
  const WhatsAppAlertRecipientsConfig legacyConfig =
      WhatsAppAlertRecipientsConfig();
  final AlertRecipientValidationTracker tracker =
      AlertRecipientValidationTracker();
  final HierarchicalAlertRecipientsCache cache =
      HierarchicalAlertRecipientsCache(loader: _loaderFor('owner-uid'));
  final HierarchicalAlertRecipientProvider provider =
      HierarchicalAlertRecipientProvider(
        mode: AlertRecipientProviderMode.validate,
        legacyConfig: legacyConfig,
        cache: cache,
        validationTracker: tracker,
      );

  final PendingNotificationBatch batch = _batch(
    tenantId: 'the-gene-pig',
    siteId: 'las-heras',
    muntersId: 'laboratorio',
  );
  final List<AlertRecipient> expectedLegacy = legacyConfig.recipientsFor(
    tenantId: 'the-gene-pig',
    siteId: 'las-heras',
  );

  final List<AlertRecipient> sent = await provider.recipientsForBatch(
    batch,
    clientName: 'Gene Pig',
    siteName: 'Las Heras',
  );
  _expect(
    sent.length == expectedLegacy.length,
    '§35 validate: el sender real sigue siendo legacy (mismo tamaño de lista)',
  );
  _expect(cache.lastReadCount > 0, '§35 primer load real: reads > 0');
  _expect(tracker.comparisons == 1, '§35 se registró 1 comparación real');
  _expect(
    tracker.lastError == null,
    '§35 sin error: Firestore real respondió correctamente',
  );

  // Segunda pasada (dentro del TTL): cache hit, cero reads nuevos —
  // Etapa B6.3 §7/§9/§33 "polling = 0 reads Firestore agregadas".
  await provider.recipientsForBatch(
    batch,
    clientName: 'Gene Pig',
    siteName: 'Las Heras',
  );
  _expect(
    cache.lastReadCount == 0,
    '§33/§35 segunda resolución del mismo target: 0 reads (cache hit)',
  );
  _expect(
    tracker.comparisons == 2,
    '§35 la segunda pasada sigue comparando (aunque no lea Firestore de nuevo)',
  );
}

Future<Directory> _writeEmulatorProject() async {
  final Directory dir = await Directory.systemTemp.createTemp(
    'alert-recipients-rules-test-',
  );
  final String rules = await File('../firestore.rules').exists()
      ? await File('../firestore.rules').readAsString()
      : await File('firestore.rules').readAsString();
  await File('${dir.path}/firestore.rules').writeAsString(rules);
  await File('${dir.path}/firebase.json').writeAsString(
    jsonEncode(<String, Object?>{
      'firestore': <String, Object?>{'rules': 'firestore.rules'},
      'emulators': <String, Object?>{
        'firestore': <String, Object?>{'port': _port},
      },
    }),
  );
  return dir;
}

Future<Process> _startEmulator(Directory projectDir, StringBuffer log) async {
  final Process process = await Process.start('firebase', <String>[
    'emulators:start',
    '--only',
    'firestore',
    '--project',
    _projectId,
  ], workingDirectory: projectDir.path);
  process.stdout.transform(utf8.decoder).listen(log.write);
  process.stderr.transform(utf8.decoder).listen(log.write);
  return process;
}

Future<void> _waitForReady(StringBuffer log) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    if (log.toString().contains('All emulators ready')) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError(
    'Firestore emulator did not report ready within 90s.\n--- emulator log ---\n$log',
  );
}

Future<void> _waitForRestApi() async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 30));
  final HttpClient client = HttpClient();
  try {
    while (DateTime.now().isBefore(deadline)) {
      try {
        final HttpClientRequest request = await client.getUrl(
          Uri.parse(
            '$_baseUrl/v1/projects/$_projectId/databases/(default)/documents/tenants',
          ),
        );
        final HttpClientResponse response = await request.close();
        await response.drain<void>();
        if (response.statusCode == 200 || response.statusCode == 403) return;
      } catch (_) {
        // Keep polling.
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  } finally {
    client.close(force: true);
  }
  throw StateError('Firestore emulator REST API never became reachable.');
}

Future<void> _seedAuthContext() async {
  await _adminPatch('users/owner-uid', <String, Object?>{
    'active': true,
    'role': 'owner',
    'activeTenantId': 'the-gene-pig',
  });
  await _adminPatch('users/admin-a', <String, Object?>{
    'active': true,
    'role': 'tenant_admin',
    'activeTenantId': 'the-gene-pig',
  });
  await _adminPatch('users/admin-b', <String, Object?>{
    'active': true,
    'role': 'tenant_admin',
    'activeTenantId': 'the-gene-pig',
  });
  await _adminPatch('users/admin-other', <String, Object?>{
    'active': true,
    'role': 'tenant_admin',
    'activeTenantId': 'la-payana',
  });
  await _adminPatch('tenants/the-gene-pig/members/admin-a', <String, Object?>{
    'active': true,
    'role': 'tenant_admin',
  });
  await _adminPatch('tenants/the-gene-pig/members/admin-b', <String, Object?>{
    'active': true,
    'role': 'tenant_admin',
  });
  await _adminPatch('tenants/la-payana/members/admin-other', <String, Object?>{
    'active': true,
    'role': 'tenant_admin',
  });
}

Future<void> _adminPatch(String path, Map<String, Object?> fields) async {
  final int status = await _write(
    method: 'PATCH',
    path: path,
    fields: fields,
    bearer: 'owner',
  );
  if (status != 200) {
    throw StateError('Admin seed failed for $path status=$status');
  }
}

Future<int> _patchAs({
  required String uid,
  required String path,
  required Map<String, Object?> fields,
  List<String>? updateMask,
}) {
  return _write(
    method: 'PATCH',
    path: path,
    fields: fields,
    bearer: _jwt(uid),
    updateMask: updateMask,
  );
}

Future<Map<String, Object?>> _getAs({
  required String uid,
  required String path,
}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.getUrl(_docUri(path));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${_jwt(uid)}');
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw StateError('GET failed status=${response.statusCode} body=$body');
    }
    return _decodeFields(jsonDecode(body) as Map<String, dynamic>);
  } finally {
    client.close(force: true);
  }
}

Future<int> _deleteAs({required String uid, required String path}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.deleteUrl(_docUri(path));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${_jwt(uid)}');
    final HttpClientResponse response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

Future<int> _write({
  required String method,
  required String path,
  required Map<String, Object?> fields,
  required String bearer,
  List<String>? updateMask,
}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = method == 'PATCH'
        ? await client.patchUrl(_docUri(path, updateMask: updateMask))
        : await client.postUrl(_docUri(path, updateMask: updateMask));
    request.headers.set('Content-Type', 'application/json');
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    request.write(
      jsonEncode(<String, Object?>{
        'fields': <String, Object?>{
          for (final MapEntry<String, Object?> entry in fields.entries)
            entry.key: _encodeFirestoreValue(entry.value),
        },
      }),
    );
    final HttpClientResponse response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

Uri _docUri(String path, {List<String>? updateMask}) {
  final Uri base = Uri.parse(
    '$_baseUrl/v1/projects/$_projectId/databases/(default)/documents/$path',
  );
  if (updateMask == null || updateMask.isEmpty) return base;
  final String query = updateMask
      .map(
        (String field) =>
            'updateMask.fieldPaths=${Uri.encodeQueryComponent(field)}',
      )
      .join('&');
  return Uri.parse('$base?$query');
}

Map<String, Object?> _recipientFields({
  required String displayName,
  required String phoneE164,
  required String updatedBy,
  String? createdBy,
  bool enabled = true,
  int schemaVersion = 1,
  Map<String, Object?> extra = const <String, Object?>{},
}) {
  return <String, Object?>{
    'schemaVersion': schemaVersion,
    'displayName': displayName,
    'phoneE164': phoneE164,
    'enabled': enabled,
    'createdAt': DateTime.utc(2026, 9, 7, 12),
    'createdBy': createdBy ?? updatedBy,
    'updatedAt': DateTime.utc(2026, 9, 7, 12),
    'updatedBy': updatedBy,
    ...extra,
  };
}

AlertConfigurationTarget _target({
  required String tenantId,
  required String siteId,
  required String deviceId,
  String? roomId,
}) {
  return AlertConfigurationTarget(
    tenantId: tenantId,
    siteId: siteId,
    scope: roomId == null
        ? AlertConfigurationScope.device
        : AlertConfigurationScope.room,
    deviceId: deviceId,
    roomId: roomId,
    snapshotUnitKey: deviceId,
    muntersId: deviceId,
  );
}

FirestoreHierarchicalAlertRecipientLoader _loaderFor(String uid) {
  return FirestoreHierarchicalAlertRecipientLoader(
    projectId: _projectId,
    databaseId: '(default)',
    serviceAccountJsonPath: 'unused-in-emulator-mode',
    baseUrl: _baseUrl,
    accessTokenProvider: () async => _jwt(uid),
  );
}

PendingNotificationBatch _batch({
  required String tenantId,
  required String siteId,
  required String muntersId,
}) {
  final PendingNotificationBatch batch = PendingNotificationBatch(
    batchId: 'NTF-20260907-120000-TEST',
    key: NotificationBatchKey(
      tenantId: tenantId,
      siteId: siteId,
      roomId: 'room_1',
    ),
    roomNumber: 1,
    muntersId: muntersId,
    plcLabel: 'Sala 1',
    createdAt: DateTime.utc(2026, 9, 7, 12),
    closesAt: DateTime.utc(2026, 9, 7, 12, 0, 10),
    alertOrder: <AlertType, int>{
      for (final AlertType type in alertPriorityOrder)
        type: alertPriorityIndex(type) + 1,
    },
  );
  batch.add(
    EvaluatedAlert(
      key: AlertInstanceKey(
        tenantId: tenantId,
        siteId: siteId,
        roomId: 'room_1',
        roomNumber: 1,
        muntersId: muntersId,
        alertType: AlertType.muntersDoorOpen,
      ),
      type: AlertType.muntersDoorOpen,
      isActive: true,
      sendWhatsapp: true,
      thresholdKind: AlertThresholdKind.maximum,
      unit: '',
      evaluatedAt: DateTime.utc(2026, 9, 7, 12),
    ),
  );
  return batch;
}

HierarchicalAlertRecipient _recipient({
  required String id,
  required String name,
  required String phone,
  bool enabled = true,
  AlertRecipientConfigScope scope = AlertRecipientConfigScope.device,
  AlertConfigOrigin origin = AlertConfigOrigin.device,
}) {
  return HierarchicalAlertRecipient(
    id: id,
    displayName: name,
    phoneE164: phone,
    enabled: enabled,
    scope: scope,
    origin: origin,
  );
}

Map<String, Object?> _encodeFirestoreValue(Object? value) {
  if (value == null) return <String, Object?>{'nullValue': null};
  if (value is bool) return <String, Object?>{'booleanValue': value};
  if (value is int) return <String, Object?>{'integerValue': value.toString()};
  if (value is double) return <String, Object?>{'doubleValue': value};
  if (value is String) return <String, Object?>{'stringValue': value};
  if (value is DateTime) {
    return <String, Object?>{'timestampValue': value.toUtc().toIso8601String()};
  }
  throw ArgumentError.value(value, 'value', 'Unsupported Firestore value type');
}

Map<String, Object?> _decodeFields(Map<String, dynamic> document) {
  final Map<String, dynamic> fields =
      document['fields'] as Map<String, dynamic>? ?? <String, dynamic>{};
  return fields.map(
    (String key, dynamic value) => MapEntry(key, _decodeFirestoreValue(value)),
  );
}

Object? _decodeFirestoreValue(Object? value) {
  if (value is! Map) return null;
  final Map<Object?, Object?> field = value;
  if (field.containsKey('nullValue')) return null;
  if (field.containsKey('stringValue')) return field['stringValue']?.toString();
  if (field.containsKey('booleanValue')) return field['booleanValue'] == true;
  if (field.containsKey('integerValue')) {
    return int.tryParse(field['integerValue'].toString());
  }
  if (field.containsKey('doubleValue')) {
    return double.tryParse(field['doubleValue'].toString());
  }
  if (field.containsKey('timestampValue')) {
    return field['timestampValue']?.toString();
  }
  return null;
}

String _jwt(String uid) {
  final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final String header = _base64UrlJson(<String, Object?>{
    'alg': 'none',
    'typ': 'JWT',
  });
  final String payload = _base64UrlJson(<String, Object?>{
    'iss': 'https://securetoken.google.com/$_projectId',
    'aud': _projectId,
    'auth_time': now,
    'iat': now,
    'exp': now + 3600,
    'sub': uid,
    'user_id': uid,
    'firebase': <String, Object?>{'sign_in_provider': 'custom'},
  });
  return '$header.$payload.';
}

String _base64UrlJson(Map<String, Object?> value) {
  return base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Failed expectation: $description');
  }
}

class _FakeRecipientLoader implements HierarchicalAlertRecipientLoader {
  _FakeRecipientLoader({
    this.device = const <HierarchicalAlertRecipient>[],
    this.throwOnLoad = false,
  });

  List<HierarchicalAlertRecipient> tenant =
      const <HierarchicalAlertRecipient>[];
  List<HierarchicalAlertRecipient> site = const <HierarchicalAlertRecipient>[];
  List<HierarchicalAlertRecipient> device;
  List<HierarchicalAlertRecipient> room = const <HierarchicalAlertRecipient>[];
  bool throwOnLoad;
  int loadCount = 0;

  @override
  Future<HierarchicalAlertRecipientsSnapshot> load(
    AlertConfigurationTarget target,
  ) async {
    loadCount += 1;
    if (throwOnLoad) {
      throw StateError('firestore unavailable');
    }
    return HierarchicalAlertRecipientsSnapshot(
      tenant: tenant,
      site: site,
      device: target.deviceId == null
          ? const <HierarchicalAlertRecipient>[]
          : device,
      room: target.scope == AlertConfigurationScope.room
          ? room
          : const <HierarchicalAlertRecipient>[],
      readCount: target.scope == AlertConfigurationScope.room ? 4 : 3,
    );
  }
}
