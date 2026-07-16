import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agro_data_control_backend/src/alert_runtime.dart';
import 'package:agro_data_control_backend/src/alert_settings_cache.dart';
import 'package:agro_data_control_backend/src/alert_notifications.dart';
import 'package:agro_data_control_backend/src/firebase_custom_claims_service.dart';
import 'package:agro_data_control_backend/src/firebase_request_auth.dart';
import 'package:agro_data_control_backend/src/firestore_alert_settings_loader.dart';
import 'package:agro_data_control_backend/src/plc_installation_config.dart';
import 'package:agro_data_control_backend/src/presence_registry.dart';
import 'package:agro_data_control_backend/src/room_wash_authorization.dart';
import 'package:agro_data_control_backend/src/snapshot_runtime.dart';
import 'package:agro_data_control_backend/src/whatsapp_alert_recipients.dart';
import 'package:agro_data_control_backend/src/whatsapp_service.dart';
import 'package:agro_data_control_backend/src/alert_processing_coordinator.dart';

const Duration _httpHandlerTimeout = Duration(seconds: 20);
const Duration _httpWriteTimeout = Duration(seconds: 5);
const int _maxRequestBodyBytes = 16 * 1024;

Future<void> main(List<String> args) async {
  final String configPath = _resolveConfigPath(args);
  final PlcInstallationConfig config = PlcInstallationConfig.fromJson(
    jsonDecode(await File(configPath).readAsString()) as Map<String, dynamic>,
  );

  final AlertRuntime alertRuntime = AlertRuntime(
    settingsCache: AlertSettingsCache(
      loader: FirestoreAlertSettingsLoader(
        projectId:
            config.runtimeEvents.firestoreProjectId ??
            Platform.environment['FIRESTORE_PROJECT_ID'] ??
            '',
        databaseId: config.runtimeEvents.firestoreDatabaseId,
        serviceAccountJsonPath:
            config.runtimeEvents.firestoreServiceAccountPath,
      ),
    ),
  );
  final WhatsAppService whatsAppService = WhatsAppService();
  const WhatsAppAlertRecipientsConfig alertRecipientsConfig =
      WhatsAppAlertRecipientsConfig();
  final NotificationBatchManager notificationBatchManager =
      NotificationBatchManager(
        processor: AlertNotificationProcessor(
          recipientsConfig: alertRecipientsConfig,
          sender: AlertNotificationSender(whatsAppService: whatsAppService),
          clientName: config.clientName,
          siteName: config.siteName,
          builder: NotificationBatchBuilder(
            templateBuilder: WhatsAppTemplateBuilder.fromEnvironment(),
          ),
        ),
      );
  final AlertProcessingCoordinator alertProcessingCoordinator =
      AlertProcessingCoordinator(
        tenantId: config.runtimeEvents.tenantId,
        siteId: config.runtimeEvents.siteId,
        runtime: alertRuntime,
        plcLabelsByMuntersId: {
          for (final MapEntry<String, UnitConfig> entry in config.units.entries)
            entry.key: entry.value.name,
        },
        notificationBatchManager: notificationBatchManager,
      );
  final SnapshotRuntime runtime = SnapshotRuntime(
    config,
    onSnapshotUpdated: alertProcessingCoordinator.processSnapshot,
  );
  final FirebaseRequestAuthService authService = FirebaseRequestAuthService(
    projectId:
        config.runtimeEvents.firestoreProjectId ??
        Platform.environment['FIRESTORE_PROJECT_ID'] ??
        '',
    databaseId: config.runtimeEvents.firestoreDatabaseId,
    serviceAccountJsonPath: config.runtimeEvents.firestoreServiceAccountPath,
  );
  final FirebaseCustomClaimsService customClaimsService =
      FirebaseCustomClaimsService(
        projectId:
            config.runtimeEvents.firestoreProjectId ??
            Platform.environment['FIRESTORE_PROJECT_ID'] ??
            '',
        databaseId: config.runtimeEvents.firestoreDatabaseId,
        serviceAccountJsonPath:
            config.runtimeEvents.firestoreServiceAccountPath,
      );
  final _OperationalEventHub operationalEventHub = _OperationalEventHub();
  final PresenceRegistry presenceRegistry = PresenceRegistry(
    backendVersion: config.backendName,
  );
  _logHttp(
    'alert runtime initialized settings=${alertRuntime.settingsCache.size} washes=${alertRuntime.roomWashRegistry.size} activeAlerts=${alertRuntime.activeAlertsRegistry.size}',
  );
  runtime.start();

  final HttpServer server = await HttpServer.bind(
    config.httpHost,
    config.httpPort,
  );

  _logHttp(
    'server started host=${server.address.address} port=${server.port} config=$configPath',
  );

  final StreamSubscription<ProcessSignal> sigintSub = ProcessSignal.sigint
      .watch()
      .listen((_) async {
        _logHttp('shutdown signal=SIGINT');
        await server.close(force: true);
        await runtime.dispose();
        exit(0);
      });

  await for (final HttpRequest request in server) {
    await _handleRequest(
      request,
      runtime,
      authService,
      whatsAppService,
      alertRecipientsConfig,
      operationalEventHub,
      presenceRegistry,
      alertRuntime,
      customClaimsService,
    );
  }

  await sigintSub.cancel();
}

