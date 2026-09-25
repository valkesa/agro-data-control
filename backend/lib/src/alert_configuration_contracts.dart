import 'alert_priority.dart';
import 'alert_runtime_config.dart';
import 'alert_settings_cache.dart';
import 'whatsapp_alert_recipients.dart' as legacy_recipients;

enum AlertConfigurationScope { tenant, site, device, room }

enum AlertScopeCapability { device, room, deviceOrRoom }

enum AlertConfigOrigin { catalogDefault, tenant, site, device, room, legacy }

enum AlertParameterKind { none, minimum, maximum, range, minimumMargin }

class AlertMetricBinding {
  const AlertMetricBinding({required this.role, required this.metricKey});

  final String role;
  final String metricKey;
}

class AlertParameterSchema {
  const AlertParameterSchema({
    required this.kind,
    this.supportsSensorFailureMinimum = false,
  });

  final AlertParameterKind kind;
  final bool supportsSensorFailureMinimum;
}

class AlertDefinition {
  const AlertDefinition({
    required this.type,
    required this.id,
    required this.label,
    required this.scopeCapability,
    required this.parameterSchema,
    required this.metricBindings,
    required this.supportsVisual,
    required this.supportsWhatsapp,
    required this.supportsWhatsappDelay,
    this.usesRoomWashSuppression = false,
    this.thresholdLinks = const <String, String>{},
  });

  final AlertType type;
  final String id;
  final String label;
  final AlertScopeCapability scopeCapability;
  final AlertParameterSchema parameterSchema;
  final List<AlertMetricBinding> metricBindings;
  final bool supportsVisual;

  /// Campos de `thresholds` de ESTA alerta que en realidad son un espejo de
  /// otra alerta, no un valor propio configurable — clave: nombre del
  /// campo de threshold (`'max'`, `'min'`, `'sensorFailureMin'`); valor:
  /// `id` de la alerta de la que se toma el valor efectivo.
  ///
  /// Pedido explícito del usuario (2026-09-08):
  ///   - `high_temperature_heating_active.max` refleja
  ///     `temperature_interior.max` — nunca un valor propio.
  ///   - `low_temperature_humidifier_active.min` refleja
  ///     `temperature_interior.min` — nunca un valor propio.
  ///   - `temperature_interior.sensorFailureMin` refleja
  ///     `sensor_failure`'s propio umbral — la fuente de verdad de ese
  ///     número pasa a ser exclusivamente la card de "Falla sensor Temp.
  ///     Interior".
  ///
  /// Esto documenta la relación a nivel de contrato para que B6 no la
  /// pierda — hoy no cambia nada en producción porque este catálogo no
  /// está conectado al motor de evaluación real (que sigue leyendo
  /// `CachedAlertThresholds`, donde estos campos YA son, de hecho, el
  /// mismo número compartido — ver comentario en
  /// `LegacyAlertSettingsAdapter._thresholdConfigFor`).
  final Map<String, String> thresholdLinks;
  final bool supportsWhatsapp;
  final bool supportsWhatsappDelay;

  /// Real current behavior: high humidity is suppressed while the room is
  /// inside the room-wash window. This keeps that semantic visible in the
  /// future contract without changing the evaluator.
  final bool usesRoomWashSuppression;
}

class AlertDefinitionCatalog {
  const AlertDefinitionCatalog._();

