import 'package:flutter/material.dart';
import '../board_preview/board_editor_page.dart';
import '../board_preview/board_render_config.dart';
import '../device_capabilities/device_capability_profile.dart';
import '../device_capabilities/device_capability_profile_store.dart';
import '../device_capabilities/reference_capability_seeds.dart';
import '../device_capabilities/capability_library_store.dart';
import '../cell_layout_presets/cell_layout_preset_catalog.dart';
import '../device_metric_catalogs/device_metric_catalog.dart';
import '../layout_templates/layout_template.dart';
import 'board_preset.dart';
import 'board_preset_catalog.dart';
import '../services/firestore_version_conflict.dart';
import '../services/global_board_configuration_service.dart';

const _labelStyle = TextStyle(color: Color(0xFF94A3B8), fontSize: 12);

/// Owner-only list of [BoardPreset]s: create, duplicate, rename/redescribe,
/// and open [BoardEditorPage] in preset mode. The default production path is
/// backed by [GlobalBoardConfigurationService]; an injected catalog keeps
/// tests and development tools deterministic. It never assigns a Device.
class BoardPresetsPage extends StatefulWidget {
  BoardPresetsPage({
    super.key,
    required this.isOwner,
    this.renderConfig = const BoardRenderConfig(),
    BoardPresetCatalog? catalog,
    this.metricCatalog,
    this.capabilityProfileStore,
    GlobalBoardConfigurationService? configurationService,
  }) : catalog = catalog ?? BoardPresetCatalog(initial: const []),
       configurationService =
           configurationService ?? sharedGlobalBoardConfigurationService,
       firestoreBacked = catalog == null;

  final bool isOwner;
  final BoardRenderConfig renderConfig;
  final BoardPresetCatalog catalog;
  final GlobalBoardConfigurationService configurationService;
  final bool firestoreBacked;

  /// N6.4 §21/§26: lets a caller (a test, or the `tool/board_preview_main`
  /// dev entrypoint's `?emptyCatalog=1`) open every preset's editor against
  /// a [DeviceMetricCatalog] with zero metrics — proving a BoardPreset can
  /// be fully designed without one. Defaults to [BoardEditorPage]'s own
  /// default ([referenceCapabilityProfile]'s resolved catalog) when
  /// omitted, unchanged from before N6.4.
  final DeviceMetricCatalog? metricCatalog;

  /// N6.5 §25/§30, renamed N6.5.2 §17 — forwarded to
  /// [BoardEditorPage.capabilityProfileStore].
  final DeviceCapabilityProfileStore? capabilityProfileStore;

  @override
  State<BoardPresetsPage> createState() => _BoardPresetsPageState();
}

class _BoardPresetsPageState extends State<BoardPresetsPage> {
  bool _loading = false;
  String? _loadError;
  late CellLayoutPresetCatalog _cellLayouts;
  late MetricLibraryStore _metrics;
  late IndicatorLibraryStore _indicators;
  late DeviceCapabilityProfileStore _profiles;

  @override
  void initState() {
    super.initState();
    _cellLayouts = CellLayoutPresetCatalog(initial: const []);
    _metrics = MetricLibraryStore();
    _indicators = IndicatorLibraryStore();
    _profiles = widget.capabilityProfileStore ?? DeviceCapabilityProfileStore();
    widget.catalog.addListener(_onChanged);
    if (widget.firestoreBacked) _load();
  }

