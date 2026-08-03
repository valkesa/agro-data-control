// Widget tests for the new "Tabla" view (EnvironmentTablePage), opened
// from EnvironmentOverviewPage's previously-unwired "Tabla" button.
//
// No Firebase is initialized in this test — that's fine because the pig
// count cell (_EnvironmentTablePigCell) only calls CerdasRepository when
// tenantId/siteId/plcId are all non-empty; passing null here (as done
// below) short-circuits straight to a '-' placeholder with no Firestore
// access, so the whole page can be pumped safely.
import 'package:agro_data_control/models/dashboard_range_settings.dart';
import 'package:agro_data_control/models/munters_model.dart';
import 'package:agro_data_control/pages/comparison_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders a single unified table with one row per unit', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnvironmentTablePage(
            units: <MuntersModel>[_sala1Healthy(), _sala2Alarm()],
            labels: const <String>['Sala 1', 'Sala 2'],
            plcIds: const <String?>['munters1', 'munters2'],
            tenantId: null,
            siteId: null,
            rangeSettings: const DashboardRangeSettings.defaults(),
          ),
        ),
      ),
    );
    await tester.pump();

    // One flat table: each Sala's label appears exactly once as its row
    // label. PLC identification is intentionally not shown yet (to be
    // added in a follow-up) — no per-PLC header/grouping today.
    expect(find.text('Sala 1'), findsOneWidget);
    expect(find.text('Sala 2'), findsOneWidget);

    // Column headers from the demo layout.
    for (final String header in <String>[
      'Temperatura °C',
      'Humedad %',
      'Punto de rocío °C',
      'Ventilador %',
      'Panel evaporativo',
      'Cerdos',
      'CO2 ppm',
      'Agua L/día',
      'NH3 ppm',
    ]) {
      expect(find.text(header), findsWidgets);
    }

    // Color legend footer.
    expect(find.text('Verde: Óptimo'), findsOneWidget);
    expect(find.text('Amarillo: Atención'), findsOneWidget);
    expect(find.text('Rojo: Alarma'), findsOneWidget);
  });

  testWidgets('shows real measurements and Sin datos for missing fields', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnvironmentTablePage(
            units: <MuntersModel>[_sala1Healthy()],
            labels: const <String>['Sala 1'],
            plcIds: const <String?>['munters1'],
            tenantId: null,
            siteId: null,
            rangeSettings: const DashboardRangeSettings.defaults(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('22.1'), findsOneWidget); // temperatureC
    expect(find.text('60'), findsOneWidget); // humidityPercent
    expect(find.text('ON'), findsOneWidget); // evaporativePanelOn
    // CO2 and Agua never have a real source today; NH3 has the field but
    // no PLC signal feeds it, so it also falls back to 'Sin datos'.
    expect(find.text('Sin datos'), findsNWidgets(3));
  });

  testWidgets('pig count cell shows a placeholder without a tenant/site/plc', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnvironmentTablePage(
            units: <MuntersModel>[_sala1Healthy()],
            labels: const <String>['Sala 1'],
            plcIds: const <String?>[null],
            tenantId: null,
            siteId: null,
            rangeSettings: const DashboardRangeSettings.defaults(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('-'), findsWidgets);
  });
}

MuntersModel _sala1Healthy() {
  return const MuntersModel(
    name: 'Sala 1',
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

MuntersModel _sala2Alarm() {
  return const MuntersModel(
    name: 'Sala 2',
    tempInterior: 31.2,
    tempIngresoSala: null,
    humInterior: 78,
    tempExterior: 24,
    humExterior: 80,
    tensionSalidaVentiladores: 900,
    bombaHumidificador: false,
    fanQ5: true,
    fanQ6: true,
    fanQ7: true,
    fanQ8: true,
    fanQ9: true,
    fanQ10: true,
    resistencia1: false,
    resistencia2: false,
    alarmaGeneral: true,
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
