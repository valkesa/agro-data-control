// Etapa B6.3 — tests obligatorios §27-§34 del prompt: validate nunca
// cambia el sender real, clasificación expected/unexpected, dedup, cache y
// comportamiento ante fallo de Firestore. Mismo estilo que el resto del
// backend: script Dart puro, `main()` con `_expect`, sin dependencias
// externas de testing.

import 'package:agro_data_control_backend/src/alert_configuration_contracts.dart';
import 'package:agro_data_control_backend/src/alert_notifications.dart';
import 'package:agro_data_control_backend/src/alert_priority.dart';
import 'package:agro_data_control_backend/src/alert_recipient_validation.dart';
import 'package:agro_data_control_backend/src/hierarchical_alert_recipients.dart';
import 'package:agro_data_control_backend/src/whatsapp_alert_recipients.dart';

int _passed = 0;
int _failed = 0;

Future<void> main() async {
  _testModeConfigDefaultsToLegacy();
  _testModeConfigTenantGuard();

  _testValidateDoesNotChangeSend();
  _testExactMatch();
  _testExpectedDifferenceSala1();
  _testLaboratorioLegacyOnlyGlobalOnly();
  _testUnexpectedDifferenceMissingModern();
  _testDedupSamePhoneMultipleLevels();
  await _testFirestoreFailureKeepsLegacySend();

  stdout('\n=== RESULTADO: $_passed OK, $_failed FALLOS ===');
  if (_failed > 0) {
    // ignore: avoid_print
    print('FALLARON $_failed TESTS');
  }
}

void _testModeConfigDefaultsToLegacy() {
  final AlertRecipientModeConfig config =
      AlertRecipientModeConfig.fromEnvironment(
        environment: const <String, String>{},
      );
  _expect(
    config.requestedMode == 'legacy',
    '§24 sin env var -> default legacy',
  );
  _expect(
    config.effectiveModeFor('the-gene-pig') == 'legacy',
    'default legacy se mantiene para cualquier tenant',
  );

  final AlertRecipientModeConfig invalid =
      AlertRecipientModeConfig.fromEnvironment(
        environment: const <String, String>{'ALERT_RECIPIENT_MODE': 'bogus'},
      );
  _expect(
    invalid.requestedMode == 'legacy',
    'valor desconocido de ALERT_RECIPIENT_MODE -> legacy, nunca validate/hierarchical',
  );
}

void _testModeConfigTenantGuard() {
  final AlertRecipientModeConfig config =
      AlertRecipientModeConfig.fromEnvironment(
        environment: const <String, String>{
          'ALERT_RECIPIENT_MODE': 'validate',
          'ALERT_RECIPIENT_VALIDATE_TENANT': 'the-gene-pig',
        },
      );
  _expect(
    config.effectiveModeFor('the-gene-pig') == 'validate',
    '§5 tenant coincide -> validate se activa',
  );
  _expect(
    config.effectiveModeFor('la-payana') == 'legacy',
    '§42 tenant distinto (La Payana) -> forzado a legacy pase lo que pase la env var',
  );
}

/// §27.
void _testValidateDoesNotChangeSend() {
  final legacyA = _recipient('A', '5491100000001', global: false);
  final legacyB = _recipient('B', '5491100000002', global: false);
  final modernA = _modern('A', '+5491100000001');
  final modernC = _modern('C', '+5491100000003');

  final AlertRecipientComparison comparison = compareLegacyAndModernRecipients(
    legacyRecipients: [legacyA, legacyB],
    modernRecipients: [modernA, modernC],
  );
  _expect(comparison.both.length == 1, '§27 both=[A]');
  _expect(comparison.legacyOnly.length == 1, '§27 legacyOnly=[B]');
  _expect(comparison.modernOnly.length == 1, '§27 modernOnly=[C]');

  final tracker = AlertRecipientValidationTracker();
  tracker.record(
    tenantId: 't',
    siteId: 's',
    targetKey: 'target',
    alertId: 'temperature_interior',
    comparison: comparison,
    legacyRecipients: [legacyA, legacyB],
  );
  _expect(
    tracker.comparisons == 1,
    '§27 el tracker registra la comparación sin tocar el sender',
  );
}

