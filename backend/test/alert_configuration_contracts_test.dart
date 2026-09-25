import 'package:agro_data_control_backend/src/alert_configuration_contracts.dart';
import 'package:agro_data_control_backend/src/alert_priority.dart';
import 'package:agro_data_control_backend/src/alert_runtime_config.dart';
import 'package:agro_data_control_backend/src/alert_settings_cache.dart';
import 'package:agro_data_control_backend/src/whatsapp_alert_recipients.dart'
    as legacy_recipients;

void main() {
  _testCatalogCoversCurrentAlerts();
  _testCatalogBindingsAndScopes();
  _testLegacyAdapterPreservesTheGenePigConfiguration();
  _testLegacyAdapterPreservesExplicitFalseValues();
  _testLegacyAdapterUsesCurrentDefaults();
  _testRecipientPhoneNormalizationAndLegacyAdapter();
  _testRecipientDeduplicationRules();
  _testRecipientDisabledEntriesAreIgnored();
}

void _testCatalogCoversCurrentAlerts() {
  final List<AlertDefinition> definitions = AlertDefinitionCatalog.definitions;
  _expect(
    definitions.length == AlertType.values.length,
    'catalog covers all current alert types',
  );

  final Set<String> ids = <String>{};
  final Set<AlertType> types = <AlertType>{};
  for (final AlertDefinition definition in definitions) {
    _expect(definition.id.isNotEmpty, 'definition id is not empty');
    _expect(ids.add(definition.id), 'definition id is unique');
    _expect(types.add(definition.type), 'definition type is unique');
    _expect(
      definition.id == definition.type.id,
      'definition id matches current stable alert id',
    );
    _expect(definition.label.isNotEmpty, 'definition label is not empty');
  }
}

void _testCatalogBindingsAndScopes() {
  _expect(
    AlertDefinitionCatalog.byType(AlertType.roomDoorOpen).scopeCapability ==
        AlertScopeCapability.room,
    'room door alert is room scoped',
  );
  _expect(
    AlertDefinitionCatalog.byType(
          AlertType.temperatureInterior,
        ).scopeCapability ==
        AlertScopeCapability.room,
    'temperature alert is room scoped',
  );
  _expect(
    AlertDefinitionCatalog.byType(
          AlertType.highDifferentialPressure,
        ).scopeCapability ==
        AlertScopeCapability.deviceOrRoom,
    'differential pressure supports device or room scope',
  );
  _expect(
    AlertDefinitionCatalog.byType(AlertType.muntersDoorOpen).scopeCapability ==
        AlertScopeCapability.deviceOrRoom,
    'munters door supports device or room scope',
  );

  _expectBinding(AlertType.temperatureInterior, 'temperature', 'tempInterior');
  _expectBinding(AlertType.highHumidity, 'humidity', 'humInterior');
  _expectBinding(
    AlertType.highDifferentialPressure,
    'differentialPressure',
    'presionDiferencial',
  );
  _expectBinding(AlertType.roomDoorOpen, 'door', 'puertaSala');
  _expectBinding(AlertType.muntersDoorOpen, 'door', 'puertaMunter');
  _expectBinding(
    AlertType.highTemperatureHeatingActive,
    'heating1',
    'resistencia1',
  );
  _expectBinding(
    AlertType.highTemperatureHeatingActive,
    'heating2',
    'resistencia2',
  );
  _expectBinding(
    AlertType.lowTemperatureHumidifierActive,
    'humidifierPump',
    'bombaHumidificador',
  );
  _expect(
    AlertDefinitionCatalog.byType(
      AlertType.highHumidity,
    ).usesRoomWashSuppression,
    'high humidity preserves room wash suppression semantic',
  );
}