  @override
  void dispose() {
    widget.catalog.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final snapshot = await widget.configurationService.load(refresh: refresh);
      widget.catalog.replaceAll(snapshot.boardPresets.where((p) => p.enabled));
      _cellLayouts.replaceAll(snapshot.cellLayouts.where((p) => p.enabled));
      _metrics.replaceAll(
        snapshot.metrics.where((r) => r.enabled).map((r) => r.metric),
      );
      _indicators.replaceAll(
        snapshot.indicators.where((r) => r.enabled).map((r) => r.indicator),
      );
      _profiles.replaceAll(
        snapshot.profiles.where((r) => r.profile.enabled).map((r) => r.profile),
      );
      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = '$error';
        });
      }
    }
  }

  Future<void> _openEditor(String presetId) async {
    final cellVersions = {
      for (final preset in _cellLayouts.presets)
        preset.id: preset.presetVersion,
    };
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BoardEditorPage(
          isOwner: widget.isOwner,
          renderConfig: widget.renderConfig,
          presetId: presetId,
          presetCatalog: widget.catalog,
          metricCatalog: widget.metricCatalog,
          capabilityProfileStore: widget.firestoreBacked
              ? _profiles
              : widget.capabilityProfileStore,
          metricLibrary: widget.firestoreBacked ? _metrics : null,
          indicatorLibrary: widget.firestoreBacked ? _indicators : null,
          cellLayoutPresetCatalog: widget.firestoreBacked ? _cellLayouts : null,
          onPresetSave: widget.firestoreBacked
              ? (draft, expectedVersion) async {
                  // A design created from a generic cell default must exist
                  // before the BoardPreset that traces it is persisted.
                  for (final cell in _cellLayouts.presets) {
                    final oldVersion = cellVersions[cell.id];
                    if (oldVersion == null) {
                      await widget.configurationService.cellLayoutPresets
                          .create(cell);
                      cellVersions[cell.id] = 1;
                    } else if (cell.presetVersion != oldVersion) {
                      final savedVersion = await widget
                          .configurationService
                          .cellLayoutPresets
                          .save(preset: cell, expectedVersion: oldVersion);
                      cellVersions[cell.id] = savedVersion;
                    }
                  }
                  final savedVersion = await widget
                      .configurationService
                      .boardPresets
                      .save(preset: draft, expectedVersion: expectedVersion);
                  widget.configurationService.invalidate();
                  return savedVersion;
                }
              : null,
        ),
      ),
    );
    if (widget.firestoreBacked && mounted) {
      widget.configurationService.invalidate();
      await _load(refresh: true);
    }
  }

  Future<void> _createPreset() async {
    final result =
        await showDialog<
          ({
            String name,
            String description,
            LayoutTemplate layout,
            String? capabilityProfileId,
          })
        >(
          context: context,
          builder: (context) => _NewPresetDialog(
            profiles: widget.firestoreBacked
                ? _profiles.profiles
                : (widget.capabilityProfileStore ??
                          sharedDeviceCapabilityProfileStore)
                      .profiles,
          ),
        );
    if (result == null) return;
    final preset = widget.catalog.create(
      name: result.name,
      description: result.description,
      layout: result.layout,
      capabilityProfileId: result.capabilityProfileId,
    );
    if (widget.firestoreBacked) {
      try {
        final layout = result.layout;
        try {
          await widget.configurationService.layoutTemplates.create(layout);
        } on FirestoreAlreadyExists {
          // Reusing an existing global geometry is expected.
        }
        await widget.configurationService.boardPresets.create(preset);
        widget.configurationService.invalidate();
        await _load(refresh: true);
      } catch (error) {
        widget.catalog.remove(preset.id);
        if (mounted) setState(() => _loadError = 'No se pudo crear: $error');
        return;
      }
    }
    if (!mounted) return;
    await _openEditor(preset.id);
  }

  Future<void> _duplicatePreset(BoardPreset preset) async {
    final copy = widget.catalog.duplicate(preset.id);
    if (widget.firestoreBacked) {
      try {
        await widget.configurationService.boardPresets.create(copy);
        widget.configurationService.invalidate();
        await _load(refresh: true);
      } catch (error) {
        widget.catalog.remove(copy.id);
        if (mounted) setState(() => _loadError = 'No se pudo duplicar: $error');
      }
    }
  }

  Future<void> _renamePreset(BoardPreset preset) async {
    final result = await showDialog<({String name, String description})>(
      context: context,
      builder: (context) => _RenamePresetDialog(preset: preset),
    );
    if (result == null) return;
    if (widget.firestoreBacked) {
      try {
        await widget.configurationService.boardPresets.save(
          preset: preset.copyWith(
            name: result.name,
            description: result.description,
          ),
          expectedVersion: preset.presetVersion,
        );
        widget.configurationService.invalidate();
        await _load(refresh: true);
      } catch (error) {
        if (mounted) {
          setState(() => _loadError = 'No se pudo renombrar: $error');
        }
      }
    } else {
      widget.catalog.rename(
        preset.id,
        name: result.name,
        description: result.description,
      );
    }
  }

  Future<void> _deletePreset(BoardPreset preset) async {
    try {
      final count = await widget.configurationService.boardPresets
          .countDeviceUsages(preset.id);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Eliminar BoardPreset'),
          content: Text(
            'Este preset fue usado para inicializar $count Devices.\n\n'
            'Los Devices existentes NO serán modificados. ¿Desea eliminarlo?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await widget.configurationService.boardPresets.delete(
        preset.id,
        expectedVersion: preset.presetVersion,
      );
      widget.configurationService.invalidate();
      await _load(refresh: true);
    } catch (error) {
      if (mounted) setState(() => _loadError = 'No se pudo eliminar: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOwner) {
      return const Scaffold(
        body: Center(child: Text('Board Presets disponible solo para owner')),
      );
    }
    final presets = widget.catalog.presets;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Board Presets'),
        actions: [
          if (widget.firestoreBacked)
            IconButton(
              onPressed: () => _load(refresh: true),
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      floatingActionButton: _loading ? const CircularProgressIndicator() : null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'BOARD PRESETS — OWNER ONLY',
                style: TextStyle(
                  color: Color(0xFF38BDF8),
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Configuraciones reutilizables e independientes de Tenant/Site/Device.',
                style: _labelStyle,
              ),
              const SizedBox(height: 16),
              if (_loadError != null) ...[
                Text(
                  _loadError!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
                const SizedBox(height: 12),
              ],
              if (!_loading && presets.isEmpty)
                const Text(
                  'No hay BoardPresets configurados.',
                  style: _labelStyle,
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const ValueKey('presets-new'),
                  onPressed: _createPreset,
                  icon: const Icon(Icons.add),
                  label: const Text('Nuevo preset'),
                ),
              ),
              const SizedBox(height: 16),
              for (final preset in presets)
                Container(
                  key: ValueKey('preset-row-${preset.id}'),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B1120),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1F2A3C)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preset.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      if (preset.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(preset.description, style: _labelStyle),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        'id: ${preset.id} · layout: ${preset.layoutTemplateId} · '
                        '${preset.items.length} items · v${preset.presetVersion}',
                        style: _labelStyle,
                      ),
                      if (preset.requiredMetricKeys.isNotEmpty ||
                          preset.optionalMetricKeys.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'required: ${preset.requiredMetricKeys.join(', ')}'
                          '${preset.optionalMetricKeys.isEmpty ? '' : ' · optional: ${preset.optionalMetricKeys.join(', ')}'}',
                          style: _labelStyle,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton.tonal(
                            key: ValueKey('preset-edit-${preset.id}'),
                            onPressed: () => _openEditor(preset.id),
                            child: const Text('Editar'),
                          ),
                          OutlinedButton(
                            key: ValueKey('preset-duplicate-${preset.id}'),
                            onPressed: () => _duplicatePreset(preset),
                            child: const Text('Duplicar'),
                          ),
                          if (widget.firestoreBacked)
                            OutlinedButton(
                              key: ValueKey('preset-delete-${preset.id}'),
                              onPressed: () => _deletePreset(preset),
                              child: const Text('Eliminar'),
                            ),
                          OutlinedButton(
                            key: ValueKey('preset-rename-${preset.id}'),
                            onPressed: () => _renamePreset(preset),
                            child: const Text('Renombrar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewPresetDialog extends StatefulWidget {
  const _NewPresetDialog({required this.profiles});

  /// N6.5.1 §2, renamed N6.5.2 §18: populates the "Perfil de capacidades"
  /// selector so a new preset's profile is always an explicit user choice,
  /// never a silent default (§1/§3).
  final List<DeviceCapabilityProfile> profiles;

  @override
  State<_NewPresetDialog> createState() => _NewPresetDialogState();
}

class _NewPresetDialogState extends State<_NewPresetDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  int _columns = 6;
  int _rows = 4;

  /// Optional initial picker filter. `null` exposes every global metric.
  String? _capabilityProfileId;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trimmedName = _nameController.text.trim();
    return AlertDialog(
      title: const Text('Nuevo preset'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('new-preset-name'),
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nombre'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('new-preset-description'),
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Descripción'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Columnas:', style: _labelStyle),
                    _stepper(
                      value: _columns,
                      keyName: 'new-preset-columns',
                      onChanged: (v) => setState(() => _columns = v),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Filas:', style: _labelStyle),
                    _stepper(
                      value: _rows,
                      keyName: 'new-preset-rows',
                      onChanged: (v) => setState(() => _rows = v),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Filtro inicial de métricas:', style: _labelStyle),
            const SizedBox(height: 4),
            DropdownButton<String?>(
              key: const ValueKey('new-preset-profile'),
              isExpanded: true,
              value: _capabilityProfileId,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    'Todas las métricas',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                for (final entry in widget.profiles)
                  DropdownMenuItem<String?>(
                    value: entry.id,
                    child: Text(entry.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (id) => setState(() => _capabilityProfileId = id),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('new-preset-confirm'),
          onPressed: trimmedName.isEmpty
              ? null
              : () => Navigator.of(context).pop((
                  name: trimmedName,
                  description: _descriptionController.text.trim(),
                  layout: buildLayoutTemplate(_columns, _rows),
                  capabilityProfileId: _capabilityProfileId,
                )),
          child: const Text('Crear'),
        ),
      ],
    );
  }

  Widget _stepper({
    required int value,
    required String keyName,
    required ValueChanged<int> onChanged,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        key: ValueKey('$keyName-minus'),
        icon: const Icon(Icons.remove, size: 16),
        onPressed: value > 1 ? () => onChanged(value - 1) : null,
      ),
      Text('$value', style: const TextStyle(color: Colors.white)),
      IconButton(
        key: ValueKey('$keyName-plus'),
        icon: const Icon(Icons.add, size: 16),
        onPressed: () => onChanged(value + 1),
      ),
    ],
  );
}

class _RenamePresetDialog extends StatefulWidget {
  const _RenamePresetDialog({required this.preset});
  final BoardPreset preset;
  @override
  State<_RenamePresetDialog> createState() => _RenamePresetDialogState();
}

class _RenamePresetDialogState extends State<_RenamePresetDialog> {
  late final _nameController = TextEditingController(text: widget.preset.name);
  late final _descriptionController = TextEditingController(
    text: widget.preset.description,
  );

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trimmedName = _nameController.text;
    return AlertDialog(
      title: const Text('Renombrar preset'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('rename-preset-name'),
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nombre'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('rename-preset-description'),
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Descripción'),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'id: ${widget.preset.id} (no editable)',
                style: _labelStyle,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('rename-preset-confirm'),
          onPressed: trimmedName.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop((
                  name: trimmedName.trim(),
                  description: _descriptionController.text.trim(),
                )),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