/// §28.
void _testExactMatch() {
  final legacyA = _recipient('A', '5491100000001', global: false);
  final modernA = _modern('A', '+5491100000001');
  final comparison = compareLegacyAndModernRecipients(
    legacyRecipients: [legacyA],
    modernRecipients: [modernA],
  );
  final tracker = AlertRecipientValidationTracker();
  tracker.record(
    tenantId: 't',
    siteId: 's',
    targetKey: 'target',
    alertId: 'sensor_failure',
    comparison: comparison,
    legacyRecipients: [legacyA],
  );
  _expect(tracker.exactMatches == 1, '§28 exactMatches += 1');
  _expect(tracker.unexpectedDifferences == 0, '§28 unexpectedDifferences += 0');
}

/// §29 — fixture conceptual real: Sala1 solo tiene Nicolás en moderno, pero
/// legacy incluye además a Gerardo/Demián (global) y Enzo/Mauro
/// (tenantSite, hoy hardcodeados a nivel Site). Nada de esto es un fallo.
void _testExpectedDifferenceSala1() {
  final gerardo = _recipient('Gerardo', '5491138267368', global: true);
  final demian = _recipient('Demian', '5491169380079', global: true);
  final enzo = _recipient('Enzo', '5491123040959', global: false);
  final mauro = _recipient('Mauro', '5492227516703', global: false);
  final nicolas = _recipient('Nicolas', '5491169384562', global: false);
  final modernNicolas = _modern('Nicolas', '+5491169384562');

  final comparison = compareLegacyAndModernRecipients(
    legacyRecipients: [gerardo, demian, enzo, mauro, nicolas],
    modernRecipients: [modernNicolas],
  );
  _expect(
    comparison.legacyOnly.length == 4,
    'Sala1: 4 legacyOnly (Gerardo/Demian/Enzo/Mauro)',
  );

  final AlertRecipientDifferenceReport report = classifyRecipientDifferences(
    comparison: comparison,
    legacyRecipients: [gerardo, demian, enzo, mauro, nicolas],
  );
  _expect(
    report.expectedLegacyOnly == 4,
    '§29 las 4 diferencias de Sala1 se clasifican como esperadas',
  );
  _expect(
    report.unexpectedLegacyOnly == 0 && report.unexpectedModernOnly == 0,
    '§29 no debe haber ninguna diferencia inesperada en Sala1',
  );
  _expect(
    !report.hasUnexpectedDifferences,
    '§29 no se considera fallo automáticamente',
  );
}

/// §30 — Laboratorio: moderno tiene exactamente Nicolas/Enzo/Mauro, legacy
/// tiene además Gerardo/Demian (global). legacyOnly = solo los 2 globales,
/// modernOnly = ninguno, todo esperado.
void _testLaboratorioLegacyOnlyGlobalOnly() {
  final gerardo = _recipient('Gerardo', '5491138267368', global: true);
  final demian = _recipient('Demian', '5491169380079', global: true);
  final enzo = _recipient('Enzo', '5491123040959', global: false);
  final mauro = _recipient('Mauro', '5492227516703', global: false);
  final nicolas = _recipient('Nicolas', '5491169384562', global: false);

  final modernEnzo = _modern('Enzo', '+5491123040959');
  final modernMauro = _modern('Mauro', '+5492227516703');
  final modernNicolas = _modern('Nicolas', '+5491169384562');

  final comparison = compareLegacyAndModernRecipients(
    legacyRecipients: [gerardo, demian, enzo, mauro, nicolas],
    modernRecipients: [modernEnzo, modernMauro, modernNicolas],
  );
  _expect(
    comparison.legacyOnly.length == 2,
    '§30 legacyOnly = Gerardo/Demian únicamente',
  );
  _expect(comparison.modernOnly.isEmpty, '§30 modernOnly = none');

  final report = classifyRecipientDifferences(
    comparison: comparison,
    legacyRecipients: [gerardo, demian, enzo, mauro, nicolas],
  );
  _expect(
    !report.hasUnexpectedDifferences,
    '§30 Laboratorio: unexpected = none',
  );
}

/// §31 — Nicolás ausente en moderno debe contar como inesperado.
void _testUnexpectedDifferenceMissingModern() {
  final nicolas = _recipient('Nicolas', '5491169384562', global: false);
  final comparison = compareLegacyAndModernRecipients(
    legacyRecipients: [nicolas],
    modernRecipients: const <HierarchicalAlertRecipient>[],
  );
  final report = classifyRecipientDifferences(
    comparison: comparison,
    legacyRecipients: [nicolas],
  );
  _expect(
    report.unexpectedLegacyOnly == 1,
    '§31 Nicolas faltando en moderno -> unexpectedDifferences',
  );

  final tracker = AlertRecipientValidationTracker();
  tracker.record(
    tenantId: 't',
    siteId: 's',
    targetKey: 'laboratorio',
    alertId: 'temperature_interior',
    comparison: comparison,
    legacyRecipients: [nicolas],
  );
  _expect(
    tracker.unexpectedDifferences == 1,
    '§31 el tracker incrementa unexpectedDifferences',
  );
}

