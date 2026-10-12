import 'package:agro_data_control/utils/historical_export_filename.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildHistoricalExportFilename', () {
    test('matches the prompt example exactly', () {
      final name = buildHistoricalExportFilename(
        clientName: 'Gene Pig',
        establishmentName: 'Las Heras',
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
      );
      expect(name, 'AgroData_GenePig_LasHeras_2026-09-01_2026-09-30.xlsx');
    });

    test('strips invalid filesystem characters', () {
      final name = buildHistoricalExportFilename(
        clientName: 'Cliente/Raro:Test*',
        establishmentName: 'Sitio?["x"]',
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 2),
      );
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains(':')));
      expect(name, isNot(contains('*')));
      expect(name, isNot(contains('?')));
      expect(name, isNot(contains('[')));
      expect(name.endsWith('.xlsx'), isTrue);
    });

    test('transliterates common Spanish diacritics', () {
      final name = buildHistoricalExportFilename(
        clientName: 'Peña',
        establishmentName: 'Roque Pérez',
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 2),
      );
      expect(name, 'AgroData_Pena_RoquePerez_2026-01-01_2026-01-02.xlsx');
    });

    test('falls back to a placeholder when a name sanitizes to empty', () {
      final name = buildHistoricalExportFilename(
        clientName: '***',
        establishmentName: 'Sitio',
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 2),
      );
      expect(name, contains('sin-nombre'));
    });
  });
}
