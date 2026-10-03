import 'dart:io';

import 'package:agro_data_control/demo/demo.dart';
import 'package:agro_data_control/models/dashboard_door_event.dart';
import 'package:agro_data_control/models/dashboard_snapshot.dart';
import 'package:agro_data_control/models/munters_model.dart';
import 'package:flutter_test/flutter_test.dart';

MuntersModel _unit(String key, {double temperature = 24}) => MuntersModel(
  name: key,
  historyClientId: 'client',
  historyPlcId: key,
  backendOnline: true,
  configured: true,
  plcReachable: true,
  plcRunning: true,
  dataFresh: true,
  plcOnline: true,
  tempInterior: temperature,
  tempIngresoSala: 22,
  humInterior: 60,
  tempExterior: 18,
  humExterior: 70,
  nh3: 8,
  presionDiferencial: 20,
  tensionSalidaVentiladores: 450,
  fanQ5: true,
  fanQ6: false,
  fanQ7: null,
  fanQ8: null,
  fanQ9: null,
  fanQ10: null,
  bombaHumidificador: false,
  resistencia1: false,
  resistencia2: false,
  alarmaGeneral: false,
  fallaRed: false,
  nivelAguaAlarma: false,
  fallaTermicaBomba: false,
  eventosSinAgua: 1,
  horasMunter: 2,
  horasFiltroF9: 3,
  horasFiltroG4: 4,
  horasPolifosfato: 5,
  salaAbierta: false,
  aperturasSala: 6,
  munterAbierto: false,
  aperturasMunter: 7,
  cantidadApagadas: 8,
  estadoEquipo: 'RUN',
);

DashboardSnapshot _snapshot() => DashboardSnapshot(
  units: <MuntersModel>[_unit('plc-a'), _unit('plc-b', temperature: 25)],
  doorEvents: const <String, DashboardDoorEvent>{
    'sala': DashboardDoorEvent(
      doorId: 'sala',
      isOpen: false,
      currentOpenedAt: null,
      lastChangedAt: null,
      lastOpeningId: null,
    ),
  },
  backendOnline: true,
  lastUpdatedAt: DateTime(2026, 10, 2, 10),
  startedAt: DateTime(2026, 10, 2, 9),
  clientName: 'test',
);

