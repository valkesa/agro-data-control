import 'package:flutter/material.dart';
import '../board_preview/board_render_config.dart';
import '../board_preview/cell_layout_canvas.dart';
import '../board_preview/preview_board_data.dart';
import '../device_board_layouts/device_board_layout.dart';
import '../device_board_layouts/layout_validation_issue.dart';
import '../device_capabilities/reference_capability_seeds.dart';
import '../layout_templates/grid_placement.dart';
import '../layout_templates/layout_template.dart';
import 'cell_content_resolver.dart';
import 'cell_layout_preset.dart';
import 'cell_layout_preset_catalog.dart';
import 'cell_layout_validator.dart';

const _labelStyle = TextStyle(color: Color(0xFF94A3B8), fontSize: 12);
const _errorStyle = TextStyle(color: Color(0xFFF87171), fontSize: 12);

/// Visual editor for a [CellLayoutPreset]'s internal composition (N6.3):
/// label/value/unit/icon/indicator slots, moved/resized/aligned inside the
/// preset's own subgrid — never pixels, never a parallel geometry (reuses
/// [CellLayoutCanvas], the same widget the real board renders through).
/// Owner-only, entirely in-memory: no Firestore, no Device real (N6.3 §28).
class CellLayoutEditorPage extends StatefulWidget {
  const CellLayoutEditorPage({
    super.key,
    required this.isOwner,
    required this.presetId,
    required this.catalog,
    this.isReferenced,
    this.renderConfig = const BoardRenderConfig(),
  });

  final bool isOwner;
  final String presetId;
  final CellLayoutPresetCatalog catalog;

  /// Whether some Board/BoardPreset in this session already references this
  /// exact preset id — gates direct editing of a global/shared preset
  /// (N6.3 §3). When null, direct editing is always offered (e.g. a preset
  /// created from a picker that has no such context yet).
  final bool Function(String presetId)? isReferenced;
  final BoardRenderConfig renderConfig;

  @override
  State<CellLayoutEditorPage> createState() => _CellLayoutEditorPageState();
}

class _CellLayoutEditorPageState extends State<CellLayoutEditorPage> {
  late CellLayoutPreset _pristine;
  late List<CellLayoutElement> _elements;
  late bool _enabled;
  String? _selectedElementId;
  bool _moveArmed = false;
  bool _dirty = false;
  bool _editingDirectly = false;

  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFrom(widget.catalog.byId(widget.presetId)!);
    _nameController.text = _pristine.name;
    final isGlobal = widget.catalog.isSeedGlobal(widget.presetId);
    final referenced = widget.isReferenced?.call(widget.presetId) ?? false;
    _editingDirectly = !isGlobal && !referenced;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _loadFrom(CellLayoutPreset preset) {
    _pristine = preset;
    _elements = List.of(preset.elements);
    _enabled = preset.enabled;
    _selectedElementId = null;
    _moveArmed = false;
    _dirty = false;
  }

  int get _width => _pristine.widthCells;
  int get _height => _pristine.heightCells;
  int get _columns => _width * 8;
  int get _rows => _height * 8;

  CellLayoutElement? get _selected {
    final id = _selectedElementId;
    if (id == null) return null;
    for (final e in _elements) {
      if (e.id == id) return e;
    }
    return null;
  }

  void _replaceSelected(
    CellLayoutElement Function(CellLayoutElement current) build,
  ) {
    final id = _selectedElementId;
    if (id == null) return;
    setState(() {
      _elements = [
        for (final e in _elements)
          if (e.id == id) build(e) else e,
      ];
      _dirty = true;
    });
  }

  List<LayoutValidationIssue> get _collisions =>
      CellLayoutValidator.collisions(_elements);

  Set<String> get _outOfBoundsIds => {
    for (final e in _elements)
      if (!e.placement.fitsWithin(_columns, _rows)) e.id,
  };

  Set<String> get _invalidElementIds => {
    ..._outOfBoundsIds,
    for (final c in _collisions) ...[
      if (c.itemId != null) c.itemId!,
      if (c.relatedItemId != null) c.relatedItemId!,
    ],
  };

