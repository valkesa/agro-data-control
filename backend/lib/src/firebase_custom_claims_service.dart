import 'dart:convert';
import 'dart:io';

import 'auth_claims_policy.dart';
import 'service_account_auth.dart';

class FirebaseCustomClaimsService {
  FirebaseCustomClaimsService({
    required String projectId,
    required String databaseId,
    required String serviceAccountJsonPath,
    HttpClient? httpClient,
    AuthClaimsPolicy policy = const AuthClaimsPolicy(),
  }) : _projectId = projectId,
       _databaseId = databaseId,
       _auth = ServiceAccountAuth(
         serviceAccountJsonPath: serviceAccountJsonPath,
       ),
       _httpClient = httpClient ?? HttpClient(),
       _policy = policy;

  final String _projectId;
  final String _databaseId;
  final ServiceAccountAuth _auth;
  final HttpClient _httpClient;
  final AuthClaimsPolicy _policy;

  bool get isConfigured =>
      _projectId.trim().isNotEmpty && _databaseId.trim().isNotEmpty;

  Future<CustomClaimsSyncResult> syncUserClaims({
    required String targetUid,
    required String requesterUid,
    required String requesterRole,
    required String requesterTenantId,
    bool dryRun = false,
  }) async {
    final String uid = targetUid.trim();
    if (uid.isEmpty) {
      throw const CustomClaimsException(
        statusCode: HttpStatus.badRequest,
        message: 'Target uid is required',
      );
    }
    if (!isConfigured) {
      throw const CustomClaimsException(
        statusCode: HttpStatus.serviceUnavailable,
        message: 'Custom claims service is not configured',
      );
    }
    if (requesterRole != AgroDataRole.owner) {
      throw const CustomClaimsException(
        statusCode: HttpStatus.forbidden,
        message: 'Forbidden: owner role required',
      );
    }

    final PersistedUserAccessProfile profile = await readUserProfile(uid);
    _validateRequesterTenant(
      requesterTenantId: requesterTenantId,
      profile: profile,
    );

    final AuthClaimsBuildResult built = _policy.buildClaims(profile);
    if (!built.success) {
      throw CustomClaimsException(
        statusCode: HttpStatus.badRequest,
        message: 'User profile cannot be synced to custom claims',
        details: built.reason,
      );
    }

    final Map<String, Object?> currentClaims = await _lookupCurrentClaims(uid);
    final Map<String, Object?> finalClaims = _policy.mergeWithExistingClaims(
      existingClaims: currentClaims,
      agroDataClaims: built.claims,
    );

    if (!dryRun) {
      await _setCustomClaims(uid: uid, claims: finalClaims);
    }

    return CustomClaimsSyncResult(
      uid: uid,
      requesterUid: requesterUid,
      role: built.role ?? '',
      activeTenantId: built.activeTenantId,
      allowedSiteCount: built.allowedSiteIds.length,
      operationalAccess: built.operationalAccess,
      reason: built.reason,
      changed: !_claimsEqual(currentClaims, finalClaims),
      dryRun: dryRun,
    );
  }