void _testLegacyAdapterPreservesTheGenePigConfiguration() {
  final CachedAlertSettings settings = CachedAlertSettings.fromRaw(
    tenantId: 'the-gene-pig',
    siteId: 'las-heras',
    raw: _theGenePigLikeSettings(),
    loadedAt: DateTime.utc(2026, 9, 3),
    source: 'test',
    configVersion: 7,
  );
  const LegacyAlertSettingsAdapter adapter = LegacyAlertSettingsAdapter(
    runtimeConfig: AlertRuntimeConfig(
      cooldown: Duration(minutes: 10),
      doorOpeningCooldown: Duration(minutes: 60),
    ),
  );
  final EffectiveAlertConfiguration effective = adapter.fromCachedSettings(
    settings: settings,
    target: const AlertConfigurationTarget(
      tenantId: 'the-gene-pig',
      siteId: 'las-heras',
      scope: AlertConfigurationScope.room,
      deviceId: 'munters1',
      roomId: 'room_1',
      snapshotUnitKey: 'munters1',
      muntersId: 'munters1',
    ),
  );

  _expect(effective.origin == AlertConfigOrigin.legacy, 'origin is legacy');
  _expect(effective.configVersion == 7, 'config version is preserved');
  _expect(
    effective.alerts.length == AlertType.values.length,
    'adapter returns one effective config per current alert',
  );

  final EffectiveAlertConfig muntersDoor = effective.configFor(
    AlertType.muntersDoorOpen,
  );
  _expect(muntersDoor.enabled, 'munters door enabled preserved');
  _expect(muntersDoor.whatsappEnabled, 'munters door whatsapp preserved');
  _expect(
    muntersDoor.whatsappDelay == const Duration(minutes: 12),
    'munters door delay preserved',
  );
  _expect(
    muntersDoor.cooldown == const Duration(minutes: 60),
    'door cooldown preserved',
  );

  final EffectiveAlertConfig temperature = effective.configFor(
    AlertType.temperatureInterior,
  );
  _expect(temperature.thresholds.min == 19.5, 'temperature min preserved');
  _expect(temperature.thresholds.max == 28.0, 'temperature max preserved');
  _expect(
    temperature.thresholds.sensorFailureMin == 1.0,
    'sensor failure min preserved on temperature config',
  );
  _expect(
    temperature.metricBindings['temperature'] == 'tempInterior',
    'temperature binding preserved',
  );

  final EffectiveAlertConfig humidity = effective.configFor(
    AlertType.highHumidity,
  );
  _expect(humidity.thresholds.max == 88.0, 'humidity threshold preserved');
  _expect(
    humidity.usesRoomWashSuppression,
    'humidity room wash suppression preserved',
  );

  final EffectiveAlertConfig dewPoint = effective.configFor(
    AlertType.dewPointRisk,
  );
  _expect(dewPoint.thresholds.margin == 2.5, 'dew point margin preserved');
  _expect(
    dewPoint.thresholds.threshold == 2.5,
    'dew point threshold preserved',
  );

  final EffectiveAlertConfig pressure = effective.configFor(
    AlertType.highDifferentialPressure,
  );
  _expect(pressure.thresholds.max == 125.0, 'pressure max preserved');
  _expect(
    pressure.cooldown == const Duration(minutes: 10),
    'non-door cooldown preserved',
  );
}

void _testLegacyAdapterPreservesExplicitFalseValues() {
  final CachedAlertSettings settings = CachedAlertSettings.fromRaw(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    raw: <String, Object?>{
      'alerts': <String, Object?>{
        'temperatureInterior': <String, Object?>{
          'enabled': false,
          'sendWhatsapp': true,
          'order': 4,
        },
        'roomDoorOpen': <String, Object?>{
          'enabled': true,
          'sendWhatsapp': false,
          'whatsappDelayMinutes': 9,
        },
      },
    },
    loadedAt: DateTime.utc(2026),
    source: 'test',
  );

  final EffectiveAlertConfiguration effective =
      const LegacyAlertSettingsAdapter().fromCachedSettings(
        settings: settings,
        target: _target(),
      );

  final EffectiveAlertConfig temperature = effective.configFor(
    AlertType.temperatureInterior,
  );
  _expect(!temperature.enabled, 'explicit false enabled is preserved');
  _expect(
    !temperature.whatsappEnabled,
    'disabled alert cannot keep whatsapp enabled',
  );

  final EffectiveAlertConfig roomDoor = effective.configFor(
    AlertType.roomDoorOpen,
  );
  _expect(roomDoor.enabled, 'room door remains enabled');
  _expect(!roomDoor.whatsappEnabled, 'explicit false whatsapp is preserved');
  _expect(
    roomDoor.whatsappDelay == const Duration(minutes: 9),
    'door delay is preserved even when whatsapp is false',
  );
}

