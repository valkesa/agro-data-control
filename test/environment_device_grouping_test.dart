// Widget tests for grouping Salas by their physical Device — Tablero
// (EnvironmentOverviewPage) and Tabla (EnvironmentTablePage). Rules, as
// specified for La Payana's "PLC Maternidad" (1 Device -> 8 Salas):
//
// Tablero:
//   - up to 3 Salas total (across the whole page): single column, stacked.
//   - 1-3 Salas: single column.
//   - 4-6 Salas: two columns, filled top-to-bottom.
//   - 7+ Salas: up to three columns when the viewport fits complete cards.
//   - Salas are additionally grouped under a titled header per Device;
//     groups stack vertically, each using its own mini-grid in the same
//     column mode.
//
// Tabla: grouped by Device too, but simpler — a title row above each
// Device's Sala rows, no column layout involved.
//
// `deviceNames` is null for legacy PLC1/PLC2 (no Device concept there) —
// covered by the "sin deviceNames" cases below, which must render exactly
// as before this feature existed (no group titles).
import 'package:agro_data_control/models/dashboard_range_settings.dart';
import 'package:agro_data_control/models/munters_model.dart';
import 'package:agro_data_control/models/plc_unit_diagnostics.dart';
import 'package:agro_data_control/pages/comparison_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EnvironmentOverviewPage (Tablero)', () {
    testWidgets('hasta 3 salas totales: columna unica (mismo x, y creciente)', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnvironmentOverviewPage(
              units: <MuntersModel>[
                _sala('Sala 1'),
                _sala('Sala 2'),
                _sala('Sala 3'),
              ],
              labels: const <String>['Sala 1', 'Sala 2', 'Sala 3'],
              plcIds: const <String?>[null, null, null],
              deviceNames: const <String>['PLC A', 'PLC A', 'PLC A'],
              tenantId: null,
              siteId: null,
              rangeSettings: const DashboardRangeSettings.defaults(),
              showSnapshotPulse: false,
              snapshotStale: false,
            ),
          ),
        ),
      );
      await tester.pump();

      final Offset p1 = tester.getTopLeft(find.text('Sala 1').first);
      final Offset p2 = tester.getTopLeft(find.text('Sala 2').first);
      final Offset p3 = tester.getTopLeft(find.text('Sala 3').first);

      expect(
        p1.dx,
        p2.dx,
        reason: 'sala2 debe quedar debajo de sala1, misma columna',
      );
      expect(
        p2.dx,
        p3.dx,
        reason: 'sala3 debe quedar debajo de sala2, misma columna',
      );
      expect(p2.dy, greaterThan(p1.dy));
      expect(p3.dy, greaterThan(p2.dy));
    });

    testWidgets('dos cards quedan en una columna aunque haya ancho', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnvironmentOverviewPage(
              units: <MuntersModel>[_sala('Sala 1'), _sala('Sala 2')],
              labels: const <String>['Sala 1', 'Sala 2'],
              plcIds: const <String?>[null, null],
              deviceNames: const <String>['PLC A', 'PLC A'],
              templateIds: const <String?>['room_climate', 'room_climate'],
              tenantId: null,
              siteId: null,
              rangeSettings: const DashboardRangeSettings.defaults(),
              showSnapshotPulse: false,
              snapshotStale: false,
            ),
          ),
        ),
      );
      await tester.pump();

      final Offset p1 = tester.getTopLeft(find.text('Sala 1').first);
      final Offset p2 = tester.getTopLeft(find.text('Sala 2').first);

      expect(p1.dx, p2.dx);
      expect(p2.dy, greaterThan(p1.dy));
      expect(tester.takeException(), isNull);
    });

    testWidgets('cerca del breakpoint: cambia a una columna sin overlap', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(720, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnvironmentOverviewPage(
              units: <MuntersModel>[_sala('Sala 1'), _sala('Sala 2')],
              labels: const <String>['Sala 1', 'Sala 2'],
              plcIds: const <String?>[null, null],
              deviceNames: const <String>['PLC A', 'PLC A'],
              templateIds: const <String?>['room_climate', 'room_climate'],
              tenantId: null,
              siteId: null,
              rangeSettings: const DashboardRangeSettings.defaults(),
              showSnapshotPulse: false,
              snapshotStale: false,
            ),
          ),
        ),
      );
      await tester.pump();

      final Offset p1 = tester.getTopLeft(find.text('Sala 1').first);
      final Offset p2 = tester.getTopLeft(find.text('Sala 2').first);

      expect(p1.dx, p2.dx);
      expect(p2.dy, greaterThan(p1.dy));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '4 salas: 2 columnas x 2 filas, llenadas de arriba hacia abajo',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EnvironmentOverviewPage(
                units: <MuntersModel>[
                  _sala('Sala 1'),
                  _sala('Sala 2'),
                  _sala('Sala 3'),
                  _sala('Sala 4'),
                ],
                labels: const <String>['Sala 1', 'Sala 2', 'Sala 3', 'Sala 4'],
                plcIds: const <String?>[null, null, null, null],
                deviceNames: const <String>['PLC A', 'PLC A', 'PLC A', 'PLC A'],
                tenantId: null,
                siteId: null,
                rangeSettings: const DashboardRangeSettings.defaults(),
                showSnapshotPulse: false,
                snapshotStale: false,
              ),
            ),
          ),
        );
        await tester.pump();

        final Offset p1 = tester.getTopLeft(
          find.byKey(const Key('environment-overview-card-0')),
        );
        final Offset p2 = tester.getTopLeft(
          find.byKey(const Key('environment-overview-card-1')),
        );
        final Offset p3 = tester.getTopLeft(
          find.byKey(const Key('environment-overview-card-2')),
        );
        final Offset p4 = tester.getTopLeft(
          find.byKey(const Key('environment-overview-card-3')),
        );

        expect(p2.dx, p1.dx);
        expect(p2.dy, greaterThan(p1.dy));
        expect(p3.dx, greaterThan(p1.dx));
        expect(p3.dy, p1.dy);
        expect(p4.dx, p3.dx);
        expect(p4.dy, p2.dy);
      },
    );

    testWidgets('5 salas: columnas 3 + 2', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnvironmentOverviewPage(
              units: <MuntersModel>[
                for (int i = 1; i <= 5; i++) _sala('Sala $i'),
              ],
              labels: <String>[for (int i = 1; i <= 5; i++) 'Sala $i'],
              plcIds: const <String?>[null, null, null, null, null],
              deviceNames: const <String>[
                'PLC A',
                'PLC A',
                'PLC A',
                'PLC A',
                'PLC A',
              ],
              templateIds: const <String?>[
                'room_climate',
                'room_climate',
                'room_climate',
                'room_climate',
                'room_climate',
              ],
              tenantId: null,
              siteId: null,
              rangeSettings: const DashboardRangeSettings.defaults(),
              showSnapshotPulse: false,
              snapshotStale: false,
            ),
          ),
        ),
      );
      await tester.pump();

      final Offset p1 = tester.getTopLeft(find.text('Sala 1').first);
      final Offset p3 = tester.getTopLeft(find.text('Sala 3').first);
      final Offset p4 = tester.getTopLeft(find.text('Sala 4').first);
      final Offset p5 = tester.getTopLeft(find.text('Sala 5').first);

      expect(p3.dx, p1.dx);
      expect(p3.dy, greaterThan(p1.dy));
      expect(p4.dx, greaterThan(p1.dx));
      expect(p4.dy, p1.dy);
      expect(p5.dx, p4.dx);
      expect(p5.dy, greaterThan(p4.dy));
    });

    testWidgets('9 salas: 3 columnas x 3 filas si el viewport alcanza', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1320, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnvironmentOverviewPage(
              units: <MuntersModel>[
                for (int i = 1; i <= 9; i++) _sala('Sala $i'),
              ],
              labels: <String>[for (int i = 1; i <= 9; i++) 'Sala $i'],
              plcIds: const <String?>[
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
              ],
              deviceNames: const <String>[
                'PLC A',
                'PLC A',
                'PLC A',
                'PLC A',
                'PLC A',
                'PLC A',
                'PLC A',
                'PLC A',
                'PLC A',
              ],
              templateIds: const <String?>[
                'room_climate',
                'room_climate',
                'room_climate',
                'room_climate',
                'room_climate',
                'room_climate',
                'room_climate',
                'room_climate',
                'room_climate',
              ],
              tenantId: null,
              siteId: null,
              rangeSettings: const DashboardRangeSettings.defaults(),
              showSnapshotPulse: false,
              snapshotStale: false,
            ),
          ),
        ),
      );
      await tester.pump();

      final Offset p1 = tester.getTopLeft(find.text('Sala 1').first);
      final Offset p4 = tester.getTopLeft(find.text('Sala 4').first);
      final Offset p7 = tester.getTopLeft(find.text('Sala 7').first);
      final Offset p9 = tester.getTopLeft(find.text('Sala 9').first);

      expect(p4.dx, greaterThan(p1.dx));
      expect(p4.dy, p1.dy);
      expect(p7.dx, greaterThan(p4.dx));
      expect(p7.dy, p1.dy);
      expect(p9.dx, p7.dx);
      expect(p9.dy, greaterThan(p7.dy));
    });

    testWidgets(
      'agrupacion por device es independiente del layout de columnas: '
      'device1 con 3 salas (2 col) + device2 con 1 sala debajo, con titulos',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EnvironmentOverviewPage(
                units: <MuntersModel>[
                  _sala('Sala 1'),
                  _sala('Sala 2'),
                  _sala('Sala 3'),
                  _sala('Sala 4'),
                ],
                labels: const <String>['Sala 1', 'Sala 2', 'Sala 3', 'Sala 4'],
                plcIds: const <String?>[null, null, null, null],
                deviceNames: const <String>[
                  'PLC Maternidad',
                  'PLC Maternidad',
                  'PLC Maternidad',
                  'PLC Recria',
                ],
                tenantId: null,
                siteId: null,
                rangeSettings: const DashboardRangeSettings.defaults(),
                showSnapshotPulse: false,
                snapshotStale: false,
              ),
            ),
          ),
        );
        await tester.pump();

        // Titulos de grupo, uno por Device.
        expect(find.text('PLC Maternidad'), findsOneWidget);
        expect(find.text('PLC Recria'), findsOneWidget);

        final Offset p1 = tester.getTopLeft(find.text('Sala 1').first);
        final Offset p3 = tester.getTopLeft(find.text('Sala 3').first);
        final Offset p4 = tester.getTopLeft(find.text('Sala 4').first);
        final Offset recriaTitle = tester.getTopLeft(find.text('PLC Recria'));

        expect(p4.dx, p1.dx);
        // El grupo de Device 2 aparece completo debajo del grupo de Device 1.
        expect(recriaTitle.dy, greaterThan(p3.dy));
        expect(p4.dy, greaterThan(p3.dy));
      },
    );

    testWidgets('sin deviceNames (legacy): no se muestran titulos de grupo', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnvironmentOverviewPage(
              units: <MuntersModel>[_sala('Munters 1'), _sala('Munters 2')],
              labels: const <String>['Munters 1', 'Munters 2'],
              plcIds: const <String?>['munters1', 'munters2'],
              tenantId: null,
              siteId: null,
              rangeSettings: const DashboardRangeSettings.defaults(),
              showSnapshotPulse: false,
              snapshotStale: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('environment-device-group-Munters 1')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('environment-device-group-Munters 2')),
        findsNothing,
      );
    });

    testWidgets('muestra cartel con tipo de mantenimiento en la card', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnvironmentOverviewPage(
              units: <MuntersModel>[_maintenanceSala('Sala 1')],
              labels: const <String>['Sala 1'],
              plcIds: const <String?>[null],
              deviceNames: const <String>['PLC A'],
              tenantId: null,
              siteId: null,
              rangeSettings: const DashboardRangeSettings.defaults(),
              showSnapshotPulse: false,
              snapshotStale: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Tareas de Mantenimiento: Sistemas'), findsOneWidget);
    });

    testWidgets(
      'un device de una sola sala cuyo nombre coincide con el de la sala '
      '(sin Rooms) no repite el titulo del grupo',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EnvironmentOverviewPage(
                units: <MuntersModel>[_sala('Sala1')],
                labels: const <String>['Sala1'],
                plcIds: const <String?>[null],
                deviceNames: const <String>['Sala1'],
                tenantId: null,
                siteId: null,
                rangeSettings: const DashboardRangeSettings.defaults(),
                showSnapshotPulse: false,
                snapshotStale: false,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.byKey(const Key('environment-device-group-Sala1')),
          findsNothing,
        );
        expect(find.text('Sala1'), findsWidgets);
      },
    );

    testWidgets(
      'regresion: 3+ devices con nombres distintos, cada uno su propio '
      'grupo de 1 sala (forma real de Las Heras) — no debe tirar '
      '"Duplicate keys found"',
      (WidgetTester tester) async {
        // Antes del fix, la key del Row de cada grupo solo dependia de
        // (cantidad de cards, columnas) — 3 grupos independientes de 1
        // card cada uno generaban la MISMA key
        // ('environment-overview-card-columns-1-1'), sin importar que
        // fueran devices distintos. Reproduce el crash real reportado en
        // producción para el tenant the-gene-pig / site las-heras.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EnvironmentOverviewPage(
                units: <MuntersModel>[
                  _sala('Sala1'),
                  _sala('Sala2'),
                  _sala('Laboratorio'),
                ],
                labels: const <String>['Sala1', 'Sala2', 'Laboratorio'],
                plcIds: const <String?>[null, null, null],
                deviceNames: const <String>['Sala1', 'Sala2', 'Laboratorio'],
                tenantId: 'the-gene-pig',
                siteId: 'las-heras',
                rangeSettings: const DashboardRangeSettings.defaults(),
                showSnapshotPulse: false,
                snapshotStale: false,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Sala1'), findsWidgets);
        expect(find.text('Sala2'), findsWidgets);
        expect(find.text('Laboratorio'), findsWidgets);
      },
    );
  });

  group('EnvironmentTablePage (Tabla)', () {
    testWidgets('agrupa filas por device, con un titulo por grupo', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnvironmentTablePage(
              units: <MuntersModel>[
                _sala('Sala 1'),
                _sala('Sala 2'),
                _sala('Sala 3'),
              ],
              labels: const <String>['Sala 1', 'Sala 2', 'Sala 3'],
              plcIds: const <String?>[null, null, null],
              deviceNames: const <String>[
                'PLC Maternidad',
                'PLC Maternidad',
                'PLC Recria',
              ],
              tenantId: null,
              siteId: null,
              rangeSettings: const DashboardRangeSettings.defaults(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('PLC Maternidad'), findsOneWidget);
      expect(find.text('PLC Recria'), findsOneWidget);
      expect(find.text('Sala 1'), findsOneWidget);
      expect(find.text('Sala 2'), findsOneWidget);
      expect(find.text('Sala 3'), findsOneWidget);

      // El titulo de "PLC Maternidad" queda arriba de sus 2 salas, y el de
      // "PLC Recria" arriba de la suya, siguiendo el orden de entrada.
      final double maternidadTitleY = tester
          .getTopLeft(find.text('PLC Maternidad'))
          .dy;
      final double sala1Y = tester.getTopLeft(find.text('Sala 1').first).dy;
      final double sala3Y = tester.getTopLeft(find.text('Sala 3').first).dy;
      final double recriaTitleY = tester.getTopLeft(find.text('PLC Recria')).dy;

      expect(sala1Y, greaterThan(maternidadTitleY));
      expect(recriaTitleY, greaterThan(sala1Y));
      expect(sala3Y, greaterThan(recriaTitleY));
    });

    testWidgets('sin deviceNames (legacy): sin titulos de grupo', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnvironmentTablePage(
              units: <MuntersModel>[_sala('Munters 1'), _sala('Munters 2')],
              labels: const <String>['Munters 1', 'Munters 2'],
              plcIds: const <String?>['munters1', 'munters2'],
              tenantId: null,
              siteId: null,
              rangeSettings: const DashboardRangeSettings.defaults(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.memory), findsNothing);
    });

    testWidgets('muestra tipo de mantenimiento en la fila', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnvironmentTablePage(
              units: <MuntersModel>[_maintenanceSala('Sala 1')],
              labels: const <String>['Sala 1'],
              plcIds: const <String?>[null],
              deviceNames: const <String>['PLC A'],
              tenantId: null,
              siteId: null,
              rangeSettings: const DashboardRangeSettings.defaults(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Tareas de Mantenimiento: Sistemas'), findsOneWidget);
    });

    testWidgets(
      'un device de una sola sala cuyo nombre coincide con el de la sala '
      '(sin Rooms) no repite el titulo del grupo',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EnvironmentTablePage(
                units: <MuntersModel>[_sala('Sala1')],
                labels: const <String>['Sala1'],
                plcIds: const <String?>[null],
                deviceNames: const <String>['Sala1'],
                tenantId: null,
                siteId: null,
                rangeSettings: const DashboardRangeSettings.defaults(),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byIcon(Icons.memory), findsNothing);
        expect(find.text('Sala1'), findsOneWidget);
      },
    );

    testWidgets(
      'en una mezcla, solo se omite el titulo del grupo redundante — el '
      'grupo multi-sala sigue mostrando el suyo',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EnvironmentTablePage(
                units: <MuntersModel>[
                  _sala('Sala1'),
                  _sala('Sala 1'),
                  _sala('Sala 2'),
                ],
                labels: const <String>['Sala1', 'Sala 1', 'Sala 2'],
                plcIds: const <String?>[null, null, null],
                deviceNames: const <String>[
                  'Sala1',
                  'PLC Maternidad',
                  'PLC Maternidad',
                ],
                tenantId: null,
                siteId: null,
                rangeSettings: const DashboardRangeSettings.defaults(),
              ),
            ),
          ),
        );
        await tester.pump();

        // Solo 1 icono de grupo: el de "PLC Maternidad". El grupo "Sala1"
        // (una sola sala, mismo nombre) no dibuja su propio titulo.
        expect(find.byIcon(Icons.memory), findsOneWidget);
        expect(find.text('PLC Maternidad'), findsOneWidget);
        expect(find.text('Sala1'), findsOneWidget);
      },
    );
  });
}

