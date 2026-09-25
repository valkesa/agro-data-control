import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'alert_configuration_contracts.dart';
import 'alert_processing_coordinator.dart';
import 'service_account_auth.dart';

enum AlertTopologyMode {
  legacy,
  validate,
  dynamic;

  static AlertTopologyMode fromWireName(Object? raw) {
    final String value = raw?.toString().trim().toLowerCase() ?? '';
    return switch (value) {
      'validate' => AlertTopologyMode.validate,
      'dynamic' => AlertTopologyMode.dynamic,
      _ => AlertTopologyMode.legacy,
    };
  }

  String get wireName => name;
}

enum AlertTopologySource { legacyFallback, firestore, fixture }

class OperationalAlertTopology {
  OperationalAlertTopology({
    required this.tenantId,
    required this.siteId,
    required List<OperationalAlertDevice> devices,
    this.source = AlertTopologySource.firestore,
    this.loadedAt,
    List<String> warnings = const <String>[],
  }) : devices = List<OperationalAlertDevice>.unmodifiable(devices),
       warnings = List<String>.unmodifiable(warnings);

  final String tenantId;
  final String siteId;
  final List<OperationalAlertDevice> devices;
  final AlertTopologySource source;
  final DateTime? loadedAt;
  final List<String> warnings;

  List<OperationalAlertTarget> get targets {
    final List<OperationalAlertTarget> result = <OperationalAlertTarget>[];
    for (final OperationalAlertDevice device in devices) {
      if (device.rooms.isEmpty) {
        result.add(
          OperationalAlertTarget(
            tenantId: tenantId,
            siteId: siteId,
            deviceId: device.deviceId,
            snapshotUnitKey: device.snapshotUnitKey,
          ),
        );
        continue;
      }
      for (final OperationalAlertRoom room in device.rooms) {
        result.add(
          OperationalAlertTarget(
            tenantId: tenantId,
            siteId: siteId,
            deviceId: device.deviceId,
            roomId: room.roomId,
            roomNumber: room.roomNumber,
            snapshotUnitKey: room.snapshotUnitKey,
          ),
        );
      }
    }
    return List<OperationalAlertTarget>.unmodifiable(result);
  }

  int get roomCount =>
      devices.fold<int>(0, (int sum, OperationalAlertDevice device) {
        return sum + device.rooms.length;
      });

  bool get isValid => validate().isValid;

  OperationalAlertTopologyValidation validate() {
    final List<String> invalid = <String>[];
    final Map<String, List<String>> ownersBySnapshotUnitKey =
        <String, List<String>>{};
    for (final OperationalAlertDevice device in devices) {
      if (device.deviceId.trim().isEmpty) {
        invalid.add('device_missing_id');
      }
      if (device.siteId != siteId) {
        invalid.add('device_site_mismatch:${device.deviceId}:${device.siteId}');
      }
      if (!device.enabled) {
        invalid.add('device_disabled_included:${device.deviceId}');
      }
      if (device.rooms.isEmpty) {
        final String unitKey = device.snapshotUnitKey.trim();
        if (unitKey.isEmpty) {
          invalid.add('device_missing_snapshot_unit_key:${device.deviceId}');
        } else {
          ownersBySnapshotUnitKey
              .putIfAbsent(unitKey, () => <String>[])
              .add('device:${device.deviceId}');
        }
        continue;
      }
      for (final OperationalAlertRoom room in device.rooms) {
        if (!room.enabled) {
          invalid.add(
            'room_disabled_included:${device.deviceId}/${room.roomId}',
          );
        }
        final String unitKey = room.snapshotUnitKey.trim();
        if (unitKey.isEmpty) {
          invalid.add(
            'room_missing_snapshot_unit_key:${device.deviceId}/${room.roomId}',
          );
        } else {
          ownersBySnapshotUnitKey
              .putIfAbsent(unitKey, () => <String>[])
              .add('room:${device.deviceId}/${room.roomId}');
        }
      }
    }
    for (final MapEntry<String, List<String>> entry
        in ownersBySnapshotUnitKey.entries) {
      if (entry.value.length > 1) {
        invalid.add(
          'duplicate_snapshot_unit_key:${entry.key}:${entry.value.join('|')}',
        );
      }
    }
    return OperationalAlertTopologyValidation(
      invalidReasons: invalid,
      warnings: warnings,
    );
  }

