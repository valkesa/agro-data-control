import 'package:agro_data_control/models/hierarchical_alert_config.dart';
import 'package:agro_data_control/services/hierarchical_alert_config_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

// Pure test of the diff/payload builders — no live Firestore instance
// needed. `FieldValue` overrides `==` by comparing its underlying delegate,
// so `FieldValue.delete() == FieldValue.delete()` is a reliable check.
bool _isDelete(Object? value) => value == FieldValue.delete();

void main() {
  group(
    'buildAlertConfigCreatePayload — documento nuevo, para .set(merge:true)',
    () {
      test('incluye createdAt/createdBy/updatedAt/updatedBy', () {
        final Map<String, Object?>? payload = buildAlertConfigCreatePayload(
          desired: const AlertConfigOverride(enabled: true),
          uid: 'admin-a',
        );
        expect(payload, isNotNull);
        expect(payload!['enabled'], true);
        expect(payload['createdBy'], 'admin-a');
        expect(payload['updatedBy'], 'admin-a');
        expect(payload.containsKey('createdAt'), isTrue);
        expect(payload.containsKey('updatedAt'), isTrue);
        expect(payload['schemaVersion'], 1);
      });

      test('thresholds va como mapa anidado real, sin claves punteadas', () {
        final Map<String, Object?>? payload = buildAlertConfigCreatePayload(
          desired: const AlertConfigOverride(
            thresholds: AlertThresholds(min: 20, max: 30),
          ),
          uid: 'admin-a',
        );
        expect(payload, isNotNull);
        expect(payload!['thresholds'], {'min': 20.0, 'max': 30.0});
        expect(payload.containsKey('thresholds.min'), isFalse);
      });

      test('sin ningún campo funcional, no genera payload (null)', () {
        final Map<String, Object?>? payload = buildAlertConfigCreatePayload(
          desired: AlertConfigOverride.empty,
          uid: 'admin-a',
        );
        expect(payload, isNull);
      });
    },
  );

  group(
    'buildAlertConfigUpdatePayload — documento existente, para .update() — Etapa B5 §21/§23 (hallazgo B4.1)',
    () {
      test('NUNCA incluye createdAt/createdBy', () {
        final Map<String, Object?>? payload = buildAlertConfigUpdatePayload(
          current: const AlertConfigOverride(enabled: true),
          desired: const AlertConfigOverride(enabled: false),
          uid: 'admin-b',
        );
        expect(payload, isNotNull);
        expect(payload!.containsKey('createdAt'), isFalse);
        expect(payload.containsKey('createdBy'), isFalse);
        expect(payload['updatedBy'], 'admin-b');
      });

      test(
        '"Heredar" (desired null) borra el campo con FieldValue.delete()',
        () {
          final Map<String, Object?>? payload = buildAlertConfigUpdatePayload(
            current: const AlertConfigOverride(enabled: true),
            desired: const AlertConfigOverride(enabled: null),
            uid: 'admin-a',
          );
          expect(payload, isNotNull);
          expect(_isDelete(payload!['enabled']), isTrue);
        },
      );

      test('sin cambios reales, no genera payload (null)', () {
        final Map<String, Object?>? payload = buildAlertConfigUpdatePayload(
          current: const AlertConfigOverride(enabled: true, order: 3),
          desired: const AlertConfigOverride(enabled: true, order: 3),
          uid: 'admin-a',
        );
        expect(payload, isNull);
      });

      test(
        'threshold parcial: usa field-path punteado, no toca hermanos ni reemplaza el mapa',
        () {
          final Map<String, Object?>? payload = buildAlertConfigUpdatePayload(
            current: const AlertConfigOverride(
              thresholds: AlertThresholds(min: 20, max: 30),
            ),
            desired: const AlertConfigOverride(
              thresholds: AlertThresholds(min: 20, max: 28),
            ),
            uid: 'admin-a',
          );
          expect(payload, isNotNull);
          // Clave punteada de nivel superior: solo `.update()` la interpreta
          // como FieldPath anidado (`FieldPath.fromString` divide por '.').
          // `.set(merge:true)` la trataría como el nombre LITERAL de un
          // campo — por eso este payload es exclusivo de `.update()`.
          expect(payload!['thresholds.max'], 28);
          expect(payload.containsKey('thresholds.min'), isFalse);
          expect(payload.containsKey('thresholds'), isFalse);
        },
      );

      test(
        'quitar el último threshold borra el mapa completo, no dotted-path',
        () {
          final Map<String, Object?>? payload = buildAlertConfigUpdatePayload(
            current: const AlertConfigOverride(
              thresholds: AlertThresholds(max: 28),
            ),
            desired: const AlertConfigOverride(
              thresholds: AlertThresholds.empty,
            ),
            uid: 'admin-a',
          );
          expect(payload, isNotNull);
          expect(_isDelete(payload!['thresholds']), isTrue);
          expect(payload.containsKey('thresholds.max'), isFalse);
        },
      );

      test(
        'siempre incluye schemaVersion=1 y updatedAt cuando hay cambios',
        () {
          final Map<String, Object?>? payload = buildAlertConfigUpdatePayload(
            current: AlertConfigOverride.empty,
            desired: const AlertConfigOverride(order: 5),
            uid: 'owner-uid',
          );
          expect(payload, isNotNull);
          expect(payload!['schemaVersion'], 1);
          expect(payload.containsKey('updatedAt'), isTrue);
        },
      );
    },
  );
}
