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
  static const String defaultTestTemplateName = 'agrodata_alerts';
  static const String defaultTemplateLanguageCode = 'es_AR';

  Future<WhatsAppSendResult> sendWhatsAppMessage({
    required String tenantId,
    required String to,
    required String message,
    bool preferText = true,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    final String attemptedMode = preferText ? 'text' : 'template';
    String finalMode = 'failed';
    bool fallbackUsed = false;
    int? statusCode;
    String? metaErrorCode;
    String? metaErrorMessage;
    String? templateName;
    String? languageCode;

    try {
      if (!preferText) {
        final WhatsAppSendResult result = await sendTemplateMessage(
          tenantId: tenantId,
          to: to,
          message: message,
        );
        finalMode = result.mode;
        statusCode = result.metaStatusCode;
        templateName = result.templateName;
        languageCode = result.languageCode;
        return result;
      }

      try {
        final WhatsAppSendResult result = await sendTextMessage(
          tenantId: tenantId,
          to: to,
          message: message,
        );
        finalMode = result.mode;
        statusCode = result.metaStatusCode;
        templateName = result.templateName;
        languageCode = result.languageCode;
        return result;
      } on WhatsAppServiceException catch (error) {
        statusCode = error.metaStatusCode ?? error.statusCode;
        metaErrorCode = error.metaErrorCode;
        metaErrorMessage = error.metaErrorMessage;
        if (!_shouldFallbackToTemplate(error)) {
          rethrow;
        }
      }

      fallbackUsed = true;
      try {
        final WhatsAppSendResult result = await sendTemplateMessage(
          tenantId: tenantId,
          to: to,
          message: message,
        );
        finalMode = result.mode;
        statusCode = result.metaStatusCode;
        templateName = result.templateName;
        languageCode = result.languageCode;
        return result.copyWith(fallbackUsed: true);
      } on WhatsAppServiceException catch (error) {
        finalMode = 'template';
        throw error.copyWith(
          attemptedMode: attemptedMode,
          finalMode: finalMode,
          fallbackUsed: fallbackUsed,
        );
      }
    } on WhatsAppServiceException catch (error) {
      statusCode = error.metaStatusCode ?? error.statusCode;
      metaErrorCode = error.metaErrorCode;
      metaErrorMessage = error.metaErrorMessage;
      rethrow;
    } finally {
      stopwatch.stop();
      _logWhatsApp(
        'tenant=$tenantId to=${_maskPhone(to)} messageLength=${message.length} modeAttempted=$attemptedMode modeFinal=$finalMode fallbackUsed=$fallbackUsed template=${templateName ?? ''} language=${languageCode ?? ''} status=${statusCode?.toString() ?? 'none'} metaErrorCode=${metaErrorCode ?? ''} metaErrorMessage=${metaErrorMessage ?? ''} elapsed=${stopwatch.elapsedMilliseconds}ms',
      );
    }
  }

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

      final Uri uri = Uri.parse(
        'https://graph.facebook.com/v23.0/$phoneNumberId/messages',
      );
      final Map<String, Object?> requestBody = <String, Object?>{
        'messaging_product': 'whatsapp',
        'to': to,
        'type': 'text',
        'text': <String, Object?>{'body': message},
      };

      final WhatsAppSendResult result = await _sendMessagePayload(
        uri: uri,
        token: token,
        requestBody: requestBody,
        mode: 'text',
        setStatusCode: (int value) => statusCode = value,
        setOutcome: (String value) => outcome = value,
      );
      outcome = 'sent';
      return result;
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
        'tenant=$tenantId to=${_maskPhone(to)} type=text status=${statusCode?.toString() ?? outcome} elapsed=${stopwatch.elapsedMilliseconds}ms outcome=$outcome',
      );
    }
  }

  Future<WhatsAppSendResult> sendTemplateMessage({
    required String tenantId,
    required String to,
    String? message,
    String? templateName,
    String? languageCode,
    List<String>? bodyParameters,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    int? statusCode;
    String outcome = 'unexpected';
    String? metaErrorCode;
    String? metaErrorMessage;
    final String effectiveTemplateName = templateName?.trim().isNotEmpty == true
        ? templateName!.trim()
        : testTemplateName();
    final String effectiveLanguageCode = languageCode?.trim().isNotEmpty == true
        ? languageCode!.trim()
        : templateLanguageCode();
    final List<String> effectiveBodyParameters =
        bodyParameters ??
        (message == null ? const <String>[] : <String>[message]);

    try {
      final String token = _requiredEnv('WHATSAPP_TOKEN');
      final String phoneNumberId = _requiredEnv('WHATSAPP_PHONE_NUMBER_ID');

      final Uri uri = Uri.parse(
        'https://graph.facebook.com/v23.0/$phoneNumberId/messages',
      );
      final Map<String, Object?> template = <String, Object?>{
        'name': effectiveTemplateName,
        'language': <String, Object?>{'code': effectiveLanguageCode},
      };
      if (effectiveBodyParameters.isNotEmpty) {
        template['components'] = <Map<String, Object?>>[
          <String, Object?>{
            'type': 'body',
            'parameters': effectiveBodyParameters
                .map(
                  (String value) => <String, Object?>{
                    'type': 'text',
                    'text': value,
                  },
                )
                .toList(),
          },
        ];
      }
      final Map<String, Object?> requestBody = <String, Object?>{
        'messaging_product': 'whatsapp',
        'to': to,
        'type': 'template',
        'template': template,
      };

      final WhatsAppSendResult result = await _sendMessagePayload(
        uri: uri,
        token: token,
        requestBody: requestBody,
        mode: 'template',
        templateName: effectiveTemplateName,
        languageCode: effectiveLanguageCode,
        setStatusCode: (int value) => statusCode = value,
        setOutcome: (String value) => outcome = value,
      );
      outcome = 'sent';
      return result;
    } on TimeoutException {
      outcome = WhatsAppErrorKind.timeout.name;
      throw WhatsAppServiceException(
        kind: WhatsAppErrorKind.timeout,
        message: 'WhatsApp request timeout',
        statusCode: HttpStatus.gatewayTimeout,
        details:
            'Meta Cloud API did not respond within ${_requestTimeout.inSeconds}s',
      );
    } on WhatsAppServiceException catch (error) {
      metaErrorCode = error.metaErrorCode;
      metaErrorMessage = error.metaErrorMessage;
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
        'tenant=$tenantId to=${_maskPhone(to)} messageLength=${message?.length ?? 0} type=template template=$effectiveTemplateName language=$effectiveLanguageCode status=${statusCode?.toString() ?? outcome} metaErrorCode=${metaErrorCode ?? ''} metaErrorMessage=${metaErrorMessage ?? ''} elapsed=${stopwatch.elapsedMilliseconds}ms outcome=$outcome',
      );
    }
  }

  String testTemplateName() => defaultTestTemplateName;

  String templateLanguageCode() => defaultTemplateLanguageCode;

  Future<WhatsAppSendResult> _sendMessagePayload({
    required Uri uri,
    required String token,
    required Map<String, Object?> requestBody,
    required String mode,
    String? templateName,
    String? languageCode,
    required void Function(int statusCode) setStatusCode,
    required void Function(String outcome) setOutcome,
  }) async {
    final ({Object? decodedBody, String responseBody, int statusCode})
    metaResponse = await _sendMetaRequest(
      uri: uri,
      token: token,
      requestBody: requestBody,
    ).timeout(_requestTimeout);
    setStatusCode(metaResponse.statusCode);

    if (metaResponse.statusCode < 200 || metaResponse.statusCode >= 300) {
      setOutcome(WhatsAppErrorKind.http.name);
      throw WhatsAppServiceException(
        kind: WhatsAppErrorKind.http,
        message: _summarizeMetaError(
          metaResponse.decodedBody,
          metaResponse.statusCode,
        ),
        statusCode: metaResponse.statusCode,
        metaStatusCode: metaResponse.statusCode,
        metaErrorCode: _metaErrorCode(metaResponse.decodedBody),
        metaErrorMessage: _metaErrorMessage(metaResponse.decodedBody),
        details: _metaErrorDetails(
          metaResponse.decodedBody,
          metaResponse.statusCode,
        ),
      );
    }

    if (metaResponse.decodedBody is! Map) {
      setOutcome(WhatsAppErrorKind.invalidResponse.name);
      throw WhatsAppServiceException(
        kind: WhatsAppErrorKind.invalidResponse,
        message: 'Invalid WhatsApp response',
        statusCode: HttpStatus.badGateway,
        metaStatusCode: metaResponse.statusCode,
        details: 'Meta returned a non-JSON object response',
      );
    }

    final Map<String, Object?> raw = Map<String, Object?>.from(
      metaResponse.decodedBody! as Map,
    );
    final String? messageId = _extractMessageId(raw);
    if (messageId == null || messageId.isEmpty) {
      setOutcome(WhatsAppErrorKind.invalidResponse.name);
      throw WhatsAppServiceException(
        kind: WhatsAppErrorKind.invalidResponse,
        message: 'Invalid WhatsApp response',
        statusCode: HttpStatus.badGateway,
        metaStatusCode: metaResponse.statusCode,
        details: 'Meta response did not include messages[0].id',
      );
    }

    return WhatsAppSendResult(
      messageId: messageId,
      raw: raw,
      mode: mode,
      fallbackUsed: false,
      metaStatusCode: metaResponse.statusCode,
      templateName: templateName,
      languageCode: languageCode,
    );
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
  const WhatsAppSendResult({
    required this.messageId,
    required this.raw,
    required this.mode,
    required this.fallbackUsed,
    required this.metaStatusCode,
    this.templateName,
    this.languageCode,
  });

  final String? messageId;
  final Map<String, Object?> raw;
  final String mode;
  final bool fallbackUsed;
  final int metaStatusCode;
  final String? templateName;
  final String? languageCode;

  WhatsAppSendResult copyWith({bool? fallbackUsed}) {
    return WhatsAppSendResult(
      messageId: messageId,
      raw: raw,
      mode: mode,
      fallbackUsed: fallbackUsed ?? this.fallbackUsed,
      metaStatusCode: metaStatusCode,
      templateName: templateName,
      languageCode: languageCode,
    );
  }
}