String _resolveConfigPath(List<String> args) {
  final String? fromArg = args.cast<String?>().firstWhere(
    (arg) => arg != null && arg.startsWith('--config='),
    orElse: () => null,
  );
  if (fromArg != null) {
    return fromArg.substring('--config='.length);
  }

  return 'backend/config/sites/default.json';
}

Future<void> _handleRequest(
  HttpRequest request,
  SnapshotRuntime runtime,
  FirebaseRequestAuthService authService,
  WhatsAppService whatsAppService,
  WhatsAppAlertRecipientsConfig alertRecipientsConfig,
  _OperationalEventHub operationalEventHub,
  PresenceRegistry presenceRegistry,
  AlertRuntime alertRuntime,
  FirebaseCustomClaimsService customClaimsService,
) async {
  final Stopwatch stopwatch = Stopwatch()..start();
  final String path = request.uri.path;
  _logHttp(
    'request started method=${request.method} path=$path remote=${request.connectionInfo?.remoteAddress.address}',
  );

  try {
    await _handleRequestInternal(
      request,
      runtime,
      authService,
      whatsAppService,
      alertRecipientsConfig,
      operationalEventHub,
      presenceRegistry,
      alertRuntime,
      customClaimsService,
    ).timeout(_httpHandlerTimeout);
  } on TimeoutException catch (error, stackTrace) {
    _logHttp('timeout path=$path operation=request_handler error=$error');
    _logHttp('error path=$path stack=$stackTrace');
    await _writeErrorResponse(
      request.response,
      path: path,
      statusCode: HttpStatus.gatewayTimeout,
      message: 'Request timed out',
    );
  } catch (error, stackTrace) {
    _logHttp('error path=$path error=$error');
    _logHttp('error path=$path stack=$stackTrace');
    await _writeErrorResponse(
      request.response,
      path: path,
      statusCode: HttpStatus.internalServerError,
      message: 'Internal server error',
    );
  } finally {
    stopwatch.stop();
    _logHttp(
      'request finished method=${request.method} path=$path status=${request.response.statusCode} elapsedMs=${stopwatch.elapsedMilliseconds}',
    );
  }
}

Future<void> _handleRequestInternal(
  HttpRequest request,
  SnapshotRuntime runtime,
  FirebaseRequestAuthService authService,
  WhatsAppService whatsAppService,
  WhatsAppAlertRecipientsConfig alertRecipientsConfig,
  _OperationalEventHub operationalEventHub,
  PresenceRegistry presenceRegistry,
  AlertRuntime alertRuntime,
  FirebaseCustomClaimsService customClaimsService,
) async {
  _writeCorsHeaders(request.response);

  if (request.method == 'OPTIONS') {
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close().timeout(_httpWriteTimeout);
    return;
  }

  final String path = request.uri.path;
  if (request.method == 'GET' &&
      (path == '/snapshot' || path == '/api/snapshot')) {
    final Map<String, Object?> payload = Map<String, Object?>.from(
      runtime.snapshotJson(),
    );
    final String tenantId = request.uri.queryParameters['tenantId'] ?? '';
    final String siteId = request.uri.queryParameters['siteId'] ?? '';
    final DateTime now = DateTime.now().toUtc();
    final AuthenticatedBackendUser? authenticatedUser = await authService
        .tryAuthenticate(request);
    if (authenticatedUser != null) {
      presenceRegistry.recordSnapshotHeartbeat(
        uid: authenticatedUser.uid,
        email: authenticatedUser.email,
        displayName: authenticatedUser.displayName,
        tenantId: tenantId,
        siteId: siteId,
        sessionId: _headerValue(request, 'X-AgroData-Session-Id'),
        seenAt: now,
        userAgent: request.headers.value(HttpHeaders.userAgentHeader),
        ip: _clientIp(request),
        appVersion: _headerValue(request, 'X-AgroData-App-Version'),
        deviceType: _headerValue(request, 'X-AgroData-Device-Type'),
      );
    }
    if (tenantId.trim().isNotEmpty && siteId.trim().isNotEmpty) {
      payload['presence'] = presenceRegistry.snapshotJson(
        tenantId: tenantId.trim(),
        siteId: siteId.trim(),
        includeDetails: _truthy(request.uri.queryParameters['presenceDetails']),
        now: now,
      );
    }
    final List<Map<String, Object?>> events = operationalEventHub.eventsFor(
      tenantId: tenantId,
      siteId: siteId,
    );
    if (events.isNotEmpty) {
      payload['operationalEvents'] = events;
    }
    await _writeJson(request.response, payload);
    return;
  }

  if (request.method == 'GET' && path == '/health') {
    final Map<String, Object?> health = runtime.healthJson();
    await _writeJson(
      request.response,
      health,
      statusCode: runtime.isHealthy
          ? HttpStatus.ok
          : HttpStatus.serviceUnavailable,
    );
    return;
  }

  if (request.method == 'POST' && _isWhatsAppTestPath(path)) {
    await _handleWhatsAppTestRequest(request, authService, whatsAppService);
    return;
  }

  if (request.method == 'GET' && _isWhatsAppWebhookPath(path)) {
    await _handleWhatsAppWebhookVerification(request);
    return;
  }

  if (request.method == 'POST' && _isWhatsAppWebhookPath(path)) {
    await _handleWhatsAppWebhookEvent(request);
    return;
  }

  if (request.method == 'GET' && _isWhatsAppAlertRecipientsPath(path)) {
    await _handleWhatsAppAlertRecipientsRequest(
      request,
      authService,
      alertRecipientsConfig,
      alertRuntime,
    );
    return;
  }

  if (request.method == 'POST' && _isOperationalEventPath(path)) {
    await _handleOperationalEventRequest(
      request,
      authService,
      operationalEventHub,
    );
    return;
  }

  if (request.method == 'POST' && _isCustomClaimsSyncPath(path)) {
    await _handleCustomClaimsSyncRequest(
      request,
      authService,
      customClaimsService,
    );
    return;
  }

  if (request.method == 'PUT' && _isAlertSettingsCachePath(path)) {
    await _handleAlertSettingsCacheRequest(request, authService, alertRuntime);
    return;
  }

  if (request.method == 'POST' && _isRoomWashCachePath(path)) {
    await _handleRoomWashCacheRequest(request, authService, alertRuntime);
    return;
  }

  await _writeJson(request.response, <String, Object?>{
    'error': 'Not found',
    'path': path,
  }, statusCode: HttpStatus.notFound);
}

