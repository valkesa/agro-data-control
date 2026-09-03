// Etapa 6A — fallback matrix + single-subscription/cache tests for
// DeviceTemplateRegistry. No fake_cloud_firestore/mocking package exists in
// this repo (see pubspec.yaml) — the established pattern (e.g.
// _FakeCerdasRepository in test/environment_overview_templates_test.dart)
// is a subclass that overrides the repository's public methods. Every test
// resets the process-wide singleton in tearDown so nothing leaks between
// tests in this file.
import 'dart:async';

import 'package:agro_data_control/services/device_template_repository.dart';
import 'package:agro_data_control/ui_templates/ui_templates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    DeviceTemplateRegistry.instance.reset();
  });

  DeviceTemplateRecord remoteRoomClimate({
    bool enabled = true,
    int schemaVersion = 1,
  }) {
    final DeviceTemplate local = getTemplateById('room_climate')!;
    return DeviceTemplateRecord(
      template: DeviceTemplate(
        id: local.id,
        name: '${local.name} (remoto)',
        boardPreset: local.boardPreset,
        metrics: local.metrics,
        indicators: local.indicators,
        boardSlots: local.boardSlots,
        tableSection: local.tableSection,
        tableColumns: local.tableColumns,
      ),
      schemaVersion: schemaVersion,
      templateVersion: 2,
      enabled: enabled,
    );
  }

  group('DeviceTemplateRegistry fallback matrix', () {
    test('remote válido -> remote', () async {
      final _FakeDeviceTemplateRepository fake = _FakeDeviceTemplateRepository(
        <DeviceTemplateRecord>[remoteRoomClimate()],
      );

      DeviceTemplateRegistry.instance.start(repository: fake);
      await fake.emit();

      final DeviceTemplate? resolved = DeviceTemplateRegistry.instance.resolve(
        'room_climate',
      );
      expect(resolved, isNotNull);
      expect(resolved!.name, 'Sala / Ambiente controlado (remoto)');
    });

    test('remote ausente -> local (nunca se llamó start)', () {
      // Sin start(): el mapa remoto siempre está vacío.
      expect(DeviceTemplateRegistry.instance.resolve('room_climate'), isNull);
    });

    test('remote existe pero no incluye este id -> local', () async {
      final _FakeDeviceTemplateRepository fake = _FakeDeviceTemplateRepository(
        <DeviceTemplateRecord>[], // colección vacía / sin ese doc
      );

      DeviceTemplateRegistry.instance.start(repository: fake);
      await fake.emit();

      expect(DeviceTemplateRegistry.instance.resolve('room_climate'), isNull);
    });

    test(
      'remote inválido (fromMap devuelve null en el repo) -> local',
      () async {
        // Simula lo que hace DeviceTemplateRepository ante un doc inválido:
        // se descarta antes de llegar al registry.
        final _FakeDeviceTemplateRepository fake =
            _FakeDeviceTemplateRepository(<DeviceTemplateRecord>[]);

        DeviceTemplateRegistry.instance.start(repository: fake);
        await fake.emit();

        expect(DeviceTemplateRegistry.instance.resolve('room_climate'), isNull);
      },
    );

    test('remote enabled:false -> local', () async {
      final _FakeDeviceTemplateRepository fake = _FakeDeviceTemplateRepository(
        <DeviceTemplateRecord>[remoteRoomClimate(enabled: false)],
      );

      DeviceTemplateRegistry.instance.start(repository: fake);
      await fake.emit();

      expect(DeviceTemplateRegistry.instance.resolve('room_climate'), isNull);
    });

    test(
      'remote con schemaVersion incompatible (ya descartado en el record) -> local',
      () async {
        // DeviceTemplateRecord.fromMap ya devuelve null en este caso — el
        // repositorio real jamás lo agrega a la lista que llega al
        // registry. El fake reproduce ese contrato: una colección sin el
        // template incompatible.
        final _FakeDeviceTemplateRepository fake =
            _FakeDeviceTemplateRepository(<DeviceTemplateRecord>[]);

        DeviceTemplateRegistry.instance.start(repository: fake);
        await fake.emit();

        expect(DeviceTemplateRegistry.instance.resolve('room_climate'), isNull);
      },
    );

    test('ni remote ni local -> null', () {
      expect(
        DeviceTemplateRegistry.instance.resolve('template_que_no_existe'),
        isNull,
      );
    });

    test(
      'resolver de más alto nivel cae a local cuando el registry no tiene nada',
      () {
        const DeviceTemplateResolver resolver = DeviceTemplateResolver();
        final DeviceTemplate? resolved = resolver.templateForId('room_climate');
        expect(resolved, isNotNull);
        expect(
          resolved!.name,
          'Sala / Ambiente controlado',
        ); // el local, sin "(remoto)"
      },
    );

    test(
      'resolver de más alto nivel usa remote cuando el registry lo tiene',
      () async {
        final _FakeDeviceTemplateRepository fake =
            _FakeDeviceTemplateRepository(<DeviceTemplateRecord>[
              remoteRoomClimate(),
            ]);
        DeviceTemplateRegistry.instance.start(repository: fake);
        await fake.emit();

        const DeviceTemplateResolver resolver = DeviceTemplateResolver();
        final DeviceTemplate? resolved = resolver.templateForId('room_climate');
        expect(resolved!.name, 'Sala / Ambiente controlado (remoto)');
      },
    );
  });

  group('DeviceTemplateRegistry cache / single read', () {
    test(
      'pedir el mismo template varias veces no genera lecturas remotas repetidas',
      () async {
        final _FakeDeviceTemplateRepository fake =
            _FakeDeviceTemplateRepository(<DeviceTemplateRecord>[
              remoteRoomClimate(),
            ]);

        DeviceTemplateRegistry.instance.start(repository: fake);
        await fake.emit();

        for (int i = 0; i < 20; i++) {
          DeviceTemplateRegistry.instance.resolve('room_climate');
        }

        // watchTemplates() se invoca una sola vez al hacer start(), sin
        // importar cuántas veces se llame resolve() después — es un lookup
        // sincrónico contra el mapa cacheado, no una lectura nueva.
        expect(fake.watchCallCount, 1);
      },
    );

    test('start() repetido no apila listeners (idempotente)', () async {
      final _FakeDeviceTemplateRepository fakeA = _FakeDeviceTemplateRepository(
        <DeviceTemplateRecord>[remoteRoomClimate()],
      );
      final _FakeDeviceTemplateRepository fakeB = _FakeDeviceTemplateRepository(
        <DeviceTemplateRecord>[remoteRoomClimate(enabled: false)],
      );

      DeviceTemplateRegistry.instance.start(repository: fakeA);
      await fakeA.emit();
      expect(
        DeviceTemplateRegistry.instance.resolve('room_climate'),
        isNotNull,
      );

      // Simula logout->login: start() de nuevo con otro repository.
      DeviceTemplateRegistry.instance.start(repository: fakeB);
      await fakeB.emit();

      // Si el primer listener siguiera vivo, una emisión tardía de fakeA
      // podría pisar el estado — acá solo confirmamos que el segundo
      // start() controla el estado final.
      expect(DeviceTemplateRegistry.instance.resolve('room_climate'), isNull);
    });

    test(
      'error de Firestore antes del primer snapshot deja fallback local',
      () async {
        final _FakeDeviceTemplateRepository fake =
            _FakeDeviceTemplateRepository(<DeviceTemplateRecord>[]);

        DeviceTemplateRegistry.instance.start(repository: fake);
        await fake.emitError(StateError('permission-denied'));

        expect(DeviceTemplateRegistry.instance.resolve('room_climate'), isNull);
        const DeviceTemplateResolver resolver = DeviceTemplateResolver();
        expect(
          resolver.templateForId('room_climate')!.name,
          'Sala / Ambiente controlado',
        );
      },
    );

    test(
      'error de Firestore después de un snapshot conserva el último cache válido',
      () async {
        final _FakeDeviceTemplateRepository fake =
            _FakeDeviceTemplateRepository(<DeviceTemplateRecord>[
              remoteRoomClimate(),
            ]);

        DeviceTemplateRegistry.instance.start(repository: fake);
        await fake.emit();
        await fake.emitError(StateError('unavailable'));

        final DeviceTemplate? resolved = DeviceTemplateRegistry.instance
            .resolve('room_climate');
        expect(resolved, isNotNull);
        expect(resolved!.name, 'Sala / Ambiente controlado (remoto)');
      },
    );
  });
}

class _FakeDeviceTemplateRepository extends DeviceTemplateRepository {
  _FakeDeviceTemplateRepository(this._records);

  final List<DeviceTemplateRecord> _records;
  int watchCallCount = 0;
  final StreamController<List<DeviceTemplateRecord>> _controller =
      StreamController<List<DeviceTemplateRecord>>.broadcast();

  @override
  Stream<List<DeviceTemplateRecord>> watchTemplates() {
    watchCallCount += 1;
    return _controller.stream;
  }

  /// Pushes the fixture records and waits a microtask so the registry's
  /// `.listen` callback has run before assertions.
  Future<void> emit() async {
    _controller.add(_records);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> emitError(Object error) async {
    _controller.addError(error, StackTrace.current);
    await Future<void>.delayed(Duration.zero);
  }
}
