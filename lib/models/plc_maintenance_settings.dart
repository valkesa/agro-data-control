import 'package:flutter/material.dart';

enum PlcMaintenanceMode {
  inSitu,
  systems,
  scheduled;

  String get firestoreValue => switch (this) {
    PlcMaintenanceMode.inSitu => 'in_situ',
    PlcMaintenanceMode.systems => 'systems',
    PlcMaintenanceMode.scheduled => 'scheduled',
  };

  String get label => switch (this) {
    PlcMaintenanceMode.inSitu => 'In Situ',
    PlcMaintenanceMode.systems => 'Sistemas',
    PlcMaintenanceMode.scheduled => 'Programado',
  };

  String get fullLabel => switch (this) {
    PlcMaintenanceMode.inSitu => 'Mantenimiento In-Situ',
    PlcMaintenanceMode.systems => 'Mantenimiento Sistemas',
    PlcMaintenanceMode.scheduled => 'Mantenimiento Programado',
  };

  IconData get icon => switch (this) {
    PlcMaintenanceMode.inSitu => Icons.construction_rounded,
    PlcMaintenanceMode.systems => Icons.memory_rounded,
    PlcMaintenanceMode.scheduled => Icons.event_available_rounded,
  };

  static PlcMaintenanceMode? fromFirestore(Object? value) {
    return switch (value?.toString()) {
      'in_situ' => PlcMaintenanceMode.inSitu,
      'systems' => PlcMaintenanceMode.systems,
      'scheduled' => PlcMaintenanceMode.scheduled,
      _ => null,
    };
  }
}

class PlcMaintenanceEntry {
  const PlcMaintenanceEntry({required this.mode, required this.expiresAt});

  final PlcMaintenanceMode mode;
  final DateTime? expiresAt;

  bool get isExpired {
    final DateTime? currentExpiresAt = expiresAt;
    return currentExpiresAt != null &&
        !currentExpiresAt.isAfter(DateTime.now());
  }

  Map<String, Object?> toFirestore() {
    return <String, Object?>{
      'mode': mode.firestoreValue,
      'expiresAt': expiresAt,
    };
  }
}

class PlcMaintenanceSettings {
  const PlcMaintenanceSettings({
    required this.entriesByPlcId,
    this.entriesByDeviceId = const <String, PlcMaintenanceEntry>{},
  });

  const PlcMaintenanceSettings.empty()
    : entriesByPlcId = const <String, PlcMaintenanceEntry>{},
      entriesByDeviceId = const <String, PlcMaintenanceEntry>{};

  final Map<String, PlcMaintenanceEntry> entriesByPlcId;
  final Map<String, PlcMaintenanceEntry> entriesByDeviceId;

  Map<String, PlcMaintenanceMode> get modesByPlcId {
    return <String, PlcMaintenanceMode>{
      for (final MapEntry<String, PlcMaintenanceEntry> entry
          in activeEntriesByPlcId.entries)
        entry.key: entry.value.mode,
    };
  }

  Map<String, PlcMaintenanceEntry> get activeEntriesByPlcId {
    return <String, PlcMaintenanceEntry>{
      for (final MapEntry<String, PlcMaintenanceEntry> entry
          in entriesByPlcId.entries)
        if (!entry.value.isExpired) entry.key: entry.value,
    };
  }

  Map<String, PlcMaintenanceEntry> get activeEntriesByDeviceId {
    return <String, PlcMaintenanceEntry>{
      for (final MapEntry<String, PlcMaintenanceEntry> entry
          in entriesByDeviceId.entries)
        if (!entry.value.isExpired) entry.key: entry.value,
    };
  }

  PlcMaintenanceMode? modeFor(String? plcId) {
    if (plcId == null || plcId.isEmpty) {
      return null;
    }
    final PlcMaintenanceEntry? entry = entriesByPlcId[plcId];
    if (entry == null || entry.isExpired) {
      return null;
    }
    return entry.mode;
  }

