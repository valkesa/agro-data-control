import 'package:agro_data_control/models/hierarchical_alert_catalog.dart';
import 'package:agro_data_control/models/hierarchical_alert_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AlertDefinitionCatalog', () {
    test('tiene exactamente las 9 alertas del backend (Etapa B2)', () {
      const List<String> expectedIds = [
        'munters_door_open',
        'room_door_open',
        'sensor_failure',
        'temperature_interior',
        'high_temperature_heating_active',
        'low_temperature_humidifier_active',
        'high_differential_pressure',
        'high_humidity',
        'dew_point_risk',
      ];
      expect(
        AlertDefinitionCatalog.definitions.map((d) => d.id).toList(),
        expectedIds,
      );
    });

    test('temperature_interior expone min y max, no margin', () {
      final AlertDefinition def = AlertDefinitionCatalog.byId(
        'temperature_interior',
      );
      expect(def.applicableThresholdFields, {'min', 'max', 'sensorFailureMin'});
    });

    test('dew_point_risk expone solo margin (Etapa B5 §13)', () {
      final AlertDefinition def = AlertDefinitionCatalog.byId('dew_point_risk');
      expect(def.applicableThresholdFields, {'margin'});
    });

    test(
      // Etapa B5.1 §7-10: réplica exacta de AlertMetadataRegistry.all en
      // backend/lib/src/alert_priority.dart — fijado por número, no por
      // posición de lista, para que un drift futuro se note como valor
      // incorrecto y no pase desapercibido.
      'order replica exactamente AlertMetadataRegistry.all del backend',
      () {
        const Map<String, int> expectedOrderById = {
          'munters_door_open': 1,
          'room_door_open': 2,
          'sensor_failure': 3,
          'temperature_interior': 4,
          'high_temperature_heating_active': 5,
          'low_temperature_humidifier_active': 6,
          'high_differential_pressure': 7,
          'high_humidity': 8,
          'dew_point_risk': 9,
        };
        for (final MapEntry<String, int> entry in expectedOrderById.entries) {
          expect(
            AlertDefinitionCatalog.byId(entry.key).order,
            entry.value,
            reason: 'order de ${entry.key}',
          );
        }
      },
    );

    test('munters_door_open no expone ningun threshold', () {
      final AlertDefinition def = AlertDefinitionCatalog.byId(
        'munters_door_open',
      );
      expect(def.applicableThresholdFields, isEmpty);
    });

    test(
      // Pedido del usuario (2026-09-08): "Falla sensor Temp. Interior"
      // pasa a ser la única dueña de ese umbral — ya no muestra también un
      // "Mínimo" genérico redundante con el mismo número.
      'sensor_failure expone solo sensorFailureMin (sin "min" genérico redundante)',
      () {
        final AlertDefinition def = AlertDefinitionCatalog.byId(
          'sensor_failure',
        );
        expect(def.applicableThresholdFields, {'sensorFailureMin'});
        expect(def.thresholdLinks, isEmpty);
      },
    );

    test(
      'temperature_interior enlaza sensorFailureMin a sensor_failure (solo lectura)',
      () {
        final AlertDefinition def = AlertDefinitionCatalog.byId(
          'temperature_interior',
        );
        expect(def.thresholdLinks, {'sensorFailureMin': 'sensor_failure'});
      },
    );

    test(
      // Pedido del usuario (2026-09-08): estas dos alertas ya no tienen un
      // umbral propio editable — reflejan max/min de temperature_interior.
      'high_temperature_heating_active/low_temperature_humidifier_active enlazan a temperature_interior',
      () {
        final AlertDefinition heating = AlertDefinitionCatalog.byId(
          'high_temperature_heating_active',
        );
        expect(heating.thresholdLinks, {'max': 'temperature_interior'});
        expect(heating.applicableThresholdFields, {'max'});

        final AlertDefinition humidifier = AlertDefinitionCatalog.byId(
          'low_temperature_humidifier_active',
        );
        expect(humidifier.thresholdLinks, {'min': 'temperature_interior'});
        expect(humidifier.applicableThresholdFields, {'min'});
      },
    );

    test(
      // Pedido del usuario (2026-09-08): humedad interior baja real, ambos
      // sentidos configurables, sin links (son valores propios).
      'high_humidity expone min y max, sin thresholdLinks, label sin "alta"',
      () {
        final AlertDefinition def = AlertDefinitionCatalog.byId(
          'high_humidity',
        );
        expect(def.applicableThresholdFields, {'min', 'max'});
        expect(def.thresholdLinks, isEmpty);
        expect(def.label, 'Humedad interior');
      },
    );
  });

  group('resolveEffectiveAlertConfig — precedencia', () {
    test('Room > Device > Site > Tenant > legacy > catálogo', () {
      final EffectiveAlertConfig effective = resolveEffectiveAlertConfig(
        alertId: 'temperature_interior',
        catalogOrder: 4,
        legacy: const AlertConfigOverride(enabled: false, order: 99),
        tenant: const AlertConfigOverride(enabled: true, cooldownMinutes: 10),
        site: const AlertConfigOverride(whatsappEnabled: true),
        device: const AlertConfigOverride(whatsappEnabled: false),
        room: AlertConfigOverride.empty,
      );
      // enabled: solo tenant lo define -> tenant gana sobre legacy.
      expect(effective.enabled, isTrue);
      expect(effective.fieldOrigins['enabled'], AlertConfigOrigin.tenant);
      // whatsappEnabled: device (false explícito) gana sobre site (true).
      expect(effective.whatsappEnabled, isFalse);
      expect(
        effective.fieldOrigins['whatsappEnabled'],
        AlertConfigOrigin.device,
      );
      // cooldownMinutes: solo tenant lo define.
      expect(effective.cooldownMinutes, 10);
      expect(
        effective.fieldOrigins['cooldownMinutes'],
        AlertConfigOrigin.tenant,
      );
      // order: nadie lo define salvo legacy -> legacy gana sobre catálogo.
      expect(effective.order, 99);
      expect(effective.fieldOrigins['order'], AlertConfigOrigin.legacy);
    });

    test(
      'explicit false en el nivel más específico se preserva (Etapa B5 §12)',
      () {
        final EffectiveAlertConfig effective = resolveEffectiveAlertConfig(
          alertId: 'high_humidity',
          catalogOrder: 8,
          tenant: const AlertConfigOverride(whatsappEnabled: true),
          room: const AlertConfigOverride(whatsappEnabled: false),
        );
        expect(effective.whatsappEnabled, isFalse);
        expect(
          effective.fieldOrigins['whatsappEnabled'],
          AlertConfigOrigin.room,
        );
      },
    );

    test('nivel no aplicable (null) no compite ni dispara herencia', () {
      final EffectiveAlertConfig effective = resolveEffectiveAlertConfig(
        alertId: 'high_humidity',
        catalogOrder: 8,
        tenant: const AlertConfigOverride(enabled: true),
        site: null,
        device: null,
        room: null,
      );
      expect(effective.enabled, isTrue);
      expect(effective.fieldOrigins['enabled'], AlertConfigOrigin.tenant);
    });

    test('sin ningún override, cae al default del catálogo', () {
      final EffectiveAlertConfig effective = resolveEffectiveAlertConfig(
        alertId: 'high_humidity',
        catalogOrder: 8,
      );
      expect(effective.enabled, AlertCatalogDefaults.enabled);
      expect(
        effective.fieldOrigins['enabled'],
        AlertConfigOrigin.catalogDefault,
      );
      expect(effective.order, 8);
      expect(effective.fieldOrigins['order'], AlertConfigOrigin.catalogDefault);
    });

    test(
      // Etapa B5.1 §10: usa el order REAL del catálogo (no un número
      // mágico) para cada alerta, sin ningún override en ningún nivel.
      'sin overrides, el order efectivo es el order real del catálogo para cada alerta',
      () {
        for (final AlertDefinition definition
            in AlertDefinitionCatalog.definitions) {
          final EffectiveAlertConfig effective = resolveEffectiveAlertConfig(
            alertId: definition.id,
            catalogOrder: definition.order,
          );
          expect(
            effective.order,
            definition.order,
            reason: 'order efectivo de ${definition.id}',
          );
          expect(
            effective.fieldOrigins['order'],
            AlertConfigOrigin.catalogDefault,
          );
        }
      },
    );

    test(
      'override de order en un nivel gana sobre el order real del catálogo',
      () {
        final AlertDefinition definition = AlertDefinitionCatalog.byId(
          'dew_point_risk',
        );
        // catalogOrder real de dew_point_risk es 9; el Site lo pisa con 2.
        final EffectiveAlertConfig effective = resolveEffectiveAlertConfig(
          alertId: definition.id,
          catalogOrder: definition.order,
          site: const AlertConfigOverride(order: 2),
        );
        expect(effective.order, 2);
        expect(effective.fieldOrigins['order'], AlertConfigOrigin.site);
      },
    );
  });

  group('AlertThresholds.merge — merge campo a campo (Etapa B3)', () {
    test('cada campo hereda independientemente del más específico', () {
      const AlertThresholds child = AlertThresholds(max: 28);
      const AlertThresholds parent = AlertThresholds(min: 20, max: 30);
      final AlertThresholds merged = AlertThresholds.merge(child, parent);
      expect(merged.min, 20); // heredado del parent
      expect(merged.max, 28); // override del child
    });

    test('resolver: threshold parcial no borra los demás campos', () {
      final EffectiveAlertConfig effective = resolveEffectiveAlertConfig(
        alertId: 'temperature_interior',
        catalogOrder: 4,
        tenant: const AlertConfigOverride(
          thresholds: AlertThresholds(min: 20, max: 30),
        ),
        site: const AlertConfigOverride(thresholds: AlertThresholds(max: 28)),
      );
      expect(effective.thresholds.min, 20);
      expect(effective.thresholds.max, 28);
      expect(
        effective.fieldOrigins['thresholds.min'],
        AlertConfigOrigin.tenant,
      );
      expect(effective.fieldOrigins['thresholds.max'], AlertConfigOrigin.site);
    });
  });

  group('AlertConfigOverride.hasFunctionalOverride (Etapa B4/B4.1 §22)', () {
    test('vacío no tiene override funcional', () {
      expect(AlertConfigOverride.empty.hasFunctionalOverride, isFalse);
    });

    test('solo un campo ya lo hace funcional', () {
      expect(
        const AlertConfigOverride(enabled: true).hasFunctionalOverride,
        isTrue,
      );
    });

    test('thresholds vacío (todos null) no cuenta como funcional', () {
      const AlertConfigOverride override = AlertConfigOverride(
        thresholds: AlertThresholds.empty,
      );
      expect(override.hasFunctionalOverride, isFalse);
    });

    test('un solo campo de thresholds ya cuenta como funcional', () {
      const AlertConfigOverride override = AlertConfigOverride(
        thresholds: AlertThresholds(max: 28),
      );
      expect(override.hasFunctionalOverride, isTrue);
    });
  });

  group('AlertConfigOverride.copyWith — "Heredar" limpia a null', () {
    test('copyWith(enabled: null) vuelve a heredar, no pone false', () {
      const AlertConfigOverride override = AlertConfigOverride(enabled: true);
      final AlertConfigOverride cleared = override.copyWith(enabled: null);
      expect(cleared.enabled, isNull);
    });
  });
}
