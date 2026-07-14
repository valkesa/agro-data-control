import 'package:agro_data_control/models/alert_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses compatible defaults when alerts are missing', () {
    final AlertSettings settings = AlertSettings.fromRaw(<String, dynamic>{});

    expect(settings.muntersDoorOpen.enabled, isTrue);
    expect(settings.muntersDoorOpen.sendWhatsapp, isFalse);
    expect(settings.highHumidity.enabled, isTrue);
    expect(settings.highHumidity.sendWhatsapp, isFalse);
  });

  test('prevents disabled alert with whatsapp enabled', () {
    final AlertToggleSettings settings = AlertToggleSettings.fromRaw(
      <String, dynamic>{'enabled': false, 'sendWhatsapp': true},
      defaultEnabled: true,
      defaultOrder: 1,
    );

    expect(settings.enabled, isFalse);
    expect(settings.sendWhatsapp, isFalse);
  });

  test('serializes alert settings', () {
    final AlertSettings settings = const AlertSettings.defaults().copyWith(
      highHumidity: const AlertToggleSettings(
        enabled: true,
        sendWhatsapp: true,
        order: 6,
      ),
    );

    final Map<String, Object?> data = settings.toFirestore();
    expect(
      data['highHumidity'],
      equals(<String, Object?>{
        'enabled': true,
        'sendWhatsapp': true,
        'order': 6,
      }),
    );
  });

  test('reads legacy temperature alert toggle keys', () {
    final AlertSettings settings = AlertSettings.fromRaw(<String, dynamic>{
      'alerts': <String, dynamic>{
        'lowTemperatureHeatingActive': <String, dynamic>{
          'enabled': false,
          'sendWhatsapp': true,
        },
        'highTemperatureHumidifierActive': <String, dynamic>{
          'enabled': true,
          'sendWhatsapp': true,
        },
      },
    });

    expect(settings.highTemperatureHeatingActive.enabled, isFalse);
    expect(settings.highTemperatureHeatingActive.sendWhatsapp, isFalse);
    expect(settings.lowTemperatureHumidifierActive.enabled, isTrue);
    expect(settings.lowTemperatureHumidifierActive.sendWhatsapp, isTrue);
  });

  test('uses fallback order when alerts are missing order', () {
    final AlertSettings settings = AlertSettings.fromRaw(<String, dynamic>{});

    expect(settings.orderedKeys, equals(AlertSettingKey.values));
    expect(settings.highHumidity.order, 6);
    expect(settings.dewPointRisk.order, 7);
  });

  test('normalizes duplicated and invalid order values', () {
    final AlertSettings settings = AlertSettings.fromRaw(<String, dynamic>{
      'alerts': <String, dynamic>{
        'muntersDoorOpen': <String, dynamic>{'order': -1},
        'roomDoorOpen': <String, dynamic>{'order': 2},
        'highTemperatureHeatingActive': <String, dynamic>{'order': 2},
        'lowTemperatureHumidifierActive': <String, dynamic>{'order': null},
        'highDifferentialPressure': <String, dynamic>{'order': 20},
        'highHumidity': <String, dynamic>{'order': 20},
        'dewPointRisk': <String, dynamic>{'order': 'bad'},
      },
    });

    expect(
      settings.orderedKeys
          .map((AlertSettingKey key) => settings.toggleFor(key).order)
          .toList(),
      equals(<int>[1, 2, 3, 4, 5, 6, 7]),
    );
  });

  test('moves alerts up and down with continuous order', () {
    final AlertSettings moved = const AlertSettings.defaults()
        .move(AlertSettingKey.highHumidity, -1)
        .move(AlertSettingKey.highHumidity, -1);

    expect(
      moved.orderedKeys,
      equals(<AlertSettingKey>[
        AlertSettingKey.muntersDoorOpen,
        AlertSettingKey.roomDoorOpen,
        AlertSettingKey.highTemperatureHeatingActive,
        AlertSettingKey.highHumidity,
        AlertSettingKey.lowTemperatureHumidifierActive,
        AlertSettingKey.highDifferentialPressure,
        AlertSettingKey.dewPointRisk,
      ]),
    );
    expect(
      moved.orderedKeys
          .map((AlertSettingKey key) => moved.toggleFor(key).order)
          .toList(),
      equals(<int>[1, 2, 3, 4, 5, 6, 7]),
    );
  });

  test('humidity and dew point keep shared logical toggles', () {
    final AlertSettings settings = const AlertSettings.defaults()
        .withToggle(
          AlertSettingKey.highHumidity,
          const AlertToggleSettings(
            enabled: true,
            sendWhatsapp: true,
            order: 2,
          ),
        )
        .withToggle(
          AlertSettingKey.dewPointRisk,
          const AlertToggleSettings(
            enabled: false,
            sendWhatsapp: false,
            order: 1,
          ),
        );

    expect(settings.highHumidity.sendWhatsapp, isTrue);
    expect(settings.dewPointRisk.enabled, isFalse);
    expect(settings.dewPointRisk.sendWhatsapp, isFalse);
    expect(settings.highHumidity.order, isNot(settings.dewPointRisk.order));
  });
}
