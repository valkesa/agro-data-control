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
    );

    expect(settings.enabled, isFalse);
    expect(settings.sendWhatsapp, isFalse);
  });

  test('serializes alert settings', () {
    final AlertSettings settings = const AlertSettings.defaults().copyWith(
      highHumidity: const AlertToggleSettings(
        enabled: true,
        sendWhatsapp: true,
      ),
    );

    final Map<String, Object?> data = settings.toFirestore();
    expect(
      data['highHumidity'],
      equals(<String, Object?>{'enabled': true, 'sendWhatsapp': true}),
    );
  });
}
