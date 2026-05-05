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
  const PlcMaintenanceSettings({required this.entriesByPlcId});

  const PlcMaintenanceSettings.empty()
    : entriesByPlcId = const <String, PlcMaintenanceEntry>{};

  final Map<String, PlcMaintenanceEntry> entriesByPlcId;

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
    return PlcMaintenanceSettings(entriesByPlcId: updated);
  }

  PlcMaintenanceSettings withoutExpired() {
    return PlcMaintenanceSettings(entriesByPlcId: activeEntriesByPlcId);
  }

  DateTime? get nextExpiration {
    DateTime? next;
    for (final PlcMaintenanceEntry entry in activeEntriesByPlcId.values) {
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
    return <String, Object?>{
      for (final MapEntry<String, PlcMaintenanceEntry> entry
          in activeEntriesByPlcId.entries)
        entry.key: entry.value.toFirestore(),
    };
  }
}
