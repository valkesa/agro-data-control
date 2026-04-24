import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';

class ControlDashboardConfigService {
  const ControlDashboardConfigService();

  Future<ControlDashboardConfigResult> readConfig({
    required String tenantId,
    required String siteId,
  }) async {
    final String path = FirestorePaths.controlDashboardSettings(
      tenantId,
      siteId,
    );
    debugPrint('[Firestore] dashboard config read started path=$path');

    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance.doc(path).get();

      if (!snapshot.exists) {
        debugPrint('[Firestore] dashboard config missing path=$path');
        return ControlDashboardConfigResult.notFound(path: path);
      }

      final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};
      debugPrint(
        '[Firestore] dashboard config read success path=$path data=$data',
      );

      return ControlDashboardConfigResult.success(
        path: path,
        active: data['active'] as bool?,
        updatedAt: _parseDateTime(data['updatedAt']),
        updatedByUid: data['updatedByUid']?.toString(),
        thresholds: ControlDashboardThresholds.fromRaw(data),
        rawData: data,
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[Firestore] dashboard config read error path=$path error=$error',
      );
      debugPrint('[Firestore] dashboard config read error stack=$stackTrace');
      return ControlDashboardConfigResult.error(
        path: path,
        errorMessage: error.toString(),
      );
    }
  }

  Stream<ControlDashboardConfigResult> watchConfig({
    required String tenantId,
    required String siteId,
  }) {
    final String path = FirestorePaths.controlDashboardSettings(
      tenantId,
      siteId,
    );
    debugPrint('[Firestore] dashboard config watch started path=$path');
    return FirebaseFirestore.instance.doc(path).snapshots().map((
      DocumentSnapshot<Map<String, dynamic>> snapshot,
    ) {
      if (!snapshot.exists) {
        return ControlDashboardConfigResult.notFound(path: path);
      }
      final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};
      return ControlDashboardConfigResult.success(
        path: path,
        active: data['active'] as bool?,
        updatedAt: _parseDateTime(data['updatedAt']),
        updatedByUid: data['updatedByUid']?.toString(),
        thresholds: ControlDashboardThresholds.fromRaw(data),
        rawData: data,
      );
    });
  }

  Future<ControlDashboardSaveResult> saveThresholds({
    required String tenantId,
    required String siteId,
    required String userUid,
    required ControlDashboardThresholds thresholds,
  }) async {
    final String path = FirestorePaths.controlDashboardSettings(
      tenantId,
      siteId,
    );
    debugPrint('[Firestore] dashboard config save started path=$path');

    try {
      await FirebaseFirestore.instance.doc(path).set(<String, Object?>{
        'munters': <String, Object?>{
          'munters1': <String, Object?>{
            'tempInterior': <String, Object?>{
              'min': thresholds.tempInteriorMin,
              'opt': thresholds.tempInteriorOpt,
              'max': thresholds.tempInteriorMax,
            },
            'humidityInterior': <String, Object?>{
              'min': thresholds.humidityInteriorMin,
              'opt': thresholds.humidityInteriorOpt,
              'max': thresholds.humidityInteriorMax,
            },
            'presionDiferencial': <String, Object?>{
              'max': thresholds.filterPressureMax,
            },
          },
        },
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByUid': userUid,
      }, SetOptions(merge: true));

      debugPrint('[Firestore] dashboard config save success path=$path');
      return const ControlDashboardSaveResult.success();
    } catch (error, stackTrace) {
      debugPrint(
        '[Firestore] dashboard config save error path=$path error=$error',
      );
      debugPrint('[Firestore] dashboard config save error stack=$stackTrace');
      return ControlDashboardSaveResult.error(error.toString());
    }
  }

  Future<ControlDashboardSaveResult> saveMagnifierSettings({
    required String tenantId,
    required String siteId,
    required String userUid,
    required double zoom,
    required double size,
  }) async {
    final String path = FirestorePaths.controlDashboardSettings(
      tenantId,
      siteId,
    );
    debugPrint('[Firestore] dashboard magnifier save started path=$path');

    try {
      await FirebaseFirestore.instance.doc(path).set(<String, Object?>{
        'ui': <String, Object?>{
          'magnifier': <String, Object?>{'zoom': zoom, 'size': size},
        },
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByUid': userUid,
      }, SetOptions(merge: true));

      debugPrint('[Firestore] dashboard magnifier save success path=$path');
      return const ControlDashboardSaveResult.success();
    } catch (error, stackTrace) {
      debugPrint(
        '[Firestore] dashboard magnifier save error path=$path error=$error',
      );
      debugPrint(
        '[Firestore] dashboard magnifier save error stack=$stackTrace',
      );
      return ControlDashboardSaveResult.error(error.toString());
    }
  }

  Future<ControlDashboardSaveResult> saveUnitVisibilitySettings({
    required String tenantId,
    required String siteId,
    required String userUid,
    required bool showMunters1,
    required bool showMunters2,
  }) async {
    final String path = FirestorePaths.controlDashboardSettings(
      tenantId,
      siteId,
    );
    debugPrint('[Firestore] dashboard unit visibility save started path=$path');

    try {
      await FirebaseFirestore.instance.doc(path).set(<String, Object?>{
        'ui': <String, Object?>{
          'visibleUnits': <String, Object?>{
            'munters1': showMunters1,
            'munters2': showMunters2,
          },
        },
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByUid': userUid,
      }, SetOptions(merge: true));

      debugPrint(
        '[Firestore] dashboard unit visibility save success path=$path',
      );
      return const ControlDashboardSaveResult.success();
    } catch (error, stackTrace) {
      debugPrint(
        '[Firestore] dashboard unit visibility save error path=$path error=$error',
      );
      debugPrint(
        '[Firestore] dashboard unit visibility save error stack=$stackTrace',
      );
      return ControlDashboardSaveResult.error(error.toString());
    }
  }

  DateTime? _parseDateTime(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }
}

