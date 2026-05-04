import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';

class SiteDocument {
  const SiteDocument({
    required this.siteId,
    required this.technicalId,
    required this.name,
    required this.backendUrl,
    required this.active,
  });

  final String siteId;
  final String technicalId;
  final String name;
  final String? backendUrl;
  final bool active;

  bool get hasValidName => name.trim().isNotEmpty;
  bool get hasValidTechnicalId => technicalId == siteId;
  bool get hasValidActiveBackend =>
      !active || (backendUrl != null && backendUrl!.trim().isNotEmpty);
  bool get isValidActiveSite =>
      active && hasValidName && hasValidTechnicalId && hasValidActiveBackend;
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
      final DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore
          .instance
          .doc(path)
          .get();
      if (!doc.exists) {
        debugPrint('[SiteConfig] site not found path=$path — using fallback');
        return null;
      }
      final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
      final SiteDocument site = _siteFromData(doc.id, data);
      _logSiteValidation(site, path: path);
      return site;
    } catch (error) {
      debugPrint('[SiteConfig] fetchSite error path=$path error=$error');
      return null;
    }
  }

  SiteDocument fallbackSingleSite({required String siteId}) {
    final String normalizedSiteId = siteId.trim();
    return SiteDocument(
      siteId: normalizedSiteId,
      technicalId: normalizedSiteId,
      name: normalizedSiteId,
      backendUrl: null,
      active: true,
    );
  }

  SiteDocument _siteFromData(String siteId, Map<String, dynamic> data) {
    final String technicalId =
        data['technicalId']?.toString().trim().isNotEmpty == true
        ? data['technicalId'].toString().trim()
        : siteId;
    final String name = data['name']?.toString().trim() ?? '';
    final String? backendUrl = data['backendUrl']?.toString().trim();
    return SiteDocument(
      siteId: siteId,
      technicalId: technicalId,
      name: name.isEmpty ? siteId : name,
      backendUrl: backendUrl?.isEmpty == true ? null : backendUrl,
      active: data['active'] == true,
    );
  }

  void _logSiteValidation(SiteDocument site, {required String path}) {
    if (site.hasValidName &&
        site.hasValidTechnicalId &&
        site.hasValidActiveBackend) {
      return;
    }
    debugPrint(
      '[SiteConfig] invalid site config path=$path '
      'nameValid=${site.hasValidName} '
      'technicalIdValid=${site.hasValidTechnicalId} '
      'activeBackendValid=${site.hasValidActiveBackend}',
    );
  }

  Future<List<SiteDocument>> fetchActiveSitesForUser({
    required String tenantId,
    required List<String> allowedSiteIds,
  }) async {
    if (allowedSiteIds.isEmpty) {
      debugPrint(
        '[SiteConfig] no allowedSiteIds for tenant=$tenantId — access requires at least one assigned site',
      );
      return const <SiteDocument>[];
    }
    debugPrint(
      '[SiteConfig] fetchActiveSitesForUser tenant=$tenantId sites=$allowedSiteIds',
    );
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection(FirestorePaths.tenantSitesCollection(tenantId))
          .where('active', isEqualTo: true)
          .get();

      final List<SiteDocument> sites = snap.docs
          .where(
            (DocumentSnapshot<Map<String, dynamic>> doc) =>
                allowedSiteIds.contains(doc.id),
          )
          .map((DocumentSnapshot<Map<String, dynamic>> doc) {
            final Map<String, dynamic> data =
                (doc as QueryDocumentSnapshot<Map<String, dynamic>>).data();
            final SiteDocument site = _siteFromData(doc.id, data);
            _logSiteValidation(
              site,
              path: FirestorePaths.siteDoc(tenantId, doc.id),
            );
            return site;
          })
          .where((SiteDocument site) => site.isValidActiveSite)
          .toList();

      if (sites.isEmpty) {
        final String fallbackSiteId = allowedSiteIds.first;
        debugPrint(
          '[SiteConfig] no valid active site docs for tenant=$tenantId — using explicit single-site fallback siteId=$fallbackSiteId',
        );
        return <SiteDocument>[fallbackSingleSite(siteId: fallbackSiteId)];
      }

      return sites;
    } catch (error) {
      final String fallbackSiteId = allowedSiteIds.first;
      debugPrint(
        '[SiteConfig] fetchActiveSitesForUser error tenant=$tenantId error=$error — using explicit single-site fallback siteId=$fallbackSiteId',
      );
      return <SiteDocument>[fallbackSingleSite(siteId: fallbackSiteId)];
    }
  }
}
