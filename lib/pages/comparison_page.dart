import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/dashboard_range_settings.dart';
import '../models/magnifier_settings.dart';
import '../models/munters_model.dart';
import '../models/plc_unit_diagnostics.dart';
import '../widgets/status_indicator.dart';
import '../widgets/temperature_history_mini_charts_card.dart';

class ComparisonPage extends StatefulWidget {
  const ComparisonPage({
    super.key,
    required this.munters1,
    required this.munters2,
    this.tenantId,
    this.siteId,
    required this.showMunters1,
    required this.showMunters2,
    required this.snapshotStale,
    required this.showSnapshotPulse,
    required this.rangeSettings,
    required this.magnifierSettings,
  });

  final MuntersModel munters1;
  final MuntersModel munters2;
  final String? tenantId;
  final String? siteId;
  final bool showMunters1;
  final bool showMunters2;
  final bool snapshotStale;
  final bool showSnapshotPulse;
  final DashboardRangeSettings rangeSettings;
  final MagnifierSettings magnifierSettings;

  @override
  State<ComparisonPage> createState() => _ComparisonPageState();
}

class _ComparisonPageState extends State<ComparisonPage> {
  static const Duration _technicalDataAutoCollapseDelay = Duration(minutes: 5);
  static const Duration _sectionsAutoCollapseDelay = Duration(minutes: 10);
  static const String _sectionFuncionamiento = 'Funcionamiento';
  static const String _sectionAmbiente = 'Ambiente';
  static const String _sectionVentilacion = 'Ventilacion';
  static const String _sectionHumidificacion = 'Humidificacion';
  static const String _sectionAperturas = 'Aperturas';
  static const String _sectionCalefaccion = 'Calefaccion';
  static const String _sectionAlarmas = 'Alarmas';

  Timer? _technicalDataAutoCollapseTimer;
  Timer? _sectionsAutoCollapseTimer;
  bool _technicalDataExpanded = false;
  bool _munters1Collapsed = false;
  bool _munters2Collapsed = false;
  bool _allSectionsExpanded = false;
  int _sectionsCollapseGeneration = 0;
  int _sectionsExpandGeneration = 0;
  final Map<String, int> _sectionExpandRequests = <String, int>{};
  final Map<String, GlobalKey> _sectionKeys = <String, GlobalKey>{
    _sectionFuncionamiento: GlobalKey(),
    _sectionAmbiente: GlobalKey(),
    _sectionVentilacion: GlobalKey(),
    _sectionHumidificacion: GlobalKey(),
    _sectionAperturas: GlobalKey(),
    _sectionCalefaccion: GlobalKey(),
    _sectionAlarmas: GlobalKey(),
  };

  @override
  void dispose() {
    _technicalDataAutoCollapseTimer?.cancel();
    _sectionsAutoCollapseTimer?.cancel();
    super.dispose();
  }

  void _setTechnicalDataExpanded(bool expanded) {
    _technicalDataAutoCollapseTimer?.cancel();
    if (expanded) {
      _technicalDataAutoCollapseTimer = Timer(
        _technicalDataAutoCollapseDelay,
        () {
          if (!mounted) {
            return;
          }
          setState(() {
            _technicalDataExpanded = false;
          });
        },
      );
    }

    setState(() {
      _technicalDataExpanded = expanded;
    });
  }

