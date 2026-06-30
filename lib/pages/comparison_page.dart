import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/dashboard_range_settings.dart';
import '../models/dashboard_door_event.dart';
import '../models/cerdas_models.dart';
import '../models/magnifier_settings.dart';
import '../models/munters_model.dart';
import '../models/plc_maintenance_settings.dart';
import '../models/plc_unit_diagnostics.dart';
import '../models/room_wash_event.dart';
import '../services/cerdas_repository.dart';
import '../services/room_wash_events_service.dart';
import '../widgets/cerdas_module.dart';
import '../widgets/differential_pressure_history_card.dart';
import '../widgets/door_openings_module.dart';
import '../widgets/status_indicator.dart';
import '../widgets/temperature_history_mini_charts_card.dart';

class ComparisonPage extends StatefulWidget {
  const ComparisonPage({
    super.key,
    required this.munters1,
    required this.munters2,
    required this.doorEvents,
    this.tenantId,
    this.siteId,
    required this.showMunters1,
    required this.showMunters2,
    required this.snapshotStale,
    required this.showSnapshotPulse,
    required this.rangeSettings,
    required this.magnifierSettings,
    required this.moduleOrder,
    required this.onModuleOrderChanged,
    required this.homeGeneration,
    required this.currentUser,
    this.plc1ColumnLabel,
    this.plc2ColumnLabel,
    this.plc1MaintenanceMode,
    this.plc2MaintenanceMode,
    this.onOpenEnvironmentOverview,
  });

  static const String sectionEstado = 'Estado';
  static const String sectionAmbiente = 'Ambiente';
  static const String sectionFiltros = 'Filtros';
  static const String sectionVentilacion = 'Ventilacion';
  static const String sectionEnfriamiento = 'Enfriamiento';
  static const String sectionAperturas = 'Aperturas';
  static const String sectionCalefaccion = 'Calefaccion';
  static const String sectionAlarmas = 'Alarmas';
  static const String sectionAmoniaco = 'Amoniaco';
  static const String sectionAgua = 'Agua';
  static const String sectionEnergiaE = 'EnergiaE';
  static const String sectionOee = 'Oee';
  static const String sectionProduccion = 'Produccion';
  static const String sectionCerdas = 'Cerdas';

  static const List<String> defaultModuleOrder = <String>[
    sectionEstado,
    sectionCerdas,
    sectionAmbiente,
    sectionFiltros,
    sectionVentilacion,
    sectionEnfriamiento,
    sectionAperturas,
    sectionCalefaccion,
    sectionAlarmas,
    sectionAmoniaco,
    sectionAgua,
    sectionEnergiaE,
    sectionOee,
    sectionProduccion,
  ];

  static List<String> normalizeModuleOrder(List<String> rawOrder) {
    final Set<String> allowed = defaultModuleOrder.toSet();
    final List<String> normalized = <String>[];

    void addIfAllowed(String value) {
      if (allowed.contains(value) && !normalized.contains(value)) {
        normalized.add(value);
      }
    }

    for (final String value in rawOrder) {
      if (value == 'Funcionamiento') {
        addIfAllowed(sectionEstado);
      } else if (value == 'Humidificacion') {
        addIfAllowed(sectionEnfriamiento);
      } else {
        addIfAllowed(value);
      }
    }

    for (final String value in defaultModuleOrder) {
      addIfAllowed(value);
    }
    normalized.remove(sectionCerdas);
    final int estadoIndex = normalized.indexOf(sectionEstado);
    normalized.insert(estadoIndex >= 0 ? estadoIndex + 1 : 0, sectionCerdas);
    return normalized;
  }

  final MuntersModel munters1;
  final MuntersModel munters2;
  final Map<String, DashboardDoorEvent> doorEvents;
  final String? tenantId;
  final String? siteId;
  final bool showMunters1;
  final bool showMunters2;
  final bool snapshotStale;
  final bool showSnapshotPulse;
  final DashboardRangeSettings rangeSettings;
  final MagnifierSettings magnifierSettings;
  final List<String> moduleOrder;
  final ValueChanged<List<String>> onModuleOrderChanged;
  final int homeGeneration;
  final User currentUser;
  // Column header labels from Firestore plc config. Fallback to 'M1'/'M2'.
  final String? plc1ColumnLabel;
  final String? plc2ColumnLabel;
  final PlcMaintenanceMode? plc1MaintenanceMode;
  final PlcMaintenanceMode? plc2MaintenanceMode;
  final VoidCallback? onOpenEnvironmentOverview;

  @override
  State<ComparisonPage> createState() => _ComparisonPageState();
}

class EnvironmentOverviewPage extends StatefulWidget {
  const EnvironmentOverviewPage({
    super.key,
    required this.units,
    required this.labels,
    required this.plcIds,
    required this.tenantId,
    required this.siteId,
    required this.rangeSettings,
    required this.onTapBack,
  });

  final List<MuntersModel> units;
  final List<String> labels;
  final List<String?> plcIds;
  final String? tenantId;
  final String? siteId;
  final DashboardRangeSettings rangeSettings;
  final VoidCallback onTapBack;

  @override
  State<EnvironmentOverviewPage> createState() =>
      _EnvironmentOverviewPageState();
}

enum _EnvironmentOverviewSizePreset { compact, medium, large }

class _EnvironmentOverviewPageState extends State<EnvironmentOverviewPage> {
  _EnvironmentOverviewSizePreset _sizePreset =
      _EnvironmentOverviewSizePreset.large;

  void _setSizePreset(_EnvironmentOverviewSizePreset preset) {
    setState(() {
      _sizePreset = preset;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTapBack,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'AgroData Monitor | Valke S.A.',
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      height: 1,
                    ),
                  ),
                ),
                _EnvironmentOverviewSizeButton(
                  preset: _sizePreset,
                  onChanged: _setSizePreset,
                ),
              ],
            ),
            const SizedBox(height: 6),
            _EnvironmentOverviewPresetLayout(
              preset: _sizePreset,
              units: widget.units,
              labels: widget.labels,
              plcIds: widget.plcIds,
              tenantId: widget.tenantId,
              siteId: widget.siteId,
              rangeSettings: widget.rangeSettings,
            ),
          ],
        ),
      ),
    );
  }
}

class _EnvironmentOverviewSizeButton extends StatelessWidget {
  const _EnvironmentOverviewSizeButton({
    required this.preset,
    required this.onChanged,
  });

  final _EnvironmentOverviewSizePreset preset;
  final ValueChanged<_EnvironmentOverviewSizePreset> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_EnvironmentOverviewSizePreset>(
      tooltip: 'Tamano de vista',
      initialValue: preset,
      color: const Color(0xFF111827),
      onSelected: onChanged,
      itemBuilder: (BuildContext context) {
        return const [
          PopupMenuItem<_EnvironmentOverviewSizePreset>(
            value: _EnvironmentOverviewSizePreset.compact,
            child: Text('Chico'),
          ),
          PopupMenuItem<_EnvironmentOverviewSizePreset>(
            value: _EnvironmentOverviewSizePreset.medium,
            child: Text('Medio'),
          ),
          PopupMenuItem<_EnvironmentOverviewSizePreset>(
            value: _EnvironmentOverviewSizePreset.large,
            child: Text('Grande'),
          ),
        ];
      },
      child: Container(
        width: 28,
        height: 24,
        decoration: BoxDecoration(
          color: const Color(0xFF162133),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0xFF223046)),
        ),
        child: Icon(
          switch (preset) {
            _EnvironmentOverviewSizePreset.compact =>
              Icons.close_fullscreen_rounded,
            _EnvironmentOverviewSizePreset.medium => Icons.aspect_ratio_rounded,
            _EnvironmentOverviewSizePreset.large => Icons.open_in_full_rounded,
          },
          size: 15,
          color: const Color(0xFFCBD5E1),
        ),
      ),
    );
  }
}

class _EnvironmentOverviewPresetLayout extends StatelessWidget {
  const _EnvironmentOverviewPresetLayout({
    required this.preset,
    required this.units,
    required this.labels,
    required this.plcIds,
    required this.tenantId,
    required this.siteId,
    required this.rangeSettings,
  });

  final _EnvironmentOverviewSizePreset preset;
  final List<MuntersModel> units;
  final List<String> labels;
  final List<String?> plcIds;
  final String? tenantId;
  final String? siteId;
  final DashboardRangeSettings rangeSettings;

  @override
  Widget build(BuildContext context) {
    if (preset == _EnvironmentOverviewSizePreset.compact) {
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final MuntersModel unit in units)
            SizedBox(
              width: 154,
              child: _HeaderEnvironmentCard(
                unit: unit,
                rangeSettings: rangeSettings,
                blocked: _shouldBlockOperationalData(unit),
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < units.length; i++) ...[
          if (preset == _EnvironmentOverviewSizePreset.medium)
            Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: _LargeEnvironmentUnitCard(
                  label: i < labels.length ? labels[i] : units[i].name,
                  unit: units[i],
                  tenantId: tenantId,
                  siteId: siteId,
                  plcId: i < plcIds.length ? plcIds[i] : units[i].historyPlcId,
                  rangeSettings: rangeSettings,
                  blocked: _shouldBlockOperationalData(units[i]),
                  scale: 0.72,
                ),
              ),
            )
          else
            _LargeEnvironmentUnitCard(
              label: i < labels.length ? labels[i] : units[i].name,
              unit: units[i],
              tenantId: tenantId,
              siteId: siteId,
              plcId: i < plcIds.length ? plcIds[i] : units[i].historyPlcId,
              rangeSettings: rangeSettings,
              blocked: _shouldBlockOperationalData(units[i]),
            ),
          if (i != units.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _RoomWashTarget {
  const _RoomWashTarget({
    required this.roomId,
    required this.roomNumber,
    required this.muntersId,
    required this.label,
  });

  final String roomId;
  final int roomNumber;
  final String muntersId;
  final String label;
}

class _RoomWashDraft {
  const _RoomWashDraft({required this.target, required this.washedAt});

  final _RoomWashTarget target;
  final DateTime washedAt;
}

class _RoomWashRegistrationDialog extends StatefulWidget {
  const _RoomWashRegistrationDialog({required this.targets});

  final List<_RoomWashTarget> targets;

  @override
  State<_RoomWashRegistrationDialog> createState() =>
      _RoomWashRegistrationDialogState();
}

class _RoomWashRegistrationDialogState
    extends State<_RoomWashRegistrationDialog> {
  late _RoomWashTarget _selectedTarget = widget.targets.first;
  late DateTime _washedAt = DateTime.now();

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _washedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _washedAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _washedAt.hour,
        _washedAt.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_washedAt),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _washedAt = DateTime(
        _washedAt.year,
        _washedAt.month,
        _washedAt.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  void _submit() {
    Navigator.of(
      context,
    ).pop(_RoomWashDraft(target: _selectedTarget, washedAt: _washedAt));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111827),
      title: const Text('Registrar lavado de sala'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<_RoomWashTarget>(
              initialValue: _selectedTarget,
              dropdownColor: const Color(0xFF111827),
              decoration: const InputDecoration(labelText: 'Sala lavada'),
              items: [
                for (final _RoomWashTarget target in widget.targets)
                  DropdownMenuItem<_RoomWashTarget>(
                    value: target,
                    child: Text(target.label),
                  ),
              ],
              onChanged: (_RoomWashTarget? value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _selectedTarget = value;
                });
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_rounded, size: 16),
                    label: Text(_formatWashDate(_washedAt)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule_rounded, size: 16),
                    label: Text(_formatWashTime(_washedAt)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}

String _formatWashDate(DateTime value) {
  return '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.year}';
}

String _formatWashTime(DateTime value) {
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

class _ComparisonPageState extends State<ComparisonPage> {
  static const Duration _technicalDataAutoCollapseDelay = Duration(minutes: 5);
  static const Duration _sectionsAutoCollapseDelay = Duration(minutes: 10);
  static const RoomWashEventsService _roomWashEventsService =
      RoomWashEventsService();
  static const String _sectionFuncionamiento = ComparisonPage.sectionEstado;
  static const String _sectionAmbiente = ComparisonPage.sectionAmbiente;
  static const String _sectionFiltros = ComparisonPage.sectionFiltros;
  static const String _sectionVentilacion = ComparisonPage.sectionVentilacion;
  static const String _sectionHumidificacion =
      ComparisonPage.sectionEnfriamiento;
  static const String _sectionAperturas = ComparisonPage.sectionAperturas;
  static const String _sectionCalefaccion = ComparisonPage.sectionCalefaccion;
  static const String _sectionAlarmas = ComparisonPage.sectionAlarmas;
  static const String _sectionAmoniaco = ComparisonPage.sectionAmoniaco;
  static const String _sectionAgua = ComparisonPage.sectionAgua;
  static const String _sectionEnergiaE = ComparisonPage.sectionEnergiaE;
  static const String _sectionOee = ComparisonPage.sectionOee;
  static const String _sectionProduccion = ComparisonPage.sectionProduccion;
  static const String _sectionCerdas = ComparisonPage.sectionCerdas;

  Timer? _technicalDataAutoCollapseTimer;
  Timer? _sectionsAutoCollapseTimer;
  bool _technicalDataExpanded = false;
  final bool _munters1Collapsed = false;
  final bool _munters2Collapsed = false;
  bool _reorderEnabled = false;
  bool _alarmasAutoExpandQueued = false;
  int _sectionsCollapseGeneration = 0;
  final Map<String, int> _sectionExpandRequests = <String, int>{};
  final Set<String> _expandedSectionIds = <String>{};
  final Map<String, GlobalKey> _sectionKeys = <String, GlobalKey>{
    _sectionFuncionamiento: GlobalKey(),
    _sectionAmbiente: GlobalKey(),
    _sectionFiltros: GlobalKey(),
    _sectionVentilacion: GlobalKey(),
    _sectionHumidificacion: GlobalKey(),
    _sectionAperturas: GlobalKey(),
    _sectionCalefaccion: GlobalKey(),
    _sectionAlarmas: GlobalKey(),
    _sectionAmoniaco: GlobalKey(),
    _sectionAgua: GlobalKey(),
    _sectionEnergiaE: GlobalKey(),
    _sectionOee: GlobalKey(),
    _sectionProduccion: GlobalKey(),
    _sectionCerdas: GlobalKey(),
  };

  @override
  void dispose() {
    _technicalDataAutoCollapseTimer?.cancel();
    _sectionsAutoCollapseTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ComparisonPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.homeGeneration != oldWidget.homeGeneration) {
      _sectionsAutoCollapseTimer?.cancel();
      setState(() {
        _sectionsCollapseGeneration += 1;
        _expandedSectionIds.clear();
      });
    }
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
        _sectionsCollapseGeneration += 1;
        _expandedSectionIds.clear();
      });
    });
  }

  void _handleSectionExpandedChanged(
    String sectionId, {
    required bool expanded,
    int? plcIndex,
  }) {
    setState(() {
      if (expanded) {
        _expandedSectionIds.add(sectionId);
      } else {
        _expandedSectionIds.remove(sectionId);
      }
    });
    if (expanded) {
      _handleSectionExpanded();
    }
  }

