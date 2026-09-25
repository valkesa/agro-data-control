// Etapa B5 — configuración jerárquica de alertas: documento crudo por
// scope (`AlertConfigOverride`), valor resuelto por alerta
// (`EffectiveAlertConfig`) y el resolver de herencia. Replica, sin
// importarlo, el algoritmo de `backend/lib/src/hierarchical_alert_settings.dart`
// (Etapa B3): Room > Device > Site > Tenant > catálogo/legacy, con merge
// campo-a-campo para thresholds y `fieldOrigins` por campo.

import 'hierarchical_alert_catalog.dart';

/// Umbrales de una alerta. Cualquier campo ausente (`null`) significa "sin
/// valor en este nivel", no "cero" — importante para la herencia.
class AlertThresholds {
  const AlertThresholds({
    this.min,
    this.max,
    this.margin,
    this.sensorFailureMin,
  });

  final double? min;
  final double? max;
  final double? margin;
  final double? sensorFailureMin;

  static const AlertThresholds empty = AlertThresholds();

  bool get isEmpty =>
      min == null && max == null && margin == null && sensorFailureMin == null;

  factory AlertThresholds.fromRaw(Map<String, Object?>? raw) {
    if (raw == null) return AlertThresholds.empty;
    return AlertThresholds(
      min: _readDouble(raw['min']),
      max: _readDouble(raw['max']),
      margin: _readDouble(raw['margin']),
      sensorFailureMin: _readDouble(raw['sensorFailureMin']),
    );
  }

  /// Solo incluye las claves con valor — el mapa resultante nunca contiene
  /// `null` porque Rules (`isValidAlertConfigThresholds`) exige que cada
  /// clave presente tenga el tipo correcto, no que sea nullable.
  Map<String, Object?> toFirestoreMap() {
    return <String, Object?>{
      if (min != null) 'min': min,
      if (max != null) 'max': max,
      if (margin != null) 'margin': margin,
      if (sensorFailureMin != null) 'sensorFailureMin': sensorFailureMin,
    };
  }

  /// Merge campo-a-campo: cada campo de umbral hereda independientemente
  /// del nivel más específico que lo define — igual que
  /// `_mergeThresholds` en el backend (Etapa B3).
  static AlertThresholds merge(AlertThresholds child, AlertThresholds parent) {
    return AlertThresholds(
      min: child.min ?? parent.min,
      max: child.max ?? parent.max,
      margin: child.margin ?? parent.margin,
      sensorFailureMin: child.sensorFailureMin ?? parent.sensorFailureMin,
    );
  }

  static Map<String, AlertConfigOrigin> mergeOrigins({
    required AlertThresholds child,
    required Map<String, AlertConfigOrigin> childOrigins,
    required AlertThresholds parent,
    required Map<String, AlertConfigOrigin> parentOrigins,
  }) {
    Map<String, AlertConfigOrigin> pick(String field, double? childValue) {
      return <String, AlertConfigOrigin>{
        field: childValue != null
            ? childOrigins[field]!
            : parentOrigins[field]!,
      };
    }

    return <String, AlertConfigOrigin>{
      ...pick('thresholds.min', child.min),
      ...pick('thresholds.max', child.max),
      ...pick('thresholds.margin', child.margin),
      ...pick('thresholds.sensorFailureMin', child.sensorFailureMin),
    };
  }
}

double? _readDouble(Object? value) {
  if (value is num) return value.toDouble();
  return null;
}

/// El documento crudo `alertConfig/{alertId}` en UN scope — nunca resuelto,
/// nunca mezclado con otros niveles. Cualquier campo funcional ausente
/// significa "hereda de un nivel superior", nunca "false"/"0" implícito.
class AlertConfigOverride {
  const AlertConfigOverride({
    this.enabled,
    this.visualEnabled,
    this.whatsappEnabled,
    this.whatsappDelayMinutes,
    this.thresholds = AlertThresholds.empty,
    this.cooldownMinutes,
    this.order,
    this.schemaVersion = 1,
    this.createdAt,
    this.createdBy,
    this.updatedAt,
    this.updatedBy,
  });