  void _handleSectionExpanded() {
    _sectionsAutoCollapseTimer?.cancel();
    _sectionsAutoCollapseTimer = Timer(_sectionsAutoCollapseDelay, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _allSectionsExpanded = false;
        _sectionsCollapseGeneration += 1;
      });
    });
  }

  void _expandAllSections() {
    _sectionsAutoCollapseTimer?.cancel();
    setState(() {
      _allSectionsExpanded = true;
      _sectionsExpandGeneration += 1;
    });
    _handleSectionExpanded();
  }

  void _collapseAllSections() {
    _sectionsAutoCollapseTimer?.cancel();
    setState(() {
      _allSectionsExpanded = false;
      _sectionsCollapseGeneration += 1;
    });
  }

  void _focusSection(String sectionId) {
    setState(() {
      _sectionExpandRequests[sectionId] =
          (_sectionExpandRequests[sectionId] ?? 0) + 1;
    });
    _handleSectionExpanded();
    final GlobalKey? targetKey = _sectionKeys[sectionId];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? targetContext = targetKey?.currentContext;
      if (targetContext == null) {
        return;
      }
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
        alignment: 0.06,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final MuntersModel munters1 = widget.showMunters1
        ? widget.munters1
        : const MuntersModel.placeholder(name: 'Munters 1');
    final MuntersModel munters2 = widget.showMunters2
        ? widget.munters2
        : const MuntersModel.placeholder(name: 'Munters 2');
    final DashboardRangeSettings rangeSettings = widget.rangeSettings;
    final bool munters1DataBlocked = _shouldBlockOperationalData(munters1);
    final bool munters2DataBlocked = _shouldBlockOperationalData(munters2);
    final _ModuleStatus functioningStatus = _resolveFunctioningModuleStatus(
      <MuntersModel>[munters1, munters2],
    );
    final _WitnessDotVisual m1WitnessVisual = _resolvePlcWitnessVisual(<MuntersModel>[munters1]);
    final _WitnessDotVisual m2WitnessVisual = _resolvePlcWitnessVisual(<MuntersModel>[munters2]);
    final bool hasAlarm = _hasAlarm(munters1) || _hasAlarm(munters2);
    final _ModuleStatus aperturasStatus = _resolveAperturasStatus(
      munters1,
      munters2,
    );
    final _ModuleStatus environmentStatus = _resolveEnvironmentStatus(
      munters1: munters1,
      munters2: munters2,
      rangeSettings: rangeSettings,
    );
    final _ModuleStatus ventilationStatus = _resolveVentilationStatus(
      munters1,
      munters2,
    );
    final _ModuleStatus humidificationStatus = _resolveHumidificationStatus(
      munters1,
      munters2,
      rangeSettings,
    );
    final _ModuleStatus calefaccionStatus = _resolveCalefaccionStatus(
      munters1,
      munters2,
      rangeSettings,
    );
    final _ModuleStatus alarmasStatus = _resolveAlarmasStatus(
      functioningStatus: functioningStatus,
      environmentStatus: environmentStatus,
      ventilationStatus: ventilationStatus,
      humidificationStatus: humidificationStatus,
      aperturasStatus: aperturasStatus,
      calefaccionStatus: calefaccionStatus,
      hasAlarmOutput: hasAlarm,
    );
    final bool hasAnyModuleAlarm = _isModuleStatusAlarm(alarmasStatus);

    // Per-PLC icon data
    Color funcIconColor(_ModuleStatus s) => switch (s.kind) {
      _ModuleStatusKind.alert || _ModuleStatusKind.error => const Color(0xFFEF4444),
      _ModuleStatusKind.ok => const Color(0xFF22C55E),
      _ => const Color(0xFF94A3B8),
    };
    final _ModuleStatus m1FuncStatus = _resolveFunctioningStatusForUnit(munters1);
    final _ModuleStatus m2FuncStatus = _resolveFunctioningStatusForUnit(munters2);
    final List<_PlcModuleIconData> funcionamientoPlcIconData = <_PlcModuleIconData>[
      _PlcModuleIconData(
        icon: Icons.power_settings_new,
        iconColor: funcIconColor(m1FuncStatus),
        status: m1FuncStatus,
        witnessVisual: m1WitnessVisual,
        showPulseDot: widget.showSnapshotPulse,
        pulseDotBackendAlive: !widget.snapshotStale,
        pulseDotColor: _isPlcStopState(munters1) ? const Color(0xFFF59E0B) : const Color(0xFF22C55E),
      ),
      _PlcModuleIconData(
        icon: Icons.power_settings_new,
        iconColor: funcIconColor(m2FuncStatus),
        status: m2FuncStatus,
        witnessVisual: m2WitnessVisual,
        showPulseDot: widget.showSnapshotPulse,
        pulseDotBackendAlive: !widget.snapshotStale,
        pulseDotColor: _isPlcStopState(munters2) ? const Color(0xFFF59E0B) : const Color(0xFF22C55E),
      ),
    ];
    final List<_PlcModuleIconData> ambientePlcIconData = <_PlcModuleIconData>[
      _PlcModuleIconData(
        icon: Icons.thermostat,
        iconColor: _resolveEnvironmentIconColorForUnit(unit: munters1, rangeSettings: rangeSettings),
        status: _resolveEnvironmentStatusForUnit(unit: munters1, rangeSettings: rangeSettings),
        extraWidget: _EnvironmentHeaderHumidityIcon(
          visual: _resolveEnvironmentHumidityVisualForUnit(unit: munters1, rangeSettings: rangeSettings),
        ),
      ),
      _PlcModuleIconData(
        icon: Icons.thermostat,
        iconColor: _resolveEnvironmentIconColorForUnit(unit: munters2, rangeSettings: rangeSettings),
        status: _resolveEnvironmentStatusForUnit(unit: munters2, rangeSettings: rangeSettings),
        extraWidget: _EnvironmentHeaderHumidityIcon(
          visual: _resolveEnvironmentHumidityVisualForUnit(unit: munters2, rangeSettings: rangeSettings),
        ),
      ),
    ];
    final List<_PlcModuleIconData> ventilacionPlcIconData = <_PlcModuleIconData>[
      _PlcModuleIconData(
        icon: Icons.cyclone_rounded,
        iconColor: _resolveVentilationIconColorForUnit(munters1),
        status: _resolveVentilationStatusForUnit(munters1),
        spinning: _isVentilationFullyRunning(munters1),
      ),
      _PlcModuleIconData(
        icon: Icons.cyclone_rounded,
        iconColor: _resolveVentilationIconColorForUnit(munters2),
        status: _resolveVentilationStatusForUnit(munters2),
        spinning: _isVentilationFullyRunning(munters2),
      ),
    ];
    final List<_PlcModuleIconData> humidificacionPlcIconData = <_PlcModuleIconData>[
      _PlcModuleIconData(
        icon: Icons.water_drop,
        iconColor: !munters1DataBlocked && munters1.bombaHumidificador == true ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
        status: _resolveHumidificationStatusForUnit(munters1, rangeSettings),
      ),
      _PlcModuleIconData(
        icon: Icons.water_drop,
        iconColor: !munters2DataBlocked && munters2.bombaHumidificador == true ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
        status: _resolveHumidificationStatusForUnit(munters2, rangeSettings),
      ),
    ];
    final List<_PlcModuleIconData> aperturasPlcIconData = <_PlcModuleIconData>[
      _PlcModuleIconData(
        icon: _hasDoorAlarm(munters1) ? Icons.meeting_room_outlined : Icons.door_front_door_outlined,
        iconColor: _hasDoorAlarm(munters1) ? const Color(0xFFFACC15) : const Color(0xFF94A3B8),
        status: _resolveAperturasStatusForUnit(munters1),
      ),
      _PlcModuleIconData(
        icon: _hasDoorAlarm(munters2) ? Icons.meeting_room_outlined : Icons.door_front_door_outlined,
        iconColor: _hasDoorAlarm(munters2) ? const Color(0xFFFACC15) : const Color(0xFF94A3B8),
        status: _resolveAperturasStatusForUnit(munters2),
      ),
    ];
    final List<_PlcModuleIconData> calefaccionPlcIconData = <_PlcModuleIconData>[
      _PlcModuleIconData(
        icon: Icons.local_fire_department,
        iconColor: !munters1DataBlocked && (munters1.resistencia1 == true || munters1.resistencia2 == true) ? const Color(0xFFEF4444) : const Color(0xFF94A3B8),
        status: _resolveCalefaccionStatusForUnit(munters1, rangeSettings),
      ),
      _PlcModuleIconData(
        icon: Icons.local_fire_department,
        iconColor: !munters2DataBlocked && (munters2.resistencia1 == true || munters2.resistencia2 == true) ? const Color(0xFFEF4444) : const Color(0xFF94A3B8),
        status: _resolveCalefaccionStatusForUnit(munters2, rangeSettings),
      ),
    ];
    final _ModuleStatus m1AlarmasStatus = _resolveAlarmasStatusForUnit(munters1, rangeSettings);
    final _ModuleStatus m2AlarmasStatus = _resolveAlarmasStatusForUnit(munters2, rangeSettings);
    final List<_PlcModuleIconData> alarmasPlcIconData = <_PlcModuleIconData>[
      _PlcModuleIconData(
        icon: Icons.warning_amber_rounded,
        iconColor: _isModuleStatusAlarm(m1AlarmasStatus) ? const Color(0xFFFACC15) : const Color(0xFF94A3B8),
        status: m1AlarmasStatus,
      ),
      _PlcModuleIconData(
        icon: Icons.warning_amber_rounded,
        iconColor: _isModuleStatusAlarm(m2AlarmasStatus) ? const Color(0xFFFACC15) : const Color(0xFF94A3B8),
        status: m2AlarmasStatus,
      ),
    ];

    final Widget funcionamientoSection = _SectionTable(
      key: _sectionKeys[_sectionFuncionamiento],
      title: 'FUNCIONAMIENTO',
      plcIconData: funcionamientoPlcIconData,
      collapseGeneration: _sectionsCollapseGeneration,
      expandGeneration: _sectionsExpandGeneration,
      expandRequestGeneration: _sectionExpandRequests[_sectionFuncionamiento] ?? 0,
      onExpanded: _handleSectionExpanded,
      rows: [
        _ComparisonRow(
          label: 'Nombre',
          munters1: const _TextValue('Munters 1'),
          munters2: const _TextValue('Munters 2'),
        ),
        _ComparisonRow(
          label: 'Estado equipo',
          munters1: _EquipmentStateValue(
            diagnostics: widget.munters1.diagnostics,
            showSnapshotPulse: widget.showSnapshotPulse,
          ),
          munters2: _EquipmentStateValue(
            diagnostics: widget.munters2.diagnostics,
            showSnapshotPulse: widget.showSnapshotPulse,
          ),
        ),
        _ComparisonRow(
          label: 'Cantidad de apagadas',
          munters1: _TextValue(
            munters1DataBlocked ? '-' : _formatInt(widget.munters1.cantidadApagadas),
          ),
          munters2: _TextValue(
            munters2DataBlocked ? '-' : _formatInt(widget.munters2.cantidadApagadas),
          ),
        ),
        _ComparisonTechnicalDataGroup(
          expanded: _technicalDataExpanded,
          onToggle: () => _setTechnicalDataExpanded(!_technicalDataExpanded),
          rows: [
            _ComparisonRow(
              label: 'Latency',
              munters1: _TextValue(
                munters1DataBlocked
                    ? '-'
                    : _formatIntWithUnit(widget.munters1.plcLatencyMs, 'ms'),
                fontWeight: FontWeight.w400,
              ),
              munters2: _TextValue(
                munters2DataBlocked
                    ? '-'
                    : _formatIntWithUnit(widget.munters2.plcLatencyMs, 'ms'),
                fontWeight: FontWeight.w400,
              ),
            ),
            _ComparisonRow(
              label: 'Backend',
              munters1: _StateValue(
                active: munters1DataBlocked ? null : widget.munters1.backendOnline,
                activeLabel: 'on-line',
                inactiveLabel: 'off-line',
                activeColor: const Color(0xFF22C55E),
                inactiveColor: const Color(0xFFEF4444),
                fontWeight: FontWeight.w400,
              ),
              munters2: _StateValue(
                active: munters2DataBlocked ? null : widget.munters2.backendOnline,
                activeLabel: 'on-line',
                inactiveLabel: 'off-line',
                activeColor: const Color(0xFF22C55E),
                inactiveColor: const Color(0xFFEF4444),
                fontWeight: FontWeight.w400,
              ),
            ),
            _ComparisonRow(
              label: 'Uptime',
              munters1: _TextValue(
                munters1DataBlocked
                    ? '-'
                    : _formatUptime(widget.munters1.backendStartedAt),
                fontWeight: FontWeight.w400,
              ),
              munters2: _TextValue(
                munters2DataBlocked
                    ? '-'
                    : _formatUptime(widget.munters2.backendStartedAt),
                fontWeight: FontWeight.w400,
              ),
            ),
            _ComparisonRow(
              label: 'Last update -1',
              munters1: _TextValue(
                munters1DataBlocked
                    ? '-'
                    : _formatPreviousLastUpdated(widget.munters1.previousLastUpdatedAt),
                fontWeight: FontWeight.w400,
              ),
              munters2: _TextValue(
                munters2DataBlocked
                    ? '-'
                    : _formatPreviousLastUpdated(widget.munters2.previousLastUpdatedAt),
                fontWeight: FontWeight.w400,
              ),
            ),
            _ComparisonRow(
              label: 'Last update',
              munters1: _TextValue(
                munters1DataBlocked
                    ? '-'
                    : _formatLastUpdated(
                        widget.munters1.lastUpdatedAt,
                        widget.munters1.previousLastUpdatedAt,
                      ),
                fontWeight: FontWeight.w400,
              ),
              munters2: _TextValue(
                munters2DataBlocked
                    ? '-'
                    : _formatLastUpdated(
                        widget.munters2.lastUpdatedAt,
                        widget.munters2.previousLastUpdatedAt,
                      ),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ],
    );
    final Widget ambienteSection = _SectionTable(
      key: _sectionKeys[_sectionAmbiente],
      title: 'AMBIENTE',
      plcIconData: ambientePlcIconData,
      collapseGeneration: _sectionsCollapseGeneration,
      expandGeneration: _sectionsExpandGeneration,
      expandRequestGeneration: _sectionExpandRequests[_sectionAmbiente] ?? 0,
      onExpanded: _handleSectionExpanded,
      rows: [
        _ComparisonRow(
          label: 'Temp. interior',
          munters1: _TemperatureValue(
            value: munters1.tempInterior,
            min: rangeSettings.temperatureMin,
            max: rangeSettings.temperatureMax,
            blocked: munters1DataBlocked,
          ),
          munters2: _TemperatureValue(
            value: munters2.tempInterior,
            min: rangeSettings.temperatureMin,
            max: rangeSettings.temperatureMax,
            blocked: munters2DataBlocked,
          ),
        ),
        _ComparisonRow(
          label: '',
          alignToTop: true,
          munters1: _ComparisonHistoryValue(
            unitName: munters1.name,
            rangeSettings: rangeSettings,
            tenantId: widget.tenantId,
            siteId: widget.siteId,
            plcId: munters1.historyPlcId,
            blocked: munters1DataBlocked,
          ),
          munters2: _ComparisonHistoryValue(
            unitName: munters2.name,
            rangeSettings: rangeSettings,
            tenantId: widget.tenantId,
            siteId: widget.siteId,
            plcId: munters2.historyPlcId,
            blocked: munters2DataBlocked,
          ),
        ),
        _ComparisonRow(
          label: 'Humedad interior',
          munters1: _HumidityValue(
            value: munters1.humInterior,
            min: rangeSettings.humidityMin,
            max: rangeSettings.humidityMax,
            blocked: munters1DataBlocked,
          ),
          munters2: _HumidityValue(
            value: munters2.humInterior,
            min: rangeSettings.humidityMin,
            max: rangeSettings.humidityMax,
            blocked: munters2DataBlocked,
          ),
        ),
        _ComparisonRow(
          label: 'Temp. exterior',
          munters1: _TextValue(
            munters1DataBlocked ? '-' : _formatValueWithUnit(munters1.tempExterior, '°C'),
          ),
          munters2: _TextValue(
            munters2DataBlocked ? '-' : _formatValueWithUnit(munters2.tempExterior, '°C'),
          ),
        ),
        _ComparisonRow(
          label: 'Humedad exterior',
          munters1: _TextValue(
            munters1DataBlocked ? '-' : _formatValueWithUnit(munters1.humExterior, '%'),
          ),
          munters2: _TextValue(
            munters2DataBlocked ? '-' : _formatValueWithUnit(munters2.humExterior, '%'),
          ),
        ),
        _ComparisonRow(
          label: 'Presion diferencial',
          munters1: _TextValue(
            munters1DataBlocked
                ? '-'
                : _formatValueWithUnit(munters1.presionDiferencial, 'Pa'),
          ),
          munters2: _TextValue(
            munters2DataBlocked
                ? '-'
                : _formatValueWithUnit(munters2.presionDiferencial, 'Pa'),
          ),
        ),
        _ComparisonRow(
          label: 'NH3',
          munters1: _TextValue(
            munters1DataBlocked ? '-' : _formatValueWithUnit(munters1.nh3, 'ppm'),
          ),
          munters2: _TextValue(
            munters2DataBlocked ? '-' : _formatValueWithUnit(munters2.nh3, 'ppm'),
          ),
        ),
      ],
    );
    final Widget ventilacionSection = _SectionTable(
      key: _sectionKeys[_sectionVentilacion],
      title: 'VENTILACION',
      plcIconData: ventilacionPlcIconData,
      collapseGeneration: _sectionsCollapseGeneration,
      expandGeneration: _sectionsExpandGeneration,
      expandRequestGeneration: _sectionExpandRequests[_sectionVentilacion] ?? 0,
      onExpanded: _handleSectionExpanded,
      rows: [
        _ComparisonRow(
          label: 'Estado fans',
          munters1: _FanStateValue(
            fans: [
              ('Q5', munters1.fanQ5),
              ('Q6', munters1.fanQ6),
              ('Q7', munters1.fanQ7),
              ('Q8', munters1.fanQ8),
              ('Q9', munters1.fanQ9),
              ('Q10', munters1.fanQ10),
            ],
            blocked: munters1DataBlocked,
          ),
          munters2: _FanStateValue(
            fans: [
              ('Q5', munters2.fanQ5),
              ('Q6', munters2.fanQ6),
              ('Q7', munters2.fanQ7),
              ('Q8', munters2.fanQ8),
              ('Q9', munters2.fanQ9),
              ('Q10', munters2.fanQ10),
            ],
            blocked: munters2DataBlocked,
          ),
        ),
        _ComparisonRow(
          label: 'Potencia',
          munters1: _BarValue(
            value: munters1DataBlocked
                ? null
                : _normalizeVoltageToPercent(munters1.tensionSalidaVentiladores),
            blocked: munters1DataBlocked,
          ),
          munters2: _BarValue(
            value: munters2DataBlocked
                ? null
                : _normalizeVoltageToPercent(munters2.tensionSalidaVentiladores),
            blocked: munters2DataBlocked,
          ),
        ),
      ],
    );
    final Widget humidificacionSection = _SectionTable(
      key: _sectionKeys[_sectionHumidificacion],
      title: 'HUMIDIFICACION',
      plcIconData: humidificacionPlcIconData,
      collapseGeneration: _sectionsCollapseGeneration,
      expandGeneration: _sectionsExpandGeneration,
      expandRequestGeneration: _sectionExpandRequests[_sectionHumidificacion] ?? 0,
      onExpanded: _handleSectionExpanded,
      rows: [
        _ComparisonRow(
          label: 'Bomba humidificador',
          munters1: _StatusValue(
            active: munters1DataBlocked ? null : munters1.bombaHumidificador,
            activeLabel: 'On',
            inactiveLabel: 'Off',
            blocked: munters1DataBlocked,
          ),
          munters2: _StatusValue(
            active: munters2DataBlocked ? null : munters2.bombaHumidificador,
            activeLabel: 'On',
            inactiveLabel: 'Off',
            blocked: munters2DataBlocked,
          ),
        ),
        if (_hasHumidificationNotice(munters1, rangeSettings) ||
            _hasHumidificationNotice(munters2, rangeSettings))
          _ComparisonRow(
            label: '',
            alignToTop: true,
            munters1: _ModuleNoticeValue(
              messages: _humidificationNoticesForUnit(munters1, rangeSettings),
            ),
            munters2: _ModuleNoticeValue(
              messages: _humidificationNoticesForUnit(munters2, rangeSettings),
            ),
          ),
        _ComparisonRow(
          label: 'Nivel de agua',
          munters1: _WaterLevelValue(
            alarm: munters1DataBlocked ? null : munters1.nivelAguaAlarma,
            blocked: munters1DataBlocked,
          ),
          munters2: _WaterLevelValue(
            alarm: munters2DataBlocked ? null : munters2.nivelAguaAlarma,
            blocked: munters2DataBlocked,
          ),
        ),
        _ComparisonRow(
          label: 'Falla termica bomba',
          munters1: _WaterLevelValue(
            alarm: munters1DataBlocked ? null : munters1.fallaTermicaBomba,
            blocked: munters1DataBlocked,
          ),
          munters2: _WaterLevelValue(
            alarm: munters2DataBlocked ? null : munters2.fallaTermicaBomba,
            blocked: munters2DataBlocked,
          ),
        ),
        _ComparisonRow(
          label: 'Eventos sin agua',
          munters1: _TextValue(
            munters1DataBlocked ? '-' : _formatInt(munters1.eventosSinAgua),
          ),
          munters2: _TextValue(
            munters2DataBlocked ? '-' : _formatInt(munters2.eventosSinAgua),
          ),
        ),
      ],
    );
    final Widget estadosMecanicosSection = _SectionTable(
      key: _sectionKeys[_sectionAperturas],
      title: 'APERTURAS',
      plcIconData: aperturasPlcIconData,
      collapseGeneration: _sectionsCollapseGeneration,
      expandGeneration: _sectionsExpandGeneration,
      expandRequestGeneration: _sectionExpandRequests[_sectionAperturas] ?? 0,
      onExpanded: _handleSectionExpanded,
      rows: [
        _ComparisonRow(
          label: 'Puerta sala',
          munters1: _StateValue(
            active: munters1DataBlocked ? null : munters1.salaAbierta,
            activeLabel: 'Abierta',
            inactiveLabel: 'Cerrada',
            activeColor: const Color(0xFFEF4444),
            inactiveColor: const Color(0xFF22C55E),
            blocked: munters1DataBlocked,
          ),
          munters2: _StateValue(
            active: munters2DataBlocked ? null : munters2.salaAbierta,
            activeLabel: 'Abierta',
            inactiveLabel: 'Cerrada',
            activeColor: const Color(0xFFEF4444),
            inactiveColor: const Color(0xFF22C55E),
            blocked: munters2DataBlocked,
          ),
        ),
        _ComparisonRow(
          label: 'Aperturas sala',
          munters1: _TextValue(
            munters1DataBlocked ? '-' : _formatInt(munters1.aperturasSala),
          ),
          munters2: _TextValue(
            munters2DataBlocked ? '-' : _formatInt(munters2.aperturasSala),
          ),
        ),
        _ComparisonRow(
          label: 'Puerta Munter',
          munters1: _StateValue(
            active: munters1DataBlocked ? null : munters1.munterAbierto,
            activeLabel: 'Abierto',
            inactiveLabel: 'Cerrado',
            activeColor: const Color(0xFFEF4444),
            inactiveColor: const Color(0xFF22C55E),
            blocked: munters1DataBlocked,
          ),
          munters2: _StateValue(
            active: munters2DataBlocked ? null : munters2.munterAbierto,
            activeLabel: 'Abierto',
            inactiveLabel: 'Cerrado',
            activeColor: const Color(0xFFEF4444),
            inactiveColor: const Color(0xFF22C55E),
            blocked: munters2DataBlocked,
          ),
        ),
        _ComparisonRow(
          label: 'Aperturas Munter',
          munters1: _TextValue(
            munters1DataBlocked ? '-' : _formatInt(munters1.aperturasMunter),
          ),
          munters2: _TextValue(
            munters2DataBlocked ? '-' : _formatInt(munters2.aperturasMunter),
          ),
        ),
      ],
    );
    final Widget calefaccionSection = _SectionTable(
      key: _sectionKeys[_sectionCalefaccion],
      title: 'CALEFACCION',
      plcIconData: calefaccionPlcIconData,
      collapseGeneration: _sectionsCollapseGeneration,
      expandGeneration: _sectionsExpandGeneration,
      expandRequestGeneration: _sectionExpandRequests[_sectionCalefaccion] ?? 0,
      onExpanded: _handleSectionExpanded,
      rows: [
        if (_hasCalefaccionNotice(munters1, rangeSettings) ||
            _hasCalefaccionNotice(munters2, rangeSettings))
          _ComparisonRow(
            label: '',
            alignToTop: true,
            munters1: _ModuleNoticeValue(
              messages: _calefaccionNoticesForUnit(munters1, rangeSettings),
            ),
            munters2: _ModuleNoticeValue(
              messages: _calefaccionNoticesForUnit(munters2, rangeSettings),
            ),
          ),
        _ComparisonRow(
          label: 'Resistencia etapa 1',
          munters1: _StatusValue(
            active: munters1DataBlocked ? null : munters1.resistencia1,
            activeLabel: 'On',
            inactiveLabel: 'Off',
            blocked: munters1DataBlocked,
          ),
          munters2: _StatusValue(
            active: munters2DataBlocked ? null : munters2.resistencia1,
            activeLabel: 'On',
            inactiveLabel: 'Off',
            blocked: munters2DataBlocked,
          ),
        ),
        _ComparisonRow(
          label: 'Resistencia etapa 2',
          munters1: _StatusValue(
            active: munters1DataBlocked ? null : munters1.resistencia2,
            activeLabel: 'On',
            inactiveLabel: 'Off',
            blocked: munters1DataBlocked,
          ),
          munters2: _StatusValue(
            active: munters2DataBlocked ? null : munters2.resistencia2,
            activeLabel: 'On',
            inactiveLabel: 'Off',
            blocked: munters2DataBlocked,
          ),
        ),
      ],
    );
    final Widget alarmasSection = _SectionTable(
      key: _sectionKeys[_sectionAlarmas],
      title: 'ALARMAS',
      plcIconData: alarmasPlcIconData,
      collapseGeneration: _sectionsCollapseGeneration,
      expandGeneration: _sectionsExpandGeneration,
      expandRequestGeneration: _sectionExpandRequests[_sectionAlarmas] ?? 0,
      onExpanded: _handleSectionExpanded,
      rows: [
        _ComparisonRow(
          label: 'Eventos',
          alignToTop: true,
          munters1: _EventModulesValue(
            modules: _eventModulesForUnit(munters1, rangeSettings),
            blocked: munters1DataBlocked,
            onModuleTap: _focusSection,
          ),
          munters2: _EventModulesValue(
            modules: _eventModulesForUnit(munters2, rangeSettings),
            blocked: munters2DataBlocked,
            onModuleTap: _focusSection,
          ),
        ),
        _ComparisonRow(
          label: 'Salida alarmas (Q12)',
          munters1: _AlarmValue(
            active: munters1DataBlocked ? null : munters1.alarmaGeneral,
            blocked: munters1DataBlocked,
          ),
          munters2: _AlarmValue(
            active: munters2DataBlocked ? null : munters2.alarmaGeneral,
            blocked: munters2DataBlocked,
          ),
        ),
        _ComparisonRow(
          label: 'Falla red electrica',
          munters1: _AlarmValue(
            active: munters1DataBlocked ? null : munters1.fallaRed,
            blocked: munters1DataBlocked,
          ),
          munters2: _AlarmValue(
            active: munters2DataBlocked ? null : munters2.fallaRed,
            blocked: munters2DataBlocked,
          ),
        ),
        _ComparisonRow(
          label: 'Puertas abiertas',
          munters1: _AlarmValue(
            active: munters1DataBlocked ? null : _hasDoorAlarm(munters1),
            blocked: munters1DataBlocked,
          ),
          munters2: _AlarmValue(
            active: munters2DataBlocked ? null : _hasDoorAlarm(munters2),
            blocked: munters2DataBlocked,
          ),
        ),
      ],
    );
    final List<Widget> orderedSections = hasAnyModuleAlarm
        ? <Widget>[
            alarmasSection,
            funcionamientoSection,
            ambienteSection,
            ventilacionSection,
            humidificacionSection,
            estadosMecanicosSection,
            calefaccionSection,
          ]
        : <Widget>[
            funcionamientoSection,
            ambienteSection,
            ventilacionSection,
            humidificacionSection,
            estadosMecanicosSection,
            calefaccionSection,
            alarmasSection,
          ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TableHeader(
                  showMunters1: widget.showMunters1,
                  showMunters2: widget.showMunters2,
                  munters1Collapsed: _munters1Collapsed,
                  munters2Collapsed: _munters2Collapsed,
                  magnifierSettings: widget.magnifierSettings,
                  onToggleAll: _allSectionsExpanded
                      ? _collapseAllSections
                      : _expandAllSections,
                  allSectionsExpanded: _allSectionsExpanded,
                  onToggleMunters1: () {
                    setState(() {
                      _munters1Collapsed = !_munters1Collapsed;
                    });
                  },
                  onToggleMunters2: () {
                    setState(() {
                      _munters2Collapsed = !_munters2Collapsed;
                    });
                  },
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: _ComparisonColumnsScope(
                      showMunters1: widget.showMunters1,
                      showMunters2: widget.showMunters2,
                      munters1Collapsed: _munters1Collapsed,
                      munters2Collapsed: _munters2Collapsed,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _withSectionSpacing(orderedSections, 8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _WitnessDotMode {
  blinking,
  fixed,
}

class _WitnessDotVisual {
  const _WitnessDotVisual({
    required this.color,
    required this.mode,
  });

  final Color color;
  final _WitnessDotMode mode;
}

class _ComparisonTechnicalDataGroup extends StatelessWidget {
  const _ComparisonTechnicalDataGroup({
    required this.expanded,
    required this.onToggle,
    required this.rows,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2638),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF223046)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Technical data',
                      style: TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(
                      Icons.expand_more,
                      color: Color(0xFF94A3B8),
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ClipRect(
            child: AnimatedAlign(
              alignment: Alignment.topCenter,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              heightFactor: expanded ? 1 : 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
                child: Column(children: rows),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({
    required this.showMunters1,
    required this.showMunters2,
    required this.munters1Collapsed,
    required this.munters2Collapsed,
    required this.magnifierSettings,
    required this.onToggleAll,
    required this.allSectionsExpanded,
    required this.onToggleMunters1,
    required this.onToggleMunters2,
  });

  final bool showMunters1;
  final bool showMunters2;
  final bool munters1Collapsed;
  final bool munters2Collapsed;
  final MagnifierSettings magnifierSettings;
  final VoidCallback onToggleAll;
  final bool allSectionsExpanded;
  final VoidCallback onToggleMunters1;
  final VoidCallback onToggleMunters2;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(bottom: BorderSide(color: Color(0xFF334155))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                _InstantMagnifierButton(settings: magnifierSettings),
              ],
            ),
          ),
          if (showMunters1)
            _HeaderUnit(
              title: 'M1',
              collapsed: munters1Collapsed,
              onToggle: onToggleMunters1,
            ),
          if (showMunters2)
            _HeaderUnit(
              title: 'M2',
              collapsed: munters2Collapsed,
              onToggle: onToggleMunters2,
            ),
          _HeaderTapIcon(
            icon: allSectionsExpanded
                ? Icons.unfold_less_rounded
                : Icons.unfold_more_rounded,
            onTap: onToggleAll,
          ),
        ],
      ),
    );
  }
}

List<Widget> _withSectionSpacing(List<Widget> children, double spacing) {
  if (children.isEmpty) {
    return const <Widget>[];
  }

  final List<Widget> spaced = <Widget>[];
  for (int index = 0; index < children.length; index += 1) {
    if (index > 0) {
      spaced.add(SizedBox(height: spacing));
    }
    spaced.add(children[index]);
  }
  return spaced;
}

class _HeaderUnit extends StatelessWidget {
  const _HeaderUnit({
    required this.title,
    required this.collapsed,
    required this.onToggle,
  });

  final String title;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return SizedBox(
        width: 52,
        height: 24,
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFE5E7EB),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_right_rounded,
                  color: Color(0xFF94A3B8),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Expanded(
      flex: 4,
      child: SizedBox(
        height: 24,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFE5E7EB),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(
                  Icons.keyboard_arrow_left_rounded,
                  color: Color(0xFF94A3B8),
                  size: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderTapIcon extends StatelessWidget {
  const _HeaderTapIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: const Color(0xFF162133),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF223046)),
        ),
        child: Icon(icon, size: 16, color: const Color(0xFF94A3B8)),
      ),
    );
  }
}

class _HeaderActionIcon extends StatelessWidget {
  const _HeaderActionIcon({
    required this.icon,
    required this.onPointerDown,
  });

  final IconData icon;
  final ValueChanged<PointerDownEvent>? onPointerDown;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: onPointerDown,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: const Color(0xFF162133),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF223046)),
        ),
        child: Icon(icon, size: 16, color: const Color(0xFF94A3B8)),
      ),
    );
  }
}