bool _isWhatsAppTestPath(String path) {
  return path == '/api/notifications/whatsapp/test' ||
      path == '/notifications/whatsapp/test';
}

bool _isWhatsAppWebhookPath(String path) {
  return path == '/api/whatsapp/webhook' || path == '/whatsapp/webhook';
}

bool _isWhatsAppAlertRecipientsPath(String path) {
  return path == '/api/whatsapp/alert-recipients' ||
      path == '/whatsapp/alert-recipients';
}

bool _isOperationalEventPath(String path) {
  return path == '/api/operational-events/room-wash' ||
      path == '/operational-events/room-wash';
}

bool _isAlertSettingsCachePath(String path) {
  return path == '/api/alerts/settings-cache' ||
      path == '/alerts/settings-cache';
}

bool _isRoomWashCachePath(String path) {
  return path == '/api/room-wash/cache' || path == '/room-wash/cache';
}

bool _isCustomClaimsSyncPath(String path) {
  return path == '/api/auth/custom-claims/sync' ||
      path == '/auth/custom-claims/sync';
}

String _headerValue(HttpRequest request, String name) {
  return request.headers.value(name)?.trim() ?? '';
}

String _clientIp(HttpRequest request) {
  final String forwardedFor =
      request.headers.value('X-Forwarded-For')?.trim() ?? '';
  if (forwardedFor.isNotEmpty) {
    return forwardedFor.split(',').first.trim();
  }
  return request.connectionInfo?.remoteAddress.address ?? '';
}

bool _truthy(String? value) {
  final String normalized = value?.trim().toLowerCase() ?? '';
  return normalized == '1' || normalized == 'true' || normalized == 'yes';
}

