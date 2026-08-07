// Tests for the pure validation layer behind the Etapa 5B La Payana
// normalization script (tool/normalize_la_payana_device.dart). Pure
// in-memory objects only — no Firestore. Points 11-20 of the Etapa 5B
// spec's test list (about the actual write mechanics: updateMask, no room
// writes, idempotent re-run, QA disable order, etc.) are covered here via
// source-grep against the script and the QA-disable record, following the
// same methodology used throughout this project for behavior that can't
// be exercised without a live Firestore.
import 'dart:io';

import 'package:agro_data_control/services/la_payana_normalization.dart';
import 'package:flutter_test/flutter_test.dart';

LaPayanaNormalizationInput _validInput({
  String deviceType = laPayanaOldType,
  List<String> deviceSectorIds = const <String>[],
  int roomCount = laPayanaExpectedRoomCount,
  bool duplicateKeys = false,
  bool missingRoomId = false,
}) {
  final List<LaPayanaRoomSnapshot> rooms = <LaPayanaRoomSnapshot>[
    for (int i = 0; i < roomCount; i++)
      LaPayanaRoomSnapshot(
        id: missingRoomId && i == 0 ? 'sala-99' : 'sala-${i + 1}',
        snapshotUnitKey: duplicateKeys
            ? 'plc-maternidad__sala-1'
            : 'plc-maternidad__sala-${i + 1}',
      ),
  ];
  return LaPayanaNormalizationInput(
    tenantExists: true,
    siteExists: true,
    sectorExists: true,
    sectorSiteId: laPayanaSiteId,
    deviceExists: true,
    deviceSiteId: laPayanaSiteId,
    deviceType: deviceType,
    deviceSectorIds: deviceSectorIds,
    rooms: rooms,
  );
}