class _InstantMagnifierButton extends StatefulWidget {
  const _InstantMagnifierButton({required this.settings});

  final MagnifierSettings settings;

  @override
  State<_InstantMagnifierButton> createState() => _InstantMagnifierButtonState();
}

class _InstantMagnifierButtonState extends State<_InstantMagnifierButton> {
  OverlayEntry? _overlayEntry;
  Offset? _globalPosition;
  int? _activePointer;

  @override
  void dispose() {
    _stopTracking();
    super.dispose();
  }

  void _startTracking(PointerDownEvent event) {
    _activePointer = event.pointer;
    WidgetsBinding.instance.pointerRouter.addGlobalRoute(_handlePointerEvent);
    _showMagnifier(event.position);
  }

  void _handlePointerEvent(PointerEvent event) {
    if (event.pointer != _activePointer) {
      return;
    }
    if (event is PointerMoveEvent) {
      _updateMagnifier(event.position);
      return;
    }
    if (event is PointerUpEvent) {
      _stopTracking();
    }
  }

  void _showMagnifier(Offset globalPosition) {
    _globalPosition = globalPosition;
    final OverlayState overlay = Overlay.of(context, rootOverlay: true);
    _overlayEntry ??= OverlayEntry(builder: _buildOverlay);
    if (!(_overlayEntry?.mounted ?? false)) {
      overlay.insert(_overlayEntry!);
    } else {
      _overlayEntry!.markNeedsBuild();
    }
  }

