import 'package:agro_data_control/models/alert_settings.dart';
import 'package:agro_data_control/models/plc_maintenance_settings.dart';
import 'package:agro_data_control/services/control_dashboard_config_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ControlDashboardConfigResult configFrom(Map<String, dynamic> rawData) {
    return ControlDashboardConfigResult.success(
      path: 'tenants/t/sites/s/settings/controlDashboard',
      active: true,
      updatedAt: null,
      updatedByUid: null,
      thresholds: const ControlDashboardThresholds.empty(),
      alertSettings: const AlertSettings.defaults(),
      rawData: rawData,
    );
  }

  test('reads legacy flat maintenance settings without degrading Detalle', () {
    final PlcMaintenanceSettings settings = configFrom(<String, dynamic>{
      'ui': <String, dynamic>{
        'maintenance': <String, dynamic>{
          'munters1': 'in_situ',
          'munters2': <String, dynamic>{
            'mode': 'systems',
            'expiresAt': DateTime.now().add(const Duration(hours: 1)),
          },
        },
      },
    }).maintenanceSettings;

    expect(settings.modeFor('munters1'), PlcMaintenanceMode.inSitu);
    expect(settings.modeFor('munters2'), PlcMaintenanceMode.systems);
    expect(settings.modeForDevice('device-a'), isNull);
  });

  test('reads scoped legacy and device maintenance settings', () {
    final PlcMaintenanceSettings settings = configFrom(<String, dynamic>{
      'ui': <String, dynamic>{
        'maintenance': <String, dynamic>{
          'legacy': <String, dynamic>{'munters1': 'scheduled'},
          'devices': <String, dynamic>{
            'device-a': <String, dynamic>{
              'mode': 'systems',
              'expiresAt': DateTime.now().add(const Duration(hours: 2)),
            },
          },
        },
      },
    }).maintenanceSettings;

    expect(settings.modeFor('munters1'), PlcMaintenanceMode.scheduled);
    expect(settings.modeForDevice('device-a'), PlcMaintenanceMode.systems);
    expect(settings.modeFor('device-a'), isNull);
  });

  test('serializes device maintenance in scoped format', () {
    final PlcMaintenanceSettings settings = PlcMaintenanceSettings(
      entriesByPlcId: <String, PlcMaintenanceEntry>{
        'munters1': PlcMaintenanceEntry(
          mode: PlcMaintenanceMode.inSitu,
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      },
      entriesByDeviceId: <String, PlcMaintenanceEntry>{
        'device-a': PlcMaintenanceEntry(
          mode: PlcMaintenanceMode.scheduled,
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      },
    );

    final Map<String, Object?> data = settings.toFirestore();
    expect(data.keys, containsAll(<String>['legacy', 'devices']));
    expect((data['legacy'] as Map<String, Object?>).keys, contains('munters1'));
    expect(
      (data['devices'] as Map<String, Object?>).keys,
      contains('device-a'),
    );
  });
}