  Map<String, Object?> toHealthJson({
    required AlertTopologyMode mode,
    required AlertTopologySource effectiveSource,
    DateTime? lastRefreshAt,
    Object? lastError,
  }) {
    final OperationalAlertTopologyValidation validation = validate();
    return <String, Object?>{
      'mode': mode.wireName,
      'source': effectiveSource.name,
      'tenantId': tenantId,
      'siteId': siteId,
      'deviceCount': devices.length,
      'roomCount': roomCount,
      'targetCount': targets.length,
      'valid': validation.isValid,
      'lastRefreshAt': lastRefreshAt?.toUtc().toIso8601String(),
      'lastError': lastError?.toString(),
      'warnings': warnings,
      'invalid': validation.invalidReasons,
    };
  }
}

class OperationalAlertDevice {
  OperationalAlertDevice({
    required this.deviceId,
    required this.siteId,
    required this.enabled,
    required this.snapshotUnitKey,
    List<OperationalAlertRoom> rooms = const <OperationalAlertRoom>[],
  }) : rooms = List<OperationalAlertRoom>.unmodifiable(rooms);

  final String deviceId;
  final String siteId;
  final bool enabled;
  final String snapshotUnitKey;
  final List<OperationalAlertRoom> rooms;
}

class OperationalAlertRoom {
  const OperationalAlertRoom({
    required this.roomId,
    required this.enabled,
    required this.snapshotUnitKey,
    this.roomNumber,
  });

  final String roomId;
  final bool enabled;
  final String snapshotUnitKey;
  final int? roomNumber;
}

class OperationalAlertTarget {
  const OperationalAlertTarget({
    required this.tenantId,
    required this.siteId,
    required this.deviceId,
    required this.snapshotUnitKey,
    this.roomId,
    this.roomNumber,
  });

  final String tenantId;
  final String siteId;
  final String deviceId;
  final String snapshotUnitKey;
  final String? roomId;
  final int? roomNumber;

  AlertConfigurationTarget toAlertConfigurationTarget() {
    return AlertConfigurationTarget(
      tenantId: tenantId,
      siteId: siteId,
      scope: roomId == null
          ? AlertConfigurationScope.device
          : AlertConfigurationScope.room,
      deviceId: deviceId,
      roomId: roomId,
      snapshotUnitKey: snapshotUnitKey,
      muntersId: snapshotUnitKey,
    );
  }
}

class OperationalAlertTopologyValidation {
  const OperationalAlertTopologyValidation({
    required this.invalidReasons,
    required this.warnings,
  });

  final List<String> invalidReasons;
  final List<String> warnings;

  bool get isValid => invalidReasons.isEmpty && warnings.isEmpty;
}

bool canRefreshAlertTopology(String? role) => role?.trim() == 'owner';

class OperationalTopologyDiscoveryResult {
  const OperationalTopologyDiscoveryResult({
    required this.topology,
    required this.readCount,
  });

  final OperationalAlertTopology topology;
  final int readCount;
}

abstract class OperationalTopologyLoader {
  Future<OperationalTopologyDiscoveryResult> load({
    required String tenantId,
    required String siteId,
  });
}

class ParsedOperationalTopologyLoader implements OperationalTopologyLoader {
  const ParsedOperationalTopologyLoader({
    required this.tenantExists,
    required this.site,
    required this.devices,
    this.roomsByDeviceId = const <String, List<Map<String, Object?>>>{},
    this.source = AlertTopologySource.fixture,
  });

  final bool tenantExists;
  final Map<String, Object?>? site;
  final List<Map<String, Object?>> devices;
  final Map<String, List<Map<String, Object?>>> roomsByDeviceId;
  final AlertTopologySource source;

