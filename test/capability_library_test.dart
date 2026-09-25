import 'package:flutter_test/flutter_test.dart';
import 'package:agro_data_control/device_capabilities/capability_indicator_definition.dart';
import 'package:agro_data_control/device_capabilities/capability_library_store.dart';
import 'package:agro_data_control/device_capabilities/capability_metric_definition.dart';
import 'package:agro_data_control/device_capabilities/capability_reference_utils.dart';
import 'package:agro_data_control/device_capabilities/device_capability_profile_store.dart';
import 'package:agro_data_control/device_capabilities/indicator_binding.dart';
import 'package:agro_data_control/device_capabilities/metric_binding.dart';
import 'package:agro_data_control/device_capabilities/reference_capability_seeds.dart';
import 'package:agro_data_control/ui_templates/enums/metric_display_type.dart';

CapabilityMetricDefinition _tempInterior() => CapabilityMetricDefinition(
  key: 'tempInterior',
  label: 'Temperatura interior',
  defaultUnit: '°C',
  icon: 'thermometer',
  displayType: MetricDisplayType.number,
  decimals: 1,
);

CapabilityIndicatorDefinition _indicator(String key, String label) =>
    CapabilityIndicatorDefinition(key: key, label: label, defaultIcon: 'flame');

void main() {
  group('N6.5.2 §22 Bibliotecas — reutilización entre perfiles', () {
    late MetricLibraryStore metrics;
    late IndicatorLibraryStore indicators;
    late DeviceCapabilityProfileStore profiles;

    setUp(() {
      metrics = MetricLibraryStore();
      indicators = IndicatorLibraryStore();
      profiles = DeviceCapabilityProfileStore();
      metrics.upsert(_tempInterior());
      indicators.upsert(_indicator('heater', 'Calefacción'));
      indicators.upsert(_indicator('humidifier', 'Humidificador'));
      profiles.create(name: 'Perfil A');
      profiles.create(name: 'Perfil B');
      final a = profiles.profiles[0];
      final b = profiles.profiles[1];
      profiles.addMetric(
        a.id,
        'tempInterior',
        MetricBinding(sourceField: 'room1.temp'),
      );
      profiles.addMetric(
        b.id,
        'tempInterior',
        MetricBinding(sourceField: 'plc.temperature'),
      );
      profiles.addIndicator(
        a.id,
        'heater',
        IndicatorBinding(sourceField: 'calefaccionEtapa1'),
      );
      profiles.addIndicator(
        b.id,
        'humidifier',
        IndicatorBinding(sourceField: 'humidifierOn'),
      );
    });

    test(
      'una métrica global es reutilizada por 2 perfiles, sin duplicarse',
      () {
        expect(
          metrics.metrics.where((m) => m.key == 'tempInterior'),
          hasLength(1),
        );
        final a = profiles.profiles[0];
        final b = profiles.profiles[1];
        expect(a.metricKeys, contains('tempInterior'));
        expect(b.metricKeys, contains('tempInterior'));
        // Same global definition object reused, not two copies.
        expect(
          metrics.byKey('tempInterior'),
          same(metrics.byKey('tempInterior')),
        );
      },
    );

    test(
      'un indicator global es reutilizado por perfiles distintos, sin duplicarse',
      () {
        expect(indicators.indicators, hasLength(2));
        final refsHeater = profiles.findIndicatorKeyReferences('heater');
        final refsHumidifier = profiles.findIndicatorKeyReferences(
          'humidifier',
        );
        expect(refsHeater, hasLength(1));
        expect(refsHumidifier, hasLength(1));
      },
    );

    test('editar el binding de Perfil A nunca afecta a Perfil B', () {
      final a = profiles.profiles[0];
      final b = profiles.profiles[1];
      profiles.setMetricBinding(
        a.id,
        'tempInterior',
        MetricBinding(sourceField: 'room1.temp.changed'),
      );
      final resolvedA = profiles.byId(a.id)!.resolve(metrics, indicators);
      final resolvedB = profiles.byId(b.id)!.resolve(metrics, indicators);
      expect(
        resolvedA.metricByKey('tempInterior')!.sourceField,
        'room1.temp.changed',
      );
      expect(
        resolvedB.metricByKey('tempInterior')!.sourceField,
        'plc.temperature',
      );
    });

    test(
      'sourceField no es tratado como universal: el mismo metricKey resuelve '
      'sourceField distinto por perfil',
      () {
        final a = profiles.profiles[0];
        final b = profiles.profiles[1];
        final resolvedA = profiles.byId(a.id)!.resolve(metrics, indicators);
        final resolvedB = profiles.byId(b.id)!.resolve(metrics, indicators);
        expect(
          resolvedA.metricByKey('tempInterior')!.sourceField,
          'room1.temp',
        );
        expect(
          resolvedB.metricByKey('tempInterior')!.sourceField,
          'plc.temperature',
        );
        expect(
          resolvedA.metricByKey('tempInterior')!.sourceField,
          isNot(resolvedB.metricByKey('tempInterior')!.sourceField),
        );
      },
    );
  });

  group('N6.5.2 §22 Perfil — CRUD', () {
    late MetricLibraryStore metrics;
    late IndicatorLibraryStore indicators;
    late DeviceCapabilityProfileStore profiles;

    setUp(() {
      metrics = MetricLibraryStore();
      indicators = IndicatorLibraryStore();
      profiles = DeviceCapabilityProfileStore();
      metrics.upsert(_tempInterior());
      indicators.upsert(_indicator('heater', 'Calefacción'));
    });

    test('crear un perfil vacío', () {
      final profile = profiles.create(name: 'Sala nueva');
      expect(profile.metricKeys, isEmpty);
      expect(profile.indicatorKeys, isEmpty);
      expect(profiles.byId(profile.id), isNotNull);
    });

    test(
      'duplicar copia membership/bindings/suggestions de forma independiente',
      () {
        final original = profiles.create(name: 'Original');
        profiles.addMetric(
          original.id,
          'tempInterior',
          MetricBinding(sourceField: 'x.temp'),
        );
        profiles.addIndicator(
          original.id,
          'heater',
          IndicatorBinding(sourceField: 'heaterOn'),
        );
        profiles.setSuggestedIndicators(original.id, 'tempInterior', [
          'heater',
        ]);

        final copy = profiles.duplicate(original.id);
        expect(copy.id, isNot(original.id));
        expect(copy.metricKeys, ['tempInterior']);
        expect(copy.suggestedIndicatorsByMetric['tempInterior'], ['heater']);

        // Editing the copy's binding never reaches back into the original.
        profiles.setMetricBinding(
          copy.id,
          'tempInterior',
          MetricBinding(sourceField: 'y.temp'),
        );
        expect(
          profiles
              .byId(original.id)!
              .metricBindings['tempInterior']!
              .sourceField,
          'x.temp',
        );
        expect(
          profiles.byId(copy.id)!.metricBindings['tempInterior']!.sourceField,
          'y.temp',
        );
      },
    );

    test('agregar y quitar una métrica del perfil', () {
      final profile = profiles.create(name: 'P');
      profiles.addMetric(
        profile.id,
        'tempInterior',
        MetricBinding(sourceField: 'x'),
      );
      expect(profiles.byId(profile.id)!.metricKeys, contains('tempInterior'));
      profiles.removeMetric(profile.id, 'tempInterior');
      expect(profiles.byId(profile.id)!.metricKeys, isEmpty);
      // Removing the metric drops its binding too (no dangling entry).
      expect(profiles.byId(profile.id)!.metricBindings, isEmpty);
    });

    test('agregar y quitar un indicator del perfil', () {
      final profile = profiles.create(name: 'P');
      profiles.addIndicator(
        profile.id,
        'heater',
        IndicatorBinding(sourceField: 'x'),
      );
      expect(profiles.byId(profile.id)!.indicatorKeys, contains('heater'));
      profiles.removeIndicator(profile.id, 'heater');
      expect(profiles.byId(profile.id)!.indicatorKeys, isEmpty);
      expect(profiles.byId(profile.id)!.indicatorBindings, isEmpty);
    });

    test('binding sourceField por perfil se persiste y es editable', () {
      final profile = profiles.create(name: 'P');
      profiles.addMetric(
        profile.id,
        'tempInterior',
        MetricBinding(sourceField: 'a.b'),
      );
      expect(
        profiles.byId(profile.id)!.metricBindings['tempInterior']!.sourceField,
        'a.b',
      );
      profiles.setMetricBinding(
        profile.id,
        'tempInterior',
        MetricBinding(sourceField: 'c.d'),
      );
      expect(
        profiles.byId(profile.id)!.metricBindings['tempInterior']!.sourceField,
        'c.d',
      );
    });

    test(
      'suggestedIndicatorsByMetric se persiste, y removerlo de indicatorKeys '
      'también lo saca de las sugerencias',
      () {
        final profile = profiles.create(name: 'P');
        profiles.addMetric(
          profile.id,
          'tempInterior',
          MetricBinding(sourceField: 'a'),
        );
        profiles.addIndicator(
          profile.id,
          'heater',
          IndicatorBinding(sourceField: 'b'),
        );
        profiles.setSuggestedIndicators(profile.id, 'tempInterior', ['heater']);
        expect(
          profiles
              .byId(profile.id)!
              .suggestedIndicatorsByMetric['tempInterior'],
          ['heater'],
        );
        profiles.removeIndicator(profile.id, 'heater');
        expect(
          profiles
              .byId(profile.id)!
              .suggestedIndicatorsByMetric['tempInterior'],
          isNot(contains('heater')),
        );
      },
    );
  });

  group('N6.5.2 §21 — caso crítico de aceptación (nivel modelo)', () {
    test('una sola tempInterior global; Perfil A resuelve heater+fan, Perfil B '
        'resuelve humidifier; nunca duplica la métrica global', () {
      final metrics = MetricLibraryStore();
      final indicators = IndicatorLibraryStore();
      final profiles = DeviceCapabilityProfileStore();

      metrics.upsert(_tempInterior());
      indicators.upsert(_indicator('heater', 'Calefacción'));
      indicators.upsert(_indicator('fan', 'Ventilador'));
      indicators.upsert(_indicator('humidifier', 'Humidificador'));

      final a = profiles.create(name: 'Sala A');
      profiles.addMetric(
        a.id,
        'tempInterior',
        MetricBinding(sourceField: 'salaA.temp'),
      );
      profiles.addIndicator(
        a.id,
        'heater',
        IndicatorBinding(sourceField: 'salaA.heater'),
      );
      profiles.addIndicator(
        a.id,
        'fan',
        IndicatorBinding(sourceField: 'salaA.fan'),
      );
      profiles.setSuggestedIndicators(a.id, 'tempInterior', ['heater']);

      final b = profiles.create(name: 'Sala B');
      profiles.addMetric(
        b.id,
        'tempInterior',
        MetricBinding(sourceField: 'salaB.temp'),
      );
      profiles.addIndicator(
        b.id,
        'humidifier',
        IndicatorBinding(sourceField: 'salaB.humidifier'),
      );

      // Exactly one global tempInterior, reused by both profiles.
      expect(
        metrics.metrics.where((m) => m.key == 'tempInterior'),
        hasLength(1),
      );

      final resolvedA = profiles.byId(a.id)!.resolve(metrics, indicators);
      final resolvedB = profiles.byId(b.id)!.resolve(metrics, indicators);

      // Board A can select heater + fan for tempInterior.
      expect(
        resolvedA.availableIndicators['tempInterior'],
        containsAll(['heater', 'fan']),
      );
      expect(
        resolvedA.availableIndicators['tempInterior'],
        isNot(contains('humidifier')),
      );

      // Board B can select humidifier, and heater is NOT available at all.
      expect(resolvedB.availableIndicators['tempInterior'], ['humidifier']);
      expect(
        resolvedB.availableIndicators['tempInterior'],
        isNot(contains('heater')),
      );

      // Suggestion is only on Perfil A, only for its own tempInterior binding.
      expect(profiles.byId(a.id)!.suggestedIndicatorsByMetric['tempInterior'], [
        'heater',
      ]);
      expect(
        profiles.byId(b.id)!.suggestedIndicatorsByMetric['tempInterior'],
        isNull,
      );
    });
  });

  group('N6.5.2 §16 — migración de seeds', () {
    test('Sala/Laboratorio/Arco siguen resolviendo con su contenido real', () {
      final env = sharedDeviceCapabilityProfileStore.byId(
        'environment_room_v1',
      )!;
      final lab = sharedDeviceCapabilityProfileStore.byId('laboratory_v1')!;
      final arch = sharedDeviceCapabilityProfileStore.byId(
        'disinfection_arch_v1',
      )!;

      final resolvedEnv = env.resolve(
        sharedMetricLibraryStore,
        sharedIndicatorLibraryStore,
      );
      final resolvedLab = lab.resolve(
        sharedMetricLibraryStore,
        sharedIndicatorLibraryStore,
      );
      final resolvedArch = arch.resolve(
        sharedMetricLibraryStore,
        sharedIndicatorLibraryStore,
      );

      expect(resolvedEnv.metrics, hasLength(13));
      expect(resolvedEnv.indicators, hasLength(3));
      expect(resolvedLab.metrics, hasLength(2));
      expect(resolvedArch.metrics, hasLength(3));

      // Behavior preserved exactly (N6.5's own regression coverage): the
      // Arco profile's metrics resolve with the real vehicle/disinfectant
      // keys, not the old hardcoded-fallback mismatch N6.5 fixed.
      expect(resolvedArch.metricByKey('vehiclesDisinfectedDaily'), isNotNull);
      expect(resolvedArch.metricByKey('vehiclesTotalDaily'), isNotNull);
      expect(resolvedArch.metricByKey('disinfectantLevel'), isNotNull);
    });

    test(
      'tempInterior/humedadInterior compartidas por environment_room_v1 y '
      'laboratory_v1 dejan de estar duplicadas: una sola definición global',
      () {
        expect(
          sharedMetricLibraryStore.metrics.where(
            (m) => m.key == 'tempInterior',
          ),
          hasLength(1),
        );
        expect(
          sharedMetricLibraryStore.metrics.where(
            (m) => m.key == 'humedadInterior',
          ),
          hasLength(1),
        );
        // But each profile's *binding* is independent — same sourceField
        // here because both real templates happened to use the same field
        // name, proving reuse without forcing bindings to match.
        final env = sharedDeviceCapabilityProfileStore.byId(
          'environment_room_v1',
        )!;
        final lab = sharedDeviceCapabilityProfileStore.byId('laboratory_v1')!;
        expect(env.metricBindings['tempInterior']!.sourceField, 'tempInterior');
        expect(lab.metricBindings['tempInterior']!.sourceField, 'tempInterior');
      },
    );

    test(
      'calefaccionEtapa1/2 y humidificacion siguen siendo una sola definición global',
      () {
        for (final key in [
          'calefaccionEtapa1',
          'calefaccionEtapa2',
          'humidificacion',
        ]) {
          expect(
            sharedIndicatorLibraryStore.indicators.where((i) => i.key == key),
            hasLength(1),
            reason: key,
          );
        }
      },
    );
  });
}
