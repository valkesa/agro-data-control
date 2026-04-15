import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agro_data_control_backend/src/plc_installation_config.dart';
import 'package:agro_data_control_backend/src/snapshot_runtime.dart';

const Duration _httpHandlerTimeout = Duration(seconds: 10);
const Duration _httpWriteTimeout = Duration(seconds: 5);

Future<void> main(List<String> args) async {
  final String configPath = _resolveConfigPath(args);
  final PlcInstallationConfig config = PlcInstallationConfig.fromJson(
    jsonDecode(await File(configPath).readAsString()) as Map<String, dynamic>,
  );

  final SnapshotRuntime runtime = SnapshotRuntime(config);
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
    await _handleRequest(request, runtime);
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
) async {
  final Stopwatch stopwatch = Stopwatch()..start();
  final String path = request.uri.path;
  _logHttp(
    'request started method=${request.method} path=$path remote=${request.connectionInfo?.remoteAddress.address}',
  );

  try {
    await _handleRequestInternal(request, runtime).timeout(_httpHandlerTimeout);
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

  await _writeJson(request.response, <String, Object?>{
    'error': 'Not found',
    'path': path,
  }, statusCode: HttpStatus.notFound);
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
    ..set(HttpHeaders.accessControlAllowMethodsHeader, 'GET, OPTIONS')
    ..set(HttpHeaders.accessControlAllowHeadersHeader, 'Content-Type')
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