  @override
  Future<OperationalTopologyDiscoveryResult> load({
    required String tenantId,
    required String siteId,
  }) async {
    return parseOperationalTopology(
      tenantId: tenantId,
      siteId: siteId,
      tenantExists: tenantExists,
      site: site,
      devices: devices,
      roomsByDeviceId: roomsByDeviceId,
      source: source,
      loadedAt: DateTime.now().toUtc(),
    );
  }
}

OperationalTopologyDiscoveryResult parseOperationalTopology({
  required String tenantId,
  required String siteId,
  required bool tenantExists,
  required Map<String, Object?>? site,
  required List<Map<String, Object?>> devices,
  Map<String, List<Map<String, Object?>>> roomsByDeviceId =
      const <String, List<Map<String, Object?>>>{},
  AlertTopologySource source = AlertTopologySource.firestore,
  DateTime? loadedAt,
}) {
  final List<String> warnings = <String>[];
  int readCount = 1; // Tenant document.
  if (!tenantExists) {
    warnings.add('tenant_missing:$tenantId');
    return OperationalTopologyDiscoveryResult(
      topology: OperationalAlertTopology(
        tenantId: tenantId,
        siteId: siteId,
        devices: const <OperationalAlertDevice>[],
        source: source,
        loadedAt: loadedAt,
        warnings: warnings,
      ),
      readCount: readCount,
    );
  }
  readCount += 1; // Site document.
  if (site == null) {
    warnings.add('site_missing:$siteId');
    return OperationalTopologyDiscoveryResult(
      topology: OperationalAlertTopology(
        tenantId: tenantId,
        siteId: siteId,
        devices: const <OperationalAlertDevice>[],
        source: source,
        loadedAt: loadedAt,
        warnings: warnings,
      ),
      readCount: readCount,
    );
  }
  if (site['enabled'] == false || site['active'] == false) {
    warnings.add('site_disabled:$siteId');
  }
  if (site['provisioningStatus'] == null) {
    warnings.add('site_legacy_or_missing_provisioning_status:$siteId');
  }

  readCount += devices.length;
  final List<OperationalAlertDevice> parsedDevices = <OperationalAlertDevice>[];
  for (final Map<String, Object?> deviceRaw in devices) {
    final String deviceId = _readId(deviceRaw);
    final String deviceSiteId = _readString(deviceRaw['siteId']);
    final bool enabled = deviceRaw['enabled'] is bool
        ? deviceRaw['enabled'] as bool
        : true;
    if (deviceSiteId.isEmpty) {
      warnings.add('device_missing_site_id:$deviceId');
      continue;
    }
    if (deviceSiteId != siteId) {
      warnings.add('device_site_mismatch:$deviceId:$deviceSiteId');
      continue;
    }
    if (!enabled) {
      warnings.add('device_disabled:$deviceId');
      continue;
    }

    final List<Map<String, Object?>> roomsRaw =
        roomsByDeviceId[deviceId] ?? const <Map<String, Object?>>[];
    readCount += roomsRaw.length;
    final List<OperationalAlertRoom> rooms = <OperationalAlertRoom>[];
    for (final Map<String, Object?> roomRaw in roomsRaw) {
      final String roomId = _readId(roomRaw);
      final bool roomEnabled = roomRaw['enabled'] is bool
          ? roomRaw['enabled'] as bool
          : true;
      if (!roomEnabled) {
        warnings.add('room_disabled:$deviceId/$roomId');
        continue;
      }
      final String roomSnapshotUnitKey = _readString(
        roomRaw['snapshotUnitKey'],
      );
      if (roomSnapshotUnitKey.isEmpty) {
        warnings.add('room_missing_snapshot_unit_key:$deviceId/$roomId');
        continue;
      }
      rooms.add(
        OperationalAlertRoom(
          roomId: roomId,
          enabled: roomEnabled,
          snapshotUnitKey: roomSnapshotUnitKey,
          roomNumber: _readInt(roomRaw['roomNumber']),
        ),
      );
    }

    if (roomsRaw.isNotEmpty && rooms.isEmpty) {
      warnings.add('device_without_valid_rooms:$deviceId');
      continue;
    }

    final String deviceSnapshotUnitKey = _readString(
      deviceRaw['snapshotUnitKey'],
    );
    if (rooms.isEmpty && deviceSnapshotUnitKey.isEmpty) {
      warnings.add('device_missing_snapshot_unit_key:$deviceId');
      continue;
    }
    parsedDevices.add(
      OperationalAlertDevice(
        deviceId: deviceId,
        siteId: deviceSiteId,
        enabled: enabled,
        snapshotUnitKey: deviceSnapshotUnitKey,
        rooms: rooms,
      ),
    );
  }

  final OperationalAlertTopology topology = OperationalAlertTopology(
    tenantId: tenantId,
    siteId: siteId,
    devices: parsedDevices,
    source: source,
    loadedAt: loadedAt,
    warnings: warnings,
  );
  return OperationalTopologyDiscoveryResult(
    topology: topology,
    readCount: readCount,
  );
}

