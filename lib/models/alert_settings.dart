class AlertSettings {
  const AlertSettings({
    required this.muntersDoorOpen,
    required this.roomDoorOpen,
    required this.lowTemperatureHeatingActive,
    required this.highTemperatureHumidifierActive,
    required this.highHumidity,
    required this.dewPointRisk,
    required this.highDifferentialPressure,
  });

  factory AlertSettings.fromRaw(Map<String, dynamic> rawData) {
    final Object? alerts = rawData['alerts'];
    final Map<String, dynamic> source = alerts is Map<String, dynamic>
        ? alerts
        : <String, dynamic>{};
    return AlertSettings(
      muntersDoorOpen: AlertToggleSettings.fromRaw(
        source['muntersDoorOpen'],
        defaultEnabled: true,
      ),
      roomDoorOpen: AlertToggleSettings.fromRaw(
        source['roomDoorOpen'],
        defaultEnabled: true,
      ),
      lowTemperatureHeatingActive: AlertToggleSettings.fromRaw(
        source['lowTemperatureHeatingActive'],
        defaultEnabled: true,
      ),
      highTemperatureHumidifierActive: AlertToggleSettings.fromRaw(
        source['highTemperatureHumidifierActive'],
        defaultEnabled: true,
      ),
      highHumidity: AlertToggleSettings.fromRaw(
        source['highHumidity'],
        defaultEnabled: true,
      ),
      dewPointRisk: AlertToggleSettings.fromRaw(
        source['dewPointRisk'],
        defaultEnabled: true,
      ),
      highDifferentialPressure: AlertToggleSettings.fromRaw(
        source['highDifferentialPressure'],
        defaultEnabled: true,
      ),
    );
  }

  const AlertSettings.defaults()
    : muntersDoorOpen = const AlertToggleSettings.defaults(),
      roomDoorOpen = const AlertToggleSettings.defaults(),
      lowTemperatureHeatingActive = const AlertToggleSettings.defaults(),
      highTemperatureHumidifierActive = const AlertToggleSettings.defaults(),
      highHumidity = const AlertToggleSettings.defaults(),
      dewPointRisk = const AlertToggleSettings.defaults(),
      highDifferentialPressure = const AlertToggleSettings.defaults();

  final AlertToggleSettings muntersDoorOpen;
  final AlertToggleSettings roomDoorOpen;
  final AlertToggleSettings lowTemperatureHeatingActive;
  final AlertToggleSettings highTemperatureHumidifierActive;
  final AlertToggleSettings highHumidity;
  final AlertToggleSettings dewPointRisk;
  final AlertToggleSettings highDifferentialPressure;

  AlertSettings copyWith({
    AlertToggleSettings? muntersDoorOpen,
    AlertToggleSettings? roomDoorOpen,
    AlertToggleSettings? lowTemperatureHeatingActive,
    AlertToggleSettings? highTemperatureHumidifierActive,
    AlertToggleSettings? highHumidity,
    AlertToggleSettings? dewPointRisk,
    AlertToggleSettings? highDifferentialPressure,
  }) {
    return AlertSettings(
      muntersDoorOpen: muntersDoorOpen ?? this.muntersDoorOpen,
      roomDoorOpen: roomDoorOpen ?? this.roomDoorOpen,
      lowTemperatureHeatingActive:
          lowTemperatureHeatingActive ?? this.lowTemperatureHeatingActive,
      highTemperatureHumidifierActive:
          highTemperatureHumidifierActive ??
          this.highTemperatureHumidifierActive,
      highHumidity: highHumidity ?? this.highHumidity,
      dewPointRisk: dewPointRisk ?? this.dewPointRisk,
      highDifferentialPressure:
          highDifferentialPressure ?? this.highDifferentialPressure,
    );
  }

  Map<String, Object?> toFirestore() {
    return <String, Object?>{
      'muntersDoorOpen': muntersDoorOpen.toFirestore(),
      'roomDoorOpen': roomDoorOpen.toFirestore(),
      'lowTemperatureHeatingActive': lowTemperatureHeatingActive.toFirestore(),
      'highTemperatureHumidifierActive': highTemperatureHumidifierActive
          .toFirestore(),
      'highHumidity': highHumidity.toFirestore(),
      'dewPointRisk': dewPointRisk.toFirestore(),
      'highDifferentialPressure': highDifferentialPressure.toFirestore(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is AlertSettings &&
        other.muntersDoorOpen == muntersDoorOpen &&
        other.roomDoorOpen == roomDoorOpen &&
        other.lowTemperatureHeatingActive == lowTemperatureHeatingActive &&
        other.highTemperatureHumidifierActive ==
            highTemperatureHumidifierActive &&
        other.highHumidity == highHumidity &&
        other.dewPointRisk == dewPointRisk &&
        other.highDifferentialPressure == highDifferentialPressure;
  }

  @override
  int get hashCode => Object.hash(
    muntersDoorOpen,
    roomDoorOpen,
    lowTemperatureHeatingActive,
    highTemperatureHumidifierActive,
    highHumidity,
    dewPointRisk,
    highDifferentialPressure,
  );
}

class AlertToggleSettings {
  const AlertToggleSettings({required this.enabled, required this.sendWhatsapp})
    : assert(enabled || !sendWhatsapp);

  factory AlertToggleSettings.fromRaw(
    Object? value, {
    required bool defaultEnabled,
  }) {
    if (value is! Map<String, dynamic>) {
      return AlertToggleSettings(enabled: defaultEnabled, sendWhatsapp: false);
    }
    final bool enabled = value['enabled'] is bool
        ? value['enabled'] as bool
        : defaultEnabled;
    final bool rawSendWhatsapp = value['sendWhatsapp'] is bool
        ? value['sendWhatsapp'] as bool
        : false;
    return AlertToggleSettings(
      enabled: enabled,
      sendWhatsapp: enabled && rawSendWhatsapp,
    );
  }

  const AlertToggleSettings.defaults() : enabled = true, sendWhatsapp = false;

  final bool enabled;
  final bool sendWhatsapp;

  AlertToggleSettings copyWith({bool? enabled, bool? sendWhatsapp}) {
    final bool nextEnabled = enabled ?? this.enabled;
    final bool nextSendWhatsapp = nextEnabled
        ? sendWhatsapp ?? this.sendWhatsapp
        : false;
    return AlertToggleSettings(
      enabled: nextEnabled,
      sendWhatsapp: nextSendWhatsapp,
    );
  }

  Map<String, Object?> toFirestore() {
    return <String, Object?>{
      'enabled': enabled,
      'sendWhatsapp': enabled && sendWhatsapp,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is AlertToggleSettings &&
        other.enabled == enabled &&
        other.sendWhatsapp == sendWhatsapp;
  }

  @override
  int get hashCode => Object.hash(enabled, sendWhatsapp);
}
