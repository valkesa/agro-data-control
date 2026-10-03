/// Value families accepted by the in-memory demo contracts.
enum DemoSignalKind { number, boolean, text }

/// Closed set of signals backed by the current [MuntersModel] snapshot.
///
/// Keeping this as an enum is the first safety boundary: scenario input can
/// never address an arbitrary object path or invent a backend field.
enum DemoSignalKey {
  indoorTemperature('tempInterior'),
  outdoorTemperature('tempExterior'),
  inletTemperature('tempIngresoSala'),
  indoorHumidity('humInterior'),
  outdoorHumidity('humExterior'),
  differentialPressure('presionDiferencial'),
  ammonia('nh3'),
  ventilationPower('tensionSalidaVentiladores'),
  heatingStage1('resistencia1'),
  heatingStage2('resistencia2'),
  humidifier('bombaHumidificador'),
  fanQ5('fanQ5'),
  fanQ6('fanQ6'),
  fanQ7('fanQ7'),
  fanQ8('fanQ8'),
  fanQ9('fanQ9'),
  fanQ10('fanQ10'),
  roomDoorOpen('salaAbierta'),
  equipmentDoorOpen('munterAbierto'),
  generalAlarm('alarmaGeneral'),
  networkFailure('fallaRed'),
  waterLevelAlarm('nivelAguaAlarma'),
  humidifierThermalFailure('fallaTermicaBomba'),
  configured('configured'),
  backendOnline('backendOnline'),
  plcReachable('plcReachable'),
  plcRunning('plcRunning'),
  dataFresh('dataFresh'),
  plcOnline('plcOnline'),
  equipmentState('estadoEquipo');

  const DemoSignalKey(this.wireName);

  final String wireName;
}

/// Metadata and validation for one explicitly supported demo signal.
class DemoSignalDefinition {
  DemoSignalDefinition({
    required this.key,
    required this.label,
    required this.kind,
    required this.nullable,
    this.min,
    this.max,
    this.interpolable = false,
    Iterable<String> allowedTextValues = const <String>{},
  }) : allowedTextValues = Set<String>.unmodifiable(allowedTextValues) {
    if (label.trim().isEmpty) {
      throw ArgumentError.value(label, 'label', 'Must not be empty');
    }
    if ((min != null || max != null) && kind != DemoSignalKind.number) {
      throw ArgumentError('Only numeric signals may define a range');
    }
    if (min != null && max != null && min! > max!) {
      throw ArgumentError('min must be less than or equal to max');
    }
    if (interpolable && kind != DemoSignalKind.number) {
      throw ArgumentError('Only numeric signals may be interpolated');
    }
    if (allowedTextValues.isNotEmpty && kind != DemoSignalKind.text) {
      throw ArgumentError('Only text signals may define allowed values');
    }
  }

  final DemoSignalKey key;
  final String label;
  final DemoSignalKind kind;
  final bool nullable;
  final double? min;
  final double? max;
  final bool interpolable;
  final Set<String> allowedTextValues;

  void validateValue(Object? value, {String parameterName = 'value'}) {
    if (value == null) {
      if (!nullable) {
        throw ArgumentError.value(value, parameterName, 'May not be null');
      }
      return;
    }

    switch (kind) {
      case DemoSignalKind.number:
        if (value is! num || !value.isFinite) {
          throw ArgumentError.value(
            value,
            parameterName,
            'Expected a finite number',
          );
        }
        final number = value.toDouble();
        if (min != null && number < min!) {
          throw ArgumentError.value(
            value,
            parameterName,
            'Must be greater than or equal to $min',
          );
        }
        if (max != null && number > max!) {
          throw ArgumentError.value(
            value,
            parameterName,
            'Must be less than or equal to $max',
          );
        }
      case DemoSignalKind.boolean:
        if (value is! bool) {
          throw ArgumentError.value(value, parameterName, 'Expected a bool');
        }
      case DemoSignalKind.text:
        if (value is! String || value.trim().isEmpty) {
          throw ArgumentError.value(
            value,
            parameterName,
            'Expected a non-empty String',
          );
        }
        if (allowedTextValues.isNotEmpty &&
            !allowedTextValues.contains(value)) {
          throw ArgumentError.value(
            value,
            parameterName,
            'Expected one of ${allowedTextValues.join(', ')}',
          );
        }
    }
  }
}

/// Typed allowlist for Stage 2A. It intentionally omits CO2, water, a third
/// heating stage, every pending.* source and unsupported disinfection signals.
class DemoSignalCatalog {
  DemoSignalCatalog._();

