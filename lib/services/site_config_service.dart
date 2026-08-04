import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';
import '../models/agro_site.dart';

class TenantDocument {
  const TenantDocument({
    required this.tenantId,
    required this.name,
    required this.active,
  });

  final String tenantId;
  final String name;
  final bool active;
}

class SiteDocument {
  const SiteDocument({
    required this.siteId,
    required this.technicalId,
    required this.name,
    required this.backendUrl,
    required this.active,
    required this.enabled,
    required this.provisioningStatus,
  });

  final String siteId;
  final String technicalId;
  final String name;
  final String? backendUrl;
  final bool active;
  final bool enabled;
  final String? provisioningStatus;

  bool get hasValidName => name.trim().isNotEmpty;
  bool get hasValidTechnicalId => technicalId == siteId;
  bool get hasConfiguredBackend => backendUrl?.trim().isNotEmpty == true;
  bool get isLegacyOperationalSite =>
      provisioningStatus == null && active && hasConfiguredBackend;

  /// Architecture switch: a Site created through the new structural flow
  /// always has `provisioningStatus` set; a legacy Site never does. When
  /// true, this Site's PLC cards must come exclusively from the tenant-level
  /// `devices` collection (`AgroDevice`) — never from the legacy
  /// `sites/{siteId}/plcs` subcollection, and vice versa for legacy Sites.
  bool get usesDynamicDevices => provisioningStatus != null;
  bool get isOperational {
    if (!enabled) {
      return false;
    }
    final String? status = provisioningStatus;
    if (status != null) {
      return status == SiteProvisioningStatus.ready && hasConfiguredBackend;
    }
    return isLegacyOperationalSite;
  }

  bool get isVisibleSite => enabled && hasValidName && hasValidTechnicalId;

  String get operationalStatusLabel {
    if (!enabled) {
      return 'Deshabilitado';
    }
    final String? status = provisioningStatus;
    if (status != null) {
      return SiteProvisioningStatus.label(status);
    }
    return isLegacyOperationalSite ? 'Listo' : 'Pendiente de backend';
  }

  String get notOperationalMessage {
    return switch (provisioningStatus) {
      SiteProvisioningStatus.error => 'Error de configuración operativa',
      _ => 'Site pendiente de configuración operativa',
    };
  }

  String get notOperationalDetail {
    return switch (provisioningStatus) {
      SiteProvisioningStatus.error =>
        'La estructura del Site existe, pero la configuración operativa requiere revisión.',
      _ =>
        'La estructura del Site fue creada, pero todavía no tiene un backend operativo asociado.',
    };
  }
}

class SiteConfigService {
  const SiteConfigService();

