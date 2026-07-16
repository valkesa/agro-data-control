enum AlertSettingKey {
  muntersDoorOpen,
  roomDoorOpen,
  temperatureInterior,
  highTemperatureHeatingActive,
  lowTemperatureHumidifierActive,
  highDifferentialPressure,
  highHumidity,
  dewPointRisk,
}

extension AlertSettingKeyDefaults on AlertSettingKey {
  String get firestoreKey {
    return switch (this) {
      AlertSettingKey.muntersDoorOpen => 'muntersDoorOpen',
      AlertSettingKey.roomDoorOpen => 'roomDoorOpen',
      AlertSettingKey.temperatureInterior => 'temperatureInterior',
      AlertSettingKey.highTemperatureHeatingActive =>
        'highTemperatureHeatingActive',
      AlertSettingKey.lowTemperatureHumidifierActive =>
        'lowTemperatureHumidifierActive',
      AlertSettingKey.highDifferentialPressure => 'highDifferentialPressure',
      AlertSettingKey.highHumidity => 'highHumidity',
      AlertSettingKey.dewPointRisk => 'dewPointRisk',
    };
  }

  int get fallbackOrder => index + 1;
}

class AlertSettings {
  const AlertSettings({
    required this.muntersDoorOpen,
    required this.roomDoorOpen,
    required this.temperatureInterior,
    required this.highTemperatureHeatingActive,
    required this.lowTemperatureHumidifierActive,
    required this.highHumidity,
    required this.dewPointRisk,
    required this.highDifferentialPressure,
  });

  factory AlertSettings.fromRaw(Map<String, dynamic> rawData) {
    final Object? alerts = rawData['alerts'];
    final Map<String, dynamic> source = alerts is Map<String, dynamic>
        ? alerts
        : <String, dynamic>{};
    return AlertSettings._normalized(
      muntersDoorOpen: AlertToggleSettings.fromRaw(
        source['muntersDoorOpen'],
        defaultEnabled: true,
        defaultOrder: AlertSettingKey.muntersDoorOpen.fallbackOrder,
      ),
      roomDoorOpen: AlertToggleSettings.fromRaw(
        source['roomDoorOpen'],
        defaultEnabled: true,
        defaultOrder: AlertSettingKey.roomDoorOpen.fallbackOrder,
      ),
      temperatureInterior: AlertToggleSettings.fromRaw(
        source['temperatureInterior'],
        defaultEnabled: true,
        defaultOrder: AlertSettingKey.temperatureInterior.fallbackOrder,
      ),
      highTemperatureHeatingActive: AlertToggleSettings.fromRaw(
        source['highTemperatureHeatingActive'] ??
            source['lowTemperatureHeatingActive'],
        defaultEnabled: true,
        defaultOrder:
            AlertSettingKey.highTemperatureHeatingActive.fallbackOrder,
      ),
      lowTemperatureHumidifierActive: AlertToggleSettings.fromRaw(
        source['lowTemperatureHumidifierActive'] ??
            source['highTemperatureHumidifierActive'],
        defaultEnabled: true,
        defaultOrder:
            AlertSettingKey.lowTemperatureHumidifierActive.fallbackOrder,
      ),
      highHumidity: AlertToggleSettings.fromRaw(
        source['highHumidity'],
        defaultEnabled: true,
        defaultOrder: AlertSettingKey.highHumidity.fallbackOrder,
      ),
      dewPointRisk: AlertToggleSettings.fromRaw(
        source['dewPointRisk'],
        defaultEnabled: true,
        defaultOrder: AlertSettingKey.dewPointRisk.fallbackOrder,
      ),
      highDifferentialPressure: AlertToggleSettings.fromRaw(
        source['highDifferentialPressure'],
        defaultEnabled: true,
        defaultOrder: AlertSettingKey.highDifferentialPressure.fallbackOrder,
      ),
    );
  }

