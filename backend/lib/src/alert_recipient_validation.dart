// Etapa B6.3 — soporte de transición (no arquitectura permanente, ver §15
// del prompt) para operar el modo `validate` en producción:
//
//   - [AlertRecipientModeConfig]: lee el modo (legacy|validate|hierarchical)
//     y el tenant permitido desde variables de entorno, con default seguro
//     `legacy` y un guard explícito de scoping (§5/§24).
//   - [classifyRecipientDifferences]: clasifica cada diferencia de
//     `AlertRecipientComparison` como esperada o inesperada (§14), usando
//     la semántica real del recipient legacy (su `scope`) en vez de
//     teléfonos hardcodeados sueltos.
//   - [AlertRecipientValidationTracker]: acumula métricas (§19) y produce
//     el bloque `alertRecipientsValidation` para `/health` (§18).
//
// Nada de esto cambia quién recibe WhatsApp — `validate` siempre envía por
// legacy (ver `HierarchicalAlertRecipientProvider` en alert_notifications.dart).

import 'dart:io';

import 'alert_configuration_contracts.dart'
    show normalizeAlertRecipientPhoneE164;
import 'hierarchical_alert_recipients.dart';
import 'whatsapp_alert_recipients.dart' as legacy_recipients;

/// Modo de resolución de recipients + scoping — Etapa B6.3 §3/§5/§23/§24.
///
/// Deliberadamente expresado como `String` ('legacy'|'validate'|
/// 'hierarchical'), no como `AlertRecipientProviderMode` — ese enum vive en
/// `alert_notifications.dart`, que a su vez necesita usar este archivo para
/// el tracker de métricas; importarlo acá crearía un ciclo. El caller
/// (`plc_snapshot_server.dart`) convierte el `String` resultante al enum
/// real al construir el provider.
///
/// Lee `ALERT_RECIPIENT_MODE` (default: `legacy`, nunca `validate`/
/// `hierarchical` por defecto) y, opcionalmente, `ALERT_RECIPIENT_
/// VALIDATE_TENANT`: si está seteada, el modo pedido solo se activa cuando
/// coincide exactamente con el `tenantId` real de este proceso — cualquier
/// otro tenant (p.ej. La Payana) queda forzado a `legacy` sin importar qué
/// diga la variable de entorno, así un error de configuración no puede
/// activar `validate` fuera de The Gene Pig.
class AlertRecipientModeConfig {
  const AlertRecipientModeConfig({
    required this.requestedMode,
    required this.validateTenantId,
  });

  factory AlertRecipientModeConfig.fromEnvironment({
    Map<String, String>? environment,
  }) {
    final Map<String, String> env = environment ?? Platform.environment;
    final String rawMode = (env['ALERT_RECIPIENT_MODE'] ?? '')
        .trim()
        .toLowerCase();
    final String requestedMode = switch (rawMode) {
      'validate' => 'validate',
      'hierarchical' => 'hierarchical',
      _ => 'legacy',
    };
    final String rawTenant = (env['ALERT_RECIPIENT_VALIDATE_TENANT'] ?? '')
        .trim();
    return AlertRecipientModeConfig(
      requestedMode: requestedMode,
      validateTenantId: rawTenant.isEmpty ? null : rawTenant,
    );
  }

  /// 'legacy' | 'validate' | 'hierarchical'.
  final String requestedMode;
  final String? validateTenantId;

  /// Modo real a usar para un `tenantId` dado — nunca `validate`/
  /// `hierarchical` si `validateTenantId` está seteado y no coincide.
  String effectiveModeFor(String tenantId) {
    if (requestedMode == 'legacy') return 'legacy';
    if (validateTenantId == null) return requestedMode;
    return validateTenantId == tenantId ? requestedMode : 'legacy';
  }
}

/// Etapa B6.3 (transición, no permanente): nombres de contactos legacy con
/// scope `tenantSite` que YA tienen equivalente moderno en un Device más
/// específico dentro del mismo Site (hoy: Enzo/Mauro → Device Laboratorio).
/// Es esperado que aparezcan como `legacyOnly` en cualquier otro Device/Room
/// del mismo Site — eso representa la mejora de scope buscada, no un bug.
/// Se identifica por nombre (no por teléfono) para no duplicar números
/// reales acá; se elimina en B7 cuando legacy deje de tenerlos hardcodeados
/// a nivel Site.
const Set<String> kKnownDeviceScopedTenantSiteContactNames = <String>{
  'Enzo',
  'Mauro',
};

/// Resultado de clasificar una [AlertRecipientComparison] — Etapa B6.3 §14.
class AlertRecipientDifferenceReport {
  const AlertRecipientDifferenceReport({
    required this.comparison,
    required this.expectedLegacyOnly,
    required this.unexpectedLegacyOnly,
    required this.unexpectedModernOnly,
  });

  final AlertRecipientComparison comparison;
  final int expectedLegacyOnly;
  final int unexpectedLegacyOnly;
  final int unexpectedModernOnly;

  bool get isExactMatch =>
      comparison.legacyOnly.isEmpty &&
      comparison.modernOnly.isEmpty &&
      comparison.invalid == 0;

  bool get hasUnexpectedDifferences =>
      unexpectedLegacyOnly > 0 ||
      unexpectedModernOnly > 0 ||
      comparison.invalid > 0;
}