  DateTime? expiresAtFor(String? plcId) {
    if (plcId == null || plcId.isEmpty) {
      return null;
    }
    final PlcMaintenanceEntry? entry = entriesByPlcId[plcId];
    if (entry == null || entry.isExpired) {
      return null;
    }
    return entry.expiresAt;
  }

  bool isInMaintenance(String? plcId) => modeFor(plcId) != null;

  PlcMaintenanceMode? modeForDevice(String? deviceId) {
    if (deviceId == null || deviceId.isEmpty) {
      return null;
    }
    final PlcMaintenanceEntry? entry = entriesByDeviceId[deviceId];
    if (entry == null || entry.isExpired) {
      return null;
    }
    return entry.mode;
  }

  DateTime? expiresAtForDevice(String? deviceId) {
    if (deviceId == null || deviceId.isEmpty) {
      return null;
    }
    final PlcMaintenanceEntry? entry = entriesByDeviceId[deviceId];
    if (entry == null || entry.isExpired) {
      return null;
    }
    return entry.expiresAt;
  }

  bool isDeviceInMaintenance(String? deviceId) =>
      modeForDevice(deviceId) != null;

  PlcMaintenanceSettings copyWithEntry({
    required String plcId,
    required PlcMaintenanceEntry? entry,
  }) {
    final Map<String, PlcMaintenanceEntry> updated =
        Map<String, PlcMaintenanceEntry>.of(activeEntriesByPlcId);
    if (entry == null) {
      updated.remove(plcId);
    } else {
      updated[plcId] = entry;
    }
    return PlcMaintenanceSettings(
      entriesByPlcId: updated,
      entriesByDeviceId: activeEntriesByDeviceId,
    );
  }

  PlcMaintenanceSettings copyWithDeviceEntry({
    required String deviceId,
    required PlcMaintenanceEntry? entry,
  }) {
    final Map<String, PlcMaintenanceEntry> updated =
        Map<String, PlcMaintenanceEntry>.of(activeEntriesByDeviceId);
    if (entry == null) {
      updated.remove(deviceId);
    } else {
      updated[deviceId] = entry;
    }
    return PlcMaintenanceSettings(
      entriesByPlcId: activeEntriesByPlcId,
      entriesByDeviceId: updated,
    );
  }

  PlcMaintenanceSettings withoutExpired() {
    return PlcMaintenanceSettings(
      entriesByPlcId: activeEntriesByPlcId,
      entriesByDeviceId: activeEntriesByDeviceId,
    );
  }

  DateTime? get nextExpiration {
    DateTime? next;
    for (final PlcMaintenanceEntry entry in <PlcMaintenanceEntry>[
      ...activeEntriesByPlcId.values,
      ...activeEntriesByDeviceId.values,
    ]) {
      final DateTime? expiresAt = entry.expiresAt;
      if (expiresAt == null) {
        continue;
      }
      if (next == null || expiresAt.isBefore(next)) {
        next = expiresAt;
      }
    }
    return next;
  }

  Map<String, Object?> toFirestore() {
    final Map<String, PlcMaintenanceEntry> activeLegacy = activeEntriesByPlcId;
    final Map<String, PlcMaintenanceEntry> activeDevices =
        activeEntriesByDeviceId;
    if (activeDevices.isEmpty) {
      return <String, Object?>{
        for (final MapEntry<String, PlcMaintenanceEntry> entry
            in activeLegacy.entries)
          entry.key: entry.value.toFirestore(),
      };
    }
    return <String, Object?>{
      'legacy': <String, Object?>{
        for (final MapEntry<String, PlcMaintenanceEntry> entry
            in activeLegacy.entries)
          entry.key: entry.value.toFirestore(),
      },
      'devices': <String, Object?>{
        for (final MapEntry<String, PlcMaintenanceEntry> entry
            in activeDevices.entries)
          entry.key: entry.value.toFirestore(),
      },
    };
  }
}