  static const AlertConfigOverride empty = AlertConfigOverride();

  final bool? enabled;
  final bool? visualEnabled;
  final bool? whatsappEnabled;
  final int? whatsappDelayMinutes;
  final AlertThresholds thresholds;
  final int? cooldownMinutes;
  final int? order;
  final int schemaVersion;
  final DateTime? createdAt;
  final String? createdBy;
  final DateTime? updatedAt;
  final String? updatedBy;

  /// Espejo de `hasFunctionalAlertConfigOverride()` en `firestore.rules`
  /// (Etapa B4/B4.1): un documento sin NINGÚN campo funcional se considera
  /// vacío y debe borrarse en vez de persistirse (Etapa B5 §22) — de lo
  /// contrario desplazaría el fallback legacy sin aportar nada.
  bool get hasFunctionalOverride {
    return enabled != null ||
        visualEnabled != null ||
        whatsappEnabled != null ||
        whatsappDelayMinutes != null ||
        !thresholds.isEmpty ||
        cooldownMinutes != null ||
        order != null;
  }

  factory AlertConfigOverride.fromRaw(Map<String, Object?>? raw) {
    if (raw == null) return AlertConfigOverride.empty;
    return AlertConfigOverride(
      enabled: raw['enabled'] is bool ? raw['enabled'] as bool : null,
      visualEnabled: raw['visualEnabled'] is bool
          ? raw['visualEnabled'] as bool
          : null,
      whatsappEnabled: raw['whatsappEnabled'] is bool
          ? raw['whatsappEnabled'] as bool
          : null,
      whatsappDelayMinutes: _readInt(raw['whatsappDelayMinutes']),
      thresholds: AlertThresholds.fromRaw(
        raw['thresholds'] is Map
            ? Map<String, Object?>.from(raw['thresholds'] as Map)
            : null,
      ),
      cooldownMinutes: _readInt(raw['cooldownMinutes']),
      order: _readInt(raw['order']),
      schemaVersion: _readInt(raw['schemaVersion']) ?? 1,
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

  AlertConfigOverride copyWith({
    Object? enabled = _unset,
    Object? visualEnabled = _unset,
    Object? whatsappEnabled = _unset,
    Object? whatsappDelayMinutes = _unset,
    AlertThresholds? thresholds,
    Object? cooldownMinutes = _unset,
    Object? order = _unset,
  }) {
    return AlertConfigOverride(
      enabled: identical(enabled, _unset) ? this.enabled : enabled as bool?,
      visualEnabled: identical(visualEnabled, _unset)
          ? this.visualEnabled
          : visualEnabled as bool?,
      whatsappEnabled: identical(whatsappEnabled, _unset)
          ? this.whatsappEnabled
          : whatsappEnabled as bool?,
      whatsappDelayMinutes: identical(whatsappDelayMinutes, _unset)
          ? this.whatsappDelayMinutes
          : whatsappDelayMinutes as int?,
      thresholds: thresholds ?? this.thresholds,
      cooldownMinutes: identical(cooldownMinutes, _unset)
          ? this.cooldownMinutes
          : cooldownMinutes as int?,
      order: identical(order, _unset) ? this.order : order as int?,
      schemaVersion: schemaVersion,
      createdAt: createdAt,
      createdBy: createdBy,
      updatedAt: updatedAt,
      updatedBy: updatedBy,
    );
  }
}

/// Compara dos overrides campo a campo — usada para decidir si un draft de
/// edición realmente difiere del último valor guardado (y por lo tanto
/// vale la pena habilitar "Guardar"), tanto en la vista de tabla como en
/// cualquier otra UI de edición.
bool alertConfigOverridesEqual(AlertConfigOverride a, AlertConfigOverride b) {
  return a.enabled == b.enabled &&
      a.visualEnabled == b.visualEnabled &&
      a.whatsappEnabled == b.whatsappEnabled &&
      a.whatsappDelayMinutes == b.whatsappDelayMinutes &&
      a.cooldownMinutes == b.cooldownMinutes &&
      a.order == b.order &&
      a.thresholds.min == b.thresholds.min &&
      a.thresholds.max == b.thresholds.max &&
      a.thresholds.margin == b.thresholds.margin &&
      a.thresholds.sensorFailureMin == b.thresholds.sensorFailureMin;
}

const Object _unset = Object();

int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

/// Valor resuelto de una alerta para un target concreto, con el origen de
/// CADA campo (Etapa B5 §19 — nunca usar solo un `origin` global para
/// explicar procedencia).
class EffectiveAlertConfig {
  const EffectiveAlertConfig({
    required this.alertId,
    required this.enabled,
    required this.visualEnabled,
    required this.whatsappEnabled,
    required this.whatsappDelayMinutes,
    required this.thresholds,
    required this.cooldownMinutes,
    required this.order,
    required this.fieldOrigins,
  });

  final String alertId;
  final bool enabled;
  final bool visualEnabled;
  final bool whatsappEnabled;
  final int whatsappDelayMinutes;
  final AlertThresholds thresholds;
  final int cooldownMinutes;
  final int order;

  /// Claves: `enabled`, `visualEnabled`, `whatsappEnabled`,
  /// `whatsappDelayMinutes`, `cooldownMinutes`, `order`,
  /// `thresholds.min`, `thresholds.max`, `thresholds.margin`,
  /// `thresholds.sensorFailureMin`.
  final Map<String, AlertConfigOrigin> fieldOrigins;
}

/// Valores por defecto del catálogo cuando ningún nivel (ni legacy) define
/// un campo todavía — evita alertas "sin configurar" que no muestren nada.
class AlertCatalogDefaults {
  const AlertCatalogDefaults._();

  static const bool enabled = true;
  static const bool visualEnabled = true;
  static const bool whatsappEnabled = false;
  static const int whatsappDelayMinutes = 0;
  static const int cooldownMinutes = 15;
}

/// Resuelve la config efectiva de UNA alerta combinando catálogo, legacy (si
/// corresponde) y los overrides tenant/site/device/room disponibles para el
/// scope actual. Cada override ausente (`null`) para un nivel que no aplica
/// al scope seleccionado (p. ej. `device`/`room` cuando solo hay Tenant
/// seleccionado) debe pasarse como `null`, no como `AlertConfigOverride.empty`,
/// para que quede claro que ese nivel no fue leído.
EffectiveAlertConfig resolveEffectiveAlertConfig({
  required String alertId,
  required int catalogOrder,
  AlertConfigOverride? legacy,
  AlertConfigOverride? tenant,
  AlertConfigOverride? site,
  AlertConfigOverride? device,
  AlertConfigOverride? room,
}) {
  // Room > Device > Site > Tenant > legacy > catálogo — misma precedencia
  // que HierarchicalAlertConfigResolver en el backend (Etapa B3).
  final List<MapEntry<AlertConfigOrigin, AlertConfigOverride>> chain =
      <MapEntry<AlertConfigOrigin, AlertConfigOverride>>[
        if (room != null) MapEntry(AlertConfigOrigin.room, room),
        if (device != null) MapEntry(AlertConfigOrigin.device, device),
        if (site != null) MapEntry(AlertConfigOrigin.site, site),
        if (tenant != null) MapEntry(AlertConfigOrigin.tenant, tenant),
        if (legacy != null) MapEntry(AlertConfigOrigin.legacy, legacy),
      ];

  bool? enabled;
  AlertConfigOrigin? enabledOrigin;
  bool? visualEnabled;
  AlertConfigOrigin? visualEnabledOrigin;
  bool? whatsappEnabled;
  AlertConfigOrigin? whatsappEnabledOrigin;
  int? whatsappDelayMinutes;
  AlertConfigOrigin? whatsappDelayOrigin;
  int? cooldownMinutes;
  AlertConfigOrigin? cooldownOrigin;
  int? order;
  AlertConfigOrigin? orderOrigin;
  AlertThresholds thresholds = AlertThresholds.empty;
  Map<String, AlertConfigOrigin> thresholdOrigins =
      <String, AlertConfigOrigin>{};

  // Se recorre de más a menos específico UNA sola vez; el primer nivel que
  // define un campo gana ese campo (aditivo por campo, nunca por documento
  // completo) — igual semántica que el backend.
  for (final MapEntry<AlertConfigOrigin, AlertConfigOverride> entry in chain) {
    final AlertConfigOrigin origin = entry.key;
    final AlertConfigOverride override = entry.value;
    enabled ??= override.enabled;
    if (enabled == override.enabled && override.enabled != null) {
      enabledOrigin ??= origin;
    }
    visualEnabled ??= override.visualEnabled;
    if (visualEnabled == override.visualEnabled &&
        override.visualEnabled != null) {
      visualEnabledOrigin ??= origin;
    }
    whatsappEnabled ??= override.whatsappEnabled;
    if (whatsappEnabled == override.whatsappEnabled &&
        override.whatsappEnabled != null) {
      whatsappEnabledOrigin ??= origin;
    }
    whatsappDelayMinutes ??= override.whatsappDelayMinutes;
    if (whatsappDelayMinutes == override.whatsappDelayMinutes &&
        override.whatsappDelayMinutes != null) {
      whatsappDelayOrigin ??= origin;
    }
    cooldownMinutes ??= override.cooldownMinutes;
    if (cooldownMinutes == override.cooldownMinutes &&
        override.cooldownMinutes != null) {
      cooldownOrigin ??= origin;
    }
    order ??= override.order;
    if (order == override.order && override.order != null) {
      orderOrigin ??= origin;
    }

    final AlertThresholds beforeMerge = thresholds;
    thresholds = AlertThresholds.merge(thresholds, override.thresholds);
    for (final String field in <String>[
      'min',
      'max',
      'margin',
      'sensorFailureMin',
    ]) {
      final String key = 'thresholds.$field';
      if (thresholdOrigins.containsKey(key)) continue;
      final double? beforeValue = switch (field) {
        'min' => beforeMerge.min,
        'max' => beforeMerge.max,
        'margin' => beforeMerge.margin,
        _ => beforeMerge.sensorFailureMin,
      };
      final double? overrideValue = switch (field) {
        'min' => override.thresholds.min,
        'max' => override.thresholds.max,
        'margin' => override.thresholds.margin,
        _ => override.thresholds.sensorFailureMin,
      };
      if (beforeValue == null && overrideValue != null) {
        thresholdOrigins[key] = origin;
      }
    }
  }

  for (final String field in <String>[
    'min',
    'max',
    'margin',
    'sensorFailureMin',
  ]) {
    thresholdOrigins.putIfAbsent(
      'thresholds.$field',
      () => AlertConfigOrigin.catalogDefault,
    );
  }

  return EffectiveAlertConfig(
    alertId: alertId,
    enabled: enabled ?? AlertCatalogDefaults.enabled,
    visualEnabled: visualEnabled ?? AlertCatalogDefaults.visualEnabled,
    whatsappEnabled: whatsappEnabled ?? AlertCatalogDefaults.whatsappEnabled,
    whatsappDelayMinutes:
        whatsappDelayMinutes ?? AlertCatalogDefaults.whatsappDelayMinutes,
    thresholds: thresholds,
    cooldownMinutes: cooldownMinutes ?? AlertCatalogDefaults.cooldownMinutes,
    order: order ?? catalogOrder,
    fieldOrigins: <String, AlertConfigOrigin>{
      'enabled': enabledOrigin ?? AlertConfigOrigin.catalogDefault,
      'visualEnabled': visualEnabledOrigin ?? AlertConfigOrigin.catalogDefault,
      'whatsappEnabled':
          whatsappEnabledOrigin ?? AlertConfigOrigin.catalogDefault,
      'whatsappDelayMinutes':
          whatsappDelayOrigin ?? AlertConfigOrigin.catalogDefault,
      'cooldownMinutes': cooldownOrigin ?? AlertConfigOrigin.catalogDefault,
      'order': orderOrigin ?? AlertConfigOrigin.catalogDefault,
      ...thresholdOrigins,
    },
  );
}