  Future<PersistedUserAccessProfile> readUserProfile(String uid) async {
    final String token = await _auth.getAccessToken();
    final Uri uri = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$_projectId'
      '/databases/$_databaseId/documents/users/$uid',
    );
    final HttpClientRequest request = await _httpClient.getUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode == HttpStatus.notFound) {
      throw CustomClaimsException(
        statusCode: HttpStatus.notFound,
        message: 'Target user profile not found',
        details: 'path=users/${_maskUid(uid)}',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CustomClaimsException(
        statusCode: HttpStatus.serviceUnavailable,
        message: 'Could not read target user profile',
        details: _compact(body),
      );
    }
    final Map<String, dynamic> decoded =
        jsonDecode(body) as Map<String, dynamic>;
    return firestoreUserProfileFromDocument(uid, decoded);
  }

  Future<List<String>> listUserIds({String? tenantId, String? uid}) async {
    if (uid != null && uid.trim().isNotEmpty) {
      return <String>[uid.trim()];
    }
    final String token = await _auth.getAccessToken();
    final List<String> ids = <String>[];
    String? pageToken;
    do {
      final Map<String, String> params = <String, String>{
        'pageSize': '100',
        if (pageToken != null) 'pageToken': pageToken,
      };
      final Uri uri = Uri.https(
        'firestore.googleapis.com',
        '/v1/projects/$_projectId/databases/$_databaseId/documents/users',
        params,
      );
      final HttpClientRequest request = await _httpClient.getUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final HttpClientResponse response = await request.close();
      final String body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CustomClaimsException(
          statusCode: HttpStatus.serviceUnavailable,
          message: 'Could not list user profiles',
          details: _compact(body),
        );
      }
      final Map<String, dynamic> decoded =
          jsonDecode(body) as Map<String, dynamic>;
      final List<dynamic> documents =
          decoded['documents'] as List<dynamic>? ?? <dynamic>[];
      for (final dynamic document in documents) {
        if (document is! Map<String, dynamic>) {
          continue;
        }
        final String id = document['name']?.toString().split('/').last ?? '';
        if (id.isEmpty) {
          continue;
        }
        if (tenantId != null && tenantId.trim().isNotEmpty) {
          final PersistedUserAccessProfile profile =
              firestoreUserProfileFromDocument(id, document);
          if (profile.activeTenantId != tenantId.trim()) {
            continue;
          }
        }
        ids.add(id);
      }
      pageToken = decoded['nextPageToken']?.toString();
    } while (pageToken != null && pageToken.isNotEmpty);
    return ids;
  }

  Future<Map<String, Object?>> _lookupCurrentClaims(String uid) async {
    final String token = await _auth.getAccessToken();
    final HttpClientRequest request = await _httpClient.postUrl(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/projects/$_projectId/accounts:lookup',
      ),
    );
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..set(HttpHeaders.contentTypeHeader, 'application/json');
    request.write(
      jsonEncode(<String, Object?>{
        'localId': <String>[uid],
      }),
    );
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CustomClaimsException(
        statusCode: HttpStatus.serviceUnavailable,
        message: 'Could not read current custom claims',
        details: _compact(body),
      );
    }
    final Map<String, dynamic> decoded =
        jsonDecode(body) as Map<String, dynamic>;
    final List<dynamic> users =
        decoded['users'] as List<dynamic>? ?? <dynamic>[];
    if (users.isEmpty || users.first is! Map) {
      return const <String, Object?>{};
    }
    final Object? raw = (users.first as Map)['customAttributes'];
    if (raw == null || raw.toString().trim().isEmpty) {
      return const <String, Object?>{};
    }
    final Object? parsed = jsonDecode(raw.toString());
    if (parsed is Map) {
      return Map<String, Object?>.from(parsed as Map<Object?, Object?>);
    }
    return const <String, Object?>{};
  }

  Future<void> _setCustomClaims({
    required String uid,
    required Map<String, Object?> claims,
  }) async {
    final String token = await _auth.getAccessToken();
    final HttpClientRequest request = await _httpClient.postUrl(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/projects/$_projectId/accounts:update',
      ),
    );
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..set(HttpHeaders.contentTypeHeader, 'application/json');
    request.write(
      jsonEncode(<String, Object?>{
        'localId': uid,
        'customAttributes': jsonEncode(claims),
      }),
    );
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CustomClaimsException(
        statusCode: HttpStatus.badGateway,
        message: 'Could not update custom claims',
        details: _compact(body),
      );
    }
  }

  void _validateRequesterTenant({
    required String requesterTenantId,
    required PersistedUserAccessProfile profile,
  }) {
    final String requesterTenant = requesterTenantId.trim();
    if (requesterTenant.isEmpty) {
      throw const CustomClaimsException(
        statusCode: HttpStatus.forbidden,
        message: 'Requester tenant context is required',
      );
    }
    final String targetTenant = profile.activeTenantId?.trim() ?? '';
    final bool targetHasNoOperationalAccess =
        !profile.active || profile.role == AgroDataRole.pending;
    if (targetTenant.isEmpty && targetHasNoOperationalAccess) {
      return;
    }
    if (targetTenant != requesterTenant) {
      throw CustomClaimsException(
        statusCode: HttpStatus.forbidden,
        message: 'Forbidden: target user belongs to another tenant',
        details:
            'requesterTenant=$requesterTenant targetTenant=${targetTenant.isEmpty ? 'none' : targetTenant}',
      );
    }
  }
}

