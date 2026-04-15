// Usar solo en pruebas controladas sobre salidas no criticas.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

const String _defaultHost = '192.168.10.51';
const int _defaultPort = 502;
const int _defaultUnitId = 1;
const int _defaultStart = 0;
const int _defaultCount = 16;
const int _defaultDelayMs = 1000;
const Duration _defaultTimeout = Duration(seconds: 3);

Future<void> main(List<String> args) async {
  final int? address = _readIntArg(args, '--address');
  final bool? value = _readBoolArg(args, '--value');
  final String host = _readStringArg(args, '--host') ?? _defaultHost;
  final int port = _readIntArg(args, '--port') ?? _defaultPort;
  final int unitId = _readIntArg(args, '--unit') ?? _defaultUnitId;
  final int start = _readIntArg(args, '--start') ?? _defaultStart;
  final int count = _readIntArg(args, '--count') ?? _defaultCount;
  final int delayMs = _readIntArg(args, '--delay-ms') ?? _defaultDelayMs;
  final int timeoutMs =
      _readIntArg(args, '--timeout-ms') ?? _defaultTimeout.inMilliseconds;

  if (address == null || address < 0) {
    stderr.writeln('Error: --address es obligatorio y debe ser >= 0.');
    exitCode = 64;
    return;
  }
  if (value == null) {
    stderr.writeln('Error: --value es obligatorio y debe ser true o false.');
    exitCode = 64;
    return;
  }
  if (start < 0 || count <= 0) {
    stderr.writeln('Error: --start debe ser >= 0 y --count > 0.');
    exitCode = 64;
    return;
  }
  if (port <= 0 || port > 65535) {
    stderr.writeln('Error: --port fuera de rango.');
    exitCode = 64;
    return;
  }
  if (unitId < 0 || unitId > 255) {
    stderr.writeln('Error: --unit debe estar entre 0 y 255.');
    exitCode = 64;
    return;
  }
  if (delayMs < 0 || timeoutMs <= 0) {
    stderr.writeln('Error: --delay-ms debe ser >= 0 y --timeout-ms > 0.');
    exitCode = 64;
    return;
  }

  final _SimpleModbusProbeClient client = _SimpleModbusProbeClient(
    host: host,
    port: port,
    unitId: unitId,
    timeout: Duration(milliseconds: timeoutMs),
  );

  try {
    stdout.writeln(
      'Conectando a $host:$port unitId=$unitId '
      'range=$start..${start + count - 1}',
    );
    await client.connect();
    stdout.writeln('Conexion OK.');

    final List<bool> before = await client.readCoils(
      start: start,
      count: count,
    );
    stdout.writeln('\nestado inicial leido');

    stdout.writeln('\nescribiendo coil $address = $value');
    await client.writeSingleCoil(address: address, value: value);
    stdout.writeln('write success');

    if (delayMs > 0) {
      stdout.writeln('esperando ${delayMs}ms...');
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }

    final List<bool> after = await client.readCoils(
      start: start,
      count: count,
    );
    stdout.writeln('\ncomparacion antes/despues');
    _printComparisonTable(start: start, before: before, after: after);
  } on SocketException catch (error) {
    stderr.writeln(
      'Error de conexion al PLC ($host:$port): ${error.message}',
    );
    stderr.writeln(client.buildDiagnostics());
    exitCode = 1;
  } on TimeoutException {
    stderr.writeln(
      'Error de conexion al PLC ($host:$port): timeout al conectar, leer o escribir.',
    );
    stderr.writeln(client.buildDiagnostics());
    exitCode = 1;
  } on _SimpleModbusException catch (error) {
    stderr.writeln('Error Modbus: ${error.message}');
    stderr.writeln(client.buildDiagnostics());
    exitCode = 1;
  } catch (error) {
    stderr.writeln('Error inesperado: $error');
    stderr.writeln(client.buildDiagnostics());
    exitCode = 1;
  } finally {
    await client.close(reason: 'logo_write_and_read_probe_done');
  }
}

