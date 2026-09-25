import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'alert_configuration_contracts.dart';
import 'service_account_auth.dart';
import 'whatsapp_alert_recipients.dart' as legacy_recipients;

class AlertRecipientFirestoreDocument {
  const AlertRecipientFirestoreDocument({
    required this.id,
    required this.displayName,
    required this.phoneE164,
    required this.enabled,
    required this.updatedAt,
    required this.updatedBy,
    this.createdAt,
    this.createdBy,
    this.schemaVersion = 1,
  });

  factory AlertRecipientFirestoreDocument.fromRaw({
    required String id,
    required Map<String, Object?> raw,
  }) {
    final AlertRecipientFirestoreDocument document =
        AlertRecipientFirestoreDocument(
          id: id,
          displayName: raw['displayName']?.toString() ?? '',
          phoneE164: normalizeAlertRecipientPhoneE164(
            raw['phoneE164']?.toString() ?? '',
          ),
          enabled: raw['enabled'] == true,
          schemaVersion: _readOptionalNonNegativeInt(raw['schemaVersion']) ?? 0,
          createdAt: _readOptionalDateTime(raw['createdAt']),
          createdBy: raw['createdBy']?.toString(),
          updatedAt: _readOptionalDateTime(raw['updatedAt']),
          updatedBy: raw['updatedBy']?.toString() ?? '',
        );
    document.validate();
    return document;
  }

  final String id;
  final String displayName;
  final String phoneE164;
  final bool enabled;
  final DateTime? createdAt;
  final String? createdBy;
  final DateTime? updatedAt;
  final String updatedBy;
  final int schemaVersion;

  HierarchicalAlertRecipient toRecipient({
    required AlertRecipientConfigScope scope,
    required AlertConfigOrigin origin,
    required String tenantId,
    String? siteId,
    String? deviceId,
    String? roomId,
  }) {
    return HierarchicalAlertRecipient(
      id: id,
      displayName: displayName,
      phoneE164: phoneE164,
      enabled: enabled,
      scope: scope,
      origin: origin,
      tenantId: tenantId,
      siteId: siteId,
      deviceId: deviceId,
      roomId: roomId,
      createdAt: createdAt,
      createdBy: createdBy,
      updatedAt: updatedAt,
      updatedBy: updatedBy,
    );
  }

  Map<String, Object?> toFirestoreMap() {
    validate();
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'displayName': displayName,
      'phoneE164': phoneE164,
      'enabled': enabled,
      if (createdAt != null) 'createdAt': createdAt!.toUtc(),
      if (createdBy != null) 'createdBy': createdBy,
      'updatedAt': updatedAt!.toUtc(),
      'updatedBy': updatedBy,
    };
  }

  void validate() {
    if (schemaVersion != 1) {
      throw AlertRecipientDocumentException(
        'Unsupported alertRecipient schemaVersion: $schemaVersion',
      );
    }
    if (displayName.trim().isEmpty) {
      throw const AlertRecipientDocumentException('displayName is required');
    }
    if (!_isValidPhoneE164(phoneE164)) {
      throw AlertRecipientDocumentException('Invalid phoneE164: $phoneE164');
    }
    if (updatedAt == null) {
      throw const AlertRecipientDocumentException('updatedAt is required');
    }
    if (updatedBy.trim().isEmpty) {
      throw const AlertRecipientDocumentException('updatedBy is required');
    }
  }
}

class HierarchicalAlertRecipientsSnapshot {
  const HierarchicalAlertRecipientsSnapshot({
    this.tenant = const <HierarchicalAlertRecipient>[],
    this.site = const <HierarchicalAlertRecipient>[],
    this.device = const <HierarchicalAlertRecipient>[],
    this.room = const <HierarchicalAlertRecipient>[],
    this.readCount = 0,
  });

  final List<HierarchicalAlertRecipient> tenant;
  final List<HierarchicalAlertRecipient> site;
  final List<HierarchicalAlertRecipient> device;
  final List<HierarchicalAlertRecipient> room;
  final int readCount;
}

