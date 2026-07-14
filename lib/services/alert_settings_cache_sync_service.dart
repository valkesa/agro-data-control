import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../models/alert_settings.dart';
import '../models/dashboard_range_settings.dart';

class AlertSettingsCacheSyncService {
  const AlertSettingsCacheSyncService({String? backendSnapshotEndpoint})
    : _backendSnapshotEndpoint = backendSnapshotEndpoint;

  static const Duration _requestTimeout = Duration(seconds: 6);

  final String? _backendSnapshotEndpoint;

  Future<bool> sync({
    required String siteId,
    required DashboardRangeSettings ranges,
    required AlertSettings alerts,
  }) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return false;
    }
    final String token = await user.getIdToken() ?? '';
    if (token.isEmpty) {
      return false;
    }

    final Map<String, Object?> settings = <String, Object?>{
      'alerts': alerts.toFirestore(),
      'munters': <String, Object?>{
        'munters1': <String, Object?>{
          'tempInterior': <String, Object?>{
            'min': ranges.temperatureMin,
            'opt': (ranges.temperatureMin + ranges.temperatureMax) / 2,
            'max': ranges.temperatureMax,
          },
          'humidityInterior': <String, Object?>{
            'min': ranges.humidityMin,
            'opt': (ranges.humidityMin + ranges.humidityMax) / 2,
            'max': ranges.humidityMax,
            'alarm': <String, Object?>{
              'yellowMinInclusive': ranges.humidityAlarmYellowMin,
              'redMinExclusive': ranges.humidityAlarmRedMinExclusive,
            },
          },
          'dewPointMargin': <String, Object?>{
            'alarm': <String, Object?>{
              'redMaxInclusive': ranges.dewPointMarginAlarmRedMax,
              'yellowMaxExclusive':
                  ranges.dewPointMarginAlarmYellowMaxExclusive,
            },
          },
          'presionDiferencial': <String, Object?>{
            'max': ranges.filterPressureMax,
          },
        },
      },
    };

    try {
      final http.Response response = await http
          .put(
            _uri(),
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, Object?>{
              'siteId': siteId,
              'settings': settings,
            }),
          )
          .timeout(_requestTimeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Uri _uri() {
    final String endpoint = _backendSnapshotEndpoint?.trim().isNotEmpty == true
        ? _backendSnapshotEndpoint!.trim()
        : AppConfig.currentBackendSnapshotUrl;
    return Uri.parse(
      endpoint,
    ).replace(path: '/api/alerts/settings-cache', query: '');
  }
}
