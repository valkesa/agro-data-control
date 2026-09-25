import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control_backend/src/plc_installation_config.dart';

void main() {
  final String raw = _configFile().readAsStringSync();
  final PlcInstallationConfig config = PlcInstallationConfig.fromJson(
    jsonDecode(raw) as Map<String, dynamic>,
  );

  _testDefaultConfigUsesOperationalAlertsSite(config);

  // ignore: avoid_print
  print('default_config_runtime_events_test: all expectations passed');
}

File _configFile() {
  for (final String path in <String>[
    'backend/config/sites/default.json',
    'config/sites/default.json',
  ]) {
    final File file = File(path);
    if (file.existsSync()) {
      return file;
    }
  }
  throw StateError('backend/config/sites/default.json not found');
}

void _testDefaultConfigUsesOperationalAlertsSite(PlcInstallationConfig config) {
  _expect(config.runtimeEvents.enabled, 'runtimeEvents enabled');
  _expect(
    config.runtimeEvents.tenantId == 'the-gene-pig',
    'runtimeEvents tenantId is the-gene-pig',
  );
  _expect(
    config.runtimeEvents.siteId == 'las-heras',
    'runtimeEvents siteId is las-heras',
  );
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Failed expectation: $description');
  }
}