  void _updateMagnifier(Offset globalPosition) {
    _globalPosition = globalPosition;
    _overlayEntry?.markNeedsBuild();
  }

  Widget _buildOverlay(BuildContext context) {
    final Offset? globalPosition = _globalPosition;
    if (globalPosition == null) {
      return const SizedBox.shrink();
    }

    final double size = widget.settings.size;
    final double left = globalPosition.dx - (size / 2);
    final double top = globalPosition.dy - size - 24;

    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: RawMagnifier(
              size: Size.square(size),
              magnificationScale: widget.settings.zoom,
              decoration: MagnifierDecoration(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFF94A3B8), width: 1.5),
                ),
                shadows: const [
                  BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 18,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _stopTracking() {
    if (_activePointer != null) {
      WidgetsBinding.instance.pointerRouter.removeGlobalRoute(
        _handlePointerEvent,
      );
      _activePointer = null;
    }
    _overlayEntry?.remove();
    _overlayEntry = null;
    _globalPosition = null;
  }

  @override
  Widget build(BuildContext context) {
    return _HeaderActionIcon(
      icon: Icons.zoom_in_rounded,
      onPointerDown: _startTracking,
    );
  }
}

class _ComparisonColumnsScope extends InheritedWidget {
  const _ComparisonColumnsScope({
    required this.showMunters1,
    required this.showMunters2,
    required this.munters1Collapsed,
    required this.munters2Collapsed,
    required super.child,
  });

  final bool showMunters1;
  final bool showMunters2;
  final bool munters1Collapsed;
  final bool munters2Collapsed;

  static _ComparisonColumnsScope of(BuildContext context) {
    final _ComparisonColumnsScope? scope = context
        .dependOnInheritedWidgetOfExactType<_ComparisonColumnsScope>();
    assert(scope != null, 'Comparison columns scope not found');
    return scope!;
  }

  @override
  bool updateShouldNotify(_ComparisonColumnsScope oldWidget) {
    return showMunters1 != oldWidget.showMunters1 ||
        showMunters2 != oldWidget.showMunters2 ||
        munters1Collapsed != oldWidget.munters1Collapsed ||
        munters2Collapsed != oldWidget.munters2Collapsed;
  }
}

class _PlcModuleIconData {
  const _PlcModuleIconData({
    required this.icon,
    required this.iconColor,
    required this.status,
    this.extraWidget,
    this.spinning = false,
    this.witnessVisual,
    this.showPulseDot = false,
    this.pulseDotBackendAlive = true,
    this.pulseDotColor = const Color(0xFF22C55E),
  });

  final IconData icon;
  final Color iconColor;
  final _ModuleStatus status;
  final Widget? extraWidget;
  final bool spinning;
  final _WitnessDotVisual? witnessVisual;
  final bool showPulseDot;
  final bool pulseDotBackendAlive;
  final Color pulseDotColor;
}

class _PlcModuleIconWidget extends StatelessWidget {
  const _PlcModuleIconWidget({required this.data});

  final _PlcModuleIconData data;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ModuleStatusIndicator(status: data.status),
        const SizedBox(width: 4),
        _SpinningIcon(
          icon: data.icon,
          color: data.iconColor,
          size: 14,
          spinning: data.spinning,
        ),
        if (data.extraWidget != null) ...[
          const SizedBox(width: 2),
          data.extraWidget!,
        ],
        if (data.witnessVisual != null) ...[
          const SizedBox(width: 4),
          _SectionBlinkDot(
            color: data.witnessVisual!.color,
            intervalMs: 1000,
            mode: data.witnessVisual!.mode,
          ),
          const SizedBox(width: 2),
          _SectionTitlePulseDot(
            active: data.showPulseDot,
            backendAlive: data.pulseDotBackendAlive,
            color: data.pulseDotColor,
          ),
        ],
      ],
    );
  }
}

class _SpinningIcon extends StatefulWidget {
  const _SpinningIcon({
    required this.icon,
    required this.color,
    required this.size,
    required this.spinning,
  });

  final IconData icon;
  final Color color;
  final double size;
  final bool spinning;

  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.spinning) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _SpinningIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spinning != widget.spinning) {
      if (widget.spinning) {
        _controller.repeat();
      } else {
        _controller.stop();
        _controller.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget icon = Icon(widget.icon, size: widget.size, color: widget.color);
    if (!widget.spinning) {
      return icon;
    }
    return AnimatedBuilder(
      animation: _controller,
      child: icon,
      builder: (BuildContext context, Widget? child) => Transform.rotate(
        angle: _controller.value * math.pi * 2,
        child: child,
      ),
    );
  }
}

class _SectionTable extends StatefulWidget {
  const _SectionTable({
    super.key,
    required this.title,
    required this.rows,
    required this.plcIconData,
    required this.collapseGeneration,
    required this.expandGeneration,
    required this.expandRequestGeneration,
    required this.onExpanded,
  });

  final String title;
  final List<Widget> rows;
  final List<_PlcModuleIconData> plcIconData;
  final int collapseGeneration;
  final int expandGeneration;
  final int expandRequestGeneration;
  final VoidCallback onExpanded;

  @override
  State<_SectionTable> createState() => _SectionTableState();
}

class _SectionTableState extends State<_SectionTable> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _SectionTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.collapseGeneration != oldWidget.collapseGeneration && _expanded) {
      setState(() {
        _expanded = false;
      });
    }
    if (widget.expandGeneration != oldWidget.expandGeneration && !_expanded) {
      setState(() {
        _expanded = true;
      });
    }
    if (widget.expandRequestGeneration != oldWidget.expandRequestGeneration &&
        !_expanded) {
      setState(() {
        _expanded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final _ComparisonColumnsScope scope = _ComparisonColumnsScope.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF162133),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () {
              setState(() {
                _expanded = !_expanded;
              });
              if (_expanded) {
                widget.onExpanded();
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 18,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Center(
                            child: Text(
                              widget.title,
                              style: const TextStyle(
                                color: Color(0xFFE5E7EB),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                height: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!scope.showMunters1)
                    const SizedBox.shrink()
                  else if (scope.munters1Collapsed)
                    const SizedBox(width: 52)
                  else
                    Expanded(
                      flex: 4,
                      child: Center(
                        child: widget.plcIconData.isNotEmpty
                            ? _PlcModuleIconWidget(data: widget.plcIconData[0])
                            : const SizedBox.shrink(),
                      ),
                    ),
                  if (!scope.showMunters2)
                    const SizedBox.shrink()
                  else if (scope.munters2Collapsed)
                    const SizedBox(width: 52)
                  else
                    Expanded(
                      flex: 4,
                      child: Center(
                        child: widget.plcIconData.length > 1
                            ? _PlcModuleIconWidget(data: widget.plcIconData[1])
                            : const SizedBox.shrink(),
                      ),
                    ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF94A3B8),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 6),
            ...widget.rows,
          ] else ...[
            const SizedBox(height: 2),
          ],
        ],
      ),
    );
  }
}

class _SectionTitlePulseDot extends StatelessWidget {
  const _SectionTitlePulseDot({
    required this.active,
    required this.backendAlive,
    this.color = const Color(0xFF22C55E),
  });