Future<void> _handleAlertSettingsCacheRequest(
  HttpRequest request,
  FirebaseRequestAuthService authService,
  AlertRuntime alertRuntime,
) async {
  AuthenticatedBackendUser user;
  try {
    user = await authService.requireOwnerOrAdmin(request);
  } on BackendAuthException catch (error) {
    await _writeJson(request.response, <String, Object?>{
      'ok': false,
      'error': error.message,
      'details': error.details?.toString() ?? 'auth_failed',
    }, statusCode: error.statusCode);
    return;
  }
  if (user.role != 'owner' && user.role != 'admin') {
    await _writeJson(request.response, <String, Object?>{
      'ok': false,
      'error': 'Forbidden: owner or admin role required',
    }, statusCode: HttpStatus.forbidden);
    return;
  }

  final Map<String, Object?> body;
  try {
    body = await _readJsonBody(request);
  } on FormatException catch (error) {
    await _writeJson(request.response, <String, Object?>{
      'ok': false,
      'error': 'Invalid request body',
      'details': error.message,
    }, statusCode: HttpStatus.badRequest);
    return;
  }

  final String tenantId = user.tenantId?.trim() ?? '';
  final String siteId = body['siteId']?.toString().trim() ?? '';
  final Object? settingsRaw = body['settings'];
  if (tenantId.isEmpty || siteId.isEmpty || settingsRaw is! Map) {
    _logHttp(
      'alert settings cache validation failed uid=${user.uid} tenant=$tenantId site=$siteId',
    );
    await _writeValidationError(
      request.response,
      '"siteId" and "settings" are required',
    );
    return;
  }

  final cached;
  try {
    cached = alertRuntime.settingsCache.updateFromPayload(
      tenantId: tenantId,
      siteId: siteId,
      payload: Map<String, Object?>.from(settingsRaw as Map<Object?, Object?>),
    );
  } on FormatException catch (error) {
    _logHttp(
      'alert settings cache validation failed uid=${user.uid} tenant=$tenantId site=$siteId details=${error.message}',
    );
    await _writeValidationError(request.response, error.message);
    return;
  }
  _logHttp(
    'alert settings cache updated uid=${user.uid} tenant=$tenantId site=$siteId source=${cached.source}',
  );
  await _writeJson(request.response, <String, Object?>{
    'ok': true,
    'success': true,
    'tenantId': tenantId,
    'siteId': siteId,
    'source': cached.source,
    'loadedAt': cached.loadedAt.toIso8601String(),
  });
}

Future<void> _handleCustomClaimsSyncRequest(
  HttpRequest request,
  FirebaseRequestAuthService authService,
  FirebaseCustomClaimsService customClaimsService,
) async {
  AuthenticatedBackendUser requester;
  try {
    requester = await authService.requireOwnerOrAdmin(request);
  } on BackendAuthException catch (error) {
    await _writeJson(request.response, <String, Object?>{
      'ok': false,
      'error': error.message,
      'details': error.details?.toString() ?? 'auth_failed',
    }, statusCode: error.statusCode);
    return;
  }
  if (requester.role != 'owner') {
    await _writeJson(request.response, <String, Object?>{
      'ok': false,
      'error': 'Forbidden: owner role required',
    }, statusCode: HttpStatus.forbidden);
    return;
  }

  final Map<String, Object?> body;
  try {
    body = await _readJsonBody(request);
  } on FormatException catch (error) {
    await _writeJson(request.response, <String, Object?>{
      'ok': false,
      'error': 'Invalid request body',
      'details': error.message,
    }, statusCode: HttpStatus.badRequest);
    return;
  }

  final Set<String> forbiddenPayloadKeys = <String>{
    'role',
    'tenantRole',
    'activeTenantId',
    'tenantId',
    'allowedSiteIds',
  };
  final List<String> providedForbiddenKeys = body.keys
      .where(forbiddenPayloadKeys.contains)
      .toList(growable: false);
  if (providedForbiddenKeys.isNotEmpty) {
    await _writeValidationError(
      request.response,
      'Only "uid" is accepted. Claims are rebuilt from Firestore.',
    );
    return;
  }

  final String targetUid = body['uid']?.toString().trim() ?? '';
  final String requesterTenantId = requester.tenantId?.trim() ?? '';
  if (targetUid.isEmpty) {
    await _writeValidationError(request.response, '"uid" is required');
    return;
  }

  try {
    final CustomClaimsSyncResult result = await customClaimsService
        .syncUserClaims(
          targetUid: targetUid,
          requesterUid: requester.uid,
          requesterRole: requester.role ?? '',
          requesterTenantId: requesterTenantId,
        );
    _logHttp(
      'custom claims synced requesterUid=${requester.uid} targetUid=$targetUid tenant=${result.activeTenantId ?? ''} role=${result.role} sites=${result.allowedSiteCount} changed=${result.changed}',
    );
    await _writeJson(request.response, <String, Object?>{
      'ok': true,
      'success': true,
      'message': 'Custom claims synchronized',
      'result': result.toSafeJson(),
    });
  } on CustomClaimsException catch (error) {
    _logHttp(
      'custom claims sync failed requesterUid=${requester.uid} targetUid=$targetUid status=${error.statusCode} error=${error.message} details=${error.details ?? ''}',
    );
    await _writeJson(request.response, <String, Object?>{
      'ok': false,
      'success': false,
      'error': error.message,
      'details': error.details?.toString() ?? 'custom_claims_failed',
    }, statusCode: error.statusCode);
  } catch (error) {
    _logHttp(
      'custom claims sync failed requesterUid=${requester.uid} targetUid=$targetUid error=$error',
    );
    await _writeJson(request.response, <String, Object?>{
      'ok': false,
      'success': false,
      'error': 'Unexpected custom claims error',
      'details': error.toString(),
    }, statusCode: HttpStatus.badGateway);
  }
}