  static final Map<DemoSignalKey, DemoSignalDefinition> _definitions =
      Map<DemoSignalKey, DemoSignalDefinition>.unmodifiable({
        DemoSignalKey.indoorTemperature: _number(
          DemoSignalKey.indoorTemperature,
          'Temperatura interior',
          min: -50,
          max: 80,
        ),
        DemoSignalKey.outdoorTemperature: _number(
          DemoSignalKey.outdoorTemperature,
          'Temperatura exterior',
          min: -50,
          max: 80,
        ),
        DemoSignalKey.inletTemperature: _number(
          DemoSignalKey.inletTemperature,
          'Temperatura de ingreso',
          min: -50,
          max: 80,
        ),
        DemoSignalKey.indoorHumidity: _number(
          DemoSignalKey.indoorHumidity,
          'Humedad interior',
          min: 0,
          max: 100,
        ),
        DemoSignalKey.outdoorHumidity: _number(
          DemoSignalKey.outdoorHumidity,
          'Humedad exterior',
          min: 0,
          max: 100,
        ),
        DemoSignalKey.differentialPressure: _number(
          DemoSignalKey.differentialPressure,
          'Presión diferencial',
          min: -1000,
          max: 5000,
        ),
        DemoSignalKey.ammonia: _number(
          DemoSignalKey.ammonia,
          'NH3',
          min: 0,
          max: 10000,
        ),
        DemoSignalKey.ventilationPower: _number(
          DemoSignalKey.ventilationPower,
          'Potencia de ventilación',
          min: 0,
          max: 1000,
        ),
        for (final entry in <DemoSignalKey, String>{
          DemoSignalKey.heatingStage1: 'Calefacción etapa 1',
          DemoSignalKey.heatingStage2: 'Calefacción etapa 2',
          DemoSignalKey.humidifier: 'Humidificador',
          DemoSignalKey.fanQ5: 'Ventilador Q5',
          DemoSignalKey.fanQ6: 'Ventilador Q6',
          DemoSignalKey.fanQ7: 'Ventilador Q7',
          DemoSignalKey.fanQ8: 'Ventilador Q8',
          DemoSignalKey.fanQ9: 'Ventilador Q9',
          DemoSignalKey.fanQ10: 'Ventilador Q10',
          DemoSignalKey.roomDoorOpen: 'Puerta de sala abierta',
          DemoSignalKey.equipmentDoorOpen: 'Puerta de equipo abierta',
          DemoSignalKey.generalAlarm: 'Alarma general',
          DemoSignalKey.networkFailure: 'Falla de red',
          DemoSignalKey.waterLevelAlarm: 'Alarma de nivel de agua',
          DemoSignalKey.humidifierThermalFailure:
              'Falla térmica del humidificador',
          DemoSignalKey.configured: 'Equipo configurado',
          DemoSignalKey.backendOnline: 'Backend online',
          DemoSignalKey.plcReachable: 'PLC alcanzable',
          DemoSignalKey.plcRunning: 'PLC ejecutándose',
          DemoSignalKey.dataFresh: 'Datos frescos',
          DemoSignalKey.plcOnline: 'PLC online',
        }.entries)
          entry.key: DemoSignalDefinition(
            key: entry.key,
            label: entry.value,
            kind: DemoSignalKind.boolean,
            nullable: true,
          ),
        DemoSignalKey.equipmentState: DemoSignalDefinition(
          key: DemoSignalKey.equipmentState,
          label: 'Estado del equipo',
          kind: DemoSignalKind.text,
          nullable: true,
          allowedTextValues: const <String>{'RUN', 'STOP', 'FAULT'},
        ),
      });

  static List<DemoSignalDefinition> get definitions =>
      List<DemoSignalDefinition>.unmodifiable(_definitions.values);

  static DemoSignalDefinition definitionFor(DemoSignalKey key) =>
      _definitions[key]!;

  static DemoSignalKey parseKey(String wireName) {
    final normalized = wireName.trim();
    for (final key in DemoSignalKey.values) {
      if (key.wireName == normalized && _definitions.containsKey(key)) {
        return key;
      }
    }
    throw ArgumentError.value(wireName, 'signalKey', 'Unsupported demo signal');
  }

  static DemoSignalDefinition _number(
    DemoSignalKey key,
    String label, {
    required double min,
    required double max,
  }) => DemoSignalDefinition(
    key: key,
    label: label,
    kind: DemoSignalKind.number,
    nullable: true,
    min: min,
    max: max,
    interpolable: true,
  );
}