void _testLegacyAdapterUsesCurrentDefaults() {
  final CachedAlertSettings settings = CachedAlertSettings.fromRaw(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    raw: const <String, Object?>{},
    loadedAt: DateTime.utc(2026),
    source: 'test',
  );
  final EffectiveAlertConfiguration effective =
      const LegacyAlertSettingsAdapter().fromCachedSettings(
        settings: settings,
        target: _target(),
      );

  final EffectiveAlertConfig sensorFailure = effective.configFor(
    AlertType.sensorFailure,
  );
  _expect(sensorFailure.enabled, 'missing toggles default to enabled');
  _expect(
    !sensorFailure.whatsappEnabled,
    'missing toggles default to whatsapp disabled',
  );
  _expect(sensorFailure.order == 3, 'missing order uses current default order');
  _expect(
    sensorFailure.origin == AlertConfigOrigin.legacy,
    'defaulted legacy values still expose legacy origin',
  );
}

void _testRecipientPhoneNormalizationAndLegacyAdapter() {
  _expect(
    normalizeAlertRecipientPhoneE164('5491138267368') == '+5491138267368',
    'plain digits normalize to E.164 identity',
  );
  _expect(
    normalizeAlertRecipientPhoneE164('+54 9 11 3826 7368') == '+5491138267368',
    'formatted phone normalizes to E.164 identity',
  );
  _expect(
    normalizeAlertRecipientPhoneE164('PENDING_PHONE') == '',
    'placeholder phone has empty identity',
  );

  final List<HierarchicalAlertRecipient> adapted =
      const LegacyAlertRecipientAdapter()
          .fromLegacyRecipients(const <legacy_recipients.AlertRecipient>[
            legacy_recipients.AlertRecipient(
              scope: legacy_recipients.AlertRecipientScope.global,
              contactName: 'Gerardo',
              phone: '5491138267368',
            ),
            legacy_recipients.AlertRecipient(
              scope: legacy_recipients.AlertRecipientScope.tenantSite,
              tenantId: 'tenant-a',
              siteId: 'site-a',
              clientName: 'Cliente',
              siteName: 'Sitio',
              contactName: 'Placeholder',
              phone: 'PENDING_PHONE',
            ),
          ]);
  _expect(adapted.length == 1, 'legacy adapter ignores placeholders');
  _expect(
    adapted.single.scope == AlertRecipientConfigScope.legacyGlobal,
    'legacy global scope is represented',
  );
  _expect(
    adapted.single.origin == AlertConfigOrigin.legacy,
    'legacy recipient origin is represented',
  );
}

void _testRecipientDeduplicationRules() {
  const HierarchicalAlertRecipientResolver resolver =
      HierarchicalAlertRecipientResolver();

  _expect(
    resolver
            .resolve(
              tenantRecipients: <HierarchicalAlertRecipient>[
                _recipient('tenant-gerardo', 'Gerardo', '+5491138267368'),
              ],
              siteRecipients: <HierarchicalAlertRecipient>[
                _recipient('site-gerardo', 'Gerardo Sitio', '5491138267368'),
              ],
            )
            .single
            .id ==
        'site-gerardo',
    'same phone in tenant and site deduplicates to one recipient',
  );
  _expect(
    resolver
            .resolve(
              siteRecipients: <HierarchicalAlertRecipient>[
                _recipient('site-gerardo', 'Gerardo', '+5491138267368'),
              ],
              deviceRecipients: <HierarchicalAlertRecipient>[
                _recipient('device-other-name', 'Otro Nombre', '5491138267368'),
              ],
            )
            .single
            .id ==
        'device-other-name',
    'same phone in site and device keeps lower-scope metadata',
  );
  _expect(
    resolver
            .resolve(
              tenantRecipients: <HierarchicalAlertRecipient>[
                _recipient('tenant-a', 'Mismo Nombre', '+5491138267368'),
                _recipient('tenant-b', 'Mismo Nombre', '+5491130740079'),
              ],
            )
            .length ==
        2,
    'different phones with same name remain two recipients',
  );
}

