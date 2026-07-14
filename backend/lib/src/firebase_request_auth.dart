import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'service_account_auth.dart';

class FirebaseRequestAuthService {
  FirebaseRequestAuthService({
    required String projectId,
    required String databaseId,
    required String serviceAccountJsonPath,
    HttpClient? httpClient,
  }) : _projectId = projectId,
       _databaseId = databaseId,
       _auth = ServiceAccountAuth(
         serviceAccountJsonPath: serviceAccountJsonPath,
       ),
       _httpClient = httpClient ?? HttpClient();

  final String _projectId;
  final String _databaseId;
  final ServiceAccountAuth _auth;
  final HttpClient _httpClient;

  static const Duration _userProfileCacheTtl = Duration(minutes: 10);
  static const Duration _userProfileStaleTtl = Duration(hours: 6);

  Map<String, String>? _cachedFirebaseCerts;
  DateTime? _firebaseCertsExpireAt;
  final Map<String, _CachedUserProfile> _userProfileCache =
      <String, _CachedUserProfile>{};

  bool get isConfigured =>
      _projectId.trim().isNotEmpty && _databaseId.trim().isNotEmpty;

  Future<AuthenticatedBackendUser> requireOwnerOrAdmin(
    HttpRequest request,
  ) async {
    if (!isConfigured) {
      throw BackendAuthException(
        statusCode: HttpStatus.serviceUnavailable,
        message: 'Backend auth is not configured',
      );
    }

    final String idToken = _readBearerToken(request);
    final JWT jwt = await _verifyFirebaseIdToken(idToken);
    final Map<String, Object?> tokenPayload = _jwtPayload(jwt);
    final String uid = jwt.subject ?? '';
    if (uid.isEmpty) {
      throw BackendAuthException(
        statusCode: HttpStatus.unauthorized,
        message: 'Invalid Firebase token subject',
      );
    }

    final FirestoreUserProfile profile = await _readUserProfile(uid);
    final bool allowed =
        profile.active &&
        (profile.role == 'owner' || profile.role == 'tenant_admin');
    if (!allowed) {
      throw BackendAuthException(
        statusCode: HttpStatus.forbidden,
        message: 'Forbidden: owner or tenant_admin role required',
        details: <String, Object?>{
          'uid': uid,
          'role': profile.role,
          'active': profile.active,
        },
      );
    }

    return AuthenticatedBackendUser(
      uid: uid,
      role: profile.role,
      tenantId: profile.activeTenantId,
      email: tokenPayload['email']?.toString(),
      displayName:
          tokenPayload['name']?.toString() ??
          tokenPayload['displayName']?.toString(),
    );
  }

  Future<AuthenticatedBackendUser?> tryAuthenticate(HttpRequest request) async {
    try {
      return await requireAuthenticated(request);
    } on BackendAuthException {
      return null;
    }
  }

  Future<AuthenticatedBackendUser> requireAuthenticated(
    HttpRequest request,
  ) async {
    if (!isConfigured) {
      throw BackendAuthException(
        statusCode: HttpStatus.serviceUnavailable,
        message: 'Backend auth is not configured',
      );
    }

    final String idToken = _readBearerToken(request);
    final JWT jwt = await _verifyFirebaseIdToken(idToken);
    final Map<String, Object?> tokenPayload = _jwtPayload(jwt);
    final String uid = jwt.subject ?? '';
    if (uid.isEmpty) {
      throw BackendAuthException(
        statusCode: HttpStatus.unauthorized,
        message: 'Invalid Firebase token subject',
      );
    }

    return AuthenticatedBackendUser(
      uid: uid,
      role:
          tokenPayload['role']?.toString() ??
          tokenPayload['tenantRole']?.toString(),
      tenantId:
          tokenPayload['activeTenantId']?.toString() ??
          tokenPayload['tenantId']?.toString(),
      email: tokenPayload['email']?.toString(),
      displayName:
          tokenPayload['name']?.toString() ??
          tokenPayload['displayName']?.toString(),
      allowedSiteIds: _stringListClaim(tokenPayload['allowedSiteIds']),
    );
  }

