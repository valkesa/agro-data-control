import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';
import 'user_management_service.dart';

class UserContextService {
  const UserContextService();

  Future<UserContextResult> readUserContext(String uid, {String? email}) async {
    final String path = FirestorePaths.userProfile(uid);
    debugPrint('[Firestore] user context read started path=$path');

    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance.doc(path).get();

      if (!snapshot.exists) {
        debugPrint(
          '[Firestore] user context missing path=$path — creating default profile',
        );
        await _createDefaultProfile(uid: uid, email: email);
        return UserContextResult.pendingActivation(email: email);
      }

      final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};
      final bool active = data['active'] == true;
      final String? tenantId = data['activeTenantId']?.toString();
      final String? siteId = data['defaultSiteId']?.toString();
      final String? role = data['role']?.toString();
      final List<String> allowedSiteIds = _parseStringList(
        data['allowedSiteIds'],
      );

      debugPrint(
        '[Firestore] user context read success uid=$uid tenantId=$tenantId siteId=$siteId active=$active role=$role allowedSites=${allowedSiteIds.length}',
      );

      if (role == null || role.isEmpty || role == UserAppRole.pending) {
        return UserContextResult.pendingActivation(
          email: data['email']?.toString() ?? email,
        );
      }

      return UserContextResult.success(
        email: data['email']?.toString(),
        activeTenantId: (tenantId == null || tenantId.isEmpty)
            ? null
            : tenantId,
        defaultSiteId: (siteId == null || siteId.isEmpty) ? null : siteId,
        allowedSiteIds: allowedSiteIds,
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
            'role': UserAppRole.pending,
            'active': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
      debugPrint('[Firestore] default profile created uid=$uid');
    } catch (error) {
      debugPrint(
        '[Firestore] error creating default profile uid=$uid error=$error',
      );
    }
  }

  Future<void> setActiveSite({
    required String uid,
    required String siteId,
  }) async {
    final String path = FirestorePaths.userProfile(uid);
    debugPrint('[Firestore] setActiveSite started path=$path siteId=$siteId');
    await FirebaseFirestore.instance.doc(path).update(<String, Object?>{
      'defaultSiteId': siteId,
    });
    debugPrint('[Firestore] setActiveSite done uid=$uid siteId=$siteId');
  }

  Future<void> saveComparisonModuleOrder({
    required String uid,
    required List<String> moduleOrder,
  }) async {
    final String path = FirestorePaths.userProfile(uid);
    debugPrint(
      '[Firestore] comparison module order save started path=$path order=$moduleOrder',
    );

    await FirebaseFirestore.instance.doc(path).set(<String, Object?>{
      'ui': <String, Object?>{
        'comparison': <String, Object?>{'moduleOrder': moduleOrder},
      },
    }, SetOptions(merge: true));
  }

  Future<void> saveUnitVisibilitySettings({
    required String uid,
    required bool showMunters1,
    required bool showMunters2,
  }) async {
    final String path = FirestorePaths.userProfile(uid);
    debugPrint(
      '[Firestore] unit visibility save started path=$path m1=$showMunters1 m2=$showMunters2',
    );

    await FirebaseFirestore.instance.doc(path).set(<String, Object?>{
      'ui': <String, Object?>{
        'visibleUnits': <String, Object?>{
          'munters1': showMunters1,
          'munters2': showMunters2,
        },
      },
    }, SetOptions(merge: true));
  }

  static List<String> _parseStringList(Object? value) {
    if (value is List<dynamic>) {
      return value
          .map((Object? e) => e?.toString() ?? '')
          .where((String s) => s.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }
}

class UserContextResult {
  const UserContextResult({
    required this.email,
    required this.activeTenantId,
    required this.defaultSiteId,
    required this.allowedSiteIds,
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
      allowedSiteIds = const <String>[],
      active = false,
      role = null,
      rawData = const <String, dynamic>{},
      errorMessage = null,
      exists = false,
      isPendingActivation = false;

  const UserContextResult.pendingActivation({this.email})
    : activeTenantId = null,
      defaultSiteId = null,
      allowedSiteIds = const <String>[],
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
      allowedSiteIds = const <String>[],
      active = false,
      role = null,
      rawData = const <String, dynamic>{},
      exists = false,
      isPendingActivation = false;

  const UserContextResult.success({
    required this.email,
    required this.activeTenantId,
    required this.defaultSiteId,
    required this.allowedSiteIds,
    required this.active,
    required this.role,
    required this.rawData,
  }) : errorMessage = null,
       exists = true,
       isPendingActivation = false;

  final String? email;
  final String? activeTenantId;
  final String? defaultSiteId;
  final List<String> allowedSiteIds;
  final bool active;
  final String? role;
  final Map<String, dynamic> rawData;
  final String? errorMessage;
  final bool exists;
  final bool isPendingActivation;

  bool get hasError => errorMessage != null;

  List<String>? readComparisonModuleOrder() {
    Object? current = rawData['ui'];
    if (current is! Map<String, dynamic>) {
      return null;
    }
    current = current['comparison'];
    if (current is! Map<String, dynamic>) {
      return null;
    }
    current = current['moduleOrder'];
    if (current is! List<dynamic>) {
      return null;
    }
    final List<String> values = current
        .map((dynamic value) => value.toString())
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
    return values.isEmpty ? null : values;
  }

  bool? readShowMunters1() =>
      _readBool(rawData, const ['ui', 'visibleUnits', 'munters1']);

  bool? readShowMunters2() =>
      _readBool(rawData, const ['ui', 'visibleUnits', 'munters2']);

  static bool? _readBool(Map<String, dynamic> source, List<String> path) {
    Object? current = source;
    for (final String segment in path) {
      if (current is! Map<String, dynamic>) {
        return null;
      }
      current = current[segment];
    }
    if (current is bool) {
      return current;
    }
    return null;
  }
}