class WhatsAppServiceException implements Exception {
  WhatsAppServiceException({
    required this.kind,
    required this.message,
    required this.statusCode,
    this.metaStatusCode,
    this.metaErrorCode,
    this.metaErrorMessage,
    this.attemptedMode,
    this.finalMode,
    this.fallbackUsed = false,
    this.details,
  });

  final WhatsAppErrorKind kind;
  final String message;
  final int statusCode;
  final int? metaStatusCode;
  final String? metaErrorCode;
  final String? metaErrorMessage;
  final String? attemptedMode;
  final String? finalMode;
  final bool fallbackUsed;
  final Object? details;

  WhatsAppServiceException copyWith({
    String? attemptedMode,
    String? finalMode,
    bool? fallbackUsed,
  }) {
    return WhatsAppServiceException(
      kind: kind,
      message: message,
      statusCode: statusCode,
      metaStatusCode: metaStatusCode,
      metaErrorCode: metaErrorCode,
      metaErrorMessage: metaErrorMessage,
      attemptedMode: attemptedMode ?? this.attemptedMode,
      finalMode: finalMode ?? this.finalMode,
      fallbackUsed: fallbackUsed ?? this.fallbackUsed,
      details: details,
    );
  }

  @override
  String toString() => message;
}

enum WhatsAppErrorKind { timeout, http, invalidResponse, unexpected }