  void _focusSection(String sectionId) {
    setState(() {
      _sectionExpandRequests[sectionId] =
          (_sectionExpandRequests[sectionId] ?? 0) + 1;
      _expandedSectionIds.add(sectionId);
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

  List<_RoomWashTarget> _roomWashTargets() {
    return <_RoomWashTarget>[
      if (widget.showMunters1)
        _RoomWashTarget(
          roomId: 'room_1',
          roomNumber: 1,
          muntersId: widget.munters1.historyPlcId ?? 'munters1',
          label: 'Sala 1',
        ),
      if (widget.showMunters2)
        _RoomWashTarget(
          roomId: 'room_2',
          roomNumber: 2,
          muntersId: widget.munters2.historyPlcId ?? 'munters2',
          label: 'Sala 2',
        ),
    ];
  }

  Future<void> _openRoomWashDialog() async {
    final String? tenantId = widget.tenantId;
    final String? siteId = widget.siteId;
    if (tenantId == null ||
        tenantId.isEmpty ||
        siteId == null ||
        siteId.isEmpty) {
      _showRoomWashMessage('No hay contexto de granja/sala para guardar.');
      return;
    }

    final List<_RoomWashTarget> targets = _roomWashTargets();
    if (targets.isEmpty) {
      _showRoomWashMessage('No hay salas visibles para registrar lavado.');
      return;
    }

    final _RoomWashDraft? draft = await showDialog<_RoomWashDraft>(
      context: context,
      builder: (BuildContext context) {
        return _RoomWashRegistrationDialog(targets: targets);
      },
    );
    if (draft == null) {
      return;
    }

    final User user = widget.currentUser;
    final String createdByName = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : (user.email?.trim().isNotEmpty == true
              ? user.email!.trim()
              : user.uid);
    final RoomWashEvent event = RoomWashEvent(
      tenantId: tenantId,
      roomId: draft.target.roomId,
      roomNumber: draft.target.roomNumber,
      muntersId: draft.target.muntersId,
      washedAt: draft.washedAt,
      createdByUid: user.uid,
      createdByName: createdByName,
      source: RoomWashEvent.operatorSource,
    );

    try {
      await _roomWashEventsService.create(
        tenantId: tenantId,
        siteId: siteId,
        event: event,
      );
      if (!mounted) {
        return;
      }
      _showRoomWashMessage('Lavado registrado para ${draft.target.label}.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showRoomWashMessage('No se pudo registrar el lavado: $error');
    }
  }

  void _showRoomWashMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  void _queueAlarmasAutoExpand() {
    if (_alarmasAutoExpandQueued) {
      return;
    }
    _alarmasAutoExpandQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _alarmasAutoExpandQueued = false;
      if (!mounted || _expandedSectionIds.contains(_sectionAlarmas)) {
        return;
      }
      setState(() {
        _sectionExpandRequests[_sectionAlarmas] =
            (_sectionExpandRequests[_sectionAlarmas] ?? 0) + 1;
        _expandedSectionIds.add(_sectionAlarmas);
      });
      _handleSectionExpanded();
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
    final _WitnessDotVisual m1WitnessVisual = _resolvePlcWitnessVisual(
      <MuntersModel>[munters1],
    );
    final _WitnessDotVisual m2WitnessVisual = _resolvePlcWitnessVisual(
      <MuntersModel>[munters2],
    );
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
    final _ModuleStatus filtrosStatus = _resolveFiltrosStatus(
      munters1,
      munters2,
      rangeSettings,
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
    _resolveAlarmasStatus(
      functioningStatus: functioningStatus,
      environmentStatus: environmentStatus,
      filtrosStatus: filtrosStatus,
      ventilationStatus: ventilationStatus,
      humidificationStatus: humidificationStatus,
      aperturasStatus: aperturasStatus,
      calefaccionStatus: calefaccionStatus,
      hasAlarmOutput: hasAlarm,
    );

    // Per-PLC icon data
    Color funcIconColor(_ModuleStatus s) => switch (s.kind) {
      _ModuleStatusKind.alert ||
      _ModuleStatusKind.error => const Color(0xFFEF4444),
      _ModuleStatusKind.ok => const Color(0xFF22C55E),
      _ => const Color(0xFF94A3B8),
    };
    final _ModuleStatus m1FuncStatus = _resolveFunctioningStatusForUnit(
      munters1,
    );
    final _ModuleStatus m2FuncStatus = _resolveFunctioningStatusForUnit(
      munters2,
    );
    final List<_PlcModuleIconData> funcionamientoPlcIconData =
        <_PlcModuleIconData>[
          _PlcModuleIconData(
            icon: Icons.power_settings_new,
            iconColor: funcIconColor(m1FuncStatus),
            status: m1FuncStatus,
            witnessVisual: m1WitnessVisual,
            showPulseDot: widget.showSnapshotPulse,
            pulseDotBackendAlive: !widget.snapshotStale,
            pulseDotColor: _isPlcStopState(munters1)
                ? const Color(0xFFF59E0B)
                : const Color(0xFF22C55E),
          ),
          _PlcModuleIconData(
            icon: Icons.power_settings_new,
            iconColor: funcIconColor(m2FuncStatus),
            status: m2FuncStatus,
            witnessVisual: m2WitnessVisual,
            showPulseDot: widget.showSnapshotPulse,
            pulseDotBackendAlive: !widget.snapshotStale,
            pulseDotColor: _isPlcStopState(munters2)
                ? const Color(0xFFF59E0B)
                : const Color(0xFF22C55E),
          ),
        ];
    final List<_PlcModuleIconData> ambientePlcIconData = <_PlcModuleIconData>[
      _PlcModuleIconData(
        icon: Icons.thermostat,
        iconColor: _resolveEnvironmentIconColorForUnit(
          unit: munters1,
          rangeSettings: rangeSettings,
        ),
        status: _resolveEnvironmentStatusForUnit(
          unit: munters1,
          rangeSettings: rangeSettings,
        ),
        extraWidget: _EnvironmentHeaderExtra(
          temperature: munters1DataBlocked ? null : munters1.tempInterior,
          visual: _resolveEnvironmentHumidityVisualForUnit(
            unit: munters1,
            rangeSettings: rangeSettings,
          ),
        ),
      ),
      _PlcModuleIconData(
        icon: Icons.thermostat,
        iconColor: _resolveEnvironmentIconColorForUnit(
          unit: munters2,
          rangeSettings: rangeSettings,
        ),
        status: _resolveEnvironmentStatusForUnit(
          unit: munters2,
          rangeSettings: rangeSettings,
        ),
        extraWidget: _EnvironmentHeaderExtra(
          temperature: munters2DataBlocked ? null : munters2.tempInterior,
          visual: _resolveEnvironmentHumidityVisualForUnit(
            unit: munters2,
            rangeSettings: rangeSettings,
          ),
        ),
      ),
    ];
    final List<_PlcModuleIconData> filtrosPlcIconData = <_PlcModuleIconData>[
      _PlcModuleIconData(
        icon: Icons.filter_alt_rounded,
        iconColor: _resolveFiltrosIconColorForUnit(munters1, rangeSettings),
        status: _resolveFiltrosStatusForUnit(munters1, rangeSettings),
        iconWidget: _SquareAirFilterIcon(
          color: _resolveFiltrosIconColorForUnit(munters1, rangeSettings),
          denseMesh: true,
        ),
        extraWidget: _FilterHeaderPressureValue(
          pressure: munters1DataBlocked ? null : munters1.presionDiferencial,
        ),
      ),
      _PlcModuleIconData(
        icon: Icons.filter_alt_rounded,
        iconColor: _resolveFiltrosIconColorForUnit(munters2, rangeSettings),
        status: _resolveFiltrosStatusForUnit(munters2, rangeSettings),
        iconWidget: _SquareAirFilterIcon(
          color: _resolveFiltrosIconColorForUnit(munters2, rangeSettings),
          denseMesh: true,
        ),
        extraWidget: _FilterHeaderPressureValue(
          pressure: munters2DataBlocked ? null : munters2.presionDiferencial,
        ),
      ),
    ];
    final List<_PlcModuleIconData>
    ventilacionPlcIconData = <_PlcModuleIconData>[
      _PlcModuleIconData(
        icon: Icons.cyclone_rounded,
        iconColor: _resolveVentilationIconColorForUnit(munters1),
        status: _resolveVentilationStatusForUnit(munters1),
        spinning: _isVentilationFullyRunning(munters1),
        extraWidget: _VentilationHeaderPowerValue(
          value: munters1DataBlocked
              ? null
              : _normalizeVoltageToPercent(munters1.tensionSalidaVentiladores),
        ),
      ),
      _PlcModuleIconData(
        icon: Icons.cyclone_rounded,
        iconColor: _resolveVentilationIconColorForUnit(munters2),
        status: _resolveVentilationStatusForUnit(munters2),
        spinning: _isVentilationFullyRunning(munters2),
        extraWidget: _VentilationHeaderPowerValue(
          value: munters2DataBlocked
              ? null
              : _normalizeVoltageToPercent(munters2.tensionSalidaVentiladores),
        ),
      ),
    ];
    final List<_PlcModuleIconData>
    humidificacionPlcIconData = <_PlcModuleIconData>[
      _PlcModuleIconData(
        icon: Icons.power_settings_new,
        iconColor: !munters1DataBlocked && munters1.bombaHumidificador == true
            ? const Color(0xFF22C55E)
            : const Color(0xFF94A3B8),
        status: _resolveHumidificationStatusForUnit(munters1, rangeSettings),
        extraWidget: _OnOffHeaderValue(
          active: munters1DataBlocked ? null : munters1.bombaHumidificador,
        ),
      ),
      _PlcModuleIconData(
        icon: Icons.power_settings_new,
        iconColor: !munters2DataBlocked && munters2.bombaHumidificador == true
            ? const Color(0xFF22C55E)
            : const Color(0xFF94A3B8),
        status: _resolveHumidificationStatusForUnit(munters2, rangeSettings),
        extraWidget: _OnOffHeaderValue(
          active: munters2DataBlocked ? null : munters2.bombaHumidificador,
        ),
      ),
    ];
    final List<_PlcModuleIconData> aperturasPlcIconData = <_PlcModuleIconData>[
      _PlcModuleIconData(
        icon: _hasDoorAlarm(munters1)
            ? Icons.meeting_room_outlined
            : Icons.door_front_door_outlined,
        iconColor: _hasDoorAlarm(munters1)
            ? const Color(0xFFFACC15)
            : const Color(0xFF94A3B8),
        status: _resolveAperturasStatusForUnit(munters1),
      ),
      _PlcModuleIconData(
        icon: _hasDoorAlarm(munters2)
            ? Icons.meeting_room_outlined
            : Icons.door_front_door_outlined,
        iconColor: _hasDoorAlarm(munters2)
            ? const Color(0xFFFACC15)
            : const Color(0xFF94A3B8),
        status: _resolveAperturasStatusForUnit(munters2),
      ),
    ];
    final List<_PlcModuleIconData>
    calefaccionPlcIconData = <_PlcModuleIconData>[
      _PlcModuleIconData(
        icon: Icons.local_fire_department,
        iconColor:
            !munters1DataBlocked &&
                (munters1.resistencia1 == true || munters1.resistencia2 == true)
            ? const Color(0xFFEF4444)
            : const Color(0xFF94A3B8),
        status: _resolveCalefaccionStatusForUnit(munters1, rangeSettings),
        extraWidget: _OnOffHeaderValue(
          active: munters1DataBlocked ? null : _hasAnyHeatingOn(munters1),
        ),
      ),
      _PlcModuleIconData(
        icon: Icons.local_fire_department,
        iconColor:
            !munters2DataBlocked &&
                (munters2.resistencia1 == true || munters2.resistencia2 == true)
            ? const Color(0xFFEF4444)
            : const Color(0xFF94A3B8),
        status: _resolveCalefaccionStatusForUnit(munters2, rangeSettings),
        extraWidget: _OnOffHeaderValue(
          active: munters2DataBlocked ? null : _hasAnyHeatingOn(munters2),
        ),
      ),
    ];
    final _ModuleStatus m1AlarmasStatus = _resolveAlarmasStatusForUnit(
      munters1,
      rangeSettings,
    );
    final _ModuleStatus m2AlarmasStatus = _resolveAlarmasStatusForUnit(
      munters2,
      rangeSettings,
    );
    final List<_PlcModuleIconData> alarmasPlcIconData = <_PlcModuleIconData>[
      _PlcModuleIconData(
        icon: Icons.warning_amber_rounded,
        iconColor: _isModuleStatusAlarm(m1AlarmasStatus)
            ? const Color(0xFFFACC15)
            : const Color(0xFF94A3B8),
        status: m1AlarmasStatus,
      ),
      _PlcModuleIconData(
        icon: Icons.warning_amber_rounded,
        iconColor: _isModuleStatusAlarm(m2AlarmasStatus)
            ? const Color(0xFFFACC15)
            : const Color(0xFF94A3B8),
        status: m2AlarmasStatus,
      ),
    ];

    final Widget funcionamientoSection = _SectionTable(
      key: _sectionKeys[_sectionFuncionamiento],
      sectionId: _sectionFuncionamiento,
      title: 'ESTADO',
      plcIconData: funcionamientoPlcIconData,
      collapseGeneration: _sectionsCollapseGeneration,
      expandRequestGeneration:
          _sectionExpandRequests[_sectionFuncionamiento] ?? 0,
      onExpandedChanged: _handleSectionExpandedChanged,
      rows: [
        _ComparisonRow(
          label: 'Nombre',
          munters1: _TextValue(widget.munters1.name),
          munters2: _TextValue(widget.munters2.name),
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
            munters1DataBlocked
                ? '-'
                : _formatInt(widget.munters1.cantidadApagadas),
          ),
          munters2: _TextValue(
            munters2DataBlocked
                ? '-'
                : _formatInt(widget.munters2.cantidadApagadas),
          ),
        ),
        _ComparisonTechnicalDataGroup(
          expanded: _technicalDataExpanded,
          onToggle: () => _setTechnicalDataExpanded(!_technicalDataExpanded),
          rows: [
            _ComparisonRow(
              label: 'Latency PLC',
              munters1: _TextValue(
                _formatIntWithUnit(widget.munters1.plcLatencyMs, 'ms'),
                fontWeight: FontWeight.w400,
              ),
              munters2: _TextValue(
                _formatIntWithUnit(widget.munters2.plcLatencyMs, 'ms'),
                fontWeight: FontWeight.w400,
              ),
            ),
            _ComparisonRow(
              label: 'Latency ER605',
              munters1: _TextValue(
                _formatIntWithUnit(widget.munters1.routerLatencyMs, 'ms'),
                fontWeight: FontWeight.w400,
              ),
              munters2: _TextValue(
                _formatIntWithUnit(widget.munters2.routerLatencyMs, 'ms'),
                fontWeight: FontWeight.w400,
              ),
            ),
            _ComparisonRow(
              label: 'Backend',
              munters1: _StateValue(
                active: munters1DataBlocked
                    ? null
                    : widget.munters1.backendOnline,
                activeLabel: 'on-line',
                inactiveLabel: 'off-line',
                activeColor: const Color(0xFF22C55E),
                inactiveColor: const Color(0xFFEF4444),
                fontWeight: FontWeight.w400,
              ),
              munters2: _StateValue(
                active: munters2DataBlocked
                    ? null
                    : widget.munters2.backendOnline,
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
                    : _formatPreviousLastUpdated(
                        widget.munters1.previousLastUpdatedAt,
                      ),
                fontWeight: FontWeight.w400,
              ),
              munters2: _TextValue(
                munters2DataBlocked
                    ? '-'
                    : _formatPreviousLastUpdated(
                        widget.munters2.previousLastUpdatedAt,
                      ),
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
      sectionId: _sectionAmbiente,
      title: 'AMBIENTE',
      plcIconData: ambientePlcIconData,
      collapseGeneration: _sectionsCollapseGeneration,
      expandRequestGeneration: _sectionExpandRequests[_sectionAmbiente] ?? 0,
      onExpandedChanged: _handleSectionExpandedChanged,
      rows: [
        _EnvironmentTemperatureBlock(
          munters1: munters1,
          munters2: munters2,
          rangeSettings: rangeSettings,
          munters1Blocked: munters1DataBlocked,
          munters2Blocked: munters2DataBlocked,
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
            unit: munters1,
            min: rangeSettings.humidityMin,
            max: rangeSettings.humidityMax,
            blocked: munters1DataBlocked,
          ),
          munters2: _HumidityValue(
            unit: munters2,
            min: rangeSettings.humidityMin,
            max: rangeSettings.humidityMax,
            blocked: munters2DataBlocked,
          ),
        ),
        _ComparisonRow(
          label: 'Humedad exterior',
          munters1: _TextValue(
            munters1DataBlocked
                ? '-'
                : _formatValueWithUnit(munters1.displayHumExterior, '%'),
          ),
          munters2: _TextValue(
            munters2DataBlocked
                ? '-'
                : _formatValueWithUnit(munters2.displayHumExterior, '%'),
          ),
        ),
        _ComparisonRow(
          label: 'NH3',
          munters1: _TextValue(
            munters1DataBlocked
                ? '-'
                : _formatValueWithUnit(munters1.nh3, 'ppm'),
          ),
          munters2: _TextValue(
            munters2DataBlocked
                ? '-'
                : _formatValueWithUnit(munters2.nh3, 'ppm'),
          ),
        ),
      ],
    );
    final Widget filtrosSection = _SectionTable(
      key: _sectionKeys[_sectionFiltros],
      sectionId: _sectionFiltros,
      title: 'FILTROS',
      plcIconData: filtrosPlcIconData,
      collapseGeneration: _sectionsCollapseGeneration,
      expandRequestGeneration: _sectionExpandRequests[_sectionFiltros] ?? 0,
      onExpandedChanged: _handleSectionExpandedChanged,
      rows: [
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
          label: '',
          alignToTop: true,
          munters1: _DifferentialPressureHistoryValue(
            unitName: munters1.name,
            tenantId: widget.tenantId,
            siteId: widget.siteId,
            plcId: munters1.historyPlcId,
            blocked: munters1DataBlocked,
          ),
          munters2: _DifferentialPressureHistoryValue(
            unitName: munters2.name,
            tenantId: widget.tenantId,
            siteId: widget.siteId,
            plcId: munters2.historyPlcId,
            blocked: munters2DataBlocked,
          ),
        ),
        _ComparisonRow(
          label: 'Seteo alarma',
          munters1: _TextValue(
            _formatValueWithUnit(rangeSettings.filterPressureMax, 'Pa'),
            fontWeight: FontWeight.w400,
          ),
          munters2: _TextValue(
            _formatValueWithUnit(rangeSettings.filterPressureMax, 'Pa'),
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
    final Widget ventilacionSection = _SectionTable(
      key: _sectionKeys[_sectionVentilacion],
      sectionId: _sectionVentilacion,
      title: 'VENTILACION',
      plcIconData: ventilacionPlcIconData,
      collapseGeneration: _sectionsCollapseGeneration,
      expandRequestGeneration: _sectionExpandRequests[_sectionVentilacion] ?? 0,
      onExpandedChanged: _handleSectionExpandedChanged,
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
                : _normalizeVoltageToPercent(
                    munters1.tensionSalidaVentiladores,
                  ),
            blocked: munters1DataBlocked,
          ),
          munters2: _BarValue(
            value: munters2DataBlocked
                ? null
                : _normalizeVoltageToPercent(
                    munters2.tensionSalidaVentiladores,
                  ),
            blocked: munters2DataBlocked,
          ),
        ),
      ],
    );
    final Widget humidificacionSection = _SectionTable(
      key: _sectionKeys[_sectionHumidificacion],
      sectionId: _sectionHumidificacion,
      title: 'ENFRIAMIENTO',
      plcIconData: humidificacionPlcIconData,
      collapseGeneration: _sectionsCollapseGeneration,
      expandRequestGeneration:
          _sectionExpandRequests[_sectionHumidificacion] ?? 0,
      onExpandedChanged: _handleSectionExpandedChanged,
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
      sectionId: _sectionAperturas,
      title: 'APERTURAS',
      plcIconData: aperturasPlcIconData,
      collapseGeneration: _sectionsCollapseGeneration,
      expandRequestGeneration: _sectionExpandRequests[_sectionAperturas] ?? 0,
      onExpandedChanged: _handleSectionExpandedChanged,
      rows: [
        DoorOpeningsModule(
          tenantId: widget.tenantId,
          siteId: widget.siteId,
          doorEvents: widget.doorEvents,
        ),
      ],
    );
    final Widget calefaccionSection = _SectionTable(
      key: _sectionKeys[_sectionCalefaccion],
      sectionId: _sectionCalefaccion,
      title: 'CALEFACCION',
      plcIconData: calefaccionPlcIconData,
      collapseGeneration: _sectionsCollapseGeneration,
      expandRequestGeneration: _sectionExpandRequests[_sectionCalefaccion] ?? 0,
      onExpandedChanged: _handleSectionExpandedChanged,
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
      sectionId: _sectionAlarmas,
      title: 'ALARMAS',
      plcIconData: alarmasPlcIconData,
      collapseGeneration: _sectionsCollapseGeneration,
      expandRequestGeneration: _sectionExpandRequests[_sectionAlarmas] ?? 0,
      onExpandedChanged: _handleSectionExpandedChanged,
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
    final List<_PlcModuleIconData> amoniacoPlcIconData = <_PlcModuleIconData>[
      _PlcModuleIconData(
        icon: Icons.air,
        iconColor: const Color(0xFF94A3B8),
        status: const _ModuleStatus.pending(),
      ),
      _PlcModuleIconData(
        icon: Icons.air,
        iconColor: const Color(0xFF94A3B8),
        status: const _ModuleStatus.pending(),
      ),
    ];
    final Widget amoniacoSection = _SectionTable(
      key: _sectionKeys[_sectionAmoniaco],
      sectionId: _sectionAmoniaco,
      title: 'AMONIACO',
      plcIconData: amoniacoPlcIconData,
      collapseGeneration: _sectionsCollapseGeneration,
      expandRequestGeneration: _sectionExpandRequests[_sectionAmoniaco] ?? 0,
      onExpandedChanged: _handleSectionExpandedChanged,
      rows: [
        _ComparisonRow(
          label: 'NH3',
          munters1: const _TextValue('Sin datos'),
          munters2: const _TextValue('Sin datos'),
        ),
        _ComparisonRow(
          label: 'Seteo Alarma',
          munters1: const _TextValue('Sin datos'),
          munters2: const _TextValue('Sin datos'),
        ),
        _ComparisonRow(
          label: 'Gráfico',
          munters1: const _TextValue('Sin datos'),
          munters2: const _TextValue('Sin datos'),
        ),
      ],
    );
    final List<_PlcModuleIconData> aguaPlcIconData = <_PlcModuleIconData>[
      _PlcModuleIconData(
        icon: Icons.water_drop_outlined,
        iconColor: const Color(0xFF94A3B8),
        status: const _ModuleStatus.pending(),
      ),
      _PlcModuleIconData(
        icon: Icons.water_drop_outlined,
        iconColor: const Color(0xFF94A3B8),
        status: const _ModuleStatus.pending(),
      ),
    ];
    final Widget aguaSection = _SectionTable(
      key: _sectionKeys[_sectionAgua],
      sectionId: _sectionAgua,
      title: 'AGUA',
      plcIconData: aguaPlcIconData,
      collapseGeneration: _sectionsCollapseGeneration,
      expandRequestGeneration: _sectionExpandRequests[_sectionAgua] ?? 0,
      onExpandedChanged: _handleSectionExpandedChanged,
      rows: [
        _ComparisonRow(
          label: 'Litros Consumidos',
          munters1: const _TextValue('Sin datos'),
          munters2: const _TextValue('Sin datos'),
        ),
      ],
    );
    final List<_PlcModuleIconData> energiaEPlcIconData = <_PlcModuleIconData>[
      _PlcModuleIconData(
        icon: Icons.bolt,
        iconColor: const Color(0xFF94A3B8),
        status: const _ModuleStatus.pending(),
      ),
      _PlcModuleIconData(
        icon: Icons.bolt,
        iconColor: const Color(0xFF94A3B8),
        status: const _ModuleStatus.pending(),
      ),
    ];
    final Widget energiaESection = _SectionTable(
      key: _sectionKeys[_sectionEnergiaE],
      sectionId: _sectionEnergiaE,
      title: 'ENERGIA E.',
      plcIconData: energiaEPlcIconData,
      collapseGeneration: _sectionsCollapseGeneration,
      expandRequestGeneration: _sectionExpandRequests[_sectionEnergiaE] ?? 0,
      onExpandedChanged: _handleSectionExpandedChanged,
      rows: [
        _ComparisonRow(
          label: 'Potencia Ventilación',
          munters1: const _DashWithUnitValue('kW'),
          munters2: const _DashWithUnitValue('kW'),
        ),
        _ComparisonRow(
          label: 'Potencia Enfriamiento',
          munters1: const _DashWithUnitValue('kW'),
          munters2: const _DashWithUnitValue('kW'),
        ),
        _ComparisonRow(
          label: 'Potencia Calefacción',
          munters1: const _DashWithUnitValue('kW'),
          munters2: const _DashWithUnitValue('kW'),
        ),
        _ComparisonRow(
          label: 'Potencia Diaria',
          munters1: const _DashWithUnitValue('kWh'),
          munters2: const _DashWithUnitValue('kWh'),
        ),
      ],
    );
    final List<_PlcModuleIconData> oeePlcIconData = <_PlcModuleIconData>[
      _PlcModuleIconData(
        icon: Icons.speed,
        iconColor: const Color(0xFF94A3B8),
        status: const _ModuleStatus.pending(),
      ),
      _PlcModuleIconData(
        icon: Icons.speed,
        iconColor: const Color(0xFF94A3B8),
        status: const _ModuleStatus.pending(),
      ),
    ];
    final Widget oeeSection = _SectionTable(
      key: _sectionKeys[_sectionOee],
      sectionId: _sectionOee,
      title: 'OEE',
      plcIconData: oeePlcIconData,
      collapseGeneration: _sectionsCollapseGeneration,
      expandRequestGeneration: _sectionExpandRequests[_sectionOee] ?? 0,
      onExpandedChanged: _handleSectionExpandedChanged,
      rows: const [],
    );
    final List<_PlcModuleIconData> produccionPlcIconData = <_PlcModuleIconData>[
      _PlcModuleIconData(
        icon: Icons.factory_outlined,
        iconColor: const Color(0xFF94A3B8),
        status: const _ModuleStatus.pending(),
      ),
      _PlcModuleIconData(
        icon: Icons.factory_outlined,
        iconColor: const Color(0xFF94A3B8),
        status: const _ModuleStatus.pending(),
      ),
    ];
    final Widget produccionSection = _SectionTable(
      key: _sectionKeys[_sectionProduccion],
      sectionId: _sectionProduccion,
      title: 'PRODUCCION',
      plcIconData: produccionPlcIconData,
      collapseGeneration: _sectionsCollapseGeneration,
      expandRequestGeneration: _sectionExpandRequests[_sectionProduccion] ?? 0,
      onExpandedChanged: _handleSectionExpandedChanged,
      rows: const [],
    );
    final String? cerdasTenantId = widget.tenantId;
    final String? cerdasSiteId = widget.siteId;
    final String? cerdasPlc1Id = widget.munters1.historyPlcId;
    final String? cerdasPlc2Id = widget.munters2.historyPlcId;
    final bool cerdasHasContext =
        cerdasTenantId != null &&
        cerdasTenantId.isNotEmpty &&
        cerdasSiteId != null &&
        cerdasSiteId.isNotEmpty;
    final List<_PlcModuleIconData> cerdasPlcIconData = <_PlcModuleIconData>[
      _PlcModuleIconData(
        icon: Icons.pets,
        iconColor: const Color(0xFF94A3B8),
        status: const _ModuleStatus.pending(),
        extraWidget:
            cerdasHasContext && cerdasPlc1Id != null && cerdasPlc1Id.isNotEmpty
            ? CerdasPigCountWidget(
                tenantId: cerdasTenantId,
                siteId: cerdasSiteId,
                plcId: cerdasPlc1Id,
              )
            : null,
      ),
      _PlcModuleIconData(
        icon: Icons.pets,
        iconColor: const Color(0xFF94A3B8),
        status: const _ModuleStatus.pending(),
        extraWidget:
            cerdasHasContext && cerdasPlc2Id != null && cerdasPlc2Id.isNotEmpty
            ? CerdasPigCountWidget(
                tenantId: cerdasTenantId,
                siteId: cerdasSiteId,
                plcId: cerdasPlc2Id,
              )
            : null,
      ),
    ];
    final Widget cerdasSection = _SectionTable(
      key: _sectionKeys[_sectionCerdas],
      sectionId: _sectionCerdas,
      title: 'CERDAS',
      plcIconData: cerdasPlcIconData,
      collapseGeneration: _sectionsCollapseGeneration,
      expandRequestGeneration: _sectionExpandRequests[_sectionCerdas] ?? 0,
      onExpandedChanged: _handleSectionExpandedChanged,
      rows: <Widget>[
        CerdasModule(
          tenantId: widget.tenantId,
          siteId: widget.siteId,
          plc1Id: cerdasPlc1Id,
          plc2Id: cerdasPlc2Id,
          plc1Label: widget.plc1ColumnLabel ?? 'M1',
          plc2Label: widget.plc2ColumnLabel ?? 'M2',
        ),
      ],
    );
    final bool hasAnyModuleAlarm =
        _isModuleStatusAlarm(m1AlarmasStatus) ||
        _isModuleStatusAlarm(m2AlarmasStatus);
    if (hasAnyModuleAlarm && !_expandedSectionIds.contains(_sectionAlarmas)) {
      _queueAlarmasAutoExpand();
    }
    final Map<String, Widget> sectionById = <String, Widget>{
      _sectionFuncionamiento: funcionamientoSection,
      _sectionAmbiente: ambienteSection,
      _sectionFiltros: filtrosSection,
      _sectionVentilacion: ventilacionSection,
      _sectionHumidificacion: humidificacionSection,
      _sectionAperturas: estadosMecanicosSection,
      _sectionCalefaccion: calefaccionSection,
      _sectionAlarmas: alarmasSection,
      _sectionAmoniaco: amoniacoSection,
      _sectionAgua: aguaSection,
      _sectionEnergiaE: energiaESection,
      _sectionOee: oeeSection,
      _sectionProduccion: produccionSection,
      _sectionCerdas: cerdasSection,
    };
    final List<String> storedModuleIds = ComparisonPage.normalizeModuleOrder(
      widget.moduleOrder,
    );
    final List<String> orderedModuleIds = hasAnyModuleAlarm
        ? <String>[
            _sectionAlarmas,
            ...storedModuleIds.where((String id) => id != _sectionAlarmas),
          ]
        : storedModuleIds;
    final List<Widget> orderedSections = orderedModuleIds
        .asMap()
        .entries
        .map((MapEntry<int, String> entry) {
          final int index = entry.key;
          final String id = entry.value;
          final bool canDragSection =
              _reorderEnabled && !(hasAnyModuleAlarm && id == _sectionAlarmas);
          return Container(
            key: ValueKey<String>(id),
            margin: const EdgeInsets.only(bottom: 8),
            child: _ComparisonColumnsScope(
              showMunters1: widget.showMunters1,
              showMunters2: widget.showMunters2,
              plc1ColumnLabel: widget.plc1ColumnLabel ?? 'M1',
              plc2ColumnLabel: widget.plc2ColumnLabel ?? 'M2',
              munters1Collapsed: _munters1Collapsed,
              munters2Collapsed: _munters2Collapsed,
              child: Stack(
                children: [
                  sectionById[id]!,
                  if (canDragSection)
                    Positioned(
                      top: 10,
                      left: 6,
                      child: ReorderableDragStartListener(
                        index: index,
                        child: const _SectionDragHandle(),
                      ),
                    ),
                ],
              ),
            ),
          );
        })
        .toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TableHeader(
                      showMunters1: widget.showMunters1,
                      showMunters2: widget.showMunters2,
                      plc1ColumnLabel: widget.plc1ColumnLabel ?? 'M1',
                      plc2ColumnLabel: widget.plc2ColumnLabel ?? 'M2',
                      munters1: munters1,
                      munters2: munters2,
                      rangeSettings: rangeSettings,
                      munters1Blocked: munters1DataBlocked,
                      munters2Blocked: munters2DataBlocked,
                      plc1MaintenanceMode: widget.plc1MaintenanceMode,
                      plc2MaintenanceMode: widget.plc2MaintenanceMode,
                      magnifierSettings: widget.magnifierSettings,
                      reorderEnabled: _reorderEnabled,
                      onOpenEnvironmentOverview:
                          widget.onOpenEnvironmentOverview,
                      onRegisterRoomWash: _openRoomWashDialog,
                      onToggleReorder: () {
                        setState(() {
                          _reorderEnabled = !_reorderEnabled;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ReorderableListView(
                        padding: EdgeInsets.zero,
                        buildDefaultDragHandles: false,
                        proxyDecorator:
                            (
                              Widget child,
                              int index,
                              Animation<double> animation,
                            ) {
                              return AnimatedBuilder(
                                animation: animation,
                                child: child,
                                builder: (BuildContext context, Widget? child) {
                                  return Material(
                                    type: MaterialType.transparency,
                                    child: Opacity(opacity: 0.96, child: child),
                                  );
                                },
                              );
                            },
                        onReorder: (int oldIndex, int newIndex) {
                          final List<String> nextOrder = List<String>.from(
                            orderedModuleIds,
                          );
                          if (newIndex > oldIndex) {
                            newIndex -= 1;
                          }
                          final String moved = nextOrder.removeAt(oldIndex);
                          nextOrder.insert(newIndex, moved);
                          if (hasAnyModuleAlarm) {
                            final int alarmStoredIndex = storedModuleIds
                                .indexOf(_sectionAlarmas);
                            nextOrder.remove(_sectionAlarmas);
                            final int insertionIndex = alarmStoredIndex.clamp(
                              0,
                              nextOrder.length,
                            );
                            nextOrder.insert(insertionIndex, _sectionAlarmas);
                          }
                          widget.onModuleOrderChanged(nextOrder);
                        },
                        children: orderedSections,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ComparisonColumnDividerPainter(
                  showMunters1: widget.showMunters1,
                  showMunters2: widget.showMunters2,
                  munters1Collapsed: _munters1Collapsed,
                  munters2Collapsed: _munters2Collapsed,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonColumnDividerPainter extends CustomPainter {
  const _ComparisonColumnDividerPainter({
    required this.showMunters1,
    required this.showMunters2,
    required this.munters1Collapsed,
    required this.munters2Collapsed,
  });

  final bool showMunters1;
  final bool showMunters2;
  final bool munters1Collapsed;
  final bool munters2Collapsed;

  @override
  void paint(Canvas canvas, Size size) {
    // Guias de referencia.
    // canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
  }

  @override
  bool shouldRepaint(_ComparisonColumnDividerPainter oldDelegate) {
    return showMunters1 != oldDelegate.showMunters1 ||
        showMunters2 != oldDelegate.showMunters2 ||
        munters1Collapsed != oldDelegate.munters1Collapsed ||
        munters2Collapsed != oldDelegate.munters2Collapsed;
  }
}

enum _WitnessDotMode { blinking, fixed }

class _WitnessDotVisual {
  const _WitnessDotVisual({required this.color, required this.mode});

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
    required this.plc1ColumnLabel,
    required this.plc2ColumnLabel,
    required this.munters1,
    required this.munters2,
    required this.rangeSettings,
    required this.munters1Blocked,
    required this.munters2Blocked,
    required this.plc1MaintenanceMode,
    required this.plc2MaintenanceMode,
    required this.magnifierSettings,
    required this.reorderEnabled,
    required this.onOpenEnvironmentOverview,
    required this.onRegisterRoomWash,
    required this.onToggleReorder,
  });

  final bool showMunters1;
  final bool showMunters2;
  final String plc1ColumnLabel;
  final String plc2ColumnLabel;
  final MuntersModel munters1;
  final MuntersModel munters2;
  final DashboardRangeSettings rangeSettings;
  final bool munters1Blocked;
  final bool munters2Blocked;
  final PlcMaintenanceMode? plc1MaintenanceMode;
  final PlcMaintenanceMode? plc2MaintenanceMode;
  final MagnifierSettings magnifierSettings;
  final bool reorderEnabled;
  final VoidCallback? onOpenEnvironmentOverview;
  final VoidCallback onRegisterRoomWash;
  final VoidCallback onToggleReorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        // Guias de referencia.
        // border: Border(bottom: BorderSide(color: Color(0xFF334155))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeaderActionPlaceholderButton(onTap: onRegisterRoomWash),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _InstantMagnifierButton(settings: magnifierSettings),
                    const SizedBox(width: 6),
                    _HeaderToggleIcon(
                      icon: Icons.drag_indicator_rounded,
                      active: reorderEnabled,
                      onTap: onToggleReorder,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (showMunters1)
            _HeaderUnit(
              title: plc1ColumnLabel,
              mode: plc1MaintenanceMode,
              unit: munters1,
              rangeSettings: rangeSettings,
              blocked: munters1Blocked,
              onOpenEnvironmentOverview: onOpenEnvironmentOverview,
            ),
          if (showMunters2)
            _HeaderUnit(
              title: plc2ColumnLabel,
              mode: plc2MaintenanceMode,
              unit: munters2,
              rangeSettings: rangeSettings,
              blocked: munters2Blocked,
              onOpenEnvironmentOverview: onOpenEnvironmentOverview,
            ),
        ],
      ),
    );
  }
}

class _HeaderUnit extends StatelessWidget {
  const _HeaderUnit({
    required this.title,
    required this.mode,
    required this.unit,
    required this.rangeSettings,
    required this.blocked,
    required this.onOpenEnvironmentOverview,
  });

  final String title;
  final PlcMaintenanceMode? mode;
  final MuntersModel unit;
  final DashboardRangeSettings rangeSettings;
  final bool blocked;
  final VoidCallback? onOpenEnvironmentOverview;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HeaderEnvironmentCard(
              unit: unit,
              rangeSettings: rangeSettings,
              blocked: blocked,
              onTap: onOpenEnvironmentOverview,
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: mode == null ? 18 : 44,
              child: Center(
                child: mode == null
                    ? Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFE5E7EB),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : Tooltip(
                        message: mode!.fullLabel,
                        child: Container(
                          height: 42,
                          constraints: const BoxConstraints(maxWidth: 160),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFFBBF24)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x335B3B00),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    mode!.icon,
                                    color: const Color(0xFF111827),
                                    size: 14,
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      mode!.label,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xFF111827),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        height: 1,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                'Tareas de Mantenimiento',
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF111827),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  height: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderEnvironmentCard extends StatelessWidget {
  const _HeaderEnvironmentCard({
    required this.unit,
    required this.rangeSettings,
    required this.blocked,
    this.onTap,
  });

  final MuntersModel unit;
  final DashboardRangeSettings rangeSettings;
  final bool blocked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final double? temp = blocked ? null : unit.tempInterior;
    final double? exteriorTemp = blocked ? null : unit.tempExterior;
    final double? exteriorHumidity = blocked ? null : unit.displayHumExterior;
    final double? humidity = blocked ? null : unit.displayHumInterior;
    final double? dewPoint = blocked
        ? null
        : _calculateDewPointC(
            temperatureC: unit.tempInterior,
            relativeHumidityPercent: unit.humInterior,
          );
    final bool tempInRange =
        temp != null &&
        temp >= rangeSettings.temperatureMin &&
        temp <= rangeSettings.temperatureMax;
    final bool humidityInRange =
        humidity != null &&
        unit.humInterior != null &&
        unit.humInterior! >= rangeSettings.humidityMin &&
        unit.humInterior! <= rangeSettings.humidityMax;
    final bool humidityHighWithRecentWash =
        !blocked && _isHighHumidityExplainedByRecentWash(unit, rangeSettings);
    final bool hasAlert =
        (temp != null && !tempInRange) ||
        (humidity != null && !humidityInRange && !humidityHighWithRecentWash);
    final bool hasWarning = humidityHighWithRecentWash;
    final bool hasAnyData = temp != null || humidity != null;
    final Color borderColor = !hasAnyData
        ? const Color(0xFF334155)
        : hasAlert
        ? const Color(0xFFEF4444)
        : hasWarning
        ? const Color(0xFFFACC15)
        : const Color(0xFF22C55E);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 116),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: 1,
                right: 1,
                child: _EnvironmentVentilationBadge(
                  value: blocked
                      ? null
                      : _normalizeVoltageToPercent(
                          unit.tensionSalidaVentiladores,
                        ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _HeaderExteriorMetricText(
                    value: exteriorTemp?.toStringAsFixed(1),
                    unit: '°C',
                  ),
                  const SizedBox(height: 4),
                  _HeaderTemperatureMetric(
                    value: temp,
                    color: temp == null
                        ? const Color(0xFF94A3B8)
                        : tempInRange
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFEF4444),
                    heatingActive: !blocked && _hasAnyHeatingOn(unit),
                    coolingActive: !blocked && unit.bombaHumidificador == true,
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    height: 1,
                    color: const Color(0xFF223046),
                  ),
                  _HeaderHumidityDewPointRow(
                    humidity: humidity,
                    humidityColor: humidity == null
                        ? const Color(0xFF94A3B8)
                        : humidityHighWithRecentWash
                        ? const Color(0xFFFACC15)
                        : humidityInRange
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFEF4444),
                    dewPoint: dewPoint,
                  ),
                  if (humidityHighWithRecentWash) ...[
                    const SizedBox(height: 4),
                    _RoomWashNoticeText(event: unit.recentRoomWashEvent),
                  ],
                  const SizedBox(height: 3),
                  _HeaderExteriorMetricText(
                    value: exteriorHumidity?.toStringAsFixed(0),
                    unit: '%',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LargeEnvironmentUnitCard extends StatelessWidget {
  const _LargeEnvironmentUnitCard({
    required this.label,
    required this.unit,
    required this.tenantId,
    required this.siteId,
    required this.plcId,
    required this.rangeSettings,
    required this.blocked,
    this.scale = 1,
  });

  final String label;
  final MuntersModel unit;
  final String? tenantId;
  final String? siteId;
  final String? plcId;
  final DashboardRangeSettings rangeSettings;
  final bool blocked;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final double? temp = blocked ? null : unit.tempInterior;
    final double? exteriorTemp = blocked ? null : unit.tempExterior;
    final double? exteriorHumidity = blocked ? null : unit.displayHumExterior;
    final double? humidity = blocked ? null : unit.displayHumInterior;
    final double? dewPoint = blocked
        ? null
        : _calculateDewPointC(
            temperatureC: unit.tempInterior,
            relativeHumidityPercent: unit.humInterior,
          );
    final bool tempInRange =
        temp != null &&
        temp >= rangeSettings.temperatureMin &&
        temp <= rangeSettings.temperatureMax;
    final bool humidityInRange =
        humidity != null &&
        unit.humInterior != null &&
        unit.humInterior! >= rangeSettings.humidityMin &&
        unit.humInterior! <= rangeSettings.humidityMax;
    final bool humidityHighWithRecentWash =
        !blocked && _isHighHumidityExplainedByRecentWash(unit, rangeSettings);
    final bool hasAlert =
        (temp != null && !tempInRange) ||
        (humidity != null && !humidityInRange && !humidityHighWithRecentWash);
    final bool hasWarning = humidityHighWithRecentWash;
    final bool hasAnyData = temp != null || humidity != null;
    final Color borderColor = !hasAnyData
        ? const Color(0xFF334155)
        : hasAlert
        ? const Color(0xFFEF4444)
        : hasWarning
        ? const Color(0xFFFACC15)
        : const Color(0xFF22C55E);

    return Container(
      padding: EdgeInsets.fromLTRB(
        18 * scale,
        18 * scale,
        18 * scale,
        20 * scale,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12 * scale),
        border: Border.all(color: borderColor, width: 1.5 * scale),
        boxShadow: [
          BoxShadow(
            color: const Color(0x44000000),
            blurRadius: 16 * scale,
            offset: Offset(0, 6 * scale),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            child: _EnvironmentVentilationBadge(
              value: blocked
                  ? null
                  : _normalizeVoltageToPercent(unit.tensionSalidaVentiladores),
              scale: scale,
              large: true,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _LargeEnvironmentUnitLabel(label: label, scale: scale),
              SizedBox(height: 10 * scale),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 7,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _LargeExteriorMetricText(
                          value: exteriorTemp?.toStringAsFixed(1),
                          unit: '°C',
                          scale: scale,
                        ),
                        SizedBox(height: 6 * scale),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _LargeEnvironmentStatusIcons(
                              heatingActive: !blocked && _hasAnyHeatingOn(unit),
                              coolingActive:
                                  !blocked && unit.bombaHumidificador == true,
                              scale: scale,
                            ),
                            SizedBox(width: 18 * scale),
                            Flexible(
                              child: _LargeTemperatureValue(
                                value: temp,
                                color: temp == null
                                    ? const Color(0xFF94A3B8)
                                    : tempInRange
                                    ? const Color(0xFF22C55E)
                                    : const Color(0xFFEF4444),
                                scale: scale,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          margin: EdgeInsets.symmetric(vertical: 18 * scale),
                          height: 1,
                          color: const Color(0xFF223046),
                        ),
                        _LargeHumidityDewPointRow(
                          humidity: humidity,
                          humidityColor: humidity == null
                              ? const Color(0xFF94A3B8)
                              : humidityHighWithRecentWash
                              ? const Color(0xFFFACC15)
                              : humidityInRange
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFEF4444),
                          dewPoint: dewPoint,
                          scale: scale,
                        ),
                        if (humidityHighWithRecentWash) ...[
                          SizedBox(height: 5 * scale),
                          _RoomWashNoticeText(
                            event: unit.recentRoomWashEvent,
                            scale: scale,
                          ),
                        ],
                        SizedBox(height: 6 * scale),
                        _LargeExteriorMetricText(
                          value: exteriorHumidity?.toStringAsFixed(0),
                          unit: '%',
                          scale: scale,
                        ),
                        if (hasAlert) ...[
                          SizedBox(height: 12 * scale),
                          _LargeEnvironmentAlarmLabel(scale: scale),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: 18 * scale),
                  Expanded(
                    flex: 5,
                    child: _LargeEnvironmentExtraData(
                      tenantId: tenantId,
                      siteId: siteId,
                      plcId: plcId,
                      nh3: blocked ? null : unit.nh3,
                      scale: scale,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EnvironmentVentilationBadge extends StatelessWidget {
  const _EnvironmentVentilationBadge({
    required this.value,
    this.scale = 1,
    this.large = false,
  });

  final double? value;
  final double scale;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final int? percent = value == null ? null : (value! * 100).round();
    final bool running = (value ?? 0) > 0;
    final Color color = value == null
        ? const Color(0xFF64748B)
        : running
        ? const Color(0xFF38BDF8)
        : const Color(0xFF94A3B8);

    final double sizeScale = large ? scale * 2.25 : scale;

    return Container(
      padding: large
          ? EdgeInsets.symmetric(
              horizontal: 10 * sizeScale,
              vertical: 6 * sizeScale,
            )
          : EdgeInsets.zero,
      decoration: large
          ? BoxDecoration(
              color: const Color(0xCC111827),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFF223046)),
            )
          : null,
      child: large
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SpinningIcon(
                  icon: Icons.cyclone_rounded,
                  color: color,
                  size: 13 * sizeScale,
                  spinning: running,
                ),
                SizedBox(width: 4 * sizeScale),
                Text(
                  percent == null ? '--' : '$percent%',
                  style: TextStyle(
                    color: const Color(0xFFCBD5E1),
                    fontSize: 10 * sizeScale,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SpinningIcon(
                  icon: Icons.cyclone_rounded,
                  color: color,
                  size: 13 * sizeScale,
                  spinning: running,
                ),
                SizedBox(height: 2 * sizeScale),
                Text(
                  percent == null ? '--' : '$percent%',
                  style: TextStyle(
                    color: const Color(0xFFCBD5E1),
                    fontSize: 10 * sizeScale,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ],
            ),
    );
  }
}

class _LargeEnvironmentStatusIcons extends StatelessWidget {
  const _LargeEnvironmentStatusIcons({
    required this.heatingActive,
    required this.coolingActive,
    required this.scale,
  });

  final bool heatingActive;
  final bool coolingActive;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46 * scale,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.local_fire_department,
            size: 40 * scale,
            color: heatingActive
                ? const Color(0xFFF97316)
                : const Color(0xFF64748B),
          ),
          SizedBox(height: 18 * scale),
          Icon(
            Icons.ac_unit,
            size: 36 * scale,
            color: coolingActive
                ? const Color(0xFF38BDF8)
                : const Color(0xFF64748B),
          ),
        ],
      ),
    );
  }
}

class _LargeEnvironmentUnitLabel extends StatelessWidget {
  const _LargeEnvironmentUnitLabel({required this.label, required this.scale});

  final String label;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: const Color(0xFF94A3B8),
        fontSize: 12 * scale,
        fontWeight: FontWeight.w700,
        height: 1,
      ),
    );
  }
}

class _LargeExteriorMetricText extends StatelessWidget {
  const _LargeExteriorMetricText({
    required this.value,
    required this.unit,
    required this.scale,
  });

  final String? value;
  final String unit;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Text(
      _formatExteriorMetricLabel(value: value, unit: unit),
      textAlign: TextAlign.center,
      maxLines: 1,
      style: TextStyle(
        color: const Color(0xFFCBD5E1),
        fontSize: 20 * scale,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

class _LargeTemperatureValue extends StatelessWidget {
  const _LargeTemperatureValue({
    required this.value,
    required this.color,
    required this.scale,
  });

  final double? value;
  final Color color;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return _PlainEnvironmentValue(
      value: value?.toStringAsFixed(1),
      unit: '°C',
      color: color,
      fontSize: 86 * scale,
      unitFontSize: 24 * scale,
    );
  }
}

class _LargeEnvironmentExtraData extends StatelessWidget {
  const _LargeEnvironmentExtraData({
    required this.tenantId,
    required this.siteId,
    required this.plcId,
    required this.nh3,
    required this.scale,
  });

  final String? tenantId;
  final String? siteId;
  final String? plcId;
  final double? nh3;
  final double scale;

  static const CerdasRepository _repository = CerdasRepository();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 14 * scale,
        vertical: 12 * scale,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(10 * scale),
        border: Border.all(color: const Color(0xFF223046)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LargeExtraMetricRow(
            label: 'Cerdas por sala',
            valueChild: _LargeCerdasValue(
              tenantId: tenantId,
              siteId: siteId,
              plcId: plcId,
              repository: _repository,
              scale: scale,
            ),
            scale: scale,
          ),
          SizedBox(height: 12 * scale),
          _LargeExtraMetricRow(
            label: 'NH3',
            value: nh3 == null ? '-' : '${nh3!.toStringAsFixed(1)} ppm',
            scale: scale,
          ),
          SizedBox(height: 12 * scale),
          _LargeExtraMetricRow(label: 'CO2', value: '-', scale: scale),
          SizedBox(height: 12 * scale),
          _LargeExtraMetricRow(label: 'Consumo H2O', value: '-', scale: scale),
        ],
      ),
    );
  }
}

class _LargeCerdasValue extends StatelessWidget {
  const _LargeCerdasValue({
    required this.tenantId,
    required this.siteId,
    required this.plcId,
    required this.repository,
    required this.scale,
  });

  final String? tenantId;
  final String? siteId;
  final String? plcId;
  final CerdasRepository repository;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final String? tenantId = this.tenantId;
    final String? siteId = this.siteId;
    final String? plcId = this.plcId;
    if (tenantId == null ||
        tenantId.isEmpty ||
        siteId == null ||
        siteId.isEmpty ||
        plcId == null ||
        plcId.isEmpty) {
      return _LargeExtraValueText('-', scale: scale);
    }
    return StreamBuilder<PigStatsRecord?>(
      stream: repository.watchPigStats(
        tenantId: tenantId,
        siteId: siteId,
        plcId: plcId,
      ),
      builder: (BuildContext context, AsyncSnapshot<PigStatsRecord?> snapshot) {
        final int? count = snapshot.data?.currentCount;
        return _LargeExtraValueText(
          count == null ? '-' : '$count',
          scale: scale,
        );
      },
    );
  }
}

class _LargeExtraMetricRow extends StatelessWidget {
  const _LargeExtraMetricRow({
    required this.label,
    required this.scale,
    this.value,
    this.valueChild,
  });

  final String label;
  final double scale;
  final String? value;
  final Widget? valueChild;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: const Color(0xFF94A3B8),
              fontSize: 13 * scale,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(width: 10 * scale),
        valueChild ?? _LargeExtraValueText(value ?? '-', scale: scale),
      ],
    );
  }
}

class _LargeExtraValueText extends StatelessWidget {
  const _LargeExtraValueText(this.value, {required this.scale});

  final String value;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      textAlign: TextAlign.right,
      style: TextStyle(
        color: const Color(0xFFE5E7EB),
        fontSize: 18 * scale,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _LargeEnvironmentAlarmLabel extends StatelessWidget {
  const _LargeEnvironmentAlarmLabel({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    return Text(
      'ALARMA',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: const Color(0xFFEF4444),
        fontSize: 18 * scale,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _LargeHumidityDewPointRow extends StatelessWidget {
  const _LargeHumidityDewPointRow({
    required this.humidity,
    required this.humidityColor,
    required this.dewPoint,
    required this.scale,
  });

  final double? humidity;
  final Color humidityColor;
  final double? dewPoint;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100 * scale,
      child: Row(
        children: [
          Expanded(
            child: _LargeCompactMetricValue(
              value: humidity?.toStringAsFixed(0),
              unit: '%',
              color: humidityColor,
              fontSize: 78 * scale,
              unitFontSize: 28 * scale,
            ),
          ),
          Container(
            width: 1.2 * scale,
            height: 76 * scale,
            margin: EdgeInsets.symmetric(horizontal: 16 * scale),
            color: const Color(0xFF223046),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.water_drop_outlined,
                  size: 30 * scale,
                  color: const Color(0xFF38BDF8),
                ),
                SizedBox(width: 8 * scale),
                Flexible(
                  child: _LargeCompactMetricValue(
                    value: dewPoint?.toStringAsFixed(1),
                    unit: '°C',
                    color: dewPoint == null
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFFCBD5E1),
                    fontSize: 48 * scale,
                    unitFontSize: 18 * scale,
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

class _LargeCompactMetricValue extends StatelessWidget {
  const _LargeCompactMetricValue({
    required this.value,
    required this.unit,
    required this.color,
    required this.fontSize,
    required this.unitFontSize,
  });

  final String? value;
  final String unit;
  final Color color;
  final double fontSize;
  final double unitFontSize;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            value ?? '--',
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              height: 0.95,
            ),
          ),
          SizedBox(width: 4 * (fontSize / 78)),
          Padding(
            padding: EdgeInsets.only(bottom: 7 * (fontSize / 78)),
            child: Text(
              unit,
              maxLines: 1,
              style: TextStyle(
                color: color.withValues(alpha: 0.85),
                fontSize: unitFontSize,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderExteriorMetricText extends StatelessWidget {
  const _HeaderExteriorMetricText({required this.value, required this.unit});

  final String? value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        _formatExteriorMetricLabel(value: value, unit: unit),
        maxLines: 1,
        style: const TextStyle(
          color: Color(0xFFCBD5E1),
          fontSize: 13,
          fontWeight: FontWeight.w400,
          height: 1,
        ),
      ),
    );
  }
}

String _formatExteriorMetricLabel({
  required String? value,
  required String unit,
}) {
  return value == null ? 'Ext: -- $unit' : 'Ext: $value $unit';
}

class _HeaderTemperatureMetric extends StatelessWidget {
  const _HeaderTemperatureMetric({
    required this.value,
    required this.color,
    required this.heatingActive,
    required this.coolingActive,
  });

  final double? value;
  final Color color;
  final bool heatingActive;
  final bool coolingActive;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_fire_department,
              size: 16,
              color: heatingActive
                  ? const Color(0xFFF97316)
                  : const Color(0xFF64748B),
            ),
            const SizedBox(height: 4),
            Icon(
              Icons.ac_unit,
              size: 15,
              color: coolingActive
                  ? const Color(0xFF38BDF8)
                  : const Color(0xFF64748B),
            ),
          ],
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _PlainEnvironmentValue(
            value: value?.toStringAsFixed(1),
            unit: '°C',
            color: color,
            fontSize: 38,
            unitFontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _HeaderHumidityDewPointRow extends StatelessWidget {
  const _HeaderHumidityDewPointRow({
    required this.humidity,
    required this.humidityColor,
    required this.dewPoint,
  });

  final double? humidity;
  final Color humidityColor;
  final double? dewPoint;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          Expanded(
            child: _HeaderCompactMetricValue(
              value: humidity?.toStringAsFixed(0),
              unit: '%',
              color: humidityColor,
              fontSize: 33,
              unitFontSize: 14,
            ),
          ),
          Container(
            width: 1,
            height: 31,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: const Color(0xFF223046),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.water_drop_outlined,
                  size: 15,
                  color: Color(0xFF38BDF8),
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: _HeaderCompactMetricValue(
                    value: dewPoint?.toStringAsFixed(1),
                    unit: '°C',
                    color: dewPoint == null
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFFCBD5E1),
                    fontSize: 24,
                    unitFontSize: 10,
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

class _HeaderCompactMetricValue extends StatelessWidget {
  const _HeaderCompactMetricValue({
    required this.value,
    required this.unit,
    required this.color,
    required this.fontSize,
    required this.unitFontSize,
  });

  final String? value;
  final String unit;
  final Color color;
  final double fontSize;
  final double unitFontSize;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            value ?? '--',
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              height: 0.95,
            ),
          ),
          const SizedBox(width: 2),
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              unit,
              maxLines: 1,
              style: TextStyle(
                color: color.withValues(alpha: 0.85),
                fontSize: unitFontSize,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlainEnvironmentValue extends StatelessWidget {
  const _PlainEnvironmentValue({
    required this.value,
    required this.unit,
    required this.color,
    required this.fontSize,
    required this.unitFontSize,
  });

  final String? value;
  final String unit;
  final Color color;
  final double fontSize;
  final double unitFontSize;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            value ?? '--',
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              height: 0.94,
            ),
          ),
          const SizedBox(width: 4),
          Padding(
            padding: EdgeInsets.only(bottom: fontSize * 0.08),
            child: Text(
              unit,
              style: TextStyle(
                color: color,
                fontSize: unitFontSize,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderActionIcon extends StatelessWidget {
  const _HeaderActionIcon({required this.icon, required this.onPointerDown});

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

class _HeaderActionPlaceholderButton extends StatelessWidget {
  const _HeaderActionPlaceholderButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Accion',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Theme.of(context).colorScheme.primary),
          ),
          child: const Icon(
            Icons.draw_rounded,
            size: 22,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
    );
  }
}

class _InstantMagnifierButton extends StatefulWidget {
  const _InstantMagnifierButton({required this.settings});

  final MagnifierSettings settings;

  @override
  State<_InstantMagnifierButton> createState() =>
      _InstantMagnifierButtonState();
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

class _HeaderToggleIcon extends StatelessWidget {
  const _HeaderToggleIcon({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
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
          color: active ? const Color(0xFF1F2937) : const Color(0xFF162133),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? const Color(0xFF475569) : const Color(0xFF223046),
          ),
        ),
        child: Icon(
          icon,
          size: 15,
          color: active ? const Color(0xFFCBD5E1) : const Color(0xFF94A3B8),
        ),
      ),
    );
  }
}

class _SectionDragHandle extends StatelessWidget {
  const _SectionDragHandle();

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: SizedBox(
        width: 10,
        height: 16,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List<Widget>.generate(
              3,
              (int row) => Padding(
                padding: EdgeInsets.only(bottom: row == 2 ? 0 : 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List<Widget>.generate(
                    2,
                    (int column) => Padding(
                      padding: EdgeInsets.only(right: column == 1 ? 0 : 2),
                      child: Container(
                        width: 2.1,
                        height: 2.1,
                        decoration: const BoxDecoration(
                          color: Color(0xFF94A3B8),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ComparisonColumnsScope extends InheritedWidget {
  const _ComparisonColumnsScope({
    required this.showMunters1,
    required this.showMunters2,
    required this.plc1ColumnLabel,
    required this.plc2ColumnLabel,
    required this.munters1Collapsed,
    required this.munters2Collapsed,
    required super.child,
  });

  final bool showMunters1;
  final bool showMunters2;
  final String plc1ColumnLabel;
  final String plc2ColumnLabel;
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
        plc1ColumnLabel != oldWidget.plc1ColumnLabel ||
        plc2ColumnLabel != oldWidget.plc2ColumnLabel ||
        munters1Collapsed != oldWidget.munters1Collapsed ||
        munters2Collapsed != oldWidget.munters2Collapsed;
  }
}

class _ExpandedSectionColumnLabels extends StatelessWidget {
  const _ExpandedSectionColumnLabels();

  static const double _actionColumnWidth = 26;

  @override
  Widget build(BuildContext context) {
    final _ComparisonColumnsScope scope = _ComparisonColumnsScope.of(context);
    final bool showFirstLabel = scope.showMunters1 && !scope.munters1Collapsed;
    final bool showSecondLabel = scope.showMunters2 && !scope.munters2Collapsed;
    if (!showFirstLabel && !showSecondLabel) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        const Expanded(flex: 3, child: SizedBox.shrink()),
        if (!scope.showMunters1)
          const SizedBox.shrink()
        else if (scope.munters1Collapsed)
          const SizedBox(width: 52)
        else
          Expanded(
            flex: 4,
            child: _ExpandedSectionColumnLabel(scope.plc1ColumnLabel),
          ),
        if (!scope.showMunters2)
          const SizedBox.shrink()
        else if (scope.munters2Collapsed)
          const SizedBox(width: 52)
        else
          Expanded(
            flex: 4,
            child: _ExpandedSectionColumnLabel(scope.plc2ColumnLabel),
          ),
        if (scope.showMunters1 || scope.showMunters2)
          const SizedBox(width: _actionColumnWidth),
      ],
    );
  }
}

class _ExpandedSectionColumnLabel extends StatelessWidget {
  const _ExpandedSectionColumnLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _PlcModuleIconData {
  const _PlcModuleIconData({
    required this.icon,
    required this.iconColor,
    required this.status,
    this.iconWidget,
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
  final Widget? iconWidget;
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
    final Widget leadingIcon =
        data.iconWidget ??
        _SpinningIcon(
          icon: data.icon,
          color: data.iconColor,
          size: 14,
          spinning: data.spinning,
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ModuleStatusIndicator(status: data.status),
        const SizedBox(width: 4),
        leadingIcon,
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
    final Widget icon = Icon(
      widget.icon,
      size: widget.size,
      color: widget.color,
    );
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

class _VentilationHeaderPowerValue extends StatelessWidget {
  const _VentilationHeaderPowerValue({required this.value});

  final double? value;

  @override
  Widget build(BuildContext context) {
    final int? percent = value == null ? null : (value! * 100).round();
    return Text(
      percent == null ? '--' : '$percent%',
      style: const TextStyle(
        color: Color(0xFFCBD5E1),
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _FilterHeaderPressureValue extends StatelessWidget {
  const _FilterHeaderPressureValue({required this.pressure});

  final double? pressure;

  @override
  Widget build(BuildContext context) {
    final String label = pressure == null
        ? '--'
        : _formatValueWithUnit(pressure, 'Pa');
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFFCBD5E1),
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _SquareAirFilterIcon extends StatelessWidget {
  const _SquareAirFilterIcon({required this.color, this.denseMesh = false});

  final Color color;
  final bool denseMesh;

  @override
  Widget build(BuildContext context) {
    final List<double> guides = denseMesh
        ? const <double>[4, 7, 10]
        : const <double>[5.5, 8.5];

    return SizedBox(
      width: 14,
      height: 14,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: color, width: 1.3),
              ),
            ),
          ),
          for (final double x in guides)
            Positioned(
              left: x,
              top: 2,
              bottom: 2,
              child: Container(width: 1, color: color.withValues(alpha: 0.85)),
            ),
          for (final double y in guides)
            Positioned(
              left: 2,
              right: 2,
              top: y,
              child: Container(height: 1, color: color.withValues(alpha: 0.85)),
            ),
        ],
      ),
    );
  }
}

class _OnOffHeaderValue extends StatelessWidget {
  const _OnOffHeaderValue({required this.active});

  final bool? active;

  @override
  Widget build(BuildContext context) {
    final bool? current = active;
    final String label = current == null ? '--' : (current ? 'ON' : 'OFF');
    final Color color = current == null
        ? const Color(0xFF94A3B8)
        : (current ? const Color(0xFF22C55E) : const Color(0xFFCBD5E1));

    return Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _SectionTable extends StatefulWidget {
  const _SectionTable({
    super.key,
    required this.sectionId,
    required this.title,
    required this.rows,
    required this.plcIconData,
    required this.collapseGeneration,
    required this.expandRequestGeneration,
    required this.onExpandedChanged,
  });

  final String sectionId;
  final String title;
  final List<Widget> rows;
  final List<_PlcModuleIconData> plcIconData;
  final int collapseGeneration;
  final int expandRequestGeneration;
  final void Function(String sectionId, {required bool expanded, int? plcIndex})
  onExpandedChanged;

  @override
  State<_SectionTable> createState() => _SectionTableState();
}

class _SectionTableState extends State<_SectionTable> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _SectionTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.collapseGeneration != oldWidget.collapseGeneration &&
        _expanded) {
      setState(() {
        _expanded = false;
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
    void toggleSection({int? plcIndex}) {
      final bool nextExpanded = !_expanded;
      setState(() {
        _expanded = nextExpanded;
      });
      widget.onExpandedChanged(
        widget.sectionId,
        expanded: nextExpanded,
        plcIndex: nextExpanded ? plcIndex : null,
      );
    }

    final bool hasRows = widget.rows.isNotEmpty;
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: hasRows ? toggleSection : null,
                    child: SizedBox(
                      height: 18,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(width: 14),
                          Text(
                            widget.title,
                            style: const TextStyle(
                              color: Color(0xFFE5E7EB),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
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
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: hasRows ? () => toggleSection(plcIndex: 0) : null,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: widget.plcIconData.isNotEmpty
                            ? _PlcModuleIconWidget(data: widget.plcIconData[0])
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                if (!scope.showMunters2)
                  const SizedBox.shrink()
                else if (scope.munters2Collapsed)
                  const SizedBox(width: 52)
                else
                  Expanded(
                    flex: 4,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: hasRows ? () => toggleSection(plcIndex: 1) : null,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: widget.plcIconData.length > 1
                            ? _PlcModuleIconWidget(data: widget.plcIconData[1])
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                if (hasRows)
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: toggleSection,
                    child: Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: const Color(0xFF94A3B8),
                      size: 18,
                    ),
                  )
                else
                  const SizedBox(width: 18),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 6),
            const _ExpandedSectionColumnLabels(),
            const SizedBox(height: 4),
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
            : (t < 0.44 ? 1 - Curves.easeIn.transform((t - 0.22) / 0.22) : 0);
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
    modules.add('Estado');
  }
  if (_isModuleStatusAlarm(
    _resolveEnvironmentStatusForUnit(unit: unit, rangeSettings: rangeSettings),
  )) {
    modules.add('Ambiente');
  }
  if (_isModuleStatusAlarm(_resolveFiltrosStatusForUnit(unit, rangeSettings))) {
    modules.add('Filtros');
  }
  if (_isModuleStatusAlarm(_resolveVentilationStatusForUnit(unit))) {
    modules.add('Ventilacion');
  }
  if (_isModuleStatusAlarm(
    _resolveHumidificationStatusForUnit(unit, rangeSettings),
  )) {
    modules.add('Enfriamiento');
  }
  if (_isModuleStatusAlarm(_resolveAperturasStatusForUnit(unit))) {
    modules.add('Aperturas');
  }
  if (_isModuleStatusAlarm(
    _resolveCalefaccionStatusForUnit(unit, rangeSettings),
  )) {
    modules.add('Calefaccion');
  }
  return modules;
}

bool _isVentilationFullyRunning(MuntersModel unit) {
  if (_shouldBlockOperationalData(unit)) {
    return false;
  }
  final List<bool> fans = <bool?>[
    unit.fanQ5,
    unit.fanQ6,
    unit.fanQ7,
    unit.fanQ8,
    unit.fanQ9,
    unit.fanQ10,
  ].whereType<bool>().toList(growable: false);
  return fans.any((bool f) => f == true);
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
  if (_shouldBlockOperationalData(unit)) {
    return const Color(0xFF94A3B8);
  }
  final _ModuleStatus status = _resolveEnvironmentStatusForUnit(
    unit: unit,
    rangeSettings: rangeSettings,
  );
  if (status.kind == _ModuleStatusKind.error) {
    return const Color(0xFFEF4444);
  }
  if (status.kind == _ModuleStatusKind.warning) {
    return const Color(0xFFFACC15);
  }
  if (unit.tempInterior == null) {
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
    filtrosStatus: _resolveFiltrosStatusForUnit(unit, rangeSettings),
    ventilationStatus: _resolveVentilationStatusForUnit(unit),
    humidificationStatus: _resolveHumidificationStatusForUnit(
      unit,
      rangeSettings,
    ),
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

bool _isHighHumidityExplainedByRecentWash(
  MuntersModel unit,
  DashboardRangeSettings rangeSettings,
) {
  return _isHighHumidityExplainedByRecentWashMax(
    unit,
    rangeSettings.humidityMax,
  );
}

bool _isHighHumidityExplainedByRecentWashMax(
  MuntersModel unit,
  double humidityMax,
) {
  final double? rawHumidity = unit.humInterior;
  final RoomWashEvent? event = unit.recentRoomWashEvent;
  if (rawHumidity == null || event == null || rawHumidity <= humidityMax) {
    return false;
  }
  final DateTime now = DateTime.now();
  final DateTime washedAt = event.washedAt;
  return !washedAt.isAfter(now) &&
      now.difference(washedAt) <= RoomWashEvent.defaultHumidityShadingWindow;
}

String _formatRoomWashNotice(RoomWashEvent? event) {
  if (event == null) {
    return '';
  }
  final DateTime now = DateTime.now();
  final Duration age = now.difference(event.washedAt);
  if (!age.isNegative && age.inMinutes < 60) {
    return 'Sala lavada hace ${age.inMinutes} min';
  }
  return 'Lavado registrado a las ${_formatWashTime(event.washedAt)}';
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
  final _RangeAssessment tempAssessment = _assessRange(
    unit.tempInterior,
    rangeSettings.temperatureMin,
    rangeSettings.temperatureMax,
  );
  final _RangeAssessment humidityAssessment = _assessRange(
    unit.humInterior,
    rangeSettings.humidityMin,
    rangeSettings.humidityMax,
  );
  final bool humidityExplainedByRecentWash =
      _isHighHumidityExplainedByRecentWash(unit, rangeSettings);

  if (tempAssessment == _RangeAssessment.outOfRange ||
      (humidityAssessment == _RangeAssessment.outOfRange &&
          !humidityExplainedByRecentWash)) {
    return const _ModuleStatus.error();
  }
  if (humidityExplainedByRecentWash ||
      tempAssessment == _RangeAssessment.limit ||
      humidityAssessment == _RangeAssessment.limit) {
    return const _ModuleStatus.warning();
  }
  final _RangeAssessment assessment = _mergeAssessments(<_RangeAssessment>[
    tempAssessment,
    humidityAssessment,
  ]);

  return switch (assessment) {
    _RangeAssessment.outOfRange => const _ModuleStatus.warning(),
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
  required _ModuleStatus filtrosStatus,
  required _ModuleStatus ventilationStatus,
  required _ModuleStatus humidificationStatus,
  required _ModuleStatus aperturasStatus,
  required _ModuleStatus calefaccionStatus,
  required bool hasAlarmOutput,
}) {
  if (hasAlarmOutput ||
      _isModuleStatusAlarm(functioningStatus) ||
      _isModuleStatusAlarm(environmentStatus) ||
      _isModuleStatusAlarm(filtrosStatus) ||
      _isModuleStatusAlarm(ventilationStatus) ||
      _isModuleStatusAlarm(humidificationStatus) ||
      _isModuleStatusAlarm(aperturasStatus) ||
      _isModuleStatusAlarm(calefaccionStatus)) {
    return const _ModuleStatus.alert();
  }
  if (functioningStatus.kind == _ModuleStatusKind.pending &&
      environmentStatus.kind == _ModuleStatusKind.pending &&
      filtrosStatus.kind == _ModuleStatusKind.pending &&
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

_ModuleStatus _resolveFiltrosStatus(
  MuntersModel munters1,
  MuntersModel munters2,
  DashboardRangeSettings rangeSettings,
) {
  final List<_ModuleStatus> statuses = <_ModuleStatus>[
    _resolveFiltrosStatusForUnit(munters1, rangeSettings),
    _resolveFiltrosStatusForUnit(munters2, rangeSettings),
  ];
  if (statuses.any(_isModuleStatusAlarm)) {
    return const _ModuleStatus.alert();
  }
  if (statuses.any((status) => status.kind == _ModuleStatusKind.ok)) {
    return const _ModuleStatus.ok();
  }
  return const _ModuleStatus.pending();
}

_ModuleStatus _resolveFiltrosStatusForUnit(
  MuntersModel unit,
  DashboardRangeSettings rangeSettings,
) {
  if (_shouldBlockOperationalData(unit)) {
    return const _ModuleStatus.pending();
  }
  final double? differentialPressure = unit.presionDiferencial;
  if (differentialPressure == null) {
    return const _ModuleStatus.pending();
  }
  if (differentialPressure > rangeSettings.filterPressureMax) {
    return const _ModuleStatus.alert();
  }
  return const _ModuleStatus.ok();
}

Color _resolveFiltrosIconColorForUnit(
  MuntersModel unit,
  DashboardRangeSettings rangeSettings,
) {
  return switch (_resolveFiltrosStatusForUnit(unit, rangeSettings).kind) {
    _ModuleStatusKind.alert ||
    _ModuleStatusKind.error => const Color(0xFFEF4444),
    _ModuleStatusKind.ok => const Color(0xFF22C55E),
    _ => const Color(0xFF94A3B8),
  };
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
    notices.add('Enfriamiento ON');
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
  static const double _defaultItemFontSize = 12;
  static const double _actionColumnWidth = 26;

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
                          fontSize: _defaultItemFontSize,
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
                  child: alignToTop ? munters1 : Center(child: munters1),
                ),
              if (!scope.showMunters2)
                const SizedBox.shrink()
              else if (scope.munters2Collapsed)
                const SizedBox(width: 52)
              else
                Expanded(
                  flex: 4,
                  child: alignToTop ? munters2 : Center(child: munters2),
                ),
              if (scope.showMunters1 || scope.showMunters2)
                const SizedBox(width: _actionColumnWidth),
            ],
          ),
        ],
      ),
    );
  }
}

class _EnvironmentTemperatureBlock extends StatelessWidget {
  const _EnvironmentTemperatureBlock({
    required this.munters1,
    required this.munters2,
    required this.rangeSettings,
    required this.munters1Blocked,
    required this.munters2Blocked,
  });

  final MuntersModel munters1;
  final MuntersModel munters2;
  final DashboardRangeSettings rangeSettings;
  final bool munters1Blocked;
  final bool munters2Blocked;

  static const List<String> _labels = <String>[
    'T. Exterior',
    'T. Ingreso Sala',
    'T. Salida Sala',
    '∆T (Ing-Egr)',
    'P. Rocío',
    'Flujo térmico',
  ];
  static const double _actionColumnWidth = 26;

  @override
  Widget build(BuildContext context) {
    final _ComparisonColumnsScope scope = _ComparisonColumnsScope.of(context);

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF223046))),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(flex: 3, child: _EnvironmentTemperatureLabels()),
            if (!scope.showMunters1)
              const SizedBox.shrink()
            else if (scope.munters1Collapsed)
              const SizedBox(width: 52)
            else
              Expanded(
                flex: 4,
                child: Center(
                  child: _EnvironmentTemperatureColumn(
                    exterior: munters1.tempExterior,
                    ingreso: munters1.tempIngresoSala,
                    egreso: munters1.tempInterior,
                    humedadRelativa: munters1.humInterior,
                    min: rangeSettings.temperatureMin,
                    max: rangeSettings.temperatureMax,
                    flowThreshold: rangeSettings.thermalFlowThresholdC,
                    markedFlowDelta: rangeSettings.thermalFlowMarkedDeltaC,
                    blocked: munters1Blocked,
                    showThermalFlowDiagram: true,
                  ),
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
                  child: _EnvironmentTemperatureColumn(
                    exterior: munters2.tempExterior,
                    ingreso: munters2.tempIngresoSala,
                    egreso: munters2.tempInterior,
                    humedadRelativa: munters2.humInterior,
                    min: rangeSettings.temperatureMin,
                    max: rangeSettings.temperatureMax,
                    flowThreshold: rangeSettings.thermalFlowThresholdC,
                    markedFlowDelta: rangeSettings.thermalFlowMarkedDeltaC,
                    blocked: munters2Blocked,
                    showThermalFlowDiagram: false,
                  ),
                ),
              ),
            if (scope.showMunters1 || scope.showMunters2)
              const SizedBox(width: _actionColumnWidth),
          ],
        ),
      ),
    );
  }
}

class _EnvironmentTemperatureLabels extends StatelessWidget {
  const _EnvironmentTemperatureLabels();

  static const double _rowH = _EnvironmentTemperatureColumn._valueRowHeight;
  static const double _bracketWidth = 20;
  static const int _labelCount = 6;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final String label in _EnvironmentTemperatureBlock._labels)
              SizedBox(
                height: _rowH,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(
          width: _bracketWidth,
          height: _rowH * _labelCount,
          child: CustomPaint(painter: _DeltaBracketPainter(rowHeight: _rowH)),
        ),
        const Spacer(),
      ],
    );
  }
}

class _DeltaBracketPainter extends CustomPainter {
  const _DeltaBracketPainter({required this.rowHeight});

  final double rowHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = const Color(0xFF475569)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Vertical centers of rows 1 (Ingreso), 2 (Salida) and 3 (∆T).
    final double yIngreso = rowHeight * 1 + rowHeight / 2;
    final double yEgreso = rowHeight * 2 + rowHeight / 2;
    final double yDelta = rowHeight * 3 + rowHeight / 2;
    final double yMid = (yIngreso + yEgreso) / 2;

    final double xBracket = size.width - 10;
    const double tickLen = 6;

    // Horizontal ticks from Ingreso and Egreso rows into the bracket.
    canvas.drawLine(
      Offset(xBracket - tickLen, yIngreso),
      Offset(xBracket, yIngreso),
      paint,
    );
    canvas.drawLine(
      Offset(xBracket - tickLen, yEgreso),
      Offset(xBracket, yEgreso),
      paint,
    );

    // Vertical line spanning both rows.
    canvas.drawLine(
      Offset(xBracket, yIngreso),
      Offset(xBracket, yEgreso),
      paint,
    );

    // Connector from midpoint down to the ∆T row.
    canvas.drawLine(Offset(xBracket, yMid), Offset(xBracket, yDelta), paint);

    // Small arrowhead pointing right at the ∆T row.
    canvas.drawLine(
      Offset(xBracket, yDelta),
      Offset(xBracket + tickLen, yDelta),
      paint,
    );
    canvas.drawLine(
      Offset(xBracket + tickLen - 3, yDelta - 3),
      Offset(xBracket + tickLen, yDelta),
      paint,
    );
    canvas.drawLine(
      Offset(xBracket + tickLen - 3, yDelta + 3),
      Offset(xBracket + tickLen, yDelta),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _DeltaBracketPainter old) =>
      old.rowHeight != rowHeight;
}

class _EnvironmentTemperatureColumn extends StatelessWidget {
  const _EnvironmentTemperatureColumn({
    required this.exterior,
    required this.ingreso,
    required this.egreso,
    required this.humedadRelativa,
    required this.min,
    required this.max,
    required this.flowThreshold,
    required this.markedFlowDelta,
    required this.blocked,
    required this.showThermalFlowDiagram,
  });

  final double? exterior;
  final double? ingreso;
  final double? egreso;
  final double? humedadRelativa;
  final double min;
  final double max;
  final double flowThreshold;
  final double markedFlowDelta;
  final bool blocked;
  final bool showThermalFlowDiagram;

  static const double _contentLeft = 0;
  static const double _gaugeWidth = 150;
  static const double _valueRowHeight = 48;
  static const double _diagramHeight = 136;
  static const double _blockHeight = (_valueRowHeight * 5) + _diagramHeight;

  @override
  Widget build(BuildContext context) {
    final double? delta = ingreso != null && egreso != null
        ? egreso! - ingreso!
        : null;
    final double? puntoRocio = _calculateDewPointC(
      temperatureC: egreso,
      relativeHumidityPercent: humedadRelativa,
    );
    return SizedBox(
      width: _gaugeWidth,
      height: _blockHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: _contentLeft),
            child: Column(
              children: [
                _TemperatureValue(
                  value: exterior,
                  min: min,
                  max: max,
                  blocked: blocked,
                ),
                _TemperatureValue(
                  value: ingreso,
                  min: min,
                  max: max,
                  blocked: blocked,
                ),
                _TemperatureValue(
                  value: egreso,
                  min: min,
                  max: max,
                  blocked: blocked,
                ),
                _DeltaTemperatureValue(
                  delta: delta,
                  blocked: blocked,
                  gaugeWidth: _gaugeWidth,
                ),
                _DewPointValue(
                  value: puntoRocio,
                  blocked: blocked,
                  gaugeWidth: _gaugeWidth,
                ),
                if (showThermalFlowDiagram)
                  _ThermalFlowDiagram(
                    exterior: exterior,
                    ingreso: ingreso,
                    egreso: egreso,
                    blocked: blocked,
                    threshold: flowThreshold,
                    markedDelta: markedFlowDelta,
                  )
                else
                  const _ThermalFlowUnavailableLegend(),
              ],
            ),
          ),
          // Positioned(
          //   left: 2,
          //   top: 44,
          //   child: _TemperatureDeltaGauge(value: delta, blocked: blocked),
          // ),
        ],
      ),
    );
  }
}

class _ThermalFlowUnavailableLegend extends StatelessWidget {
  const _ThermalFlowUnavailableLegend();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: _EnvironmentTemperatureColumn._gaugeWidth,
      height: _EnvironmentTemperatureColumn._diagramHeight,
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'Faltan sensores para completar el gráfico (T. ingr)',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: FontWeight.w400,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _ThermalFlowDiagram extends StatelessWidget {
  const _ThermalFlowDiagram({
    required this.exterior,
    required this.ingreso,
    required this.egreso,
    required this.blocked,
    required this.threshold,
    required this.markedDelta,
  });

  final double? exterior;
  final double? ingreso;
  final double? egreso;
  final bool blocked;
  final double threshold;
  final double markedDelta;

  @override
  Widget build(BuildContext context) {
    final bool hasAnyData =
        !blocked && (exterior != null || ingreso != null || egreso != null);
    final bool hasGradient = ingreso != null && egreso != null;
    final _ThermalCondition condition = _resolveThermalCondition(
      exterior: exterior,
      interiorReference: ingreso ?? egreso,
      threshold: threshold,
    );
    final double delta = hasGradient ? egreso! - ingreso! : 0;
    final _ThermalFlowPositions positions = _ThermalFlowPositions.resolve(
      const Size(
        _EnvironmentTemperatureColumn._gaugeWidth,
        _EnvironmentTemperatureColumn._diagramHeight,
      ),
      delta: delta,
      threshold: threshold,
      markedDelta: markedDelta,
      blocked: !hasAnyData,
    );

    return SizedBox(
      width: _EnvironmentTemperatureColumn._gaugeWidth,
      height: _EnvironmentTemperatureColumn._diagramHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _ThermalFlowPainter(
                delta: delta,
                threshold: threshold,
                markedDelta: markedDelta,
                blocked: !hasAnyData,
                forceNeutral: !hasGradient,
              ),
            ),
          ),
          Positioned(
            left: 14,
            top: positions.ingresoY - 27,
            child: _DiagramTempLabel(
              value: exterior,
              blocked: !hasAnyData,
              alignRight: false,
            ),
          ),
          Positioned(
            left: 41,
            top: positions.ingresoY - 11,
            child: _DiagramTempLabel(
              value: ingreso,
              blocked: !hasAnyData,
              alignRight: false,
            ),
          ),
          Positioned(
            right: 16,
            top: positions.egresoY - 11,
            child: _DiagramTempLabel(
              value: egreso,
              blocked: !hasAnyData,
              alignRight: true,
            ),
          ),
          Positioned(
            left: 18,
            top: positions.ingresoY + 3,
            child: Icon(
              switch (condition) {
                _ThermalCondition.heating => Icons.local_fire_department,
                _ThermalCondition.cooling => Icons.ac_unit,
                _ThermalCondition.neutral => Icons.remove,
              },
              size: 18,
              color: switch (condition) {
                _ThermalCondition.heating => const Color(0xFFF97316),
                _ThermalCondition.cooling => const Color(0xFF38BDF8),
                _ThermalCondition.neutral => const Color(0xFF94A3B8),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagramTempLabel extends StatelessWidget {
  const _DiagramTempLabel({
    required this.value,
    required this.blocked,
    required this.alignRight,
  });

  final double? value;
  final bool blocked;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final String label = blocked || value == null ? '-' : '${value!.round()}°';
    return SizedBox(
      width: 42,
      child: Text(
        label,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          color: blocked ? const Color(0xFF64748B) : const Color(0xFFE5E7EB),
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

enum _ThermalCondition { heating, cooling, neutral }

_ThermalCondition _resolveThermalCondition({
  required double? exterior,
  required double? interiorReference,
  required double threshold,
}) {
  if (exterior == null || interiorReference == null) {
    return _ThermalCondition.neutral;
  }
  final double delta = interiorReference - exterior;
  if (delta.abs() <= threshold) {
    return _ThermalCondition.neutral;
  }
  return delta > 0 ? _ThermalCondition.heating : _ThermalCondition.cooling;
}

class _ThermalFlowPositions {
  const _ThermalFlowPositions({
    required this.room,
    required this.ingresoY,
    required this.egresoY,
  });

  final Rect room;
  final double ingresoY;
  final double egresoY;

  static _ThermalFlowPositions resolve(
    Size size, {
    required double delta,
    required double threshold,
    required double markedDelta,
    required bool blocked,
  }) {
    final Rect room = Rect.fromLTWH(36, 18, size.width - 48, size.height - 34);
    final double centerY = room.center.dy;
    if (blocked || delta.abs() <= threshold) {
      return _ThermalFlowPositions(
        room: room,
        ingresoY: centerY,
        egresoY: centerY,
      );
    }

    final double offset = delta.abs() >= markedDelta ? 31 : 16;
    final double upperY = (centerY - offset).clamp(
      room.top + 22,
      room.bottom - 22,
    );
    final double lowerY = (centerY + offset).clamp(
      room.top + 22,
      room.bottom - 22,
    );

    if (delta > 0) {
      return _ThermalFlowPositions(
        room: room,
        ingresoY: lowerY,
        egresoY: upperY,
      );
    }
    return _ThermalFlowPositions(room: room, ingresoY: upperY, egresoY: lowerY);
  }
}

class _ThermalFlowPainter extends CustomPainter {
  const _ThermalFlowPainter({
    required this.delta,
    required this.threshold,
    required this.markedDelta,
    required this.blocked,
    required this.forceNeutral,
  });

  final double delta;
  final double threshold;
  final double markedDelta;
  final bool blocked;
  final bool forceNeutral;

  @override
  void paint(Canvas canvas, Size size) {
    final _ThermalFlowPositions positions = _ThermalFlowPositions.resolve(
      size,
      delta: delta,
      threshold: threshold,
      markedDelta: markedDelta,
      blocked: blocked,
    );
    final Rect room = positions.room;
    final Paint roomPaint = Paint()
      ..color = blocked ? const Color(0xFF334155) : const Color(0xFF64748B)
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;
    canvas.drawRect(room, roomPaint);

    final Paint inletPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(10, positions.ingresoY),
      Offset(room.left - 8, positions.ingresoY),
      inletPaint,
    );
    _drawArrowHead(
      canvas,
      tip: Offset(room.left - 8, positions.ingresoY),
      angle: 0,
      color: const Color(0xFFCBD5E1),
      size: 5,
    );
    canvas.drawLine(
      Offset(room.right + 7, positions.egresoY),
      Offset(size.width - 4, positions.egresoY),
      inletPaint,
    );
    _drawArrowHead(
      canvas,
      tip: Offset(size.width - 4, positions.egresoY),
      angle: 0,
      color: const Color(0xFFCBD5E1),
      size: 5,
    );

    if (blocked || forceNeutral || delta.abs() <= threshold) {
      final Paint neutralPaint = Paint()
        ..color = const Color(0xFF94A3B8)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      final Offset start = Offset(room.left + 28, positions.ingresoY);
      final Offset end = Offset(room.right - 28, positions.egresoY);
      canvas.drawLine(start, end, neutralPaint);
      _drawArrowHead(
        canvas,
        tip: end,
        angle: 0,
        color: const Color(0xFF94A3B8),
        size: 9,
      );
      return;
    }

    final bool marked = delta.abs() >= markedDelta;
    final Offset start = Offset(room.left + 28, positions.ingresoY);
    final Offset end = Offset(room.right - 28, positions.egresoY);
    final Color arrowColor = delta > 0
        ? const Color(0xFFF97316)
        : const Color(0xFF38BDF8);
    final Paint arrowPaint = Paint()
      ..color = arrowColor
      ..strokeWidth = marked ? 4 : 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start, end, arrowPaint);
    _drawArrowHead(
      canvas,
      tip: end,
      angle: math.atan2(end.dy - start.dy, end.dx - start.dx),
      color: arrowColor,
      size: marked ? 13 : 10,
    );
  }

  void _drawArrowHead(
    Canvas canvas, {
    required Offset tip,
    required double angle,
    required Color color,
    required double size,
  }) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final double leftAngle = angle + math.pi - math.pi / 7;
    final double rightAngle = angle + math.pi + math.pi / 7;
    final Path path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        tip.dx + math.cos(leftAngle) * size,
        tip.dy + math.sin(leftAngle) * size,
      )
      ..lineTo(
        tip.dx + math.cos(rightAngle) * size,
        tip.dy + math.sin(rightAngle) * size,
      )
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ThermalFlowPainter oldDelegate) {
    return oldDelegate.delta != delta ||
        oldDelegate.threshold != threshold ||
        oldDelegate.markedDelta != markedDelta ||
        oldDelegate.blocked != blocked ||
        oldDelegate.forceNeutral != forceNeutral;
  }
}

// class _TemperatureDeltaGauge extends StatelessWidget {
//   const _TemperatureDeltaGauge({required this.value, required this.blocked});
//
//   final double? value;
//   final bool blocked;
//
//   static const double _min = 0;
//   static const double _max = 5;
//   static const double _height = 104;
//   static const double _width = 6;
//   static const double _markerHeight = 14;
//   static const double _markerWidth = 22;
//   static const double _barLeft = 18;
//   static const double _labelLeft = 5;
//   static const double _markerLeft = 12;
//
//   @override
//   Widget build(BuildContext context) {
//     if (blocked || value == null) {
//       return const SizedBox(width: 48, height: 142);
//     }
//
//     final double clamped = value!.clamp(_min, _max);
//     final double ratio = (clamped - _min) / (_max - _min);
//     final double markerTop = (_height - _markerHeight) * (1 - ratio);
//
//     return SizedBox(
//       width: 48,
//       height: 142,
//       child: Stack(
//         clipBehavior: Clip.none,
//         children: [
//           const Positioned(
//             left: _labelLeft - 8,
//             top: 52,
//             child: RotatedBox(
//               quarterTurns: 3,
//               child: Text(
//                 '∆ Temp.',
//                 style: TextStyle(
//                   color: Color(0xFF94A3B8),
//                   fontSize: 10,
//                   fontWeight: FontWeight.w400,
//                 ),
//               ),
//             ),
//           ),
//           const Positioned(
//             top: 14,
//             left: _labelLeft,
//             width: 14,
//             child: Text(
//               '5',
//               textAlign: TextAlign.left,
//               style: TextStyle(
//                 color: Color(0xFF94A3B8),
//                 fontSize: 10,
//                 fontWeight: FontWeight.w400,
//               ),
//             ),
//           ),
//           const Positioned(
//             top: 108,
//             left: _labelLeft,
//             width: 14,
//             child: Text(
//               '0',
//               textAlign: TextAlign.left,
//               style: TextStyle(
//                 color: Color(0xFF94A3B8),
//                 fontSize: 10,
//                 fontWeight: FontWeight.w400,
//               ),
//             ),
//           ),
//           Positioned(
//             top: 14,
//             left: _barLeft,
//             child: ClipRRect(
//               borderRadius: BorderRadius.circular(99),
//               child: Container(
//                 width: _width,
//                 height: _height,
//                 decoration: const BoxDecoration(
//                   gradient: LinearGradient(
//                     begin: Alignment.bottomCenter,
//                     end: Alignment.topCenter,
//                     colors: [Color(0x00EF4444), Color(0xFFEF4444)],
//                   ),
//                   border: Border.fromBorderSide(
//                     BorderSide(
//                       color: Color.fromARGB(133, 255, 255, 255),
//                       width: 0.6,
//                     ), //color original propuesto: 0x5594A3B8
//                   ),
//                 ),
//               ),
//             ),
//           ),
//           Positioned(
//             top: 14 + markerTop,
//             left: _markerLeft,
//             child: Container(
//               width: _markerWidth,
//               height: _markerHeight,
//               alignment: Alignment.center,
//               decoration: BoxDecoration(
//                 color: const Color(0xFFE2E8F0),
//                 borderRadius: BorderRadius.circular(99),
//                 border: Border.all(color: const Color(0xFF0F172A)),
//               ),
//               child: Text(
//                 clamped.toStringAsFixed(clamped % 1 == 0 ? 0 : 1),
//                 style: const TextStyle(
//                   color: Color(0xFF0F172A),
//                   fontSize: 10,
//                   fontWeight: FontWeight.w400,
//                   height: 1,
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

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
    this.activeColor = const Color(0xFF22C55E),
    this.inactiveColor = const Color(0xFFE5E7EB),
    this.fontWeight = FontWeight.w600,
  });

  final bool? active;
  final String activeLabel;
  final String inactiveLabel;
  final Color activeColor;
  final Color inactiveColor;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
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

class _DashWithUnitValue extends StatelessWidget {
  const _DashWithUnitValue(this.unit);

  final String unit;

  @override
  Widget build(BuildContext context) {
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        children: [
          const TextSpan(
            text: '-',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
          TextSpan(
            text: ' $unit',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
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

class _RoomWashNoticeText extends StatelessWidget {
  const _RoomWashNoticeText({required this.event, this.scale = 1});

  final RoomWashEvent? event;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final String message = _formatRoomWashNotice(event);
    if (message.isEmpty) {
      return const SizedBox.shrink();
    }
    return Text(
      message,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: const Color(0xFFFACC15),
        fontSize: 10 * scale,
        fontWeight: FontWeight.w700,
      ),
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
      horizontalMargin: 8,
    );
  }
}

class _DifferentialPressureHistoryValue extends StatelessWidget {
  const _DifferentialPressureHistoryValue({
    required this.unitName,
    required this.tenantId,
    required this.siteId,
    required this.plcId,
    this.blocked = false,
  });

  final String unitName;
  final String? tenantId;
  final String? siteId;
  final String? plcId;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    if (blocked) {
      return const _TextValue('-', fontWeight: FontWeight.w400);
    }
    return DifferentialPressureHistoryCard(
      unitName: unitName,
      tenantId: tenantId,
      siteId: siteId,
      plcId: plcId,
      horizontalMargin: 8,
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
      PlcUnitDiagnostics.plcReachableNoValidData => const Color(0xFFF59E0B),
      PlcUnitDiagnostics.plcStopConfirmed => const Color(0xFFF59E0B),
      PlcUnitDiagnostics.plcHealthy => const Color(0xFF22C55E),
      PlcUnitDiagnostics.plcRunConfirmed => const Color(0xFF22C55E),
      PlcUnitDiagnostics.plcStateUnknown => const Color(0xFFCBD5E1),
      PlcUnitDiagnostics.plcReachableStateUnknown => const Color(0xFFCBD5E1),
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
      return _LinearGaugeEmpty(
        min: min,
        max: max,
        gaugeWidth: _EnvironmentTemperatureColumn._gaugeWidth,
      );
    }
    final double currentValue = value!;

    return SizedBox(
      width: _EnvironmentTemperatureColumn._gaugeWidth,
      child: _LinearGauge(
        value: currentValue,
        min: min,
        max: max,
        valueLabel: '${currentValue.toStringAsFixed(1)} °C',
        colors: const [Color(0xFF2563EB), Color(0xFFDC2626)],
        showAlert: _isOutOfRange(currentValue, min, max),
        gaugeWidth: _EnvironmentTemperatureColumn._gaugeWidth,
      ),
    );
  }
}

class _HumidityValue extends StatelessWidget {
  const _HumidityValue({
    required this.unit,
    required this.min,
    required this.max,
    this.blocked = false,
  });

  final MuntersModel unit;
  final double min;
  final double max;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    if (blocked) {
      return const _TextValue('-', fontWeight: FontWeight.w400);
    }
    if (unit.humInterior == null) {
      return const _TextValue('Sin datos');
    }
    final double rawValue = unit.humInterior!;
    final double currentValue = unit.displayHumInterior!;
    final bool explainedByRecentWash = _isHighHumidityExplainedByRecentWashMax(
      unit,
      max,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 150,
          child: _LinearGauge(
            value: currentValue,
            min: min,
            max: max,
            valueLabel: '${currentValue.toStringAsFixed(0)} %',
            colors: const [Color(0xFFD6C3A1), Color(0xFF38BDF8)],
            showAlert: _isOutOfRange(rawValue, min, max),
            alertColor: explainedByRecentWash
                ? const Color(0xFFFACC15)
                : const Color(0xFFEF4444),
          ),
        ),
        if (explainedByRecentWash)
          _RoomWashNoticeText(event: unit.recentRoomWashEvent),
      ],
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

class _EnvironmentHeaderExtra extends StatelessWidget {
  const _EnvironmentHeaderExtra({
    required this.temperature,
    required this.visual,
  });

  final double? temperature;
  final _HumidityHeaderVisual visual;

  @override
  Widget build(BuildContext context) {
    final String label = temperature == null
        ? '--'
        : _formatValueWithUnit(temperature, '°C');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFCBD5E1),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 4),
        _EnvironmentHeaderHumidityIcon(visual: visual),
      ],
    );
  }
}

class _HumidityFillIcon extends StatelessWidget {
  const _HumidityFillIcon({required this.fill, this.size = 22});

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
          Icon(Icons.water_drop_outlined, color: _outlineColor, size: size),
          Align(
            alignment: Alignment.bottomCenter,
            child: ClipRect(
              child: SizedBox(
                width: size,
                height: size * clampedFill,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  heightFactor: 1,
                  child: Icon(Icons.water_drop, color: _fillColor, size: size),
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

  final int fractionDigits = unit == '°C' ? 1 : (value % 1 != 0 ? 1 : 0);
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

class _LinearGaugeEmpty extends StatelessWidget {
  const _LinearGaugeEmpty({
    required this.min,
    required this.max,
    required this.gaugeWidth,
  });

  final double min;
  final double max;
  final double gaugeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: gaugeWidth,
            height: 14,
            child: const Align(
              alignment: Alignment.center,
              child: Text(
                'Sin datos',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          SizedBox(
            width: gaugeWidth,
            height: 18,
            child: Align(
              alignment: Alignment.centerLeft,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: Container(height: 8, color: const Color(0xFF334155)),
              ),
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

class _DeltaTemperatureValue extends StatelessWidget {
  const _DeltaTemperatureValue({
    required this.delta,
    required this.blocked,
    required this.gaugeWidth,
  });

  final double? delta;
  final bool blocked;
  final double gaugeWidth;

  static const double _maxDelta = 5.0;

  @override
  Widget build(BuildContext context) {
    if (blocked || delta == null) {
      return _LinearGaugeEmpty(
        min: 0,
        max: _maxDelta.toInt().toDouble(),
        gaugeWidth: gaugeWidth,
      );
    }
    final double clampedDelta = delta!.abs().clamp(0.0, _maxDelta);
    return SizedBox(
      height: 48,
      width: gaugeWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: gaugeWidth,
            height: 14,
            child: Align(
              alignment: Alignment.center,
              child: Text(
                '∆T: ${clampedDelta.toStringAsFixed(1)} °C',
                style: const TextStyle(
                  color: Color(0xFFE5E7EB),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          SizedBox(
            width: gaugeWidth,
            height: 18,
            child: CustomPaint(
              painter: _DeltaTrianglePainter(
                delta: clampedDelta,
                maxDelta: _maxDelta,
                width: gaugeWidth,
              ),
            ),
          ),
          SizedBox(
            width: gaugeWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text(
                  '0°',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  '5°',
                  style: TextStyle(
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

class _DewPointValue extends StatelessWidget {
  const _DewPointValue({
    required this.value,
    required this.blocked,
    required this.gaugeWidth,
  });

  final double? value;
  final bool blocked;
  final double gaugeWidth;

  @override
  Widget build(BuildContext context) {
    final String label = blocked || value == null
        ? '--'
        : '${value!.toStringAsFixed(1)} °C';
    final Color color = blocked || value == null
        ? const Color(0xFF94A3B8)
        : const Color(0xFFE5E7EB);

    return SizedBox(
      height: _EnvironmentTemperatureColumn._valueRowHeight,
      width: gaugeWidth,
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

double? _calculateDewPointC({
  required double? temperatureC,
  required double? relativeHumidityPercent,
}) {
  if (temperatureC == null || relativeHumidityPercent == null) {
    return null;
  }
  if (!temperatureC.isFinite || !relativeHumidityPercent.isFinite) {
    return null;
  }

  final double rh = relativeHumidityPercent.clamp(1.0, 100.0);
  const double a = 17.62;
  const double b = 243.12;
  final double gamma =
      (a * temperatureC) / (b + temperatureC) + math.log(rh / 100.0);
  return (b * gamma) / (a - gamma);
}

class _DeltaTrianglePainter extends CustomPainter {
  const _DeltaTrianglePainter({
    required this.delta,
    required this.maxDelta,
    required this.width,
  });

  final double delta;
  final double maxDelta;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final double h = size.height;
    final double w = size.width;

    // Triangle: bottom-left(0,h) → bottom-right(w,h) → top-right(w,0)
    // Hypotenuse goes from bottom-left to top-right.
    final Path triangle = Path()
      ..moveTo(0, h)
      ..lineTo(w, h)
      ..lineTo(w, 0)
      ..close();

    final Paint fillPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF1E3A5F), Color(0xFF3B82F6)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(triangle, fillPaint);

    // Vertical bar at delta position (cursor)
    final double barX = (delta / maxDelta) * w;
    // Height of the triangle at barX = (barX / w) * h
    final double barTop = h - (barX / w) * h;
    const double barWidth = 3;

    final Paint barPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = barWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(barX, barTop), Offset(barX, h), barPaint);
  }

  @override
  bool shouldRepaint(_DeltaTrianglePainter old) =>
      old.delta != delta || old.maxDelta != maxDelta || old.width != width;
}

class _LinearGauge extends StatelessWidget {
  const _LinearGauge({
    required this.value,
    required this.min,
    required this.max,
    required this.valueLabel,
    required this.colors,
    required this.showAlert,
    this.alertColor = const Color(0xFFEF4444),
    this.gaugeWidth = 126,
  });

  final double value;
  final double min;
  final double max;
  final String valueLabel;
  final List<Color> colors;
  final bool showAlert;
  final Color alertColor;
  final double gaugeWidth;

  @override
  Widget build(BuildContext context) {
    final double clamped = ((value - min) / (max - min)).clamp(0.0, 1.0);
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
      height: 48,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: gaugeWidth,
            height: 14,
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
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 14,
                          color: alertColor,
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
