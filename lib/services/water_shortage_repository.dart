import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase/firestore_paths.dart';
import '../models/water_shortage_summary.dart';

class WaterShortageRepository {
  const WaterShortageRepository();

  /// Atomically records a water shortage fault event and increments all counters.
  Future<void> recordFaultEvent({
    required String tenantId,
    required String siteId,
    required String plcId,
  }) async {
    final DateTime now = DateTime.now();
    final String monthKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final Timestamp ts = Timestamp.now();
    final FirebaseFirestore db = FirebaseFirestore.instance;

    final String rootPath = FirestorePaths.waterShortageMetricsRoot(
      tenantId: tenantId,
      siteId: siteId,
      plcId: plcId,
    );

    final WriteBatch batch = db.batch();

    // New event document (auto-ID).
    final DocumentReference eventRef =
        db.collection('$rootPath/events').doc();
    batch.set(eventRef, {
      'timestamp': ts,
      'monthKey': monthKey,
    });

    // Summary document: increment total, update timestamp.
    final DocumentReference summaryRef = db.doc(rootPath);
    batch.set(
      summaryRef,
      {
        'totalEvents': FieldValue.increment(1),
        'updatedAt': ts,
      },
      SetOptions(merge: true),
    );

    // Monthly document: increment count, record last event timestamp.
    final DocumentReference monthRef =
        db.doc('$rootPath/monthly/$monthKey');
    batch.set(
      monthRef,
      {
        'monthKey': monthKey,
        'eventCount': FieldValue.increment(1),
        'lastEventAt': ts,
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  /// Fetches the total event count and the current-month event count.
  Future<WaterShortageSummary> fetchSummary({
    required String tenantId,
    required String siteId,
    required String plcId,
  }) async {
    final DateTime now = DateTime.now();
    final String monthKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';

    final FirebaseFirestore db = FirebaseFirestore.instance;
    final String rootPath = FirestorePaths.waterShortageMetricsRoot(
      tenantId: tenantId,
      siteId: siteId,
      plcId: plcId,
    );

    final List<DocumentSnapshot<Map<String, dynamic>>> results =
        await Future.wait([
          db.doc(rootPath).get(),
          db.doc('$rootPath/monthly/$monthKey').get(),
        ]);

    final DocumentSnapshot<Map<String, dynamic>> summaryDoc = results[0];
    final DocumentSnapshot<Map<String, dynamic>> monthDoc = results[1];

    final int totalEvents = summaryDoc.exists
        ? (summaryDoc.data()?['totalEvents'] as int? ?? 0)
        : 0;
    final int monthEvents = monthDoc.exists
        ? (monthDoc.data()?['eventCount'] as int? ?? 0)
        : 0;

    return WaterShortageSummary(
      totalEvents: totalEvents,
      monthEvents: monthEvents,
      monthKey: monthKey,
    );
  }
}
