import 'dart:async';
import 'dart:convert';
import 'dart:io';

class WhatsAppService {
  WhatsAppService({Map<String, String>? environment, HttpClient? httpClient})
    : _environment = environment ?? Platform.environment,
      _httpClient = httpClient ?? HttpClient();

  final Map<String, String> _environment;
  final HttpClient _httpClient;

  static const String provider = 'meta_cloud_api';
  static const Duration _requestTimeout = Duration(seconds: 10);

  Future<WhatsAppSendResult> sendTextMessage({
    required String tenantId,
    required String to,
    required String message,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    int? statusCode;
    String outcome = 'unexpected';

    try {
      final String token = _requiredEnv('WHATSAPP_TOKEN');
      final String phoneNumberId = _requiredEnv('WHATSAPP_PHONE_NUMBER_ID');
      final String apiVersion =
          _environment['WHATSAPP_API_VERSION']?.trim().isNotEmpty == true
          ? _environment['WHATSAPP_API_VERSION']!.trim()
          : 'v23.0';

      final Uri uri = Uri.parse(
        'https://graph.facebook.com/$apiVersion/$phoneNumberId/messages',
      );
      final Map<String, Object?> requestBody = <String, Object?>{
        'messaging_product': 'whatsapp',
        'to': to,
        'type': 'text',
        'text': <String, Object?>{'body': message},
      };

      final ({Object? decodedBody, String responseBody, int statusCode})
      metaResponse = await _sendMetaRequest(
        uri: uri,
        token: token,
        requestBody: requestBody,
      ).timeout(_requestTimeout);
      statusCode = metaResponse.statusCode;

      if (statusCode < 200 || statusCode >= 300) {
        outcome = WhatsAppErrorKind.http.name;
        throw WhatsAppServiceException(
          kind: WhatsAppErrorKind.http,
          message: _summarizeMetaError(metaResponse.decodedBody, statusCode),
          statusCode: statusCode,
          details: _metaErrorDetails(metaResponse.decodedBody, statusCode),
        );
      }

      if (metaResponse.decodedBody is! Map) {
        outcome = WhatsAppErrorKind.invalidResponse.name;
        throw WhatsAppServiceException(
          kind: WhatsAppErrorKind.invalidResponse,
          message: 'Invalid WhatsApp response',
          statusCode: HttpStatus.badGateway,
          metaStatusCode: statusCode,
          details: 'Meta returned a non-JSON object response',
        );
      }

      final Map<String, Object?> raw = Map<String, Object?>.from(
        metaResponse.decodedBody! as Map,
      );
      final String? messageId = _extractMessageId(raw);
      if (messageId == null || messageId.isEmpty) {
        outcome = WhatsAppErrorKind.invalidResponse.name;
        throw WhatsAppServiceException(
          kind: WhatsAppErrorKind.invalidResponse,
          message: 'Invalid WhatsApp response',
          statusCode: HttpStatus.badGateway,
          metaStatusCode: statusCode,
          details: 'Meta response did not include messages[0].id',
        );
      }

      outcome = 'sent';
      return WhatsAppSendResult(messageId: messageId, raw: raw);
    } on TimeoutException {
      outcome = WhatsAppErrorKind.timeout.name;
      throw WhatsAppServiceException(
        kind: WhatsAppErrorKind.timeout,
        message: 'WhatsApp request timeout',
        statusCode: HttpStatus.gatewayTimeout,
        details:
            'Meta Cloud API did not respond within ${_requestTimeout.inSeconds}s',
      );
    } on WhatsAppServiceException {
      rethrow;
    } catch (error) {
      outcome = WhatsAppErrorKind.unexpected.name;
      throw WhatsAppServiceException(
        kind: WhatsAppErrorKind.unexpected,
        message: 'Unexpected WhatsApp error',
        statusCode: HttpStatus.badGateway,
        metaStatusCode: statusCode,
        details: error.toString(),
      );
    } finally {
      stopwatch.stop();
      _logWhatsApp(
        'tenant=$tenantId to=${_maskPhone(to)} status=${statusCode?.toString() ?? outcome} elapsed=${stopwatch.elapsedMilliseconds}ms outcome=$outcome',
      );
    }
  }

  Future<({Object? decodedBody, String responseBody, int statusCode})>
  _sendMetaRequest({
    required Uri uri,
    required String token,
    required Map<String, Object?> requestBody,
  }) async {
    final HttpClientRequest request = await _httpClient.postUrl(uri);
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..set(HttpHeaders.contentTypeHeader, 'application/json');
    request.write(jsonEncode(requestBody));

    final HttpClientResponse response = await request.close();
    final String responseBody = await response.transform(utf8.decoder).join();
    return (
      decodedBody: _tryDecodeJson(responseBody),
      responseBody: responseBody,
      statusCode: response.statusCode,
    );
  }

  String _requiredEnv(String name) {
    final String? value = _environment[name];
    if (value == null || value.trim().isEmpty) {
      throw WhatsAppServiceException(
        kind: WhatsAppErrorKind.unexpected,
        message: 'Missing required environment variable $name',
        statusCode: HttpStatus.serviceUnavailable,
        details: 'Backend environment variable is not configured',
      );
    }
    return value.trim();
  }
}

class WhatsAppSendResult {
  const WhatsAppSendResult({required this.messageId, required this.raw});

  final String? messageId;
  final Map<String, Object?> raw;
}

class WhatsAppServiceException implements Exception {
  WhatsAppServiceException({
    required this.kind,
    required this.message,
    required this.statusCode,
    this.metaStatusCode,
    this.details,
  });

  final WhatsAppErrorKind kind;
  final String message;
  final int statusCode;
  final int? metaStatusCode;
  final Object? details;

  @override
  String toString() => message;
}

enum WhatsAppErrorKind { timeout, http, invalidResponse, unexpected }

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

String _summarizeMetaError(Object? decodedBody, int statusCode) {
  if (decodedBody is Map) {
    final Object? error = decodedBody['error'];
    if (error is Map) {
      final Object? message = error['message'];
      if (message != null && message.toString().trim().isNotEmpty) {
        return message.toString();
      }
    }
  }
  return 'Meta WhatsApp API request failed status=$statusCode';
}

String _metaErrorDetails(Object? decodedBody, int statusCode) {
  if (decodedBody is Map) {
    final Object? error = decodedBody['error'];
    if (error is Map) {
      final List<String> parts = <String>[];
      final Object? type = error['type'];
      final Object? code = error['code'];
      final Object? subcode = error['error_subcode'];
      if (type != null) {
        parts.add('type=$type');
      }
      if (code != null) {
        parts.add('code=$code');
      }
      if (subcode != null) {
        parts.add('subcode=$subcode');
      }
      if (parts.isNotEmpty) {
        return parts.join(' ');
      }
    }
  }
  return 'Meta HTTP status=$statusCode';
}

String? _extractMessageId(Map<String, Object?> raw) {
  final Object? messages = raw['messages'];
  if (messages is List && messages.isNotEmpty) {
    final Object? first = messages.first;
    if (first is Map) {
      final Object? id = first['id'];
      if (id != null && id.toString().isNotEmpty) {
        return id.toString();
      }
    }
  }
  return null;
}

String _maskPhone(String phone) {
  if (phone.length <= 4) {
    return '****';
  }
  final String suffix = phone.substring(phone.length - 4);
  final String prefix = phone.length >= 5 ? phone.substring(0, 5) : '';
  return '$prefix******$suffix';
}

void _logWhatsApp(String message) {
  stdout.writeln('[WhatsApp] $message');
}
