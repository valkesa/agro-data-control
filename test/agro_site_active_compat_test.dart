// Tests for keeping AgroSite creation aligned with the current structural
// schema. Legacy site fields are intentionally excluded from new writes.
//
// No Firestore emulator is wired into this project, so:
//   - the create/update PAYLOAD shape is tested directly (pure functions,
//     no network call needed)
//   - the firestore.rules TEXT is checked for the exact clauses this fix
//     depends on, as a cheap regression guard against someone reverting
//     the rule without reverting the code (or vice versa). This is a
//     text-level check, not a rule-evaluation test — there's no emulator
//     here to actually execute the rules.
import 'dart:io';

import 'package:agro_data_control/models/agro_site.dart';
import 'package:agro_data_control/services/agro_site_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Creation payload uses only current schema fields', () {
    test('buildAgroSiteCreatePayload excludes legacy site fields', () {
      final Map<String, Object?> payload = buildAgroSiteCreatePayload(
        tenantId: 'the-gene-pig',
        siteId: 'main_site',
        name: 'Establecimiento principal',
      );

      expect(payload['name'], 'Establecimiento principal');
      expect(payload['enabled'], isTrue);
      expect(
        payload['provisioningStatus'],
        SiteProvisioningStatus.pendingBackend,
      );
      expect(payload.containsKey('createdAt'), isTrue);
      expect(payload.containsKey('updatedAt'), isTrue);
      for (final String legacyField in <String>[
        'active',
        'technicalId',
        'backendUrl',
      ]) {
        expect(payload.containsKey(legacyField), isFalse);
      }
    });
  });

  group('Update payload never includes active', () {
    test('AgroSite.toUpdatePayload has no active key', () {
      const AgroSite site = AgroSite(
        id: 'main_site',
        tenantId: 'the-gene-pig',
        name: 'Establecimiento principal',
        description: '',
        enabled: true,
        provisioningStatus: SiteProvisioningStatus.pendingBackend,
        createdAt: null,
        updatedAt: null,
      );

      final Map<String, Object?> payload = site.toUpdatePayload();

      expect(payload.containsKey('active'), isFalse);
    });
  });

  group('Legacy fields are never touched by either payload', () {
    test(
      'create and update payloads never mention technicalId/backendUrl '
      '(preservation relies on SetOptions(merge: true) + these fields simply '
      'never appearing in the payload — not on AgroSite reading them back)',
      () {
        final Map<String, Object?> createPayload = buildAgroSiteCreatePayload(
          tenantId: 'the-gene-pig',
          siteId: 'main_site',
          name: 'Establecimiento principal',
        );
        const AgroSite site = AgroSite(
          id: 'main_site',
          tenantId: 'the-gene-pig',
          name: 'Establecimiento principal',
          description: '',
          enabled: true,
          provisioningStatus: SiteProvisioningStatus.pendingBackend,
          createdAt: null,
          updatedAt: null,
        );
        final Map<String, Object?> updatePayload = site.toUpdatePayload();

        for (final String legacyField in <String>[
          'technicalId',
          'backendUrl',
        ]) {
          expect(createPayload.containsKey(legacyField), isFalse);
          expect(updatePayload.containsKey(legacyField), isFalse);
        }
      },
    );
  });

  group('firestore.rules text matches this fix', () {
    late String rulesSource;

    setUpAll(() {
      rulesSource = File('firestore.rules').readAsStringSync();
    });

    test('sites/{siteId} create allows only current AgroSite fields', () {
      final int siteBlockStart = rulesSource.indexOf('match /sites/{siteId}');
      final int legacyBlockStart = rulesSource.indexOf(
        'match /plcs/{plcId}',
        siteBlockStart,
      );
      final String siteRules = rulesSource.substring(
        siteBlockStart,
        legacyBlockStart,
      );

      expect(
        siteRules,
        contains(
          "'name',\n                'description',\n                'enabled',\n                'provisioningStatus',\n                'createdAt',\n                'updatedAt'",
        ),
      );
      expect(
        siteRules,
        contains(
          "request.resource.data.provisioningStatus == 'pending_backend'",
        ),
      );
      expect(siteRules, isNot(contains('request.resource.data.active')));
    });

    test('sites/{siteId} update allowlist still excludes active', () {
      expect(
        rulesSource,
        contains(
          ".hasOnly(['name', 'description', 'enabled', 'provisioningStatus', 'updatedAt'])",
        ),
      );
      // The update hasOnly list must not have grown to include 'active'.
      expect(
        rulesSource,
        isNot(
          contains(
            ".hasOnly(['name', 'description', 'enabled', 'active', 'updatedAt'])",
          ),
        ),
      );
    });

    test('tenant create requires creation audit fields', () {
      expect(rulesSource, contains("'createdByUid'"));
      expect(
        rulesSource,
        contains('request.resource.data.createdByUid == request.auth.uid'),
      );
      expect(rulesSource, contains("'createdByEmail'"));
    });

    test('sector/device create validate site relation with existsAfter', () {
      expect(
        rulesSource,
        contains(
          r'existsAfter(/databases/$(database)/documents/tenants/$(tenantId)/sites/$(request.resource.data.siteId))',
        ),
      );
    });
  });
}