void _testRecipientDisabledEntriesAreIgnored() {
  final List<HierarchicalAlertRecipient> resolved =
      const HierarchicalAlertRecipientResolver().resolve(
        tenantRecipients: <HierarchicalAlertRecipient>[
          _recipient('disabled', 'Deshabilitado', '+5491138267368', false),
          _recipient('enabled', 'Habilitado', '+5491130740079'),
        ],
      );
  _expect(resolved.length == 1, 'disabled recipient is ignored');
  _expect(resolved.single.id == 'enabled', 'enabled recipient remains');
}

void _expectBinding(AlertType type, String role, String metricKey) {
  final AlertDefinition definition = AlertDefinitionCatalog.byType(type);
  final AlertMetricBinding binding = definition.metricBindings.firstWhere(
    (AlertMetricBinding candidate) => candidate.role == role,
  );
  _expect(
    binding.metricKey == metricKey,
    'binding $role for ${type.id} uses $metricKey',
  );
}

Map<String, Object?> _theGenePigLikeSettings() {
  return <String, Object?>{
    'alerts': <String, Object?>{
      'muntersDoorOpen': <String, Object?>{
        'enabled': true,
        'sendWhatsapp': true,
        'whatsappDelayMinutes': 12,
        'order': 1,
      },
      'roomDoorOpen': <String, Object?>{
        'enabled': true,
        'sendWhatsapp': true,
        'whatsappDelayMinutes': 15,
        'order': 2,
      },
      'sensorFailure': <String, Object?>{
        'enabled': true,
        'sendWhatsapp': true,
        'order': 3,
      },
      'temperatureInterior': <String, Object?>{
        'enabled': true,
        'sendWhatsapp': true,
        'order': 4,
      },
      'highTemperatureHeatingActive': <String, Object?>{
        'enabled': true,
        'sendWhatsapp': false,
        'order': 5,
      },
      'lowTemperatureHumidifierActive': <String, Object?>{
        'enabled': true,
        'sendWhatsapp': false,
        'order': 6,
      },
      'highDifferentialPressure': <String, Object?>{
        'enabled': true,
        'sendWhatsapp': true,
        'order': 7,
      },
      'highHumidity': <String, Object?>{
        'enabled': true,
        'sendWhatsapp': true,
        'order': 8,
      },
      'dewPointRisk': <String, Object?>{
        'enabled': true,
        'sendWhatsapp': true,
        'order': 9,
      },
    },
    'munters': <String, Object?>{
      'munters1': <String, Object?>{
        'tempInterior': <String, Object?>{
          'min': 19.5,
          'max': 28.0,
          'sensorFailure': <String, Object?>{'min': 1.0},
        },
        'humidityInterior': <String, Object?>{
          'alarm': <String, Object?>{'redMinExclusive': 88.0},
        },
        'dewPointMargin': <String, Object?>{
          'alarm': <String, Object?>{'redMaxInclusive': 2.5},
        },
        'presionDiferencial': <String, Object?>{'max': 125.0},
      },
    },
  };
}

AlertConfigurationTarget _target() {
  return const AlertConfigurationTarget(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    scope: AlertConfigurationScope.room,
    deviceId: 'munters1',
    roomId: 'room_1',
    snapshotUnitKey: 'munters1',
    muntersId: 'munters1',
  );
}

HierarchicalAlertRecipient _recipient(
  String id,
  String displayName,
  String phone, [
  bool enabled = true,
]) {
  return HierarchicalAlertRecipient(
    id: id,
    displayName: displayName,
    phoneE164: phone,
    enabled: enabled,
    scope: AlertRecipientConfigScope.tenant,
    origin: AlertConfigOrigin.tenant,
  );
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Failed expectation: $description');
  }
}