  static const List<AlertDefinition> definitions = <AlertDefinition>[
    AlertDefinition(
      type: AlertType.muntersDoorOpen,
      id: 'munters_door_open',
      label: 'Puerta Munters abierta',
      scopeCapability: AlertScopeCapability.deviceOrRoom,
      parameterSchema: AlertParameterSchema(kind: AlertParameterKind.none),
      metricBindings: <AlertMetricBinding>[
        AlertMetricBinding(role: 'door', metricKey: 'puertaMunter'),
      ],
      supportsVisual: true,
      supportsWhatsapp: true,
      supportsWhatsappDelay: true,
    ),
    AlertDefinition(
      type: AlertType.roomDoorOpen,
      id: 'room_door_open',
      label: 'Puerta de sala abierta',
      scopeCapability: AlertScopeCapability.room,
      parameterSchema: AlertParameterSchema(kind: AlertParameterKind.none),
      metricBindings: <AlertMetricBinding>[
        AlertMetricBinding(role: 'door', metricKey: 'puertaSala'),
      ],
      supportsVisual: true,
      supportsWhatsapp: true,
      supportsWhatsappDelay: true,
    ),
    AlertDefinition(
      type: AlertType.sensorFailure,
      id: 'sensor_failure',
      label: 'Falla sensor Temp. Interior',
      scopeCapability: AlertScopeCapability.deviceOrRoom,
      // Etapa 2026-09-08: antes tenía `kind: minimum` ADEMÁS de
      // `supportsSensorFailureMinimum`, lo que mostraba dos campos
      // ("Mínimo" y "Mínimo falla sensor") con el mismo número. Ahora
      // muestra uno solo — este ES el dueño real de ese umbral.
      parameterSchema: AlertParameterSchema(
        kind: AlertParameterKind.none,
        supportsSensorFailureMinimum: true,
      ),
      metricBindings: <AlertMetricBinding>[
        AlertMetricBinding(role: 'temperature', metricKey: 'tempInterior'),
      ],
      supportsVisual: true,
      supportsWhatsapp: true,
      supportsWhatsappDelay: false,
    ),
    AlertDefinition(
      type: AlertType.temperatureInterior,
      id: 'temperature_interior',
      label: 'Temperatura interior',
      scopeCapability: AlertScopeCapability.room,
      parameterSchema: AlertParameterSchema(
        kind: AlertParameterKind.range,
        supportsSensorFailureMinimum: true,
      ),
      metricBindings: <AlertMetricBinding>[
        AlertMetricBinding(role: 'temperature', metricKey: 'tempInterior'),
      ],
      supportsVisual: true,
      supportsWhatsapp: true,
      supportsWhatsappDelay: false,
      thresholdLinks: <String, String>{'sensorFailureMin': 'sensor_failure'},
    ),
    AlertDefinition(
      type: AlertType.highTemperatureHeatingActive,
      id: 'high_temperature_heating_active',
      label: 'Temperatura alta con calefaccion activa',
      scopeCapability: AlertScopeCapability.deviceOrRoom,
      // Etapa 2026-09-08: ya no tiene un `max` propio editable — siempre
      // fue, de hecho, el mismo campo compartido que `temperature_interior`
      // en el modelo legacy (ver `_thresholdConfigFor` más abajo); ahora el
      // catálogo lo refleja explícitamente en vez de dejarlo como dos
      // campos que coinciden por casualidad.
      parameterSchema: AlertParameterSchema(kind: AlertParameterKind.none),
      metricBindings: <AlertMetricBinding>[
        AlertMetricBinding(role: 'temperature', metricKey: 'tempInterior'),
        AlertMetricBinding(role: 'heating1', metricKey: 'resistencia1'),
        AlertMetricBinding(role: 'heating2', metricKey: 'resistencia2'),
      ],
      supportsVisual: true,
      supportsWhatsapp: true,
      supportsWhatsappDelay: false,
      thresholdLinks: <String, String>{'max': 'temperature_interior'},
    ),
    AlertDefinition(
      type: AlertType.lowTemperatureHumidifierActive,
      id: 'low_temperature_humidifier_active',
      label: 'Temperatura baja con bomba humidificadora activa',
      scopeCapability: AlertScopeCapability.deviceOrRoom,
      // Mismo criterio que high_temperature_heating_active, para `min`.
      parameterSchema: AlertParameterSchema(kind: AlertParameterKind.none),
      metricBindings: <AlertMetricBinding>[
        AlertMetricBinding(role: 'temperature', metricKey: 'tempInterior'),
        AlertMetricBinding(
          role: 'humidifierPump',
          metricKey: 'bombaHumidificador',
        ),
      ],
      supportsVisual: true,
      supportsWhatsapp: true,
      supportsWhatsappDelay: false,
      thresholdLinks: <String, String>{'min': 'temperature_interior'},
    ),
    AlertDefinition(
      type: AlertType.highDifferentialPressure,
      id: 'high_differential_pressure',
      label: 'Presion diferencial alta',
      scopeCapability: AlertScopeCapability.deviceOrRoom,
      parameterSchema: AlertParameterSchema(kind: AlertParameterKind.maximum),
      metricBindings: <AlertMetricBinding>[
        AlertMetricBinding(
          role: 'differentialPressure',
          metricKey: 'presionDiferencial',
        ),
      ],
      supportsVisual: true,
      supportsWhatsapp: true,
      supportsWhatsappDelay: false,
    ),
    AlertDefinition(
      type: AlertType.highHumidity,
      id: 'high_humidity',
      // Etapa 2026-09-08: pasa a cubrir ambos sentidos (antes solo tenía
      // evaluador de humedad alta) — ver HighHumidityEvaluator en
      // alert_evaluation_engine.dart. El `id`/AlertType no cambian (evita
      // tocar claves ya guardadas en Firestore/Rules), solo el label y el
      // rango de umbrales que expone.
      label: 'Humedad interior',
      scopeCapability: AlertScopeCapability.room,
      parameterSchema: AlertParameterSchema(kind: AlertParameterKind.range),
      metricBindings: <AlertMetricBinding>[
        AlertMetricBinding(role: 'humidity', metricKey: 'humInterior'),
      ],
      supportsVisual: true,
      supportsWhatsapp: true,
      supportsWhatsappDelay: false,
      usesRoomWashSuppression: true,
    ),
    AlertDefinition(
      type: AlertType.dewPointRisk,
      id: 'dew_point_risk',
      label: 'Riesgo por punto de rocio',
      scopeCapability: AlertScopeCapability.room,
      parameterSchema: AlertParameterSchema(
        kind: AlertParameterKind.minimumMargin,
      ),
      metricBindings: <AlertMetricBinding>[
        AlertMetricBinding(role: 'temperature', metricKey: 'tempInterior'),
        AlertMetricBinding(role: 'humidity', metricKey: 'humInterior'),
      ],
      supportsVisual: true,
      supportsWhatsapp: true,
      supportsWhatsappDelay: false,
    ),
  ];

