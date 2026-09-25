import 'package:flutter/material.dart';
import '../board_preview/board_editor_page.dart';
import '../board_preview/board_render_config.dart';
import '../device_capabilities/device_capability_profile.dart';
import '../device_capabilities/device_capability_profile_store.dart';
import '../device_capabilities/reference_capability_seeds.dart';
import '../device_metric_catalogs/device_metric_catalog.dart';
import '../layout_templates/layout_template.dart';
import 'board_preset.dart';
import 'board_preset_catalog.dart';

const _labelStyle = TextStyle(color: Color(0xFF94A3B8), fontSize: 12);

/// Owner-only list of [BoardPreset]s (N6.2 §9/§10): create, duplicate,
/// rename/redescribe, and jump into [BoardEditorPage] in preset mode to
/// edit content. Entirely in-memory — no Tenant/Site/Device selector, no
/// Firestore, no Device assignment (N6.2 §19).
class BoardPresetsPage extends StatefulWidget {
  BoardPresetsPage({
    super.key,
    required this.isOwner,
    this.renderConfig = const BoardRenderConfig(),
    BoardPresetCatalog? catalog,
    this.metricCatalog,
    this.capabilityProfileStore,
  }) : catalog = catalog ?? sharedBoardPresetCatalog;

  final bool isOwner;
  final BoardRenderConfig renderConfig;
  final BoardPresetCatalog catalog;

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
  @override
  void initState() {
    super.initState();
    widget.catalog.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.catalog.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  Future<void> _openEditor(String presetId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BoardEditorPage(
          isOwner: widget.isOwner,
          renderConfig: widget.renderConfig,
          presetId: presetId,
          presetCatalog: widget.catalog,
          metricCatalog: widget.metricCatalog,
          capabilityProfileStore: widget.capabilityProfileStore,
        ),
      ),
    );
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
            profiles:
                (widget.capabilityProfileStore ??
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
    if (!mounted) return;
    await _openEditor(preset.id);
  }

  Future<void> _duplicatePreset(BoardPreset preset) async {
    widget.catalog.duplicate(preset.id);
  }

  Future<void> _renamePreset(BoardPreset preset) async {
    final result = await showDialog<({String name, String description})>(
      context: context,
      builder: (context) => _RenamePresetDialog(preset: preset),
    );
    if (result == null) return;
    widget.catalog.rename(
      preset.id,
      name: result.name,
      description: result.description,
    );
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
      appBar: AppBar(title: const Text('Board Presets')),
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
                'Configuraciones reutilizables e independientes de '
                'Tenant/Site/Device — todavía en memoria, sin Firestore.',
                style: _labelStyle,
              ),
              const SizedBox(height: 16),
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

  /// N6.5.1 §3, renamed N6.5.2 §18: `null` means "Sin perfil", the required
  /// initial value — never pre-selected to a real profile.
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
            const Text('Perfil de capacidades:', style: _labelStyle),
            const SizedBox(height: 4),
            DropdownButton<String?>(
              key: const ValueKey('new-preset-profile'),
              isExpanded: true,
              value: _capabilityProfileId,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Sin perfil', overflow: TextOverflow.ellipsis),
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