  Future<AuthenticatedBackendUser> requireRoomWashWriter(
    HttpRequest request,
  ) async {
    if (!isConfigured) {
      throw BackendAuthException(
        statusCode: HttpStatus.serviceUnavailable,
        message: 'Backend auth is not configured',
      );
    }

    final String idToken = _readBearerToken(request);
    final JWT jwt = await _verifyFirebaseIdToken(idToken);
    final Map<String, Object?> tokenPayload = _jwtPayload(jwt);
    final String uid = jwt.subject ?? '';
    if (uid.isEmpty) {
      throw BackendAuthException(
        statusCode: HttpStatus.unauthorized,
        message: 'Invalid Firebase token subject',
      );
    }
    // Canonical AgroData claims are role, activeTenantId and allowedSiteIds.
    // tenantRole and tenantId are accepted only as transitional aliases.
    final String? role =
        tokenPayload['role']?.toString() ??
        tokenPayload['tenantRole']?.toString();
    final String? tenantId =
        tokenPayload['activeTenantId']?.toString() ??
        tokenPayload['tenantId']?.toString();
    if (role == null || role.isEmpty || tenantId == null || tenantId.isEmpty) {
      throw BackendAuthException(
        statusCode: HttpStatus.forbidden,
        message:
            'Forbidden: room wash writer claims are missing role or tenantId',
        details: <String, Object?>{
          'uid': uid,
          'hasRole': role != null && role.isNotEmpty,
          'hasTenantId': tenantId != null && tenantId.isNotEmpty,
        },
      );
    }
    return AuthenticatedBackendUser(
      uid: uid,
      role: role,
      tenantId: tenantId,
      email: tokenPayload['email']?.toString(),
      displayName:
          tokenPayload['name']?.toString() ??
          tokenPayload['displayName']?.toString(),
      allowedSiteIds: _stringListClaim(tokenPayload['allowedSiteIds']),
    );
  }

  String _readBearerToken(HttpRequest request) {
    final String? authorization = request.headers.value(
      HttpHeaders.authorizationHeader,
    );
    if (authorization == null || authorization.trim().isEmpty) {
      throw BackendAuthException(
        statusCode: HttpStatus.unauthorized,
        message: 'Missing Authorization bearer token',
      );
    }
    final RegExpMatch? match = RegExp(
      r'^Bearer\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(authorization.trim());
    if (match == null || match.group(1)?.trim().isEmpty == true) {
      throw BackendAuthException(
        statusCode: HttpStatus.unauthorized,
        message: 'Invalid Authorization bearer token',
      );
    }
    return match.group(1)!.trim();
  }

  Future<JWT> _verifyFirebaseIdToken(String idToken) async {
    final JWT? decoded = JWT.tryDecode(idToken);
    final String? keyId = decoded?.header?['kid']?.toString();
    if (keyId == null || keyId.isEmpty) {
      throw BackendAuthException(
        statusCode: HttpStatus.unauthorized,
        message: 'Firebase token missing key id',
      );
    }

    final Map<String, String> certs = await _firebasePublicCerts();
    final String? cert = certs[keyId];
    if (cert == null || cert.isEmpty) {
      throw BackendAuthException(
        statusCode: HttpStatus.unauthorized,
        message: 'Firebase token key id not recognized',
      );
    }

    try {
      return JWT.verify(
        idToken,
        RSAPublicKey.cert(cert),
        audience: Audience.one(_projectId),
        issuer: 'https://securetoken.google.com/$_projectId',
      );
    } on JWTException catch (error) {
      throw BackendAuthException(
        statusCode: HttpStatus.unauthorized,
        message: 'Invalid Firebase token',
        details: error.toString(),
      );
    }
  }

  Future<Map<String, String>> _firebasePublicCerts() async {
    final DateTime now = DateTime.now().toUtc();
    if (_cachedFirebaseCerts != null &&
        _firebaseCertsExpireAt != null &&
        _firebaseCertsExpireAt!.isAfter(now)) {
      return _cachedFirebaseCerts!;
    }

    final Uri uri = Uri.parse(
      'https://www.googleapis.com/robot/v1/metadata/x509/'
      'securetoken@system.gserviceaccount.com',
    );
    final HttpClientRequest request = await _httpClient.getUrl(uri);
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackendAuthException(
        statusCode: HttpStatus.serviceUnavailable,
        message: 'Could not fetch Firebase public certificates',
      );
    }
    final Map<String, dynamic> decoded =
        jsonDecode(body) as Map<String, dynamic>;
    _cachedFirebaseCerts = decoded.map(
      (String key, dynamic value) => MapEntry(key, value.toString()),
    );
    _firebaseCertsExpireAt = now.add(
      _cacheMaxAge(response) ?? const Duration(hours: 1),
    );
    return _cachedFirebaseCerts!;
  }

  Duration? _cacheMaxAge(HttpClientResponse response) {
    final String? cacheControl = response.headers.value(
      HttpHeaders.cacheControlHeader,
    );
    if (cacheControl == null) {
      return null;
    }
    final RegExpMatch? match = RegExp(
      r'max-age=(\d+)',
    ).firstMatch(cacheControl);
    if (match == null) {
      return null;
    }
    final int? seconds = int.tryParse(match.group(1)!);
    if (seconds == null || seconds <= 0) {
      return null;
    }
    return Duration(seconds: seconds);
  }