  const AlertSettings.defaults()
    : muntersDoorOpen = const AlertToggleSettings.defaults(order: 1),
      roomDoorOpen = const AlertToggleSettings.defaults(order: 2),
      temperatureInterior = const AlertToggleSettings.defaults(order: 3),
      highTemperatureHeatingActive = const AlertToggleSettings.defaults(
        order: 4,
      ),
      lowTemperatureHumidifierActive = const AlertToggleSettings.defaults(
        order: 5,
      ),
      highDifferentialPressure = const AlertToggleSettings.defaults(order: 6),
      highHumidity = const AlertToggleSettings.defaults(order: 7),
      dewPointRisk = const AlertToggleSettings.defaults(order: 8);

  factory AlertSettings._normalized({
    required AlertToggleSettings muntersDoorOpen,
    required AlertToggleSettings roomDoorOpen,
    required AlertToggleSettings temperatureInterior,
    required AlertToggleSettings highTemperatureHeatingActive,
    required AlertToggleSettings lowTemperatureHumidifierActive,
    required AlertToggleSettings highHumidity,
    required AlertToggleSettings dewPointRisk,
    required AlertToggleSettings highDifferentialPressure,
  }) {
    final Map<AlertSettingKey, AlertToggleSettings> normalized =
        _normalizeOrders(<AlertSettingKey, AlertToggleSettings>{
          AlertSettingKey.muntersDoorOpen: muntersDoorOpen,
          AlertSettingKey.roomDoorOpen: roomDoorOpen,
          AlertSettingKey.temperatureInterior: temperatureInterior,
          AlertSettingKey.highTemperatureHeatingActive:
              highTemperatureHeatingActive,
          AlertSettingKey.lowTemperatureHumidifierActive:
              lowTemperatureHumidifierActive,
          AlertSettingKey.highDifferentialPressure: highDifferentialPressure,
          AlertSettingKey.highHumidity: highHumidity,
          AlertSettingKey.dewPointRisk: dewPointRisk,
        });
    return AlertSettings(
      muntersDoorOpen: normalized[AlertSettingKey.muntersDoorOpen]!,
      roomDoorOpen: normalized[AlertSettingKey.roomDoorOpen]!,
      temperatureInterior: normalized[AlertSettingKey.temperatureInterior]!,
      highTemperatureHeatingActive:
          normalized[AlertSettingKey.highTemperatureHeatingActive]!,
      lowTemperatureHumidifierActive:
          normalized[AlertSettingKey.lowTemperatureHumidifierActive]!,
      highDifferentialPressure:
          normalized[AlertSettingKey.highDifferentialPressure]!,
      highHumidity: normalized[AlertSettingKey.highHumidity]!,
      dewPointRisk: normalized[AlertSettingKey.dewPointRisk]!,
    );
  }

  final AlertToggleSettings muntersDoorOpen;
  final AlertToggleSettings roomDoorOpen;
  final AlertToggleSettings temperatureInterior;
  final AlertToggleSettings highTemperatureHeatingActive;
  final AlertToggleSettings lowTemperatureHumidifierActive;
  final AlertToggleSettings highHumidity;
  final AlertToggleSettings dewPointRisk;
  final AlertToggleSettings highDifferentialPressure;

  AlertSettings copyWith({
    AlertToggleSettings? muntersDoorOpen,
    AlertToggleSettings? roomDoorOpen,
    AlertToggleSettings? temperatureInterior,
    AlertToggleSettings? highTemperatureHeatingActive,
    AlertToggleSettings? lowTemperatureHumidifierActive,
    AlertToggleSettings? highHumidity,
    AlertToggleSettings? dewPointRisk,
    AlertToggleSettings? highDifferentialPressure,
  }) {
    return AlertSettings._normalized(
      muntersDoorOpen: muntersDoorOpen ?? this.muntersDoorOpen,
      roomDoorOpen: roomDoorOpen ?? this.roomDoorOpen,
      temperatureInterior: temperatureInterior ?? this.temperatureInterior,
      highTemperatureHeatingActive:
          highTemperatureHeatingActive ?? this.highTemperatureHeatingActive,
      lowTemperatureHumidifierActive:
          lowTemperatureHumidifierActive ?? this.lowTemperatureHumidifierActive,
      highHumidity: highHumidity ?? this.highHumidity,
      dewPointRisk: dewPointRisk ?? this.dewPointRisk,
      highDifferentialPressure:
          highDifferentialPressure ?? this.highDifferentialPressure,
    );
  }

