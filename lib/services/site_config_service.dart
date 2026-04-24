import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';

class SiteDocument {
  const SiteDocument({
    required this.siteId,
    required this.name,
    required this.backendUrl,
    required this.active,
  });

  final String siteId;
  final String name;
  final String? backendUrl;
  final bool active;
}

class SiteConfigService {
  const SiteConfigService();

  Future<SiteDocument?> fetchSite({
    required String tenantId,
    required String siteId,
  }) async {
    final String path = FirestorePaths.siteDoc(tenantId, siteId);
    debugPrint('[SiteConfig] fetchSite path=$path');
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc =
          await FirebaseFirestore.instance.doc(path).get();
      if (!doc.exists) {
        debugPrint('[SiteConfig] site not found path=$path — using fallback');
        return null;
      }
      final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
      return SiteDocument(
        siteId: doc.id,
        name: data['name']?.toString() ?? siteId,
        backendUrl: data['backendUrl']?.toString(),
        active: data['active'] == true,
      );
    } catch (error) {
      debugPrint('[SiteConfig] fetchSite error path=$path error=$error');
      return null;
    }
  }

  Future<List<SiteDocument>> fetchActiveSitesForUser({
    required String tenantId,
    required List<String> allowedSiteIds,
  }) async {
    if (allowedSiteIds.isEmpty) {
      return const <SiteDocument>[];
    }
    debugPrint(
      '[SiteConfig] fetchActiveSitesForUser tenant=$tenantId sites=$allowedSiteIds',
    );
    try {
      final QuerySnapshot<Map<String, dynamic>> snap =
          await FirebaseFirestore.instance
              .collection(FirestorePaths.tenantSitesCollection(tenantId))
              .where('active', isEqualTo: true)
              .get();

      return snap.docs
          .where(
            (DocumentSnapshot<Map<String, dynamic>> doc) =>
                allowedSiteIds.contains(doc.id),
          )
          .map((DocumentSnapshot<Map<String, dynamic>> doc) {
            final Map<String, dynamic> data =
                (doc as QueryDocumentSnapshot<Map<String, dynamic>>).data();
            return SiteDocument(
              siteId: doc.id,
              name: data['name']?.toString() ?? doc.id,
              backendUrl: data['backendUrl']?.toString(),
              active: true,
            );
          })
          .toList();
    } catch (error) {
      debugPrint(
        '[SiteConfig] fetchActiveSitesForUser error tenant=$tenantId error=$error',
      );
      return const <SiteDocument>[];
    }
  }
}
