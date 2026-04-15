import 'dart:io';
import 'package:args/args.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('host', abbr: 'h', defaultsTo: '192.168.10.51')
    ..addOption('port', abbr: 'p', defaultsTo: '502')
    ..addOption('unit-id', abbr: 'u', defaultsTo: '1')
    ..addOption('address', abbr: 'a', defaultsTo: '112')
    ..addFlag('help', abbr: 'x', negatable: false);

  final result = parser.parse(args);

  if (result['help'] == true) {
    print('''
Uso:
  dart run scripts/test_vw224_types.dart --host 192.168.10.51 --port 502 --unit-id 1 --address 112
''');
    exit(0);
  }

  final host = result['host'] as String;
  final port = int.parse(result['port'] as String);
  final unitId = int.parse(result['unit-id'] as String);
  final address = int.parse(result['address'] as String);

  final client = ModbusClientTcp(
    host,
    serverPort: port,
    unitId: unitId,
    connectionMode: ModbusConnectionMode.autoConnectAndKeepConnected,
    responseTimeout: const Duration(seconds: 3),
  );

  try {
    print('Probando HR$address en $host:$port (unitId=$unitId)...');

    final reg16 = ModbusInt16Register(
      name: 'hr$address-int16',
      type: ModbusElementType.holdingRegister,
      address: address,
    );

    final rc16 = await client.send(reg16.getReadRequest());
    if (rc16 == ModbusResponseCode.requestSucceed && reg16.value != null) {
      final value16 = reg16.value!.toInt();
      final raw16 = value16 & 0xFFFF;
      final signed16 = raw16 >= 0x8000 ? raw16 - 0x10000 : raw16;
      print('HR$address como 16 bits:');
      print('  uint16 = $raw16');
      print('  int16  = $signed16');
    } else {
      print('HR$address como 16 bits: error ($rc16)');
    }

    final reg32 = ModbusInt32Register(
      name: 'hr$address-int32',
      type: ModbusElementType.holdingRegister,
      address: address,
    );

    final rc32 = await client.send(reg32.getReadRequest());
    if (rc32 == ModbusResponseCode.requestSucceed && reg32.value != null) {
      final value32 = reg32.value!.toInt();
      final raw32 = value32 & 0xFFFFFFFF;
      print('HR$address-HR${address + 1} como 32 bits:');
      print('  uint32 = $raw32');
      print('  int32  = $value32');
    } else {
      print('HR$address-HR${address + 1} como 32 bits: error ($rc32)');
    }
  } catch (e, st) {
    print('Error: $e');
    print(st);
    exit(1);
  } finally {
    await client.disconnect();
  }
}