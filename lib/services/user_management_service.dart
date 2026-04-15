import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class UserAppRole {
  const UserAppRole._();

  static const String owner = 'owner';
  static const String tenantAdmin = 'tenant_admin';
  static const String tenantOperator = 'tenant_operator';

  static const List<String> all = <String>[owner, tenantAdmin, tenantOperator];

  static String label(String? role) {
    return switch (role) {
      owner => 'Owner',
      tenantAdmin => 'Admin de tenant',
      tenantOperator => 'Operador',
      _ => 'Sin rol',
    };
  }
}

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.email,
    required this.role,
    required this.activeTenantId,
    required this.defaultSiteId,
    required this.active,
  });

  final String uid;
  final String? email;
  final String? role;
  final String? activeTenantId;
  final String? defaultSiteId;
  final bool active;
}

class UserManagementService {
  const UserManagementService();

  Future<List<UserProfile>> listAllUsers() async {
    debugPrint('[UserManagement] listing all users');
    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance.collection('users').get();

      return snapshot.docs.map((DocumentSnapshot<Map<String, dynamic>> doc) {
        final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
        return UserProfile(
          uid: doc.id,
          email: data['email']?.toString(),
          role: data['role']?.toString(),
          activeTenantId: data['activeTenantId']?.toString(),
          defaultSiteId: data['defaultSiteId']?.toString(),
          active: data['active'] == true,
        );
      }).toList();
    } catch (error, stackTrace) {
      debugPrint('[UserManagement] listAllUsers error=$error');
      debugPrint('[UserManagement] listAllUsers stack=$stackTrace');
      rethrow;
    }
  }

  Future<void> updateUserRole(String uid, String? role) async {
    debugPrint('[UserManagement] updateUserRole uid=$uid role=$role');
    await FirebaseFirestore.instance.collection('users').doc(uid).update(
      <String, Object?>{'role': role},
    );
  }
}
