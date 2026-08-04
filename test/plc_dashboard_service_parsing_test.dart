// Tests for PlcDashboardService's dynamic snapshot parser (Etapa 3 of the
// "Devices dinámicos" migration — see
// no_git/informes_de_codigo/informe_diseno_devices_dinamicos_multitenant_2026-08-04.html).
//
// `_parseSnapshot` used to make exactly 2 hardcoded calls keyed to the
// literal strings 'munters1'/'munters2'. It now discovers unit keys
// dynamically from whatever the backend's JSON actually contains, so these
// tests cover 0/1/N units plus an exact reproduction of the real backend's
// payload shape (see backend/lib/src/snapshot_runtime.dart's
// `_buildSnapshotPayload` and backend/bin/plc_snapshot_server.dart's
// `/api/snapshot` handler) to prove the legacy client keeps working
// byte-for-byte.
//
// `_parseSnapshot` is private and there's no injectable HTTP client on this
// service, so tests go through `parseSnapshotForTesting` (a thin
// `@visibleForTesting` wrapper) with a JSON `Map` built in-memory — no
// network call, no Firestore.
import 'package:agro_data_control/models/dashboard_snapshot.dart';
import 'package:agro_data_control/models/munters_model.dart';
import 'package:agro_data_control/services/plc_dashboard_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('0 unidades', () {
    test('un payload con solo metadata no produce ninguna unidad, sin excepcion', () {
      const PlcDashboardService service = PlcDashboardService();
      final DashboardSnapshot snapshot = service.parseSnapshotForTesting(
        <String, dynamic>{
          'backendName': 'agrodata-vps',
          'backendOnline': true,
          'lastUpdatedAt': '2026-08-04T12:00:00Z',
          'clientName': 'The Gene Pig',
          'siteName': 'Genetica 1',
          'refreshInProgress': false,
          'status': <String, dynamic>{'backendOnline': true},
          'doorEvents': <String, dynamic>{},
          'presence': <String, dynamic>{'count': 1},
          'operationalEvents': <dynamic>[
            <String, dynamic>{'type': 'door_opened'},
          ],
        },
      );

      expect(snapshot.units, isEmpty);
      expect(snapshot.unitsByKey, isEmpty);
      expect(snapshot.backendOnline, isTrue);
      expect(snapshot.clientName, 'The Gene Pig');
    });
  });

  group('1 unidad', () {
    test('un solo device dinamico (key arbitraria, no munters1/2)', () {
      const PlcDashboardService service = PlcDashboardService();
      final DashboardSnapshot snapshot = service.parseSnapshotForTesting(
        <String, dynamic>{
          'backendName': 'agrodata-vps',
          'backendOnline': true,
          'lastUpdatedAt': '2026-08-04T12:00:00Z',
          'clientName': 'La Payana',
          'status': <String, dynamic>{},
          'doorEvents': <String, dynamic>{},
          'plc-maternidad-cerdos': <String, dynamic>{
            'configured': true,
            'plcReachable': true,
            'estadoEquipo': 'RUN',
            'tempInterior': 221,
            'fanQ5': true,
          },
        },
      );

      expect(snapshot.units, hasLength(1));
      final MuntersModel unit = snapshot.units.single;
      expect(unit.historyPlcId, 'plc-maternidad-cerdos');
      // No Firestore-configured display name was passed via plcNames, so it
      // falls back to the key itself (new-schema devices have no special
      // literal fallback the way munters1/munters2 do).
      expect(unit.name, 'plc-maternidad-cerdos');
      expect(unit.estadoEquipo, 'RUN');
      expect(unit.fanQ5, isTrue);
      expect(unit.tempInterior, 221.0);
      expect(snapshot.unitsByKey['plc-maternidad-cerdos'], same(unit));
    });

    test('plcNames sobreescribe el nombre por defecto', () {
      const PlcDashboardService service = PlcDashboardService(
        plcNames: <String, String>{
          'plc-maternidad-cerdos': 'PLC Maternidad',
        },
      );
      final DashboardSnapshot snapshot = service.parseSnapshotForTesting(
        <String, dynamic>{
          'status': <String, dynamic>{},
          'doorEvents': <String, dynamic>{},
          'plc-maternidad-cerdos': <String, dynamic>{'estadoEquipo': 'RUN'},
        },
      );

      expect(snapshot.units.single.name, 'PLC Maternidad');
    });
  });

  group('N unidades (3+)', () {
    test('3 devices con keys arbitrarias, todas presentes y en orden', () {
      const PlcDashboardService service = PlcDashboardService();
      final DashboardSnapshot snapshot = service.parseSnapshotForTesting(
        <String, dynamic>{
          'status': <String, dynamic>{},
          'doorEvents': <String, dynamic>{},
          'munters1': <String, dynamic>{'estadoEquipo': 'RUN'},
          'plc-maternidad-cerdos': <String, dynamic>{'estadoEquipo': 'STOP'},
          's7-gestacion': <String, dynamic>{'estadoEquipo': 'RUN'},
        },
      );

      expect(snapshot.units, hasLength(3));
      expect(
        snapshot.units.map((u) => u.historyPlcId).toList(),
        <String>['munters1', 'plc-maternidad-cerdos', 's7-gestacion'],
      );
      expect(snapshot.unitsByKey.keys.toSet(), <String>{
        'munters1',
        'plc-maternidad-cerdos',
        's7-gestacion',
      });
    });
  });

  group('Compatibilidad total con PLC1/PLC2 legacy', () {
    // Shape confirmed by reading backend/lib/src/snapshot_runtime.dart's
    // _buildSnapshotPayload (the single function every snapshot state funnels
    // through) plus the /api/snapshot handler in
    // backend/bin/plc_snapshot_server.dart, which merges in `presence` and
    // (conditionally) `operationalEvents` on top of it.
    Map<String, dynamic> realBackendShapedPayload() {
      return <String, dynamic>{
        'backendName': 'agrodata-vps',
        'backendOnline': true,
        'lastUpdatedAt': '2026-08-04T12:00:00Z',
        'clientName': 'The Gene Pig',
        'siteName': 'Genetica 1',
        'refreshInProgress': false,
        'status': <String, dynamic>{
          'backendName': 'agrodata-vps',
          'backendOnline': true,
          'lastUpdatedAt': '2026-08-04T12:00:00Z',
          'clientName': 'The Gene Pig',
          'siteName': 'Genetica 1',
          'lastError': null,
          'startedAt': '2026-08-04T08:00:00Z',
          'lastPollDurationMs': 120,
          'consecutiveFailures': 0,
          'refreshInProgress': false,
          'hasFreshSnapshot': true,
        },
        'doorEvents': <String, dynamic>{},
        'presence': <String, dynamic>{'count': 2},
        'operationalEvents': <dynamic>[],
        'munters1': <String, dynamic>{
          'configured': true,
          'plcReachable': true,
          'dataFresh': true,
          'estadoEquipo': 'RUN',
          'tempInterior': 221,
          'humInterior': 600,
          'fanQ5': true,
          'fanQ6': false,
          'alarmaGeneral': false,
        },
        'munters2': <String, dynamic>{
          'configured': true,
          'plcReachable': true,
          'dataFresh': true,
          'estadoEquipo': 'RUN',
          'tempInterior': 199,
          'humInterior': 780,
          'fanQ5': true,
          'fanQ6': true,
          'alarmaGeneral': true,
        },
      };
    }

    test('produce exactamente 2 unidades, munters1 y munters2, en ese orden', () {
      const PlcDashboardService service = PlcDashboardService();
      final DashboardSnapshot snapshot = service.parseSnapshotForTesting(
        realBackendShapedPayload(),
      );

      expect(snapshot.units, hasLength(2));
      expect(
        snapshot.units.map((u) => u.historyPlcId).toList(),
        <String>['munters1', 'munters2'],
      );
    });

    test('nombres caen al fallback literal legacy cuando no hay plcNames', () {
      const PlcDashboardService service = PlcDashboardService();
      final DashboardSnapshot snapshot = service.parseSnapshotForTesting(
        realBackendShapedPayload(),
      );

      expect(snapshot.units[0].name, 'Munters 1');
      expect(snapshot.units[1].name, 'Munters 2');
    });

    test('plcNames de Firestore sigue pisando el fallback, como antes', () {
      const PlcDashboardService service = PlcDashboardService(
        plcNames: <String, String>{'munters1': 'Sala 1', 'munters2': 'Sala 2'},
      );
      final DashboardSnapshot snapshot = service.parseSnapshotForTesting(
        realBackendShapedPayload(),
      );

      expect(snapshot.units[0].name, 'Sala 1');
      expect(snapshot.units[1].name, 'Sala 2');
    });

    test('los campos de cada unidad se parsean igual que antes', () {
      const PlcDashboardService service = PlcDashboardService();
      final DashboardSnapshot snapshot = service.parseSnapshotForTesting(
        realBackendShapedPayload(),
      );

      final MuntersModel munters1 = snapshot.unitsByKey['munters1']!;
      final MuntersModel munters2 = snapshot.unitsByKey['munters2']!;

      expect(munters1.estadoEquipo, 'RUN');
      expect(munters1.tempInterior, 221.0);
      expect(munters1.humInterior, 600.0);
      expect(munters1.fanQ5, isTrue);
      expect(munters1.fanQ6, isFalse);
      expect(munters1.alarmaGeneral, isFalse);
      expect(munters1.backendOnline, isTrue);

      expect(munters2.estadoEquipo, 'RUN');
      expect(munters2.tempInterior, 199.0);
      expect(munters2.humInterior, 780.0);
      expect(munters2.fanQ6, isTrue);
      expect(munters2.alarmaGeneral, isTrue);
    });

    test('status/doorEvents/presence/operationalEvents nunca se confunden con unidades', () {
      const PlcDashboardService service = PlcDashboardService();
      final DashboardSnapshot snapshot = service.parseSnapshotForTesting(
        realBackendShapedPayload(),
      );

      final Set<String?> historyPlcIds = snapshot.units
          .map((u) => u.historyPlcId)
          .toSet();
      expect(historyPlcIds, <String>{'munters1', 'munters2'});
      expect(historyPlcIds, isNot(contains('status')));
      expect(historyPlcIds, isNot(contains('doorEvents')));
      expect(historyPlcIds, isNot(contains('presence')));
      expect(historyPlcIds, isNot(contains('operationalEvents')));
    });

    test('metadata de nivel superior (clientName/backendOnline/startedAt) se parsea igual', () {
      const PlcDashboardService service = PlcDashboardService();
      final DashboardSnapshot snapshot = service.parseSnapshotForTesting(
        realBackendShapedPayload(),
      );

      expect(snapshot.clientName, 'The Gene Pig');
      expect(snapshot.backendOnline, isTrue);
      expect(snapshot.startedAt, DateTime.parse('2026-08-04T08:00:00Z').toLocal());
      expect(snapshot.lastUpdatedAt, DateTime.parse('2026-08-04T12:00:00Z').toLocal());
    });
  });
}
