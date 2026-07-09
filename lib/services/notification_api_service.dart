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
          mode: _readString(decoded, 'mode'),
          fallbackUsed: _readBool(decoded, 'fallbackUsed'),
          metaStatusCode: _readIntFromDecoded(decoded, 'metaStatusCode'),
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
          mode: payload['mode']?.toString(),
          fallbackUsed: payload['fallbackUsed'] == true,
          metaStatusCode: _readInt(payload['metaStatusCode']),
          statusCode: response.statusCode,
        );
      }

      return WhatsAppTestMessageResult.success(
        messageId:
            payload['wamid']?.toString() ?? payload['messageId']?.toString(),
        mode: payload['mode']?.toString(),
        templateName: payload['templateName']?.toString(),
        languageCode: payload['languageCode']?.toString(),
        fallbackUsed: payload['fallbackUsed'] == true,
        metaStatusCode: _readInt(payload['metaStatusCode']),
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
    this.mode,
    this.templateName,
    this.languageCode,
    this.fallbackUsed = false,
    this.metaStatusCode,
    this.statusCode,
  });

  const WhatsAppTestMessageResult.success({
    String? messageId,
    String? mode,
    String? templateName,
    String? languageCode,
    bool fallbackUsed = false,
    int? metaStatusCode,
  }) : this._(
         ok: true,
         messageId: messageId,
         mode: mode,
         templateName: templateName,
         languageCode: languageCode,
         fallbackUsed: fallbackUsed,
         metaStatusCode: metaStatusCode,
       );

  const WhatsAppTestMessageResult.error(
    String message, {
    String? details,
    String? mode,
    bool fallbackUsed = false,
    int? metaStatusCode,
    int? statusCode,
  }) : this._(
         ok: false,
         message: message,
         details: details,
         mode: mode,
         fallbackUsed: fallbackUsed,
         metaStatusCode: metaStatusCode,
         statusCode: statusCode,
       );

  final bool ok;
  final String? message;
  final String? details;
  final String? messageId;
  final String? mode;
  final String? templateName;
  final String? languageCode;
  final bool fallbackUsed;
  final int? metaStatusCode;
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

bool _readBool(Object? decoded, String key) {
  return decoded is Map && decoded[key] == true;
}

int? _readIntFromDecoded(Object? decoded, String key) {
  if (decoded is Map) {
    return _readInt(decoded[key]);
  }
  return null;
}

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse(value?.toString() ?? '');
}
