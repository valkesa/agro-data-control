import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control_backend/src/auth_claims_policy.dart';
import 'package:agro_data_control_backend/src/firebase_custom_claims_service.dart';
import 'package:args/args.dart';

Future<void> main(List<String> args) async {
  final ArgParser parser = ArgParser()
    ..addFlag(
      'dry-run',
      defaultsTo: false,
      help: 'Valida y muestra resultados sin escribir custom claims.',
    )
    ..addOption('tenant', help: 'Procesa solo usuarios del tenant indicado.')
    ..addOption('uid', help: 'Procesa solo el usuario indicado.')
    ..addOption(
      'config',
      defaultsTo: 'backend/config/sites/default.json',
      help: 'Ruta al archivo de config del backend.',
    )
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults parsed = parser.parse(args);
  if (parsed['help'] == true) {
    stdout.writeln(parser.usage);
    return;
  }

  final String configPath = parsed['config'] as String;
  final Map<String, dynamic> config =
      jsonDecode(File(configPath).readAsStringSync()) as Map<String, dynamic>;
  final Map<String, dynamic> runtimeEvents =
      config['runtimeEvents'] as Map<String, dynamic>? ?? <String, dynamic>{};

  final String projectId =
      runtimeEvents['firestoreProjectId']?.toString() ??
      Platform.environment['FIRESTORE_PROJECT_ID'] ??
      '';
  final String databaseId =
      runtimeEvents['firestoreDatabaseId']?.toString() ?? '(default)';
  final String serviceAccountPath =
      runtimeEvents['firestoreServiceAccountPath']?.toString() ??
      Platform.environment['GOOGLE_APPLICATION_CREDENTIALS'] ??
      '';

  final bool dryRun = parsed['dry-run'] as bool;
  final String? tenant = parsed['tenant'] as String?;
  final String? uid = parsed['uid'] as String?;

  final FirebaseCustomClaimsService service = FirebaseCustomClaimsService(
    projectId: projectId,
    databaseId: databaseId,
    serviceAccountJsonPath: serviceAccountPath,
  );

  final List<String> userIds = await service.listUserIds(
    tenantId: tenant,
    uid: uid,
  );

  int processed = 0;
  int updated = 0;
  int skipped = 0;
  int errors = 0;

  stdout.writeln(
    '[claims-backfill] users=${userIds.length} tenant=${tenant ?? ''} uid=${uid ?? ''} dryRun=$dryRun',
  );

  for (final String userId in userIds) {
    try {
      final PersistedUserAccessProfile profile = await service.readUserProfile(
        userId,
      );
      final String requesterTenantId = profile.activeTenantId ?? '';
      if (requesterTenantId.isEmpty &&
          profile.active &&
          profile.role != AgroDataRole.pending) {
        skipped += 1;
        stdout.writeln(
          '[claims-backfill] skipped uid=$userId reason=missing_tenant',
        );
        continue;
      }
      final CustomClaimsSyncResult result = await service.syncUserClaims(
        targetUid: userId,
        requesterUid: 'manual-backfill',
        requesterRole: AgroDataRole.owner,
        requesterTenantId: requesterTenantId,
        dryRun: dryRun,
      );
      processed += 1;
      if (result.changed) {
        updated += 1;
      } else {
        skipped += 1;
      }
      stdout.writeln(
        '[claims-backfill] ok uid=$userId role=${result.role} tenant=${result.activeTenantId ?? ''} sites=${result.allowedSiteCount} changed=${result.changed}',
      );
    } catch (error) {
      errors += 1;
      stdout.writeln('[claims-backfill] error uid=$userId error=$error');
    }
  }

  stdout.writeln(
    '[claims-backfill] done processed=$processed updated=$updated skipped=$skipped errors=$errors dryRun=$dryRun',
  );
}
