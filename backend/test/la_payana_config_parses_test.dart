// Regression test for backend/config/sites/la-payana__roque-perez.json — the
// one physical "PLC Maternidad" device exposing 8 logical Salas, none wired
// yet (no host/registers known). Locks in two things that would otherwise
// fail silently:
//   - all 8 units parse with empty `signals` (no exception, no fabricated
//     registers)
//   - `temperatureHistories` stays explicitly disabled — if the key were
//     ever dropped from the JSON, PlcInstallationConfig's fallback defaults
//     it back to enabled:true, which would make the backend write bogus
//     temperature-history docs to Firestore on every poll despite the empty
//     signals.
import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control_backend/src/plc_installation_config.dart';

void main() {
  final String raw = File(
    'config/sites/la-payana__roque-perez.json',
  ).readAsStringSync();
  final PlcInstallationConfig config = PlcInstallationConfig.fromJson(
    jsonDecode(raw) as Map<String, dynamic>,
  );

  _testDefinesTheEightSalas(config);
  _testNoRoomHasRegistersConfiguredYet(config);
  _testTemperatureHistoriesExplicitlyDisabled(config);
  _testDifferentialPressureHistoriesEmpty(config);
  _testDoorOpeningsAndRuntimeEventsDisabledByDefault(config);
  _testRealTenantAndSiteIds(config);

  // ignore: avoid_print
  print('la_payana_config_parses_test: all expectations passed');
}

void _testDefinesTheEightSalas(PlcInstallationConfig config) {
  final Set<String> expectedKeys = <String>{
    for (int i = 1; i <= 8; i++) 'plc-maternidad__sala-$i',
  };
  _expect(
    config.units.keys.toSet().length == expectedKeys.length &&
        config.units.keys.every(expectedKeys.contains),
    'defines exactly the 8 plc-maternidad__sala-N units',
  );
}

void _testNoRoomHasRegistersConfiguredYet(PlcInstallationConfig config) {
  for (final MapEntry<String, UnitConfig> entry in config.units.entries) {
    _expect(
      entry.value.signals.isEmpty,
      '${entry.key} has no signals configured yet',
    );
  }
}

void _testTemperatureHistoriesExplicitlyDisabled(
  PlcInstallationConfig config,
) {
  _expect(
    config.temperatureHistories.length == 1,
    'exactly one temperatureHistories entry',
  );
  _expect(
    config.temperatureHistories.single.enabled == false,
    'temperatureHistories is explicitly disabled',
  );
}

void _testDifferentialPressureHistoriesEmpty(PlcInstallationConfig config) {
  _expect(
    config.differentialPressureHistories.isEmpty,
    'differentialPressureHistories stays empty (no pressure signal defined)',
  );
}

void _testDoorOpeningsAndRuntimeEventsDisabledByDefault(
  PlcInstallationConfig config,
) {
  _expect(config.doorOpenings.enabled == false, 'doorOpenings disabled');
  _expect(config.runtimeEvents.enabled == false, 'runtimeEvents disabled');
}

void _testRealTenantAndSiteIds(PlcInstallationConfig config) {
  final TemperatureHistoryConfig history = config.temperatureHistories.single;
  _expect(history.tenantId == 'la-payana', 'tenantId is la-payana');
  _expect(history.siteId == 'roque-perez', 'siteId is roque-perez');
  _expect(history.plcId == 'plc-maternidad', 'plcId is plc-maternidad');
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Failed expectation: $description');
  }
}