  static AlertDefinition byType(AlertType type) {
    for (final AlertDefinition definition in definitions) {
      if (definition.type == type) {
        return definition;
      }
    }
    throw StateError('Missing alert definition for $type');
  }

  static AlertDefinition byId(String id) {
    for (final AlertDefinition definition in definitions) {
      if (definition.id == id) {
        return definition;
      }
    }
    throw StateError('Missing alert definition for $id');
  }
}

class AlertCapability {
  const AlertCapability({
    required this.alertId,
    required this.enabled,
    required this.metricBindings,
  });

  final String alertId;
  final bool enabled;
  final Map<String, String> metricBindings;
}

class AlertConfigurationTarget {
  const AlertConfigurationTarget({
    required this.tenantId,
    required this.siteId,
    required this.scope,
    this.deviceId,
    this.roomId,
    this.snapshotUnitKey,
    this.muntersId,
  });

  final String tenantId;
  final String siteId;
  final AlertConfigurationScope scope;
  final String? deviceId;
  final String? roomId;
  final String? snapshotUnitKey;
  final String? muntersId;
}

class AlertThresholdConfig {
  const AlertThresholdConfig({
    this.min,
    this.max,
    this.threshold,
    this.margin,
    this.sensorFailureMin,
  });

  final double? min;
  final double? max;
  final double? threshold;
  final double? margin;
  final double? sensorFailureMin;
}

class EffectiveAlertConfig {
  const EffectiveAlertConfig({
    required this.alertId,
    required this.type,
    required this.enabled,
    required this.visualEnabled,
    required this.whatsappEnabled,
    required this.whatsappDelay,
    required this.thresholds,
    required this.cooldown,
    required this.order,
    required this.target,
    required this.metricBindings,
    required this.origin,
    required this.usesRoomWashSuppression,
    this.fieldOrigins = const <String, AlertConfigOrigin>{},
  });

  final String alertId;
  final AlertType type;
  final bool enabled;
  final bool visualEnabled;
  final bool whatsappEnabled;
  final Duration whatsappDelay;
  final AlertThresholdConfig thresholds;
  final Duration cooldown;
  final int order;
  final AlertConfigurationTarget target;
  final Map<String, String> metricBindings;
  final AlertConfigOrigin origin;
  final bool usesRoomWashSuppression;
  final Map<String, AlertConfigOrigin> fieldOrigins;
}

class EffectiveAlertConfiguration {
  const EffectiveAlertConfiguration({
    required this.tenantId,
    required this.siteId,
    required this.target,
    required this.alerts,
    required this.origin,
    required this.configVersion,
  });

  final String tenantId;
  final String siteId;
  final AlertConfigurationTarget target;
  final List<EffectiveAlertConfig> alerts;
  final AlertConfigOrigin origin;
  final int configVersion;

