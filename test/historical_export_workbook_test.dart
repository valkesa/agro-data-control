import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agro_data_control/services/historical_export_repository.dart';
import 'package:agro_data_control/services/historical_export_variable.dart';
import 'package:agro_data_control/services/historical_export_workbook.dart';

HistoricalExportPoint _point(
  int hour, {
  double? temp,
  int tempSamples = 6,
  double? hum,
  int humSamples = 6,
}) => HistoricalExportPoint(DateTime.utc(2026, 9, 1, hour + 3), {
  if (temp != null) 'temperature': {'avg': temp, 'sampleCount': tempSamples},
  if (hum != null) 'humidity': {'avg': hum, 'sampleCount': humSamples},
});

Object? _cellValue(Data? c) => switch (c?.value) {
  DateCellValue v => v.asDateTimeUtc(),
  TimeCellValue v => v.asDuration(),
  TextCellValue v => v.value.text,
  DoubleCellValue v => v.value,
  // Whole-number doubles (e.g. 19.0) round-trip through the file as
  // IntCellValue — still "a real numeric value, not text" (§FORMATO), just
  // a different CellValue subtype than the one this code wrote.
  IntCellValue v => v.value.toDouble(),
  _ => null,
};

List<Object?> _rowValues(List<Data?> row) => row.map(_cellValue).toList();

