import 'dart:convert';
import 'dart:io';

import 'alert_settings_cache.dart';
import 'service_account_auth.dart';

class FirestoreAlertSettingsLoader implements AlertSettingsLoader {
  FirestoreAlertSettingsLoader({
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

  bool get isConfigured =>
      _projectId.trim().isNotEmpty &&
      _databaseId.trim().isNotEmpty &&
      _auth.serviceAccountJsonPath.trim().isNotEmpty;

  @override
  Future<Map<String, Object?>?> load(String tenantId, String siteId) async {
    if (!isConfigured) {
      throw const AlertSettingsLoaderException(
        'Firestore alert settings loader is not configured',
      );
    }
    final String token = await _auth.getAccessToken();
    final String documentPath =
        'tenants/$tenantId/sites/$siteId/settings/controlDashboard';
    final Uri uri = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$_projectId'
      '/databases/$_databaseId/documents/$documentPath',
    );
    final HttpClientRequest request = await _httpClient.getUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode == HttpStatus.notFound) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AlertSettingsLoaderException(
        'Firestore alert settings GET failed status=${response.statusCode} path=$documentPath body=${_compact(body)}',
      );
    }
    final Map<String, dynamic> document =
        jsonDecode(body) as Map<String, dynamic>;
    final Map<String, dynamic> fields =
        document['fields'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return fields.map(
      (String key, dynamic value) =>
          MapEntry(key, _decodeFirestoreValue(value)),
    );
  }
}

Object? _decodeFirestoreValue(Object? value) {
  if (value is! Map) {
    return null;
  }
  final Map<Object?, Object?> field = value;
  if (field.containsKey('nullValue')) {
    return null;
  }
  if (field.containsKey('stringValue')) {
    return field['stringValue']?.toString();
  }
  if (field.containsKey('booleanValue')) {
    return field['booleanValue'] == true;
  }
  if (field.containsKey('integerValue')) {
    return int.tryParse(field['integerValue'].toString());
  }
  if (field.containsKey('doubleValue')) {
    return double.tryParse(field['doubleValue'].toString());
  }
  if (field.containsKey('timestampValue')) {
    return field['timestampValue']?.toString();
  }
  if (field['mapValue'] is Map) {
    final Object? rawFields = (field['mapValue'] as Map)['fields'];
    if (rawFields is Map) {
      return rawFields.map(
        (Object? key, Object? nestedValue) =>
            MapEntry(key.toString(), _decodeFirestoreValue(nestedValue)),
      );
    }
    return const <String, Object?>{};
  }
  if (field['arrayValue'] is Map) {
    final Object? values = (field['arrayValue'] as Map)['values'];
    if (values is List) {
      return values.map(_decodeFirestoreValue).toList(growable: false);
    }
    return const <Object?>[];
  }
  return null;
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

class AlertSettingsLoaderException implements Exception {
  const AlertSettingsLoaderException(this.message);

  final String message;

  @override
  String toString() => message;
}