bool _shouldFallbackToTemplate(WhatsAppServiceException error) {
  if (error.kind != WhatsAppErrorKind.http) {
    return false;
  }

  final String code = error.metaErrorCode ?? '';
  if (code == '131047') {
    return true;
  }

  final String message = <String>[
    error.metaErrorMessage ?? '',
    error.message,
    error.details?.toString() ?? '',
  ].join(' ').toLowerCase();

  if (error.metaStatusCode == HttpStatus.unauthorized ||
      error.metaStatusCode == HttpStatus.forbidden ||
      <String>{'10', '100', '190', '200', '131026'}.contains(code) ||
      message.contains('access token') ||
      message.contains('oauth') ||
      message.contains('permission') ||
      message.contains('phone_number_id') ||
      message.contains('invalid parameter') ||
      message.contains('invalid phone') ||
      message.contains('invalid recipient') ||
      message.contains('not a valid whatsapp')) {
    return false;
  }

  final bool mentionsConversationWindow =
      message.contains('24 hour') ||
      message.contains('24-hour') ||
      message.contains('outside the allowed window') ||
      message.contains('outside of the allowed window') ||
      message.contains('conversation window') ||
      message.contains('customer care window') ||
      message.contains('re-engagement') ||
      message.contains('template required') ||
      message.contains('template message');
  final bool mentionsNonTemplate =
      message.contains('non-template') || message.contains('non template');
  return mentionsConversationWindow || mentionsNonTemplate;
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
      final Object? message = error['message'];
      final Object? type = error['type'];
      final Object? code = error['code'];
      final Object? subcode = error['error_subcode'];
      final Object? fbtraceId = error['fbtrace_id'];
      if (message != null) {
        parts.add('message=$message');
      }
      if (type != null) {
        parts.add('type=$type');
      }
      if (code != null) {
        parts.add('code=$code');
      }
      if (subcode != null) {
        parts.add('subcode=$subcode');
      }
      if (fbtraceId != null) {
        parts.add('fbtrace_id=$fbtraceId');
      }
      if (parts.isNotEmpty) {
        return parts.join(' ');
      }
    }
  }
  return 'Meta HTTP status=$statusCode';
}

String? _metaErrorCode(Object? decodedBody) {
  if (decodedBody is Map) {
    final Object? error = decodedBody['error'];
    if (error is Map) {
      final Object? code = error['code'];
      return code?.toString();
    }
  }
  return null;
}

String? _metaErrorMessage(Object? decodedBody) {
  if (decodedBody is Map) {
    final Object? error = decodedBody['error'];
    if (error is Map) {
      final Object? message = error['message'];
      if (message != null && message.toString().trim().isNotEmpty) {
        return message.toString();
      }
    }
  }
  return null;
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