void main() {
  group('E. Generación de filas / hojas', () {
    test('encabezado incluye Device, métricas, período y columnas amigables', () {
      final bytes = buildHistoricalExportWorkbook(
        HistoricalExportRequest(
          clientName: 'Gene Pig',
          establishmentName: 'Las Heras',
          fromDate: DateTime(2026, 9, 1),
          toDate: DateTime(2026, 9, 30),
          variables: kHistoricalExportVariables,
          devices: [
            HistoricalExportDeviceData(
              deviceName: 'Sala 1',
              points: [_point(0, temp: 21.5, hum: 70)],
            ),
          ],
        ),
      );
      final decoded = Excel.decodeBytes(bytes);
      expect(decoded.sheets.keys, ['Sala 1']);
      final rows = decoded['Sala 1'].rows;
      expect(_rowValues(rows[0]).first, 'Gene Pig');
      expect(_rowValues(rows[1]).first, 'Las Heras');
      expect(_rowValues(rows[2]).first, 'Device: Sala 1');
      expect(
        _rowValues(rows[3]).first,
        'Métricas seleccionadas: Temperatura interior (°C), Humedad interior (%)',
      );
      expect(_rowValues(rows[4]).first, 'Período: 01/09/2026 al 30/09/2026');
      expect(_rowValues(rows[5]).first, 'Formato Fecha: año.mes.dia.hora');
      expect(rows[6].every((c) => c?.value == null), isTrue); // blank spacer
      expect(_rowValues(rows[7]).take(5), [
        'Fecha',
        'Hora',
        'Fecha y hora',
        'Temperatura interior (°C)',
        'Humedad interior (%)',
      ]);
      expect(rows[7][0]?.cellStyle?.isBold, isTrue); // I. bold header
    });

    test('fecha y hora consolidada usa YY.MM.DD.hh en horario ART', () {
      expect(
        historicalExportDateTimeLabel(DateTime.utc(2026, 9, 1, 3)),
        '26.09.01.00',
      );
      expect(
        historicalExportDateTimeLabel(DateTime.utc(2026, 10, 5, 11)),
        '26.10.05.08',
      );
    });

    test('chronological ascending order, numeric values (not text)', () {
      final bytes = buildHistoricalExportWorkbook(
        HistoricalExportRequest(
          clientName: 'C',
          establishmentName: 'E',
          fromDate: DateTime(2026, 9, 1),
          toDate: DateTime(2026, 9, 1),
          variables: kHistoricalExportVariables,
          devices: [
            HistoricalExportDeviceData(
              deviceName: 'Sala 1',
              points: [
                _point(0, temp: 19, hum: 60),
                _point(1, temp: 20, hum: 61),
                _point(2, temp: 21, hum: 62),
              ],
            ),
          ],
        ),
      );
      final rows = Excel.decodeBytes(bytes)['Sala 1'].rows;
      expect(_rowValues(rows[8]).take(3), [
        '01/09/2026',
        '00:00',
        '26.09.01.00',
      ]);
      expect(_rowValues(rows[10]).take(3), [
        '01/09/2026',
        '02:00',
        '26.09.01.02',
      ]);
      final temps = [
        _rowValues(rows[8])[3],
        _rowValues(rows[9])[3],
        _rowValues(rows[10])[3],
      ];
      expect(temps, [19.0, 20.0, 21.0]); // ascending, real doubles
      expect(temps.every((t) => t is double), isTrue);
    });

    test('H. valores faltantes quedan en blanco, nunca inventados', () {
      final bytes = buildHistoricalExportWorkbook(
        HistoricalExportRequest(
          clientName: 'C',
          establishmentName: 'E',
          fromDate: DateTime(2026, 9, 1),
          toDate: DateTime(2026, 9, 1),
          variables: kHistoricalExportVariables,
          devices: [
            HistoricalExportDeviceData(
              deviceName: 'Sala 1',
              points: [_point(0, temp: 19, tempSamples: 0, hum: 60)],
            ),
          ],
        ),
      );
      final row = Excel.decodeBytes(bytes)['Sala 1'].rows[8];
      expect(row[3]?.value, isNull); // temperature: sampleCount 0 -> blank
      expect(_rowValues([row[4]]).single, 60.0); // humidity: present
    });

    test(
      'múltiples Devices generan sólo una hoja por Device, sin Consolidado',
      () {
        final bytes = buildHistoricalExportWorkbook(
          HistoricalExportRequest(
            clientName: 'C',
            establishmentName: 'E',
            fromDate: DateTime(2026, 9, 1),
            toDate: DateTime(2026, 9, 1),
            variables: kHistoricalExportVariables,
            devices: [
              HistoricalExportDeviceData(
                deviceName: 'Sala 1',
                points: [_point(0, temp: 21, hum: 70)],
              ),
              HistoricalExportDeviceData(
                deviceName: 'Sala 2',
                points: [_point(-1, temp: 19, hum: 65)],
              ),
            ],
          ),
        );
        final decoded = Excel.decodeBytes(bytes);
        expect(decoded.sheets.keys, ['Sala 1', 'Sala 2']);
        expect(decoded.sheets.keys, isNot(contains('Consolidado')));
        expect(_rowValues(decoded['Sala 1'].rows[2]).first, 'Device: Sala 1');
        expect(_rowValues(decoded['Sala 2'].rows[2]).first, 'Device: Sala 2');
        expect(_rowValues(decoded['Sala 1'].rows[7]), [
          'Fecha',
          'Hora',
          'Fecha y hora',
          'Temperatura interior (°C)',
          'Humedad interior (%)',
        ]);
        expect(_rowValues(decoded['Sala 1'].rows[8])[2], '26.09.01.00');
        expect(_rowValues(decoded['Sala 2'].rows[8]).take(3), [
          '31/08/2026',
          '23:00',
          '26.08.31.23',
        ]);
      },
    );

    test('single device never gets a Consolidado sheet', () {
      final bytes = buildHistoricalExportWorkbook(
        HistoricalExportRequest(
          clientName: 'C',
          establishmentName: 'E',
          fromDate: DateTime(2026, 9, 1),
          toDate: DateTime(2026, 9, 1),
          variables: kHistoricalExportVariables,
          devices: [
            HistoricalExportDeviceData(deviceName: 'Sala 1', points: const []),
          ],
        ),
      );
      expect(Excel.decodeBytes(bytes).sheets.keys, ['Sala 1']);
    });

    test(
      'K. Device sin datos en el rango: hoja con encabezado, sin filas de datos',
      () {
        final bytes = buildHistoricalExportWorkbook(
          HistoricalExportRequest(
            clientName: 'C',
            establishmentName: 'E',
            fromDate: DateTime(2026, 9, 1),
            toDate: DateTime(2026, 9, 30),
            variables: kHistoricalExportVariables,
            devices: [
              HistoricalExportDeviceData(
                deviceName: 'Sala Vacía',
                points: const [],
              ),
            ],
          ),
        );
        final rows = Excel.decodeBytes(bytes)['Sala Vacía'].rows;
        expect(rows.length, 8); // 6 metadata lines + blank + column header
      },
    );

    test(
      'variables seleccionables: solo las elegidas aparecen como columnas',
      () {
        const onlyHumidity = [
          HistoricalExportVariable(
            key: 'humidity',
            label: 'Humedad interior',
            unit: '%',
          ),
        ];
        final bytes = buildHistoricalExportWorkbook(
          HistoricalExportRequest(
            clientName: 'C',
            establishmentName: 'E',
            fromDate: DateTime(2026, 9, 1),
            toDate: DateTime(2026, 9, 1),
            variables: onlyHumidity,
            devices: [
              HistoricalExportDeviceData(
                deviceName: 'Sala 1',
                points: [_point(0, temp: 21, hum: 70)],
              ),
            ],
          ),
        );
        final rows = Excel.decodeBytes(bytes)['Sala 1'].rows;
        expect(
          _rowValues(rows[3]).first,
          'Métricas seleccionadas: Humedad interior (%)',
        );
        final header = _rowValues(rows[7]);
        expect(header, [
          'Fecha',
          'Hora',
          'Fecha y hora',
          'Humedad interior (%)',
        ]);
      },
    );

    test('sheet names are sanitized and de-duplicated', () {
      expect(sanitizeSheetName('Sala/Especial:1', {}), 'Sala Especial 1');
      expect(sanitizeSheetName('A' * 40, {}), hasLength(31));
      final used = {'Sala 1'};
      expect(sanitizeSheetName('Sala 1', used), isNot('Sala 1'));
    });
  });
}