class ControlDashboardConfigResult {
  const ControlDashboardConfigResult({
    required this.path,
    required this.exists,
    required this.active,
    required this.updatedAt,
    required this.updatedByUid,
    required this.thresholds,
    required this.rawData,
    required this.errorMessage,
  });

  factory ControlDashboardConfigResult.notFound({required String path}) {
    return ControlDashboardConfigResult(
      path: path,
      exists: false,
      active: null,
      updatedAt: null,
      updatedByUid: null,
      thresholds: const ControlDashboardThresholds.empty(),
      rawData: const <String, dynamic>{},
      errorMessage: null,
    );
  }

  factory ControlDashboardConfigResult.error({
    required String path,
    required String errorMessage,
  }) {
    return ControlDashboardConfigResult(
      path: path,
      exists: false,
      active: null,
      updatedAt: null,
      updatedByUid: null,
      thresholds: const ControlDashboardThresholds.empty(),
      rawData: const <String, dynamic>{},
      errorMessage: errorMessage,
    );
  }

  factory ControlDashboardConfigResult.success({
    required String path,
    required bool? active,
    required DateTime? updatedAt,
    required String? updatedByUid,
    required ControlDashboardThresholds thresholds,
    required Map<String, dynamic> rawData,
  }) {
    return ControlDashboardConfigResult(
      path: path,
      exists: true,
      active: active,
      updatedAt: updatedAt,
      updatedByUid: updatedByUid,
      thresholds: thresholds,
      rawData: rawData,
      errorMessage: null,
    );
  }

  final String path;
  final bool exists;
  final bool? active;
  final DateTime? updatedAt;
  final String? updatedByUid;
  final ControlDashboardThresholds thresholds;
  final Map<String, dynamic> rawData;
  final String? errorMessage;

  bool get hasError => errorMessage != null;