OperationalAlertTopology legacyOperationalAlertTopology({
  required String tenantId,
  required String siteId,
  DateTime? loadedAt,
}) {
  return OperationalAlertTopology(
    tenantId: tenantId,
    siteId: siteId,
    source: AlertTopologySource.legacyFallback,
    loadedAt: loadedAt,
    devices: <OperationalAlertDevice>[
      for (final AlertRoomIdentity room in AlertRoomIdentity.defaultRooms)
        OperationalAlertDevice(
          deviceId: room.muntersId,
          siteId: siteId,
          enabled: true,
          snapshotUnitKey: room.muntersId,
          rooms: <OperationalAlertRoom>[
            OperationalAlertRoom(
              roomId: room.roomId,
              enabled: true,
              snapshotUnitKey: room.muntersId,
              roomNumber: room.roomNumber,
            ),
          ],
        ),
    ],
  );
}

class TopologyValidationComparison {
  const TopologyValidationComparison({
    required this.legacyUnitKeys,
    required this.dynamicUnitKeys,
    required this.missingInDynamic,
    required this.missingInLegacy,
    required this.duplicateDynamicUnitKeys,
    required this.invalidReasons,
  });

  final List<String> legacyUnitKeys;
  final List<String> dynamicUnitKeys;
  final List<String> missingInDynamic;
  final List<String> missingInLegacy;
  final List<String> duplicateDynamicUnitKeys;
  final List<String> invalidReasons;

  bool get matches =>
      missingInDynamic.isEmpty &&
      missingInLegacy.isEmpty &&
      duplicateDynamicUnitKeys.isEmpty &&
      invalidReasons.isEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'legacyUnitKeys': legacyUnitKeys,
      'dynamicUnitKeys': dynamicUnitKeys,
      'missingInDynamic': missingInDynamic,
      'missingInLegacy': missingInLegacy,
      'duplicateDynamicUnitKeys': duplicateDynamicUnitKeys,
      'invalidReasons': invalidReasons,
      'matches': matches,
    };
  }
}

TopologyValidationComparison compareLegacyAndDynamicTopologies({
  required OperationalAlertTopology legacy,
  required OperationalAlertTopology dynamic,
}) {
  final List<String> legacyKeys = _sortedUnitKeys(legacy.targets);
  final List<String> dynamicKeys = _sortedUnitKeys(dynamic.targets);
  final Set<String> legacySet = legacyKeys.toSet();
  final Set<String> dynamicSet = dynamicKeys.toSet();
  final List<String> duplicateDynamicKeys = _duplicates(dynamic.targets);
  return TopologyValidationComparison(
    legacyUnitKeys: legacyKeys,
    dynamicUnitKeys: dynamicKeys,
    missingInDynamic:
        legacySet
            .where((String key) => !dynamicSet.contains(key))
            .toList(growable: false)
          ..sort(),
    missingInLegacy:
        dynamicSet
            .where((String key) => !legacySet.contains(key))
            .toList(growable: false)
          ..sort(),
    duplicateDynamicUnitKeys: duplicateDynamicKeys,
    invalidReasons: dynamic.validate().invalidReasons,
  );
}