Future<void> _handleRoomWashCacheRequest(
  HttpRequest request,
  FirebaseRequestAuthService authService,
  AlertRuntime alertRuntime,
) async {
  AuthenticatedBackendUser user;
  try {
    user = await authService.requireRoomWashWriter(request);
  } on BackendAuthException catch (error) {
    await _writeJson(request.response, <String, Object?>{
      'ok': false,
      'error': error.message,
      'details': error.details?.toString() ?? 'auth_failed',
    }, statusCode: error.statusCode);
    return;
  }

  final Map<String, Object?> body;
  try {
    body = await _readJsonBody(request);
  } on FormatException catch (error) {
    await _writeJson(request.response, <String, Object?>{
      'ok': false,
      'error': 'Invalid request body',
      'details': error.message,
    }, statusCode: HttpStatus.badRequest);
    return;
  }

  final String tenantId = user.tenantId?.trim() ?? '';
  final String siteId = body['siteId']?.toString().trim() ?? '';
  final String roomId = body['roomId']?.toString().trim() ?? '';
  final int? roomNumber = int.tryParse(body['roomNumber']?.toString() ?? '');
  final DateTime? washedAt = DateTime.tryParse(
    body['washedAt']?.toString().trim() ?? '',
  );
  final RoomWashAuthorizationResult authorization = canRegisterRoomWash(
    user: user,
    siteId: siteId,
  );
  if (!authorization.allowed) {
    _logHttp(
      'room wash cache forbidden uid=${user.uid} tenant=$tenantId site=$siteId role=${authorization.role} reason=${authorization.reason}',
    );
    await _writeJson(request.response, <String, Object?>{
      'ok': false,
      'error': 'Forbidden: room wash writer role required',
      'reason': authorization.reason,
    }, statusCode: HttpStatus.forbidden);
    return;
  }
  if (tenantId.isEmpty ||
      siteId.isEmpty ||
      roomId.isEmpty ||
      (roomNumber != null && roomNumber <= 0) ||
      washedAt == null ||
      washedAt.isAfter(
        DateTime.now().toUtc().add(const Duration(minutes: 1)),
      )) {
    _logHttp(
      'room wash cache validation failed uid=${user.uid} tenant=$tenantId site=$siteId room=$roomId',
    );
    await _writeValidationError(
      request.response,
      '"siteId", "roomId", valid "roomNumber" and valid "washedAt" are required',
    );
    return;
  }

  final state = alertRuntime.roomWashRegistry.registerWash(
    tenantId: tenantId,
    siteId: siteId,
    roomId: roomId,
    roomNumber: roomNumber,
    washedAt: washedAt.toUtc(),
    createdAt: DateTime.now().toUtc(),
    createdByUid: user.uid,
  );
  _logHttp(
    'room wash cache updated uid=${user.uid} tenant=$tenantId site=$siteId room=$roomId role=${authorization.role} siteValidation=${authorization.siteValidation?.name} washedAt=${state.washedAt.toIso8601String()}',
  );
  await _writeJson(request.response, <String, Object?>{
    'ok': true,
    'success': true,
    'tenantId': tenantId,
    'siteId': siteId,
    'roomId': roomId,
    'washedAt': state.washedAt.toIso8601String(),
  });
}

Future<void> _handleWhatsAppAlertRecipientsRequest(
  HttpRequest request,
  FirebaseRequestAuthService authService,
  WhatsAppAlertRecipientsConfig alertRecipientsConfig,
  AlertRuntime alertRuntime,
) async {
  AuthenticatedBackendUser user;
  try {
    user = await authService.requireOwnerOrAdmin(request);
  } on BackendAuthException catch (error) {
    await _writeJson(request.response, <String, Object?>{
      'ok': false,
      'error': error.message,
      'details': error.details?.toString() ?? 'auth_failed',
    }, statusCode: error.statusCode);
    return;
  }

  final String queryTenantId =
      request.uri.queryParameters['tenantId']?.trim() ?? '';
  final String siteId = request.uri.queryParameters['siteId']?.trim() ?? '';
  final Map<String, Object?> payload = buildWhatsAppAlertRecipientsResponse(
    recipientsConfig: alertRecipientsConfig,
    runtimeControl: alertRuntime.config.toJson(),
    role: user.role,
    userTenantId: user.tenantId,
    queryTenantId: queryTenantId,
    querySiteId: siteId,
  );
  _logHttp(
    'whatsapp alert recipients requested uid=${user.uid} role=${user.role ?? ''} userTenant=${user.tenantId ?? ''} queryTenant=$queryTenantId site=$siteId count=${payload['recipientCount']} globalCount=${(payload['globalRecipients'] as List).length} siteCount=${(payload['siteRecipients'] as List).length}',
  );
  await _writeJson(request.response, payload);
}