PersistedUserAccessProfile firestoreUserProfileFromDocument(
  String uid,
  Map<String, dynamic> document,
) {
  final Map<String, dynamic> fields =
      document['fields'] as Map<String, dynamic>? ?? <String, dynamic>{};
  return PersistedUserAccessProfile(
    uid: uid,
    role: firestoreStringField(fields['role']),
    activeTenantId: firestoreStringField(fields['activeTenantId']),
    allowedSiteIds: firestoreStringListField(fields['allowedSiteIds']),
    active: firestoreBoolField(fields['active']),
  );
}

String? firestoreStringField(Object? field) {
  if (field is Map && field['stringValue'] != null) {
    return field['stringValue'].toString();
  }
  return null;
}

bool firestoreBoolField(Object? field) {
  if (field is Map && field['booleanValue'] is bool) {
    return field['booleanValue'] as bool;
  }
  return false;
}

List<String> firestoreStringListField(Object? field) {
  if (field is! Map) {
    return const <String>[];
  }
  final Object? values = field['arrayValue'] is Map
      ? (field['arrayValue'] as Map)['values']
      : null;
  if (values is! List) {
    return const <String>[];
  }
  return values
      .map((Object? value) => firestoreStringField(value))
      .whereType<String>()
      .where((String value) => value.trim().isNotEmpty)
      .map((String value) => value.trim())
      .toList(growable: false);
}

class CustomClaimsSyncResult {
  const CustomClaimsSyncResult({
    required this.uid,
    required this.requesterUid,
    required this.role,
    required this.activeTenantId,
    required this.allowedSiteCount,
    required this.operationalAccess,
    required this.reason,
    required this.changed,
    required this.dryRun,
  });

  final String uid;
  final String requesterUid;
  final String role;
  final String? activeTenantId;
  final int allowedSiteCount;
  final bool operationalAccess;
  final String reason;
  final bool changed;
  final bool dryRun;

  Map<String, Object?> toSafeJson() {
    return <String, Object?>{
      'uid': uid,
      'role': role,
      'activeTenantId': activeTenantId,
      'allowedSiteCount': allowedSiteCount,
      'operationalAccess': operationalAccess,
      'reason': reason,
      'changed': changed,
      'dryRun': dryRun,
    };
  }
}

class CustomClaimsException implements Exception {
  const CustomClaimsException({
    required this.statusCode,
    required this.message,
    this.details,
  });

  final int statusCode;
  final String message;
  final Object? details;

  @override
  String toString() => message;
}

bool _claimsEqual(Map<String, Object?> a, Map<String, Object?> b) {
  return jsonEncode(_stableJson(a)) == jsonEncode(_stableJson(b));
}

Map<String, Object?> _stableJson(Map<String, Object?> input) {
  final List<String> keys = input.keys.toList()..sort();
  return <String, Object?>{for (final String key in keys) key: input[key]};
}

String _compact(Object value) {
  final String compacted = value
      .toString()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (compacted.length <= 240) {
    return compacted;
  }
  return '${compacted.substring(0, 240)}...';
}

String _maskUid(String uid) {
  if (uid.length <= 6) {
    return '***';
  }
  return '${uid.substring(0, 3)}***${uid.substring(uid.length - 3)}';
}
