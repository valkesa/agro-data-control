import 'package:cloud_firestore/cloud_firestore.dart';

import '../device_capabilities/device_capability_profile.dart';
import '../firebase/firestore_paths.dart';
import 'firestore_timestamp_adapter.dart';
import 'firestore_version_conflict.dart';

/// N7.1 §2/§4/§13 — persistence for `capabilityProfiles/{id}`, global
/// config (§3). [DeviceCapabilityProfile] already carries its own
/// `enabled`/`profileVersion` (N6.5.2), so — unlike the metric/indicator
/// libraries — no separate Record envelope is needed here; the domain
/// object is the persisted shape directly, same as [BoardPresetRepository].
///
/// `createdAt`/`updatedAt` are tracked here in the repository layer (not on
/// [DeviceCapabilityProfile] itself, which predates N7.1 and has no
/// timestamp fields) by round-tripping them through the same map this
/// repository reads/writes — `fetchOne`/`fetchAll` attach them onto a
/// [CapabilityProfileRecord] alongside the parsed profile.
class CapabilityProfileRepository {
  const CapabilityProfileRepository({FirebaseFirestore? firestore})
    : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get firestore => _firestore ?? FirebaseFirestore.instance;

  static const List<String> _timestampFields = ['createdAt', 'updatedAt'];

  Future<List<CapabilityProfileRecord>> fetchAll() async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await firestore
        .collection(FirestorePaths.capabilityProfilesCollection())
        .get();
    final List<CapabilityProfileRecord> results = <CapabilityProfileRecord>[];
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in snapshot.docs) {
      final CapabilityProfileRecord? record = _tryParse(doc.data());
      if (record != null) results.add(record);
    }
    return results;
  }

  Future<CapabilityProfileRecord?> fetchOne(String profileId) async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await firestore
        .doc(FirestorePaths.capabilityProfileDoc(profileId))
        .get();
    if (!snapshot.exists) return null;
    return _tryParse(snapshot.data() ?? <String, Object?>{});
  }

  Future<void> create(DeviceCapabilityProfile profile) async {
    final DocumentReference<Map<String, dynamic>> reference = firestore.doc(
      FirestorePaths.capabilityProfileDoc(profile.id),
    );
    if ((await reference.get()).exists) {
      throw StateError(
        'Ya existe un CapabilityProfile con id "${profile.id}".',
      );
    }
    await reference.set(<String, Object?>{
      ...profile.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<int> save({
    required DeviceCapabilityProfile profile,
    required int expectedVersion,
  }) {
    final DocumentReference<Map<String, dynamic>> reference = firestore.doc(
      FirestorePaths.capabilityProfileDoc(profile.id),
    );
    return firestore.runTransaction<int>((Transaction transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await transaction
          .get(reference);
      if (!snapshot.exists) {
        throw StateError('CapabilityProfile remoto inexistente: ${profile.id}');
      }
      final int actualVersion =
          (snapshot.data()?['profileVersion'] as int?) ?? 1;
      if (actualVersion != expectedVersion) {
        throw FirestoreVersionConflict(
          entityType: 'capabilityProfile',
          entityId: profile.id,
          expectedVersion: expectedVersion,
          actualVersion: actualVersion,
        );
      }
      final int nextVersion = expectedVersion + 1;
      transaction.set(reference, <String, Object?>{
        ...profile.toMap(),
        'profileVersion': nextVersion,
        'createdAt':
            snapshot.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return nextVersion;
    });
  }

  Future<void> setEnabled(String profileId, bool enabled) async {
    await firestore.doc(FirestorePaths.capabilityProfileDoc(profileId)).set(
      <String, Object?>{
        'enabled': enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  CapabilityProfileRecord? _tryParse(Map<String, Object?> raw) {
    try {
      final Map<String, Object?> normalized = normalizeFirestoreTimestamps(
        raw,
        timestampFields: _timestampFields,
      );
      return CapabilityProfileRecord(
        profile: DeviceCapabilityProfile.fromMap(normalized),
        createdAt: normalized['createdAt'] is String
            ? DateTime.parse(normalized['createdAt']! as String)
            : null,
        updatedAt: normalized['updatedAt'] is String
            ? DateTime.parse(normalized['updatedAt']! as String)
            : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// [DeviceCapabilityProfile] plus the persistence-only timestamps it
/// doesn't carry itself — see [CapabilityProfileRepository]'s doc comment.
class CapabilityProfileRecord {
  const CapabilityProfileRecord({
    required this.profile,
    this.createdAt,
    this.updatedAt,
  });

  final DeviceCapabilityProfile profile;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}
