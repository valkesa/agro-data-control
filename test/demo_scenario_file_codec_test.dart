import 'dart:convert';

import 'package:agro_data_control/demo/demo.dart';
import 'package:flutter_test/flutter_test.dart';

DemoScenarioDraft fixture() => DemoScenarioDraft(
  id: 'scenario-stable-id',
  name: 'Puerta temporizada',
  durationSeconds: 30,
  events: const <DemoEventDraft>[
    DemoEventDraft(
      id: 'legacy-event',
      name: 'Evento anterior',
      signalKey: DemoSignalKey.indoorTemperature,
      startSeconds: 1,
      durationSeconds: 4,
      transition: DemoTransition.linear,
      fromValue: 20,
      toValue: 25,
    ),
    DemoEventDraft(
      id: 'door-event',
      name: 'Abrir y cerrar',
      signalKey: DemoSignalKey.roomDoorOpen,
      startSeconds: 10,
      durationSeconds: 8,
      transition: DemoTransition.instant,
      toValue: true,
      endMode: DemoEventEndMode.setValue,
      endValue: false,
    ),
  ],
);

void main() {
  test('round-trip conserva nombre, identidad, orden y finalización', () {
    final encoded = DemoScenarioFileCodec.encode(fixture());
    final decoded = DemoScenarioFileCodec.decode(encoded);

    expect(decoded.id, 'scenario-stable-id');
    expect(decoded.name, 'Puerta temporizada');
    expect(decoded.durationSeconds, 30);
    expect(decoded.events.map((event) => event.id), <String>[
      'legacy-event',
      'door-event',
    ]);
    expect(decoded.events.first.name, 'Evento anterior');
    expect(decoded.events.first.endMode, DemoEventEndMode.keepApplied);
    expect(decoded.events.last.endMode, DemoEventEndMode.setValue);
    expect(decoded.events.last.endValue, isFalse);
    expect(decoded.validate('another-device').isValid, isTrue);

    final root = jsonDecode(encoded) as Map<String, dynamic>;
    expect(root['format'], DemoScenarioFileCodec.formatId);
    expect(root['schemaVersion'], DemoScenarioFileCodec.schemaVersion);
    expect(encoded, isNot(contains('tenantId')));
    expect(encoded, isNot(contains('siteId')));
    expect(encoded, isNot(contains('deviceId')));
    expect(encoded, isNot(contains('snapshotUnitKey')));
  });

  test('JSON sin endMode conserva la semántica histórica', () {
    final root =
        jsonDecode(DemoScenarioFileCodec.encode(fixture()))
            as Map<String, dynamic>;
    final scenario = root['scenario'] as Map<String, dynamic>;
    final events = scenario['events'] as List<dynamic>;
    final event = events.last as Map<String, dynamic>;
    event.remove('endMode');
    event.remove('endValue');

    final decoded = DemoScenarioFileCodec.decode(jsonEncode(root));
    expect(decoded.events.last.endMode, DemoEventEndMode.keepApplied);
    expect(decoded.events.last.endValue, isNull);
  });

  test('rechaza formato, versión futura, señal, tipos y rangos inválidos', () {
    Map<String, dynamic> root() =>
        jsonDecode(DemoScenarioFileCodec.encode(fixture()))
            as Map<String, dynamic>;

    final wrongFormat = root()..['format'] = 'other';
    expect(
      () => DemoScenarioFileCodec.decode(jsonEncode(wrongFormat)),
      throwsA(isA<DemoScenarioFileException>()),
    );
    final future = root()..['schemaVersion'] = 99;
    expect(
      () => DemoScenarioFileCodec.decode(jsonEncode(future)),
      throwsA(isA<DemoScenarioFileException>()),
    );
    final badSignal = root();
    ((badSignal['scenario'] as Map)['events'] as List).first['signalKey'] =
        'arbitrary.path';
    expect(
      () => DemoScenarioFileCodec.decode(jsonEncode(badSignal)),
      throwsA(isA<DemoScenarioFileException>()),
    );
    final badType = root();
    ((badType['scenario'] as Map)['events'] as List).last['toValue'] = 1;
    expect(
      () => DemoScenarioFileCodec.decode(jsonEncode(badType)),
      throwsA(isA<DemoScenarioFileException>()),
    );
    final badRange = root();
    ((badRange['scenario'] as Map)['events'] as List).first['toValue'] = 900;
    expect(
      () => DemoScenarioFileCodec.decode(jsonEncode(badRange)),
      throwsA(isA<DemoScenarioFileException>()),
    );
  });

  test('importación fallida no obliga a reemplazar el borrador actual', () {
    final current = fixture();
    expect(
      () => DemoScenarioFileCodec.decode('{invalid'),
      throwsA(isA<DemoScenarioFileException>()),
    );
    expect(current.name, 'Puerta temporizada');
    expect(current.events, hasLength(2));
  });
}
