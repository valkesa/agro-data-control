import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';
import '../models/differential_pressure_history_point.dart';

class DifferentialPressureHistoryRepository {
  DifferentialPressureHistoryRepository({FirebaseFirestore? firestore})
    : _firestore = firestore;

  static const Duration _cacheTtl = Duration(minutes: 5);
  static final Map<String, _CacheEntry<List<DifferentialPressureDailyPoint>>>
  _dailyCache = <String, _CacheEntry<List<DifferentialPressureDailyPoint>>>{};

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get firestore => _firestore ?? FirebaseFirestore.instance;

  Future<List<DifferentialPressureDailyPoint>>
  fetchDifferentialPressureDailyHistory({
    required String tenantId,
    required String siteId,
    required String plcId,
    int limit = 30,
  }) async {
    final String cacheKey = 'daily|$tenantId|$siteId|$plcId|$limit';
    final _CacheEntry<List<DifferentialPressureDailyPoint>>? cached =
        _dailyCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      debugPrint(
        '[Firestore] differential pressure daily history cache hit key=$cacheKey count=${cached.value.length}',
      );
      return cached.value;
    }

    final String path =
        FirestorePaths.differentialPressureDailyHistoryCollection(
          tenantId: tenantId,
          siteId: siteId,
          plcId: plcId,
        );
    debugPrint(
      '[Firestore] differential pressure daily history read started path=$path',
    );

    final QuerySnapshot<Map<String, dynamic>> snapshot = await firestore
        .collection(path)
        .orderBy('timestampDayStart', descending: true)
        .limit(limit)
        .get();

    final List<DifferentialPressureDailyPoint> points =
        snapshot.docs
            .map(
              (doc) => DifferentialPressureDailyPoint.fromFirestore(
                doc.data(),
                documentId: doc.id,
              ),
            )
            .toList(growable: false)
          ..sort(
            (left, right) =>
                left.timestampDayStart.compareTo(right.timestampDayStart),
          );

    debugPrint(
      '[Firestore] differential pressure daily history read success path=$path count=${points.length}',
    );
    _dailyCache[cacheKey] = _CacheEntry<List<DifferentialPressureDailyPoint>>(
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
