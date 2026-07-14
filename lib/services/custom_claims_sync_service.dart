import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';

class CustomClaimsSyncService {
  const CustomClaimsSyncService({String? backendSnapshotEndpoint})
    : _backendSnapshotEndpoint = backendSnapshotEndpoint;

  static const Duration _requestTimeout = Duration(seconds: 8);

  final String? _backendSnapshotEndpoint;

  Future<CustomClaimsSyncResponse> syncUser(String uid) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const CustomClaimsSyncResponse(
        success: false,
        message: 'No hay usuario autenticado.',
      );
    }
    final String token = await user.getIdToken() ?? '';
    if (token.isEmpty) {
      return const CustomClaimsSyncResponse(
        success: false,
        message: 'No se pudo obtener el token de autenticación.',
      );
    }

    try {
      final http.Response response = await http
          .post(
            _uri(),
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, Object?>{'uid': uid}),
          )
          .timeout(_requestTimeout);
      final Map<String, Object?> decoded = _decodeObject(response.body);
      final bool ok = response.statusCode >= 200 && response.statusCode < 300;
      return CustomClaimsSyncResponse(
        success: ok,
        statusCode: response.statusCode,
        message:
            decoded['message']?.toString() ??
            decoded['error']?.toString() ??
            (ok
                ? 'Permisos actualizados.'
                : 'No se pudieron actualizar los permisos.'),
      );
    } on TimeoutException {
      return const CustomClaimsSyncResponse(
        success: false,
        message: 'La sincronización de permisos tardó demasiado.',
      );
    } catch (error) {
      return CustomClaimsSyncResponse(
        success: false,
        message: 'No se pudieron actualizar los permisos: $error',
      );
    }
  }

  Uri _uri() {
    final String endpoint = _backendSnapshotEndpoint?.trim().isNotEmpty == true
        ? _backendSnapshotEndpoint!.trim()
        : AppConfig.currentBackendSnapshotUrl;
    return Uri.parse(
      endpoint,
    ).replace(path: '/api/auth/custom-claims/sync', query: '');
  }
}

class CustomClaimsSyncResponse {
  const CustomClaimsSyncResponse({
    required this.success,
    required this.message,
    this.statusCode,
  });

  final bool success;
  final String message;
  final int? statusCode;
}

Map<String, Object?> _decodeObject(String body) {
  if (body.trim().isEmpty) {
    return const <String, Object?>{};
  }
  try {
    final Object? decoded = jsonDecode(body);
    if (decoded is Map) {
      return Map<String, Object?>.from(decoded as Map<Object?, Object?>);
    }
  } catch (_) {
    // Fall through to empty object.
  }
  return const <String, Object?>{};
}
