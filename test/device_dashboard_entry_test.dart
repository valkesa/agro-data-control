// Tests for DeviceDashboardEntry — the Device⇄snapshot join used by
// Tablero/Tabla for dynamic-Devices Sites (Etapas 4-5 of the "Devices
// dinámicos" migration). Pure in-memory objects only: no Firestore, no
// HTTP, no widget pumping needed for this file.
import 'package:agro_data_control/models/agro_device.dart';
import 'package:agro_data_control/models/agro_device_room.dart';
import 'package:agro_data_control/models/dashboard_door_event.dart';
import 'package:agro_data_control/models/dashboard_snapshot.dart';
import 'package:agro_data_control/models/device_dashboard_entry.dart';
import 'package:agro_data_control/models/munters_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AgroDevice device({
    required String id,
    required String name,
    int sortOrder = 0,
    String? snapshotUnitKey,
    bool enabled = true,
  }) {
    return AgroDevice(
      id: id,
      tenantId: 'la-payana',
      siteId: 'roque-perez',
      name: name,
      type: AgroDeviceType.s7,
      model: '',
      description: '',
      enabled: enabled,
      createdAt: null,
      updatedAt: null,
      sortOrder: sortOrder,
      snapshotUnitKey: snapshotUnitKey,
    );
  }

  MuntersModel liveUnit({required String historyPlcId, String? estadoEquipo}) {
    return MuntersModel(
      name: historyPlcId,
      historyPlcId: historyPlcId,
      tempInterior: null,
      tempIngresoSala: null,
      humInterior: null,
      tempExterior: null,
      humExterior: null,
      fanQ5: null,
      fanQ6: null,
      fanQ7: null,
      fanQ8: null,
      fanQ9: null,
      fanQ10: null,
      bombaHumidificador: null,
      resistencia1: null,
      resistencia2: null,
      alarmaGeneral: null,
      fallaRed: null,
      nivelAguaAlarma: null,
      fallaTermicaBomba: null,
      eventosSinAgua: null,
      horasMunter: null,
      horasFiltroF9: null,
      horasFiltroG4: null,
      horasPolifosfato: null,
      salaAbierta: null,
      aperturasSala: null,
      munterAbierto: null,
      aperturasMunter: null,
      cantidadApagadas: null,
      estadoEquipo: estadoEquipo,
    );
  }

  DashboardSnapshot snapshotWithUnits(List<MuntersModel> units) {
    return DashboardSnapshot(
      units: units,
      doorEvents: const <String, DashboardDoorEvent>{},
      backendOnline: true,
      lastUpdatedAt: null,
      startedAt: null,
    );
  }

  group('0 Devices', () {
    test('sin devices habilitados devuelve lista vacia, no fabrica entradas', () {
      final List<DeviceDashboardEntry> entries = DeviceDashboardEntry.listFrom(
        devices: const <AgroDevice>[],
        snapshot: snapshotWithUnits(const <MuntersModel>[]),
      );

      expect(entries, isEmpty);
    });
  });

  group('1 Device', () {
    test('con telemetria: liveUnit presente, hasTelemetry true, displayUnit es el real', () {
      final AgroDevice d = device(id: 'plc-maternidad-cerdos', name: 'PLC Maternidad');
      final MuntersModel unit = liveUnit(
        historyPlcId: 'plc-maternidad-cerdos',
        estadoEquipo: 'RUN',
      );
      final List<DeviceDashboardEntry> entries = DeviceDashboardEntry.listFrom(
        devices: [d],
        snapshot: snapshotWithUnits([unit]),
      );

      expect(entries, hasLength(1));
      expect(entries.single.hasTelemetry, isTrue);
      expect(entries.single.liveUnit, same(unit));
      expect(entries.single.displayUnit, same(unit));
      expect(entries.single.displayName, 'PLC Maternidad');
    });

    test('sin telemetria: liveUnit null, displayUnit es un placeholder con el nombre real', () {
      final AgroDevice d = device(id: 'plc-maternidad-cerdos', name: 'PLC Maternidad');
      final List<DeviceDashboardEntry> entries = DeviceDashboardEntry.listFrom(
        devices: [d],
        snapshot: snapshotWithUnits(const <MuntersModel>[]),
      );

      expect(entries, hasLength(1));
      expect(entries.single.hasTelemetry, isFalse);
      expect(entries.single.liveUnit, isNull);
      // Nunca "Munters 1"/"Munters 2" ni ningun fallback legacy — el
      // nombre real del Device, con todos los campos de telemetria null.
      expect(entries.single.displayUnit.name, 'PLC Maternidad');
      expect(entries.single.displayUnit.tempInterior, isNull);
      expect(entries.single.displayUnit.estadoEquipo, isNull);
    });
  });

  group('N Devices (3)', () {
    test('3 devices, mezcla de con/sin telemetria, todos presentes', () {
      final List<AgroDevice> devices = [
        device(id: 'a', name: 'Sala A', sortOrder: 0),
        device(id: 'b', name: 'Sala B', sortOrder: 1),
        device(id: 'c', name: 'Sala C', sortOrder: 2),
      ];
      final List<DeviceDashboardEntry> entries = DeviceDashboardEntry.listFrom(
        devices: devices,
        snapshot: snapshotWithUnits([
          liveUnit(historyPlcId: 'a', estadoEquipo: 'RUN'),
          liveUnit(historyPlcId: 'c', estadoEquipo: 'STOP'),
        ]),
      );

      expect(entries, hasLength(3));
      expect(entries[0].hasTelemetry, isTrue);
      expect(entries[1].hasTelemetry, isFalse);
      expect(entries[2].hasTelemetry, isTrue);
    });
  });

  group('Orden', () {
    test('listFrom preserva el orden de entrada (ya viene ordenado por sortOrder aguas arriba)', () {
      final List<AgroDevice> devices = [
        device(id: 'z', name: 'Z-last', sortOrder: 2),
        device(id: 'a', name: 'A-first', sortOrder: 0),
        device(id: 'm', name: 'M-middle', sortOrder: 1),
      ];
      final List<DeviceDashboardEntry> entries = DeviceDashboardEntry.listFrom(
        devices: devices,
        snapshot: snapshotWithUnits(const <MuntersModel>[]),
      );

      expect(
        entries.map((e) => e.device.id).toList(),
        <String>['z', 'a', 'm'],
        reason:
            'listFrom no reordena — el orden real por sortOrder lo aplica '
            'AgroDeviceService.listBySite antes de llegar aca (Etapa 2).',
      );
    });
  });

  group('snapshotUnitKey distinto de deviceId', () {
    test('el join usa effectiveSnapshotUnitKey, no el id del documento', () {
      final AgroDevice d = device(
        id: 'device-doc-id',
        name: 'S7 Gestacion',
        snapshotUnitKey: 'unit_gestacion_01',
      );
      final MuntersModel unit = liveUnit(historyPlcId: 'unit_gestacion_01');
      final List<DeviceDashboardEntry> entries = DeviceDashboardEntry.listFrom(
        devices: [d],
        snapshot: snapshotWithUnits([unit]),
      );

      expect(d.effectiveSnapshotUnitKey, 'unit_gestacion_01');
      expect(entries.single.liveUnit, same(unit));
    });
  });

  group('Unidad huerfana', () {
    test('una unidad del snapshot sin Device asociado se ignora, no crea card fantasma', () {
      final AgroDevice d = device(id: 'known-device', name: 'Conocido');
      final List<DeviceDashboardEntry> entries = DeviceDashboardEntry.listFrom(
        devices: [d],
        snapshot: snapshotWithUnits([
          liveUnit(historyPlcId: 'known-device'),
          liveUnit(historyPlcId: 'orphan-unit-nobody-registered'),
        ]),
      );

      expect(entries, hasLength(1));
      expect(entries.single.device.id, 'known-device');
    });
  });

  group('Device deshabilitado', () {
    test('un device enabled=false nunca aparece en el resultado', () {
      final List<AgroDevice> devices = [
        device(id: 'active', name: 'Activo'),
        device(id: 'off', name: 'Deshabilitado', enabled: false),
      ];
      final List<DeviceDashboardEntry> entries = DeviceDashboardEntry.listFrom(
        devices: devices,
        snapshot: snapshotWithUnits([
          liveUnit(historyPlcId: 'active'),
          liveUnit(historyPlcId: 'off'),
        ]),
      );

      expect(entries, hasLength(1));
      expect(entries.single.device.id, 'active');
    });
  });

  group('N Rooms per Device', () {
    AgroDeviceRoom room({
      required String id,
      required String deviceId,
      required String name,
      int sortOrder = 0,
      String? snapshotUnitKey,
      bool enabled = true,
    }) {
      return AgroDeviceRoom(
        id: id,
        tenantId: 'la-payana',
        deviceId: deviceId,
        siteId: 'roque-perez',
        name: name,
        enabled: enabled,
        createdAt: null,
        updatedAt: null,
        sortOrder: sortOrder,
        snapshotUnitKey: snapshotUnitKey,
      );
    }

    test('0 rooms: comportamiento identico al 1:1 original (regresion)', () {
      final AgroDevice d = device(id: 'plc-maternidad', name: 'PLC Maternidad');
      final List<DeviceDashboardEntry> entries = DeviceDashboardEntry.listFrom(
        devices: [d],
        snapshot: snapshotWithUnits(const <MuntersModel>[]),
        roomsByDeviceId: const <String, List<AgroDeviceRoom>>{},
      );

      expect(entries, hasLength(1));
      expect(entries.single.displayName, 'PLC Maternidad');
      expect(entries.single.hasTelemetry, isFalse);
    });

    test(
      '8 salas de un mismo Device fisico (caso La Payana), con telemetria mixta',
      () {
        final AgroDevice plcMaternidad = device(
          id: 'plc-maternidad',
          name: 'PLC Maternidad',
        );
        final List<AgroDeviceRoom> salas = [
          for (int i = 1; i <= 8; i++)
            room(
              id: 'sala-$i',
              deviceId: 'plc-maternidad',
              name: 'Sala $i',
              sortOrder: i,
              snapshotUnitKey: 'plc-maternidad__sala-$i',
            ),
        ];
        final List<DeviceDashboardEntry> entries = DeviceDashboardEntry.listFrom(
          devices: [plcMaternidad],
          snapshot: snapshotWithUnits([
            // Solo sala-3 tiene telemetria; el resto debe salir "Sin datos".
            liveUnit(historyPlcId: 'plc-maternidad__sala-3'),
          ]),
          roomsByDeviceId: {'plc-maternidad': salas},
        );

        expect(entries, hasLength(8));
        expect(
          entries.map((e) => e.displayName).toList(),
          <String>[for (int i = 1; i <= 8; i++) 'Sala $i'],
        );
        for (final DeviceDashboardEntry entry in entries) {
          expect(entry.device.id, 'plc-maternidad');
        }
        expect(entries[2].hasTelemetry, isTrue);
        expect(entries[2].displayName, 'Sala 3');
        final List<DeviceDashboardEntry> withoutData = [...entries]
          ..removeAt(2);
        for (final DeviceDashboardEntry entry in withoutData) {
          expect(entry.hasTelemetry, isFalse);
          expect(entry.displayUnit.tempInterior, isNull);
          expect(entry.displayUnit.humInterior, isNull);
          // Nunca "Munters 1/2" ni el nombre del Device — el nombre real de
          // cada sala, incluso sin datos.
          expect(entry.displayUnit.name, entry.roomName);
        }
      },
    );

    test('salas deshabilitadas se excluyen, no aparecen en el resultado', () {
      final AgroDevice d = device(id: 'plc-maternidad', name: 'PLC Maternidad');
      final List<DeviceDashboardEntry> entries = DeviceDashboardEntry.listFrom(
        devices: [d],
        snapshot: snapshotWithUnits(const <MuntersModel>[]),
        roomsByDeviceId: {
          'plc-maternidad': [
            room(id: 'sala-1', deviceId: 'plc-maternidad', name: 'Sala 1', sortOrder: 0),
            room(
              id: 'sala-2',
              deviceId: 'plc-maternidad',
              name: 'Sala 2',
              sortOrder: 1,
              enabled: false,
            ),
          ],
        },
      );

      expect(entries, hasLength(1));
      expect(entries.single.displayName, 'Sala 1');
    });

    test(
      'todas las salas de un Device deshabilitadas: 0 entradas, NO cae al 1:1 implicito',
      () {
        final AgroDevice d = device(id: 'plc-maternidad', name: 'PLC Maternidad');
        final List<DeviceDashboardEntry> entries = DeviceDashboardEntry.listFrom(
          devices: [d],
          snapshot: snapshotWithUnits(const <MuntersModel>[]),
          roomsByDeviceId: {
            'plc-maternidad': [
              room(
                id: 'sala-1',
                deviceId: 'plc-maternidad',
                name: 'Sala 1',
                enabled: false,
              ),
            ],
          },
        );

        expect(entries, isEmpty);
      },
    );

    test('orden: por sortOrder de Device, luego por sortOrder de Room', () {
      final List<AgroDevice> devices = [
        device(id: 'plc-maternidad', name: 'PLC Maternidad', sortOrder: 0),
        device(id: 'plc-recria', name: 'PLC Recria', sortOrder: 1),
      ];
      final List<DeviceDashboardEntry> entries = DeviceDashboardEntry.listFrom(
        devices: devices,
        snapshot: snapshotWithUnits(const <MuntersModel>[]),
        roomsByDeviceId: {
          'plc-maternidad': [
            room(id: 's2', deviceId: 'plc-maternidad', name: 'Sala 2', sortOrder: 1),
            room(id: 's1', deviceId: 'plc-maternidad', name: 'Sala 1', sortOrder: 0),
          ],
          // plc-recria tiene 0 rooms -> 1 entrada implicita con su propio nombre.
        },
      );

      expect(
        entries.map((e) => e.displayName).toList(),
        <String>['Sala 1', 'Sala 2', 'PLC Recria'],
      );
    });
  });

  group('Sin contaminacion entre contextos (cambio de tenant/site)', () {
    test('dos llamadas sucesivas con distintos devices/snapshot no se mezclan', () {
      final List<DeviceDashboardEntry> siteAEntries = DeviceDashboardEntry.listFrom(
        devices: [device(id: 'a1', name: 'Site A Device 1')],
        snapshot: snapshotWithUnits([liveUnit(historyPlcId: 'a1')]),
      );
      final List<DeviceDashboardEntry> siteBEntries = DeviceDashboardEntry.listFrom(
        devices: [
          device(id: 'b1', name: 'Site B Device 1'),
          device(id: 'b2', name: 'Site B Device 2'),
        ],
        snapshot: snapshotWithUnits([liveUnit(historyPlcId: 'b1')]),
      );

      expect(siteAEntries, hasLength(1));
      expect(siteAEntries.single.device.id, 'a1');
      expect(siteBEntries, hasLength(2));
      expect(
        siteBEntries.map((e) => e.device.id).toList(),
        <String>['b1', 'b2'],
      );
      // siteAEntries must stay exactly as it was — listFrom keeps no
      // shared/static state that a later call could mutate.
      expect(siteAEntries, hasLength(1));
      expect(siteAEntries.single.device.id, 'a1');
    });
  });
}
