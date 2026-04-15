import 'dart:io';
import 'package:args/args.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('host', defaultsTo: '192.168.10.51')
    ..addOption('port', defaultsTo: '502')
    ..addOption('unit-id', defaultsTo: '1')
    ..addOption('start', defaultsTo: '220')
    ..addOption('end', defaultsTo: '228')
    ..addOption('type', defaultsTo: 'holding', allowed: ['holding', 'input']);

  final result = parser.parse(args);

  final host = result['host'] as String;
  final port = int.parse(result['port'] as String);
  final unitId = int.parse(result['unit-id'] as String);
  final start = int.parse(result['start'] as String);
  final end = int.parse(result['end'] as String);
  final typeArg = result['type'] as String;

  final elementType = typeArg == 'input'
      ? ModbusElementType.inputRegister
      : ModbusElementType.holdingRegister;

  final client = ModbusClientTcp(
    host,
    serverPort: port,
    unitId: unitId,
    connectionMode: ModbusConnectionMode.autoConnectAndKeepConnected,
    responseTimeout: const Duration(seconds: 3),
  );

  try {
    print(
      'Escaneando $typeArg registers desde $start hasta $end en $host:$port',
    );

    for (int address = start; address <= end; address++) {
      final reg = ModbusInt16Register(
        name: 'r$address',
        address: address,
        type: elementType,
      );

      final response = await client.send(reg.getReadRequest());
      if (response == ModbusResponseCode.requestSucceed && reg.value != null) {
        final raw = reg.value!.toInt() & 0xFFFF;
        final signed = raw >= 0x8000 ? raw - 0x10000 : raw;
        print('addr=$address raw=$raw signed=$signed');
      } else {
        print('addr=$address error=$response');
      }
    }
  } catch (e) {
    print('Error: $e');
    exit(1);
  } finally {
    await client.disconnect();
  }
}
