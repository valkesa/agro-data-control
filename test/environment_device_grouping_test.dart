// Widget tests for grouping Salas by their physical Device — Tablero
// (EnvironmentOverviewPage) and Tabla (EnvironmentTablePage). Rules, as
// specified for La Payana's "PLC Maternidad" (1 Device -> 8 Salas):
//
// Tablero:
//   - up to 3 Salas total (across the whole page): single column, stacked.
//   - beyond 3 Salas total: 2 columns, left-to-right then top-to-bottom.
//     That threshold is evaluated once for the whole page, independent of
//     how many Salas any single Device has — a Device with only 1 Sala
//     still lays out in 2-column mode if another Device pushes the page
//     total past 3.
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
import 'package:agro_data_control/pages/comparison_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EnvironmentOverviewPage (Tablero)', () {
    testWidgets('hasta 3 salas totales: columna unica (mismo x, y creciente)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnvironmentOverviewPage(
              units: <MuntersModel>[_sala('Sala 1'), _sala('Sala 2'), _sala('Sala 3')],
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

      expect(p1.dx, p2.dx, reason: 'sala2 debe quedar debajo de sala1, misma columna');
      expect(p2.dx, p3.dx, reason: 'sala3 debe quedar debajo de sala2, misma columna');
      expect(p2.dy, greaterThan(p1.dy));
      expect(p3.dy, greaterThan(p2.dy));
    });

    testWidgets(
      'mas de 3 salas totales: 2 columnas, izquierda a derecha y arriba a abajo',
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
                  'PLC A',
                  'PLC A',
                  'PLC A',
                  'PLC A',
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
        final Offset p2 = tester.getTopLeft(find.text('Sala 2').first);
        final Offset p3 = tester.getTopLeft(find.text('Sala 3').first);
        final Offset p4 = tester.getTopLeft(find.text('Sala 4').first);

        // sala1 arriba, sala2 a la derecha de sala1 (misma fila).
        expect(p1.dy, p2.dy);
        expect(p2.dx, greaterThan(p1.dx));
        // sala3 debajo de sala1, sala4 debajo de sala2 (misma columna que cada una).
        expect(p3.dx, p1.dx);
        expect(p4.dx, p2.dx);
        expect(p3.dy, greaterThan(p1.dy));
        expect(p4.dy, greaterThan(p2.dy));
        // sala3 y sala4 en la misma fila entre si.
        expect(p3.dy, p4.dy);
      },
    );

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
                // Device 1 tiene 3 salas, Device 2 tiene 1 -> total 4 > 3,
                // asi que AMBOS grupos usan el modo de 2 columnas, aunque
                // Device 2 solo tenga una sola sala.
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

        // Sala 4 (unica sala de Device 2) arranca en la misma columna que
        // sala1/sala3 (columna izquierda) y, en su propio grupo, no se
        // "estira" a 2 columnas por si sola.
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

      expect(find.byIcon(Icons.memory), findsNothing);
    });
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