  final bool active;
  final bool backendAlive;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Testigo backend
    if (!backendAlive) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFEF4444).withAlpha(120),
              blurRadius: 6,
              spreadRadius: 0.6,
            ),
          ],
        ),
      );
    }

    return AnimatedOpacity(
      opacity: active ? 1 : 0.12,
      duration: const Duration(milliseconds: 140),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: active
              ? [
                  BoxShadow(
                    color: color.withAlpha(153),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : const [],
        ),
      ),
    );
  }
}

class _SectionBlinkDot extends StatefulWidget {
  const _SectionBlinkDot({
    required this.color,
    required this.intervalMs,
    this.mode = _WitnessDotMode.blinking,
  });

  final Color color;
  final int intervalMs;
  final _WitnessDotMode mode;

  @override
  State<_SectionBlinkDot> createState() => _SectionBlinkDotState();
}

class _SectionBlinkDotState extends State<_SectionBlinkDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  static const double _initialPhase = 0.43;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.intervalMs),
      value: _initialPhase,
    )..repeat(period: Duration(milliseconds: widget.intervalMs));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == _WitnessDotMode.fixed) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withAlpha(120),
              blurRadius: 6,
              spreadRadius: 0.6,
            ),
          ],
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final double t = _controller.value;
        final double pulse = t < 0.22
            ? Curves.easeOut.transform(t / 0.22)
            : (t < 0.44
                  ? 1 - Curves.easeIn.transform((t - 0.22) / 0.22)
                  : 0);
        return Opacity(
          opacity: 0.16 + (pulse * 0.84),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              boxShadow: pulse > 0
                  ? [
                      BoxShadow(
                        color: widget.color.withAlpha(140),
                        blurRadius: 7 + (pulse * 2),
                        spreadRadius: 0.8,
                      ),
                    ]
                  : const [],
            ),
          ),
        );
      },
    );
  }
}

bool _hasAlarm(MuntersModel unit) {
  if (_shouldBlockOperationalData(unit)) {
    return false;
  }
  return unit.alarmaGeneral == true || unit.fallaRed == true;
}

bool _isPlcStopState(MuntersModel unit) {
  return switch (unit.diagnostics?.stateCode) {
    PlcUnitDiagnostics.plcReachableNoValidData ||
    PlcUnitDiagnostics.plcStopConfirmed => true,
    _ => false,
  };
}

bool _isUnitOperationallyConfigured(MuntersModel unit) {
  return unit.configured == true &&
      unit.diagnostics?.stateCode != PlcUnitDiagnostics.plcNotConfigured;
}

bool _isModuleStatusAlarm(_ModuleStatus status) {
  return status.kind == _ModuleStatusKind.error ||
      status.kind == _ModuleStatusKind.alert;
}

bool _isFunctioningHealthy(MuntersModel unit) {
  return switch (unit.diagnostics?.stateCode) {
    PlcUnitDiagnostics.plcHealthy || PlcUnitDiagnostics.plcRunConfirmed => true,
    _ => false,
  };
}

_WitnessDotVisual _resolvePlcWitnessVisual(List<MuntersModel> units) {
  final List<MuntersModel> visibleUnits = units
      .where((MuntersModel unit) => _isUnitOperationallyConfigured(unit))
      .toList(growable: false);

  if (visibleUnits.isEmpty) {
    return const _WitnessDotVisual(
      color: Color(0xFF64748B),
      mode: _WitnessDotMode.fixed,
    );
  }

  if (visibleUnits.any((MuntersModel unit) {
    final String? stateCode = unit.diagnostics?.stateCode;
    return stateCode == PlcUnitDiagnostics.backendDown ||
        stateCode == PlcUnitDiagnostics.plcUnreachable;
  })) {
    return const _WitnessDotVisual(
      color: Color(0xFFEF4444),
      mode: _WitnessDotMode.fixed,
    );
  }

  if (visibleUnits.any(_isPlcStopState)) {
    return const _WitnessDotVisual(
      color: Color(0xFFF59E0B),
      mode: _WitnessDotMode.fixed,
    );
  }

  if (visibleUnits.any(_isFunctioningHealthy)) {
    return const _WitnessDotVisual(
      color: Color(0xFF4ADE80),
      mode: _WitnessDotMode.blinking,
    );
  }

  return const _WitnessDotVisual(
    color: Color(0xFFF59E0B),
    mode: _WitnessDotMode.fixed,
  );
}

bool _hasFunctioningEvent(MuntersModel unit) {
  if (!_isUnitOperationallyConfigured(unit)) {
    return false;
  }
  if (_shouldBlockOperationalData(unit)) {
    return false;
  }
  return !_isFunctioningHealthy(unit);
}

bool _hasDoorAlarm(MuntersModel unit) {
  if (_shouldBlockOperationalData(unit)) {
    return false;
  }
  return unit.salaAbierta == true || unit.munterAbierto == true;
}

bool _shouldBlockOperationalData(MuntersModel unit) {
  return switch (unit.diagnostics?.stateCode) {
    PlcUnitDiagnostics.backendDown ||
    PlcUnitDiagnostics.plcUnreachable ||
    PlcUnitDiagnostics.plcReachableNoValidData ||
    PlcUnitDiagnostics.plcStopConfirmed ||
    PlcUnitDiagnostics.plcStateUnknown ||
    PlcUnitDiagnostics.plcReachableStateUnknown => true,
    _ => false,
  };
}

_ModuleStatus _resolveFunctioningStatusForUnit(MuntersModel unit) {
  if (!_isUnitOperationallyConfigured(unit)) {
    return const _ModuleStatus.pending();
  }
  if (_shouldBlockOperationalData(unit)) {
    return const _ModuleStatus.pending();
  }
  if (_hasFunctioningEvent(unit)) {
    return const _ModuleStatus.alert();
  }
  if (_isFunctioningHealthy(unit)) {
    return const _ModuleStatus.ok();
  }
  return const _ModuleStatus.pending();
}

_ModuleStatus _resolveFunctioningModuleStatus(List<MuntersModel> units) {
  final List<MuntersModel> configuredUnits = units
      .where(_isUnitOperationallyConfigured)
      .toList(growable: false);
  if (configuredUnits.isEmpty) {
    return const _ModuleStatus.pending();
  }
  final List<_ModuleStatus> statuses = configuredUnits
      .map(_resolveFunctioningStatusForUnit)
      .toList(growable: false);
  if (statuses.any(_isModuleStatusAlarm)) {
    return const _ModuleStatus.alert();
  }
  if (statuses.any((status) => status.kind == _ModuleStatusKind.ok)) {
    return const _ModuleStatus.ok();
  }
  return const _ModuleStatus.pending();
}

List<String> _eventModulesForUnit(
  MuntersModel unit,
  DashboardRangeSettings rangeSettings,
) {
  final List<String> modules = <String>[];
  if (_isModuleStatusAlarm(_resolveFunctioningStatusForUnit(unit))) {
    modules.add('Funcionamiento');
  }
  if (_isModuleStatusAlarm(
    _resolveEnvironmentStatusForUnit(unit: unit, rangeSettings: rangeSettings),
  )) {
    modules.add('Ambiente');
  }
  if (_isModuleStatusAlarm(_resolveVentilationStatusForUnit(unit))) {
    modules.add('Ventilacion');
  }
  if (_isModuleStatusAlarm(
    _resolveHumidificationStatusForUnit(unit, rangeSettings),
  )) {
    modules.add('Humidificacion');
  }
  if (_isModuleStatusAlarm(_resolveAperturasStatusForUnit(unit))) {
    modules.add('Aperturas');
  }
  if (_isModuleStatusAlarm(_resolveCalefaccionStatusForUnit(unit, rangeSettings))) {
    modules.add('Calefaccion');
  }
  return modules;
}

bool _isVentilationFullyRunning(MuntersModel unit) {
  if (_shouldBlockOperationalData(unit)) {
    return false;
  }
  final List<bool> fans = <bool?>[
    unit.fanQ5, unit.fanQ6, unit.fanQ7,
    unit.fanQ8, unit.fanQ9, unit.fanQ10,
  ].whereType<bool>().toList(growable: false);
  return fans.isNotEmpty && fans.every((bool f) => f == true);
}

Color _resolveVentilationIconColorForUnit(MuntersModel unit) {
  if (_shouldBlockOperationalData(unit)) {
    return const Color(0xFF94A3B8);
  }
  final List<bool> fans = <bool?>[
    unit.fanQ5,
    unit.fanQ6,
    unit.fanQ7,
    unit.fanQ8,
    unit.fanQ9,
    unit.fanQ10,
  ].whereType<bool>().toList(growable: false);
  if (fans.isEmpty) {
    return const Color(0xFF94A3B8);
  }
  if (fans.every((bool f) => f == false)) {
    return const Color(0xFFEF4444);
  }
  if (fans.every((bool f) => f == true)) {
    return const Color(0xFF22C55E);
  }
  if (fans.any((bool f) => f == false)) {
    return const Color(0xFFFACC15);
  }
  return const Color(0xFF94A3B8);
}

Color _resolveEnvironmentIconColorForUnit({
  required MuntersModel unit,
  required DashboardRangeSettings rangeSettings,
}) {
  if (_shouldBlockOperationalData(unit) || unit.tempInterior == null) {
    return const Color(0xFF94A3B8);
  }
  final double temp = unit.tempInterior!;
  final double min = rangeSettings.temperatureMin;
  final double max = rangeSettings.temperatureMax;
  final double span = max - min;
  if (span <= 0) {
    return const Color(0xFF94A3B8);
  }
  final double coldLimit = min + (span * 0.25);
  final double hotLimit = min + (span * 0.75);
  if (temp >= hotLimit) {
    return const Color(0xFFEF4444);
  }
  if (temp <= coldLimit) {
    return const Color(0xFF38BDF8);
  }
  return const Color(0xFF22C55E);
}

_HumidityHeaderVisual _resolveEnvironmentHumidityVisualForUnit({
  required MuntersModel unit,
  required DashboardRangeSettings rangeSettings,
}) {
  if (_shouldBlockOperationalData(unit) || unit.humInterior == null) {
    return _HumidityHeaderVisual.empty;
  }
  final double humidity = unit.humInterior!;
  final double min = rangeSettings.humidityMin;
  final double max = rangeSettings.humidityMax;
  final double span = max - min;
  if (span <= 0) {
    return _HumidityHeaderVisual.empty;
  }
  final double lowerQuarter = min + (span * 0.25);
  final double upperQuarter = min + (span * 0.75);
  if (humidity <= lowerQuarter) {
    return _HumidityHeaderVisual.low;
  }
  if (humidity >= upperQuarter) {
    return _HumidityHeaderVisual.high;
  }
  return _HumidityHeaderVisual.medium;
}

_ModuleStatus _resolveAlarmasStatusForUnit(
  MuntersModel unit,
  DashboardRangeSettings rangeSettings,
) {
  return _resolveAlarmasStatus(
    functioningStatus: _resolveFunctioningStatusForUnit(unit),
    environmentStatus: _resolveEnvironmentStatusForUnit(
      unit: unit,
      rangeSettings: rangeSettings,
    ),
    ventilationStatus: _resolveVentilationStatusForUnit(unit),
    humidificationStatus: _resolveHumidificationStatusForUnit(unit, rangeSettings),
    aperturasStatus: _resolveAperturasStatusForUnit(unit),
    calefaccionStatus: _resolveCalefaccionStatusForUnit(unit, rangeSettings),
    hasAlarmOutput: unit.alarmaGeneral == true,
  );
}


