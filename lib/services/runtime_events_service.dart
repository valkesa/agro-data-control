import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase/firestore_paths.dart';
import '../models/runtime_event_record.dart';

class RuntimeEventsService {
  const RuntimeEventsService({FirebaseFirestore? firestore})
    : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  Future<List<RuntimeEventRecord>> fetchRecent({
    required String tenantId,
    required String siteId,
    required String plcId,
    int limit = 200,
  }) async {
    final String path = FirestorePaths.runtimeEventsCollection(
      tenantId: tenantId,
      siteId: siteId,
      plcId: plcId,
    );
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _db
        .collection(path)
        .orderBy('startedAt', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs
        .map(
          (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
              RuntimeEventRecord.fromFirestore(doc.data(), doc.id),
        )
        .whereType<RuntimeEventRecord>()
        .toList(growable: false);
  }
}
