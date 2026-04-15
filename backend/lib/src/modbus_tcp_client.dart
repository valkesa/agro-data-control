import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class ModbusException implements Exception {
  ModbusException(this.message);

  final String message;

  @override
  String toString() => 'ModbusException: $message';
}

class ModbusTcpClient {
  ModbusTcpClient({
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
  int _transactionId = 0;
  Uint8List _buffer = Uint8List(0);

  Future<void> connect() async {
    final Stopwatch stopwatch = Stopwatch()..start();
    Socket? nextSocket;
    StreamIterator<Uint8List>? nextIterator;
    bool connected = false;

    await close(reason: 'before_reconnect');
    _logPlc(
      'connect started host=$host port=$port timeoutMs=${timeout.inMilliseconds}',
    );
    try {
      nextSocket = await Socket.connect(
        host,
        port,
        timeout: timeout,
      ).timeout(timeout);
      nextSocket.setOption(SocketOption.tcpNoDelay, true);
      nextIterator = StreamIterator<Uint8List>(nextSocket);
      _socket = nextSocket;
      _iterator = nextIterator;
      _logSocketOpened(nextSocket);
      connected = true;
      stopwatch.stop();
      _logPlc('connect success elapsedMs=${stopwatch.elapsedMilliseconds}');
    } on TimeoutException catch (_) {
      stopwatch.stop();
      _logPlc(
        'timeout operation=connect host=$host port=$port elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      rethrow;
    } catch (error, stackTrace) {
      stopwatch.stop();
      _logPlc('error operation=connect error=$error');
      _logPlc('error operation=connect stack=$stackTrace');
      rethrow;
    } finally {
      if (!connected) {
        await nextIterator?.cancel().timeout(timeout).catchError((Object _) {});
        _destroySocket(nextSocket, reason: 'connect_failed');
        _socket = null;
        _iterator = null;
        _buffer = Uint8List(0);
      }
    }
  }

  Future<void> close({String reason = 'client_close'}) async {
    final StreamIterator<Uint8List>? iterator = _iterator;
    final Socket? socket = _socket;

    _socket = null;
    _iterator = null;
    _buffer = Uint8List(0);

    await iterator?.cancel().timeout(timeout).catchError((Object _) {});
    _destroySocket(socket, reason: reason);
  }

  Future<List<int>> readHoldingRegisters(
    int address,
    int count, {
    String? operationLabel,
  }) {
    return _runRead<List<int>>(
      operation: operationLabel ?? 'holdingRegister@$address/$count',
      action: () =>
          _readWords(functionCode: 0x03, address: address, count: count),
    );
  }

  Future<List<int>> readInputRegisters(
    int address,
    int count, {
    String? operationLabel,
  }) {
    return _runRead<List<int>>(
      operation: operationLabel ?? 'inputRegister@$address/$count',
      action: () =>
          _readWords(functionCode: 0x04, address: address, count: count),
    );
  }

  Future<List<bool>> readCoils(
    int address,
    int count, {
    String? operationLabel,
  }) {
    return _runRead<List<bool>>(
      operation: operationLabel ?? 'coil@$address/$count',
      action: () =>
          _readBits(functionCode: 0x01, address: address, count: count),
    );
  }

  Future<List<bool>> readDiscreteInputs(
    int address,
    int count, {
    String? operationLabel,
  }) {
    return _runRead<List<bool>>(
      operation: operationLabel ?? 'discreteInput@$address/$count',
      action: () =>
          _readBits(functionCode: 0x02, address: address, count: count),
    );
  }

  Future<List<int>> _readWords({
    required int functionCode,
    required int address,
    required int count,
  }) async {
    final Uint8List pdu = _buildReadPdu(
      functionCode: functionCode,
      address: address,
      count: count,
    );
    final Uint8List response = await _sendRequest(pdu);

    if (response[0] != functionCode) {
      throw ModbusException('Unexpected function code ${response[0]}');
    }

    final int byteCount = response[1];
    if (byteCount != count * 2) {
      throw ModbusException('Unexpected byte count $byteCount');
    }

    final ByteData data = ByteData.sublistView(response, 2, 2 + byteCount);
    return List<int>.generate(
      count,
      (index) => data.getUint16(index * 2, Endian.big),
    );
  }

  Future<List<bool>> _readBits({
    required int functionCode,
    required int address,
    required int count,
  }) async {
    final Uint8List pdu = _buildReadPdu(
      functionCode: functionCode,
      address: address,
      count: count,
    );
    final Uint8List response = await _sendRequest(pdu);

    if (response[0] != functionCode) {
      throw ModbusException('Unexpected function code ${response[0]}');
    }

    final int byteCount = response[1];
    final List<bool> values = <bool>[];
    for (int byteIndex = 0; byteIndex < byteCount; byteIndex++) {
      final int currentByte = response[2 + byteIndex];
      for (
        int bitIndex = 0;
        bitIndex < 8 && values.length < count;
        bitIndex++
      ) {
        values.add(((currentByte >> bitIndex) & 0x01) == 1);
      }
    }

    return values;
  }

  Uint8List _buildReadPdu({
    required int functionCode,
    required int address,
    required int count,
  }) {
    final ByteData pdu = ByteData(5)
      ..setUint8(0, functionCode)
      ..setUint16(1, address, Endian.big)
      ..setUint16(3, count, Endian.big);
    return pdu.buffer.asUint8List();
  }

  Future<Uint8List> _sendRequest(Uint8List pdu) async {
    final Socket socket =
        _socket ?? (throw ModbusException('Socket not connected'));
    final StreamIterator<Uint8List> iterator =
        _iterator ?? (throw ModbusException('Socket iterator not available'));

    _transactionId = (_transactionId + 1) & 0xFFFF;
    final ByteData mbap = ByteData(7)
      ..setUint16(0, _transactionId, Endian.big)
      ..setUint16(2, 0, Endian.big)
      ..setUint16(4, pdu.length + 1, Endian.big)
      ..setUint8(6, unitId);

    socket.add(Uint8List.fromList(<int>[...mbap.buffer.asUint8List(), ...pdu]));
    await socket.flush().timeout(timeout);

    final Uint8List header = await _readExact(iterator, 7);
    final ByteData headerData = ByteData.sublistView(header);
    final int responseTransactionId = headerData.getUint16(0, Endian.big);
    if (responseTransactionId != _transactionId) {
      throw ModbusException(
        'Transaction mismatch $responseTransactionId != $_transactionId',
      );
    }

    final int protocolId = headerData.getUint16(2, Endian.big);
    if (protocolId != 0) {
      throw ModbusException('Unsupported protocol id $protocolId');
    }

    final int remainingLength = headerData.getUint16(4, Endian.big);
    if (remainingLength < 2) {
      throw ModbusException('Invalid response length $remainingLength');
    }

    final Uint8List body = await _readExact(iterator, remainingLength - 1);
    if ((body[0] & 0x80) != 0) {
      final int exceptionCode = body.length > 1 ? body[1] : -1;
      throw ModbusException('PLC exception code $exceptionCode');
    }

    return body;
  }

  Future<T> _runRead<T>({
    required String operation,
    required Future<T> Function() action,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    _logPlc('read started block=$operation');
    try {
      final T result = await action().timeout(timeout);
      stopwatch.stop();
      _logPlc(
        'read success block=$operation elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      return result;
    } on TimeoutException catch (_) {
      stopwatch.stop();
      _logPlc(
        'timeout operation=read block=$operation elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      await close(reason: 'read_timeout');
      rethrow;
    } catch (error, stackTrace) {
      stopwatch.stop();
      _logPlc('error operation=read block=$operation error=$error');
      _logPlc('error operation=read block=$operation stack=$stackTrace');
      await close(reason: 'read_error');
      rethrow;
    }
  }

  Future<Uint8List> _readExact(
    StreamIterator<Uint8List> iterator,
    int length,
  ) async {
    final BytesBuilder builder = BytesBuilder(copy: false);
    if (_buffer.isNotEmpty) {
      final int fromBuffer = _buffer.length >= length ? length : _buffer.length;
      builder.add(Uint8List.sublistView(_buffer, 0, fromBuffer));
      _buffer = _buffer.length > fromBuffer
          ? Uint8List.sublistView(_buffer, fromBuffer)
          : Uint8List(0);
    }

    while (builder.length < length) {
      final bool hasNext = await iterator.moveNext().timeout(timeout);
      if (!hasNext) {
        throw ModbusException('Connection closed while reading response');
      }

      final Uint8List chunk = iterator.current;
      final int missing = length - builder.length;
      if (chunk.length <= missing) {
        builder.add(chunk);
        continue;
      }

      builder.add(Uint8List.sublistView(chunk, 0, missing));
      _buffer = Uint8List.sublistView(chunk, missing);
    }

    return builder.toBytes();
  }
}

void _destroySocket(Socket? socket, {required String reason}) {
  if (socket == null) {
    return;
  }

  final String socketInfo = _describeSocket(socket);
  try {
    socket.destroy();
  } catch (_) {
    // Ignore destroy failures; we're already tearing the socket down.
  } finally {
    _logSocketClosed(reason: reason, socketInfo: socketInfo);
  }
}

void _logSocketOpened(Socket socket) {
  try {
    stdout.writeln('[PLC] socket opened ${_describeSocket(socket)}');
  } catch (_) {
    stdout.writeln('[PLC] socket opened');
  }
}

void _logSocketClosed({required String reason, required String socketInfo}) {
  try {
    stdout.writeln('[PLC] socket closed reason=$reason $socketInfo');
  } catch (_) {
    stdout.writeln('[PLC] socket closed reason=$reason');
  }
}

String _describeSocket(Socket socket) {
  try {
    return 'local=${socket.address.address}:${socket.port} '
        'remote=${socket.remoteAddress.address}:${socket.remotePort}';
  } catch (_) {
    return 'local=unknown remote=unknown';
  }
}

void _logPlc(String message) {
  stdout.writeln('[PLC] $message');
}