  AlertToggleSettings toggleFor(AlertSettingKey key) {
    return switch (key) {
      AlertSettingKey.muntersDoorOpen => muntersDoorOpen,
      AlertSettingKey.roomDoorOpen => roomDoorOpen,
      AlertSettingKey.temperatureInterior => temperatureInterior,
      AlertSettingKey.highTemperatureHeatingActive =>
        highTemperatureHeatingActive,
      AlertSettingKey.lowTemperatureHumidifierActive =>
        lowTemperatureHumidifierActive,
      AlertSettingKey.highDifferentialPressure => highDifferentialPressure,
      AlertSettingKey.highHumidity => highHumidity,
      AlertSettingKey.dewPointRisk => dewPointRisk,
    };
  }

  AlertSettings withToggle(AlertSettingKey key, AlertToggleSettings toggle) {
    return copyWith(
      muntersDoorOpen: key == AlertSettingKey.muntersDoorOpen ? toggle : null,
      roomDoorOpen: key == AlertSettingKey.roomDoorOpen ? toggle : null,
      temperatureInterior: key == AlertSettingKey.temperatureInterior
          ? toggle
          : null,
      highTemperatureHeatingActive:
          key == AlertSettingKey.highTemperatureHeatingActive ? toggle : null,
      lowTemperatureHumidifierActive:
          key == AlertSettingKey.lowTemperatureHumidifierActive ? toggle : null,
      highDifferentialPressure: key == AlertSettingKey.highDifferentialPressure
          ? toggle
          : null,
      highHumidity: key == AlertSettingKey.highHumidity ? toggle : null,
      dewPointRisk: key == AlertSettingKey.dewPointRisk ? toggle : null,
    );
  }

  List<AlertSettingKey> get orderedKeys {
    final List<AlertSettingKey> keys = AlertSettingKey.values.toList();
    keys.sort(
      (AlertSettingKey a, AlertSettingKey b) =>
          toggleFor(a).order.compareTo(toggleFor(b).order),
    );
    return List<AlertSettingKey>.unmodifiable(keys);
  }

  AlertSettings move(AlertSettingKey key, int delta) {
    final List<AlertSettingKey> keys = orderedKeys.toList();
    final int currentIndex = keys.indexOf(key);
    if (currentIndex < 0) {
      return this;
    }
    final int nextIndex = (currentIndex + delta).clamp(0, keys.length - 1);
    if (nextIndex == currentIndex) {
      return this;
    }
    final AlertSettingKey moved = keys.removeAt(currentIndex);
    keys.insert(nextIndex, moved);
    final Map<AlertSettingKey, AlertToggleSettings> reordered =
        <AlertSettingKey, AlertToggleSettings>{};
    for (int i = 0; i < keys.length; i += 1) {
      final AlertSettingKey item = keys[i];
      reordered[item] = toggleFor(item).copyWith(order: i + 1);
    }
    return AlertSettings._normalized(
      muntersDoorOpen: reordered[AlertSettingKey.muntersDoorOpen]!,
      roomDoorOpen: reordered[AlertSettingKey.roomDoorOpen]!,
      temperatureInterior: reordered[AlertSettingKey.temperatureInterior]!,
      highTemperatureHeatingActive:
          reordered[AlertSettingKey.highTemperatureHeatingActive]!,
      lowTemperatureHumidifierActive:
          reordered[AlertSettingKey.lowTemperatureHumidifierActive]!,
      highDifferentialPressure:
          reordered[AlertSettingKey.highDifferentialPressure]!,
      highHumidity: reordered[AlertSettingKey.highHumidity]!,
      dewPointRisk: reordered[AlertSettingKey.dewPointRisk]!,
    );
  }

