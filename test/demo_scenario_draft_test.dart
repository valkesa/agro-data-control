import 'package:agro_data_control/demo/demo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CRUD conserva identidades y reorder no cambia tiempos', () {
    final d = DemoScenarioDraft(id: 'd', name: 'Demo', durationSeconds: 20);
    final a = d.addEvent(signalKey: DemoSignalKey.indoorTemperature);
    final b = d.addEvent(signalKey: DemoSignalKey.indoorHumidity);
    d.updateEvent(d.events.first.copyWith(startSeconds: 3, toValue: 25));
    final before = d.events.first.startSeconds;
    d.moveEvent(b, 0);
    expect(d.events.map((e) => e.id), <String>[b, a]);
    expect(d.events.singleWhere((e) => e.id == a).startSeconds, before);
    d.removeEvent(b);
    expect(d.events.single.id, a);
  });
  test('copia técnica es editable e independiente', () {
    final original = buildTechnicalDemoScenario(
      snapshotUnitKey: 'u',
      temperature: 20,
      humidity: 60,
    );
    final draft = DemoScenarioDraft.fromScenario(original);
    expect(draft.events.length, 4);
    draft.events.removeAt(0);
    expect(original.events.length, 4);
    expect(draft.validate('u').isValid, isTrue);
  });
  test('valida duración total, negativos, tipos, rangos y lineal', () {
    final d = DemoScenarioDraft(
      id: 'd',
      name: 'Demo',
      durationSeconds: 2,
      events: <DemoEventDraft>[
        const DemoEventDraft(
          id: 'e',
          signalKey: DemoSignalKey.indoorTemperature,
          startSeconds: 1,
          durationSeconds: 5,
          transition: DemoTransition.linear,
          fromValue: 20,
          toValue: 90,
        ),
      ],
    );
    expect(d.validate('u').isValid, isFalse);
    expect(d.validate('u').errors, isNotEmpty);
    d.durationSeconds = 10;
    d.updateEvent(d.events.first.copyWith(toValue: 40));
    expect(d.validate('u').isValid, isTrue);
  });
  test('solapamientos admitidos generan warning y conservan desempate', () {
    final d = DemoScenarioDraft(
      id: 'd',
      name: 'Demo',
      durationSeconds: 10,
      events: <DemoEventDraft>[
        const DemoEventDraft(
          id: 'a',
          signalKey: DemoSignalKey.indoorTemperature,
          startSeconds: 0,
          durationSeconds: 5,
          transition: DemoTransition.linear,
          fromValue: 20,
          toValue: 30,
        ),
        const DemoEventDraft(
          id: 'z',
          signalKey: DemoSignalKey.indoorTemperature,
          startSeconds: 2,
          durationSeconds: 5,
          transition: DemoTransition.linear,
          fromValue: 30,
          toValue: 40,
        ),
      ],
    );
    final v = d.validate('u');
    expect(v.isValid, isTrue);
    expect(v.warnings, isNotEmpty);
    expect(
      DemoScenarioEvaluator.overridesAt(
        v.scenario!,
        const Duration(seconds: 3),
      )[DemoSignalKey.indoorTemperature],
      closeTo(32, 0.001),
    );
  });
  test('formulario incompleto no produce escenario válido', () {
    final d = DemoScenarioDraft(id: 'd', name: '', durationSeconds: double.nan);
    final v = d.validate('u');
    expect(v.scenario, isNull);
    expect(v.errors.length, greaterThanOrEqualTo(2));
  });
}
