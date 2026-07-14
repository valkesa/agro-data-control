enum AlertType {
  muntersDoorOpen,
  roomDoorOpen,
  highTemperatureHeatingActive,
  lowTemperatureHumidifierActive,
  highDifferentialPressure,
  highHumidity,
  dewPointRisk,
}

enum AlertSeverity { critical, high, medium, low }

class AlertMetadata {
  const AlertMetadata({
    required this.type,
    required this.code,
    required this.order,
    required this.severity,
    required this.defaultLabel,
  });

  final AlertType type;
  final String code;
  final int order;
  final AlertSeverity severity;
  final String defaultLabel;
}

extension AlertTypeStableId on AlertType {
  String get id => AlertMetadataRegistry.metadataFor(this).code;
}

class AlertMetadataRegistry {
  const AlertMetadataRegistry._();

  static const List<AlertMetadata> all = <AlertMetadata>[
    AlertMetadata(
      type: AlertType.muntersDoorOpen,
      code: 'munters_door_open',
      order: 1,
      severity: AlertSeverity.critical,
      defaultLabel: 'Puerta Munters abierta',
    ),
    AlertMetadata(
      type: AlertType.roomDoorOpen,
      code: 'room_door_open',
      order: 2,
      severity: AlertSeverity.critical,
      defaultLabel: 'Puerta de sala abierta',
    ),
    AlertMetadata(
      type: AlertType.highTemperatureHeatingActive,
      code: 'high_temperature_heating_active',
      order: 3,
      severity: AlertSeverity.high,
      defaultLabel: 'Temperatura alta con calefacción activa',
    ),
    AlertMetadata(
      type: AlertType.lowTemperatureHumidifierActive,
      code: 'low_temperature_humidifier_active',
      order: 4,
      severity: AlertSeverity.high,
      defaultLabel: 'Temperatura baja con bomba humidificadora activa',
    ),
    AlertMetadata(
      type: AlertType.highDifferentialPressure,
      code: 'high_differential_pressure',
      order: 5,
      severity: AlertSeverity.high,
      defaultLabel: 'Presión diferencial alta',
    ),
    AlertMetadata(
      type: AlertType.highHumidity,
      code: 'high_humidity',
      order: 6,
      severity: AlertSeverity.medium,
      defaultLabel: 'Humedad interior alta',
    ),
    AlertMetadata(
      type: AlertType.dewPointRisk,
      code: 'dew_point_risk',
      order: 7,
      severity: AlertSeverity.medium,
      defaultLabel: 'Riesgo por punto de rocío',
    ),
  ];

  static List<AlertMetadata> get ordered {
    final List<AlertMetadata> copy = all.toList(growable: false)
      ..sort((AlertMetadata a, AlertMetadata b) => a.order.compareTo(b.order));
    return List<AlertMetadata>.unmodifiable(copy);
  }

  static AlertMetadata metadataFor(AlertType type) {
    for (final AlertMetadata metadata in all) {
      if (metadata.type == type) {
        return metadata;
      }
    }
    throw StateError('Missing alert metadata for $type');
  }

  static int priorityIndex(AlertType type) => metadataFor(type).order - 1;
}

List<AlertType> get alertPriorityOrder => List<AlertType>.unmodifiable(
  AlertMetadataRegistry.ordered.map((AlertMetadata metadata) => metadata.type),
);

int alertPriorityIndex(AlertType type) =>
    AlertMetadataRegistry.priorityIndex(type);
