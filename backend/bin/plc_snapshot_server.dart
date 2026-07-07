import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agro_data_control_backend/src/firebase_request_auth.dart';
import 'package:agro_data_control_backend/src/plc_installation_config.dart';
import 'package:agro_data_control_backend/src/snapshot_runtime.dart';
import 'package:agro_data_control_backend/src/whatsapp_service.dart';

const Duration _httpHandlerTimeout = Duration(seconds: 20);
const Duration _httpWriteTimeout = Duration(seconds: 5);
const int _maxRequestBodyBytes = 16 * 1024;

Future<void> main(List<String> args) async {
  final String configPath = _resolveConfigPath(args);
  final PlcInstallationConfig config = PlcInstallationConfig.fromJson(
    jsonDecode(await File(configPath).readAsString()) as Map<String, dynamic>,
  );

  final SnapshotRuntime runtime = SnapshotRuntime(config);
  final FirebaseRequestAuthService authService = FirebaseRequestAuthService(
    projectId:
        config.runtimeEvents.firestoreProjectId ??
        Platform.environment['FIRESTORE_PROJECT_ID'] ??
        '',
    databaseId: config.runtimeEvents.firestoreDatabaseId,
    serviceAccountJsonPath: config.runtimeEvents.firestoreServiceAccountPath,
  );
  final WhatsAppService whatsAppService = WhatsAppService();
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
    await _handleRequest(request, runtime, authService, whatsAppService);
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
    await _writeJson(request.response, runtime.snapshotJson());
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

  if (request.method == 'POST' && path == '/api/notifications/whatsapp/test') {
    await _handleWhatsAppTestRequest(request, authService, whatsAppService);
    return;
  }

  await _writeJson(request.response, <String, Object?>{
    'error': 'Not found',
    'path': path,
  }, statusCode: HttpStatus.notFound);
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
      'whatsapp test send requested uid=${user.uid} role=${user.role ?? ''} tenant=$tenantId to=${_maskPhone(to)} messageLength=${message.length}',
    );
    final WhatsAppSendResult result = await whatsAppService.sendTextMessage(
      tenantId: tenantId,
      to: to,
      message: message,
    );
    _logHttp(
      'whatsapp test send success uid=${user.uid} tenant=$tenantId to=${_maskPhone(to)} messageId=${result.messageId ?? ''}',
    );
    await _writeJson(request.response, <String, Object?>{
      'ok': true,
      'provider': WhatsAppService.provider,
      'status': 'sent',
      'messageId': result.messageId,
    });
  } on WhatsAppServiceException catch (error) {
    _logHttp(
      'whatsapp test send failed uid=${user.uid} tenant=$tenantId to=${_maskPhone(to)} status=${error.metaStatusCode ?? error.statusCode} kind=${error.kind.name} error=${error.message}',
    );
    await _writeJson(request.response, <String, Object?>{
      'ok': false,
      'error': error.message,
      'details': error.details?.toString() ?? error.kind.name,
    }, statusCode: _safeErrorStatus(error.statusCode));
  } catch (error) {
    _logHttp(
      'whatsapp test send failed uid=${user.uid} tenant=$tenantId to=${_maskPhone(to)} status=unexpected error=$error',
    );
    await _writeJson(request.response, <String, Object?>{
      'ok': false,
      'error': 'Unexpected WhatsApp error',
      'details': error.toString(),
    }, statusCode: HttpStatus.badGateway);
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
    ..set(HttpHeaders.accessControlAllowMethodsHeader, 'GET, POST, OPTIONS')
    ..set(
      HttpHeaders.accessControlAllowHeadersHeader,
      'Authorization, Content-Type',
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
