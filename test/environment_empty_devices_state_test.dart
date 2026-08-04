// Widget tests for the "0 Devices" empty state shared by Tablero
// (EnvironmentOverviewPage) and Tabla (EnvironmentTablePage) — Etapas 4-5 of
// the "Devices dinámicos" migration. A dynamic-Devices Site with 0 enabled
// Devices must show an explicit message, never a silently blank area or a
// phantom card.
import 'package:agro_data_control/models/dashboard_range_settings.dart';
import 'package:agro_data_control/models/munters_model.dart';
import 'package:agro_data_control/pages/comparison_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EnvironmentTablePage', () {
    testWidgets('0 unidades muestra el estado vacio, no una tabla en blanco', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EnvironmentTablePage(
              units: <MuntersModel>[],
              labels: <String>[],
              plcIds: <String?>[],
              tenantId: 'la-payana',
              siteId: 'roque-perez',
              rangeSettings: DashboardRangeSettings.defaults(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('No hay equipos configurados para este site.'),
        findsOneWidget,
      );
      // No legend, no grid — those only make sense once there's at least
      // one row.
      expect(find.text('Verde: Óptimo'), findsNothing);
    });

    testWidgets('1 unidad sigue mostrando la tabla normalmente (no el estado vacio)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnvironmentTablePage(
              units: <MuntersModel>[
                const MuntersModel.placeholder(name: 'PLC Maternidad'),
              ],
              labels: const <String>['PLC Maternidad'],
              plcIds: const <String?>[null],
              tenantId: 'la-payana',
              siteId: 'roque-perez',
              rangeSettings: const DashboardRangeSettings.defaults(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('No hay equipos configurados para este site.'),
        findsNothing,
      );
      expect(find.text('PLC Maternidad'), findsOneWidget);
      expect(find.text('Verde: Óptimo'), findsOneWidget);
    });
  });

  group('EnvironmentOverviewPage', () {
    testWidgets('0 unidades muestra el estado vacio, no una columna en blanco', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EnvironmentOverviewPage(
              units: <MuntersModel>[],
              labels: <String>[],
              plcIds: <String?>[],
              tenantId: 'la-payana',
              siteId: 'roque-perez',
              rangeSettings: DashboardRangeSettings.defaults(),
              showSnapshotPulse: false,
              snapshotStale: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('No hay equipos configurados para este site.'),
        findsOneWidget,
      );
    });

    testWidgets('1 unidad muestra su card con el nombre real del Device', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnvironmentOverviewPage(
              units: <MuntersModel>[
                const MuntersModel.placeholder(name: 'PLC Maternidad'),
              ],
              labels: const <String>['PLC Maternidad'],
              plcIds: const <String?>[null],
              tenantId: 'la-payana',
              siteId: 'roque-perez',
              rangeSettings: const DashboardRangeSettings.defaults(),
              showSnapshotPulse: false,
              snapshotStale: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('No hay equipos configurados para este site.'),
        findsNothing,
      );
      expect(find.text('PLC Maternidad'), findsWidgets);
    });
  });
}
