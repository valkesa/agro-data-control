import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';
import '../models/temperature_history_point.dart';

class TemperatureHistoryRepository {
  TemperatureHistoryRepository({FirebaseFirestore? firestore})
    : _firestore = firestore;

  static const Duration _cacheTtl = Duration(minutes: 5);
  static final Map<String, _CacheEntry<List<TemperatureHourlyPoint>>>
  _hourlyCache = <String, _CacheEntry<List<TemperatureHourlyPoint>>>{};
  static final Map<String, _CacheEntry<List<TemperatureDailyPoint>>>
  _dailyCache = <String, _CacheEntry<List<TemperatureDailyPoint>>>{};

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get firestore => _firestore ?? FirebaseFirestore.instance;

  Future<List<TemperatureHourlyPoint>> fetchTemperatureHourlyHistory({
    required String tenantId,
    required String siteId,
    required String plcId,
    int limit = 24,
  }) async {
    final String cacheKey = 'hourly|$tenantId|$siteId|$plcId|$limit';
    final _CacheEntry<List<TemperatureHourlyPoint>>? cached =
        _hourlyCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      debugPrint(
        '[Firestore] temperature hourly history cache hit key=$cacheKey count=${cached.value.length}',
      );
      return cached.value;
    }

    final String path = FirestorePaths.temperatureHourlyHistoryCollection(
      tenantId: tenantId,
      siteId: siteId,
      plcId: plcId,
    );
    debugPrint(
      '[Firestore] temperature hourly history read started path=$path',
    );

    final QuerySnapshot<Map<String, dynamic>> snapshot = await firestore
        .collection(path)
        .orderBy('timestampHourStart', descending: true)
        .limit(limit)
        .get();

    final List<TemperatureHourlyPoint> points =
        snapshot.docs
            .map(
              (doc) => TemperatureHourlyPoint.fromFirestore(
                doc.data(),
                documentId: doc.id,
              ),
            )
            .toList(growable: false)
          ..sort((left, right) => left.timestamp.compareTo(right.timestamp));

    debugPrint(
      '[Firestore] temperature hourly history read success path=$path count=${points.length}',
    );
    _hourlyCache[cacheKey] = _CacheEntry<List<TemperatureHourlyPoint>>(
      value: points,
      expiresAt: DateTime.now().add(_cacheTtl),
    );
    return points;
  }

  Future<List<TemperatureDailyPoint>> fetchTemperatureDailyHistory({
    required String tenantId,
    required String siteId,
    required String plcId,
    int limit = 30,
  }) async {
    final String cacheKey = 'daily|$tenantId|$siteId|$plcId|$limit';
    final _CacheEntry<List<TemperatureDailyPoint>>? cached =
        _dailyCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      debugPrint(
        '[Firestore] temperature daily history cache hit key=$cacheKey count=${cached.value.length}',
      );
      return cached.value;
    }

    final String path = FirestorePaths.temperatureDailyHistoryCollection(
      tenantId: tenantId,
      siteId: siteId,
      plcId: plcId,
    );
    debugPrint('[Firestore] temperature daily history read started path=$path');

    final QuerySnapshot<Map<String, dynamic>> snapshot = await firestore
        .collection(path)
        .orderBy('dateKey', descending: true)
        .limit(limit)
        .get();

    final List<TemperatureDailyPoint> points =
        snapshot.docs
            .map(
              (doc) => TemperatureDailyPoint.fromFirestore(
                doc.data(),
                documentId: doc.id,
              ),
            )
            .toList(growable: false)
          ..sort((left, right) => left.timestamp.compareTo(right.timestamp));

    debugPrint(
      '[Firestore] temperature daily history read success path=$path count=${points.length}',
    );
    _dailyCache[cacheKey] = _CacheEntry<List<TemperatureDailyPoint>>(
      value: points,
      expiresAt: DateTime.now().add(_cacheTtl),
    );
    return points;
  }
}

class _CacheEntry<T> {
  const _CacheEntry({required this.value, required this.expiresAt});

  final T value;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
