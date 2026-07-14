import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';

class WhatsAppAlertRecipientsService {
  const WhatsAppAlertRecipientsService({String? backendSnapshotEndpoint})
    : _backendSnapshotEndpoint = backendSnapshotEndpoint;

  static const Duration _requestTimeout = Duration(seconds: 8);

  final String? _backendSnapshotEndpoint;

  Future<WhatsAppAlertRecipientsResult> fetchRecipients({
    required String siteId,
  }) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const WhatsAppAlertRecipientsResult.error(
        'No hay usuario autenticado.',
      );
    }

    final String idToken = await user.getIdToken(true) ?? '';
    if (idToken.isEmpty) {
      return const WhatsAppAlertRecipientsResult.error(
        'No se pudo obtener el token de autenticacion.',
      );
    }

    final Uri uri = _resolveRecipientsUri(siteId: siteId);
    try {
      final http.Response response = await http
          .get(
            uri,
            headers: <String, String>{'Authorization': 'Bearer $idToken'},
          )
          .timeout(_requestTimeout);

      final Object? decoded = _tryDecodeJson(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final String? backendError = _readString(decoded, 'error');
        if (_isTenantContextError(backendError) ||
            _isTenantContextError(_readString(decoded, 'details'))) {
          return const WhatsAppAlertRecipientsResult.error(
            'No se pudo cargar la configuración de destinatarios. Cerrá sesión y volvé a ingresar para actualizar tus permisos.',
          );
        }
        return WhatsAppAlertRecipientsResult.error(
          backendError ?? 'El backend respondio HTTP ${response.statusCode}.',
        );
      }
      if (decoded is! Map) {
        return const WhatsAppAlertRecipientsResult.error(
          'El backend devolvio una respuesta invalida.',
        );
      }

      final List<WhatsAppAlertRecipient> recipients =
          (decoded['recipients'] is List ? decoded['recipients'] as List : [])
              .whereType<Map>()
              .map(
                (Map value) => WhatsAppAlertRecipient.fromJson(
                  Map<String, Object?>.from(value),
                ),
              )
              .toList(growable: false);
      return WhatsAppAlertRecipientsResult.success(
        enabled: decoded['enabled'] == true,
        recipientCount:
            _readInt(decoded, 'recipientCount') ?? recipients.length,
        recipients: recipients,
        runtimeControl: decoded['runtimeControl'] is Map
            ? AlertRuntimeControl.fromJson(
                Map<String, Object?>.from(decoded['runtimeControl'] as Map),
              )
            : null,
      );
    } on TimeoutException {
      return const WhatsAppAlertRecipientsResult.error(
        'El backend no respondio a tiempo.',
      );
    } on http.ClientException catch (error) {
      return WhatsAppAlertRecipientsResult.error(
        'No se pudo conectar con el backend.',
        details: error.message,
      );
    } catch (error) {
      return WhatsAppAlertRecipientsResult.error(
        'Fallo la carga de destinatarios.',
        details: error.toString(),
      );
    }
  }

  Uri _resolveRecipientsUri({required String siteId}) {
    final String endpoint = _backendSnapshotEndpoint?.trim().isNotEmpty == true
        ? _backendSnapshotEndpoint!.trim()
        : AppConfig.currentBackendSnapshotUrl;
    final Uri snapshotUri = Uri.parse(endpoint);
    return snapshotUri.replace(
      path: '/api/whatsapp/alert-recipients',
      queryParameters: <String, String>{'siteId': siteId},
    );
  }
}

bool _isTenantContextError(String? value) {
  final String normalized = value?.toLowerCase() ?? '';
  return normalized.contains('tenant context') ||
      normalized.contains('tenantid') ||
      normalized.contains('siteid') ||
      normalized.contains('claims');
}

class WhatsAppAlertRecipientsResult {
  const WhatsAppAlertRecipientsResult._({
    required this.ok,
    this.enabled = false,
    this.recipientCount = 0,
    this.recipients = const <WhatsAppAlertRecipient>[],
    this.runtimeControl,
    this.message,
    this.details,
  });

  const WhatsAppAlertRecipientsResult.success({
    required bool enabled,
    required int recipientCount,
    required List<WhatsAppAlertRecipient> recipients,
    AlertRuntimeControl? runtimeControl,
  }) : this._(
         ok: true,
         enabled: enabled,
         recipientCount: recipientCount,
         recipients: recipients,
         runtimeControl: runtimeControl,
       );

  const WhatsAppAlertRecipientsResult.error(String message, {String? details})
    : this._(ok: false, message: message, details: details);

  final bool ok;
  final bool enabled;
  final int recipientCount;
  final List<WhatsAppAlertRecipient> recipients;
  final AlertRuntimeControl? runtimeControl;
  final String? message;
  final String? details;
}

class AlertRuntimeControl {
  const AlertRuntimeControl({
    required this.cooldownMinutes,
    required this.dewPointRiskC,
    required this.temperatureC,
    required this.humidityPercent,
  });

  factory AlertRuntimeControl.fromJson(Map<String, Object?> json) {
    final Object? hysteresisRaw = json['hysteresis'];
    final Map<String, Object?> hysteresis = hysteresisRaw is Map
        ? Map<String, Object?>.from(hysteresisRaw)
        : const <String, Object?>{};
    return AlertRuntimeControl(
      cooldownMinutes: _readInt(json, 'cooldownMinutes') ?? 0,
      dewPointRiskC: _readDouble(hysteresis, 'dewPointRiskC') ?? 0,
      temperatureC: _readDouble(hysteresis, 'temperatureC') ?? 0,
      humidityPercent: _readDouble(hysteresis, 'humidityPercent') ?? 0,
    );
  }

  final int cooldownMinutes;
  final double dewPointRiskC;
  final double temperatureC;
  final double humidityPercent;
}

class WhatsAppAlertRecipient {
  const WhatsAppAlertRecipient({
    required this.clientName,
    required this.siteName,
    required this.contactName,
    required this.phoneMasked,
  });

  factory WhatsAppAlertRecipient.fromJson(Map<String, Object?> json) {
    return WhatsAppAlertRecipient(
      clientName: json['clientName']?.toString() ?? '',
      siteName: json['siteName']?.toString() ?? '',
      contactName: json['contactName']?.toString() ?? '',
      phoneMasked: json['phoneMasked']?.toString() ?? '',
    );
  }

  final String clientName;
  final String siteName;
  final String contactName;
  final String phoneMasked;
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
  if (decoded is Map) {
    final Object? value = decoded[key];
    if (value != null) {
      return value.toString();
    }
  }
  return null;
}

int? _readInt(Object? decoded, String key) {
  if (decoded is Map) {
    final Object? value = decoded[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value != null) {
      return int.tryParse(value.toString());
    }
  }
  return null;
}

double? _readDouble(Object? decoded, String key) {
  if (decoded is Map) {
    final Object? value = decoded[key];
    if (value is num) {
      return value.toDouble();
    }
    if (value != null) {
      return double.tryParse(value.toString());
    }
  }
  return null;
}