void _printComparisonTable({
  required int start,
  required List<bool> before,
  required List<bool> after,
}) {
  final List<String> changes = <String>[];
  stdout.writeln('coil     antes   despues  cambio');
  stdout.writeln('-------  ------  -------  ------');
  for (int index = 0; index < before.length; index += 1) {
    final bool beforeValue = before[index];
    final bool afterValue = after[index];
    final String changeLabel;
    if (beforeValue == afterValue) {
      changeLabel = '';
    } else if (!beforeValue && afterValue) {
      changeLabel = '↑';
    } else {
      changeLabel = '↓';
    }
    stdout.writeln(
      'coil ${(start + index).toString().padLeft(2)}'
      '   ${beforeValue.toString().padRight(6)}'
      '  ${afterValue.toString().padRight(7)}'
      '  $changeLabel',
    );

    if (beforeValue != afterValue) {
      changes.add(
        'coil ${start + index} $beforeValue -> $afterValue',
      );
    }
  }

  stdout.writeln('');
  if (changes.isEmpty) {
    stdout.writeln('sin cambios detectados');
    return;
  }

  stdout.writeln('cambios detectados:');
  for (final String change in changes) {
    stdout.writeln(change);
  }
}

class _SimpleModbusException implements Exception {
  _SimpleModbusException(this.message);

  final String message;

  @override
  String toString() => '_SimpleModbusException: $message';
}

class _SimpleModbusProbeClient {
  _SimpleModbusProbeClient({
    required this.host,
    required this.port,
    required this.unitId,
    required this.timeout,
  });

  final String host;
  final int port;
  final int unitId;
  final Duration timeout;

  Socket? _socket;
  StreamIterator<Uint8List>? _iterator;
  Uint8List _buffer = Uint8List(0);
  int _transactionId = 0;
  String? _lastRequestHex;
  final List<String> _receivedChunksHex = <String>[];

  Future<void> connect() async {
    await close(reason: 'before_reconnect');
    final Socket socket = await Socket.connect(
      host,
      port,
      timeout: timeout,
    ).timeout(timeout);
    socket.setOption(SocketOption.tcpNoDelay, true);
    _socket = socket;
    _iterator = StreamIterator<Uint8List>(socket);
    _buffer = Uint8List(0);
  }

  Future<void> close({String reason = 'client_close'}) async {
    final StreamIterator<Uint8List>? iterator = _iterator;
    final Socket? socket = _socket;
    _iterator = null;
    _socket = null;
    _buffer = Uint8List(0);

    await iterator?.cancel().timeout(timeout).catchError((Object _) {});
    if (socket != null) {
      try {
        await socket.flush().timeout(timeout);
      } catch (_) {}
      try {
        await socket.close().timeout(timeout);
      } catch (_) {
        socket.destroy();
      }
    }
    if (reason.isNotEmpty) {
      // no-op, only to keep explicit close call sites
    }
  }

  Future<List<bool>> readCoils({
    required int start,
    required int count,
  }) async {
    final ByteData pdu = ByteData(5)
      ..setUint8(0, 0x01)
      ..setUint16(1, start, Endian.big)
      ..setUint16(3, count, Endian.big);
    final Uint8List response = await _sendRequest(pdu.buffer.asUint8List());

    if (response.isEmpty || response[0] != 0x01) {
      throw _SimpleModbusException(
        'Function code inesperado en lectura de coils: ${response.isEmpty ? 'empty' : response[0]}',
      );
    }

    final int byteCount = response[1];
    final List<bool> values = <bool>[];
    for (int byteIndex = 0; byteIndex < byteCount; byteIndex += 1) {
      final int currentByte = response[2 + byteIndex];
      for (int bitIndex = 0; bitIndex < 8 && values.length < count; bitIndex += 1) {
        values.add(((currentByte >> bitIndex) & 0x01) == 1);
      }
    }
    return values;
  }

  Future<void> writeSingleCoil({
    required int address,
    required bool value,
  }) async {
    final ByteData pdu = ByteData(5)
      ..setUint8(0, 0x05)
      ..setUint16(1, address, Endian.big)
      ..setUint16(3, value ? 0xFF00 : 0x0000, Endian.big);
    final Uint8List response = await _sendRequest(pdu.buffer.asUint8List());

    if (response.length < 5 || response[0] != 0x05) {
      throw _SimpleModbusException(
        'Function code inesperado en write single coil: ${response.isEmpty ? 'empty' : response[0]}',
      );
    }

    final ByteData data = ByteData.sublistView(response);
    final int echoedAddress = data.getUint16(1, Endian.big);
    final int echoedValue = data.getUint16(3, Endian.big);
    final int expectedValue = value ? 0xFF00 : 0x0000;
    if (echoedAddress != address || echoedValue != expectedValue) {
      throw _SimpleModbusException(
        'Respuesta inconsistente address=$echoedAddress value=0x${echoedValue.toRadixString(16)}',
      );
    }
  }