List<String> _sortedUnitKeys(Iterable<OperationalAlertTarget> targets) {
  return targets
      .map((OperationalAlertTarget target) => target.snapshotUnitKey)
      .toList(growable: false)
    ..sort();
}

List<String> _duplicates(Iterable<OperationalAlertTarget> targets) {
  final Set<String> seen = <String>{};
  final Set<String> duplicated = <String>{};
  for (final OperationalAlertTarget target in targets) {
    final String key = target.snapshotUnitKey;
    if (!seen.add(key)) {
      duplicated.add(key);
    }
  }
  return duplicated.toList(growable: false)..sort();
}

class OperationalTopologyCache {
  OperationalTopologyCache({
    required this.tenantId,
    required this.siteId,
    required this.mode,
    OperationalTopologyLoader? loader,
    this.ttl = const Duration(hours: 6),
    DateTime Function()? now,
  }) : _loader = loader,
       _now = now ?? DateTime.now;

  final String tenantId;
  final String siteId;
  final AlertTopologyMode mode;
  final OperationalTopologyLoader? _loader;
  final Duration ttl;
  final DateTime Function() _now;
  OperationalAlertTopology? _dynamicTopology;
  Object? _lastError;
  DateTime? _lastRefreshAt;
  int _lastReadCount = 0;

  OperationalAlertTopology get legacyTopology => legacyOperationalAlertTopology(
    tenantId: tenantId,
    siteId: siteId,
    loadedAt: _lastRefreshAt,
  );

  OperationalAlertTopology get activeTopology {
    if (mode == AlertTopologyMode.dynamic &&
        _dynamicTopology?.isValid == true) {
      return _dynamicTopology!;
    }
    return legacyTopology;
  }

  AlertTopologySource get activeSource {
    if (mode == AlertTopologyMode.dynamic &&
        _dynamicTopology?.isValid == true) {
      return _dynamicTopology!.source;
    }
    return AlertTopologySource.legacyFallback;
  }

  Object? get lastError => _lastError;

  DateTime? get lastRefreshAt => _lastRefreshAt;

  int get lastReadCount => _lastReadCount;

  bool get shouldRefresh {
    if (mode == AlertTopologyMode.legacy) {
      return false;
    }
    final DateTime? refreshedAt = _lastRefreshAt;
    if (refreshedAt == null) {
      return true;
    }
    return _now().toUtc().difference(refreshedAt) >= ttl;
  }

  Future<OperationalAlertTopology> getOrRefresh() async {
    if (!shouldRefresh && _dynamicTopology != null) {
      return activeTopology;
    }
    return refresh();
  }