  EffectiveAlertConfig configFor(AlertType type) {
    for (final EffectiveAlertConfig config in alerts) {
      if (config.type == type) {
        return config;
      }
    }
    throw StateError('Missing effective alert config for $type');
  }
}

class LegacyAlertSettingsAdapter {
  const LegacyAlertSettingsAdapter({
    this.runtimeConfig = const AlertRuntimeConfig(),
  });

  final AlertRuntimeConfig runtimeConfig;

  EffectiveAlertConfiguration fromCachedSettings({
    required CachedAlertSettings settings,
    required AlertConfigurationTarget target,
  }) {
    final String muntersId = target.muntersId?.trim().isNotEmpty == true
        ? target.muntersId!.trim()
        : 'munters1';
    final CachedAlertThresholds thresholds = settings.thresholdsFor(muntersId);
    final List<EffectiveAlertConfig> alerts = <EffectiveAlertConfig>[
      for (final AlertMetadata metadata in AlertMetadataRegistry.ordered)
        _configFor(
          metadata.type,
          settings: settings,
          target: target,
          thresholds: thresholds,
        ),
    ];
    return EffectiveAlertConfiguration(
      tenantId: settings.tenantId,
      siteId: settings.siteId,
      target: target,
      alerts: List<EffectiveAlertConfig>.unmodifiable(alerts),
      origin: AlertConfigOrigin.legacy,
      configVersion: settings.configVersion,
    );
  }

  EffectiveAlertConfig _configFor(
    AlertType type, {
    required CachedAlertSettings settings,
    required AlertConfigurationTarget target,
    required CachedAlertThresholds thresholds,
  }) {
    final AlertDefinition definition = AlertDefinitionCatalog.byType(type);
    final CachedAlertToggle toggle = settings.alerts.toggleFor(type);
    return EffectiveAlertConfig(
      alertId: definition.id,
      type: type,
      enabled: toggle.enabled,
      visualEnabled: toggle.enabled,
      whatsappEnabled: toggle.sendWhatsapp,
      whatsappDelay: Duration(minutes: toggle.whatsappDelayMinutes),
      thresholds: _thresholdConfigFor(type, thresholds),
      cooldown: runtimeConfig.cooldownFor(type),
      order: settings.alerts.effectiveOrder(type),
      target: target,
      metricBindings: <String, String>{
        for (final AlertMetricBinding binding in definition.metricBindings)
          binding.role: binding.metricKey,
      },
      origin: AlertConfigOrigin.legacy,
      usesRoomWashSuppression: definition.usesRoomWashSuppression,
    );
  }

  AlertThresholdConfig _thresholdConfigFor(
    AlertType type,
    CachedAlertThresholds thresholds,
  ) {
    return switch (type) {
      AlertType.muntersDoorOpen ||
      AlertType.roomDoorOpen => const AlertThresholdConfig(),
      AlertType.sensorFailure => AlertThresholdConfig(
        min: thresholds.temperatureSensorFailureMin,
        threshold: thresholds.temperatureSensorFailureMin,
        sensorFailureMin: thresholds.temperatureSensorFailureMin,
      ),
      AlertType.temperatureInterior => AlertThresholdConfig(
        min: thresholds.temperatureMin,
        max: thresholds.temperatureMax,
        sensorFailureMin: thresholds.temperatureSensorFailureMin,
      ),
      AlertType.highTemperatureHeatingActive => AlertThresholdConfig(
        max: thresholds.temperatureMax,
        threshold: thresholds.temperatureMax,
      ),
      AlertType.lowTemperatureHumidifierActive => AlertThresholdConfig(
        min: thresholds.temperatureMin,
        threshold: thresholds.temperatureMin,
      ),
      AlertType.highDifferentialPressure => AlertThresholdConfig(
        max: thresholds.filterPressureMax,
        threshold: thresholds.filterPressureMax,
      ),
      AlertType.highHumidity => AlertThresholdConfig(
        min: thresholds.humidityInteriorMin,
        max: thresholds.humidityRedMinExclusive,
        threshold: thresholds.humidityRedMinExclusive,
      ),
      AlertType.dewPointRisk => AlertThresholdConfig(
        margin: thresholds.dewPointMarginRedMaxInclusive,
        threshold: thresholds.dewPointMarginRedMaxInclusive,
      ),
    };
  }
}