_RangeAssessment _assessRange(double? value, double min, double max) {
  if (value == null) {
    return _RangeAssessment.pending;
  }
  if (value < min || value > max) {
    return _RangeAssessment.outOfRange;
  }
  final double span = max - min;
  if (span <= 0) {
    return _RangeAssessment.pending;
  }
  final double coldLimit = min + (span * 0.25);
  final double hotLimit = min + (span * 0.75);
  if (value <= coldLimit || value >= hotLimit) {
    return _RangeAssessment.limit;
  }
  return _RangeAssessment.optimal;
}

_RangeAssessment _mergeAssessments(Iterable<_RangeAssessment> values) {
  _RangeAssessment current = _RangeAssessment.pending;
  for (final _RangeAssessment value in values) {
    if (value.index > current.index) {
      current = value;
    }
  }
  return current;
}

_ModuleStatus _resolveEnvironmentStatus({
  required MuntersModel munters1,
  required MuntersModel munters2,
  required DashboardRangeSettings rangeSettings,
}) {
  final List<_ModuleStatus> statuses = <_ModuleStatus>[
    _resolveEnvironmentStatusForUnit(
      unit: munters1,
      rangeSettings: rangeSettings,
    ),
    _resolveEnvironmentStatusForUnit(
      unit: munters2,
      rangeSettings: rangeSettings,
    ),
  ];
  if (statuses.any((status) => status.kind == _ModuleStatusKind.error)) {
    return const _ModuleStatus.error();
  }
  if (statuses.any((status) => status.kind == _ModuleStatusKind.warning)) {
    return const _ModuleStatus.warning();
  }
  if (statuses.any((status) => status.kind == _ModuleStatusKind.ok)) {
    return const _ModuleStatus.ok();
  }
  return const _ModuleStatus.pending();
}

_ModuleStatus _resolveEnvironmentStatusForUnit({
  required MuntersModel unit,
  required DashboardRangeSettings rangeSettings,
}) {
  if (_shouldBlockOperationalData(unit)) {
    return const _ModuleStatus.pending();
  }
  final _RangeAssessment assessment = _mergeAssessments(<_RangeAssessment>[
    _assessRange(
      unit.tempInterior,
      rangeSettings.temperatureMin,
      rangeSettings.temperatureMax,
    ),
    _assessRange(
      unit.humInterior,
      rangeSettings.humidityMin,
      rangeSettings.humidityMax,
    ),
  ]);

  return switch (assessment) {
    _RangeAssessment.outOfRange => const _ModuleStatus.error(),
    _RangeAssessment.limit => const _ModuleStatus.warning(),
    _RangeAssessment.optimal => const _ModuleStatus.ok(),
    _RangeAssessment.pending => const _ModuleStatus.pending(),
  };
}


_ModuleStatus _resolveVentilationStatus(
  MuntersModel munters1,
  MuntersModel munters2,
) {
  final List<bool> fans = <bool?>[
    if (!_shouldBlockOperationalData(munters1)) ...<bool?>[
      munters1.fanQ5,
      munters1.fanQ6,
      munters1.fanQ7,
      munters1.fanQ8,
      munters1.fanQ9,
      munters1.fanQ10,
    ],
    if (!_shouldBlockOperationalData(munters2)) ...<bool?>[
      munters2.fanQ5,
      munters2.fanQ6,
      munters2.fanQ7,
      munters2.fanQ8,
      munters2.fanQ9,
      munters2.fanQ10,
    ],
  ].whereType<bool>().toList(growable: false);

  if (fans.isEmpty) {
    return const _ModuleStatus.pending();
  }
  if (fans.every((bool fan) => fan == false)) {
    return const _ModuleStatus.alert();
  }
  if (fans.every((bool fan) => fan == true)) {
    return const _ModuleStatus.ok();
  }
  if (fans.any((bool fan) => fan == false)) {
    return const _ModuleStatus.warning();
  }
  return const _ModuleStatus.pending();
}

_ModuleStatus _resolveVentilationStatusForUnit(MuntersModel unit) {
  if (_shouldBlockOperationalData(unit)) {
    return const _ModuleStatus.pending();
  }
  final List<bool> fans = <bool?>[
    unit.fanQ5,
    unit.fanQ6,
    unit.fanQ7,
    unit.fanQ8,
    unit.fanQ9,
    unit.fanQ10,
  ].whereType<bool>().toList(growable: false);

  if (fans.isEmpty) {
    return const _ModuleStatus.pending();
  }
  if (fans.every((bool fan) => fan == false)) {
    return const _ModuleStatus.alert();
  }
  if (fans.every((bool fan) => fan == true)) {
    return const _ModuleStatus.ok();
  }
  if (fans.any((bool fan) => fan == false)) {
    return const _ModuleStatus.warning();
  }
  return const _ModuleStatus.pending();
}

_ModuleStatus _resolveHumidificationStatus(
  MuntersModel munters1,
  MuntersModel munters2,
  DashboardRangeSettings rangeSettings,
) {
  final List<_ModuleStatus> statuses = <_ModuleStatus>[
    _resolveHumidificationStatusForUnit(munters1, rangeSettings),
    _resolveHumidificationStatusForUnit(munters2, rangeSettings),
  ];
  if (statuses.any(_isModuleStatusAlarm)) {
    return const _ModuleStatus.alert();
  }
  if (statuses.any((status) => status.kind == _ModuleStatusKind.ok)) {
    return const _ModuleStatus.ok();
  }
  return const _ModuleStatus.pending();
}

_ModuleStatus _resolveAperturasStatus(
  MuntersModel munters1,
  MuntersModel munters2,
) {
  final List<_ModuleStatus> statuses = <_ModuleStatus>[
    _resolveAperturasStatusForUnit(munters1),
    _resolveAperturasStatusForUnit(munters2),
  ];

  if (statuses.any((status) => status.kind == _ModuleStatusKind.alert)) {
    return const _ModuleStatus.alert();
  }
  if (statuses.any((status) => status.kind == _ModuleStatusKind.ok)) {
    return const _ModuleStatus.ok();
  }
  return const _ModuleStatus.pending();
}

_ModuleStatus _resolveAlarmasStatus({
  required _ModuleStatus functioningStatus,
  required _ModuleStatus environmentStatus,
  required _ModuleStatus ventilationStatus,
  required _ModuleStatus humidificationStatus,
  required _ModuleStatus aperturasStatus,
  required _ModuleStatus calefaccionStatus,
  required bool hasAlarmOutput,
}) {
  if (hasAlarmOutput ||
      _isModuleStatusAlarm(functioningStatus) ||
      _isModuleStatusAlarm(environmentStatus) ||
      _isModuleStatusAlarm(ventilationStatus) ||
      _isModuleStatusAlarm(humidificationStatus) ||
      _isModuleStatusAlarm(aperturasStatus) ||
      _isModuleStatusAlarm(calefaccionStatus)) {
    return const _ModuleStatus.alert();
  }
  if (functioningStatus.kind == _ModuleStatusKind.pending &&
      environmentStatus.kind == _ModuleStatusKind.pending &&
      ventilationStatus.kind == _ModuleStatusKind.pending &&
      humidificationStatus.kind == _ModuleStatusKind.pending &&
      aperturasStatus.kind == _ModuleStatusKind.pending &&
      calefaccionStatus.kind == _ModuleStatusKind.pending) {
    return const _ModuleStatus.pending();
  }
  if (functioningStatus.kind == _ModuleStatusKind.pending) {
    return const _ModuleStatus.pending();
  }
  return const _ModuleStatus.ok();
}

_ModuleStatus _resolveHumidificationStatusForUnit(
  MuntersModel unit,
  DashboardRangeSettings rangeSettings,
) {
  if (_shouldBlockOperationalData(unit)) {
    return const _ModuleStatus.pending();
  }
  if (_hasHeatingHumidificationConflict(unit)) {
    return const _ModuleStatus.alert();
  }
  if (_isTempAboveMaximumAndPumpOff(unit, rangeSettings)) {
    return const _ModuleStatus.error();
  }
  final bool? alarm = unit.nivelAguaAlarma;
  final bool? thermalFault = unit.fallaTermicaBomba;
  if (alarm == null && thermalFault == null) {
    return const _ModuleStatus.pending();
  }
  if (alarm == true || thermalFault == true) {
    return const _ModuleStatus.alert();
  }
  return const _ModuleStatus.ok();
}

_ModuleStatus _resolveCalefaccionStatus(
  MuntersModel munters1,
  MuntersModel munters2,
  DashboardRangeSettings rangeSettings,
) {
  final List<_ModuleStatus> statuses = <_ModuleStatus>[
    _resolveCalefaccionStatusForUnit(munters1, rangeSettings),
    _resolveCalefaccionStatusForUnit(munters2, rangeSettings),
  ];
  if (statuses.any(_isModuleStatusAlarm)) {
    return const _ModuleStatus.alert();
  }
  if (statuses.every((status) => status.kind == _ModuleStatusKind.pending)) {
    return const _ModuleStatus.pending();
  }
  return const _ModuleStatus.ok();
}

_ModuleStatus _resolveCalefaccionStatusForUnit(
  MuntersModel unit,
  DashboardRangeSettings rangeSettings,
) {
  if (_shouldBlockOperationalData(unit)) {
    return const _ModuleStatus.pending();
  }
  if (_hasHeatingHumidificationConflict(unit)) {
    return const _ModuleStatus.alert();
  }
  if (_isTempBelowMinimumAndHeatingOff(unit, rangeSettings)) {
    return const _ModuleStatus.error();
  }
  if (unit.resistencia1 == null && unit.resistencia2 == null) {
    return const _ModuleStatus.pending();
  }
  return const _ModuleStatus.ok();
}

_ModuleStatus _resolveAperturasStatusForUnit(MuntersModel unit) {
  if (_shouldBlockOperationalData(unit)) {
    return const _ModuleStatus.pending();
  }
  if (_hasDoorAlarm(unit)) {
    return const _ModuleStatus.alert();
  }
  final bool hasAnyDoorSignal =
      unit.salaAbierta != null || unit.munterAbierto != null;
  if (!hasAnyDoorSignal) {
    return const _ModuleStatus.pending();
  }
  return const _ModuleStatus.ok();
}

bool _hasAnyHeatingOn(MuntersModel unit) {
  return unit.resistencia1 == true || unit.resistencia2 == true;
}

bool _areBothHeatingStagesOff(MuntersModel unit) {
  return unit.resistencia1 == false && unit.resistencia2 == false;
}

bool _hasHeatingHumidificationConflict(MuntersModel unit) {
  if (_shouldBlockOperationalData(unit)) {
    return false;
  }
  return unit.bombaHumidificador == true && _hasAnyHeatingOn(unit);
}

bool _isTempBelowMinimumAndHeatingOff(
  MuntersModel unit,
  DashboardRangeSettings rangeSettings,
) {
  if (_shouldBlockOperationalData(unit)) {
    return false;
  }
  final double? temp = unit.tempInterior;
  if (temp == null || temp >= rangeSettings.temperatureMin) {
    return false;
  }
  return _areBothHeatingStagesOff(unit);
}

bool _isTempAboveMaximumAndPumpOff(
  MuntersModel unit,
  DashboardRangeSettings rangeSettings,
) {
  if (_shouldBlockOperationalData(unit)) {
    return false;
  }
  final double? temp = unit.tempInterior;
  if (temp == null || temp <= rangeSettings.temperatureMax) {
    return false;
  }
  return unit.bombaHumidificador == false;
}

