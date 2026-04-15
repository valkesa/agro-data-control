import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';

class TenantMembershipService {
  const TenantMembershipService();

  Future<TenantMembershipLookupResult> readMembership({
    required String tenantId,
    required String uid,
  }) async {
    final String path = FirestorePaths.tenantMemberDoc(tenantId, uid);
    debugPrint('[Firestore] membership read started path=$path');

    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance.doc(path).get();

      if (!snapshot.exists) {
        debugPrint('[Firestore] membership missing path=$path');
        return const TenantMembershipLookupResult.notFound();
      }

      final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};
      final bool active = data['active'] == true;
      debugPrint(
        '[Firestore] membership read success tenantId=$tenantId uid=$uid active=$active data=$data',
      );

      if (!active) {
        return TenantMembershipLookupResult.inactive(
          tenantId: tenantId,
          role: data['role']?.toString(),
          rawData: data,
        );
      }

      return TenantMembershipLookupResult.success(
        tenantId: tenantId,
        role: data['role']?.toString(),
        rawData: data,
      );
    } catch (error, stackTrace) {
      debugPrint('[Firestore] membership read error path=$path error=$error');
      debugPrint('[Firestore] membership read error stack=$stackTrace');
      return TenantMembershipLookupResult.error(error.toString());
    }
  }
}

class TenantMembershipLookupResult {
  const TenantMembershipLookupResult({
    required this.tenantId,
    required this.role,
    required this.rawData,
    required this.errorMessage,
    required this.exists,
    required this.active,
  });

  const TenantMembershipLookupResult.notFound()
    : tenantId = null,
      role = null,
      rawData = const <String, dynamic>{},
      errorMessage = null,
      exists = false,
      active = false;

  const TenantMembershipLookupResult.error(this.errorMessage)
    : tenantId = null,
      role = null,
      rawData = const <String, dynamic>{},
      exists = false,
      active = false;

  const TenantMembershipLookupResult.success({
    required this.tenantId,
    required this.role,
    required this.rawData,
  }) : errorMessage = null,
       exists = true,
       active = true;

  const TenantMembershipLookupResult.inactive({
    required this.tenantId,
    required this.role,
    required this.rawData,
  }) : errorMessage = null,
       exists = true,
       active = false;

  final String? tenantId;
  final String? role;
  final Map<String, dynamic> rawData;
  final String? errorMessage;
  final bool exists;
  final bool active;

  bool get hasError => errorMessage != null;
}
