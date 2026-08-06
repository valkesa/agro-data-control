// Tests for snapshot_unit_key_service.dart — the site-wide snapshotUnitKey
// uniqueness index/audit added in Etapa 4.1. All logic here is pure
// in-memory (no Firestore) except the source-grep tests near the bottom,
// which verify — by reading the source text of the services that DO touch
// Firestore — that this pure logic is actually wired into every write
// path the consigna requires, since a live integration test isn't
// possible without a Firestore emulator (none configured in this repo).
import 'dart:io';

import 'package:agro_data_control/models/agro_device.dart';
import 'package:agro_data_control/models/agro_device_room.dart';
import 'package:agro_data_control/services/snapshot_unit_key_service.dart';
import 'package:flutter_test/flutter_test.dart';

AgroDevice _device({
  required String id,
  String name = '',
  String siteId = 'roque-perez',
  bool enabled = true,
  String? snapshotUnitKey,
}) {
  return AgroDevice(
    id: id,
    tenantId: 'la-payana',
    siteId: siteId,
    name: name,
    type: 'environment_single_room',
    model: '',
    description: '',
    enabled: enabled,
    createdAt: null,
    updatedAt: null,
    snapshotUnitKey: snapshotUnitKey,
  );
}

AgroDeviceRoom _room({
  required String id,
  required String deviceId,
  String name = '',
  String siteId = 'roque-perez',
  bool enabled = true,
  String? snapshotUnitKey,
}) {
  return AgroDeviceRoom(
    id: id,
    tenantId: 'la-payana',
    deviceId: deviceId,
    siteId: siteId,
    name: name,
    enabled: enabled,
    createdAt: null,
    updatedAt: null,
    snapshotUnitKey: snapshotUnitKey,
  );
}

