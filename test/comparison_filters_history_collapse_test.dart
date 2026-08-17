import 'package:agro_data_control/models/dashboard_range_settings.dart';
import 'package:agro_data_control/models/dashboard_door_event.dart';
import 'package:agro_data_control/models/magnifier_settings.dart';
import 'package:agro_data_control/models/munters_model.dart';
import 'package:agro_data_control/pages/comparison_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('grafico de filtros aparece colapsado por default', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComparisonPage(
            munters1: _unit('Sala 1', 'munters1'),
            munters2: _unit('Sala 2', 'munters2'),
            doorEvents: const <String, DashboardDoorEvent>{},
            tenantId: null,
            siteId: null,
            showMunters1: true,
            showMunters2: true,
            snapshotStale: false,
            showSnapshotPulse: false,
            rangeSettings: const DashboardRangeSettings.defaults(),
            moduleOrder: ComparisonPage.defaultModuleOrder,
            onModuleOrderChanged: (_) {},
            reorderEnabled: false,
            onToggleReorder: () {},
            onDetailAction: () {},
            magnifierSettings: const MagnifierSettings.defaults(),
            homeGeneration: 0,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('FILTROS'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Gráfico'), findsOneWidget);
    expect(find.text('Ver gráfico'), findsNWidgets(2));
    expect(find.text('Historial no disponible.'), findsNothing);
    expect(
      find.text('Todavia no hay historial diario de presion diferencial.'),
      findsNothing,
    );
  });
}

MuntersModel _unit(String name, String plcId) {
  return MuntersModel(
    name: name,
    historyPlcId: plcId,
    tempInterior: 22,
    tempIngresoSala: null,
    humInterior: 60,
    tempExterior: 18,
    humExterior: 70,
    presionDiferencial: 14,
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