List<String> _humidificationNoticesForUnit(
  MuntersModel unit,
  DashboardRangeSettings rangeSettings,
) {
  if (_shouldBlockOperationalData(unit)) {
    return const <String>[];
  }
  final List<String> notices = <String>[];
  if (_hasHeatingHumidificationConflict(unit)) {
    notices.add('Resistencias encendidas');
  }
  if (_isTempAboveMaximumAndPumpOff(unit, rangeSettings)) {
    notices.add('Temp. en max.');
  }
  if (unit.fallaTermicaBomba == true) {
    notices.add('Falla termica');
  }
  return notices;
}

bool _hasHumidificationNotice(
  MuntersModel unit,
  DashboardRangeSettings rangeSettings,
) {
  return _humidificationNoticesForUnit(unit, rangeSettings).isNotEmpty;
}

List<String> _calefaccionNoticesForUnit(
  MuntersModel unit,
  DashboardRangeSettings rangeSettings,
) {
  if (_shouldBlockOperationalData(unit)) {
    return const <String>[];
  }
  final List<String> notices = <String>[];
  if (_hasHeatingHumidificationConflict(unit)) {
    notices.add('Humidificacion ON');
  }
  if (_isTempBelowMinimumAndHeatingOff(unit, rangeSettings)) {
    notices.add('Temp. en min.');
  }
  return notices;
}

bool _hasCalefaccionNotice(
  MuntersModel unit,
  DashboardRangeSettings rangeSettings,
) {
  return _calefaccionNoticesForUnit(unit, rangeSettings).isNotEmpty;
}

enum _RangeAssessment { pending, optimal, limit, outOfRange }

enum _HumidityHeaderVisual { empty, low, medium, high }

enum _ModuleStatusKind { pending, warning, error, alert, ok }

class _ModuleStatus {
  const _ModuleStatus.pending() : kind = _ModuleStatusKind.pending;
  const _ModuleStatus.warning() : kind = _ModuleStatusKind.warning;
  const _ModuleStatus.error() : kind = _ModuleStatusKind.error;
  const _ModuleStatus.alert() : kind = _ModuleStatusKind.alert;
  const _ModuleStatus.ok() : kind = _ModuleStatusKind.ok;

  final _ModuleStatusKind kind;
}

class _ModuleStatusIndicator extends StatelessWidget {
  const _ModuleStatusIndicator({required this.status});

  final _ModuleStatus status;

