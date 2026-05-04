import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';
import '../models/plc_display_config.dart';

class SitePlcConfigService {
  const SitePlcConfigService();

  /// Fetches active PLCs for a site, ordered by sortOrder then plcId.
  /// Returns empty list if the collection does not exist or on error (safe fallback).
  Future<List<PlcDisplayConfig>> fetchActivePlcs({
    required String tenantId,
    required String siteId,
  }) async {
    final String path = FirestorePaths.plcsCollection(tenantId, siteId);
    debugPrint('[SitePlcConfig] fetchActivePlcs path=$path');
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection(path)
          .where('active', isEqualTo: true)
          .get();

      if (snap.docs.isEmpty) {
        debugPrint('[SitePlcConfig] no active plcs found at $path');
        return const <PlcDisplayConfig>[];
      }

      final List<PlcDisplayConfig> configs =
          snap.docs.map((doc) => _plcFromData(doc.id, doc.data())).toList()
            ..sort((a, b) {
              final int cmp = a.sortOrder.compareTo(b.sortOrder);
              return cmp != 0 ? cmp : a.plcId.compareTo(b.plcId);
            });

      debugPrint(
        '[SitePlcConfig] loaded ${configs.length} plcs: ${configs.map((p) => '${p.plcId}(${p.columnLabel})').join(', ')}',
      );
      return configs;
    } catch (error) {
      debugPrint(
        '[SitePlcConfig] fetchActivePlcs error path=$path error=$error — returning empty list',
      );
      return const <PlcDisplayConfig>[];
    }
  }

  /// Updates only the display name of a site document.
  Future<void> updateSiteName({
    required String tenantId,
    required String siteId,
    required String name,
  }) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final String path = FirestorePaths.siteDoc(tenantId, siteId);
    await FirebaseFirestore.instance.doc(path).update(<String, Object?>{
      'name': trimmed,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    debugPrint('[SitePlcConfig] updated site name path=$path name=$trimmed');
  }

  /// Updates the visual display fields (displayName, columnLabel) of a PLC document.
  /// Creates the document if it does not exist, preserving the technical fields.
  Future<void> updatePlcDisplayConfig({
    required String tenantId,
    required String siteId,
    required String plcId,
    required String displayName,
    required String columnLabel,
  }) async {
    final String displayNameTrimmed = displayName.trim();
    final String columnLabelTrimmed = columnLabel.trim();
    if (displayNameTrimmed.isEmpty || columnLabelTrimmed.isEmpty) return;
    final String path = FirestorePaths.plcConfigDoc(tenantId, siteId, plcId);
    await FirebaseFirestore.instance.doc(path).set({
      'displayName': displayNameTrimmed,
      'columnLabel': columnLabelTrimmed,
      'technicalId': plcId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    debugPrint(
      '[SitePlcConfig] updated plc display config path=$path displayName=$displayNameTrimmed columnLabel=$columnLabelTrimmed',
    );
  }

  PlcDisplayConfig _plcFromData(String plcId, Map<String, dynamic> data) {
    final String technicalId =
        data['technicalId']?.toString().trim().isNotEmpty == true
        ? data['technicalId'].toString().trim()
        : plcId;

    final String rawColumn = data['columnLabel']?.toString().trim() ?? '';
    final String columnLabel = rawColumn.isNotEmpty ? rawColumn : plcId;

    final String rawDisplay = data['displayName']?.toString().trim() ?? '';
    final String displayName = rawDisplay.isNotEmpty ? rawDisplay : columnLabel;

    final int sortOrder = data['sortOrder'] is num
        ? (data['sortOrder'] as num).toInt()
        : 999;

    return PlcDisplayConfig(
      plcId: plcId,
      displayName: displayName,
      columnLabel: columnLabel,
      technicalId: technicalId,
      active: data['active'] == true,
      sortOrder: sortOrder,
    );
  }
}
