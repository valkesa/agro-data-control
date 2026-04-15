import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../models/dashboard_snapshot.dart';
import '../models/munters_model.dart';
import '../models/plc_unit_diagnostics.dart';
import '../models/plc_raw_payload.dart';

class PlcDashboardService {
  static const Duration _requestTimeout = Duration(seconds: 6);
  const PlcDashboardService({String? endpoint}) : _endpoint = endpoint;

  final String? _endpoint;

  Future<DashboardSnapshot> fetchSnapshot() async {
    final LiveSnapshotResult result = await fetchLiveSnapshot();
    return result.snapshot ?? DashboardSnapshot.placeholder();
  }

  Future<LiveSnapshotResult> fetchLiveSnapshot() async {
    final String apiUrl = _endpoint ?? AppConfig.backendSnapshotUrl;
    if (apiUrl.isEmpty) {
      return const LiveSnapshotResult.error(
        message: 'PLC_API_URL is empty.',
        source: 'config',
      );
    }

    final Uri uri = Uri.parse(apiUrl);

    try {
      final http.Response response = await http
          .get(uri)
          .timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return LiveSnapshotResult.error(
          message:
              'El backend respondio con estado HTTP ${response.statusCode}.',
          source: 'http_status',
          statusCode: response.statusCode,
          endpoint: apiUrl,
        );
      }

      if (response.body.trim().isEmpty) {
        return LiveSnapshotResult.error(
          message: 'El backend devolvio una respuesta vacia.',
          source: 'empty_body',
          endpoint: apiUrl,
          statusCode: response.statusCode,
        );
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return LiveSnapshotResult.error(
          message: 'La respuesta del backend no es un objeto JSON valido.',
          source: 'invalid_payload',
          endpoint: apiUrl,
          statusCode: response.statusCode,
        );
      }

      final DashboardSnapshot snapshot = _parseSnapshot(decoded);
      return LiveSnapshotResult.success(
        snapshot: snapshot,
        rawPayload: decoded,
        endpoint: apiUrl,
        statusCode: response.statusCode,
        receivedAt: DateTime.now(),
      );
    } on TimeoutException {
      return LiveSnapshotResult.error(
        message:
            'El backend no respondio dentro de ${_requestTimeout.inSeconds} segundos.',
        source: 'timeout',
        endpoint: apiUrl,
      );
    } on FormatException catch (error) {
      return LiveSnapshotResult.error(
        message: 'El backend devolvio JSON invalido: $error',
        source: 'invalid_json',
        endpoint: apiUrl,
      );
    } on http.ClientException catch (error) {
      return LiveSnapshotResult.error(
        message:
            'No se pudo conectar con el backend: ${error.message.isEmpty ? 'error de red' : error.message}',
        source: 'client_exception',
        endpoint: apiUrl,
      );
    } catch (error) {
      return LiveSnapshotResult.error(
        message: 'Fallo la lectura del backend: $error',
        source: 'request_failed',
        endpoint: apiUrl,
      );
    }
  }

  DashboardSnapshot _parseSnapshot(Map<String, dynamic> decoded) {
    _debugSnapshotPayload(decoded);
    final PlcRawPayload raw = PlcRawPayload(decoded);
    final bool backendOnline =
        _parseBool(
          raw.firstValue([
            ['backendOnline'],
            ['snapshotOnline'],
            ['status', 'backendOnline'],
            ['status', 'snapshotOnline'],
            ['connected'],
            ['online'],
            ['plcOnline'],
            ['status', 'plcOnline'],
          ]),
        ) ??
        false;

    return DashboardSnapshot(
      backendOnline: backendOnline,
      clientName: _parseString(
        raw.firstValue([
          ['clientName'],
          ['status', 'clientName'],
        ]),
      ),
      startedAt: _parseDateTime(
        raw.firstValue([
          ['startedAt'],
          ['status', 'startedAt'],
        ]),
      ),
      lastUpdatedAt: _parseDateTime(
        raw.firstValue([
          ['lastUpdatedAt'],
          ['lastUpdate'],
          ['timestamp'],
          ['status', 'lastUpdatedAt'],
        ]),
      ),
      units: [
        _parseUnit(
          name: 'Munters 1',
          unitKey: 'munters1',
          historyClientId: _sanitizeSegment(
            _parseString(
              raw.firstValue([
                ['clientName'],
                ['status', 'clientName'],
              ]),
            ),
          ),
          backendOnline: backendOnline,
          raw: raw,
          unitCandidates: const [
            ['munters1'],
            ['units', '0'],
            ['units', 'munters1'],
            ['data', 'munters1'],
          ],
        ),
        _parseUnit(
          name: 'Munters 2',
          unitKey: 'munters2',
          historyClientId: _sanitizeSegment(
            _parseString(
              raw.firstValue([
                ['clientName'],
                ['status', 'clientName'],
              ]),
            ),
          ),
          backendOnline: backendOnline,
          raw: raw,
          unitCandidates: const [
            ['munters2'],
            ['units', '1'],
            ['units', 'munters2'],
            ['data', 'munters2'],
          ],
        ),
      ],
    );
  }

  void _debugSnapshotPayload(Map<String, dynamic> decoded) {
    final Map<String, dynamic> status =
        decoded['status'] is Map<String, dynamic>
        ? decoded['status'] as Map<String, dynamic>
        : <String, dynamic>{};
    final Map<String, dynamic> munters1 =
        decoded['munters1'] is Map<String, dynamic>
        ? decoded['munters1'] as Map<String, dynamic>
        : <String, dynamic>{};
    final Map<String, dynamic> munters2 =
        decoded['munters2'] is Map<String, dynamic>
        ? decoded['munters2'] as Map<String, dynamic>
        : <String, dynamic>{};

    // Temporary trace to confirm which payload field is driving each UI state.
    debugPrint(
      '[frontend-payload] root.plcOnline=${decoded['plcOnline']} status.plcOnline=${status['plcOnline']} munters1.plcOnline=${munters1['plcOnline']} munters2.plcOnline=${munters2['plcOnline']}',
    );
    debugPrint(
      '[frontend-payload] munters1.configured=${munters1['configured']} munters1.plcReachable=${munters1['plcReachable']} munters1.dataFresh=${munters1['dataFresh']} munters2.configured=${munters2['configured']} munters2.plcReachable=${munters2['plcReachable']} munters2.dataFresh=${munters2['dataFresh']}',
    );
    debugPrint(
      '[frontend-payload] munters1.estadoEquipo=${munters1['estadoEquipo']} munters2.estadoEquipo=${munters2['estadoEquipo']}',
    );
    _debugUnitSignals('munters1', munters1);
    _debugUnitSignals('munters2', munters2);
  }

  void _debugUnitSignals(String unitName, Map<String, dynamic> unit) {
    debugPrint(
      '[frontend-payload] $unitName fans='
      'Q5=${unit['fanQ5']} '
      'Q6=${unit['fanQ6']} '
      'Q7=${unit['fanQ7']} '
      'Q8=${unit['fanQ8']} '
      'Q9=${unit['fanQ9']} '
      'Q10=${unit['fanQ10']}',
    );
    debugPrint(
      '[frontend-payload] $unitName alarmOutputQ12='
      '${unit['alarmaGeneral'] ?? unit['alarmOutputQ12']} '
      'doorRoom=${unit['salaAbierta'] ?? unit['doorRoom']} '
      'doorMunter=${unit['munterAbierto'] ?? unit['doorMunter']}',
    );
  }

  MuntersModel _parseUnit({
    required String name,
    required String unitKey,
    required String? historyClientId,
    required bool backendOnline,
    required PlcRawPayload raw,
    required List<List<String>> unitCandidates,
  }) {
    final Object? unitObject = raw.firstValue(unitCandidates);
    final PlcRawPayload? unitRaw = unitObject is Map<String, dynamic>
        ? PlcRawPayload(unitObject)
        : null;
    const PlcRawPayload? fallbackRaw = null;
    final PlcUnitDiagnostics? diagnostics = _parseUnitDiagnostics(
      backendOnline: backendOnline,
      unitRaw: unitRaw,
      fallbackRaw: fallbackRaw,
    );
    final DateTime? resolvedLastUpdatedAt =
        diagnostics?.lastPollAt ??
        _parseDateTime(
          _read(unitRaw, fallbackRaw, const [
            ['lastUpdatedAt'],
          ]),
        );

    return MuntersModel(
      name: name,
      historyClientId: historyClientId,
      historyPlcId: unitKey,
      diagnostics: diagnostics,
      backendOnline: backendOnline,
      configured: _parseBool(
        _read(unitRaw, fallbackRaw, const [
          ['configured'],
        ]),
      ),
      plcReachable: _parseBool(
        _read(unitRaw, fallbackRaw, const [
          ['plcReachable'],
        ]),
      ),
      plcRunning: _parseBool(
        _read(unitRaw, fallbackRaw, const [
          ['plcRunning'],
        ]),
      ),
      dataFresh: _parseBool(
        _read(unitRaw, fallbackRaw, const [
          ['dataFresh'],
        ]),
      ),
      plcOnline: _parseBool(
        _read(unitRaw, fallbackRaw, const [
          ['plcOnline'],
          ['connected'],
          ['online'],
        ]),
      ),
      plcLatencyMs: _parseInt(
        _read(unitRaw, fallbackRaw, const [
          ['plcLatencyMs'],
        ]),
      ),
      lastUpdatedAt: resolvedLastUpdatedAt,
      lastHeartbeatValue: _read(unitRaw, fallbackRaw, const [
        ['lastHeartbeatValue'],
      ]),
      lastHeartbeatChangeAt: _parseDateTime(
        _read(unitRaw, fallbackRaw, const [
          ['lastHeartbeatChangeAt'],
        ]),
      ),
      lastError: _parseString(
        _read(unitRaw, fallbackRaw, const [
          ['lastError'],
        ]),
      ),
      tempInterior: _parseSignedHoldingRegister(
        _read(unitRaw, fallbackRaw, const [
          ['tempInterior'],
          ['tempInside'],
          ['clima', 'tempInterior'],
          ['clima', 'tempInside'],
          ['vm90'],
          ['VM90'],
          ['vw90'],
          ['VW90'],
          ['holdingRegisters', '45'],
          ['holdingRegisters', 'HR45'],
          ['registers', 'HR45'],
          ['registers', '45'],
          ['hr', '45'],
          ['hr45'],
        ]),
      ),
      humInterior: _parseSignedHoldingRegister(
        _read(unitRaw, fallbackRaw, const [
          ['humedadInterior'],
          ['humInterior'],
          ['rhInside'],
          ['clima', 'humedadInterior'],
          ['clima', 'rhInside'],
          ['vm106'],
          ['VM106'],
          ['vw106'],
          ['VW106'],
          ['holdingRegisters', '53'],
          ['holdingRegisters', 'HR53'],
          ['registers', 'HR53'],
          ['registers', '53'],
          ['hr', '53'],
          ['hr53'],
        ]),
      ),
      tempExterior: _parseSignedHoldingRegister(
        _read(unitRaw, fallbackRaw, const [
          ['tempExterior'],
          ['tempOutside'],
          ['clima', 'tempExterior'],
          ['clima', 'tempOutside'],
          ['vm122'],
          ['VM122'],
          ['vw122'],
          ['VW122'],
          ['holdingRegisters', '61'],
          ['holdingRegisters', 'HR61'],
          ['registers', 'HR61'],
          ['registers', '61'],
          ['hr', '61'],
          ['hr61'],
        ]),
      ),
      humExterior: _parseSignedHoldingRegister(
        _read(unitRaw, fallbackRaw, const [
          ['humedadExterior'],
          ['humExterior'],
          ['rhOutside'],
          ['clima', 'humedadExterior'],
          ['clima', 'rhOutside'],
          ['vm138'],
          ['VM138'],
          ['vw138'],
          ['VW138'],
          ['holdingRegisters', '69'],
          ['holdingRegisters', 'HR69'],
          ['registers', 'HR69'],
          ['registers', '69'],
          ['hr', '69'],
          ['hr69'],
        ]),
      ),
      nh3: _parseNum(
        _read(unitRaw, fallbackRaw, const [
          ['nh3'],
          ['ambiente', 'nh3'],
          ['clima', 'nh3'],
          ['sensors', 'nh3'],
        ]),
      ),
      presionDiferencial: _parseSignedHoldingRegister(
        _read(unitRaw, fallbackRaw, const [
          ['presionDiferencial'],
          ['pressureDiff'],
          ['clima', 'presionDiferencial'],
          ['clima', 'pressureDiff'],
          ['vm154'],
          ['VM154'],
          ['vw154'],
          ['VW154'],
          ['holdingRegisters', '77'],
          ['holdingRegisters', 'HR77'],
          ['registers', 'HR77'],
          ['registers', '77'],
          ['hr', '77'],
          ['hr77'],
        ]),
      ),
      tensionSalidaVentiladores: _parseNum(
        _read(unitRaw, fallbackRaw, const [
          ['tensionSalidaVentiladores'],
          ['outputPower'],
          ['ventilacion', 'tensionSalidaVentiladores'],
          ['ventilacion', 'outputPower'],
          ['vm170'],
          ['VM170'],
          ['vw170'],
          ['VW170'],
          ['holdingRegisters', '85'],
          ['holdingRegisters', 'HR85'],
          ['registers', 'HR85'],
          ['registers', '85'],
          ['hr', '85'],
          ['hr85'],
        ]),
      ),
      fanQ5: _parseBool(
        _read(unitRaw, fallbackRaw, const [
          ['fanQ5'],
          ['fan1'],
          ['fans', 'fan1'],
          ['estados', 'fan1'],
          ['vb1'],
          ['VB1'],
          ['nq1'],
          ['NQ1'],
        ]),
      ),
      fanQ6: _parseBool(
        _read(unitRaw, fallbackRaw, const [
          ['fanQ6'],
          ['fan2'],
          ['fans', 'fan2'],
          ['estados', 'fan2'],
          ['vb2'],
          ['VB2'],
          ['nq2'],
          ['NQ2'],
        ]),
      ),
      fanQ7: _parseBool(
        _read(unitRaw, fallbackRaw, const [
          ['fanQ7'],
          ['fan3'],
          ['fans', 'fan3'],
          ['estados', 'fan3'],
          ['vb3'],
          ['VB3'],
          ['nq3'],
          ['NQ3'],
        ]),
      ),
      fanQ8: _parseBool(
        _read(unitRaw, fallbackRaw, const [
          ['fanQ8'],
          ['fan4'],
          ['fans', 'fan4'],
          ['estados', 'fan4'],
          ['vb4'],
          ['VB4'],
          ['nq4'],
          ['NQ4'],
        ]),
      ),
      fanQ9: _parseBool(
        _read(unitRaw, fallbackRaw, const [
          ['fanQ9'],
          ['fan5'],
          ['fans', 'fan5'],
          ['estados', 'fan5'],
          ['vb5'],
          ['VB5'],
          ['nq5'],
          ['NQ5'],
        ]),
      ),
      fanQ10: _parseBool(
        _read(unitRaw, fallbackRaw, const [
          ['fanQ10'],
          ['fan6'],
          ['fans', 'fan6'],
          ['estados', 'fan6'],
          ['vb6'],
          ['VB6'],
          ['nq6'],
          ['NQ6'],
        ]),
      ),
      bombaHumidificador: _parseBool(
        _read(unitRaw, fallbackRaw, const [
          ['bombaHumidificador'],
          ['bombaHumidificadora'],
          ['humidificacion', 'bombaHumidificador'],
          ['humidificacion', 'bombaHumidificadora'],
          ['nq11'],
          ['NQ11'],
        ]),
      ),
      resistencia1: _parseBool(
        _read(unitRaw, fallbackRaw, const [
          ['resistencia1'],
          ['calefactor1'],
          ['calefaccion', 'resistencia1'],
          ['calefaccion', 'calefactor1'],
          ['nq12'],
          ['NQ12'],
        ]),
      ),
      resistencia2: _parseBool(
        _read(unitRaw, fallbackRaw, const [
          ['resistencia2'],
          ['calefactor2'],
          ['calefaccion', 'resistencia2'],
          ['calefaccion', 'calefactor2'],
          ['nq13'],
          ['NQ13'],
        ]),
      ),
      alarmaGeneral: _parseBool(
        _read(unitRaw, fallbackRaw, const [
          ['alarmaGeneral'],
          ['alarmOutputQ12'],
          ['estados', 'alarmaGeneral'],
          ['estados', 'alarmOutputQ12'],
          ['vb8'],
          ['VB8'],
          ['nq8'],
          ['NQ8'],
        ]),
      ),
      fallaRed: _parseBool(
        _read(unitRaw, fallbackRaw, const [
          ['fallaRed'],
          ['alarmas', 'fallaRed'],
        ]),
      ),
      nivelAguaAlarma: _parseBool(
        _read(unitRaw, fallbackRaw, const [
          ['nivelAguaAlarma'],
          ['nivelAgua'],
          ['humidificacion', 'nivelAguaAlarma'],
          ['humidificacion', 'nivelAgua'],
          ['nq14'],
          ['NQ14'],
        ]),
      ),
      fallaTermicaBomba: _parseBool(
        _read(unitRaw, fallbackRaw, const [
          ['fallaTermicaBomba'],
          ['fallaTermicaBombaHumidificador'],
          ['alarmas', 'fallaTermicaBomba'],
          ['humidificacion', 'fallaTermicaBomba'],
          ['humidificacion', 'fallaTermicaBombaHumidificador'],
          ['nq15'],
          ['NQ15'],
        ]),
      ),
      eventosSinAgua: _parseInt(
        _read(unitRaw, fallbackRaw, const [
          ['eventosSinAgua'],
          ['humidificacion', 'eventosSinAgua'],
        ]),
      ),
      horasMunter: _parseInt(
        _read(unitRaw, fallbackRaw, const [
          ['horasMunter'],
          ['horimetros', 'horasMunter'],
        ]),
      ),
      horasFiltroF9: _parseInt(
        _read(unitRaw, fallbackRaw, const [
          ['horasFiltroF9'],
          ['horimetros', 'horasFiltroF9'],
        ]),
      ),
      horasFiltroG4: _parseInt(
        _read(unitRaw, fallbackRaw, const [
          ['horasFiltroG4'],
          ['horimetros', 'horasFiltroG4'],
        ]),
      ),
      horasPolifosfato: _parseInt(
        _read(unitRaw, fallbackRaw, const [
          ['horasPolifosfato'],
          ['horimetros', 'horasPolifosfato'],
        ]),
      ),
      salaAbierta: _parseBool(
        _read(unitRaw, fallbackRaw, const [
          ['salaAbierta'],
          ['doorRoom'],
          ['estados', 'aperturaSala'],
          ['estados', 'doorRoom'],
          ['aperturaSala'],
          ['vb9'],
          ['VB9'],
          ['nq9'],
          ['NQ9'],
        ]),
      ),
      aperturasSala: _parseInt(
        _read(unitRaw, fallbackRaw, const [
          ['aperturasSala'],
          ['estados', 'aperturasSala'],
        ]),
      ),
      munterAbierto: _parseBool(
        _read(unitRaw, fallbackRaw, const [
          ['munterAbierto'],
          ['doorMunter'],
          ['estados', 'aperturaMunter'],
          ['estados', 'doorMunter'],
          ['aperturaMunter'],
          ['vb10'],
          ['VB10'],
          ['nq10'],
          ['NQ10'],
        ]),
      ),
      aperturasMunter: _parseInt(
        _read(unitRaw, fallbackRaw, const [
          ['aperturasMunter'],
          ['estados', 'aperturasMunter'],
        ]),
      ),
      cantidadApagadas: _parseInt(
        _read(unitRaw, fallbackRaw, const [
          ['cantidadApagadas'],
          ['funcionamiento', 'cantidadApagadas'],
        ]),
      ),
      estadoEquipo: _parseString(
        _read(unitRaw, fallbackRaw, const [
          ['estadoPLC'],
          ['estadoEquipo'],
          ['funcionamiento', 'estadoEquipo'],
        ]),
      ),
    );
  }

  PlcUnitDiagnostics? _parseUnitDiagnostics({
    required bool backendOnline,
    required PlcRawPayload? unitRaw,
    required PlcRawPayload? fallbackRaw,
  }) {
    final bool? configured = _parseBool(
      _read(unitRaw, fallbackRaw, const [
        ['configured'],
      ]),
    );
    final bool? plcReachable = _parseBool(
      _read(unitRaw, fallbackRaw, const [
        ['plcReachable'],
      ]),
    );
    final bool? plcRunning = _parseBool(
      _read(unitRaw, fallbackRaw, const [
        ['plcRunning'],
      ]),
    );
    final bool? dataFresh = _parseBool(
      _read(unitRaw, fallbackRaw, const [
        ['dataFresh'],
      ]),
    );
    final bool? plcOnline = _parseBool(
      _read(unitRaw, fallbackRaw, const [
        ['plcOnline'],
      ]),
    );
    final DateTime? lastUpdatedAt = _parseDateTime(
      _read(unitRaw, fallbackRaw, const [
        ['lastUpdatedAt'],
      ]),
    );
    final String? lastError = _parseString(
      _read(unitRaw, fallbackRaw, const [
        ['lastError'],
      ]),
    );
    final String? stateCode = _parseString(
      _read(unitRaw, fallbackRaw, const [
        ['diagnostics', 'stateCode'],
      ]),
    );
    final String? stateLabel = _parseString(
      _read(unitRaw, fallbackRaw, const [
        ['diagnostics', 'stateLabel'],
      ]),
    );
    final String? stateReason = _parseString(
      _read(unitRaw, fallbackRaw, const [
        ['diagnostics', 'stateReason'],
      ]),
    );

    if (stateCode != null || stateLabel != null || stateReason != null) {
      return PlcUnitDiagnostics(
        backendAlive: _parseBool(
              _read(unitRaw, fallbackRaw, const [
                ['diagnostics', 'backendAlive'],
              ]),
            ) ??
            backendOnline,
        plcConnectOk: _parseBool(
              _read(unitRaw, fallbackRaw, const [
                ['diagnostics', 'plcConnectOk'],
              ]),
            ) ??
            (plcReachable ?? false),
        validKeySignals: _parseInt(
          _read(unitRaw, fallbackRaw, const [
            ['diagnostics', 'validKeySignals'],
          ]),
        ),
        invalidKeySignals: _parseInt(
          _read(unitRaw, fallbackRaw, const [
            ['diagnostics', 'invalidKeySignals'],
          ]),
        ),
        totalKeySignals: _parseInt(
          _read(unitRaw, fallbackRaw, const [
            ['diagnostics', 'totalKeySignals'],
          ]),
        ),
        lastPollAt: _parseDateTime(
          _read(unitRaw, fallbackRaw, const [
            ['diagnostics', 'lastPollAt'],
          ]),
        ),
        lastSuccessfulReadAt: _parseDateTime(
          _read(unitRaw, fallbackRaw, const [
            ['diagnostics', 'lastSuccessfulReadAt'],
          ]),
        ),
        stateCode: stateCode ?? PlcUnitDiagnostics.plcUnreachable,
        stateLabel: _normalizeDiagnosticsStateLabel(
          stateLabel ?? _legacyStateLabel(unitRaw, fallbackRaw),
        ),
        stateReason: stateReason ?? (lastError ?? 'Sin detalle.'),
      );
    }

    if (configured == false) {
      return const PlcUnitDiagnostics(
        backendAlive: true,
        plcConnectOk: false,
        validKeySignals: null,
        invalidKeySignals: null,
        totalKeySignals: null,
        lastPollAt: null,
        lastSuccessfulReadAt: null,
        stateCode: PlcUnitDiagnostics.plcNotConfigured,
        stateLabel: 'PLC no configurado',
        stateReason: 'Unidad sin configuracion PLC.',
      );
    }
    if (plcReachable == false) {
      return PlcUnitDiagnostics(
        backendAlive: backendOnline,
        plcConnectOk: false,
        validKeySignals: null,
        invalidKeySignals: null,
        totalKeySignals: null,
        lastPollAt: lastUpdatedAt,
        lastSuccessfulReadAt: null,
        stateCode: PlcUnitDiagnostics.plcUnreachable,
        stateLabel: 'PLC fuera de alcance',
        stateReason: 'Posible problema de energia o red.',
      );
    }
    if (plcReachable == true) {
      return PlcUnitDiagnostics(
        backendAlive: backendOnline,
        plcConnectOk: true,
        validKeySignals: null,
        invalidKeySignals: null,
        totalKeySignals: null,
        lastPollAt: lastUpdatedAt,
        lastSuccessfulReadAt:
            (plcOnline == true || dataFresh == true || plcRunning == true)
            ? lastUpdatedAt
            : null,
        stateCode: (plcOnline == true || dataFresh == true || plcRunning == true)
            ? PlcUnitDiagnostics.plcReachableStateUnknown
            : PlcUnitDiagnostics.plcReachableNoValidData,
        stateLabel: (plcOnline == true || dataFresh == true || plcRunning == true)
            ? 'Estado PLC desconocido'
            : 'PLC alcanzable sin datos válidos',
        stateReason: (plcOnline == true || dataFresh == true || plcRunning == true)
            ? 'Sin señal confiable de RUN/STOP.'
            : 'Probable STOP.',
      );
    }
    return null;
  }

  String _legacyStateLabel(
    PlcRawPayload? unitRaw,
    PlcRawPayload? fallbackRaw,
  ) {
    final String? legacyState = _parseString(
      _read(unitRaw, fallbackRaw, const [
        ['estadoPLC'],
        ['estadoEquipo'],
      ]),
    );
    return switch (legacyState) {
      'NO_CONFIGURADO' || 'PLC no configurado' => 'PLC no configurado',
      'OFFLINE' || 'PLC offline' => 'PLC fuera de alcance',
      'STOP' || 'PLC en STOP' => 'PLC alcanzable sin datos válidos',
      'PLC Stop' => 'PLC Stop',
      'Estado PLC desconocido' => 'Estado PLC desconocido',
      'RUN' || 'PLC en RUN' || 'PLC operativo' || 'PLC online' => 'PLC online',
      _ => 'Sin datos',
    };
  }

  String _normalizeDiagnosticsStateLabel(String label) {
    return switch (label) {
      'PLC operativo' => 'PLC online',
      'PLC_HEALTHY' => 'PLC online',
      _ => label,
    };
  }

  Object? _read(
    PlcRawPayload? unitRaw,
    PlcRawPayload? fallbackRaw,
    List<List<String>> paths,
  ) {
    final Object? unitValue = unitRaw?.firstValue(paths);
    if (unitValue != null) {
      return unitValue;
    }
    return fallbackRaw?.firstValue(paths);
  }

  DateTime? _parseDateTime(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }

  double? _parseSignedHoldingRegister(Object? value) {
    final int? parsed = _parseInt(value);
    if (parsed == null) {
      return null;
    }
    return toSigned16(parsed).toDouble();
  }

  double? _parseNum(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.replaceAll(',', '.'));
    }
    return null;
  }

  int? _parseInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  bool? _parseBool(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final String normalized = value.trim().toLowerCase();
      if (['true', '1', 'on', 'si', 'sí', 'active'].contains(normalized)) {
        return true;
      }
      if (['false', '0', 'off', 'no', 'inactive'].contains(normalized)) {
        return false;
      }
    }
    return null;
  }

  String? _parseString(Object? value) {
    final String? text = value?.toString();
    if (text == null) {
      return null;
    }
    final String trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _sanitizeSegment(String? raw) {
    if (raw == null) {
      return null;
    }
    final String normalized = raw.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '-',
    );
    final String compact = normalized.replaceAll(RegExp(r'-+'), '-');
    final String cleaned = compact.replaceAll(RegExp(r'^-+|-+$'), '');
    return cleaned.isEmpty ? null : cleaned;
  }
}