  void _confirmDiscard(VoidCallback onConfirm) {
    if (!_dirty) {
      onConfirm();
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Descartar cambios?'),
        content: const Text('Hay cambios sin guardar en este diseño de celda.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('cell-editor-discard-confirm'),
            onPressed: () {
              Navigator.of(context).pop();
              onConfirm();
            },
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
  }

  void _reset() {
    setState(() {
      _loadFrom(widget.catalog.byId(_pristine.id) ?? _pristine);
      _nameController.text = _pristine.name;
    });
  }

  void _duplicateAndEdit() {
    final copy = widget.catalog.duplicate(
      widget.presetId,
      name: _nameController.text,
    );
    setState(() {
      _loadFrom(copy);
      _nameController.text = copy.name;
      _editingDirectly = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Se creó una copia local: ${copy.name}')),
    );
  }

  void _save() {
    final activeId = _pristine.id;
    widget.catalog.update(activeId, elements: _elements, enabled: _enabled);
    if (_nameController.text.trim().isNotEmpty &&
        _nameController.text.trim() != _pristine.name) {
      widget.catalog.rename(activeId, name: _nameController.text.trim());
    }
    setState(() {
      _loadFrom(widget.catalog.byId(activeId)!);
      _nameController.text = _pristine.name;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Diseño de celda guardado')));
  }

  String _freshIndicatorId() {
    var i = 0;
    final ids = _elements.map((e) => e.id).toSet();
    while (ids.contains('indicator-$i')) {
      i++;
    }
    return 'indicator-$i';
  }

  void _addIndicatorSlot() {
    final nextSlot = _elements
        .where((e) => e.type == CellElementType.indicator)
        .length;
    if (nextSlot >= 6) return; // sane ceiling; UI-only, not a model limit
    setState(() {
      _elements = [
        ..._elements,
        CellLayoutElement(
          id: _freshIndicatorId(),
          type: CellElementType.indicator,
          placement: InternalGridPlacement(
            x: 0,
            y: 0,
            widthUnits: 2,
            heightUnits: 2,
          ),
          indicatorSlot: nextSlot,
        ),
      ];
      _dirty = true;
    });
  }

  void _removeSelectedIndicatorSlot() {
    final selected = _selected;
    if (selected == null || selected.type != CellElementType.indicator) return;
    final remaining = _elements.where((e) => e.id != selected.id).toList();
    final indicators =
        remaining.where((e) => e.type == CellElementType.indicator).toList()
          ..sort((a, b) => a.indicatorSlot!.compareTo(b.indicatorSlot!));
    final ordinals = {
      for (var i = 0; i < indicators.length; i++) indicators[i].id: i,
    };
    setState(() {
      _elements = [
        for (final e in remaining)
          if (e.type != CellElementType.indicator)
            e
          else
            CellLayoutElement(
              id: e.id,
              type: e.type,
              placement: e.placement,
              indicatorSlot: ordinals[e.id],
              horizontalAlignment: e.horizontalAlignment,
              verticalAlignment: e.verticalAlignment,
              textStyle: e.textStyle,
              visibility: e.visibility,
              sizeRole: e.sizeRole,
            ),
      ];
      _selectedElementId = null;
      _moveArmed = false;
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOwner) {
      return const Scaffold(
        body: Center(child: Text('Diseño de celda disponible solo para owner')),
      );
    }
    final invalidIds = _invalidElementIds;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmDiscard(() => Navigator.of(context).pop());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: () =>
                _confirmDiscard(() => Navigator.of(context).pop(_pristine.id)),
          ),
          title: const Text('Diseño de celda'),
          actions: [
            IconButton(
              key: const ValueKey('cell-editor-reset'),
              tooltip: 'Restaurar',
              icon: const Icon(Icons.restart_alt),
              onPressed: _dirty ? _reset : null,
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 820;
                    final canvas = _canvasPanel(invalidIds);
                    final properties = _propertiesPanel(invalidIds);
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          canvas,
                          const SizedBox(height: 16),
                          properties,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: canvas),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: properties),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                _indicatorSlotsPanel(),
                const SizedBox(height: 16),
                _actionsBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final isGlobal = widget.catalog.isSeedGlobal(_pristine.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'EDITOR DE DISEÑO DE CELDA — OWNER ONLY',
          style: TextStyle(
            color: Color(0xFF38BDF8),
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$_width × $_height externo → $_columns × $_rows interno'
          '${isGlobal ? ' · diseño global compartido' : ''}',
          style: _labelStyle,
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 320,
          child: TextField(
            key: const ValueKey('cell-editor-name'),
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Nombre del diseño'),
            onChanged: (_) => setState(() => _dirty = true),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _dirty ? 'Cambios sin guardar' : 'Sin cambios',
          key: const ValueKey('cell-editor-dirty-state'),
          style: _labelStyle,
        ),
        if (!_editingDirectly) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF351F28),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Este diseño es global o está referenciado por otros boards. '
                  'Para no afectarlos, editá una copia local.',
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const ValueKey('cell-editor-duplicate'),
                  onPressed: _duplicateAndEdit,
                  child: const Text('Duplicar diseño de celda'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: const ValueKey('cell-editor-edit-global-anyway'),
                  onPressed: () => setState(() => _editingDirectly = true),
                  child: const Text('Editar igual'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _canvasPanel(Set<String> invalidIds) {
    // N6.5.2: `referenceMetricCatalog` (a raw DeviceMetricCatalog) was
    // retired with the library/profile split — this demo panel resolves
    // the same `environment_room_v1` reference profile instead, purely as
    // a stable non-productive preview, same as before.
    final referenceCatalog = referenceCapabilityProfile.resolve(
      sharedMetricLibraryStore,
      sharedIndicatorLibraryStore,
    );
    final metric = referenceCatalog.metricByKey('tempInterior');
    final demoIndicatorSlots = _elements
        .where((e) => e.type == CellElementType.indicator)
        .length;
    final demoIndicatorKeys =
        (referenceCatalog.availableIndicators['tempInterior'] ??
                const <String>[])
            .take(demoIndicatorSlots)
            .toList();
    final virtualTemplate = LayoutTemplate(
      id: 'cell-editor-virtual',
      name: 'cell editor virtual',
      columns: _width,
      rows: _height,
    );
    List<ResolvedCellElement>? resolved;
    if (metric != null && invalidIds.isEmpty && _enabled) {
      try {
        final draftPreset = CellLayoutPreset(
          id: _pristine.id,
          name: _nameController.text.isEmpty
              ? _pristine.name
              : _nameController.text,
          widthCells: _width,
          heightCells: _height,
          enabled: _enabled,
          elements: _elements,
        );
        final demoItem = DeviceBoardLayoutItem(
          id: 'cell-editor',
          metricKey: 'tempInterior',
          placement: GridPlacement(
            x: 0,
            y: 0,
            widthCells: _width,
            heightCells: _height,
          ),
          cellLayoutPresetId: draftPreset.id,
          indicatorKeys: demoIndicatorKeys,
        );
        resolved = CellContentResolver.resolve(
          metric,
          demoItem,
          draftPreset,
          template: virtualTemplate,
        );
      } catch (_) {
        resolved = null;
      }
    }
    return Container(
      key: const ValueKey('cell-editor-canvas-panel'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1120),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2A3C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SUBGRILLA INTERNA',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Métrica demo de referencia (Temperatura interior · 24.6 · °C) — '
            'no pertenece a un Device real, solo para diseñar el diseño de celda.',
            style: _labelStyle,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 360,
            child: metric == null
                ? const Center(child: Text('Métrica demo no disponible'))
                : CellLayoutCanvas(
                    columns: _columns,
                    rows: _rows,
                    resolved: resolved,
                    rawElements: resolved == null ? _elements : null,
                    catalog: referenceCatalog,
                    data: samplePreviewData,
                    metric: metric,
                    itemIdForKeys: 'cell-editor',
                    editorMode: true,
                    showGrid: true,
                    selectedElementId: _selectedElementId,
                    invalidElementIds: invalidIds,
                    onElementTap: (id) => setState(() {
                      _selectedElementId = id;
                    }),
                    underlayBuilder: !_moveArmed
                        ? null
                        : (unit) => _MoveTapGrid(
                            columns: _columns,
                            rows: _rows,
                            unit: unit,
                            onTap: (x, y) {
                              final current = _selected;
                              if (current == null) return;
                              _replaceSelected(
                                (e) => CellLayoutElement(
                                  id: e.id,
                                  type: e.type,
                                  placement: InternalGridPlacement(
                                    x: x,
                                    y: y,
                                    widthUnits: e.placement.widthUnits,
                                    heightUnits: e.placement.heightUnits,
                                  ),
                                  indicatorSlot: e.indicatorSlot,
                                  horizontalAlignment: e.horizontalAlignment,
                                  verticalAlignment: e.verticalAlignment,
                                  textStyle: e.textStyle,
                                  visibility: e.visibility,
                                  sizeRole: e.sizeRole,
                                ),
                              );
                            },
                          ),
                  ),
          ),
          if (invalidIds.isNotEmpty) ...[
            const SizedBox(height: 12),
            _issuesBox(),
          ],
        ],
      ),
    );
  }

  Widget _issuesBox() => Container(
    key: const ValueKey('cell-editor-issues'),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFF351F28),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.orange),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final id in _outOfBoundsIds)
          Text(
            'internal_out_of_bounds · $id: excede la subgrilla derivada',
            style: _errorStyle,
          ),
        for (final c in _collisions)
          Text(
            'internal_collision · ${c.itemId} ↔ ${c.relatedItemId}: elementos superpuestos',
            style: _errorStyle,
          ),
      ],
    ),
  );

  Widget _propertiesPanel(Set<String> invalidIds) {
    final selected = _selected;
    return Container(
      key: const ValueKey('cell-editor-properties-panel'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1120),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2A3C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PROPIEDADES',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Habilitado:', style: _labelStyle),
              Switch(
                key: const ValueKey('cell-editor-enabled'),
                value: _enabled,
                onChanged: (v) => setState(() {
                  _enabled = v;
                  _dirty = true;
                }),
              ),
            ],
          ),
          const Divider(color: Color(0xFF1F2A3C)),
          if (selected == null)
            const Text(
              'Tocá un elemento en la subgrilla para editarlo.',
              style: _labelStyle,
            )
          else
            _elementProperties(selected, invalidIds),
        ],
      ),
    );
  }

  Widget _elementProperties(CellLayoutElement e, Set<String> invalidIds) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          e.type == CellElementType.indicator
              ? 'Elemento: Indicator slot ${e.indicatorSlot}'
              : 'Seleccionado: ${e.id} (${e.type.name})',
          key: const ValueKey('cell-editor-selected-label'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (invalidIds.contains(e.id))
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Este elemento tiene un problema de geometría',
              style: _errorStyle,
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            IconButton(
              key: const ValueKey('cell-editor-move-up'),
              tooltip: 'Mover arriba',
              icon: const Icon(Icons.arrow_upward),
              onPressed: e.placement.y > 0
                  ? () => _moveSelectedBy(0, -1)
                  : null,
            ),
            IconButton(
              key: const ValueKey('cell-editor-move-down'),
              tooltip: 'Mover abajo',
              icon: const Icon(Icons.arrow_downward),
              onPressed: () => _moveSelectedBy(0, 1),
            ),
            IconButton(
              key: const ValueKey('cell-editor-move-left'),
              tooltip: 'Mover izquierda',
              icon: const Icon(Icons.arrow_back),
              onPressed: e.placement.x > 0
                  ? () => _moveSelectedBy(-1, 0)
                  : null,
            ),
            IconButton(
              key: const ValueKey('cell-editor-move-right'),
              tooltip: 'Mover derecha',
              icon: const Icon(Icons.arrow_forward),
              onPressed: () => _moveSelectedBy(1, 0),
            ),
            FilterChip(
              key: const ValueKey('cell-editor-move-with-click'),
              label: const Text('Mover con clic'),
              selected: _moveArmed,
              onSelected: (v) => setState(() => _moveArmed = v),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Ancho:', style: _labelStyle),
            _stepper(
              value: e.placement.widthUnits,
              keyPrefix: 'cell-editor-width',
              onChanged: (v) => _resizeSelected(widthUnits: v),
            ),
            const SizedBox(width: 16),
            const Text('Alto:', style: _labelStyle),
            _stepper(
              value: e.placement.heightUnits,
              keyPrefix: 'cell-editor-height',
              onChanged: (v) => _resizeSelected(heightUnits: v),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Horizontal:', style: _labelStyle),
            const SizedBox(width: 8),
            DropdownButton<CellHorizontalAlignment>(
              key: const ValueKey('cell-editor-h-align'),
              value: e.horizontalAlignment ?? CellHorizontalAlignment.center,
              items: [
                for (final a in CellHorizontalAlignment.values)
                  DropdownMenuItem(value: a, child: Text(a.name)),
              ],
              onChanged: (v) =>
                  _replaceSelected((c) => _withAlignment(c, horizontal: v)),
            ),
          ],
        ),
        Row(
          children: [
            const Text('Vertical:', style: _labelStyle),
            const SizedBox(width: 8),
            DropdownButton<CellVerticalAlignment>(
              key: const ValueKey('cell-editor-v-align'),
              value: e.verticalAlignment ?? CellVerticalAlignment.center,
              items: [
                for (final a in CellVerticalAlignment.values)
                  DropdownMenuItem(value: a, child: Text(a.name)),
              ],
              onChanged: (v) =>
                  _replaceSelected((c) => _withAlignment(c, vertical: v)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Tamaño:', style: _labelStyle),
            const SizedBox(width: 8),
            DropdownButton<CellSizeRole>(
              key: const ValueKey('cell-editor-size-role'),
              value: e.sizeRole,
              items: [
                for (final s in CellSizeRole.values)
                  DropdownMenuItem(value: s, child: Text(s.name)),
              ],
              onChanged: (v) =>
                  _replaceSelected((c) => _withSizeRole(c, v ?? c.sizeRole)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Visible:', style: _labelStyle),
            Switch(
              key: const ValueKey('cell-editor-visible'),
              value: e.visibility == CellVisibility.visible,
              onChanged: (v) => _replaceSelected(
                (c) => _withVisibility(
                  c,
                  v ? CellVisibility.visible : CellVisibility.hidden,
                ),
              ),
            ),
          ],
        ),
        if (e.type == CellElementType.value ||
            e.type == CellElementType.label ||
            e.type == CellElementType.unit) ...[
          const Divider(color: Color(0xFF1F2A3C)),
          const Text('Texto', style: _labelStyle),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Peso:', style: _labelStyle),
              const SizedBox(width: 8),
              DropdownButton<CellFontWeight>(
                key: const ValueKey('cell-editor-font-weight'),
                value: e.textStyle?.weight ?? CellFontWeight.normal,
                items: [
                  for (final w in CellFontWeight.values)
                    DropdownMenuItem(value: w, child: Text(w.name)),
                ],
                onChanged: (v) =>
                    _replaceSelected((c) => _withTextStyle(c, weight: v)),
              ),
              const SizedBox(width: 16),
              const Text('Líneas:', style: _labelStyle),
              _stepper(
                value: e.textStyle?.maxLines ?? 1,
                keyPrefix: 'cell-editor-max-lines',
                min: 1,
                onChanged: (v) =>
                    _replaceSelected((c) => _withTextStyle(c, maxLines: v)),
              ),
            ],
          ),
        ],
        if (e.type == CellElementType.indicator)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              key: const ValueKey('cell-editor-delete-selected-slot'),
              onPressed: _removeSelectedIndicatorSlot,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Eliminar slot seleccionado'),
            ),
          ),
      ],
    );
  }

  void _moveSelectedBy(int dx, int dy) {
    final e = _selected;
    if (e == null) return;
    final nx = e.placement.x + dx;
    final ny = e.placement.y + dy;
    if (nx < 0 || ny < 0) return;
    _replaceSelected(
      (c) => CellLayoutElement(
        id: c.id,
        type: c.type,
        placement: InternalGridPlacement(
          x: nx,
          y: ny,
          widthUnits: c.placement.widthUnits,
          heightUnits: c.placement.heightUnits,
        ),
        indicatorSlot: c.indicatorSlot,
        horizontalAlignment: c.horizontalAlignment,
        verticalAlignment: c.verticalAlignment,
        textStyle: c.textStyle,
        visibility: c.visibility,
        sizeRole: c.sizeRole,
      ),
    );
  }

  void _resizeSelected({int? widthUnits, int? heightUnits}) {
    _replaceSelected(
      (c) => CellLayoutElement(
        id: c.id,
        type: c.type,
        placement: InternalGridPlacement(
          x: c.placement.x,
          y: c.placement.y,
          widthUnits: widthUnits ?? c.placement.widthUnits,
          heightUnits: heightUnits ?? c.placement.heightUnits,
        ),
        indicatorSlot: c.indicatorSlot,
        horizontalAlignment: c.horizontalAlignment,
        verticalAlignment: c.verticalAlignment,
        textStyle: c.textStyle,
        visibility: c.visibility,
        sizeRole: c.sizeRole,
      ),
    );
  }

  static CellLayoutElement _withAlignment(
    CellLayoutElement c, {
    CellHorizontalAlignment? horizontal,
    CellVerticalAlignment? vertical,
  }) => CellLayoutElement(
    id: c.id,
    type: c.type,
    placement: c.placement,
    indicatorSlot: c.indicatorSlot,
    horizontalAlignment: horizontal ?? c.horizontalAlignment,
    verticalAlignment: vertical ?? c.verticalAlignment,
    textStyle: c.textStyle,
    visibility: c.visibility,
    sizeRole: c.sizeRole,
  );

  static CellLayoutElement _withSizeRole(
    CellLayoutElement c,
    CellSizeRole role,
  ) => CellLayoutElement(
    id: c.id,
    type: c.type,
    placement: c.placement,
    indicatorSlot: c.indicatorSlot,
    horizontalAlignment: c.horizontalAlignment,
    verticalAlignment: c.verticalAlignment,
    textStyle: c.textStyle,
    visibility: c.visibility,
    sizeRole: role,
  );

  static CellLayoutElement _withVisibility(
    CellLayoutElement c,
    CellVisibility v,
  ) => CellLayoutElement(
    id: c.id,
    type: c.type,
    placement: c.placement,
    indicatorSlot: c.indicatorSlot,
    horizontalAlignment: c.horizontalAlignment,
    verticalAlignment: c.verticalAlignment,
    textStyle: c.textStyle,
    visibility: v,
    sizeRole: c.sizeRole,
  );

  static CellLayoutElement _withTextStyle(
    CellLayoutElement c, {
    CellFontWeight? weight,
    int? maxLines,
  }) {
    final current = c.textStyle ?? CellTextStyle();
    return CellLayoutElement(
      id: c.id,
      type: c.type,
      placement: c.placement,
      indicatorSlot: c.indicatorSlot,
      horizontalAlignment: c.horizontalAlignment,
      verticalAlignment: c.verticalAlignment,
      textStyle: CellTextStyle(
        fontRole: current.fontRole,
        weight: weight ?? current.weight,
        maxLines: maxLines ?? current.maxLines,
      ),
      visibility: c.visibility,
      sizeRole: c.sizeRole,
    );
  }

  Widget _stepper({
    required int value,
    required String keyPrefix,
    required ValueChanged<int> onChanged,
    int min = 1,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        key: ValueKey('$keyPrefix-minus'),
        tooltip: keyPrefix == 'cell-editor-width'
            ? 'Reducir ancho'
            : keyPrefix == 'cell-editor-height'
            ? 'Reducir alto'
            : 'Reducir líneas',
        icon: const Icon(Icons.remove, size: 16),
        onPressed: value > min ? () => onChanged(value - 1) : null,
      ),
      Text('$value', style: const TextStyle(color: Colors.white)),
      IconButton(
        key: ValueKey('$keyPrefix-plus'),
        tooltip: keyPrefix == 'cell-editor-width'
            ? 'Aumentar ancho'
            : keyPrefix == 'cell-editor-height'
            ? 'Aumentar alto'
            : 'Aumentar líneas',
        icon: const Icon(Icons.add, size: 16),
        onPressed: () => onChanged(value + 1),
      ),
    ],
  );

  Widget _indicatorSlotsPanel() {
    final indicators = _elements
        .where((e) => e.type == CellElementType.indicator)
        .length;
    return Container(
      key: const ValueKey('cell-editor-indicator-slots-panel'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1120),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2A3C)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Indicator slots: $indicators',
            style: const TextStyle(color: Colors.white),
          ),
          for (final element
              in (_elements
                  .where((e) => e.type == CellElementType.indicator)
                  .toList()
                ..sort((a, b) => a.indicatorSlot!.compareTo(b.indicatorSlot!))))
            ChoiceChip(
              key: ValueKey('cell-editor-select-slot-${element.indicatorSlot}'),
              label: Text('Indicator slot ${element.indicatorSlot}'),
              selected: _selectedElementId == element.id,
              onSelected: (_) => setState(() {
                _selectedElementId = element.id;
                _moveArmed = false;
              }),
            ),
          OutlinedButton(
            key: const ValueKey('cell-editor-add-slot'),
            onPressed: _addIndicatorSlot,
            child: const Text('Agregar slot'),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _actionsBar() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      FilledButton(
        key: const ValueKey('cell-editor-save'),
        onPressed: _dirty && _editingDirectly ? _save : null,
        child: const Text('Guardar diseño de celda'),
      ),
      const SizedBox(width: 8),
      TextButton(
        onPressed: () =>
            _confirmDiscard(() => Navigator.of(context).pop(_pristine.id)),
        child: const Text('Volver al Board'),
      ),
    ],
  );
}

class _MoveTapGrid extends StatelessWidget {
  const _MoveTapGrid({
    required this.columns,
    required this.rows,
    required this.unit,
    required this.onTap,
  });
  final int columns;
  final int rows;
  final double unit;
  final void Function(int x, int y) onTap;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      for (var y = 0; y < rows; y++)
        for (var x = 0; x < columns; x++)
          Positioned(
            key: ValueKey('cell-editor-tap-$x-$y'),
            left: x * unit,
            top: y * unit,
            width: unit,
            height: unit,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(x, y),
            ),
          ),
    ],
  );
}
