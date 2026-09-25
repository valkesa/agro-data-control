// Etapa B5 — destinatarios jerárquicos de WhatsApp. Replica, sin
// importarlo, `backend/lib/src/hierarchical_alert_recipients.dart` y
// `alert_configuration_contracts.dart` (Etapa B4.5): resolución aditiva
// Room > Device > Site > Tenant > Legacy, deduplicada por teléfono E.164
// normalizado, sin overrides negativos (un recipient deshabilitado en un
// scope no bloquea el mismo teléfono heredado con `enabled=true`).

import 'hierarchical_alert_catalog.dart';

/// Normaliza un teléfono a dígitos + prefijo `+`. Espejo de
/// `normalizeWhatsAppPhone`/`normalizeAlertRecipientPhoneE164` del backend.
String normalizeAlertRecipientPhoneE164(String phone) {
  final String digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  return '+$digits';
}

bool isValidAlertRecipientPhoneE164(String phone) {
  final String trimmed = phone.trim();
  if (!trimmed.startsWith('+')) return false;
  final String digits = trimmed.substring(1);
  return digits.length >= 8 &&
      digits.length <= 15 &&
      RegExp(r'^[0-9]+$').hasMatch(digits);
}

/// El documento crudo `alertRecipients/{recipientId}` en UN scope.
class AlertRecipientOverride {
  const AlertRecipientOverride({
    required this.id,
    required this.displayName,
    required this.phoneE164,
    required this.enabled,
    this.schemaVersion = 1,
    this.createdAt,
    this.createdBy,
    this.updatedAt,
    this.updatedBy,
  });

  final String id;
  final String displayName;
  final String phoneE164;
  final bool enabled;
  final int schemaVersion;
  final DateTime? createdAt;
  final String? createdBy;
  final DateTime? updatedAt;
  final String? updatedBy;

  String get normalizedPhone => normalizeAlertRecipientPhoneE164(phoneE164);

  factory AlertRecipientOverride.fromRaw(String id, Map<String, Object?> raw) {
    return AlertRecipientOverride(
      id: id,
      displayName: raw['displayName']?.toString() ?? '',
      phoneE164: normalizeAlertRecipientPhoneE164(
        raw['phoneE164']?.toString() ?? '',
      ),
      enabled: raw['enabled'] == true,
      schemaVersion: raw['schemaVersion'] is int
          ? raw['schemaVersion'] as int
          : 1,
      createdAt: raw['createdAt'] is DateTime
          ? raw['createdAt'] as DateTime
          : null,
      createdBy: raw['createdBy']?.toString(),
      updatedAt: raw['updatedAt'] is DateTime
          ? raw['updatedAt'] as DateTime
          : null,
      updatedBy: raw['updatedBy']?.toString(),
    );
  }
}

/// Un recipient ya resuelto para un target concreto, con su scope/origen de
/// procedencia — usado tal cual por la UI para decidir si se muestra
/// editable o solo lectura (Etapa B5 §25).
class HierarchicalAlertRecipient {
  const HierarchicalAlertRecipient({
    required this.id,
    required this.displayName,
    required this.phoneE164,
    required this.enabled,
    required this.scope,
    this.isLegacy = false,
  });

  final String id;
  final String displayName;
  final String phoneE164;
  final bool enabled;

  /// Scope donde vive el documento fuente (dónde hay que editarlo/borrarlo).
  final AlertConfigScope scope;
  final bool isLegacy;

  String get normalizedPhone => normalizeAlertRecipientPhoneE164(phoneE164);
}

/// Resuelve la lista efectiva de recipients para un target, dado lo que se
/// leyó en cada nivel disponible (pasar `null` para un nivel no aplicable
/// al scope actual, y `const []` para un nivel aplicable pero vacío).
///
/// Precedencia Room > Device > Site > Tenant > Legacy: ante el mismo
/// teléfono normalizado, el nivel más específico define el `displayName`
/// visible, pero el teléfono sigue apareciendo (herencia aditiva, sin
/// overrides negativos — un `enabled=false` en un nivel no bloquea el mismo
/// teléfono heredado con `enabled=true` en otro).
List<HierarchicalAlertRecipient> resolveHierarchicalAlertRecipients({
  List<AlertRecipientOverride>? tenant,
  List<AlertRecipientOverride>? site,
  List<AlertRecipientOverride>? device,
  List<AlertRecipientOverride>? room,
  List<HierarchicalAlertRecipient> legacy =
      const <HierarchicalAlertRecipient>[],
}) {
  final List<MapEntry<AlertConfigScope, List<AlertRecipientOverride>>> chain =
      <MapEntry<AlertConfigScope, List<AlertRecipientOverride>>>[
        if (room != null) MapEntry(AlertConfigScope.room, room),
        if (device != null) MapEntry(AlertConfigScope.device, device),
        if (site != null) MapEntry(AlertConfigScope.site, site),
        if (tenant != null) MapEntry(AlertConfigScope.tenant, tenant),
      ];

  final Set<String> seenPhones = <String>{};
  final List<HierarchicalAlertRecipient> resolved =
      <HierarchicalAlertRecipient>[];

  for (final MapEntry<AlertConfigScope, List<AlertRecipientOverride>> entry
      in chain) {
    for (final AlertRecipientOverride override in entry.value) {
      if (!override.enabled) continue;
      final String phone = override.normalizedPhone;
      if (phone.isEmpty || !seenPhones.add(phone)) continue;
      resolved.add(
        HierarchicalAlertRecipient(
          id: override.id,
          displayName: override.displayName,
          phoneE164: phone,
          enabled: true,
          scope: entry.key,
        ),
      );
    }
  }

  for (final HierarchicalAlertRecipient legacyRecipient in legacy) {
    final String phone = legacyRecipient.normalizedPhone;
    if (phone.isEmpty || !seenPhones.add(phone)) continue;
    resolved.add(legacyRecipient);
  }

  return List<HierarchicalAlertRecipient>.unmodifiable(resolved);
}

/// Etapa B5 §27: si el usuario intenta agregar en un scope inferior un
/// teléfono que ya se hereda de un scope superior, hay que advertir/bloquear
/// en vez de crear un duplicado. Devuelve el recipient heredado en
/// conflicto, o `null` si no hay conflicto.
HierarchicalAlertRecipient? findInheritedConflict({
  required String phoneE164,
  required AlertConfigScope targetScope,
  required List<HierarchicalAlertRecipient> effectiveRecipients,
}) {
  final String normalized = normalizeAlertRecipientPhoneE164(phoneE164);
  for (final HierarchicalAlertRecipient recipient in effectiveRecipients) {
    if (recipient.normalizedPhone != normalized) continue;
    if (_scopeRank(recipient.scope) < _scopeRank(targetScope) &&
        !recipient.isLegacy) {
      return recipient;
    }
    if (recipient.isLegacy) {
      return recipient;
    }
  }
  return null;
}

int _scopeRank(AlertConfigScope scope) {
  return switch (scope) {
    AlertConfigScope.tenant => 0,
    AlertConfigScope.site => 1,
    AlertConfigScope.device => 2,
    AlertConfigScope.room => 3,
  };
}