enum AlertRecipientConfigScope {
  tenant,
  site,
  device,
  room,
  legacyGlobal,
  legacySite,
}

class HierarchicalAlertRecipient {
  const HierarchicalAlertRecipient({
    required this.id,
    required this.displayName,
    required this.phoneE164,
    required this.enabled,
    required this.scope,
    required this.origin,
    this.tenantId,
    this.siteId,
    this.deviceId,
    this.roomId,
    this.createdAt,
    this.createdBy,
    this.updatedAt,
    this.updatedBy,
  });

  final String id;
  final String displayName;
  final String phoneE164;
  final bool enabled;
  final AlertRecipientConfigScope scope;
  final AlertConfigOrigin origin;
  final String? tenantId;
  final String? siteId;
  final String? deviceId;
  final String? roomId;
  final DateTime? createdAt;
  final String? createdBy;
  final DateTime? updatedAt;
  final String? updatedBy;

  String get normalizedPhone => normalizeAlertRecipientPhoneE164(phoneE164);
}

String normalizeAlertRecipientPhoneE164(String phone) {
  final String digits = legacy_recipients.normalizeWhatsAppPhone(phone);
  if (digits.isEmpty) {
    return '';
  }
  return '+$digits';
}

List<HierarchicalAlertRecipient> deduplicateHierarchicalAlertRecipients(
  Iterable<HierarchicalAlertRecipient> recipients,
) {
  final Set<String> seenPhones = <String>{};
  final List<HierarchicalAlertRecipient> deduplicated =
      <HierarchicalAlertRecipient>[];
  for (final HierarchicalAlertRecipient recipient in recipients) {
    if (!recipient.enabled) {
      continue;
    }
    final String normalizedPhone = recipient.normalizedPhone;
    if (normalizedPhone.isEmpty || !seenPhones.add(normalizedPhone)) {
      continue;
    }
    deduplicated.add(recipient);
  }
  return List<HierarchicalAlertRecipient>.unmodifiable(deduplicated);
}

class LegacyAlertRecipientAdapter {
  const LegacyAlertRecipientAdapter();

  List<HierarchicalAlertRecipient> fromLegacyRecipients(
    Iterable<legacy_recipients.AlertRecipient> recipients,
  ) {
    return List<HierarchicalAlertRecipient>.unmodifiable(
      recipients
          .where((legacy_recipients.AlertRecipient recipient) {
            return recipient.isConfigured;
          })
          .map(_fromLegacyRecipient),
    );
  }

  HierarchicalAlertRecipient _fromLegacyRecipient(
    legacy_recipients.AlertRecipient recipient,
  ) {
    final String phoneE164 = normalizeAlertRecipientPhoneE164(recipient.phone);
    return HierarchicalAlertRecipient(
      id: 'legacy_${phoneE164.replaceAll(RegExp(r'[^0-9]'), '')}',
      displayName: recipient.contactName,
      phoneE164: phoneE164,
      enabled: true,
      scope: recipient.scope == legacy_recipients.AlertRecipientScope.global
          ? AlertRecipientConfigScope.legacyGlobal
          : AlertRecipientConfigScope.legacySite,
      origin: AlertConfigOrigin.legacy,
      tenantId: recipient.tenantId,
      siteId: recipient.siteId,
    );
  }
}

class HierarchicalAlertRecipientResolver {
  const HierarchicalAlertRecipientResolver();

  List<HierarchicalAlertRecipient> resolve({
    Iterable<HierarchicalAlertRecipient> tenantRecipients =
        const <HierarchicalAlertRecipient>[],
    Iterable<HierarchicalAlertRecipient> siteRecipients =
        const <HierarchicalAlertRecipient>[],
    Iterable<HierarchicalAlertRecipient> deviceRecipients =
        const <HierarchicalAlertRecipient>[],
    Iterable<HierarchicalAlertRecipient> roomRecipients =
        const <HierarchicalAlertRecipient>[],
    Iterable<HierarchicalAlertRecipient> legacyRecipients =
        const <HierarchicalAlertRecipient>[],
  }) {
    // Lower scopes win only when the same normalized phone appears more than
    // once. Inheritance remains additive for different phones.
    return deduplicateHierarchicalAlertRecipients(<HierarchicalAlertRecipient>[
      ...roomRecipients,
      ...deviceRecipients,
      ...siteRecipients,
      ...tenantRecipients,
      ...legacyRecipients,
    ]);
  }
}
