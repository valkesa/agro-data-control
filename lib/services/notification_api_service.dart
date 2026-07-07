import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';

class NotificationApiService {
  const NotificationApiService({String? backendSnapshotEndpoint})
    : _backendSnapshotEndpoint = backendSnapshotEndpoint;

  static const Duration _requestTimeout = Duration(seconds: 15);

  final String? _backendSnapshotEndpoint;

  Future<WhatsAppTestMessageResult> sendWhatsAppTestMessage({
    required String to,
    required String message,
  }) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const WhatsAppTestMessageResult.error(
        'No hay usuario autenticado.',
      );
    }

    final String idToken = await user.getIdToken() ?? '';
    if (idToken.isEmpty) {
      return const WhatsAppTestMessageResult.error(
        'No se pudo obtener el token de autenticacion.',
      );
    }

    final Uri uri = _resolveWhatsAppTestUri();
    try {
      final http.Response response = await http
          .post(
            uri,
            headers: <String, String>{
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, String>{'to': to, 'message': message}),
          )
          .timeout(_requestTimeout);

      final Object? decoded = _tryDecodeJson(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return WhatsAppTestMessageResult.error(
          _readString(decoded, 'error') ??
              'El backend respondio HTTP ${response.statusCode}.',
          details: _readString(decoded, 'details'),
          statusCode: response.statusCode,
        );
      }

      if (decoded is! Map) {
        return WhatsAppTestMessageResult.error(
          'El backend devolvio una respuesta invalida.',
          statusCode: response.statusCode,
        );
      }

      final Map<String, Object?> payload = Map<String, Object?>.from(decoded);
      if (payload['ok'] != true) {
        return WhatsAppTestMessageResult.error(
          payload['error']?.toString() ?? 'No se pudo enviar el mensaje.',
          details: payload['details']?.toString(),
          statusCode: response.statusCode,
        );
      }

      return WhatsAppTestMessageResult.success(
        messageId: payload['messageId']?.toString(),
      );
    } on TimeoutException {
      return const WhatsAppTestMessageResult.error(
        'El backend no respondio a tiempo.',
        details: 'timeout',
      );
    } on http.ClientException catch (error) {
      return WhatsAppTestMessageResult.error(
        'No se pudo conectar con el backend.',
        details: error.message,
      );
    } catch (error) {
      return WhatsAppTestMessageResult.error(
        'Fallo el envio de prueba.',
        details: error.toString(),
      );
    }
  }

  Uri _resolveWhatsAppTestUri() {
    final String endpoint = _backendSnapshotEndpoint?.trim().isNotEmpty == true
        ? _backendSnapshotEndpoint!.trim()
        : AppConfig.currentBackendSnapshotUrl;
    final Uri snapshotUri = Uri.parse(endpoint);

    return snapshotUri.replace(
      path: '/api/notifications/whatsapp/test',
      query: '',
    );
  }
}

class WhatsAppTestMessageResult {
  const WhatsAppTestMessageResult._({
    required this.ok,
    this.message,
    this.details,
    this.messageId,
    this.statusCode,
  });

  const WhatsAppTestMessageResult.success({String? messageId})
    : this._(ok: true, messageId: messageId);

  const WhatsAppTestMessageResult.error(
    String message, {
    String? details,
    int? statusCode,
  }) : this._(
         ok: false,
         message: message,
         details: details,
         statusCode: statusCode,
       );

  final bool ok;
  final String? message;
  final String? details;
  final String? messageId;
  final int? statusCode;
}

Object? _tryDecodeJson(String body) {
  if (body.trim().isEmpty) {
    return null;
  }
  try {
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}

String? _readString(Object? decoded, String key) {
  if (decoded is Map && decoded[key] != null) {
    return decoded[key].toString();
  }
  return null;
}
