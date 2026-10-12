import 'package:agro_data_control/services/historical_export_variable.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HistoricalExportVariable', () {
    const temperature = HistoricalExportVariable(
      key: 'temperature',
      label: 'Temperatura interior',
      unit: '°C',
    );

    test('columnHeader combines label + unit', () {
      expect(temperature.columnHeader, 'Temperatura interior (°C)');
    });

    test('columnHeader omits parens when unit is empty', () {
      const noUnit = HistoricalExportVariable(key: 'x', label: 'X', unit: '');
      expect(noUnit.columnHeader, 'X');
    });

    test('extractAvg reads avg when sampleCount > 0', () {
      final doc = {
        'temperature': {'avg': 21.5, 'min': 20.0, 'max': 23.0, 'sampleCount': 6},
      };
      expect(temperature.extractAvg(doc), 21.5);
    });

    test('extractAvg returns null when sampleCount is 0 (no real samples)', () {
      final doc = {
        'temperature': {'avg': 21.5, 'sampleCount': 0},
      };
      expect(temperature.extractAvg(doc), isNull);
    });

    test('extractAvg returns null when the field is missing entirely', () {
      final doc = <String, Object?>{'humidity': {'avg': 70.0, 'sampleCount': 3}};
      expect(temperature.extractAvg(doc), isNull);
    });

    test('extractAvg returns null for malformed data instead of throwing', () {
      expect(temperature.extractAvg({'temperature': 'not a map'}), isNull);
      expect(
        temperature.extractAvg({
          'temperature': {'avg': 'NaN', 'sampleCount': 3},
        }),
        isNull,
      );
    });

    test('registry is exactly temperature + humidity today, declaratively', () {
      expect(
        kHistoricalExportVariables.map((v) => v.key),
        ['temperature', 'humidity'],
      );
    });
  });
}