/// Clasifica cada `legacyOnly`/`modernOnly` de [comparison] como esperado o
/// inesperado (§14):
///  - `legacyOnly` con `scope == global` (Gerardo/Demián — contactos
///    técnicos de Valke, sin equivalente en el modelo moderno) → esperado.
///  - `legacyOnly` cuyo `contactName` está en
///    [kKnownDeviceScopedTenantSiteContactNames] (Enzo/Mauro fuera de
///    Laboratorio) → esperado.
///  - cualquier otro `legacyOnly` (p.ej. Nicolás faltando) → inesperado.
///  - cualquier `modernOnly` → siempre inesperado: en esta etapa lo moderno
///    debe ser un subconjunto acotado de legacy, nunca tener a alguien que
///    legacy no tiene.
AlertRecipientDifferenceReport classifyRecipientDifferences({
  required AlertRecipientComparison comparison,
  required List<legacy_recipients.AlertRecipient> legacyRecipients,
}) {
  final Map<String, legacy_recipients.AlertRecipient> legacyByPhone =
      <String, legacy_recipients.AlertRecipient>{
        for (final legacy_recipients.AlertRecipient r in legacyRecipients)
          normalizeAlertRecipientPhoneE164(r.phone): r,
      };

  int expected = 0;
  int unexpected = 0;
  for (final String phone in comparison.legacyOnly) {
    final legacy_recipients.AlertRecipient? original = legacyByPhone[phone];
    final bool isExpected =
        original?.scope == legacy_recipients.AlertRecipientScope.global ||
        (original != null &&
            kKnownDeviceScopedTenantSiteContactNames.contains(
              original.contactName,
            ));
    if (isExpected) {
      expected += 1;
    } else {
      unexpected += 1;
    }
  }

  return AlertRecipientDifferenceReport(
    comparison: comparison,
    expectedLegacyOnly: expected,
    unexpectedLegacyOnly: unexpected,
    unexpectedModernOnly: comparison.modernOnly.length,
  );
}

/// Acumula métricas de validación desde el arranque/restart del proceso
/// (§19) y produce el bloque `alertRecipientsValidation` de `/health`
/// (§18). No usa ninguna infraestructura de métricas externa — todo vive
/// en memoria, a propósito (§19 "si no hay framework de métricas,
/// mantenerlo en memoria/health").
class AlertRecipientValidationTracker {
  int comparisons = 0;
  int exactMatches = 0;
  int expectedDifferences = 0;
  int unexpectedDifferences = 0;
  int invalidRecipients = 0;
  int duplicatesDetected = 0;
  DateTime? lastComparisonAt;
  String? lastError;

  /// Conteo por target (§20) — clave libre provista por el caller (p.ej. el
  /// `muntersId`/deviceId real de la alerta), sin cardinalidad arbitraria:
  /// solo se llenan las claves que realmente generan alertas.
  final Map<String, int> comparisonsByTarget = <String, int>{};
  final Map<String, int> unexpectedDifferencesByTarget = <String, int>{};

  /// Registra una comparación real (§16: solo se llama cuando una alerta es
  /// candidata a WhatsApp, nunca por polling) y logea en formato masked,
  /// sin teléfonos completos (§17).
  void record({
    required String tenantId,
    required String siteId,
    required String targetKey,
    required String alertId,
    required AlertRecipientComparison comparison,
    required List<legacy_recipients.AlertRecipient> legacyRecipients,
  }) {
    final AlertRecipientDifferenceReport report = classifyRecipientDifferences(
      comparison: comparison,
      legacyRecipients: legacyRecipients,
    );
    comparisons += 1;
    comparisonsByTarget[targetKey] = (comparisonsByTarget[targetKey] ?? 0) + 1;
    if (report.isExactMatch) exactMatches += 1;
    expectedDifferences += report.expectedLegacyOnly;
    unexpectedDifferences +=
        report.unexpectedLegacyOnly + report.unexpectedModernOnly;
    if (report.hasUnexpectedDifferences) {
      unexpectedDifferencesByTarget[targetKey] =
          (unexpectedDifferencesByTarget[targetKey] ?? 0) + 1;
    }
    invalidRecipients += comparison.invalid;
    duplicatesDetected += comparison.duplicates;
    lastComparisonAt = DateTime.now().toUtc();
    lastError = null;

    _log(
      'event=ALERT_RECIPIENT_VALIDATE tenant=$tenantId site=$siteId '
      'target=$targetKey alert=$alertId legacyCount=${legacyRecipients.length} '
      'modernCount=${comparison.both.length + comparison.modernOnly.length} '
      'both=${comparison.both.length} legacyOnly=${comparison.legacyOnly.length} '
      'modernOnly=${comparison.modernOnly.length} '
      'expectedDiff=${report.expectedLegacyOnly > 0} '
      'unexpectedDiff=${report.hasUnexpectedDifferences}',
    );
  }

  void recordError(Object error) {
    lastError = error.toString();
    _log('event=ALERT_RECIPIENT_VALIDATE_ERROR errorType=${error.runtimeType}');
  }

  Map<String, Object?> healthJson({
    required String mode,
    required String tenantId,
  }) {
    return <String, Object?>{
      'mode': mode,
      'tenantId': tenantId,
      'comparisons': comparisons,
      'exactMatches': exactMatches,
      'expectedDifferences': expectedDifferences,
      'unexpectedDifferences': unexpectedDifferences,
      'invalidRecipients': invalidRecipients,
      'duplicatesDetected': duplicatesDetected,
      'lastComparisonAt': lastComparisonAt?.toIso8601String(),
      'lastError': lastError,
      'byTarget': <String, Object?>{
        for (final String key in comparisonsByTarget.keys)
          key: <String, Object?>{
            'comparisons': comparisonsByTarget[key],
            'unexpectedDifferences': unexpectedDifferencesByTarget[key] ?? 0,
          },
      },
    };
  }

  void _log(String message) {
    // ignore: avoid_print
    print('[alert-recipient-validation] $message');
  }
}