  @override
  Widget build(BuildContext context) {
    switch (status.kind) {
      case _ModuleStatusKind.warning:
        return Container(
          width: 18,
          height: 18,
          decoration: const BoxDecoration(
            color: Color(0xFF8A5A12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 13,
            color: Color(0xFFFDE68A),
          ),
        );
      case _ModuleStatusKind.error:
        return Container(
          width: 18,
          height: 18,
          decoration: const BoxDecoration(
            color: Color(0xFF7F1D1D),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.priority_high_rounded,
            size: 13,
            color: Color(0xFFFCA5A5),
          ),
        );
      case _ModuleStatusKind.alert:
        return Container(
          width: 18,
          height: 18,
          decoration: const BoxDecoration(
            color: Color(0xFF7F1D1D),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.priority_high_rounded,
            size: 13,
            color: Color(0xFFFCA5A5),
          ),
        );
      case _ModuleStatusKind.ok:
        return Container(
          width: 18,
          height: 18,
          decoration: const BoxDecoration(
            color: Color(0xFF14532D),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 13,
            color: Color(0xFF86EFAC),
          ),
        );
      case _ModuleStatusKind.pending:
        return Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: const Color(0xFF334155),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF475569)),
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 13,
            color: Color(0xFFCBD5E1),
          ),
        );
    }
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({
    required this.label,
    required this.munters1,
    required this.munters2,
    this.alignToTop = false,
  });

  final String label;
  final Widget munters1;
  final Widget munters2;
  final bool alignToTop;

  @override
  Widget build(BuildContext context) {
    final _ComparisonColumnsScope scope = _ComparisonColumnsScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF223046))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: alignToTop
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!scope.showMunters1)
                const SizedBox.shrink()
              else if (scope.munters1Collapsed)
                const SizedBox(width: 52)
              else
                Expanded(
                  flex: 4,
                  child: alignToTop
                      ? munters1
                      : Center(child: munters1),
                ),
              if (!scope.showMunters2)
                const SizedBox.shrink()
              else if (scope.munters2Collapsed)
                const SizedBox(width: 52)
              else
                Expanded(
                  flex: 4,
                  child: alignToTop
                      ? munters2
                      : Center(child: munters2),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EventModulesValue extends StatelessWidget {
  const _EventModulesValue({
    required this.modules,
    required this.onModuleTap,
    this.blocked = false,
  });

  final List<String> modules;
  final ValueChanged<String> onModuleTap;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    if (blocked) {
      return const _TextValue('-', fontWeight: FontWeight.w400);
    }
    if (modules.isEmpty) {
      return const Text(
        'NORMAL',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Color(0xFF22C55E),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final String module in modules)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: InkWell(
              onTap: () => onModuleTap(module),
              borderRadius: BorderRadius.circular(4),
              child: Text(
                module,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  decorationColor: Color(0xFFEF4444),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AlarmValue extends StatelessWidget {
  const _AlarmValue({required this.active, this.blocked = false});

  final bool? active;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    if (blocked) {
      return const _TextValue('-', fontWeight: FontWeight.w400);
    }
    return Text(
      active == null ? 'Sin datos' : (active! ? 'ACTIVA' : 'NORMAL'),
      style: TextStyle(
        color: active == null
            ? const Color(0xFF94A3B8)
            : (active! ? const Color(0xFFEF4444) : const Color(0xFF22C55E)),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

bool _isOutOfRange(double? value, double min, double max) {
  if (value == null) {
    return false;
  }
  return value < min || value > max;
}

class _StateValue extends StatelessWidget {
  const _StateValue({
    required this.active,
    required this.activeLabel,
    required this.inactiveLabel,
    this.blocked = false,
    this.activeColor = const Color(0xFF22C55E),
    this.inactiveColor = const Color(0xFFE5E7EB),
    this.fontWeight = FontWeight.w600,
  });

  final bool? active;
  final String activeLabel;
  final String inactiveLabel;
  final bool blocked;
  final Color activeColor;
  final Color inactiveColor;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    if (blocked) {
      return const _TextValue('-', fontWeight: FontWeight.w400);
    }
    final bool missingValue = active == null;
    return Text(
      missingValue ? 'Sin datos' : (active! ? activeLabel : inactiveLabel),
      textAlign: TextAlign.center,
      style: TextStyle(
        color: missingValue
            ? const Color(0xFF94A3B8)
            : (active! ? activeColor : inactiveColor),
        fontSize: 12,
        fontWeight: missingValue ? FontWeight.w400 : fontWeight,
      ),
    );
  }
}

class _TextValue extends StatelessWidget {
  const _TextValue(this.value, {this.fontWeight = FontWeight.w600});

  final String value;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    final bool missingValue = value == 'Sin datos' || value == '-';
    return Text(
      value,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: missingValue ? const Color(0xFF94A3B8) : const Color(0xFFE5E7EB),
        fontSize: 12,
        fontWeight: missingValue ? FontWeight.w400 : fontWeight,
      ),
    );
  }
}

class _ModuleNoticeValue extends StatelessWidget {
  const _ModuleNoticeValue({required this.messages});

  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final String message in messages)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFEF4444),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

class _ComparisonHistoryValue extends StatelessWidget {
  const _ComparisonHistoryValue({
    required this.unitName,
    required this.rangeSettings,
    required this.tenantId,
    required this.siteId,
    required this.plcId,
    this.blocked = false,
  });

  final String unitName;
  final DashboardRangeSettings rangeSettings;
  final String? tenantId;
  final String? siteId;
  final String? plcId;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    if (blocked) {
      return const _TextValue('-', fontWeight: FontWeight.w400);
    }
    return TemperatureHistoryMiniChartsCard(
      unitName: unitName,
      lowerLimit: rangeSettings.temperatureMin,
      upperLimit: rangeSettings.temperatureMax,
      tenantId: tenantId,
      siteId: siteId,
      plcId: plcId,
    );
  }
}

class _WaterLevelValue extends StatelessWidget {
  const _WaterLevelValue({required this.alarm, this.blocked = false});

  final bool? alarm;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    if (blocked) {
      return const _TextValue('-', fontWeight: FontWeight.w400);
    }
    final bool missingValue = alarm == null;
    return Text(
      missingValue ? 'Sin datos' : (alarm! ? 'ALARMA' : 'NORMAL'),
      style: TextStyle(
        color: missingValue
            ? const Color(0xFF94A3B8)
            : (alarm! ? const Color(0xFFEF4444) : const Color(0xFF22C55E)),
        fontSize: 12,
        fontWeight: missingValue ? FontWeight.w400 : FontWeight.w700,
      ),
    );
  }
}

class _StatusValue extends StatelessWidget {
  const _StatusValue({
    required this.active,
    this.activeLabel = 'SI',
    this.inactiveLabel = 'NO',
    this.blocked = false,
  });

  final bool? active;
  final String activeLabel;
  final String inactiveLabel;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    if (blocked) {
      return const _TextValue('-', fontWeight: FontWeight.w400);
    }
    final bool missingValue = active == null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusDot(active: active, size: 10),
        const SizedBox(width: 4),
        Text(
          missingValue ? 'Sin datos' : (active! ? activeLabel : inactiveLabel),
          style: TextStyle(
            color: missingValue
                ? const Color(0xFF94A3B8)
                : (active! ? const Color(0xFF22C55E) : const Color(0xFF94A3B8)),
            fontSize: 12,
            fontWeight: missingValue ? FontWeight.w400 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _EquipmentStateValue extends StatelessWidget {
  const _EquipmentStateValue({
    required this.diagnostics,
    required this.showSnapshotPulse,
  });

  final PlcUnitDiagnostics? diagnostics;
  final bool showSnapshotPulse;

  @override
  Widget build(BuildContext context) {
    final PlcUnitDiagnostics? currentDiagnostics = diagnostics;
    final bool isPlcStop =
        currentDiagnostics?.stateCode ==
            PlcUnitDiagnostics.plcReachableNoValidData ||
        currentDiagnostics?.stateCode == PlcUnitDiagnostics.plcStopConfirmed;
    final String resolvedState = isPlcStop
        ? 'PLC Stop'
        : (currentDiagnostics?.stateLabel ?? 'Sin datos');
    final List<String> detailLines = isPlcStop
        ? <String>[
            'PLC alcanzable sin datos válidos',
            if (currentDiagnostics?.stateReason case final String reason
                when reason.isNotEmpty)
              reason.replaceAll('. Probable STOP.', '.'),
          ]
        : <String>[
            if (currentDiagnostics?.stateReason case final String reason
                when reason.isNotEmpty)
              reason,
          ];

    final Color stateColor = switch (currentDiagnostics?.stateCode) {
      PlcUnitDiagnostics.plcNotConfigured => const Color(0xFFFACC15),
      PlcUnitDiagnostics.plcUnreachable => const Color(0xFFEF4444),
      PlcUnitDiagnostics.plcReachableNoValidData =>
        const Color(0xFFF59E0B),
      PlcUnitDiagnostics.plcStopConfirmed => const Color(0xFFF59E0B),
      PlcUnitDiagnostics.plcHealthy => const Color(0xFF22C55E),
      PlcUnitDiagnostics.plcRunConfirmed => const Color(0xFF22C55E),
      PlcUnitDiagnostics.plcStateUnknown =>
        const Color(0xFFCBD5E1),
      PlcUnitDiagnostics.plcReachableStateUnknown =>
        const Color(0xFFCBD5E1),
      PlcUnitDiagnostics.backendDown => const Color(0xFFCBD5E1),
      _ => const Color(0xFF94A3B8),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              resolvedState,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: stateColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            AnimatedOpacity(
              opacity:
                  showSnapshotPulse &&
                      (currentDiagnostics?.stateCode ==
                              PlcUnitDiagnostics.plcHealthy ||
                          currentDiagnostics?.stateCode ==
                              PlcUnitDiagnostics.plcRunConfirmed)
                  ? 1
                  : 0,
              duration: const Duration(milliseconds: 180),
              child: const _SnapshotPulseDot(),
            ),
          ],
        ),
        if (detailLines.isNotEmpty) ...[
          const SizedBox(height: 2),
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final String line in detailLines)
                Text(
                  line,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SnapshotPulseDot extends StatelessWidget {
  const _SnapshotPulseDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: Color(0xFF22C55E),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _BarValue extends StatelessWidget {
  const _BarValue({required this.value, this.blocked = false});

  final double? value;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    if (blocked) {
      return const _TextValue('-', fontWeight: FontWeight.w400);
    }
    final double? currentValue = value;
    final int? percent = currentValue == null
        ? null
        : (currentValue * 100).round();

    return SizedBox(
      width: 150,
      child: Row(
        children: [
          Expanded(
            child: currentValue == null
                ? const Text(
                    'Sin datos',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: SizedBox(
                      height: 8,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(
                            decoration: const BoxDecoration(
                              color: Color(0xFF38BDF8),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FractionallySizedBox(
                              widthFactor: 1 - currentValue.clamp(0.0, 1.0),
                              child: Container(color: const Color(0xFF334155)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 6),
          Text(
            percent == null ? '--' : '$percent%',
            style: const TextStyle(
              color: Color(0xFFE5E7EB),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FanStateValue extends StatelessWidget {
  const _FanStateValue({required this.fans, this.blocked = false});

  final List<(String, bool?)> fans;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    if (blocked) {
      return const _TextValue('-', fontWeight: FontWeight.w400);
    }
    return SizedBox(
      width: 92,
      child: GridView.builder(
        shrinkWrap: true,
        itemCount: fans.length,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 1.1,
        ),
        itemBuilder: (context, index) {
          final fan = fans[index];
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                fan.$1,
                style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 9),
              ),
              const SizedBox(height: 2),
              FanIcon(running: fan.$2),
            ],
          );
        },
      ),
    );
  }
}

class FanIcon extends StatefulWidget {
  const FanIcon({super.key, required this.running});

  final bool? running;

  @override
  State<FanIcon> createState() => _FanIconState();
}

class _FanIconState extends State<FanIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.running == true
          ? const Duration(milliseconds: 900)
          : const Duration(milliseconds: 650),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant FanIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.running != widget.running) {
      _controller.duration = widget.running == true
          ? const Duration(milliseconds: 900)
          : const Duration(milliseconds: 650);
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    _controller.stop();
    if (widget.running == true) {
      _controller.repeat();
      return;
    }
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool? running = widget.running;
    final Color color = running == null
        ? const Color(0xFF94A3B8)
        : (running ? const Color(0xFF22C55E) : const Color(0xFFEF4444));
    final IconData iconData = running == null
        ? Icons.remove_circle_outline
        : Icons.cyclone_rounded;
    final Widget icon = Icon(iconData, size: 16, color: color);

    return AnimatedBuilder(
      animation: _controller,
      child: icon,
      builder: (context, child) {
        if (running != true) {
          return Opacity(
            opacity: running == null
                ? 0.8
                : (0.35 + (_controller.value * 0.65)),
            child: child,
          );
        }
        return Transform.rotate(
          angle: _controller.value * math.pi * 2,
          child: child,
        );
      },
    );
  }
}

class _TemperatureValue extends StatelessWidget {
  const _TemperatureValue({
    required this.value,
    required this.min,
    required this.max,
    this.blocked = false,
  });

  final double? value;
  final double min;
  final double max;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    if (blocked) {
      return const _TextValue('-', fontWeight: FontWeight.w400);
    }
    if (value == null) {
      return const _TextValue('Sin datos');
    }
    final double currentValue = value!;

    return SizedBox(
      width: 150,
      child: _LinearGauge(
        value: currentValue,
        min: min,
        max: max,
        valueLabel: '${currentValue.toStringAsFixed(1)} °C',
        colors: const [Color(0xFF2563EB), Color(0xFFDC2626)],
        showAlert: _isOutOfRange(currentValue, min, max),
      ),
    );
  }
}

class _HumidityValue extends StatelessWidget {
  const _HumidityValue({
    required this.value,
    required this.min,
    required this.max,
    this.blocked = false,
  });

  final double? value;
  final double min;
  final double max;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    if (blocked) {
      return const _TextValue('-', fontWeight: FontWeight.w400);
    }
    if (value == null) {
      return const _TextValue('Sin datos');
    }
    final double currentValue = value!;

    return SizedBox(
      width: 150,
      child: _LinearGauge(
        value: currentValue,
        min: min,
        max: max,
        valueLabel: '${currentValue.toStringAsFixed(0)} %',
        colors: const [Color(0xFFD6C3A1), Color(0xFF38BDF8)],
        showAlert: _isOutOfRange(currentValue, min, max),
      ),
    );
  }
}

class _EnvironmentHeaderHumidityIcon extends StatelessWidget {
  const _EnvironmentHeaderHumidityIcon({required this.visual});

  final _HumidityHeaderVisual visual;

  @override
  Widget build(BuildContext context) {
    return switch (visual) {
      _HumidityHeaderVisual.high => const Icon(
        Icons.water_drop,
        color: Color(0xFF38BDF8),
        size: 16,
      ),
      _HumidityHeaderVisual.medium => const Icon(
        Icons.opacity,
        color: Color(0xFF7DD3FC),
        size: 16,
      ),
      _HumidityHeaderVisual.low => const _HumidityFillIcon(
        fill: 0.18,
        size: 16,
      ),
      _HumidityHeaderVisual.empty => const Icon(
        Icons.opacity,
        color: Color(0xFF64748B),
        size: 16,
      ),
    };
  }
}

class _HumidityFillIcon extends StatelessWidget {
  const _HumidityFillIcon({
    required this.fill,
    this.size = 22,
  });

  final double fill;
  final double size;

  Color get _fillColor {
    if (fill >= 0.66) {
      return const Color(0xFF38BDF8);
    }
    if (fill >= 0.33) {
      return const Color(0xFF7DD3FC);
    }
    return const Color(0xFFD6C3A1);
  }

  Color get _outlineColor {
    if (fill >= 0.66) {
      return const Color(0xFF38BDF8);
    }
    if (fill >= 0.33) {
      return const Color(0xFF7DD3FC);
    }
    return const Color(0xFFD6C3A1);
  }

  @override
  Widget build(BuildContext context) {
    final double clampedFill = fill.clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.water_drop_outlined,
            color: _outlineColor,
            size: size,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: ClipRect(
              child: SizedBox(
                width: size,
                height: size * clampedFill,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  heightFactor: 1,
                  child: Icon(
                    Icons.water_drop,
                    color: _fillColor,
                    size: size,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatInt(int? value) {
  if (value == null) {
    return 'Sin datos';
  }

  return value.toString();
}

String _formatIntWithUnit(int? value, String unit) {
  if (value == null) {
    return 'Sin datos';
  }

  return '$value $unit';
}

String _formatLastUpdated(DateTime? value, DateTime? previousValue) {
  if (value == null) {
    return 'Sin datos';
  }

  final DateTime local = value.toLocal();
  final String hh = local.hour.toString().padLeft(2, '0');
  final String mm = local.minute.toString().padLeft(2, '0');
  final String ss = local.second.toString().padLeft(2, '0');
  final String base = '$hh:$mm:$ss';
  if (previousValue == null) {
    return base;
  }

  final int deltaSeconds = value.difference(previousValue).inSeconds.abs();
  return '$base (${deltaSeconds}s)';
}

String _formatPreviousLastUpdated(DateTime? value) {
  if (value == null) {
    return '0';
  }

  final DateTime local = value.toLocal();
  final String hh = local.hour.toString().padLeft(2, '0');
  final String mm = local.minute.toString().padLeft(2, '0');
  final String ss = local.second.toString().padLeft(2, '0');
  return '$hh:$mm:$ss';
}

String _formatUptime(DateTime? startedAt) {
  if (startedAt == null) {
    return '00:00:00';
  }

  final int totalSeconds = DateTime.now()
      .difference(startedAt.toLocal())
      .inSeconds;
  if (totalSeconds < 0) {
    return '00:00:00';
  }

  final int hours = totalSeconds ~/ 3600;
  final int minutes = (totalSeconds % 3600) ~/ 60;
  final int seconds = totalSeconds % 60;
  final String hh = hours.toString().padLeft(2, '0');
  final String mm = minutes.toString().padLeft(2, '0');
  final String ss = seconds.toString().padLeft(2, '0');
  return '$hh:$mm:$ss';
}

String _formatValueWithUnit(double? value, String unit) {
  if (value == null) {
    return 'Sin datos';
  }

  final int fractionDigits = unit == '°C' && value % 1 != 0 ? 1 : 0;
  return '${value.toStringAsFixed(fractionDigits)} $unit';
}

double? _normalizeVoltageToPercent(double? voltage) {
  if (voltage == null) {
    return null;
  }
  // Backend exposes the raw analog output scaled by 100.
  // Example: 450 => 4.50 V, so 100% = 10.00 V.
  return (voltage / 1000).clamp(0.0, 1.0);
}

class _LinearGauge extends StatelessWidget {
  const _LinearGauge({
    required this.value,
    required this.min,
    required this.max,
    required this.valueLabel,
    required this.colors,
    required this.showAlert,
  });

  final double value;
  final double min;
  final double max;
  final String valueLabel;
  final List<Color> colors;
  final bool showAlert;

  @override
  Widget build(BuildContext context) {
    final double clamped = ((value - min) / (max - min)).clamp(0.0, 1.0);
    const double gaugeWidth = 126;
    const double markerWidth = 8;
    const double labelWidth = 74;
    final double markerLeft = clamped * (gaugeWidth - markerWidth);
    final double labelLeft = math.max(
      0,
      math.min(
        gaugeWidth - labelWidth,
        markerLeft - ((labelWidth - markerWidth) / 2),
      ),
    );

    return SizedBox(
      height: 52,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: gaugeWidth,
            height: 18,
            child: Stack(
              children: [
                Positioned(
                  left: labelLeft,
                  width: labelWidth,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          valueLabel,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.visible,
                          style: const TextStyle(
                            color: Color(0xFFE5E7EB),
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      if (showAlert) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 14,
                          color: Color(0xFFEF4444),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: gaugeWidth,
            height: 18,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: colors),
                    ),
                  ),
                ),
                Positioned(
                  left: markerLeft,
                  child: Container(
                    width: 8,
                    height: 14,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: const Color(0xFF0F172A)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: gaugeWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatGaugeEdge(min),
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  _formatGaugeEdge(max),
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatGaugeEdge(double value) {
  final bool hasDecimals = value % 1 != 0;
  return value.toStringAsFixed(hasDecimals ? 1 : 0);
}
