import 'package:flutter/material.dart';

import '../board_content/board_content_layout.dart';
import '../board_presets/board_preset.dart';
import '../board_preview/board_editor_page.dart';
import '../cell_layout_presets/cell_layout_catalog.dart';
import '../cell_layout_presets/cell_layout_preset_catalog.dart';
import '../device_board_config/apply_board_preset_to_device.dart';
import '../device_board_layouts/layout_validation_issue.dart';
import '../device_capabilities/device_capability_profile.dart';
import '../device_capabilities/capability_library_store.dart';
import '../device_metric_catalogs/device_metric_catalog.dart';
import '../device_capabilities/reference_capability_seeds.dart';
import '../models/agro_device.dart';
import '../services/board_preset_repository.dart';
import '../services/capability_profile_repository.dart';
import '../services/device_board_config_repository.dart';
import '../services/firestore_version_conflict.dart';
import '../services/global_board_configuration_service.dart';

/// N7.1 §12 — "Tenant → Site → Device → Configuración de Board": shows the
/// Device's assigned [DeviceCapabilityProfile], its [BoardContentLayout]
/// status (or "sin configurar"), and the last-updated timestamp. Actions:
/// assign a profile + apply a compatible [BoardPreset] (§8), open
/// [BoardEditorPage] in [BoardEditorMode.device] (§13), or reset from the
/// layout's own `sourceBoardPresetId` (§12, with confirmation — replaces
/// the Device's personalization).
///
/// Exactly one [DeviceBoardConfigRepository.fetchOne] read for the Device's
/// own config, plus one `fetchAll()` each for the profile/preset pickers —
/// see the informe's reads/writes table (§22) for the full breakdown.
/// Widgets never call Firestore directly (§4): every mutation goes through
/// [DeviceBoardConfigRepository].
class DeviceBoardConfigPage extends StatefulWidget {
  const DeviceBoardConfigPage({
    super.key,
    required this.isOwner,
    required this.tenantId,
    required this.device,
    this.deviceBoardConfigRepository = const DeviceBoardConfigRepository(),
    this.capabilityProfileRepository = const CapabilityProfileRepository(),
    this.boardPresetRepository = const BoardPresetRepository(),
    this.globalConfigurationService,
  });

  final bool isOwner;
  final String tenantId;
  final AgroDevice device;
  final DeviceBoardConfigRepository deviceBoardConfigRepository;
  final CapabilityProfileRepository capabilityProfileRepository;
  final BoardPresetRepository boardPresetRepository;
  final GlobalBoardConfigurationService? globalConfigurationService;

  @override
  State<DeviceBoardConfigPage> createState() => _DeviceBoardConfigPageState();
}

enum _LoadState { loading, loaded, error }

class _DeviceBoardConfigPageState extends State<DeviceBoardConfigPage> {
  _LoadState _state = _LoadState.loading;
  String? _errorMessage;

  BoardContentLayout? _layout;
  List<DeviceCapabilityProfile> _profiles = const [];
  List<BoardPreset> _presets = const [];