  Future<FirestoreUserProfile> _readUserProfile(String uid) async {
    final DateTime now = DateTime.now().toUtc();
    final _CachedUserProfile? cached = _userProfileCache[uid];
    if (cached != null && cached.expiresAt.isAfter(now)) {
      return cached.profile;
    }

    final String token;
    try {
      token = await _auth.getAccessToken();
    } catch (error) {
      throw BackendAuthException(
        statusCode: HttpStatus.serviceUnavailable,
        message: 'Could not authenticate Firestore service account',
        details: error.toString(),
      );
    }
    final Uri uri = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$_projectId'
      '/databases/$_databaseId/documents/users/$uid',
    );
    final HttpClientRequest request = await _httpClient.getUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode == HttpStatus.notFound) {
      _userProfileCache.remove(uid);
      throw BackendAuthException(
        statusCode: HttpStatus.forbidden,
        message: 'Forbidden: user profile not found',
        details:
            'firestore_status=${response.statusCode} path=users/${_maskUid(uid)} project=$_projectId database=$_databaseId',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (cached != null && cached.staleUntil.isAfter(now)) {
        stdout.writeln(
          '[auth] using stale user profile cache uid=${_maskUid(uid)} firestore_status=${response.statusCode} ${_firestoreErrorSummary(body)}',
        );
        return cached.profile;
      }
      throw BackendAuthException(
        statusCode: HttpStatus.serviceUnavailable,
        message: 'Could not read user profile',
        details:
            'firestore_status=${response.statusCode} path=users/${_maskUid(uid)} project=$_projectId database=$_databaseId ${_firestoreErrorSummary(body)}',
      );
    }
    final Map<String, dynamic> decoded =
        jsonDecode(body) as Map<String, dynamic>;
    final Map<String, dynamic> fields =
        decoded['fields'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final FirestoreUserProfile profile = FirestoreUserProfile(
      role: _stringField(fields['role']),
      active: _boolField(fields['active']),
      activeTenantId: _stringField(fields['activeTenantId']),
    );
    _userProfileCache[uid] = _CachedUserProfile(
      profile: profile,
      expiresAt: now.add(_userProfileCacheTtl),
      staleUntil: now.add(_userProfileStaleTtl),
    );
    return profile;
  }
}

class _CachedUserProfile {
  const _CachedUserProfile({
    required this.profile,
    required this.expiresAt,
    required this.staleUntil,
  });

  final FirestoreUserProfile profile;
  final DateTime expiresAt;
  final DateTime staleUntil;
}

class AuthenticatedBackendUser {
  const AuthenticatedBackendUser({
    required this.uid,
    required this.role,
    required this.tenantId,
    this.email,
    this.displayName,
    this.allowedSiteIds = const <String>[],
  });

  final String uid;
  final String? role;
  final String? tenantId;
  final String? email;
  final String? displayName;
  final List<String> allowedSiteIds;
}

class FirestoreUserProfile {
  const FirestoreUserProfile({
    required this.role,
    required this.active,
    required this.activeTenantId,
  });

  final String? role;
  final bool active;
  final String? activeTenantId;
}

class BackendAuthException implements Exception {
  BackendAuthException({
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

String? _stringField(Object? field) {
  if (field is Map && field['stringValue'] != null) {
    return field['stringValue'].toString();
  }
  return null;
}

bool _boolField(Object? field) {
  if (field is Map && field['booleanValue'] is bool) {
    return field['booleanValue'] as bool;
  }
  return false;
}

String _firestoreErrorSummary(String body) {
  if (body.trim().isEmpty) {
    return 'firestore_error=empty_response';
  }
  try {
    final Object? decoded = jsonDecode(body);
    if (decoded is Map) {
      final Object? error = decoded['error'];
      if (error is Map) {
        final List<String> parts = <String>[];
        final Object? status = error['status'];
        final Object? code = error['code'];
        final Object? message = error['message'];
        if (status != null) {
          parts.add('firestore_error_status=$status');
        }
        if (code != null) {
          parts.add('firestore_error_code=$code');
        }
        if (message != null) {
          parts.add('firestore_error_message=${_compact(message)}');
        }
        if (parts.isNotEmpty) {
          return parts.join(' ');
        }
      }
    }
  } catch (_) {
    // Fall through to compact raw body.
  }
  return 'firestore_error=${_compact(body)}';
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

Map<String, Object?> _jwtPayload(JWT jwt) {
  final Object? payload = jwt.payload;
  if (payload is Map) {
    return payload.map(
      (Object? key, Object? value) => MapEntry(key.toString(), value),
    );
  }
  return const <String, Object?>{};
}

List<String> _stringListClaim(Object? raw) {
  if (raw is List) {
    return raw
        .map((Object? value) => value?.toString().trim() ?? '')
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
  }
  if (raw is String && raw.trim().isNotEmpty) {
    return raw
        .split(',')
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
  }
  return const <String>[];
}
