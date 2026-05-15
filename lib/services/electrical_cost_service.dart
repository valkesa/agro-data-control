import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';

class ElectricalCostService {
  const ElectricalCostService();

  Future<double?> readCost({
    required String tenantId,
    required String siteId,
  }) async {
    final String path = FirestorePaths.electricalCostSettings(tenantId, siteId);
    debugPrint('[Firestore] electrical cost read path=$path');
    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await FirebaseFirestore.instance.doc(path).get();
    if (!snapshot.exists) return null;
    final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};
    final Object? value = data['costPerKw'];
    if (value is num) return value.toDouble();
    return null;
  }

  Future<void> saveCost({
    required String tenantId,
    required String siteId,
    required String userUid,
    required double costPerKw,
  }) async {
    final String path = FirestorePaths.electricalCostSettings(tenantId, siteId);
    debugPrint('[Firestore] electrical cost save path=$path costPerKw=$costPerKw');
    await FirebaseFirestore.instance.doc(path).set(<String, Object?>{
      'costPerKw': costPerKw,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': userUid,
    });
  }
}