Future<void> _handleOperationalEventRequest(
  HttpRequest request,
  FirebaseRequestAuthService authService,
  _OperationalEventHub operationalEventHub,
) async {
  AuthenticatedBackendUser user;
  try {
    user = await authService.requireAuthenticated(request);
  } on BackendAuthException catch (error) {
    await _writeJson(request.response, <String, Object?>{
      'ok': false,
      'error': error.message,
      'details': error.details?.toString() ?? 'auth_failed',
    }, statusCode: error.statusCode);
    return;
  }

  final Map<String, Object?> body;
  try {
    body = await _readJsonBody(request);
  } on FormatException catch (error) {
    await _writeJson(request.response, <String, Object?>{
      'ok': false,
      'error': 'Invalid request body',
      'details': error.message,
    }, statusCode: HttpStatus.badRequest);
    return;
  }

  final String tenantId = body['tenantId']?.toString().trim() ?? '';
  final String siteId = body['siteId']?.toString().trim() ?? '';
  final int? roomNumber = int.tryParse(body['roomNumber']?.toString() ?? '');
  final String washedAt = body['washedAt']?.toString().trim() ?? '';
  if (tenantId.isEmpty ||
      siteId.isEmpty ||
      roomNumber == null ||
      roomNumber <= 0 ||
      washedAt.isEmpty) {
    await _writeValidationError(
      request.response,
      '"tenantId", "siteId", "roomNumber" and "washedAt" are required',
    );
    return;
  }

  final Map<String, Object?> event = operationalEventHub.publish(
    tenantId: tenantId,
    siteId: siteId,
    eventType: 'roomWash',
    payload: <String, Object?>{
      'roomNumber': roomNumber,
      'washedAt': washedAt,
      if (body['operatorName'] != null)
        'operatorName': body['operatorName'].toString(),
      if (body['operatorId'] != null)
        'operatorId': body['operatorId'].toString(),
    },
  );
  _logHttp(
    'operational event published uid=${user.uid} type=roomWash tenant=$tenantId site=$siteId room=$roomNumber eventId=${event['id']}',
  );
  await _writeJson(request.response, <String, Object?>{
    'ok': true,
    'success': true,
    'event': event,
  });
}

Future<void> _handleWhatsAppTestRequest(
  HttpRequest request,
  FirebaseRequestAuthService authService,
  WhatsAppService whatsAppService,
) async {
  AuthenticatedBackendUser user;
  try {
    user = await authService.requireOwnerOrAdmin(request);
  } on BackendAuthException catch (error) {
    await _writeJson(request.response, <String, Object?>{
      'ok': false,
      'error': error.message,
      'details': error.details?.toString() ?? 'auth_failed',
    }, statusCode: error.statusCode);
    return;
  }

  final Map<String, Object?> body;
  try {
    body = await _readJsonBody(request);
  } on FormatException catch (error) {
    await _writeJson(request.response, <String, Object?>{
      'ok': false,
      'error': 'Invalid request body',
      'details': error.message,
    }, statusCode: HttpStatus.badRequest);
    return;
  }

  final Object? rawTo = body['to'];
  final Object? rawMessage = body['message'];
  final String to = _normalizePhone(rawTo?.toString() ?? '');
  final String message = rawMessage?.toString().trim() ?? '';

  if (to.isEmpty) {
    await _writeValidationError(request.response, '"to" is required');
    return;
  }
  if (message.isEmpty) {
    await _writeValidationError(request.response, '"message" is required');
    return;
  }
  if (message.length > 1000) {
    await _writeValidationError(
      request.response,
      '"message" must be 1000 characters or less',
    );
    return;
  }

  final String tenantId = user.tenantId?.trim().isNotEmpty == true
      ? user.tenantId!.trim()
      : 'unknown';
  try {
    _logHttp(
      'whatsapp test requested uid=${user.uid} role=${user.role ?? ''} tenant=$tenantId to=${_maskPhone(to)} messageLength=${message.length} modeAttempted=template',
    );
    final WhatsAppSendResult result = await whatsAppService.sendWhatsAppMessage(
      tenantId: tenantId,
      to: to,
      message: message,
      preferText: false,
    );
    _logHttp(
      'whatsapp test success uid=${user.uid} tenant=$tenantId to=${_maskPhone(to)} modeFinal=${result.mode} template=${result.templateName ?? ''} language=${result.languageCode ?? ''} fallbackUsed=${result.fallbackUsed} metaStatusCode=${result.metaStatusCode} messageId=${result.messageId ?? ''}',
    );
    await _writeJson(request.response, <String, Object?>{
      'ok': true,
      'success': true,
      'provider': WhatsAppService.provider,
      'status': 'sent',
      'messageId': result.messageId,
      'wamid': result.messageId,
      'mode': result.mode,
      'templateName': result.templateName,
      'languageCode': result.languageCode,
      'fallbackUsed': result.fallbackUsed,
      'metaStatusCode': result.metaStatusCode,
    });
  } on WhatsAppServiceException catch (error) {
    _logHttp(
      'whatsapp test send failed uid=${user.uid} tenant=$tenantId to=${_maskPhone(to)} status=${error.metaStatusCode ?? error.statusCode} kind=${error.kind.name} modeFinal=${error.finalMode ?? ''} fallbackUsed=${error.fallbackUsed} metaErrorCode=${error.metaErrorCode ?? ''} metaErrorMessage=${error.metaErrorMessage ?? error.message} metaError=${error.details ?? ''}',
    );
    await _writeJson(request.response, <String, Object?>{
      'ok': false,
      'success': false,
      'error': error.message,
      'details': error.details?.toString() ?? error.kind.name,
      'mode': error.finalMode,
      'fallbackUsed': error.fallbackUsed,
      'metaStatusCode': error.metaStatusCode,
    }, statusCode: _safeErrorStatus(error.statusCode));
  } catch (error) {
    _logHttp(
      'whatsapp test send failed uid=${user.uid} tenant=$tenantId to=${_maskPhone(to)} status=unexpected error=$error',
    );
    await _writeJson(request.response, <String, Object?>{
      'ok': false,
      'success': false,
      'error': 'Unexpected WhatsApp error',
      'details': error.toString(),
    }, statusCode: HttpStatus.badGateway);
  }
}