  String? _selectedProfileId;
  String? _assignedProfileId;
  String? _selectedPresetId;
  bool _applying = false;
  List<LayoutValidationIssue>? _blockedIssues;
  MetricLibraryStore _metrics = sharedMetricLibraryStore;
  IndicatorLibraryStore _indicators = sharedIndicatorLibraryStore;
  CellLayoutCatalog _cellLayouts = CellLayoutCatalog(
    sharedCellLayoutPresetCatalog.presets,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _state = _LoadState.loading;
      _errorMessage = null;
    });
    try {
      final globalService = widget.globalConfigurationService;
      final results = await Future.wait<Object?>([
        widget.deviceBoardConfigRepository.fetchOne(
          tenantId: widget.tenantId,
          deviceId: widget.device.id,
        ),
        if (globalService == null)
          widget.capabilityProfileRepository.fetchAll(),
        if (globalService == null) widget.boardPresetRepository.fetchAll(),
        if (globalService != null) globalService.load(),
      ]);
      if (!mounted) return;
      final layout = results[0] as BoardContentLayout?;
      final global = globalService == null
          ? null
          : results[1] as GlobalBoardConfigurationSnapshot;
      final profileRecords =
          global?.profiles ?? results[1] as List<CapabilityProfileRecord>;
      final presets = global?.boardPresets ?? results[2] as List<BoardPreset>;
      final activeProfiles = profileRecords
          .where((r) => r.profile.enabled)
          .map((r) => r.profile)
          .toList();
      final activePresets = presets.where((p) => p.enabled).toList();
      final selectedProfile = activeProfiles
          .where((profile) => profile.id == layout?.capabilityProfileId)
          .cast<DeviceCapabilityProfile?>()
          .firstOrNull;
      final sourcePresetId = layout?.sourceBoardPresetId;
      final sourcePresetIsSelectable = activePresets.any(
        (preset) =>
            preset.id == sourcePresetId &&
            missingCapabilityIssues(
              preset: preset,
              profile: selectedProfile,
            ).isEmpty,
      );
      if (global != null) {
        _metrics = MetricLibraryStore(
          initial: global.metrics
              .where((r) => r.enabled)
              .map((r) => r.metric)
              .toList(),
        );
        _indicators = IndicatorLibraryStore(
          initial: global.indicators
              .where((r) => r.enabled)
              .map((r) => r.indicator)
              .toList(),
        );
        _cellLayouts = CellLayoutCatalog(
          global.cellLayouts.where((p) => p.enabled).toList(),
        );
      }
      setState(() {
        _layout = layout;
        _profiles = activeProfiles;
        _presets = activePresets;
        _selectedProfileId = layout?.capabilityProfileId;
        _assignedProfileId = layout?.capabilityProfileId;
        _selectedPresetId = sourcePresetIsSelectable ? sourcePresetId : null;
        _state = _LoadState.loaded;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'No se pudo cargar: $error';
        _state = _LoadState.error;
      });
    }
  }

  DeviceCapabilityProfile? get _selectedProfile {
    final id = _selectedProfileId;
    if (id == null) return null;
    for (final profile in _profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  DeviceCapabilityProfile? get _assignedProfile {
    final id = _assignedProfileId;
    if (id == null) return null;
    for (final profile in _profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  /// N7.1 §8 — "seleccionar BoardPreset compatible": only presets that
  /// don't already report a missing metric/indicator against the currently
  /// *selected* (not yet applied) profile are offered, matching §11 "otro
  /// perfil compatible → validar keys" before the user even taps Aplicar.
  List<BoardPreset> get _compatiblePresets => _presets
      .where(
        (preset) => missingCapabilityIssues(
          preset: preset,
          profile: _selectedProfile,
        ).isEmpty,
      )
      .toList();

  Future<void> _apply() async {
    final preset = _presets
        .where((p) => p.id == _selectedPresetId)
        .cast<BoardPreset?>()
        .firstOrNull;
    if (preset == null) return;
    setState(() {
      _applying = true;
      _blockedIssues = null;
    });
    try {
      final result = await widget.deviceBoardConfigRepository.applyPreset(
        tenantId: widget.tenantId,
        deviceId: widget.device.id,
        preset: preset,
        profile: _selectedProfile,
        profileId: _selectedProfileId,
        metricsLibrary: _metrics,
        indicatorsLibrary: _indicators,
        cellLayoutCatalog: _cellLayouts,
        expectedLayoutVersion: _layout?.layoutVersion ?? 0,
      );
      if (!mounted) return;
      if (result.isBlocked) {
        setState(() {
          _applying = false;
          _blockedIssues = result.issues;
        });
        return;
      }
      final confirmed = await widget.deviceBoardConfigRepository.fetchOne(
        tenantId: widget.tenantId,
        deviceId: widget.device.id,
      );
      if (!mounted) return;
      setState(() {
        _layout = confirmed ?? result.layout;
        _assignedProfileId = _selectedProfileId;
        _applying = false;
        _selectedPresetId = preset.id;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preset aplicado al Device.')),
      );
    } on FirestoreVersionConflict catch (error) {
      if (!mounted) return;
      setState(() => _applying = false);
      _showConflictDialog(error);
    } catch (error) {
      if (!mounted) return;
      setState(() => _applying = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo aplicar: $error')));
    }
  }

  Future<void> _assignSelectedProfile() async {
    final current =
        _layout ??
        BoardContentLayout(
          deviceId: widget.device.id,
          layoutTemplateId: 'grid_6x4',
          items: const [],
        );
    final next = BoardContentLayout(
      deviceId: current.deviceId,
      layoutTemplateId: current.layoutTemplateId,
      showTitle: current.showTitle,
      titleOverride: current.titleOverride,
      layoutVersion: current.layoutVersion,
      capabilityProfileId: _selectedProfileId,
      sourceBoardPresetId: current.sourceBoardPresetId,
      sourceBoardPresetVersion: current.sourceBoardPresetVersion,
      items: current.items,
    );
    setState(() => _applying = true);
    try {
      await widget.deviceBoardConfigRepository.saveLayout(
        tenantId: widget.tenantId,
        deviceId: widget.device.id,
        layout: next,
        expectedLayoutVersion: _layout?.layoutVersion ?? 0,
        metricCatalog:
            _selectedProfile?.resolve(_metrics, _indicators) ??
            emptyDeviceMetricCatalog,
        cellLayoutCatalog: _cellLayouts,
      );
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() => _applying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo asignar el perfil: $error')),
        );
      }
    }
  }

  /// N7.1 §12 — "Restablecer desde preset debe confirmar porque reemplaza
  /// la personalización del Device": re-runs the exact same
  /// [DeviceBoardConfigRepository.applyPreset] the layout was originally
  /// built from (its own [BoardContentLayout.sourceBoardPresetId]), against
  /// the Device's *currently assigned* profile — never a stale one.
  Future<void> _resetFromPreset() async {
    final layout = _layout;
    final sourcePresetId = layout?.sourceBoardPresetId;
    if (sourcePresetId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restablecer desde preset'),
        content: const Text(
          'Esto reemplaza toda la personalización actual del Device por el '
          'contenido del preset de origen. Los cambios manuales hechos en '
          'el editor de este Device se perderán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restablecer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final preset = _presets
        .where((p) => p.id == sourcePresetId)
        .cast<BoardPreset?>()
        .firstOrNull;
    if (preset == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El preset de origen ya no existe — no se puede restablecer.',
          ),
        ),
      );
      return;
    }
    setState(() => _selectedPresetId = preset.id);
    await _apply();
  }

  void _showConflictDialog(FirestoreVersionConflict error) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('configuration_conflict'),
        content: Text(
          'Otra sesión modificó este Device mientras editabas '
          '(versión esperada ${error.expectedVersion}, actual '
          '${error.actualVersion}). Recargá antes de reintentar — nada se '
          'sobrescribió.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _load();
            },
            child: const Text('Recargar'),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditor() async {
    final layout =
        _layout ??
        BoardContentLayout(
          deviceId: widget.device.id,
          layoutTemplateId: 'grid_6x4',
          capabilityProfileId: _selectedProfileId,
          items: const [],
        );
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => BoardEditorPage(
          isOwner: widget.isOwner,
          deviceContext: BoardEditorDeviceContext(
            tenantId: widget.tenantId,
            deviceId: widget.device.id,
            initialLayout: layout,
            // N7.1.1 §9 (finding A5) — `0` exactly when `_layout` is null
            // (no remote document yet), never derived from the placeholder
            // `layout` above (whose `layoutVersion` defaults to 1 — the
            // model never allows less — which used to be sent as the
            // expected version and always lost against the repository's
            // correctly-computed "actual 0", producing a spurious conflict
            // on every Device's very first save).
            expectedRemoteVersion: _layout?.layoutVersion ?? 0,
            profile: _assignedProfile,
            profileId: _assignedProfileId,
            onSave: (nextLayout, expectedVersion) =>
                widget.deviceBoardConfigRepository.saveLayout(
                  tenantId: widget.tenantId,
                  deviceId: widget.device.id,
                  layout: nextLayout,
                  expectedLayoutVersion: expectedVersion,
                  // N7.1.1 §6 — the repository's own second validation pass
                  // needs the same resolved catalogs the editor itself used.
                  metricCatalog:
                      _assignedProfile?.resolve(_metrics, _indicators) ??
                      emptyDeviceMetricCatalog,
                  cellLayoutCatalog: _cellLayouts,
                ),
          ),
          metricLibrary: _metrics,
          indicatorLibrary: _indicators,
          cellLayoutPresetCatalog: CellLayoutPresetCatalog(
            initial: _cellLayouts.presets,
          ),
        ),
      ),
    );
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOwner) {
      return const Scaffold(
        body: Center(
          child: Text('Configuración de Board disponible solo para owner'),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Configuración de Board · ${widget.device.name}'),
      ),
      body: switch (_state) {
        _LoadState.loading => const Center(child: CircularProgressIndicator()),
        _LoadState.error => Center(child: Text(_errorMessage ?? 'Error')),
        _LoadState.loaded => _buildLoaded(context),
      },
    );
  }

  Widget _buildLoaded(BuildContext context) {
    final layout = _layout;
    final appliedPreset = _presets
        .where((preset) => preset.id == layout?.sourceBoardPresetId)
        .cast<BoardPreset?>()
        .firstOrNull;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ESTADO ACTUAL',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Text(
              'Asignado: ${_assignedProfileId ?? 'Sin perfil'} · '
              'Seleccionado: ${_selectedProfileId ?? 'Sin perfil'}',
              key: const ValueKey('device-board-profile-state'),
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
            const SizedBox(height: 6),
            Text(
              layout == null
                  ? 'Este Device todavía no tiene un Board configurado.'
                  : 'DeviceBoardLayout v${layout.layoutVersion} · '
                        '${layout.items.length} item(s) · '
                        'actualizado: ${layout.updatedAt?.toLocal() ?? '—'}',
              key: const ValueKey('device-board-config-status'),
            ),
            if (layout?.sourceBoardPresetId != null)
              Container(
                key: const ValueKey('device-board-config-applied-preset'),
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0x3322C55E),
                  border: Border.all(color: const Color(0xFF22C55E)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: Color(0xFF22C55E),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Preset aplicado: '
                        '${appliedPreset?.name ?? layout!.sourceBoardPresetId} '
                        '(v${layout!.sourceBoardPresetVersion})',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            const Text(
              'PERFIL DE CAPACIDADES',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
            const SizedBox(height: 6),
            DropdownButton<String?>(
              key: const ValueKey('device-board-config-profile'),
              isExpanded: true,
              value: _selectedProfileId,
              hint: const Text('Sin perfil'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Sin perfil')),
                for (final profile in _profiles)
                  DropdownMenuItem(
                    value: profile.id,
                    child: Text(profile.name),
                  ),
              ],
              onChanged: (value) => setState(() {
                _selectedProfileId = value;
                _selectedPresetId = null;
              }),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                key: const ValueKey('device-board-config-assign-profile'),
                onPressed: _applying || _selectedProfileId == _assignedProfileId
                    ? null
                    : _assignSelectedProfile,
                child: const Text('Asignar perfil'),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'PRESET DE TABLERO',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
            const SizedBox(height: 6),
            DropdownButton<String?>(
              key: const ValueKey('device-board-config-preset'),
              isExpanded: true,
              value: _selectedPresetId,
              hint: const Text('Elegí un preset compatible'),
              items: [
                for (final preset in _compatiblePresets)
                  DropdownMenuItem(value: preset.id, child: Text(preset.name)),
              ],
              onChanged: (value) => setState(() => _selectedPresetId = value),
            ),
            if (_compatiblePresets.length != _presets.length)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${_presets.length - _compatiblePresets.length} preset(s) '
                  'oculto(s) por no ser compatibles con el perfil elegido.',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
              ),
            if (_blockedIssues != null) ...[
              const SizedBox(height: 12),
              Container(
                key: const ValueKey('device-board-config-blocked-issues'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0x33F87171),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'No se puede aplicar — faltan capacidades:',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    for (final issue in _blockedIssues!)
                      Text('${issue.code}: ${issue.message}'),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  key: const ValueKey('device-board-config-apply'),
                  onPressed: (_selectedPresetId == null || _applying)
                      ? null
                      : _apply,
                  child: Text(_applying ? 'Aplicando…' : 'Aplicar preset'),
                ),
                OutlinedButton(
                  key: const ValueKey('device-board-config-edit'),
                  onPressed: _openEditor,
                  child: const Text('Editar Board del Device'),
                ),
                if (layout?.sourceBoardPresetId != null)
                  OutlinedButton(
                    key: const ValueKey('device-board-config-reset'),
                    onPressed: _resetFromPreset,
                    child: const Text('Restablecer desde preset'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