  Map<String, Object?> toFirestore() {
    return <String, Object?>{
      'muntersDoorOpen': muntersDoorOpen.toFirestore(),
      'roomDoorOpen': roomDoorOpen.toFirestore(),
      'temperatureInterior': temperatureInterior.toFirestore(),
      'highTemperatureHeatingActive': highTemperatureHeatingActive
          .toFirestore(),
      'lowTemperatureHumidifierActive': lowTemperatureHumidifierActive
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
        other.temperatureInterior == temperatureInterior &&
        other.highTemperatureHeatingActive == highTemperatureHeatingActive &&
        other.lowTemperatureHumidifierActive ==
            lowTemperatureHumidifierActive &&
        other.highHumidity == highHumidity &&
        other.dewPointRisk == dewPointRisk &&
        other.highDifferentialPressure == highDifferentialPressure;
  }

  @override
  int get hashCode => Object.hash(
    muntersDoorOpen,
    roomDoorOpen,
    temperatureInterior,
    highTemperatureHeatingActive,
    lowTemperatureHumidifierActive,
    highHumidity,
    dewPointRisk,
    highDifferentialPressure,
  );

  static Map<AlertSettingKey, AlertToggleSettings> _normalizeOrders(
    Map<AlertSettingKey, AlertToggleSettings> source,
  ) {
    final List<AlertSettingKey> keys = AlertSettingKey.values.toList();
    keys.sort((AlertSettingKey a, AlertSettingKey b) {
      final int orderA = source[a]?.order ?? a.fallbackOrder;
      final int orderB = source[b]?.order ?? b.fallbackOrder;
      final int orderComparison = orderA.compareTo(orderB);
      if (orderComparison != 0) {
        return orderComparison;
      }
      return a.fallbackOrder.compareTo(b.fallbackOrder);
    });
    return <AlertSettingKey, AlertToggleSettings>{
      for (int i = 0; i < keys.length; i += 1)
        keys[i]: source[keys[i]]!.copyWith(order: i + 1),
    };
  }
}

class AlertToggleSettings {
  const AlertToggleSettings({
    required this.enabled,
    required this.sendWhatsapp,
    required this.order,
  }) : assert(enabled || !sendWhatsapp);

  factory AlertToggleSettings.fromRaw(
    Object? value, {
    required bool defaultEnabled,
    required int defaultOrder,
  }) {
    if (value is! Map<String, dynamic>) {
      return AlertToggleSettings(
        enabled: defaultEnabled,
        sendWhatsapp: false,
        order: defaultOrder,
      );
    }
    final bool enabled = value['enabled'] is bool
        ? value['enabled'] as bool
        : defaultEnabled;
    final bool rawSendWhatsapp = value['sendWhatsapp'] is bool
        ? value['sendWhatsapp'] as bool
        : false;
    final int order = _readPositiveInt(value['order']) ?? defaultOrder;
    return AlertToggleSettings(
      enabled: enabled,
      sendWhatsapp: enabled && rawSendWhatsapp,
      order: order,
    );
  }

  const AlertToggleSettings.defaults({required this.order})
    : enabled = true,
      sendWhatsapp = false;

  final bool enabled;
  final bool sendWhatsapp;
  final int order;

  AlertToggleSettings copyWith({
    bool? enabled,
    bool? sendWhatsapp,
    int? order,
  }) {
    final bool nextEnabled = enabled ?? this.enabled;
    final bool nextSendWhatsapp = nextEnabled
        ? sendWhatsapp ?? this.sendWhatsapp
        : false;
    return AlertToggleSettings(
      enabled: nextEnabled,
      sendWhatsapp: nextSendWhatsapp,
      order: order ?? this.order,
    );
  }

  Map<String, Object?> toFirestore() {
    return <String, Object?>{
      'enabled': enabled,
      'sendWhatsapp': enabled && sendWhatsapp,
      'order': order,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is AlertToggleSettings &&
        other.enabled == enabled &&
        other.sendWhatsapp == sendWhatsapp &&
        other.order == order;
  }

  @override
  int get hashCode => Object.hash(enabled, sendWhatsapp, order);
}

int? _readPositiveInt(Object? value) {
  if (value is int && value > 0) {
    return value;
  }
  if (value is num && value.isFinite && value > 0) {
    return value.toInt();
  }
  return null;
}