  Future<OperationalAlertTopology> refresh() async {
    if (mode == AlertTopologyMode.legacy || _loader == null) {
      _lastRefreshAt = _now().toUtc();
      _lastError = null;
      _lastReadCount = 0;
      _logTopology(
        'loaded tenant=$tenantId site=$siteId devices=${legacyTopology.devices.length} rooms=${legacyTopology.roomCount} source=legacyFallback mode=${mode.wireName}',
      );
      return legacyTopology;
    }

    try {
      final OperationalTopologyDiscoveryResult result = await _loader.load(
        tenantId: tenantId,
        siteId: siteId,
      );
      _dynamicTopology = result.topology;
      _lastRefreshAt = _now().toUtc();
      _lastReadCount = result.readCount;
      _lastError = null;
      _logTopology(
        'loaded tenant=$tenantId site=$siteId devices=${result.topology.devices.length} rooms=${result.topology.roomCount} targets=${result.topology.targets.length} source=${result.topology.source.name} mode=${mode.wireName} reads=${result.readCount}',
      );
      final OperationalAlertTopologyValidation validation = result.topology
          .validate();
      if (!validation.isValid || result.topology.warnings.isNotEmpty) {
        _logTopology(
          'inconsistency tenant=$tenantId site=$siteId warnings=${result.topology.warnings.join(',')} invalid=${validation.invalidReasons.join(',')}',
        );
      }
      if (mode == AlertTopologyMode.validate) {
        final TopologyValidationComparison comparison =
            compareLegacyAndDynamicTopologies(
              legacy: legacyTopology,
              dynamic: result.topology,
            );
        if (!comparison.matches) {
          _logTopology(
            'mismatch legacyUnits=${comparison.legacyUnitKeys} dynamicUnits=${comparison.dynamicUnitKeys} missingInDynamic=${comparison.missingInDynamic} missingInLegacy=${comparison.missingInLegacy} duplicates=${comparison.duplicateDynamicUnitKeys} invalid=${comparison.invalidReasons}',
          );
        }
      }
      if (mode == AlertTopologyMode.dynamic && !result.topology.isValid) {
        _logTopology(
          'fallback reason=invalid_dynamic_topology tenant=$tenantId site=$siteId',
        );
      }
      return activeTopology;
    } catch (error) {
      _lastError = error;
      _lastRefreshAt = _now().toUtc();
      _lastReadCount = 0;
      _logTopology(
        'fallback reason=discovery_error tenant=$tenantId site=$siteId error=$error',
      );
      return legacyTopology;
    }
  }

  Map<String, Object?> healthJson() {
    final OperationalAlertTopology topology = activeTopology;
    final Map<String, Object?> health = topology.toHealthJson(
      mode: mode,
      effectiveSource: activeSource,
      lastRefreshAt: _lastRefreshAt,
      lastError: _lastError,
    );
    health['lastReadCount'] = _lastReadCount;
    if (_dynamicTopology != null) {
      health['validate'] = compareLegacyAndDynamicTopologies(
        legacy: legacyTopology,
        dynamic: _dynamicTopology!,
      ).toJson();
    }
    return health;
  }
}