MuntersModel _sala(String name) {
  return MuntersModel(
    name: name,
    tempInterior: 22.1,
    tempIngresoSala: null,
    humInterior: 60,
    tempExterior: 18,
    humExterior: 70,
    tensionSalidaVentiladores: 400,
    bombaHumidificador: true,
    fanQ5: false,
    fanQ6: false,
    fanQ7: false,
    fanQ8: false,
    fanQ9: false,
    fanQ10: false,
    resistencia1: false,
    resistencia2: false,
    alarmaGeneral: false,
    fallaRed: false,
    nivelAguaAlarma: false,
    fallaTermicaBomba: false,
    eventosSinAgua: 0,
    horasMunter: 0,
    horasFiltroF9: 0,
    horasFiltroG4: 0,
    horasPolifosfato: 0,
    salaAbierta: false,
    aperturasSala: 0,
    munterAbierto: false,
    aperturasMunter: 0,
    cantidadApagadas: 0,
    estadoEquipo: 'RUN',
  );
}

MuntersModel _maintenanceSala(String name) {
  final MuntersModel sala = _sala(name);
  return MuntersModel(
    name: sala.name,
    historyClientId: sala.historyClientId,
    historyPlcId: sala.historyPlcId,
    diagnostics: const PlcUnitDiagnostics(
      backendAlive: true,
      plcConnectOk: false,
      validKeySignals: null,
      invalidKeySignals: null,
      totalKeySignals: null,
      lastPollAt: null,
      lastSuccessfulReadAt: null,
      stateCode: PlcUnitDiagnostics.plcStateUnknown,
      stateLabel: 'Mantenimiento Sistemas',
      stateReason:
          'Valores ocultos en frontend por mantenimiento seleccionado.',
    ),
    backendOnline: sala.backendOnline,
    configured: sala.configured,
    plcReachable: null,
    plcRunning: null,
    dataFresh: null,
    plcOnline: null,
    plcLatencyMs: null,
    routerLatencyMs: null,
    backendStartedAt: null,
    lastUpdatedAt: null,
    previousLastUpdatedAt: null,
    updateDeltaSeconds: null,
    lastHeartbeatValue: null,
    lastHeartbeatChangeAt: null,
    lastError: null,
    recentRoomWashEvent: null,
    tempInterior: null,
    tempIngresoSala: null,
    humInterior: null,
    tempExterior: null,
    humExterior: null,
    nh3: null,
    presionDiferencial: null,
    tensionSalidaVentiladores: null,
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
    estadoEquipo: null,
  );
}