  double? readMagnifierZoom() => ControlDashboardThresholds._readDouble(
    rawData,
    const ['ui', 'magnifier', 'zoom'],
  );

  double? readMagnifierSize() => ControlDashboardThresholds._readDouble(
    rawData,
    const ['ui', 'magnifier', 'size'],
  );

  bool? readShowMunters1() => ControlDashboardThresholds._readBool(
    rawData,
    const ['ui', 'visibleUnits', 'munters1'],
  );

  bool? readShowMunters2() => ControlDashboardThresholds._readBool(
    rawData,
    const ['ui', 'visibleUnits', 'munters2'],
  );

  bool get hasVisibleUnitsConfig {
    final Object? ui = rawData['ui'];
    if (ui is! Map<String, dynamic>) {
      return false;
    }
    final Object? visibleUnits = ui['visibleUnits'];
    return visibleUnits is Map<String, dynamic>;
  }
}

class ControlDashboardThresholds {
  const ControlDashboardThresholds({
    required this.tempInteriorMin,
    required this.tempInteriorOpt,
    required this.tempInteriorMax,
    required this.humidityInteriorMin,
    required this.humidityInteriorOpt,
    required this.humidityInteriorMax,
    required this.filterPressureMax,
  });

  const ControlDashboardThresholds.empty()
    : tempInteriorMin = null,
      tempInteriorOpt = null,
      tempInteriorMax = null,
      humidityInteriorMin = null,
      humidityInteriorOpt = null,
      humidityInteriorMax = null,
      filterPressureMax = null;

  factory ControlDashboardThresholds.fromRaw(Map<String, dynamic> rawData) {
    return ControlDashboardThresholds(
      tempInteriorMin: _readDouble(rawData, const [
        'munters',
        'munters1',
        'tempInterior',
        'min',
      ]),
      tempInteriorOpt: _readDouble(rawData, const [
        'munters',
        'munters1',
        'tempInterior',
        'opt',
      ]),
      tempInteriorMax: _readDouble(rawData, const [
        'munters',
        'munters1',
        'tempInterior',
        'max',
      ]),
      humidityInteriorMin: _readDouble(rawData, const [
        'munters',
        'munters1',
        'humidityInterior',
        'min',
      ]),
      humidityInteriorOpt: _readDouble(rawData, const [
        'munters',
        'munters1',
        'humidityInterior',
        'opt',
      ]),
      humidityInteriorMax: _readDouble(rawData, const [
        'munters',
        'munters1',
        'humidityInterior',
        'max',
      ]),
      filterPressureMax: _readDouble(rawData, const [
        'munters',
        'munters1',
        'presionDiferencial',
        'max',
      ]),
    );
  }

  final double? tempInteriorMin;
  final double? tempInteriorOpt;
  final double? tempInteriorMax;
  final double? humidityInteriorMin;
  final double? humidityInteriorOpt;
  final double? humidityInteriorMax;
  final double? filterPressureMax;

  static double? _readDouble(Map<String, dynamic> source, List<String> path) {
    Object? current = source;
    for (final String segment in path) {
      if (current is! Map<String, dynamic>) {
        return null;
      }
      current = current[segment];
    }

    if (current is num) {
      return current.toDouble();
    }
    return null;
  }

  static bool? _readBool(Map<String, dynamic> source, List<String> path) {
    Object? current = source;
    for (final String segment in path) {
      if (current is! Map<String, dynamic>) {
        return null;
      }
      current = current[segment];
    }
    if (current is bool) {
      return current;
    }
    return null;
  }
}

class ControlDashboardSaveResult {
  const ControlDashboardSaveResult._(this.errorMessage);

  const ControlDashboardSaveResult.success() : this._(null);

  const ControlDashboardSaveResult.error(String errorMessage)
    : this._(errorMessage);

  final String? errorMessage;

  bool get isSuccess => errorMessage == null;
}