int toSigned16(int value) {
  return value > 32767 ? value - 65536 : value;
}

class LiveSnapshotResult {
  const LiveSnapshotResult({
    required this.snapshot,
    required this.rawPayload,
    required this.message,
    required this.source,
    required this.endpoint,
    required this.statusCode,
    required this.receivedAt,
  });

  const LiveSnapshotResult.success({
    required DashboardSnapshot this.snapshot,
    required Map<String, dynamic> this.rawPayload,
    required String this.endpoint,
    required int this.statusCode,
    required this.receivedAt,
  }) : message = null,
       source = 'success';

  const LiveSnapshotResult.error({
    required String this.message,
    required this.source,
    this.endpoint,
    this.statusCode,
  }) : snapshot = null,
       rawPayload = null,
       receivedAt = null;

  final DashboardSnapshot? snapshot;
  final Map<String, dynamic>? rawPayload;
  final String? message;
  final String source;
  final String? endpoint;
  final int? statusCode;
  final DateTime? receivedAt;

  bool get isSuccess => snapshot != null;

  bool get isTimeout => source == 'timeout';

  bool get isBackendError => source == 'http_status';

  bool get isNetworkError =>
      source == 'client_exception' || source == 'request_failed';

  String get statusLabel {
    if (isSuccess) {
      return snapshot!.backendOnline
          ? 'Snapshot recibido correctamente'
          : 'Backend offline';
    }

    switch (source) {
      case 'timeout':
        return 'Timeout leyendo backend';
      case 'http_status':
        return 'Backend respondio con error';
      case 'invalid_json':
      case 'invalid_payload':
      case 'empty_body':
        return 'Respuesta invalida del backend';
      case 'client_exception':
      case 'request_failed':
        return 'No se pudo conectar con el backend';
      case 'config':
        return 'Configuracion invalida del backend';
      default:
        return 'Error leyendo backend';
    }
  }
}
