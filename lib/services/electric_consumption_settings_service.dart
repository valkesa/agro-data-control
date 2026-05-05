import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';
import '../models/electric_consumption_settings.dart';

class ElectricConsumptionSettingsService {
  const ElectricConsumptionSettingsService();

  Future<ElectricConsumptionSettings> readSettings({
    required String tenantId,
    required String siteId,
    required String plcId,
  }) async {
    final String path = FirestorePaths.plcElectricalConsumptionSettings(
      tenantId: tenantId,
      siteId: siteId,
      plcId: plcId,
    );
    debugPrint('[Firestore] electrical consumption read started path=$path');

    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await FirebaseFirestore.instance.doc(path).get();
    if (!snapshot.exists) {
      return const ElectricConsumptionSettings.defaults();
    }
    return ElectricConsumptionSettings.fromFirestore(
      snapshot.data() ?? <String, dynamic>{},
    );
  }

  Future<void> saveSettings({
    required String tenantId,
    required String siteId,
    required String plcId,
    required String userUid,
    required ElectricConsumptionSettings settings,
  }) async {
    final String path = FirestorePaths.plcElectricalConsumptionSettings(
      tenantId: tenantId,
      siteId: siteId,
      plcId: plcId,
    );
    debugPrint('[Firestore] electrical consumption save started path=$path');

    await FirebaseFirestore.instance.doc(path).set(<String, Object?>{
      ...settings.toFirestore(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': userUid,
    });
  }
}
