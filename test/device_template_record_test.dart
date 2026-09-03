// Etapa 6A — round-trip serialization for the Firestore persistence
// envelope around DeviceTemplate. `DeviceTemplate.toMap()`/`fromMap()`
// already have their own structural-validation tests
// (test/ui_templates_models_test.dart); this file covers the envelope
// fields (schemaVersion/templateVersion/enabled/timestamps/description/
// tags) and the fallback-triggering parse failures around them.
import 'package:agro_data_control/ui_templates/ui_templates.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceTemplateRecord round-trip', () {
    for (final String templateId in <String>[
      'room_climate',
      'laboratory_basic',
      'disinfection_arch',
    ]) {
      test('$templateId survives toMap -> fromMap unchanged', () {
        final DeviceTemplate original = getTemplateById(templateId)!;
        final DeviceTemplateRecord record = DeviceTemplateRecord(
          template: original,
          schemaVersion: 1,
          templateVersion: 3,
          enabled: true,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 6, 1),
          description: 'test description',
          tags: const <String>['ambiente', 'sala'],
        );

        final DeviceTemplateRecord? roundTripped = DeviceTemplateRecord.fromMap(
          record.toMap(),
        );

        expect(roundTripped, isNotNull);
        // Note: DeviceTemplate has no ==/hashCode override, so this relies
        // on flutter_test's `expect` wrapping the expected value in
        // `equals()`, which does deep Map/List comparison — a bare `==`
        // between two Map instances would NOT do this.
        expect(roundTripped!.template.toMap(), original.toMap());
        expect(roundTripped.schemaVersion, 1);
        expect(roundTripped.templateVersion, 3);
        expect(roundTripped.enabled, isTrue);
        expect(roundTripped.createdAt, DateTime.utc(2026, 1, 1));
        expect(roundTripped.updatedAt, DateTime.utc(2026, 6, 1));
        expect(roundTripped.description, 'test description');
        expect(roundTripped.tags, <String>['ambiente', 'sala']);
      });

      test(
        '$templateId wrapped as "remote" reproduces the exact local structure '
        '(TABLERO/TABLA parity proof)',
        () {
          final DeviceTemplate local = getTemplateById(templateId)!;
          final DeviceTemplateRecord asRemote = DeviceTemplateRecord(
            template: local,
            schemaVersion: 1,
            templateVersion: 1,
            enabled: true,
          );
          final DeviceTemplateRecord? parsedBack = DeviceTemplateRecord.fromMap(
            asRemote.toMap(),
          );

          // Byte-identical structure -> DeviceBoardRenderer/DeviceTableRenderer
          // (already tested against arbitrary DeviceTemplate instances) render
          // identically for a "remote" template built from today's local data.
          expect(parsedBack!.template.toMap(), local.toMap());
        },
      );
    }

    test('accepts Firestore Timestamp for createdAt/updatedAt', () {
      final DeviceTemplate local = getTemplateById('room_climate')!;
      final Map<String, Object?> map = <String, Object?>{
        ...local.toMap(),
        'schemaVersion': 1,
        'templateVersion': 1,
        'enabled': true,
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 3, 1)),
        'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 3, 2)),
      };

      final DeviceTemplateRecord? record = DeviceTemplateRecord.fromMap(map);

      expect(record, isNotNull);
      expect(record!.createdAt, DateTime.utc(2026, 3, 1));
      expect(record.updatedAt, DateTime.utc(2026, 3, 2));
    });

    test('missing enabled/templateVersion default to sensible values', () {
      final DeviceTemplate local = getTemplateById('room_climate')!;
      final Map<String, Object?> map = <String, Object?>{
        ...local.toMap(),
        'schemaVersion': 1,
      };

      final DeviceTemplateRecord? record = DeviceTemplateRecord.fromMap(map);

      expect(record, isNotNull);
      expect(record!.enabled, isTrue);
      expect(record.templateVersion, 1);
      expect(record.createdAt, isNull);
      expect(record.tags, isEmpty);
    });
  });

  group('DeviceTemplateRecord defensive parsing', () {
    test('schemaVersion greater than supported returns null', () {
      final DeviceTemplate local = getTemplateById('room_climate')!;
      final Map<String, Object?> map = <String, Object?>{
        ...local.toMap(),
        'schemaVersion': supportedDeviceTemplateSchemaVersion + 1,
        'templateVersion': 1,
        'enabled': true,
      };

      expect(DeviceTemplateRecord.fromMap(map), isNull);
    });

    test('missing schemaVersion returns null', () {
      final DeviceTemplate local = getTemplateById('room_climate')!;
      final Map<String, Object?> map = <String, Object?>{
        ...local.toMap(),
        'templateVersion': 1,
        'enabled': true,
      };

      expect(DeviceTemplateRecord.fromMap(map), isNull);
    });

    test('a duplicated metric key (structurally invalid) returns null', () {
      final DeviceTemplate local = getTemplateById('room_climate')!;
      final Map<String, Object?> map = local.toMap();
      final List<Object?> metrics = List<Object?>.from(
        map['metrics']! as List<Object?>,
      );
      metrics.add(metrics.first); // duplicate key -> DeviceTemplate throws
      final Map<String, Object?> invalid = <String, Object?>{
        ...map,
        'metrics': metrics,
        'schemaVersion': 1,
        'templateVersion': 1,
        'enabled': true,
      };

      expect(DeviceTemplateRecord.fromMap(invalid), isNull);
    });

    test('a dangling boardSlot.metricKey reference returns null', () {
      final DeviceTemplate local = getTemplateById('room_climate')!;
      final Map<String, Object?> map = local.toMap();
      final List<Object?> boardSlots = List<Object?>.from(
        map['boardSlots']! as List<Object?>,
      );
      final Map<String, Object?> badSlot = Map<String, Object?>.from(
        boardSlots.first! as Map<String, Object?>,
      );
      badSlot['metricKey'] = 'does_not_exist';
      final Map<String, Object?> invalid = <String, Object?>{
        ...map,
        'boardSlots': <Object?>[badSlot, ...boardSlots.skip(1)],
        'schemaVersion': 1,
        'templateVersion': 1,
        'enabled': true,
      };

      expect(DeviceTemplateRecord.fromMap(invalid), isNull);
    });

    test('an unrecognized enum value (e.g. boardPreset) returns null', () {
      final DeviceTemplate local = getTemplateById('room_climate')!;
      final Map<String, Object?> invalid = <String, Object?>{
        ...local.toMap(),
        'boardPreset': 'not_a_real_preset',
        'schemaVersion': 1,
        'templateVersion': 1,
        'enabled': true,
      };

      expect(DeviceTemplateRecord.fromMap(invalid), isNull);
    });
  });
}