  String buildDiagnostics() {
    final String requestHex = _lastRequestHex ?? '(sin request)';
    final String receivedHex = _receivedChunksHex.isEmpty
        ? '(sin bytes recibidos)'
        : _receivedChunksHex.join(' ');
    return 'request(hex): $requestHex\nreceived(hex): $receivedHex';
  }

  Future<Uint8List> _sendRequest(Uint8List pdu) async {
    final Socket socket =
        _socket ?? (throw _SimpleModbusException('Socket no conectado'));
    final StreamIterator<Uint8List> iterator =
        _iterator ??
        (throw _SimpleModbusException('Iterador de socket no disponible'));

    _transactionId = (_transactionId + 1) & 0xFFFF;
    final ByteData mbap = ByteData(7)
      ..setUint16(0, _transactionId, Endian.big)
      ..setUint16(2, 0, Endian.big)
      ..setUint16(4, pdu.length + 1, Endian.big)
      ..setUint8(6, unitId);

    final Uint8List request = Uint8List(7 + pdu.length)
      ..setRange(0, 7, mbap.buffer.asUint8List())
      ..setRange(7, 7 + pdu.length, pdu);
    _lastRequestHex = _bytesToHex(request);
    _receivedChunksHex.clear();

    socket.add(request);
    await socket.flush().timeout(timeout);

    final Uint8List header = await _readExact(iterator, 7);
    final ByteData headerData = ByteData.sublistView(header);
    final int transactionId = headerData.getUint16(0, Endian.big);
    final int protocolId = headerData.getUint16(2, Endian.big);
    final int remainingLength = headerData.getUint16(4, Endian.big);

    if (transactionId != _transactionId) {
      throw _SimpleModbusException(
        'Transaction id inesperado $transactionId',
      );
    }
    if (protocolId != 0) {
      throw _SimpleModbusException('Protocol id invalido $protocolId');
    }
    if (remainingLength < 2) {
      throw _SimpleModbusException(
        'Longitud invalida en respuesta: $remainingLength',
      );
    }

    final Uint8List body = await _readExact(iterator, remainingLength - 1);
    if (body.isNotEmpty && (body[0] & 0x80) != 0) {
      final int exceptionCode = body.length > 1 ? body[1] : -1;
      throw _SimpleModbusException('PLC exception code $exceptionCode');
    }
    return body;
  }

  Future<Uint8List> _readExact(
    StreamIterator<Uint8List> iterator,
    int length,
  ) async {
    while (_buffer.length < length) {
      final bool hasNext = await iterator.moveNext().timeout(timeout);
      if (!hasNext) {
        throw _SimpleModbusException(
          'Conexion cerrada mientras se leia la respuesta',
        );
      }
      final Uint8List chunk = iterator.current;
      _receivedChunksHex.add(_bytesToHex(chunk));
      final Uint8List merged = Uint8List(_buffer.length + chunk.length)
        ..setRange(0, _buffer.length, _buffer)
        ..setRange(_buffer.length, _buffer.length + chunk.length, chunk);
      _buffer = merged;
    }

    final Uint8List data = Uint8List.sublistView(_buffer, 0, length);
    _buffer = Uint8List.sublistView(_buffer, length);
    return data;
  }
}

String? _readStringArg(List<String> args, String flag) {
  final int index = args.indexOf(flag);
  if (index == -1 || index + 1 >= args.length) {
    return null;
  }
  return args[index + 1];
}

int? _readIntArg(List<String> args, String flag) {
  final String? value = _readStringArg(args, flag);
  if (value == null) {
    return null;
  }
  return int.tryParse(value);
}

bool? _readBoolArg(List<String> args, String flag) {
  final String? value = _readStringArg(args, flag)?.toLowerCase();
  if (value == null) {
    return null;
  }
  if (value == 'true') {
    return true;
  }
  if (value == 'false') {
    return false;
  }
  return null;
}

String _bytesToHex(List<int> bytes) {
  return bytes
      .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join(' ');
}