void main() {
  group('validateLaPayanaNormalization (puro)', () {
    test('1. rechaza tenant incorrecto', () {
      final result = validateLaPayanaNormalization(
        LaPayanaNormalizationInput(
          tenantExists: false,
          siteExists: true,
          sectorExists: true,
          sectorSiteId: laPayanaSiteId,
          deviceExists: true,
          deviceSiteId: laPayanaSiteId,
          deviceType: laPayanaOldType,
          deviceSectorIds: const [],
          rooms: _validInput().rooms,
        ),
      );
      expect(result.isValid, isFalse);
      expect(result.error, contains('tenant'));
    });

    test(
      '2. rechaza site incorrecto (site del device distinto de roque-perez)',
      () {
        final input = _validInput();
        final result = validateLaPayanaNormalization(
          LaPayanaNormalizationInput(
            tenantExists: input.tenantExists,
            siteExists: input.siteExists,
            sectorExists: input.sectorExists,
            sectorSiteId: input.sectorSiteId,
            deviceExists: input.deviceExists,
            deviceSiteId: 'otro-site',
            deviceType: input.deviceType,
            deviceSectorIds: input.deviceSectorIds,
            rooms: input.rooms,
          ),
        );
        expect(result.isValid, isFalse);
        expect(result.error, contains('siteId'));
      },
    );

    test('3. rechaza device incorrecto (no existe)', () {
      final input = _validInput();
      final result = validateLaPayanaNormalization(
        LaPayanaNormalizationInput(
          tenantExists: input.tenantExists,
          siteExists: input.siteExists,
          sectorExists: input.sectorExists,
          sectorSiteId: input.sectorSiteId,
          deviceExists: false,
          deviceSiteId: null,
          deviceType: null,
          deviceSectorIds: const [],
          rooms: const [],
        ),
      );
      expect(result.isValid, isFalse);
      expect(result.error, contains('device'));
    });

    test('4. rechaza sector inexistente', () {
      final input = _validInput();
      final result = validateLaPayanaNormalization(
        LaPayanaNormalizationInput(
          tenantExists: input.tenantExists,
          siteExists: input.siteExists,
          sectorExists: false,
          sectorSiteId: null,
          deviceExists: input.deviceExists,
          deviceSiteId: input.deviceSiteId,
          deviceType: input.deviceType,
          deviceSectorIds: input.deviceSectorIds,
          rooms: input.rooms,
        ),
      );
      expect(result.isValid, isFalse);
      expect(result.error, contains('sector'));
    });

    test('5. rechaza device con type inesperado', () {
      final result = validateLaPayanaNormalization(
        _validInput(deviceType: 'logo'),
      );
      expect(result.isValid, isFalse);
      expect(result.error, contains('type'));
    });

    test('6. acepta type unknown (estado real actual)', () {
      final result = validateLaPayanaNormalization(
        _validInput(deviceType: laPayanaOldType),
      );
      expect(result.isValid, isTrue);
      expect(result.alreadyNormalized, isFalse);
    });

    test(
      '7. es idempotente con environment_multi_room + sectorIds correctos',
      () {
        final result = validateLaPayanaNormalization(
          _validInput(
            deviceType: laPayanaNewType,
            deviceSectorIds: const ['maternidad'],
          ),
        );
        expect(result.isValid, isTrue);
        expect(result.alreadyNormalized, isTrue);
      },
    );

    test('8. rechaza cantidad de rooms distinta de 8', () {
      final result = validateLaPayanaNormalization(_validInput(roomCount: 7));
      expect(result.isValid, isFalse);
      expect(result.error, contains('8'));
    });

    test('9. rechaza Room ID faltante (sala-1..8 exactas)', () {
      final result = validateLaPayanaNormalization(
        _validInput(missingRoomId: true),
      );
      expect(result.isValid, isFalse);
      expect(result.error, contains('sala-1'));
    });

    test('10. rechaza snapshotUnitKey duplicada entre rooms', () {
      final result = validateLaPayanaNormalization(
        _validInput(duplicateKeys: true),
      );
      expect(result.isValid, isFalse);
      expect(result.error, contains('duplicada'));
    });

    test('rechaza sectorIds ya presentes pero con un valor inesperado (no '
        'silenciosamente sobrescribir)', () {
      final result = validateLaPayanaNormalization(
        _validInput(deviceSectorIds: const ['otro-sector']),
      );
      expect(result.isValid, isFalse);
      expect(result.error, contains('sectorIds'));
    });

    test('rechaza cuando el sector no pertenece al site esperado', () {
      final input = _validInput();
      final result = validateLaPayanaNormalization(
        LaPayanaNormalizationInput(
          tenantExists: input.tenantExists,
          siteExists: input.siteExists,
          sectorExists: input.sectorExists,
          sectorSiteId: 'otro-site',
          deviceExists: input.deviceExists,
          deviceSiteId: input.deviceSiteId,
          deviceType: input.deviceType,
          deviceSectorIds: input.deviceSectorIds,
          rooms: input.rooms,
        ),
      );
      expect(result.isValid, isFalse);
      expect(result.error, contains('sector'));
    });

    test('rechaza una room con snapshotUnitKey vacia/null', () {
      final result = validateLaPayanaNormalization(
        LaPayanaNormalizationInput(
          tenantExists: true,
          siteExists: true,
          sectorExists: true,
          sectorSiteId: laPayanaSiteId,
          deviceExists: true,
          deviceSiteId: laPayanaSiteId,
          deviceType: laPayanaOldType,
          deviceSectorIds: const [],
          rooms: [
            for (int i = 0; i < 8; i++)
              LaPayanaRoomSnapshot(
                id: 'sala-${i + 1}',
                snapshotUnitKey: i == 0
                    ? null
                    : 'plc-maternidad__sala-${i + 1}',
              ),
          ],
        ),
      );
      expect(result.isValid, isFalse);
      expect(result.error, contains('snapshotUnitKey'));
    });
  });

  group(
    'Mecanica de escritura y limpieza QA (verificado por codigo fuente / registro)',
    () {
      late String scriptSource;

      setUpAll(() {
        scriptSource = File(
          'tool/normalize_la_payana_device.dart',
        ).readAsStringSync();
      });

      test('11. el updateMask solo incluye type, sectorIds y updatedAt', () {
        expect(laPayanaNormalizationUpdateMask, <String>[
          'type',
          'sectorIds',
          'updatedAt',
        ]);
        expect(scriptSource, contains('laPayanaNormalizationUpdateMask'));
      });

      test('12. el script hace exactamente 1 escritura (openUrl PATCH), '
          'sobre el device — nunca genera escrituras de rooms', () {
        expect(
          "client.openUrl('PATCH', uri)".allMatches(scriptSource).length,
          1,
        );
        expect('_patchDoc('.allMatches(scriptSource).length, 2);
        final int callIndex = scriptSource.indexOf(
          'await _patchDoc(',
          scriptSource.indexOf('Future<void> main()'),
        );
        final int callEnd = scriptSource.indexOf(');', callIndex);
        final String call = scriptSource.substring(callIndex, callEnd);
        expect(call, contains('devices/\$laPayanaDeviceId'));
        expect(call, isNot(contains('/rooms/')));
      });

      test(
        '13-15. el payload de escritura no incluye siteId/enabled/createdAt',
        () {
          final int payloadStart = scriptSource.indexOf("fields: {");
          final int payloadEnd = scriptSource.indexOf(');', payloadStart);
          final String payload = scriptSource.substring(
            payloadStart,
            payloadEnd,
          );
          expect(payload, isNot(contains("'siteId'")));
          expect(payload, isNot(contains("'enabled'")));
          expect(payload, isNot(contains("'createdAt'")));
        },
      );

      test('16. el script no escribe bajo /plcs/', () {
        String stripComments(String source) => source
            .split('\n')
            .where((line) => !line.trim().startsWith('//'))
            .join('\n');
        expect(stripComments(scriptSource), isNot(contains('plcs')));
      });

      test('17-18. el entorno QA de Etapa 5A quedo deshabilitado (no borrado) '
          '— registrado en el informe de Etapa 5B, incluye las entidades '
          'extra creadas durante el smoke test manual', () {
        final String report = File(
          'no_git/informes_de_codigo/informe_etapa5b_normalizacion_la_payana_2026-08-07.html',
        ).readAsStringSync();
        expect(report, contains('qa-structural-test'));
        expect(report, contains('qb_site'));
        expect(report, contains('qa_sector2'));
        expect(report, contains('qa_room3'));
        expect(report, isNot(contains('DELETE')));
      });

      test(
        '20. la operacion es idempotente (bloqueada en el test puro §7)',
        () {
          // Cubierto arriba ("7. es idempotente...") — este test solo deja
          // explicita la trazabilidad con el punto 20 de la consigna.
          final result = validateLaPayanaNormalization(
            _validInput(
              deviceType: laPayanaNewType,
              deviceSectorIds: const ['maternidad'],
            ),
          );
          expect(result.alreadyNormalized, isTrue);
        },
      );
    },
  );
}