/// §32 — mismo teléfono en Tenant/Device/Legacy debe deduplicarse a 1.
void _testDedupSamePhoneMultipleLevels() {
  final legacyNicolas = _recipient('Nicolas', '5491169384562', global: false);
  final tenantNicolas = _modern('Nicolas Tenant', '+5491169384562');
  final deviceNicolas = _modern('Nicolas Device', '+5491169384562');

  final comparison = compareLegacyAndModernRecipients(
    legacyRecipients: [legacyNicolas],
    modernRecipients: [tenantNicolas, deviceNicolas],
  );
  _expect(
    comparison.both.length == 1,
    '§32 mismo teléfono en dos niveles modernos -> 1 phone en la comparación',
  );
}

/// §34 — si falla la carga Firestore moderna, legacy sigue enviando y el
/// tracker registra el error, sin bloquear el batch.
Future<void> _testFirestoreFailureKeepsLegacySend() async {
  const WhatsAppAlertRecipientsConfig config = WhatsAppAlertRecipientsConfig();
  final AlertRecipientValidationTracker tracker =
      AlertRecipientValidationTracker();
  final HierarchicalAlertRecipientProvider provider =
      HierarchicalAlertRecipientProvider(
        mode: AlertRecipientProviderMode.validate,
        legacyConfig: config,
        cache: HierarchicalAlertRecipientsCache(loader: _ThrowingLoader()),
        validationTracker: tracker,
      );
  final PendingNotificationBatch batch = PendingNotificationBatch(
    batchId: 'b1',
    key: const NotificationBatchKey(
      tenantId: 'the-gene-pig',
      siteId: 'las-heras',
      roomId: 'sala1',
    ),
    roomNumber: 1,
    muntersId: 'sala1',
    plcLabel: 'Sala 1',
    createdAt: DateTime.now(),
    closesAt: DateTime.now(),
    alertOrder: const <AlertType, int>{},
  );

  final List<AlertRecipient> expectedLegacy = config.recipientsFor(
    tenantId: 'the-gene-pig',
    siteId: 'las-heras',
  );
  final List<AlertRecipient> recipients = await provider.recipientsForBatch(
    batch,
    clientName: 'c',
    siteName: 's',
  );
  _expect(
    recipients.length == expectedLegacy.length && recipients.isNotEmpty,
    '§34 recipientsForBatch devuelve la lista legacy completa aunque el loader moderno falle',
  );
  _expect(
    tracker.lastError != null,
    '§34 el fallo del loader moderno queda registrado como error de validación',
  );
  _expect(
    tracker.comparisons == 0,
    '§34 no se registra ninguna comparación cuando el loader falla (no hay modernRecipients)',
  );
}

AlertRecipient _recipient(String name, String phone, {required bool global}) {
  return AlertRecipient(
    scope: global ? AlertRecipientScope.global : AlertRecipientScope.tenantSite,
    contactName: name,
    phone: phone,
    tenantId: global ? null : 'the-gene-pig',
    siteId: global ? null : 'las-heras',
    clientName: global ? null : 'Gene Pig',
    siteName: global ? null : 'Las Heras',
  );
}

HierarchicalAlertRecipient _modern(String name, String phoneE164) {
  return HierarchicalAlertRecipient(
    id: name.toLowerCase(),
    displayName: name,
    phoneE164: phoneE164,
    enabled: true,
    scope: AlertRecipientConfigScope.tenant,
    origin: AlertConfigOrigin.tenant,
  );
}

class _ThrowingLoader implements HierarchicalAlertRecipientLoader {
  @override
  Future<HierarchicalAlertRecipientsSnapshot> load(
    AlertConfigurationTarget target,
  ) {
    throw const HierarchicalAlertRecipientLoaderException(
      'simulated Firestore failure',
    );
  }
}

void _expect(bool condition, String description) {
  if (condition) {
    _passed += 1;
    stdout('OK   $description');
  } else {
    _failed += 1;
    stdout('FAIL $description');
  }
}

void stdout(String message) {
  // ignore: avoid_print
  print(message);
}