  Future<TenantDocument?> fetchTenant({required String tenantId}) async {
    final String path = '${FirestorePaths.tenantsCollection()}/$tenantId';
    debugPrint('[SiteConfig] fetchTenant path=$path');
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore
          .instance
          .doc(path)
          .get();
      if (!doc.exists) {
        return null;
      }
      return _tenantFromData(doc.id, doc.data() ?? <String, dynamic>{});
    } catch (error) {
      debugPrint('[SiteConfig] fetchTenant error path=$path error=$error');
      return null;
    }
  }

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
      enabled: true,
      provisioningStatus: null,
    );
  }

  SiteDocument _siteFromData(String siteId, Map<String, dynamic> data) {
    final String technicalId =
        data['technicalId']?.toString().trim().isNotEmpty == true
        ? data['technicalId'].toString().trim()
        : siteId;
    final String name = data['name']?.toString().trim() ?? '';
    final String? backendUrl = data['backendUrl']?.toString().trim();
    final Object? activeRaw = data['active'];
    final Object? enabledRaw = data['enabled'];
    final String? provisioningStatus = SiteProvisioningStatus.normalize(
      data['provisioningStatus'],
    );
    return SiteDocument(
      siteId: siteId,
      technicalId: technicalId,
      name: name.isEmpty ? siteId : name,
      backendUrl: backendUrl?.isEmpty == true ? null : backendUrl,
      active: activeRaw is bool ? activeRaw : false,
      enabled: enabledRaw is bool
          ? enabledRaw
          : activeRaw is bool
          ? activeRaw
          : true,
      provisioningStatus: provisioningStatus,
    );
  }

  void _logSiteValidation(SiteDocument site, {required String path}) {
    if (site.hasValidName && site.hasValidTechnicalId) {
      return;
    }
    debugPrint(
      '[SiteConfig] invalid site config path=$path '
      'nameValid=${site.hasValidName} '
      'technicalIdValid=${site.hasValidTechnicalId}',
    );
  }

  Future<List<SiteDocument>> fetchActiveSitesForUser({
    required String tenantId,
    required List<String> allowedSiteIds,
    bool ownerBypass = false,
  }) async {
    if (allowedSiteIds.isEmpty && !ownerBypass) {
      debugPrint(
        '[SiteConfig] no allowedSiteIds for tenant=$tenantId — access requires at least one assigned site',
      );
      return const <SiteDocument>[];
    }
    debugPrint(
      '[SiteConfig] fetchActiveSitesForUser tenant=$tenantId sites=$allowedSiteIds ownerBypass=$ownerBypass',
    );
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection(FirestorePaths.tenantSitesCollection(tenantId))
          .get();

      final List<SiteDocument> sites = snap.docs
          .where(
            (DocumentSnapshot<Map<String, dynamic>> doc) =>
                ownerBypass || allowedSiteIds.contains(doc.id),
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
          .where((SiteDocument site) => site.isVisibleSite)
          .toList();

      if (sites.isEmpty) {
        if (allowedSiteIds.isNotEmpty) {
          final String fallbackSiteId = allowedSiteIds.first;
          debugPrint(
            '[SiteConfig] no valid active site docs for tenant=$tenantId — using explicit single-site fallback siteId=$fallbackSiteId',
          );
          return <SiteDocument>[fallbackSingleSite(siteId: fallbackSiteId)];
        }
        if (ownerBypass && snap.docs.isNotEmpty) {
          final String fallbackSiteId = snap.docs.first.id;
          debugPrint(
            '[SiteConfig] owner bypass: no valid active site docs for tenant=$tenantId — using any available siteId=$fallbackSiteId',
          );
          return <SiteDocument>[fallbackSingleSite(siteId: fallbackSiteId)];
        }
      }

      return sites;
    } catch (error) {
      if (allowedSiteIds.isNotEmpty) {
        final String fallbackSiteId = allowedSiteIds.first;
        debugPrint(
          '[SiteConfig] fetchActiveSitesForUser error tenant=$tenantId error=$error — using explicit single-site fallback siteId=$fallbackSiteId',
        );
        return <SiteDocument>[fallbackSingleSite(siteId: fallbackSiteId)];
      }
      debugPrint(
        '[SiteConfig] fetchActiveSitesForUser error tenant=$tenantId error=$error',
      );
      return const <SiteDocument>[];
    }
  }

  Future<List<String>> fetchAllActiveTenantIds() async {
    debugPrint('[SiteConfig] fetchAllActiveTenantIds');
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection(FirestorePaths.tenantsCollection())
          .get();
      return snap.docs
          .map((QueryDocumentSnapshot<Map<String, dynamic>> doc) => doc.id)
          .toList();
    } catch (error) {
      debugPrint('[SiteConfig] fetchAllActiveTenantIds error=$error');
      return const <String>[];
    }
  }

  Future<List<TenantDocument>> fetchActiveTenants() async {
    debugPrint('[SiteConfig] fetchActiveTenants');
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection(FirestorePaths.tenantsCollection())
          .get();
      final List<TenantDocument> tenants = snap.docs
          .map(
            (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                _tenantFromData(doc.id, doc.data()),
          )
          .where((TenantDocument tenant) => tenant.active)
          .toList();
      tenants.sort((TenantDocument a, TenantDocument b) {
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return tenants;
    } catch (error) {
      debugPrint('[SiteConfig] fetchActiveTenants error=$error');
      return const <TenantDocument>[];
    }
  }

  TenantDocument _tenantFromData(String tenantId, Map<String, dynamic> data) {
    final String name = data['name']?.toString().trim().isNotEmpty == true
        ? data['name'].toString().trim()
        : data['clientName']?.toString().trim().isNotEmpty == true
        ? data['clientName'].toString().trim()
        : tenantId;
    final Object? activeRaw = data['active'];
    return TenantDocument(
      tenantId: tenantId,
      name: name,
      active: activeRaw is bool ? activeRaw : true,
    );
  }
}