Future<void> _handleWhatsAppWebhookVerification(HttpRequest request) async {
  final String mode = request.uri.queryParameters['hub.mode'] ?? '';
  final String token = request.uri.queryParameters['hub.verify_token'] ?? '';
  final String challenge = request.uri.queryParameters['hub.challenge'] ?? '';
  final String expectedToken =
      Platform.environment['WHATSAPP_WEBHOOK_VERIFY_TOKEN']?.trim() ?? '';

  if (mode == 'subscribe' &&
      expectedToken.isNotEmpty &&
      token == expectedToken) {
    _logHttp('whatsapp webhook verification succeeded');
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.text
      ..write(challenge);
    await request.response.close().timeout(_httpWriteTimeout);
    return;
  }

  _logHttp('whatsapp webhook verification failed mode=$mode');
  await _writeJson(request.response, <String, Object?>{
    'ok': false,
    'error': 'Verification failed',
  }, statusCode: HttpStatus.forbidden);
}

Future<void> _handleWhatsAppWebhookEvent(HttpRequest request) async {
  Map<String, Object?> body;
  try {
    body = await _readJsonBody(request);
  } on FormatException catch (error) {
    _logHttp('whatsapp webhook body parse failed error=${error.message}');
    await _writeJson(request.response, <String, Object?>{'ok': true});
    return;
  }

  final List<Object?> entries = body['entry'] is List
      ? body['entry'] as List
      : const <Object?>[];
  for (final Object? entry in entries) {
    if (entry is! Map) continue;
    final List<Object?> changes = entry['changes'] is List
        ? entry['changes'] as List
        : const <Object?>[];
    for (final Object? change in changes) {
      if (change is! Map) continue;
      final Object? value = change['value'];
      if (value is! Map) continue;
      _logWhatsAppWebhookStatuses(value);
      _logWhatsAppWebhookInboundMessages(value);
    }
  }

  await _writeJson(request.response, <String, Object?>{'ok': true});
}

void _logWhatsAppWebhookStatuses(Map<Object?, Object?> value) {
  final Object? statuses = value['statuses'];
  if (statuses is! List) {
    return;
  }
  for (final Object? status in statuses) {
    if (status is! Map) continue;
    final String messageId = status['id']?.toString() ?? '';
    final String statusValue = status['status']?.toString() ?? '';
    final String recipientId = status['recipient_id']?.toString() ?? '';
    final String timestamp = status['timestamp']?.toString() ?? '';
    final Object? errors = status['errors'];
    String errorSummary = '';
    if (errors is List && errors.isNotEmpty) {
      errorSummary = errors
          .whereType<Map>()
          .map(
            (Map error) =>
                'code=${error['code']} title=${error['title']} message=${error['message']}',
          )
          .join('; ');
    }
    _logHttp(
      'whatsapp webhook status messageId=$messageId status=$statusValue recipient=${_maskPhone(recipientId)} timestamp=$timestamp errors=$errorSummary',
    );
  }
}

void _logWhatsAppWebhookInboundMessages(Map<Object?, Object?> value) {
  final Object? messages = value['messages'];
  if (messages is! List) {
    return;
  }
  for (final Object? message in messages) {
    if (message is! Map) continue;
    final String from = message['from']?.toString() ?? '';
    final String type = message['type']?.toString() ?? '';
    final String messageId = message['id']?.toString() ?? '';
    _logHttp(
      'whatsapp webhook inbound messageId=$messageId from=${_maskPhone(from)} type=$type',
    );
  }
}

