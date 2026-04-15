import 'plc_unit_diagnostics.dart';

class MuntersModel {
  const MuntersModel({
    required this.name,
    this.historyClientId,
    this.historyPlcId,
    this.diagnostics,
    this.backendOnline,
    this.configured,
    this.plcReachable,
    this.plcRunning,
    this.dataFresh,
    this.plcOnline,
    this.plcLatencyMs,
    this.backendStartedAt,
    this.lastUpdatedAt,
    this.previousLastUpdatedAt,
    this.updateDeltaSeconds,
    this.lastHeartbeatValue,
    this.lastHeartbeatChangeAt,
    this.lastError,
    required this.tempInterior,
    required this.humInterior,
    required this.tempExterior,
    required this.humExterior,
    this.nh3,
    this.presionDiferencial,
    this.tensionSalidaVentiladores,
    required this.fanQ5,
    required this.fanQ6,
    required this.fanQ7,
    required this.fanQ8,
    required this.fanQ9,
    required this.fanQ10,
    required this.bombaHumidificador,
    required this.resistencia1,
    required this.resistencia2,
    required this.alarmaGeneral,
    required this.fallaRed,
    required this.nivelAguaAlarma,
    required this.fallaTermicaBomba,
    required this.eventosSinAgua,
    required this.horasMunter,
    required this.horasFiltroF9,
    required this.horasFiltroG4,
    required this.horasPolifosfato,
    required this.salaAbierta,
    required this.aperturasSala,
    required this.munterAbierto,
    required this.aperturasMunter,
    required this.cantidadApagadas,
    required this.estadoEquipo,
  });

  const MuntersModel.placeholder({required this.name})
    : historyClientId = null,
      historyPlcId = null,
      diagnostics = null,
      backendOnline = null,
      configured = false,
      plcReachable = null,
      plcRunning = null,
      dataFresh = null,
      plcOnline = null,
      plcLatencyMs = null,
      backendStartedAt = null,
      lastUpdatedAt = null,
      previousLastUpdatedAt = null,
      updateDeltaSeconds = null,
      lastHeartbeatValue = null,
      lastHeartbeatChangeAt = null,
      lastError = null,
      tempInterior = null,
      humInterior = null,
      tempExterior = null,
      humExterior = null,
      nh3 = null,
      presionDiferencial = null,
      tensionSalidaVentiladores = null,
      fanQ5 = null,
      fanQ6 = null,
      fanQ7 = null,
      fanQ8 = null,
      fanQ9 = null,
      fanQ10 = null,
      bombaHumidificador = null,
      resistencia1 = null,
      resistencia2 = null,
      alarmaGeneral = null,
      fallaRed = null,
      nivelAguaAlarma = null,
      fallaTermicaBomba = null,
      eventosSinAgua = null,
      horasMunter = null,
      horasFiltroF9 = null,
      horasFiltroG4 = null,
      horasPolifosfato = null,
      salaAbierta = null,
      aperturasSala = null,
      munterAbierto = null,
      aperturasMunter = null,
      cantidadApagadas = null,
      estadoEquipo = null;

  final String name;
  final String? historyClientId;
  final String? historyPlcId;
  final PlcUnitDiagnostics? diagnostics;
  final bool? backendOnline;
  final bool? configured;
  final bool? plcReachable;
  final bool? plcRunning;
  final bool? dataFresh;
  final bool? plcOnline;
  final int? plcLatencyMs;
  final DateTime? backendStartedAt;
  final DateTime? lastUpdatedAt;
  final DateTime? previousLastUpdatedAt;
  final int? updateDeltaSeconds;
  final Object? lastHeartbeatValue;
  final DateTime? lastHeartbeatChangeAt;
  final String? lastError;
  final double? tempInterior;
  final double? humInterior;
  final double? tempExterior;
  final double? humExterior;
  final double? nh3;
  final double? presionDiferencial;
  final double? tensionSalidaVentiladores;
  final bool? fanQ5;
  final bool? fanQ6;
  final bool? fanQ7;
  final bool? fanQ8;
  final bool? fanQ9;
  final bool? fanQ10;
  final bool? bombaHumidificador;
  final bool? resistencia1;
  final bool? resistencia2;
  final bool? alarmaGeneral;
  final bool? fallaRed;
  final bool? nivelAguaAlarma;
  final bool? fallaTermicaBomba;
  final int? eventosSinAgua;
  final int? horasMunter;
  final int? horasFiltroF9;
  final int? horasFiltroG4;
  final int? horasPolifosfato;
  final bool? salaAbierta;
  final int? aperturasSala;
  final bool? munterAbierto;
  final int? aperturasMunter;
  final int? cantidadApagadas;
  final String? estadoEquipo;

  int? get contadorSinAgua => eventosSinAgua;
  int? get contadorAperturasSala => aperturasSala;
  int? get contadorAperturasMunter => aperturasMunter;
  int? get cantidadApagadasMunter => cantidadApagadas;
  String? get estadoMunter => estadoEquipo;
}
