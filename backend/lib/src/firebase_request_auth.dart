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

  Map<String, String>? _cachedFirebaseCerts;
  DateTime? _firebaseCertsExpireAt;

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
      throw BackendAuthException(
        statusCode: HttpStatus.forbidden,
        message: 'Forbidden: user profile not found',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackendAuthException(
        statusCode: HttpStatus.serviceUnavailable,
        message: 'Could not read user profile',
      );
    }
    final Map<String, dynamic> decoded =
        jsonDecode(body) as Map<String, dynamic>;
    final Map<String, dynamic> fields =
        decoded['fields'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return FirestoreUserProfile(
      role: _stringField(fields['role']),
      active: _boolField(fields['active']),
      activeTenantId: _stringField(fields['activeTenantId']),
    );
  }
}

class AuthenticatedBackendUser {
  const AuthenticatedBackendUser({
    required this.uid,
    required this.role,
    required this.tenantId,
  });

  final String uid;
  final String? role;
  final String? tenantId;
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
