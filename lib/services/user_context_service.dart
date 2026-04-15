import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';
import 'user_management_service.dart';

class UserContextService {
  const UserContextService();

  Future<UserContextResult> readUserContext(
    String uid, {
    String? email,
  }) async {
    final String path = FirestorePaths.userProfile(uid);
    debugPrint('[Firestore] user context read started path=$path');

    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance.doc(path).get();

      if (!snapshot.exists) {
        debugPrint('[Firestore] user context missing path=$path — creating default profile');
        await _createDefaultProfile(uid: uid, email: email);
        return UserContextResult.pendingActivation(email: email);
      }

      final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};
      final bool active = data['active'] == true;
      final String? tenantId = data['activeTenantId']?.toString();
      final String? siteId = data['defaultSiteId']?.toString();
      final String? role = data['role']?.toString();

      debugPrint(
        '[Firestore] user context read success uid=$uid tenantId=$tenantId siteId=$siteId active=$active role=$role',
      );

      if (tenantId == null || tenantId.isEmpty) {
        return UserContextResult.pendingActivation(
          email: data['email']?.toString() ?? email,
        );
      }

      return UserContextResult.success(
        email: data['email']?.toString(),
        activeTenantId: tenantId,
        defaultSiteId: (siteId == null || siteId.isEmpty)
            ? FirestorePaths.defaultSiteId
            : siteId,
        active: active,
        role: role,
        rawData: data,
      );
    } catch (error, stackTrace) {
      debugPrint('[Firestore] user context read error uid=$uid error=$error');
      debugPrint('[Firestore] user context read error stack=$stackTrace');
      return UserContextResult.error(error.toString());
    }
  }

  Future<void> _createDefaultProfile({
    required String uid,
    String? email,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(<String, Object?>{
        'email': email,
        'role': UserAppRole.tenantOperator,
        'active': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      debugPrint('[Firestore] default profile created uid=$uid');
    } catch (error) {
      debugPrint('[Firestore] error creating default profile uid=$uid error=$error');
    }
  }
}

class UserContextResult {
  const UserContextResult({
    required this.email,
    required this.activeTenantId,
    required this.defaultSiteId,
    required this.active,
    required this.role,
    required this.rawData,
    required this.errorMessage,
    required this.exists,
    required this.isPendingActivation,
  });

  const UserContextResult.notFound()
    : email = null,
      activeTenantId = null,
      defaultSiteId = null,
      active = false,
      role = null,
      rawData = const <String, dynamic>{},
      errorMessage = null,
      exists = false,
      isPendingActivation = false;

  const UserContextResult.pendingActivation({this.email})
    : activeTenantId = null,
      defaultSiteId = null,
      active = false,
      role = null,
      rawData = const <String, dynamic>{},
      errorMessage = null,
      exists = true,
      isPendingActivation = true;

  const UserContextResult.error(this.errorMessage)
    : email = null,
      activeTenantId = null,
      defaultSiteId = null,
      active = false,
      role = null,
      rawData = const <String, dynamic>{},
      exists = false,
      isPendingActivation = false;

  const UserContextResult.success({
    required this.email,
    required this.activeTenantId,
    required this.defaultSiteId,
    required this.active,
    required this.role,
    required this.rawData,
  }) : errorMessage = null,
       exists = true,
       isPendingActivation = false;

  final String? email;
  final String? activeTenantId;
  final String? defaultSiteId;
  final bool active;
  final String? role;
  final Map<String, dynamic> rawData;
  final String? errorMessage;
  final bool exists;
  final bool isPendingActivation;

  bool get hasError => errorMessage != null;
}