abstract class HierarchicalAlertRecipientLoader {
  Future<HierarchicalAlertRecipientsSnapshot> load(
    AlertConfigurationTarget target,
  );
}

class FirestoreHierarchicalAlertRecipientLoader
    implements HierarchicalAlertRecipientLoader {
  FirestoreHierarchicalAlertRecipientLoader({
    required String projectId,
    required String databaseId,
    required String serviceAccountJsonPath,
    HttpClient? httpClient,
    String? baseUrl,
    Future<String> Function()? accessTokenProvider,
  }) : _projectId = projectId,
       _databaseId = databaseId,
       _auth = ServiceAccountAuth(
         serviceAccountJsonPath: serviceAccountJsonPath,
       ),
       _httpClient = httpClient ?? HttpClient(),
       _baseUrl = baseUrl ?? 'https://firestore.googleapis.com',
       _accessTokenProvider = accessTokenProvider;

  final String _projectId;
  final String _databaseId;
  final ServiceAccountAuth _auth;
  final HttpClient _httpClient;
  final String _baseUrl;
  final Future<String> Function()? _accessTokenProvider;
  final Map<String, Future<_ListedAlertRecipients>> _memoizedCollections =
      <String, Future<_ListedAlertRecipients>>{};

  bool get isConfigured =>
      _projectId.trim().isNotEmpty &&
      _databaseId.trim().isNotEmpty &&
      (_accessTokenProvider != null ||
          _auth.serviceAccountJsonPath.trim().isNotEmpty);

  void clearMemoizedCollectionCache() {
    _memoizedCollections.clear();
  }

  @override
  Future<HierarchicalAlertRecipientsSnapshot> load(
    AlertConfigurationTarget target,
  ) async {
    if (!isConfigured) {
      throw const HierarchicalAlertRecipientLoaderException(
        'Firestore hierarchical alert recipient loader is not configured',
      );
    }
    final String token = await (_accessTokenProvider ?? _auth.getAccessToken)();
    int readCount = 0;

    final _ListedAlertRecipients tenantResult = await _listRecipients(
      token: token,
      collectionPath: 'tenants/${target.tenantId}/alertRecipients',
      scope: AlertRecipientConfigScope.tenant,
      origin: AlertConfigOrigin.tenant,
      tenantId: target.tenantId,
    );
    readCount += tenantResult.readCount;

    final _ListedAlertRecipients siteResult = await _listRecipients(
      token: token,
      collectionPath:
          'tenants/${target.tenantId}/sites/${target.siteId}/alertRecipients',
      scope: AlertRecipientConfigScope.site,
      origin: AlertConfigOrigin.site,
      tenantId: target.tenantId,
      siteId: target.siteId,
      allowMissing: true,
    );
    readCount += siteResult.readCount;

    _ListedAlertRecipients deviceResult = const _ListedAlertRecipients(
      recipients: <HierarchicalAlertRecipient>[],
      readCount: 0,
    );
    final String? deviceId = target.deviceId;
    if (deviceId != null && deviceId.trim().isNotEmpty) {
      deviceResult = await _listRecipients(
        token: token,
        collectionPath:
            'tenants/${target.tenantId}/devices/$deviceId/alertRecipients',
        scope: AlertRecipientConfigScope.device,
        origin: AlertConfigOrigin.device,
        tenantId: target.tenantId,
        siteId: target.siteId,
        deviceId: deviceId,
        allowMissing: true,
      );
      readCount += deviceResult.readCount;
    }

    _ListedAlertRecipients roomResult = const _ListedAlertRecipients(
      recipients: <HierarchicalAlertRecipient>[],
      readCount: 0,
    );
    final String? roomId = target.roomId;
    if (target.scope == AlertConfigurationScope.room &&
        deviceId != null &&
        deviceId.trim().isNotEmpty &&
        roomId != null &&
        roomId.trim().isNotEmpty) {
      roomResult = await _listRecipients(
        token: token,
        collectionPath:
            'tenants/${target.tenantId}/devices/$deviceId/rooms/$roomId/alertRecipients',
        scope: AlertRecipientConfigScope.room,
        origin: AlertConfigOrigin.room,
        tenantId: target.tenantId,
        siteId: target.siteId,
        deviceId: deviceId,
        roomId: roomId,
        allowMissing: true,
      );
      readCount += roomResult.readCount;
    }

    return HierarchicalAlertRecipientsSnapshot(
      tenant: tenantResult.recipients,
      site: siteResult.recipients,
      device: deviceResult.recipients,
      room: roomResult.recipients,
      readCount: readCount,
    );
  }

  Future<_ListedAlertRecipients> _listRecipients({
    required String token,
    required String collectionPath,
    required AlertRecipientConfigScope scope,
    required AlertConfigOrigin origin,
    required String tenantId,
    String? siteId,
    String? deviceId,
    String? roomId,
    bool allowMissing = false,
  }) async {
    final String cacheKey = '$scope|$collectionPath';
    final Future<_ListedAlertRecipients>? memoized =
        _memoizedCollections[cacheKey];
    if (memoized != null) {
      final _ListedAlertRecipients result = await memoized;
      return _ListedAlertRecipients(
        recipients: result.recipients,
        readCount: 0,
      );
    }
    final Future<_ListedAlertRecipients> future = _listRecipientsUncached(
      token: token,
      collectionPath: collectionPath,
      scope: scope,
      origin: origin,
      tenantId: tenantId,
      siteId: siteId,
      deviceId: deviceId,
      roomId: roomId,
      allowMissing: allowMissing,
    );
    _memoizedCollections[cacheKey] = future;
    return future;
  }

  Future<_ListedAlertRecipients> _listRecipientsUncached({
    required String token,
    required String collectionPath,
    required AlertRecipientConfigScope scope,
    required AlertConfigOrigin origin,
    required String tenantId,
    String? siteId,
    String? deviceId,
    String? roomId,
    required bool allowMissing,
  }) async {
    final HttpClientRequest request = await _httpClient.getUrl(
      _documentUri(collectionPath),
    );
    if (token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode == HttpStatus.notFound && allowMissing) {
      return const _ListedAlertRecipients(
        recipients: <HierarchicalAlertRecipient>[],
        readCount: 1,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HierarchicalAlertRecipientLoaderException(
        'Firestore alertRecipients LIST failed status=${response.statusCode} path=$collectionPath body=${_compact(body)}',
      );
    }
    final Map<String, dynamic> payload =
        jsonDecode(body) as Map<String, dynamic>;
    final Object? documentsRaw = payload['documents'];
    if (documentsRaw is! List) {
      return const _ListedAlertRecipients(
        recipients: <HierarchicalAlertRecipient>[],
        readCount: 1,
      );
    }
    return _ListedAlertRecipients(
      recipients: List<HierarchicalAlertRecipient>.unmodifiable(
        documentsRaw.whereType<Map<String, dynamic>>().map((
          Map<String, dynamic> document,
        ) {
          return AlertRecipientFirestoreDocument.fromRaw(
            id: _docId(document),
            raw: _decodeFields(document),
          ).toRecipient(
            scope: scope,
            origin: origin,
            tenantId: tenantId,
            siteId: siteId,
            deviceId: deviceId,
            roomId: roomId,
          );
        }),
      ),
      readCount: 1,
    );
  }

  Uri _documentUri(String documentPath) {
    return Uri.parse(
      '$_baseUrl/v1/projects/$_projectId'
      '/databases/$_databaseId/documents/$documentPath',
    );
  }
}

class HierarchicalAlertRecipientsCache {
  HierarchicalAlertRecipientsCache({
    required this.loader,
    this.resolver = const HierarchicalAlertRecipientResolver(),
    this.ttl = const Duration(hours: 6),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final HierarchicalAlertRecipientLoader loader;
  final HierarchicalAlertRecipientResolver resolver;
  final Duration ttl;
  final DateTime Function() _now;
  final Map<
    HierarchicalAlertRecipientsCacheKey,
    List<HierarchicalAlertRecipient>
  >
  _cache =
      <HierarchicalAlertRecipientsCacheKey, List<HierarchicalAlertRecipient>>{};
  final Map<HierarchicalAlertRecipientsCacheKey, DateTime> _loadedAt =
      <HierarchicalAlertRecipientsCacheKey, DateTime>{};
  final Map<
    HierarchicalAlertRecipientsCacheKey,
    Future<List<HierarchicalAlertRecipient>>
  >
  _inFlight =
      <
        HierarchicalAlertRecipientsCacheKey,
        Future<List<HierarchicalAlertRecipient>>
      >{};
  Object? _lastError;
  DateTime? _lastRefreshAt;
  int _lastReadCount = 0;

  int get size => _cache.length;

  int get lastReadCount => _lastReadCount;

  Object? get lastError => _lastError;

  DateTime? get lastRefreshAt => _lastRefreshAt;

  List<HierarchicalAlertRecipient>? get(AlertConfigurationTarget target) {
    return _cache[HierarchicalAlertRecipientsCacheKey.fromTarget(target)];
  }

  Future<List<HierarchicalAlertRecipient>> getOrLoad({
    required AlertConfigurationTarget target,
    Iterable<HierarchicalAlertRecipient> legacyRecipients =
        const <HierarchicalAlertRecipient>[],
  }) async {
    final HierarchicalAlertRecipientsCacheKey key =
        HierarchicalAlertRecipientsCacheKey.fromTarget(target);
    final List<HierarchicalAlertRecipient>? cached = _cache[key];
    final DateTime? loadedAt = _loadedAt[key];
    if (cached != null &&
        loadedAt != null &&
        _now().toUtc().difference(loadedAt) < ttl) {
      _lastReadCount = 0;
      return cached;
    }
    final Future<List<HierarchicalAlertRecipient>>? inFlight = _inFlight[key];
    if (inFlight != null) return inFlight;
    _clearLoaderOperationMemoizationIfNeeded();
    final Future<List<HierarchicalAlertRecipient>> future = _loadOne(
      target: target,
      legacyRecipients: legacyRecipients,
    );
    _inFlight[key] = future;
    try {
      return await future;
    } catch (error) {
      _lastError = error;
      _lastRefreshAt = _now().toUtc();
      rethrow;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<void> refreshTargets({
    required Iterable<AlertConfigurationTarget> targets,
    Iterable<HierarchicalAlertRecipient> legacyRecipients =
        const <HierarchicalAlertRecipient>[],
  }) async {
    _clearLoaderOperationMemoizationIfNeeded();
    int loaded = 0;
    int reads = 0;
    try {
      for (final AlertConfigurationTarget target in targets) {
        await _loadOne(target: target, legacyRecipients: legacyRecipients);
        loaded += 1;
        reads += _lastReadCount;
      }
      _lastReadCount = reads;
      _lastError = null;
      _lastRefreshAt = _now().toUtc();
      _logHierarchicalRecipients('refresh loadedTargets=$loaded reads=$reads');
    } catch (error) {
      _lastError = error;
      _lastRefreshAt = _now().toUtc();
      _logHierarchicalRecipients('refresh failed error=$error');
      rethrow;
    }
  }

  Map<String, Object?> healthJson({String mode = 'legacy'}) {
    return <String, Object?>{
      'mode': mode,
      'targets': _cache.length,
      'loaded': _cache.isNotEmpty,
      'lastRefreshAt': _lastRefreshAt?.toUtc().toIso8601String(),
      'lastError': _lastError?.toString(),
      'lastReadCount': _lastReadCount,
    };
  }

  Future<List<HierarchicalAlertRecipient>> _loadOne({
    required AlertConfigurationTarget target,
    required Iterable<HierarchicalAlertRecipient> legacyRecipients,
  }) async {
    final HierarchicalAlertRecipientsSnapshot snapshot = await loader.load(
      target,
    );
    final List<HierarchicalAlertRecipient> effective = resolver.resolve(
      legacyRecipients: legacyRecipients,
      tenantRecipients: snapshot.tenant,
      siteRecipients: target.scope == AlertConfigurationScope.tenant
          ? const <HierarchicalAlertRecipient>[]
          : snapshot.site,
      deviceRecipients:
          target.scope == AlertConfigurationScope.device ||
              target.scope == AlertConfigurationScope.room
          ? snapshot.device
          : const <HierarchicalAlertRecipient>[],
      roomRecipients: target.scope == AlertConfigurationScope.room
          ? snapshot.room
          : const <HierarchicalAlertRecipient>[],
    );
    final HierarchicalAlertRecipientsCacheKey key =
        HierarchicalAlertRecipientsCacheKey.fromTarget(target);
    _cache[key] = effective;
    _loadedAt[key] = _now().toUtc();
    _lastReadCount = snapshot.readCount;
    _lastRefreshAt = _now().toUtc();
    _lastError = null;
    return effective;
  }

  void _clearLoaderOperationMemoizationIfNeeded() {
    if (loader case final FirestoreHierarchicalAlertRecipientLoader loader) {
      loader.clearMemoizedCollectionCache();
    }
  }
}

class HierarchicalAlertRecipientsCacheKey {
  const HierarchicalAlertRecipientsCacheKey({
    required this.tenantId,
    required this.siteId,
    required this.deviceId,
    required this.roomId,
  });

  factory HierarchicalAlertRecipientsCacheKey.fromTarget(
    AlertConfigurationTarget target,
  ) {
    return HierarchicalAlertRecipientsCacheKey(
      tenantId: target.tenantId,
      siteId: target.siteId,
      deviceId: target.deviceId ?? '',
      roomId: target.roomId ?? '',
    );
  }

  final String tenantId;
  final String siteId;
  final String deviceId;
  final String roomId;

  @override
  bool operator ==(Object other) {
    return other is HierarchicalAlertRecipientsCacheKey &&
        other.tenantId == tenantId &&
        other.siteId == siteId &&
        other.deviceId == deviceId &&
        other.roomId == roomId;
  }

  @override
  int get hashCode => Object.hash(tenantId, siteId, deviceId, roomId);
}

class AlertRecipientComparison {
  const AlertRecipientComparison({
    required this.legacyOnly,
    required this.modernOnly,
    required this.both,
    required this.duplicates,
    required this.invalid,
  });

  final List<String> legacyOnly;
  final List<String> modernOnly;
  final List<String> both;
  final int duplicates;
  final int invalid;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'legacyOnly': legacyOnly.length,
      'modernOnly': modernOnly.length,
      'both': both.length,
      'duplicates': duplicates,
      'invalid': invalid,
    };
  }
}

AlertRecipientComparison compareLegacyAndModernRecipients({
  required Iterable<legacy_recipients.AlertRecipient> legacyRecipients,
  required Iterable<HierarchicalAlertRecipient> modernRecipients,
}) {
  final _PhoneSet legacy = _phoneSet(
    legacyRecipients.map(
      (legacy_recipients.AlertRecipient recipient) =>
          normalizeAlertRecipientPhoneE164(recipient.phone),
    ),
  );
  final _PhoneSet modern = _phoneSet(
    modernRecipients.map(
      (HierarchicalAlertRecipient recipient) => recipient.normalizedPhone,
    ),
  );
  return AlertRecipientComparison(
    legacyOnly: legacy.phones.difference(modern.phones).toList(growable: false),
    modernOnly: modern.phones.difference(legacy.phones).toList(growable: false),
    both: legacy.phones.intersection(modern.phones).toList(growable: false),
    duplicates: legacy.duplicates + modern.duplicates,
    invalid: legacy.invalid + modern.invalid,
  );
}

List<legacy_recipients.AlertRecipient> hierarchicalRecipientsToLegacySendList({
  required Iterable<HierarchicalAlertRecipient> recipients,
  required String tenantId,
  required String siteId,
  required String clientName,
  required String siteName,
}) {
  return List<legacy_recipients.AlertRecipient>.unmodifiable(
    recipients.map((HierarchicalAlertRecipient recipient) {
      return legacy_recipients.AlertRecipient(
        scope: legacy_recipients.AlertRecipientScope.tenantSite,
        tenantId: tenantId,
        siteId: siteId,
        clientName: clientName,
        siteName: siteName,
        contactName: recipient.displayName,
        phone: recipient.phoneE164,
      );
    }),
  );
}

_PhoneSet _phoneSet(Iterable<String> phones) {
  final Set<String> seen = <String>{};
  int duplicates = 0;
  int invalid = 0;
  for (final String phone in phones) {
    if (!_isValidPhoneE164(phone)) {
      invalid += 1;
      continue;
    }
    if (!seen.add(phone)) {
      duplicates += 1;
    }
  }
  return _PhoneSet(seen, duplicates, invalid);
}

bool _isValidPhoneE164(String phone) {
  final String normalized = phone.trim();
  if (!normalized.startsWith('+')) return false;
  final String digits = normalized.substring(1);
  return digits.length >= 8 &&
      digits.length <= 15 &&
      RegExp(r'^[0-9]+$').hasMatch(digits);
}

class _PhoneSet {
  const _PhoneSet(this.phones, this.duplicates, this.invalid);

  final Set<String> phones;
  final int duplicates;
  final int invalid;
}

class _ListedAlertRecipients {
  const _ListedAlertRecipients({
    required this.recipients,
    required this.readCount,
  });

  final List<HierarchicalAlertRecipient> recipients;
  final int readCount;
}

int? _readOptionalNonNegativeInt(Object? raw) {
  if (raw is int && raw >= 0) return raw;
  if (raw is num && raw.isFinite && raw >= 0) return raw.toInt();
  if (raw is String) {
    final int? parsed = int.tryParse(raw.trim());
    if (parsed != null && parsed >= 0) return parsed;
  }
  return null;
}

DateTime? _readOptionalDateTime(Object? raw) {
  if (raw is DateTime) return raw;
  if (raw is String) return DateTime.tryParse(raw);
  return null;
}

String _docId(Map<String, dynamic> document) =>
    (document['name']?.toString() ?? '').split('/').last;

Map<String, Object?> _decodeFields(Map<String, dynamic> document) {
  final Map<String, dynamic> fields =
      document['fields'] as Map<String, dynamic>? ?? <String, dynamic>{};
  return fields.map(
    (String key, dynamic value) => MapEntry(key, _decodeFirestoreValue(value)),
  );
}

Object? _decodeFirestoreValue(Object? value) {
  if (value is! Map) return null;
  final Map<Object?, Object?> field = value;
  if (field.containsKey('nullValue')) return null;
  if (field.containsKey('stringValue')) return field['stringValue']?.toString();
  if (field.containsKey('booleanValue')) return field['booleanValue'] == true;
  if (field.containsKey('integerValue')) {
    return int.tryParse(field['integerValue'].toString());
  }
  if (field.containsKey('doubleValue')) {
    return double.tryParse(field['doubleValue'].toString());
  }
  if (field.containsKey('timestampValue')) {
    return field['timestampValue']?.toString();
  }
  return null;
}

String _compact(Object value) {
  final String compacted = value
      .toString()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (compacted.length <= 240) return compacted;
  return '${compacted.substring(0, 240)}...';
}

void _logHierarchicalRecipients(String message) {
  stdout.writeln('[hierarchical-alert-recipients] $message');
}

class HierarchicalAlertRecipientLoaderException implements Exception {
  const HierarchicalAlertRecipientLoaderException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AlertRecipientDocumentException implements Exception {
  const AlertRecipientDocumentException(this.message);

  final String message;

  @override
  String toString() => message;
}
