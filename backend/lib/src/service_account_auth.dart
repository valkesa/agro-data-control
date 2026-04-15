import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

/// Autentica con Google APIs usando un Service Account JSON.
/// Genera tokens OAuth2 y los renueva automáticamente antes de que expiren.
class ServiceAccountAuth {
  ServiceAccountAuth({required String serviceAccountJsonPath})
    : _serviceAccountJsonPath = serviceAccountJsonPath;

  final String _serviceAccountJsonPath;

  String? _cachedToken;
  DateTime? _tokenExpiresAt;

  static const String _scope = 'https://www.googleapis.com/auth/datastore';
  static const String _tokenEndpoint = 'https://oauth2.googleapis.com/token';

  /// Retorna un access token válido. Lo renueva automáticamente si está
  /// a menos de 5 minutos de vencer.
  Future<String> getAccessToken() async {
    final DateTime now = DateTime.now().toUtc();
    final bool isValid =
        _cachedToken != null &&
        _tokenExpiresAt != null &&
        _tokenExpiresAt!.subtract(const Duration(minutes: 5)).isAfter(now);

    if (isValid) {
      return _cachedToken!;
    }

    return _refresh();
  }

  Future<String> _refresh() async {
    final Map<String, dynamic> json = _loadServiceAccountJson();
    final String clientEmail = json['client_email'] as String;
    final String privateKeyPem = json['private_key'] as String;

    final String assertion = _buildJwt(
      clientEmail: clientEmail,
      privateKeyPem: privateKeyPem,
    );

    final String token = await _exchangeJwtForToken(assertion);

    // Google emite tokens de 1 hora. Guardamos con margen de 5 minutos.
    _cachedToken = token;
    _tokenExpiresAt = DateTime.now().toUtc().add(const Duration(minutes: 55));

    stdout.writeln('[service-account-auth] token refreshed expires=${_tokenExpiresAt!.toIso8601String()}');
    return token;
  }

  Map<String, dynamic> _loadServiceAccountJson() {
    final File file = File(_serviceAccountJsonPath);
    if (!file.existsSync()) {
      throw ServiceAccountAuthException(
        'Service account file not found: $_serviceAccountJsonPath',
      );
    }
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  String _buildJwt({
    required String clientEmail,
    required String privateKeyPem,
  }) {
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final JWT jwt = JWT(
      <String, Object?>{
        'iss': clientEmail,
        'scope': _scope,
        'aud': _tokenEndpoint,
        'iat': now,
        'exp': now + 3600,
      },
    );
    return jwt.sign(RSAPrivateKey(privateKeyPem), algorithm: JWTAlgorithm.RS256);
  }

  Future<String> _exchangeJwtForToken(String assertion) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.postUrl(
        Uri.parse(_tokenEndpoint),
      );
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/x-www-form-urlencoded',
      );
      final String body =
          'grant_type=${Uri.encodeComponent('urn:ietf:params:oauth:grant-type:jwt-bearer')}'
          '&assertion=${Uri.encodeComponent(assertion)}';
      request.write(body);

      final HttpClientResponse response = await request.close();
      final String responseBody =
          await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ServiceAccountAuthException(
          'Token exchange failed status=${response.statusCode} body=$responseBody',
        );
      }

      final Map<String, dynamic> json =
          jsonDecode(responseBody) as Map<String, dynamic>;
      final String? accessToken = json['access_token'] as String?;
      if (accessToken == null || accessToken.isEmpty) {
        throw ServiceAccountAuthException(
          'Token exchange response missing access_token: $responseBody',
        );
      }
      return accessToken;
    } finally {
      client.close(force: true);
    }
  }
}

class ServiceAccountAuthException implements Exception {
  ServiceAccountAuthException(this.message);
  final String message;

  @override
  String toString() => 'ServiceAccountAuthException: $message';
}
