// scripts/logo_read_vw.dart
import 'dart:io';
import 'package:args/args.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('host', abbr: 'h', defaultsTo: '192.168.10.51')
    ..addOption('port', abbr: 'p', defaultsTo: '502')
    ..addOption('unit-id', abbr: 'u', defaultsTo: '1')
    ..addOption('address', abbr: 'a', defaultsTo: '224')
    ..addFlag('signed', defaultsTo: false)
    ..addFlag('help', abbr: 'x', negatable: false);

  final result = parser.parse(args);

  if (result['help'] == true) {
    print('''
Uso:
  dart run scripts/logo_read_vw.dart --host 192.168.10.51 --port 502 --unit-id 1 --address 224

Opciones:
  --host       IP del PLC
  --port       Puerto Modbus TCP
  --unit-id    Unit ID Modbus
  --address    Dirección holding register a leer
  --signed     Interpretar como int16 con signo
''');
    exit(0);
  }

  final host = result['host'] as String;
  final port = int.parse(result['port'] as String);
  final unitId = int.parse(result['unit-id'] as String);
  final address = int.parse(result['address'] as String);
  final signed = result['signed'] as bool;

  final client = ModbusClientTcp(
    host,
    serverPort: port,
    unitId: unitId,
    connectionMode: ModbusConnectionMode.autoConnectAndKeepConnected,
    connectionTimeout: const Duration(seconds: 3),
    responseTimeout: const Duration(seconds: 3),
  );

  try {
    print('Leyendo VW/HR $address en $host:$port (unitId=$unitId)...');

    final register = ModbusInt16Register(
      name: 'vw_$address',
      address: address,
      type: ModbusElementType.holdingRegister,
    );

    final responseCode = await client.send(register.getReadRequest());
    final value = register.value;

    if (responseCode != ModbusResponseCode.requestSucceed || value == null) {
      print(
        'No se pudo leer el registro $address (responseCode=${responseCode.name})',
      );
      exit(2);
    }

    final rawUnsigned = value.toInt() & 0xFFFF;
    final signedValue = rawUnsigned >= 0x8000
        ? rawUnsigned - 0x10000
        : rawUnsigned;

    print('Resultado:');
    print('  address: $address');
    print('  raw unsigned: $rawUnsigned');
    print('  signed int16: $signedValue');
    print('  valor usado: ${signed ? signedValue : rawUnsigned}');
  } catch (e, st) {
    print('Error leyendo VW/HR $address: $e');
    print(st);
    exit(1);
  } finally {
    await client.disconnect();
  }
}