void main() {
  group('aislamiento arquitectónico', () {
    test(
      'lib/demo sólo importa modelos de snapshot permitidos o archivos demo',
      () {
        final files = Directory('lib/demo').listSync().whereType<File>().where(
          (file) => file.path.endsWith('.dart'),
        );
        expect(files, isNotEmpty);

        final dependencyPattern = RegExp(
          r"^(?:import|export)\s+'([^']+)'",
          multiLine: true,
        );
        const allowedModelImports = <String>{
          '../models/dashboard_snapshot.dart',
          '../models/munters_model.dart',
        };
        for (final file in files) {
          final source = file.readAsStringSync();
          for (final match in dependencyPattern.allMatches(source)) {
            final target = match.group(1)!;
            expect(
              target.startsWith('demo_') ||
                  allowedModelImports.contains(target),
              isTrue,
              reason: '${file.path} must not depend on $target',
            );
          }
          expect(source, isNot(contains('FirebaseFirestore')));
          expect(source, isNot(contains('package:http')));
          expect(source, isNot(contains('Timer(')));
          expect(source, isNot(contains('Timer.periodic')));
        }
      },
    );

    test('gate exige simultáneamente build habilitado y rol owner', () {
      expect(DemoAccessGate.canAccess(role: 'owner'), isFalse);
      expect(
        DemoAccessGate.canAccess(role: 'admin', buildEnabled: true),
        isFalse,
      );
      expect(
        DemoAccessGate.canAccess(role: 'owner', buildEnabled: true),
        isTrue,
      );
    });
  });

  group('allowlist y validación', () {
    test(
      'catálogo coincide con el alcance aprobado y no contiene paths libres',
      () {
        expect(
          DemoSignalCatalog.definitions
              .map((definition) => definition.key.wireName)
              .toSet(),
          <String>{
            'tempInterior',
            'tempExterior',
            'tempIngresoSala',
            'humInterior',
            'humExterior',
            'presionDiferencial',
            'nh3',
            'tensionSalidaVentiladores',
            'resistencia1',
            'resistencia2',
            'bombaHumidificador',
            'fanQ5',
            'fanQ6',
            'fanQ7',
            'fanQ8',
            'fanQ9',
            'fanQ10',
            'salaAbierta',
            'munterAbierto',
            'alarmaGeneral',
            'fallaRed',
            'nivelAguaAlarma',
            'fallaTermicaBomba',
            'configured',
            'backendOnline',
            'plcReachable',
            'plcRunning',
            'dataFresh',
            'plcOnline',
            'estadoEquipo',
          },
        );
      },
    );

    test('rechaza signalKey desconocida y señales excluidas', () {
      expect(
        () => DemoSignalCatalog.parseKey('ruta.arbitraria'),
        throwsArgumentError,
      );
      expect(() => DemoSignalCatalog.parseKey('co2'), throwsArgumentError);
      expect(
        () => DemoSignalCatalog.parseKey('aguaLitrosDia'),
        throwsArgumentError,
      );
      expect(
        () => DemoSignalCatalog.parseKey('resistencia3'),
        throwsArgumentError,
      );
      expect(
        () => DemoSignalCatalog.parseKey('computed.dewPointDelta'),
        throwsArgumentError,
      );
    });

    test('valida tipos, finitud y rangos numéricos', () {
      final humidity = DemoSignalCatalog.definitionFor(
        DemoSignalKey.indoorHumidity,
      );
      expect(() => humidity.validateValue(85), returnsNormally);
      expect(() => humidity.validateValue(null), returnsNormally);
      expect(() => humidity.validateValue(-1), throwsArgumentError);
      expect(() => humidity.validateValue(101), throwsArgumentError);
      expect(() => humidity.validateValue('85'), throwsArgumentError);
      expect(() => humidity.validateValue(double.nan), throwsArgumentError);

      final heating = DemoSignalCatalog.definitionFor(
        DemoSignalKey.heatingStage1,
      );
      expect(() => heating.validateValue(true), returnsNormally);
      expect(() => heating.validateValue(1), throwsArgumentError);
    });

    test('linear sólo acepta una señal numérica, dos extremos y duración', () {
      expect(
        () => DemoEvent(
          id: 'humidity-rise',
          targetSnapshotUnitKey: 'plc-a',
          signalKey: DemoSignalKey.indoorHumidity,
          startTime: const Duration(seconds: 5),
          duration: const Duration(seconds: 10),
          fromValue: 60,
          toValue: 95,
          transition: DemoTransition.linear,
        ),
        returnsNormally,
      );
      expect(
        () => DemoEvent(
          id: 'bad-linear',
          targetSnapshotUnitKey: 'plc-a',
          signalKey: DemoSignalKey.heatingStage1,
          startTime: Duration.zero,
          duration: const Duration(seconds: 1),
          fromValue: false,
          toValue: true,
          transition: DemoTransition.linear,
        ),
        throwsArgumentError,
      );
    });

    test('deserialización también cruza la allowlist', () {
      expect(
        () => DemoEvent.fromMap(<String, Object?>{
          'id': 'unknown',
          'targetSnapshotUnitKey': 'plc-a',
          'signalKey': 'pending.co2',
          'startTimeMs': 0,
          'durationMs': 0,
          'toValue': 500,
          'transition': 'instant',
        }),
        throwsArgumentError,
      );
    });

    test('escenario exige IDs únicos y eventos dentro de duración', () {
      final event = DemoEvent(
        id: 'door',
        targetSnapshotUnitKey: 'plc-a',
        signalKey: DemoSignalKey.roomDoorOpen,
        startTime: const Duration(seconds: 5),
        duration: const Duration(seconds: 2),
        toValue: true,
      );
      expect(
        () => DemoScenario(
          id: 'valid',
          name: 'Validación',
          duration: const Duration(seconds: 10),
          events: <DemoEvent>[event],
        ),
        returnsNormally,
      );
      expect(
        () => DemoScenario(
          id: 'duplicates',
          name: 'Duplicados',
          duration: const Duration(seconds: 10),
          events: <DemoEvent>[event, event],
        ),
        throwsArgumentError,
      );
      expect(
        () => DemoScenario(
          id: 'short',
          name: 'Corto',
          duration: const Duration(seconds: 6),
          events: <DemoEvent>[event],
        ),
        throwsArgumentError,
      );
    });
  });

  group('DemoSnapshotBuilder', () {
    test('copia segura, aplica sólo al snapshotUnitKey y no muta el real', () {
      final real = _snapshot();
      final demo = DemoSnapshotBuilder.applyOverrides(
        realSnapshot: real,
        targetSnapshotUnitKey: 'plc-b',
        overrides: <DemoSignalKey, Object?>{
          DemoSignalKey.indoorTemperature: 17.5,
          DemoSignalKey.heatingStage1: true,
          DemoSignalKey.roomDoorOpen: true,
        },
      );

      expect(demo, isNot(same(real)));
      expect(demo.units, isNot(same(real.units)));
      expect(demo.units[0], isNot(same(real.units[0])));
      expect(demo.units[1], isNot(same(real.units[1])));
      expect(demo.units[0].tempInterior, 24);
      expect(demo.units[1].tempInterior, 17.5);
      expect(demo.units[1].resistencia1, isTrue);
      expect(demo.units[1].salaAbierta, isTrue);
      expect(real.units[1].tempInterior, 25);
      expect(real.units[1].resistencia1, isFalse);
      expect(real.units[1].salaAbierta, isFalse);
      expect(demo.doorEvents, equals(real.doorEvents));
      expect(() => demo.units.add(_unit('x')), throwsUnsupportedError);
      expect(
        () => demo.doorEvents['x'] = const DashboardDoorEvent(
          doorId: 'x',
          isOpen: false,
          currentOpenedAt: null,
          lastChangedAt: null,
          lastOpeningId: null,
        ),
        throwsUnsupportedError,
      );
    });

    test('null explícito permite representar Sin datos', () {
      final real = _snapshot();
      final demo = DemoSnapshotBuilder.applyOverrides(
        realSnapshot: real,
        targetSnapshotUnitKey: 'plc-a',
        overrides: const <DemoSignalKey, Object?>{
          DemoSignalKey.indoorTemperature: null,
          DemoSignalKey.plcOnline: null,
          DemoSignalKey.equipmentState: null,
        },
      );
      expect(demo.units.first.tempInterior, isNull);
      expect(demo.units.first.plcOnline, isNull);
      expect(demo.units.first.estadoEquipo, isNull);
    });

    test('rechaza scopes ausentes o ambiguos', () {
      final real = _snapshot();
      expect(
        () => DemoSnapshotBuilder.applyOverrides(
          realSnapshot: real,
          targetSnapshotUnitKey: 'missing',
          overrides: const <DemoSignalKey, Object?>{},
        ),
        throwsStateError,
      );
      final ambiguous = DashboardSnapshot(
        units: <MuntersModel>[_unit('same'), _unit('same')],
        doorEvents: const <String, DashboardDoorEvent>{},
        backendOnline: true,
        lastUpdatedAt: null,
        startedAt: null,
      );
      expect(
        () => DemoSnapshotBuilder.applyOverrides(
          realSnapshot: ambiguous,
          targetSnapshotUnitKey: 'same',
          overrides: const <DemoSignalKey, Object?>{},
        ),
        throwsStateError,
      );
    });

    test(
      'un override inválido falla antes de construir y no causa efectos',
      () {
        final real = _snapshot();
        expect(
          () => DemoSnapshotBuilder.applyOverrides(
            realSnapshot: real,
            targetSnapshotUnitKey: 'plc-a',
            overrides: const <DemoSignalKey, Object?>{
              DemoSignalKey.indoorHumidity: 150,
            },
          ),
          throwsArgumentError,
        );
        expect(real.units.first.humInterior, 60);
        expect(real.units.length, 2);
      },
    );
  });
}