Future<Map<String, Object?>> _readJsonBody(HttpRequest request) async {
  final BytesBuilder builder = BytesBuilder(copy: false);
  await for (final List<int> chunk in request) {
    builder.add(chunk);
    if (builder.length > _maxRequestBodyBytes) {
      throw const FormatException('Request body is too large');
    }
  }
  final String body = utf8.decode(builder.takeBytes()).trim();
  if (body.isEmpty) {
    throw const FormatException('Request body is required');
  }
  final Object? decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Request body must be a JSON object');
  }
  return Map<String, Object?>.from(decoded);
}

Future<void> _writeValidationError(
  HttpResponse response,
  String message,
) async {
  await _writeJson(response, <String, Object?>{
    'ok': false,
    'error': message,
    'details': 'validation_failed',
  }, statusCode: HttpStatus.badRequest);
}

Future<void> _writeErrorResponse(
  HttpResponse response, {
  required String path,
  required int statusCode,
  required String message,
}) async {
  try {
    _writeCorsHeaders(response);
    await _writeJson(response, <String, Object?>{
      'error': message,
      'path': path,
    }, statusCode: statusCode);
  } catch (_) {
    try {
      await response.close().timeout(_httpWriteTimeout);
    } catch (_) {
      // The response is already on its way out; nothing else to do here.
    }
  }
}

void _writeCorsHeaders(HttpResponse response) {
  response.headers
    ..set(HttpHeaders.accessControlAllowOriginHeader, '*')
    ..set(
      HttpHeaders.accessControlAllowMethodsHeader,
      'GET, POST, PUT, OPTIONS',
    )
    ..set(
      HttpHeaders.accessControlAllowHeadersHeader,
      'Authorization, Content-Type, X-AgroData-Session-Id, X-AgroData-App-Version, X-AgroData-Device-Type',
    )
    ..contentType = ContentType.json;
}

Future<void> _writeJson(
  HttpResponse response,
  Map<String, Object?> payload, {
  int statusCode = HttpStatus.ok,
}) async {
  response.statusCode = statusCode;
  response.write(jsonEncode(payload));
  await response.close().timeout(_httpWriteTimeout);
}

void _logHttp(String message) {
  stdout.writeln('[HTTP] $message');
}

String _normalizePhone(String value) =>
    value.replaceAll(RegExp(r'[\s+\-()]'), '');

String _maskPhone(String phone) {
  if (phone.length <= 4) {
    return '****';
  }
  final String suffix = phone.substring(phone.length - 4);
  return '***$suffix';
}

int _safeErrorStatus(int statusCode) {
  if (statusCode >= 400 && statusCode <= 599) {
    return statusCode;
  }
  return HttpStatus.badGateway;
}

class _OperationalEventHub {
  static const Duration _retention = Duration(minutes: 5);
  final List<_StoredOperationalEvent> _events = <_StoredOperationalEvent>[];
  int _sequence = 0;

  Map<String, Object?> publish({
    required String tenantId,
    required String siteId,
    required String eventType,
    required Map<String, Object?> payload,
  }) {
    _prune();
    final DateTime now = DateTime.now().toUtc();
    _sequence += 1;
    final Map<String, Object?> event = <String, Object?>{
      'id': '${now.microsecondsSinceEpoch}-$_sequence',
      'type': 'operationalEvent',
      'eventType': eventType,
      'tenantId': tenantId,
      'siteId': siteId,
      'createdAt': now.toIso8601String(),
      'payload': payload,
    };
    _events.add(
      _StoredOperationalEvent(
        tenantId: tenantId,
        siteId: siteId,
        createdAt: now,
        json: event,
      ),
    );
    return event;
  }

  List<Map<String, Object?>> eventsFor({
    required String tenantId,
    required String siteId,
  }) {
    _prune();
    if (tenantId.trim().isEmpty || siteId.trim().isEmpty) {
      return const <Map<String, Object?>>[];
    }
    return _events
        .where(
          (_StoredOperationalEvent event) =>
              event.tenantId == tenantId && event.siteId == siteId,
        )
        .map((event) => Map<String, Object?>.from(event.json))
        .toList(growable: false);
  }

  void _prune() {
    final DateTime cutoff = DateTime.now().toUtc().subtract(_retention);
    _events.removeWhere(
      (_StoredOperationalEvent event) => event.createdAt.isBefore(cutoff),
    );
  }
}

class _StoredOperationalEvent {
  const _StoredOperationalEvent({
    required this.tenantId,
    required this.siteId,
    required this.createdAt,
    required this.json,
  });

  final String tenantId;
  final String siteId;
  final DateTime createdAt;
  final Map<String, Object?> json;
}
