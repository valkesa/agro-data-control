// Etapa B6.3 §38/§39 — simulación read-only de resolución de recipients
// (legacy vs moderno) para un target real, SIN enviar ningún WhatsApp.
// Usa exactamente la misma lógica que corre en producción
// (`HierarchicalAlertRecipientsCache`, `compareLegacyAndModernRecipients`,
// `classifyRecipientDifferences`), contra Firestore real, para poder
// validar scopes sin esperar una alarma real. Restringido a uso local
// (no es un endpoint HTTP) — pensado para correr manualmente por un
// owner/admin.
//
// Uso (desde la raíz del repo, mismo criterio que backend/tool/sync_all_user_claims.dart):
//   dart run backend/tool/simulate_b6_3_recipient_resolution.dart --label laboratorio --device plc-genetica-laboratorio
//   dart run backend/tool/simulate_b6_3_recipient_resolution.dart --label sala1 --device plc-genetica-sala1
//   dart run backend/tool/simulate_b6_3_recipient_resolution.dart --label sala2 --device plc-genetica-sala2

import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control_backend/src/alert_configuration_contracts.dart';
import 'package:agro_data_control_backend/src/alert_recipient_validation.dart';
import 'package:agro_data_control_backend/src/hierarchical_alert_recipients.dart';
import 'package:agro_data_control_backend/src/whatsapp_alert_recipients.dart';

const String _tenantId = 'the-gene-pig';
const String _siteId = 'las-heras';
const String _defaultServiceAccountPath = 'backend/config/service-account.json';

Future<void> main(List<String> args) async {
  String? deviceId;
  String label = 'site';
  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--device') {
      i += 1;
      deviceId = i < args.length ? args[i] : null;
    } else if (args[i] == '--label') {
      i += 1;
      label = i < args.length ? args[i] : label;
    }
  }

  final FirestoreHierarchicalAlertRecipientLoader loader =
      FirestoreHierarchicalAlertRecipientLoader(
        projectId: await _projectIdFromServiceAccount(),
        databaseId: '(default)',
        serviceAccountJsonPath: _defaultServiceAccountPath,
      );
  final HierarchicalAlertRecipientsCache cache =
      HierarchicalAlertRecipientsCache(loader: loader);

  const WhatsAppAlertRecipientsConfig legacyConfig =
      WhatsAppAlertRecipientsConfig();
  final List<AlertRecipient> legacyRecipients = legacyConfig.recipientsFor(
    tenantId: _tenantId,
    siteId: _siteId,
  );

  // Mismo mapeo que `HierarchicalAlertRecipientProvider._targetForBatch`
  // en produccion — con Device presente, scope=room (asi resuelve
  // exactamente lo mismo que resolveria un batch real de esa alerta).
  final AlertConfigurationTarget target = AlertConfigurationTarget(
    tenantId: _tenantId,
    siteId: _siteId,
    scope: deviceId == null
        ? AlertConfigurationScope.site
        : AlertConfigurationScope.room,
    deviceId: deviceId,
    snapshotUnitKey: deviceId,
    muntersId: deviceId,
  );
  // Sin legacy como fallback a propósito (mismo criterio que
  // `HierarchicalAlertRecipientProvider` en modo `validate`, Etapa B6.3):
  // si se pasara legacy acá, el resolver lo incorporaría al resultado
  // "moderno" y la comparación de abajo daría siempre un match trivial,
  // sin poder detectar un gap real.
  final List<HierarchicalAlertRecipient> modernRecipients = await cache
      .getOrLoad(target: target);

  final AlertRecipientComparison comparison = compareLegacyAndModernRecipients(
    legacyRecipients: legacyRecipients,
    modernRecipients: modernRecipients,
  );
  final AlertRecipientDifferenceReport report = classifyRecipientDifferences(
    comparison: comparison,
    legacyRecipients: legacyRecipients,
  );

  stdout.writeln(
    '=== SIMULACION B6.3: label=$label device=${deviceId ?? '(site)'} ===',
  );
  stdout.writeln(
    'LEGACY (${legacyRecipients.length}): '
    '${legacyRecipients.map((AlertRecipient r) => '${r.contactName} ${maskWhatsAppPhone(r.phone)}').join(', ')}',
  );
  stdout.writeln(
    'MODERN (${modernRecipients.length}): '
    '${modernRecipients.map((HierarchicalAlertRecipient r) => '${r.displayName} ${maskWhatsAppPhone(r.phoneE164)}').join(', ')}',
  );
  stdout.writeln(
    'COMPARISON both=${comparison.both.length} legacyOnly=${comparison.legacyOnly.length} '
    'modernOnly=${comparison.modernOnly.length} duplicates=${comparison.duplicates} invalid=${comparison.invalid}',
  );
  stdout.writeln(
    'CLASSIFICATION expected=${report.expectedLegacyOnly} '
    'unexpectedLegacyOnly=${report.unexpectedLegacyOnly} '
    'unexpectedModernOnly=${report.unexpectedModernOnly} '
    'hasUnexpectedDifferences=${report.hasUnexpectedDifferences}',
  );
  stdout.writeln('reads=${cache.lastReadCount}');
}

Future<String> _projectIdFromServiceAccount() async {
  final String raw = await File(_defaultServiceAccountPath).readAsString();
  final Map<String, dynamic> serviceAccount =
      jsonDecode(raw) as Map<String, dynamic>;
  return serviceAccount['project_id'] as String;
}
