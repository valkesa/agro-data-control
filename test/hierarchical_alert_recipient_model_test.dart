import 'package:agro_data_control/models/hierarchical_alert_catalog.dart';
import 'package:agro_data_control/models/hierarchical_alert_recipient.dart';
import 'package:flutter_test/flutter_test.dart';

AlertRecipientOverride _override({
  required String id,
  required String name,
  required String phone,
  bool enabled = true,
}) {
  return AlertRecipientOverride(
    id: id,
    displayName: name,
    phoneE164: phone,
    enabled: enabled,
  );
}

void main() {
  group(
    'normalizeAlertRecipientPhoneE164 / isValidAlertRecipientPhoneE164',
    () {
      test('agrega + y deja solo dígitos', () {
        expect(
          normalizeAlertRecipientPhoneE164('+54 9 11-2304-0959'),
          '+5491123040959',
        );
      });

      test('cadena vacía normaliza a vacío', () {
        expect(normalizeAlertRecipientPhoneE164(''), '');
      });

      test('valida longitud E.164 (8-15 dígitos)', () {
        expect(isValidAlertRecipientPhoneE164('+5491123040959'), isTrue);
        expect(isValidAlertRecipientPhoneE164('+123'), isFalse);
        expect(
          isValidAlertRecipientPhoneE164('5491123040959'),
          isFalse,
        ); // sin '+'
      });
    },
  );

  group('resolveHierarchicalAlertRecipients — precedencia y dedup', () {
    test('Room > Device > Site > Tenant, dedup por teléfono (Etapa B4.5)', () {
      final List<HierarchicalAlertRecipient>
      resolved = resolveHierarchicalAlertRecipients(
        tenant: [
          _override(id: 't1', name: 'Gerardo Tenant', phone: '+5491138267368'),
        ],
        site: [_override(id: 's1', name: 'Otro', phone: '+5491111111111')],
        device: [_override(id: 'd1', name: 'Enzo', phone: '+5491123040959')],
        room: [
          _override(id: 'r1', name: 'Gerardo Room', phone: '+5491138267368'),
        ],
      );
      expect(resolved, hasLength(3)); // 4 entradas, 1 duplicado deduplicado
      final HierarchicalAlertRecipient gerardo = resolved.firstWhere(
        (r) => r.normalizedPhone == '+5491138267368',
      );
      expect(gerardo.displayName, 'Gerardo Room'); // room gana sobre tenant
      expect(gerardo.scope, AlertConfigScope.room);
    });

    test(
      'enabled=false no bloquea el mismo teléfono heredado (sin overrides negativos, §29)',
      () {
        final List<HierarchicalAlertRecipient> resolved =
            resolveHierarchicalAlertRecipients(
              tenant: [
                _override(
                  id: 't1',
                  name: 'Activo en tenant',
                  phone: '+5491111111111',
                ),
              ],
              device: [
                _override(
                  id: 'd1',
                  name: 'Deshabilitado en device',
                  phone: '+5491111111111',
                  enabled: false,
                ),
              ],
            );
        expect(resolved, hasLength(1));
        expect(resolved.single.displayName, 'Activo en tenant');
      },
    );

    test('nivel no aplicable (null) se omite sin afectar el resto', () {
      final List<HierarchicalAlertRecipient> resolved =
          resolveHierarchicalAlertRecipients(
            tenant: [
              _override(id: 't1', name: 'Gerardo', phone: '+5491138267368'),
            ],
            site: null,
            device: null,
            room: null,
          );
      expect(resolved, hasLength(1));
    });

    test('Enzo/Mauro quedan representables a nivel Device (Etapa B5 §28)', () {
      final List<HierarchicalAlertRecipient> resolved =
          resolveHierarchicalAlertRecipients(
            tenant: [
              _override(id: 'g', name: 'Gerardo', phone: '+5491138267368'),
            ],
            site: [],
            device: [
              _override(id: 'enzo', name: 'Enzo', phone: '+5491123040959'),
              _override(id: 'mauro', name: 'Mauro', phone: '+5492227516703'),
            ],
            room: null,
          );
      expect(
        resolved.map((r) => r.displayName),
        containsAll(['Enzo', 'Mauro']),
      );
      expect(
        resolved.where((r) => r.displayName == 'Enzo').single.scope,
        AlertConfigScope.device,
      );
    });
  });

  group('findInheritedConflict — Etapa B5 §27', () {
    test('detecta duplicado heredado de un scope superior', () {
      final List<HierarchicalAlertRecipient> effective = [
        const HierarchicalAlertRecipient(
          id: 't1',
          displayName: 'Gerardo',
          phoneE164: '+5491138267368',
          enabled: true,
          scope: AlertConfigScope.tenant,
        ),
      ];
      final HierarchicalAlertRecipient? conflict = findInheritedConflict(
        phoneE164: '+54 9 11 3826 7368',
        targetScope: AlertConfigScope.device,
        effectiveRecipients: effective,
      );
      expect(conflict, isNotNull);
      expect(conflict!.scope, AlertConfigScope.tenant);
    });

    test('no marca conflicto si el teléfono ya es propio del mismo scope', () {
      final List<HierarchicalAlertRecipient> effective = [
        const HierarchicalAlertRecipient(
          id: 'd1',
          displayName: 'Enzo',
          phoneE164: '+5491123040959',
          enabled: true,
          scope: AlertConfigScope.device,
        ),
      ];
      final HierarchicalAlertRecipient? conflict = findInheritedConflict(
        phoneE164: '+5491123040959',
        targetScope: AlertConfigScope.device,
        effectiveRecipients: effective,
      );
      expect(conflict, isNull);
    });

    test('sin coincidencia de teléfono, no hay conflicto', () {
      final HierarchicalAlertRecipient? conflict = findInheritedConflict(
        phoneE164: '+5491199999999',
        targetScope: AlertConfigScope.device,
        effectiveRecipients: const [],
      );
      expect(conflict, isNull);
    });
  });
}