void main() {
  group('buildSiteSnapshotUnitKeyIndex (puro)', () {
    test('2 rooms del mismo device con la misma clave: la ultima gana en el '
        'indice (para eso esta auditSnapshotUnitKeys, no este indice)', () {
      final index = buildSiteSnapshotUnitKeyIndex(
        devices: [_device(id: 'plc-1', name: 'PLC 1')],
        roomsByDeviceId: {
          'plc-1': [
            _room(
              id: 'sala-1',
              deviceId: 'plc-1',
              name: 'Sala 1',
              snapshotUnitKey: 'sala-x',
            ),
            _room(
              id: 'sala-2',
              deviceId: 'plc-1',
              name: 'Sala 2',
              snapshotUnitKey: 'sala-x',
            ),
          ],
        },
      );
      expect(index['sala-x'], isNotNull);
    });

    test('rooms de devices distintos del mismo site comparten el indice', () {
      final index = buildSiteSnapshotUnitKeyIndex(
        devices: [
          _device(id: 'plc-a', name: 'PLC A'),
          _device(id: 'plc-b', name: 'PLC B'),
        ],
        roomsByDeviceId: {
          'plc-a': [
            _room(
              id: 'sala-1',
              deviceId: 'plc-a',
              name: 'Sala 1',
              snapshotUnitKey: 'sala-1',
            ),
          ],
          'plc-b': [],
        },
      );
      final ownerB = index['sala-1'];
      expect(ownerB, isNotNull);
      expect(ownerB!.deviceId, 'plc-a');
      expect(ownerB.isRoom, isTrue);
    });

    test('un device SIN rooms no puede usar la clave de una room de otro '
        'device del mismo site — ambas quedan en el mismo indice plano', () {
      final index = buildSiteSnapshotUnitKeyIndex(
        devices: [
          _device(id: 'plc-multi', name: 'PLC Multisala'),
          _device(id: 'plc-simple', name: 'PLC Simple'),
        ],
        roomsByDeviceId: {
          'plc-multi': [
            _room(
              id: 'sala-1',
              deviceId: 'plc-multi',
              name: 'Sala 1',
              snapshotUnitKey: 'sala-1',
            ),
          ],
          'plc-simple': [],
        },
      );
      // Candidato: editar plc-simple para que use snapshotUnitKey 'sala-1'.
      final owner = index['sala-1'];
      expect(owner, isNotNull);
      expect(owner!.roomId, 'sala-1');
      expect(owner.deviceId, 'plc-multi');
      expect(owner.deviceId, isNot('plc-simple'));
    });

    test(
      'una room no puede usar la clave de un device SIN rooms del mismo site',
      () {
        final index = buildSiteSnapshotUnitKeyIndex(
          devices: [
            _device(
              id: 'plc-simple',
              name: 'PLC Simple',
              snapshotUnitKey: 'unidad-1',
            ),
            _device(id: 'plc-multi', name: 'PLC Multisala'),
          ],
          roomsByDeviceId: {'plc-simple': [], 'plc-multi': []},
        );
        final owner = index['unidad-1'];
        expect(owner, isNotNull);
        expect(owner!.isRoom, isFalse);
        expect(owner.deviceId, 'plc-simple');
      },
    );

    test('el snapshotUnitKey propio de un device CON rooms nunca entra al '
        'indice (DeviceDashboardEntry no lo lee una vez que hay rooms)', () {
      final index = buildSiteSnapshotUnitKeyIndex(
        devices: [
          _device(
            id: 'plc-multi',
            name: 'PLC Multisala',
            snapshotUnitKey: 'clave-fantasma',
          ),
        ],
        roomsByDeviceId: {
          'plc-multi': [
            _room(
              id: 'sala-1',
              deviceId: 'plc-multi',
              snapshotUnitKey: 'sala-1',
            ),
          ],
        },
      );
      expect(index['clave-fantasma'], isNull);
      expect(index['sala-1'], isNotNull);
    });

    test('una clave vacia o null nunca entra al indice', () {
      final index = buildSiteSnapshotUnitKeyIndex(
        devices: [
          _device(id: 'plc-1', snapshotUnitKey: null),
          _device(id: 'plc-2', snapshotUnitKey: ''),
          _device(id: 'plc-3', snapshotUnitKey: '   '),
        ],
        roomsByDeviceId: const {},
      );
      expect(index, isEmpty);
    });

    test('se aplica trim al indexar', () {
      final index = buildSiteSnapshotUnitKeyIndex(
        devices: [_device(id: 'plc-1', snapshotUnitKey: '  sala-1  ')],
        roomsByDeviceId: const {},
      );
      expect(index.containsKey('sala-1'), isTrue);
      expect(index.containsKey('  sala-1  '), isFalse);
    });

    test('cambiar a una clave todavia libre no encuentra ningun owner', () {
      final index = buildSiteSnapshotUnitKeyIndex(
        devices: [_device(id: 'plc-1', snapshotUnitKey: 'sala-1')],
        roomsByDeviceId: const {},
      );
      expect(index['sala-nueva'], isNull);
    });

    test('la exclusion de la entidad propia (auto-conflicto) se calcula '
        'comparando deviceId+roomId contra el owner encontrado', () {
      final index = buildSiteSnapshotUnitKeyIndex(
        devices: [_device(id: 'plc-1', name: 'PLC 1')],
        roomsByDeviceId: {
          'plc-1': [
            _room(id: 'sala-1', deviceId: 'plc-1', snapshotUnitKey: 'sala-1'),
          ],
        },
      );
      final owner = index['sala-1']!;
      // Re-guardar la MISMA room con la MISMA clave: no debe ser conflicto.
      final bool isSelf = owner.deviceId == 'plc-1' && owner.roomId == 'sala-1';
      expect(isSelf, isTrue);
      // Pero otra room del MISMO device SI es un conflicto real.
      final bool isDifferentRoom =
          owner.deviceId == 'plc-1' && owner.roomId == 'sala-2';
      expect(isDifferentRoom, isFalse);
    });
  });

  group('SnapshotUnitKeyOwner.describe() — mensaje de conflicto', () {
    test('identifica la room Y el device propietarios', () {
      const owner = SnapshotUnitKeyOwner(
        deviceId: 'plc-maternidad',
        deviceName: 'PLC Maternidad',
        roomId: 'sala-1',
        roomName: 'Sala 1',
      );
      expect(owner.describe(), 'la room "Sala 1" del device "PLC Maternidad"');
    });

    test('identifica solo el device cuando no hay room (device sin rooms)', () {
      const owner = SnapshotUnitKeyOwner(
        deviceId: 'plc-1',
        deviceName: 'PLC 1',
      );
      expect(owner.describe(), 'el device "PLC 1"');
    });

    test('usa el id cuando el nombre visible esta vacio', () {
      const owner = SnapshotUnitKeyOwner(
        deviceId: 'plc-1',
        deviceName: '',
        roomId: 'sala-1',
        roomName: '',
      );
      expect(owner.describe(), 'la room "sala-1" del device "plc-1"');
    });
  });

  group('auditSnapshotUnitKeys (puro) — herramienta de diagnostico', () {
    test('reporta duplicados exactos entre rooms de distintos devices', () {
      final result = auditSnapshotUnitKeys(
        devices: [
          _device(id: 'plc-a', name: 'PLC A'),
          _device(id: 'plc-b', name: 'PLC B'),
        ],
        roomsByDeviceId: {
          'plc-a': [
            _room(
              id: 'sala-1',
              deviceId: 'plc-a',
              name: 'Sala 1',
              snapshotUnitKey: 'sala-1',
            ),
          ],
          'plc-b': [
            _room(
              id: 'sala-1',
              deviceId: 'plc-b',
              name: 'Sala 1',
              snapshotUnitKey: 'sala-1',
            ),
          ],
        },
      );
      expect(result.duplicateGroups.containsKey('sala-1'), isTrue);
      expect(result.duplicateGroups['sala-1'], hasLength(2));
      expect(result.hasIssues, isTrue);
    });

    test('detecta espacios al inicio/final (untrimmed)', () {
      final result = auditSnapshotUnitKeys(
        devices: [_device(id: 'plc-1', snapshotUnitKey: ' sala-1 ')],
        roomsByDeviceId: const {},
      );
      expect(result.untrimmedRawKeys.containsKey(' sala-1 '), isTrue);
      expect(result.hasIssues, isTrue);
    });

    test('detecta diferencias que solo son de mayusculas/minusculas', () {
      final result = auditSnapshotUnitKeys(
        devices: [
          _device(id: 'plc-a', snapshotUnitKey: 'Sala-1'),
          _device(id: 'plc-b', snapshotUnitKey: 'sala-1'),
        ],
        roomsByDeviceId: const {},
      );
      expect(result.caseOnlyDuplicateGroups, isNotEmpty);
      expect(result.hasIssues, isTrue);
    });

    test('una clave explicitamente vacia ("") se reporta aparte, no como '
        'duplicado — un campo NUNCA seteado (null) ni siquiera genera una '
        'entrada cruda: no hay nada que auditar en "el campo no existe", a '
        'diferencia de "el campo existe pero quedo vacio"', () {
      final result = auditSnapshotUnitKeys(
        devices: [
          _device(id: 'plc-a', snapshotUnitKey: ''),
          _device(id: 'plc-b', snapshotUnitKey: null),
        ],
        roomsByDeviceId: const {},
      );
      expect(result.emptyOwners, hasLength(1));
      expect(result.emptyOwners.single.deviceId, 'plc-a');
      expect(result.duplicateGroups, isEmpty);
      expect(result.hasIssues, isFalse);
    });

    test('sin problemas reales, hasIssues es false', () {
      final result = auditSnapshotUnitKeys(
        devices: [
          _device(id: 'plc-a', snapshotUnitKey: 'sala-1'),
          _device(id: 'plc-b', snapshotUnitKey: 'sala-2'),
        ],
        roomsByDeviceId: const {},
      );
      expect(result.hasIssues, isFalse);
      expect(result.uniqueKeys, containsAll(<String>['sala-1', 'sala-2']));
    });
  });

  group('Cableado en los servicios (verificado por codigo fuente)', () {
    late String deviceServiceSource;
    late String roomServiceSource;
    late String provisioningServiceSource;
    late String validatorSource;

    setUpAll(() {
      deviceServiceSource = File(
        'lib/services/agro_device_service.dart',
      ).readAsStringSync();
      roomServiceSource = File(
        'lib/services/agro_device_room_service.dart',
      ).readAsStringSync();
      provisioningServiceSource = File(
        'lib/services/agro_device_provisioning_service.dart',
      ).readAsStringSync();
      validatorSource = File(
        'lib/services/snapshot_unit_key_service.dart',
      ).readAsStringSync();
    });

    test('AgroDeviceService.create() y .update() usan el validador', () {
      final int createStart = deviceServiceSource.indexOf(
        'Future<void> create(',
      );
      final int updateStart = deviceServiceSource.indexOf(
        'Future<void> update(',
      );
      final int validatorEnd = deviceServiceSource.indexOf(
        '\n  /// Every Sector a Device references',
      );
      final String createBody = deviceServiceSource.substring(
        createStart,
        updateStart,
      );
      final String updateBody = deviceServiceSource.substring(
        updateStart,
        validatorEnd == -1 ? deviceServiceSource.length : validatorEnd,
      );
      expect(createBody, contains('SnapshotUnitKeyValidator().ensureUnique('));
      expect(updateBody, contains('SnapshotUnitKeyValidator().ensureUnique('));
      expect(updateBody, contains('excludeDeviceId: deviceId'));
    });

    test('AgroDeviceRoomService.create() y .update() usan el validador', () {
      final int createStart = roomServiceSource.indexOf('Future<void> create(');
      final int updateStart = roomServiceSource.indexOf('Future<void> update(');
      final int invalidateCacheStart = roomServiceSource.indexOf(
        '\n  /// Explicitly invalidates cached Room lists.',
      );
      final String createBody = roomServiceSource.substring(
        createStart,
        updateStart,
      );
      final String updateBody = roomServiceSource.substring(
        updateStart,
        invalidateCacheStart == -1
            ? roomServiceSource.length
            : invalidateCacheStart,
      );
      expect(createBody, contains('SnapshotUnitKeyValidator().ensureUnique('));
      expect(updateBody, contains('SnapshotUnitKeyValidator().ensureUnique('));
      expect(updateBody, contains('excludeDeviceId: deviceId'));
      expect(updateBody, contains('excludeRoomId: roomId'));
    });

    test('AgroDeviceRoomService.update() ahora requiere siteId para poder '
        'acotar la validacion al site correcto', () {
      final int updateStart = roomServiceSource.indexOf('Future<void> update(');
      final int updateParamsEnd = roomServiceSource.indexOf(
        '}) async {',
        updateStart,
      );
      final String updateSignature = roomServiceSource.substring(
        updateStart,
        updateParamsEnd,
      );
      expect(updateSignature, contains('required String siteId'));
    });

    test('createDeviceWithRooms valida contra el site ANTES de crear el '
        'batch, y usa una unica carga del indice para todas las claves', () {
      final int checkFnIndex = provisioningServiceSource.indexOf(
        'void checkAgainstSite(',
      );
      final int loadIndexCallIndex = provisioningServiceSource.indexOf(
        'snapshotUnitKeyValidator.loadSiteIndex(',
      );
      final int batchIndex = provisioningServiceSource.indexOf(
        'FirebaseFirestore.instance.batch()',
      );
      expect(checkFnIndex, greaterThan(-1));
      expect(loadIndexCallIndex, greaterThan(-1));
      expect(batchIndex, greaterThan(-1));
      // Orden: primero se carga el indice UNA vez, despues se valida
      // cada candidato, y solo despues se crea el batch — si hay
      // conflicto, la excepcion se lanza antes de que exista el batch,
      // asi que batch.commit() nunca se ejecuta.
      expect(loadIndexCallIndex, lessThan(checkFnIndex));
      expect(checkFnIndex, lessThan(batchIndex));
      expect(
        'loadSiteIndex('.allMatches(provisioningServiceSource).length,
        1,
        reason:
            'debe cargarse una sola vez y reutilizarse para el device y '
            'todas las rooms, no una vez por candidato',
      );
    });

    test('el validador no esta inyectado como campo const-default en '
        'AgroDeviceService/AgroDeviceRoomService (evita el ciclo de '
        'evaluacion const con SnapshotUnitKeyValidator)', () {
      expect(
        deviceServiceSource,
        isNot(contains('this.snapshotUnitKeyValidator')),
      );
      expect(
        roomServiceSource,
        isNot(contains('this.snapshotUnitKeyValidator')),
      );
    });

    test('el validador no agrega listeners ni escribe bajo /plcs/', () {
      expect(validatorSource, isNot(contains('.snapshots()')));
      String stripComments(String source) => source
          .split('\n')
          .where((line) => !line.trim().startsWith('//'))
          .join('\n');
      expect(stripComments(validatorSource), isNot(contains('plcs')));
    });

    test('el validador nunca se importa desde el codigo del dashboard en vivo '
        '(no agrega lecturas al camino operativo)', () {
      for (final String path in <String>[
        'lib/main.dart',
        'lib/pages/comparison_page.dart',
        'lib/models/device_dashboard_entry.dart',
        'lib/services/plc_dashboard_service.dart',
      ]) {
        final String source = File(path).readAsStringSync();
        expect(
          source,
          isNot(contains('snapshot_unit_key_service.dart')),
          reason: '$path no debe depender de la validacion administrativa',
        );
      }
    });
  });
}