class FirestoreOperationalTopologyLoader implements OperationalTopologyLoader {
  FirestoreOperationalTopologyLoader({
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

  /// Overridable REST root — production always uses the real Firestore
  /// endpoint (the default). Tests point this at a local Firestore Emulator
  /// instance instead, so the exact same HTTP + wire-decode path
  /// (`_getDocument`/`_listDocuments`/`_decodeFirestoreValue`) that talks to
  /// production gets exercised against a real server, not a fake in-memory
  /// loader.
  final String _baseUrl;

  /// Overridable token source — production always calls the real
  /// [ServiceAccountAuth] (the default, when null). The Firestore Emulator
  /// does not validate bearer tokens, so tests inject a trivial provider
  /// instead of performing a real Google OAuth exchange.
  final Future<String> Function()? _accessTokenProvider;

  bool get isConfigured =>
      _projectId.trim().isNotEmpty &&
      _databaseId.trim().isNotEmpty &&
      (_accessTokenProvider != null ||
          _auth.serviceAccountJsonPath.trim().isNotEmpty);

  @override
  Future<OperationalTopologyDiscoveryResult> load({
    required String tenantId,
    required String siteId,
  }) async {
    if (!isConfigured) {
      throw const OperationalTopologyLoaderException(
        'Firestore topology loader is not configured',
      );
    }
    final String token = await (_accessTokenProvider ?? _auth.getAccessToken)();
    final Map<String, Object?>? tenant = await _getDocument(
      token,
      'tenants/$tenantId',
    );
    final Map<String, Object?>? site = await _getDocument(
      token,
      'tenants/$tenantId/sites/$siteId',
    );
    final List<_FirestoreDocument> deviceDocs = await _listDocuments(
      token,
      'tenants/$tenantId/devices',
    );
    final List<Map<String, Object?>> devices = <Map<String, Object?>>[];
    final Map<String, List<Map<String, Object?>>> roomsByDeviceId =
        <String, List<Map<String, Object?>>>{};
    for (final _FirestoreDocument deviceDoc in deviceDocs) {
      final Map<String, Object?> device = <String, Object?>{
        'id': deviceDoc.id,
        ...deviceDoc.fields,
      };
      if (device['siteId'] != siteId) {
        devices.add(device);
        continue;
      }
      devices.add(device);
      final List<_FirestoreDocument> roomDocs = await _listDocuments(
        token,
        'tenants/$tenantId/devices/${deviceDoc.id}/rooms',
        allowMissing: true,
      );
      roomsByDeviceId[deviceDoc.id] = <Map<String, Object?>>[
        for (final _FirestoreDocument roomDoc in roomDocs)
          <String, Object?>{'id': roomDoc.id, ...roomDoc.fields},
      ];
    }
    return parseOperationalTopology(
      tenantId: tenantId,
      siteId: siteId,
      tenantExists: tenant != null,
      site: site,
      devices: devices,
      roomsByDeviceId: roomsByDeviceId,
      source: AlertTopologySource.firestore,
      loadedAt: DateTime.now().toUtc(),
    );
  }

  Future<Map<String, Object?>?> _getDocument(
    String token,
    String documentPath,
  ) async {
    final Uri uri = _documentUri(documentPath);
    final HttpClientRequest request = await _httpClient.getUrl(uri);
    if (token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode == HttpStatus.notFound) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OperationalTopologyLoaderException(
        'Firestore topology GET failed status=${response.statusCode} path=$documentPath body=${_compact(body)}',
      );
    }
    final Map<String, dynamic> document =
        jsonDecode(body) as Map<String, dynamic>;
    return _decodeFields(document);
  }

  Future<List<_FirestoreDocument>> _listDocuments(
    String token,
    String collectionPath, {
    bool allowMissing = false,
  }) async {
    final Uri uri = _documentUri(collectionPath);
    final HttpClientRequest request = await _httpClient.getUrl(uri);
    if (token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode == HttpStatus.notFound && allowMissing) {
      return const <_FirestoreDocument>[];
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OperationalTopologyLoaderException(
        'Firestore topology LIST failed status=${response.statusCode} path=$collectionPath body=${_compact(body)}',
      );
    }
    final Map<String, dynamic> payload =
        jsonDecode(body) as Map<String, dynamic>;
    final Object? documentsRaw = payload['documents'];
    if (documentsRaw is! List) {
      return const <_FirestoreDocument>[];
    }
    return documentsRaw
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> document) {
          final String name = document['name']?.toString() ?? '';
          return _FirestoreDocument(
            id: name.split('/').last,
            fields: _decodeFields(document),
          );
        })
        .toList(growable: false);
  }

  Uri _documentUri(String documentPath) {
    return Uri.parse(
      '$_baseUrl/v1/projects/$_projectId'
      '/databases/$_databaseId/documents/$documentPath',
    );
  }
}

class _FirestoreDocument {
  const _FirestoreDocument({required this.id, required this.fields});

  final String id;
  final Map<String, Object?> fields;
}

Map<String, Object?> _decodeFields(Map<String, dynamic> document) {
  final Map<String, dynamic> fields =
      document['fields'] as Map<String, dynamic>? ?? <String, dynamic>{};
  return fields.map(
    (String key, dynamic value) => MapEntry(key, _decodeFirestoreValue(value)),
  );
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

String _readId(Map<String, Object?> raw) {
  final String id = _readString(raw['id']);
  if (id.isNotEmpty) {
    return id;
  }
  return _readString(raw['deviceId']).isNotEmpty
      ? _readString(raw['deviceId'])
      : _readString(raw['roomId']);
}

String _readString(Object? raw) => raw?.toString().trim() ?? '';

int? _readInt(Object? raw) {
  if (raw is int) {
    return raw;
  }
  if (raw is num) {
    return raw.toInt();
  }
  if (raw is String) {
    return int.tryParse(raw.trim());
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

void _logTopology(String message) {
  stdout.writeln('[topology] $message');
}

class OperationalTopologyLoaderException implements Exception {
  const OperationalTopologyLoaderException(this.message);

  final String message;

  @override
  String toString() => message;
}
