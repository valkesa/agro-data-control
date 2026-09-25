import 'package:flutter/material.dart';
import '../board_content/board_content_config.dart';
import '../board_content/board_content_layout.dart'
    show BoardContentItem, BoardContentLayout;
import '../board_presets/board_preset.dart';
import '../board_presets/board_preset_catalog.dart';
import '../cell_layout_presets/cell_layout_catalog.dart';
import '../cell_layout_presets/cell_layout_editor_page.dart';
import '../cell_layout_presets/cell_layout_preset.dart';
import '../cell_layout_presets/cell_layout_preset_catalog.dart';
import '../device_board_layouts/layout_validation_issue.dart';
import '../device_capabilities/device_capability_profile.dart';
import '../device_capabilities/device_capability_profile_store.dart';
import '../device_capabilities/reference_capability_seeds.dart';
import '../device_metric_catalogs/device_metric_catalog.dart';
import '../ui_templates/board/template_icon_resolver.dart';
import 'board_content_renderer.dart';
import 'board_editor_canvas.dart';
import 'board_editor_controller.dart';
import 'board_render_config.dart';
import 'preview_board_data.dart';

const _fieldLabelStyle = TextStyle(color: Color(0xFF94A3B8), fontSize: 12);

/// N6.3 §20 — "ayudas contextuales para imágenes": never show the raw enum
/// name for `sourceType`/`fit`, and label `sourceRef` differently per type
/// so it's clear what to type there. Never changes `ImageBoardContent`'s
/// contract — purely display text.
String imageSourceTypeLabel(BoardImageSourceType type) => switch (type) {
  BoardImageSourceType.asset => 'Asset',
  BoardImageSourceType.url => 'URL',
  BoardImageSourceType.firestoreStorageRef => 'Firebase Storage',
  BoardImageSourceType.deviceMediaRef => 'Media del Device',
};

String imageSourceRefLabel(BoardImageSourceType type) => switch (type) {
  BoardImageSourceType.asset => 'Ruta asset',
  BoardImageSourceType.url => 'URL',
  BoardImageSourceType.firestoreStorageRef => 'Ruta en Storage',
  BoardImageSourceType.deviceMediaRef => 'Referencia de media',
};

String imageFitHelp(BoardImageFit fit) => switch (fit) {
  BoardImageFit.contain => 'Contain — muestra la imagen completa',
  BoardImageFit.cover => 'Cover — llena el espacio y puede recortar',
  BoardImageFit.fill => 'Fill — llena todo y puede deformar',
};
const _errorStyle = TextStyle(color: Color(0xFFF87171), fontSize: 12);

/// N6.4 §19/§20: explicit display order for "Agregar contenido" — never the
/// raw enum declaration order — plus human labels so the chips never show a
/// bare technical enum name.
const _addableContentTypes = [
  BoardContentType.metric,
  BoardContentType.text,
  BoardContentType.icon,
  BoardContentType.image,
  BoardContentType.placeholder,
  BoardContentType.status,
  BoardContentType.latestEvent,
  BoardContentType.dataTable,
  BoardContentType.chart,
];

String boardContentTypeLabel(BoardContentType type) => switch (type) {
  BoardContentType.metric => 'Métrica',
  BoardContentType.text => 'Texto',
  BoardContentType.icon => 'Icono',
  BoardContentType.image => 'Imagen',
  BoardContentType.placeholder => 'Placeholder / Dato pendiente',
  BoardContentType.status => 'Status',
  BoardContentType.latestEvent => 'LatestEvent',
  BoardContentType.dataTable => 'DataTable',
  BoardContentType.chart => 'Chart',
};

String boardBindingModeLabel(BoardBindingMode mode) => switch (mode) {
  BoardBindingMode.unbound => 'Sin vincular',
  BoardBindingMode.demo => 'Demo',
  BoardBindingMode.bound => 'Vinculado',
};

/// Small, generic (never Arco-specific) reusable field/column sets so
/// latestEvent/dataTable have a usable minimum without a full fields editor
/// (N6.1 §8/§9).
final _fieldPresets = <String, List<BoardDataField>>{
  'Simple (1 campo)': [BoardDataField(key: 'value', label: 'Valor')],
  'Evento (fecha + estado)': [
    BoardDataField(
      key: 'timestamp',
      label: 'Fecha / hora',
      format: BoardFieldFormat.dateTime,
    ),
    BoardDataField(
      key: 'state',
      label: 'Estado',
      format: BoardFieldFormat.status,
    ),
  ],
};
final _columnPresets = <String, List<BoardTableColumn>>{
  'Simple (1 columna)': [
    BoardTableColumn(
      field: BoardDataField(key: 'value', label: 'Valor'),
    ),
  ],
  'Registro (fecha + estado)': [
    BoardTableColumn(
      field: BoardDataField(
        key: 'timestamp',
        label: 'Fecha / hora',
        format: BoardFieldFormat.dateTime,
      ),
    ),
    BoardTableColumn(
      field: BoardDataField(
        key: 'state',
        label: 'Estado',
        format: BoardFieldFormat.status,
      ),
    ),
  ],
};

String _errorFrom(Object error) {
  if (error is LayoutValidationException) return error.issues.first.message;
  if (error is ArgumentError) return (error.message ?? error).toString();
  return error.toString();
}

/// Owner-only visual editor for [BoardContentLayout] fixtures. Works
/// entirely on in-memory state (N6 §3/§23): no Firestore repository, no
/// listener, no write to a productive Device. Editing reuses N5.2's
/// approved geometry via [BoardEditorCanvas]/[BoardCanvasLayout]; Preview
/// reuses the exact same read-only [BoardContentRenderer] N5 already ships
/// (N6.1 §6 — two different widgets, not one widget pretending to be both).
/// Every mutation re-runs the existing N3/N4/N4.5 validators — none are
/// reimplemented in this file.
/// N7.1 §13 — bundles everything [BoardEditorPage] needs to open
/// [BoardEditorMode.device] against a real Tenant/Site/Device, mirroring
/// how `presetId`+`presetCatalog` bundle preset mode. [onSave] is the only
/// way this page ever touches Firestore: it never imports
/// `DeviceBoardConfigRepository` itself (§13's own words: "context =
/// Tenant/Site/Device real, profile = Device real, save =
/// DeviceBoardLayoutRepository") — the caller (`DeviceBoardConfigPage`)
/// owns the actual repository call and hands back either the new
/// `layoutVersion` or an error message.
class BoardEditorDeviceContext {
  const BoardEditorDeviceContext({
    required this.tenantId,
    required this.deviceId,
    required this.initialLayout,
    required this.profile,
    required this.profileId,
    required this.onSave,
  });

  final String tenantId;
  final String deviceId;
  final BoardContentLayout initialLayout;
  final DeviceCapabilityProfile? profile;
  final String? profileId;

  /// Returns the new `layoutVersion` on success; throws on failure (a
  /// [FirestoreVersionConflict] or any other error) — [_BoardEditorPageState]
  /// catches it and calls [BoardEditorController.markSaveError] with
  /// `error.toString()`.
  final Future<int> Function(BoardContentLayout layout, int expectedVersion)
  onSave;
}

class BoardEditorPage extends StatefulWidget {
  const BoardEditorPage({
    super.key,
    required this.isOwner,
    this.renderConfig = const BoardRenderConfig(),
    this.presets,
    this.presetId,
    this.presetCatalog,
    this.metricCatalog,
    this.capabilityProfileStore,
    this.deviceContext,
  }) : assert(
         (presetId == null) == (presetCatalog == null),
         'presetId and presetCatalog must be provided together (N6.2 §12).',
       ),
       assert(
         presetId == null || deviceContext == null,
         'preset mode and device mode are mutually exclusive (N7.1 §13).',
       );
  final bool isOwner;
  final BoardRenderConfig renderConfig;
  final CellLayoutCatalog? presets;

  /// When both are non-null, the editor opens in [BoardEditorMode.preset]
  /// against this [BoardPreset] instead of the demo fixture playground
  /// (N6.2 §12/§13). Never set from the "Casos demo" flow.
  final String? presetId;
  final BoardPresetCatalog? presetCatalog;

  /// N7.1 §13 — when set, the editor opens in [BoardEditorMode.device]
  /// against a real Device instead of a [BoardPreset] or demo fixture.
  final BoardEditorDeviceContext? deviceContext;

  /// N6.4 §21/§22/§26: lets a test (or a future caller) open preset mode
  /// against a [DeviceMetricCatalog] with zero metrics — proving a
  /// BoardPreset can be fully designed with no capability profile at all.
  /// When set, the N6.5.2 profile selector is hidden (it's a forced
  /// override, not the preset's own choice) and
  /// [preset.capabilityProfileId] is ignored.
  final DeviceMetricCatalog? metricCatalog;

  /// N6.5 §25/§30, renamed N6.5.2 §17 — the admin registry the profile
  /// selector picks from and [BoardPreset.capabilityProfileId] resolves
  /// against. Defaults to [sharedDeviceCapabilityProfileStore]. Irrelevant
  /// outside preset mode.
  final DeviceCapabilityProfileStore? capabilityProfileStore;
  @override
  State<BoardEditorPage> createState() => _BoardEditorPageState();
}

/// Per-item unsaved-and-invalid draft (N6.2 §1/R1): captured whenever the
/// user navigates away from an item whose text is still showing a field
/// error, so switching selection never silently discards it. Removed again
/// the moment that item's content is next applied successfully.
class _ItemDraft {
  _ItemDraft({this.sourceRef, this.dataSource, this.text, this.error});
  String? sourceRef;
  String? dataSource;
  String? text;
  String? error;
}

/// N6.3 §18: "[Board] [Seleccionado] [Agregar]" — the three tabs of the
/// side panel.
enum _SidePanelTab { board, selected, add }

class _BoardEditorPageState extends State<BoardEditorPage> {
  late int _fixtureIndex;
  late BoardEditorController _controller;

  bool get _presetMode => widget.presetId != null;

  /// N7.1 §13.
  bool get _deviceMode => widget.deviceContext != null;
  bool _debugVisible = false;
  final Map<String, _ItemDraft> _itemDrafts = {};

  // --- N6.3 §16/§18: side panel tabs ("desktop board izquierda / panel
  // derecha", stacked on narrow) ------------------------------------------
  _SidePanelTab _sidePanelTab = _SidePanelTab.board;
  String? _lastAutoTabSelectedId;

  // --- "Add" draft state -----------------------------------------------
  BoardContentType? _pendingType;
  int _pendingX = 0;
  int _pendingY = 0;
  int _pendingWidth = 1;
  int _pendingHeight = 1;
  String? _pendingMetricKey;
  String? _pendingPresetId;
  final Set<String> _pendingIndicatorKeys = {};
  BoardImageSourceType _pendingImageSource =
      BoardImageSourceType.deviceMediaRef;
  BoardImageFit _pendingImageFit = BoardImageFit.contain;
  BoardChartType _pendingChartType = BoardChartType.line;
  List<BoardDataField> _pendingFields = _fieldPresets.values.first;
  List<BoardTableColumn> _pendingColumns = _columnPresets.values.first;
  String? _pendingFieldError;

  // --- N6.4: freeform design pending state -------------------------------
  BoardBindingMode _pendingBindingMode = BoardBindingMode.unbound;
  Map<String, String>? _pendingDemoValues;
  List<Map<String, String>>? _pendingDemoRows;
  String _pendingIconKey = templateIconKeys.first;
  final _pendingIconLabelController = TextEditingController();
  CellSizeRole _pendingIconSizeRole = CellSizeRole.lg;
  CellHorizontalAlignment _pendingIconHAlign = CellHorizontalAlignment.center;
  CellVerticalAlignment _pendingIconVAlign = CellVerticalAlignment.center;
  final _pendingPlaceholderLabelController = TextEditingController(
    text: 'Dato pendiente',
  );
  final _pendingPlaceholderMockValueController = TextEditingController(
    text: '--',
  );
  final _pendingPlaceholderUnitController = TextEditingController();
  String? _pendingPlaceholderIconKey;
  BoardPlaceholderStyle _pendingPlaceholderStyle =
      BoardPlaceholderStyle.neutral;
  CellHorizontalAlignment _pendingTextAlignment = CellHorizontalAlignment.start;
  CellSizeRole _pendingTextSizeRole = CellSizeRole.md;
  CellFontWeight _pendingTextWeight = CellFontWeight.normal;
  int _pendingTextMaxLines = 3;

  // Persistent controllers (N6.1 §3 — never recreated during build).
  final _sourceRefController = TextEditingController(text: 'hero');
  final _dataSourceController = TextEditingController(text: 'device.status');
  final _textController = TextEditingController(text: 'Nota');
  late final TextEditingController _titleOverrideController;

  // --- Selected-item draft state ----------------------------------------
  final _selectedSourceRefController = TextEditingController();
  final _selectedDataSourceController = TextEditingController();
  final _selectedTextController = TextEditingController();
  final _selectedMetricLabelController = TextEditingController();
  final _selectedMetricUnitController = TextEditingController();
  final _selectedIconLabelController = TextEditingController();
  final _selectedPlaceholderLabelController = TextEditingController();
  final _selectedPlaceholderMockValueController = TextEditingController();
  final _selectedPlaceholderUnitController = TextEditingController();
  final _selectedDemoLabelController = TextEditingController();
  String? _syncedSelectedId;
  String? _selectedFieldError;

  bool _repositionArmed = false;

  /// A fresh [CellLayoutCatalog] snapshot of [sharedCellLayoutPresetCatalog]
  /// on every access (N6.3: any "Diseño de celda" created/duplicated/edited
  /// there must be immediately selectable back here). `defaults` stays the
  /// original per-span mapping — creating/editing designs never changes
  /// which one a span defaults to. `widget.presets`, when supplied (tests),
  /// overrides this entirely, unchanged from before N6.3.
  CellLayoutCatalog get _presets =>
      widget.presets ??
      CellLayoutCatalog(
        sharedCellLayoutPresetCatalog.presets,
        defaults: initialCellLayoutCatalog.defaults,
      );

  /// True whenever exiting/switching away would silently lose something:
  /// applied board changes, an in-progress add draft, typed-but-invalid text
  /// still shown as an error on the *current* item (N6.1 §11), or an
  /// unresolved draft parked on any *other* item (N6.2 §1/R1 — drafts are
  /// per item, not just the one currently selected).
  bool get _effectiveDirty =>
      _controller.dirty ||
      _pendingType != null ||
      _pendingFieldError != null ||
      _selectedFieldError != null ||
      _itemDrafts.isNotEmpty;

  /// N6.5 §25/§30, renamed N6.5.2 §17: the admin registry to resolve
  /// [BoardPreset.capabilityProfileId] against, and to populate the profile
  /// selector from.
  DeviceCapabilityProfileStore get _capabilityProfileStore =>
      widget.capabilityProfileStore ?? sharedDeviceCapabilityProfileStore;

  /// `null` means "Sin perfil" (N6.5 §26, N6.5.2 §18) — resolved to the
  /// sentinel empty catalog, never to [referenceCapabilityProfile], so a
  /// preset explicitly set to no profile stays exactly that, even if the
  /// reference profile still exists in the store. Returns both the source
  /// profile (for `suggestedIndicatorsByMetric`, N6.5.2 §8) and its
  /// resolved [DeviceMetricCatalog] (for validation/rendering, unchanged).
  ({DeviceCapabilityProfile? profile, DeviceMetricCatalog catalog})
  _resolveProfile(String? id) {
    if (id == null) return (profile: null, catalog: emptyDeviceMetricCatalog);
    final profile =
        _capabilityProfileStore.byId(id) ?? referenceCapabilityProfile;
    return (
      profile: profile,
      catalog: profile.resolve(
        sharedMetricLibraryStore,
        sharedIndicatorLibraryStore,
      ),
    );
  }

  /// N6.5.2 §8 — the active profile's suggested indicators for [metricKey],
  /// or none: fixture mode, "Sin perfil", and any metricKey the profile
  /// doesn't have a suggestion for all fall back to an empty prefill (the
  /// user still picks freely from every indicator the profile offers).
  List<String> _suggestedIndicatorsFor(String? metricKey) {
    if (metricKey == null) return const [];
    return _controller.profile?.suggestedIndicatorsByMetric[metricKey] ??
        const [];
  }

  @override
  void initState() {
    super.initState();
    if (_presetMode) {
      final preset = widget.presetCatalog!.byId(widget.presetId!);
      if (preset == null) {
        throw StateError('Unknown BoardPreset id "${widget.presetId}"');
      }
      final resolved = widget.metricCatalog == null
          ? _resolveProfile(preset.capabilityProfileId)
          : (profile: null, catalog: widget.metricCatalog!);
      _controller = BoardEditorController.forPreset(
        preset: preset,
        catalog: resolved.catalog,
        profile: resolved.profile,
        profileId: widget.metricCatalog == null
            ? preset.capabilityProfileId
            : null,
      )..addListener(_onControllerChanged);
    } else if (_deviceMode) {
      final ctx = widget.deviceContext!;
      final catalog = ctx.profile?.resolve(
        sharedMetricLibraryStore,
        sharedIndicatorLibraryStore,
      );
      _controller = BoardEditorController.forDevice(
        tenantId: ctx.tenantId,
        layout: ctx.initialLayout,
        catalog: catalog ?? emptyDeviceMetricCatalog,
        profile: ctx.profile,
        profileId: ctx.profileId,
      )..addListener(_onControllerChanged);
    } else {
      _fixtureIndex = 0;
      _controller = BoardEditorController(
        initial: previewBoardFixtures[_fixtureIndex],
      )..addListener(_onControllerChanged);
    }
    _titleOverrideController = TextEditingController(
      text: _controller.titleOverride ?? '',
    );
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    _sourceRefController.dispose();
    _dataSourceController.dispose();
    _textController.dispose();
    _titleOverrideController.dispose();
    _selectedSourceRefController.dispose();
    _selectedDataSourceController.dispose();
    _selectedTextController.dispose();
    _selectedMetricLabelController.dispose();
    _selectedMetricUnitController.dispose();
    _pendingIconLabelController.dispose();
    _pendingPlaceholderLabelController.dispose();
    _pendingPlaceholderMockValueController.dispose();
    _pendingPlaceholderUnitController.dispose();
    _selectedIconLabelController.dispose();
    _selectedPlaceholderLabelController.dispose();
    _selectedPlaceholderMockValueController.dispose();
    _selectedPlaceholderUnitController.dispose();
    _selectedDemoLabelController.dispose();
    super.dispose();
  }

  /// In preset mode every applied mutation is immediately committed back
  /// into the [BoardPresetCatalog] (N6.2 §12): editing *is* saving, still
  /// entirely in memory. The two catalogs (fixtures vs. presets) never
  /// share state, so this never touches a demo fixture.
  void _onControllerChanged() {
    setState(() {
      // Selecting a new item jumps the side panel to "Seleccionado" so the
      // user never has to manually switch tabs after tapping a card.
      final selectedId = _controller.selectedItemId;
      if (selectedId != null && selectedId != _lastAutoTabSelectedId) {
        _sidePanelTab = _SidePanelTab.selected;
      }
      _lastAutoTabSelectedId = selectedId;
    });
    if (_presetMode && _controller.mode == BoardEditorMode.preset) {
      // N6.5 §25, renamed N6.5.2 §17: only persist a profile choice when it
      // came from the selector itself (never when `widget.metricCatalog`
      // forced an override) — omitting the named argument leaves the
      // preset's stored choice untouched rather than wiping it to null.
      if (widget.metricCatalog == null) {
        widget.presetCatalog!.updateContent(
          widget.presetId!,
          layout: _controller.template,
          items: _controller.items,
          showTitle: _controller.showTitle,
          titleOverride: _controller.titleOverride,
          clearTitleOverride: _controller.titleOverride == null,
          capabilityProfileId: _controller.presetProfileId,
        );
      } else {
        widget.presetCatalog!.updateContent(
          widget.presetId!,
          layout: _controller.template,
          items: _controller.items,
          showTitle: _controller.showTitle,
          titleOverride: _controller.titleOverride,
          clearTitleOverride: _controller.titleOverride == null,
        );
      }
    }
  }

  /// Resets every controller/error/draft to a pristine state for the
  /// currently active fixture/preset (N6.2 §3/R3 — Reset must clear *all*
  /// ephemeral state, not just the currently-selected item's fields).
  void _resetEphemeralState() {
    _pendingType = null;
    _pendingMetricKey = null;
    _pendingPresetId = null;
    _pendingIndicatorKeys.clear();
    _pendingFields = _fieldPresets.values.first;
    _pendingColumns = _columnPresets.values.first;
    _pendingFieldError = null;
    _pendingX = 0;
    _pendingY = 0;
    _pendingWidth = 1;
    _pendingHeight = 1;
    _repositionArmed = false;
    _selectedFieldError = null;
    _syncedSelectedId = null;
    _itemDrafts.clear();
    _sourceRefController.text = 'hero';
    _dataSourceController.text = 'device.status';
    _textController.text = 'Nota';
    _titleOverrideController.text = _controller.titleOverride ?? '';
    _pendingBindingMode = BoardBindingMode.unbound;
    _pendingDemoValues = null;
    _pendingDemoRows = null;
    _pendingIconKey = templateIconKeys.first;
    _pendingIconLabelController.clear();
    _pendingPlaceholderLabelController.text = 'Dato pendiente';
    _pendingPlaceholderMockValueController.text = '--';
    _pendingPlaceholderUnitController.clear();
    _pendingPlaceholderIconKey = null;
    _pendingPlaceholderStyle = BoardPlaceholderStyle.neutral;
  }

  void _switchFixture(int index) {
    if (_presetMode) return;
    if (index == _fixtureIndex) return;
    void apply() {
      setState(() {
        _fixtureIndex = index;
        _controller.applyFixture(previewBoardFixtures[index]);
        _resetEphemeralState();
      });
    }

    if (_effectiveDirty) {
      _confirmDiscard(apply);
    } else {
      apply();
    }
  }

  void _confirmDiscard(VoidCallback onConfirm) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Descartar cambios?'),
        content: const Text('Hay cambios sin guardar. ¿Descartar cambios?'),
        actions: [
          TextButton(
            key: const ValueKey('editor-discard-cancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('editor-discard-confirm'),
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
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restaurar configuración inicial'),
        content: const Text('Se perderán los cambios locales de este fixture.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _controller.reset();
                _resetEphemeralState();
              });
            },
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
  }

  void _cancelPending() {
    setState(() {
      _pendingType = null;
      _pendingMetricKey = null;
      _pendingPresetId = null;
      _pendingIndicatorKeys.clear();
      _pendingFields = _fieldPresets.values.first;
      _pendingColumns = _columnPresets.values.first;
      _pendingFieldError = null;
      _pendingX = 0;
      _pendingY = 0;
      _pendingWidth = 1;
      _pendingHeight = 1;
      _repositionArmed = false;
    });
  }

  void _startAdding(BoardContentType type) {
    setState(() {
      _pendingType = type;
      _pendingX = 0;
      _pendingY = 0;
      _pendingWidth = 1;
      _pendingHeight = 1;
      _pendingIndicatorKeys.clear();
      _pendingFieldError = null;
      _pendingFields = _fieldPresets.values.first;
      _pendingColumns = _columnPresets.values.first;
      // Fresh defaults per type (N6.2 §3/R3): these controllers are shared
      // across pending types, so a value typed for a discarded add of a
      // different type must never reappear as if it belonged to this one.
      _sourceRefController.text = 'hero';
      _dataSourceController.text = 'device.status';
      _textController.text = 'Nota';
      _pendingBindingMode = BoardBindingMode.unbound;
      _pendingDemoValues = null;
      _pendingDemoRows = null;
      _pendingIconKey = templateIconKeys.first;
      _pendingIconLabelController.clear();
      _pendingIconSizeRole = CellSizeRole.lg;
      _pendingIconHAlign = CellHorizontalAlignment.center;
      _pendingIconVAlign = CellVerticalAlignment.center;
      _pendingPlaceholderLabelController.text = 'Dato pendiente';
      _pendingPlaceholderMockValueController.text = '--';
      _pendingPlaceholderUnitController.clear();
      _pendingPlaceholderIconKey = null;
      _pendingPlaceholderStyle = BoardPlaceholderStyle.neutral;
      _pendingTextAlignment = CellHorizontalAlignment.start;
      _pendingTextSizeRole = CellSizeRole.md;
      _pendingTextWeight = CellFontWeight.normal;
      _pendingTextMaxLines = 3;
      if (type == BoardContentType.metric) {
        final metrics = _controller.catalog.metrics;
        _pendingMetricKey = metrics.isEmpty ? null : metrics.first.key;
        // N6.5.2 §8 — the profile's suggested indicators for this metric
        // are only a prefill: already selected here, but every indicator in
        // `_controller.catalog.availableIndicators[key]` (the *entire*
        // profile list, §7/§9) stays freely toggleable below.
        _pendingIndicatorKeys
          ..clear()
          ..addAll(_suggestedIndicatorsFor(_pendingMetricKey));
      }
      // Span-driven presets are only ever chosen explicitly by the user
      // from here on (N6.1 §10) — no auto-reassignment on resize.
      _pendingPresetId = null;
      _repositionArmed = false;
    });
  }

  void _onCellTap(int x, int y) {
    if (!_controller.editMode) return;
    if (_pendingType != null) {
      setState(() {
        _pendingX = x;
        _pendingY = y;
      });
      return;
    }
    if (_controller.selectedItemId != null && _repositionArmed) {
      _controller.moveSelectedTo(x, y);
    }
  }

  BoardContentConfig _buildPendingContentOrThrow() {
    switch (_pendingType!) {
      case BoardContentType.metric:
        // N6.5.1: re-validated against the *current* catalog, not just
        // non-null — switching to a different (or empty) catalog while a
        // metric add is pending never leaves a stale key from the old
        // catalog silently confirmable.
        final key = _pendingMetricKey;
        if (key == null || _controller.catalog.metricByKey(key) == null) {
          throw ArgumentError('Elegí una métrica');
        }
        return MetricBoardContent(
          metricKey: key,
          cellLayoutPresetId: _pendingPresetId,
          indicatorKeys: _pendingIndicatorKeys.toList(),
        );
      case BoardContentType.image:
        return ImageBoardContent(
          sourceType: _pendingImageSource,
          sourceRef: _sourceRefController.text,
          fit: _pendingImageFit,
        );
      case BoardContentType.status:
        return StatusBoardContent(
          dataSourceId: _pendingBindingMode == BoardBindingMode.bound
              ? _dataSourceController.text
              : null,
          demoLabel: _pendingBindingMode == BoardBindingMode.demo
              ? (_pendingDemoValues?['status'] ?? 'Operativo')
              : null,
        );
      case BoardContentType.latestEvent:
        return LatestEventBoardContent(
          eventSourceId: _pendingBindingMode == BoardBindingMode.bound
              ? _dataSourceController.text
              : null,
          fields: _pendingFields,
          demoValues: _pendingBindingMode == BoardBindingMode.demo
              ? (_pendingDemoValues ?? _demoValuesFor(_pendingFields))
              : null,
        );
      case BoardContentType.dataTable:
        return DataTableBoardContent(
          dataSourceId: _pendingBindingMode == BoardBindingMode.bound
              ? _dataSourceController.text
              : null,
          columns: _pendingColumns,
          demoRows: _pendingBindingMode == BoardBindingMode.demo
              ? (_pendingDemoRows ?? _demoRowsFor(_pendingColumns))
              : null,
        );
      case BoardContentType.text:
        return TextBoardContent(
          text: _textController.text,
          horizontalAlignment: _pendingTextAlignment,
          sizeRole: _pendingTextSizeRole,
          fontWeight: _pendingTextWeight,
          maxLines: _pendingTextMaxLines,
        );
      case BoardContentType.chart:
        return ChartBoardContent(
          dataSourceId: _dataSourceController.text,
          chartType: _pendingChartType,
          series: [BoardChartSeries(key: 'serie1', label: 'Serie 1')],
        );
      case BoardContentType.icon:
        return IconBoardContent(
          iconKey: _pendingIconKey,
          label: _pendingIconLabelController.text.trim().isEmpty
              ? null
              : _pendingIconLabelController.text.trim(),
          sizeRole: _pendingIconSizeRole,
          horizontalAlignment: _pendingIconHAlign,
          verticalAlignment: _pendingIconVAlign,
        );
      case BoardContentType.placeholder:
        return PlaceholderBoardContent(
          label: _pendingPlaceholderLabelController.text,
          mockValue: _pendingPlaceholderMockValueController.text.trim().isEmpty
              ? null
              : _pendingPlaceholderMockValueController.text.trim(),
          unit: _pendingPlaceholderUnitController.text.trim().isEmpty
              ? null
              : _pendingPlaceholderUnitController.text.trim(),
          iconKey: _pendingPlaceholderIconKey,
          style: _pendingPlaceholderStyle,
        );
    }
  }

  /// N6.4 §11: one representative demo value per configured field/column —
  /// generated the moment "Demo" is chosen so the design is immediately
  /// previewable, never a fabricated *real* source.
  Map<String, String> _demoValuesFor(List<BoardDataField> fields) => {
    for (final f in fields) f.key: 'Demo ${f.label}',
  };
  List<Map<String, String>> _demoRowsFor(List<BoardTableColumn> columns) => [
    {for (final c in columns) c.field.key: 'Demo ${c.field.label}'},
  ];

  /// Safe construction (N6.1 §5/A3): never lets a constructor's
  /// [ArgumentError]/[LayoutValidationException] escape into the widget
  /// tree. Returns the content on success or records a visible field error.
  BoardContentConfig? _tryBuildPending() {
    if (_pendingType == null) return null;
    try {
      final content = _buildPendingContentOrThrow();
      _pendingFieldError = null;
      return content;
    } catch (e) {
      _pendingFieldError = _errorFrom(e);
      return null;
    }
  }

  CellLayoutPreset? get _pendingResolvedPreset {
    if (_pendingType != BoardContentType.metric) return null;
    return _pendingPresetId == null
        ? _presets.defaultForSpan(_pendingWidth, _pendingHeight)
        : _presets.byId(_pendingPresetId!);
  }

  int? get _pendingIndicatorOverflow {
    final preset = _pendingResolvedPreset;
    if (preset == null) return null;
    final overflow = _pendingIndicatorKeys.length - preset.indicatorSlotCount;
    return overflow > 0 ? overflow : null;
  }

  void _confirmAdd() {
    final content = _tryBuildPending();
    if (content == null || _pendingIndicatorOverflow != null) {
      setState(() {});
      return;
    }
    _controller.addItem(
      content: content,
      x: _pendingX,
      y: _pendingY,
      widthCells: _pendingWidth,
      heightCells: _pendingHeight,
    );
    _cancelPending();
  }

  void _confirmDelete() {
    final selected = _controller.selectedItem;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar elemento'),
        content: Text('¿Eliminar "${_controller.selectedItemId}" del board?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('editor-delete-confirm'),
            onPressed: () {
              Navigator.of(context).pop();
              final requiredWarning = _requiredMetricWarningFor(selected);
              setState(() {
                _itemDrafts.remove(_controller.selectedItemId);
                _controller.removeSelected();
                _selectedFieldError = null;
                _syncedSelectedId = null;
              });
              if (requiredWarning != null) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(requiredWarning)));
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  /// N6.3.1 §11: deleting a board item never touches
  /// `requiredMetricKeys`/`optionalMetricKeys` (visual structure stays
  /// decoupled from the capability contract — the delete button is never
  /// gated by this) — it only surfaces a warning, after the fact, when the
  /// removed metric was declared required by the current [BoardPreset], so
  /// the user isn't left guessing why a "required" metric no longer shows
  /// on the board.
  String? _requiredMetricWarningFor(BoardContentItem? item) {
    if (!_presetMode || item == null) return null;
    final content = item.content;
    if (content is! MetricBoardContent) return null;
    final preset = widget.presetCatalog!.byId(widget.presetId!);
    if (preset == null ||
        !preset.requiredMetricKeys.contains(content.metricKey)) {
      return null;
    }
    return 'Esta métrica sigue declarada como requerida por el preset.';
  }

  /// True if some *other* item — anywhere, including a sibling in this same
  /// [BoardPreset] — already references [cellLayoutPresetId]; used to
  /// decide whether editing a "Diseño de celda" should go straight to a
  /// local copy instead of the shared original (N6.3 §3).
  ///
  /// N6.4 §18 fix: only the item currently being edited is excluded — never
  /// the whole current [BoardPreset]. The previous version excluded every
  /// item in `widget.presetId` to stop a preset from flagging itself as
  /// "shared" merely because the item being edited references the design
  /// (a real self-triggering bug fixed in N6.3.1) — but that also silently
  /// stopped protecting *sibling* items in the same board that happen to
  /// share the same local design: editing one directly used to warn (for
  /// the wrong reason), then N6.3.1's fix made it stop warning at all. This
  /// restores the warning for the right reason — a genuine second reference
  /// — while still not self-triggering on the item actually being edited.
  bool _isCellLayoutPresetReferenced(
    String cellLayoutPresetId, {
    String? excludingItemId,
  }) {
    for (final preset
        in (widget.presetCatalog ?? sharedBoardPresetCatalog).presets) {
      for (final item in preset.items) {
        if (preset.id == widget.presetId && item.id == excludingItemId) {
          continue;
        }
        final content = item.content;
        if (content is MetricBoardContent &&
            content.cellLayoutPresetId == cellLayoutPresetId) {
          return true;
        }
      }
    }
    return false;
  }

  /// N6.3 §5: "Diseño de celda → Editar diseño". Pushes the visual cell
  /// layout editor for [presetId] and, on return, applies whichever preset
  /// id ended up being edited (the original if editing was direct, or a
  /// fresh local copy if the editor duplicated it first) back onto the
  /// item that opened it.
  Future<void> _openCellLayoutEditor(
    String? presetId, {
    required void Function(String presetId) onApplied,
  }) async {
    if (presetId == null) return;
    final resultId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CellLayoutEditorPage(
          isOwner: widget.isOwner,
          presetId: presetId,
          catalog: sharedCellLayoutPresetCatalog,
          isReferenced: (id) => _isCellLayoutPresetReferenced(
            id,
            excludingItemId: _controller.selectedItemId,
          ),
          renderConfig: widget.renderConfig,
        ),
      ),
    );
    // N6.3.1: always re-apply a non-null result, even if it equals the id
    // passed in — a freshly-created "desde default" preset is applied to
    // the item for the first time right here (it was never assigned before
    // opening the editor), so `resultId == presetId` is the common case for
    // that flow, not a no-op to skip.
    if (!mounted) return;
    if (resultId != null) {
      onApplied(resultId);
    }
    setState(() {});
  }

  /// N6.3.1 §5: materializes the ephemeral "(default por span)" resolution
  /// into a real, catalog-backed, editable [CellLayoutPreset] — never a
  /// no-op, unlike the old pencil-icon behavior when no seeded default
  /// existed for the span. The new preset is unreferenced by anything until
  /// the user actually leaves the editor via "Volver al Board" (handled by
  /// [_openCellLayoutEditor]'s `onApplied`), so it never appears "shared"
  /// and is always editable directly — no spurious duplicate-first gate.
  void _createDesignFromDefault(dynamic item, MetricBoardContent content) {
    final width = item.placement.widthCells as int;
    final height = item.placement.heightCells as int;
    final created = sharedCellLayoutPresetCatalog.create(
      name: 'Diseño $width × $height (desde default)',
      width: width,
      height: height,
    );
    _openCellLayoutEditor(
      created.id,
      onApplied: (id) => _safeUpdateSelected(
        () => MetricBoardContent(
          metricKey: content.metricKey,
          labelOverride: content.labelOverride,
          unitOverride: content.unitOverride,
          cellLayoutPresetId: id,
          indicatorKeys: content.indicatorKeys,
        ),
      ),
    );
  }

  /// Applies [build] to the selected item, catching construction errors
  /// instead of letting them reach the widget tree (A3). The invalid text
  /// stays visible in the (persistent) controller either way. On success the
  /// item is valid again, so any parked draft for it is dropped (N6.2 §1).
  void _safeUpdateSelected(BoardContentConfig Function() build) {
    setState(() {
      try {
        _controller.updateSelectedContent(build());
        _selectedFieldError = null;
        _itemDrafts.remove(_controller.selectedItemId);
      } catch (e) {
        _selectedFieldError = _errorFrom(e);
      }
    });
  }

  /// Keeps the selected-item text controllers in sync with the current
  /// selection without recreating them on every build (A2): only resets
  /// their text when the selected item id actually changes. N6.2 §1/R1: an
  /// item being navigated away from while its text still shows an error is
  /// parked in [_itemDrafts] instead of being silently discarded, and
  /// restored verbatim (text + error) if the user selects it again —
  /// independent of whichever item happens to be selected in between.
  void _syncSelectedControllers() {
    final id = _controller.selectedItemId;
    if (id == _syncedSelectedId) return;
    final previousId = _syncedSelectedId;
    if (previousId != null) {
      if (_selectedFieldError != null) {
        _itemDrafts[previousId] = _ItemDraft(
          sourceRef: _selectedSourceRefController.text,
          dataSource: _selectedDataSourceController.text,
          text: _selectedTextController.text,
          error: _selectedFieldError,
        );
      } else {
        _itemDrafts.remove(previousId);
      }
    }
    _syncedSelectedId = id;
    final draft = id == null ? null : _itemDrafts[id];
    if (draft != null) {
      _selectedFieldError = draft.error;
      _selectedSourceRefController.text = draft.sourceRef ?? '';
      _selectedDataSourceController.text = draft.dataSource ?? '';
      _selectedTextController.text = draft.text ?? '';
      return;
    }
    _selectedFieldError = null;
    final content = _controller.selectedItem?.content;
    _selectedMetricLabelController.text = content is MetricBoardContent
        ? content.labelOverride ?? ''
        : '';
    _selectedMetricUnitController.text = content is MetricBoardContent
        ? content.unitOverride ?? ''
        : '';
    _selectedSourceRefController.text = content is ImageBoardContent
        ? content.sourceRef
        : '';
    _selectedDataSourceController.text = switch (content) {
      StatusBoardContent c => c.dataSourceId ?? '',
      LatestEventBoardContent c => c.eventSourceId ?? '',
      DataTableBoardContent c => c.dataSourceId ?? '',
      ChartBoardContent c => c.dataSourceId,
      _ => '',
    };
    _selectedTextController.text = content is TextBoardContent
        ? content.text
        : '';
    _selectedIconLabelController.text = content is IconBoardContent
        ? (content.label ?? '')
        : '';
    _selectedPlaceholderLabelController.text =
        content is PlaceholderBoardContent ? content.label : '';
    _selectedPlaceholderMockValueController.text =
        content is PlaceholderBoardContent ? (content.mockValue ?? '') : '';
    _selectedPlaceholderUnitController.text = content is PlaceholderBoardContent
        ? (content.unit ?? '')
        : '';
    _selectedDemoLabelController.text = content is StatusBoardContent
        ? (content.demoLabel ?? '')
        : '';
  }

  List<DropdownMenuItem<String?>> _presetDropdownItems({
    required int width,
    required int height,
    required String? currentPresetId,
  }) {
    final compatible = _presets.presets
        .where(
          (p) => p.enabled && p.widthCells == width && p.heightCells == height,
        )
        .toList();
    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('(default por span)', overflow: TextOverflow.ellipsis),
      ),
      for (final preset in compatible)
        DropdownMenuItem<String?>(
          value: preset.id,
          child: Text(preset.name, overflow: TextOverflow.ellipsis),
        ),
    ];
    if (currentPresetId != null &&
        !compatible.any((p) => p.id == currentPresetId)) {
      final current = _presets.byId(currentPresetId);
      items.add(
        DropdownMenuItem<String?>(
          value: currentPresetId,
          child: Text(
            '${current?.name ?? currentPresetId} — actual, span incompatible',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOwner) {
      return const Scaffold(
        body: Center(child: Text('Board Editor disponible solo para owner')),
      );
    }
    _syncSelectedControllers();
    final catalog = _controller.catalog;
    final issues = _controller.issues(_presets);
    // Preset/device mode have no demo fixture: no device name to append
    // "· demo" to, no sample sensor values — an explicitly empty data
    // provider (renders the same "Sin datos" placeholders the resolver
    // already uses for any missing source, never a fabricated value)
    // (N6.2 §14). Device mode shows the real `deviceId` instead (N7.1 §13).
    final fixture = (_presetMode || _deviceMode)
        ? null
        : previewBoardFixtures[_fixtureIndex];
    final data = fixture?.data ?? const PreviewBoardDataProvider();
    final deviceName = _deviceMode
        ? widget.deviceContext!.deviceId
        : fixture == null
        ? 'Nombre del Device (al aplicar)'
        : '${fixture.name} · demo';
    final showIssuesPanel = _controller.editMode || _debugVisible;
    return PopScope(
      canPop: !_effectiveDirty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmDiscard(() => Navigator.of(context).pop());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _presetMode
                ? 'Board Preset Editor'
                : _deviceMode
                ? 'Board del Device'
                : 'Board Editor',
          ),
          actions: [
            IconButton(
              key: const ValueKey('editor-debug-toggle'),
              tooltip: _debugVisible
                  ? 'Ocultar diagnóstico'
                  : 'Mostrar diagnóstico',
              icon: Icon(
                _debugVisible ? Icons.bug_report : Icons.bug_report_outlined,
              ),
              onPressed: () => setState(() => _debugVisible = !_debugVisible),
            ),
            IconButton(
              key: const ValueKey('editor-toggle-mode'),
              tooltip: _controller.editMode ? 'Ver preview' : 'Editar',
              icon: Icon(_controller.editMode ? Icons.visibility : Icons.edit),
              onPressed: () => _controller.toggleEditMode(),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _headerPanel(),
                const SizedBox(height: 12),
                if (!_presetMode && !_deviceMode) ...[
                  const Text(
                    'CASOS DEMO',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < previewBoardFixtures.length; i++)
                        ChoiceChip(
                          label: Text('${previewBoardFixtures[i].name} demo'),
                          selected: _fixtureIndex == i,
                          onSelected: (_) => _switchFixture(i),
                        ),
                      if (_controller.editMode)
                        ActionChip(
                          key: const ValueKey('editor-reset'),
                          label: const Text('Reset'),
                          onPressed: _effectiveDirty ? _reset : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ] else if (_controller.editMode) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ActionChip(
                      key: const ValueKey('editor-reset'),
                      label: const Text('Reset'),
                      onPressed: _effectiveDirty ? _reset : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_controller.editMode) ...[
                  _layoutTemplateSelector(),
                  const SizedBox(height: 16),
                ],
                if (_controller.editMode &&
                    _presetMode &&
                    widget.metricCatalog == null) ...[
                  _capabilityProfileSelector(),
                  const SizedBox(height: 16),
                ],
                if (_controller.editMode) ...[
                  _titleSection(),
                  const SizedBox(height: 16),
                ],
                _boardAndSidePanel(
                  catalog,
                  data,
                  deviceName,
                  issues,
                  showIssuesPanel,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const double _sidePanelBreakpoint = 900;
  static const double _sidePanelWidth = 380;

  /// N6.3 §16/§17: board on the left + a side panel on the right in
  /// desktop widths; stacked (board above, panel below) under the
  /// breakpoint. Never changes `BoardEditorCanvas`/`BoardContentRenderer`
  /// themselves — purely an outer layout decision (§17: "no alterar
  /// renderer final del Board").
  Widget _boardAndSidePanel(
    DeviceMetricCatalog catalog,
    PreviewBoardDataProvider data,
    String deviceName,
    List<LayoutValidationIssue> issues,
    bool showIssuesPanel,
  ) {
    final board = Column(
      key: const ValueKey('editor-board-column'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF0B1120),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1F2A3C)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _controller.editMode
                ? BoardEditorCanvas(
                    controller: _controller,
                    renderConfig: widget.renderConfig,
                    presets: _presets,
                    data: data,
                    deviceName: deviceName,
                    issues: issues,
                    pending: _pendingType == null
                        ? null
                        : PendingPlacement(
                            x: _pendingX,
                            y: _pendingY,
                            widthCells: _pendingWidth,
                            heightCells: _pendingHeight,
                          ),
                    onCellTap: _onCellTap,
                  )
                : BoardContentRenderer(
                    key: const ValueKey('editor-preview-renderer'),
                    board: _controller.board,
                    template: _controller.template,
                    catalog: catalog,
                    data: data,
                    deviceName: deviceName,
                    presets: _presets,
                    renderConfig: widget.renderConfig,
                  ),
          ),
        ),
        if (showIssuesPanel) ...[
          const SizedBox(height: 16),
          _issuesPanel(issues),
        ],
      ],
    );
    if (!_controller.editMode) return board;
    final sidePanel = _sidePanel(catalog);
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < _sidePanelBreakpoint;
        if (narrow) {
          return Column(
            key: const ValueKey('editor-layout-narrow'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [board, const SizedBox(height: 16), sidePanel],
          );
        }
        return Row(
          key: const ValueKey('editor-layout-desktop'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: board),
            const SizedBox(width: 16),
            SizedBox(width: _sidePanelWidth, child: sidePanel),
          ],
        );
      },
    );
  }

  Widget _sidePanel(DeviceMetricCatalog catalog) => Container(
    key: const ValueKey('editor-side-panel'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF0B1120),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF1F2A3C)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tab in _SidePanelTab.values)
              ChoiceChip(
                key: ValueKey('editor-side-tab-${tab.name}'),
                label: Text(switch (tab) {
                  _SidePanelTab.board => 'Board',
                  _SidePanelTab.selected => 'Seleccionado',
                  _SidePanelTab.add => 'Agregar',
                }),
                selected: _sidePanelTab == tab,
                onSelected: (_) => setState(() => _sidePanelTab = tab),
              ),
          ],
        ),
        const SizedBox(height: 12),
        switch (_sidePanelTab) {
          _SidePanelTab.board => _itemsPanel(),
          _SidePanelTab.selected =>
            _controller.selectedItem == null
                ? const Text(
                    'Ningún item seleccionado. Tocá un elemento del board o de '
                    'la pestaña Board.',
                    style: _fieldLabelStyle,
                  )
                : _selectedItemPanel(catalog),
          _SidePanelTab.add => _addContentPanel(catalog),
        },
      ],
    ),
  );

  /// N6.2 §13: preset mode identifies itself unambiguously ("BOARD PRESET
  /// EDITOR", the preset's own name, its layout) instead of reusing the
  /// fixture-demo "Sala · demo" framing — never presented as if it were a
  /// real Device.
  /// N7.1 §14 — "Cambios sin guardar" / [Guardar]: the human-readable
  /// summary of [BoardEditorController.saveStatus]/[dirty]. `saveError` is
  /// shown verbatim (it already carries `FirestoreVersionConflict`'s
  /// `configuration_conflict` message when relevant — §15).
  String _deviceSaveStatusText() {
    switch (_controller.saveStatus) {
      case BoardSaveStatus.saving:
        return 'Guardando…';
      case BoardSaveStatus.error:
        return 'Error al guardar: ${_controller.saveError}';
      case BoardSaveStatus.saved:
        return 'Guardado · v${_controller.loadedLayoutVersion}';
      case BoardSaveStatus.idle:
        return _controller.dirty
            ? 'Cambios sin guardar'
            : 'Sin cambios · v${_controller.loadedLayoutVersion}';
    }
  }

  Future<void> _saveDeviceBoard() async {
    final ctx = widget.deviceContext;
    if (ctx == null) return;
    final layout = _controller.board;
    final expectedVersion = _controller.loadedLayoutVersion;
    _controller.markSaving();
    try {
      final int newVersion = await ctx.onSave(layout, expectedVersion);
      if (!mounted) return;
      _controller.markSaved(newVersion);
    } catch (error) {
      if (!mounted) return;
      _controller.markSaveError(error.toString());
    }
  }

  Widget _deviceSaveBar() {
    final saving = _controller.saveStatus == BoardSaveStatus.saving;
    final canSave = _controller.dirty && !saving;
    return Row(
      children: [
        Expanded(
          child: Text(
            _deviceSaveStatusText(),
            key: const ValueKey('editor-dirty-state'),
            style: _controller.saveStatus == BoardSaveStatus.error
                ? const TextStyle(color: Color(0xFFF87171), fontSize: 12)
                : _fieldLabelStyle,
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          key: const ValueKey('editor-device-save'),
          onPressed: canSave ? _saveDeviceBoard : null,
          child: Text(saving ? 'Guardando…' : 'Guardar'),
        ),
      ],
    );
  }

  Widget _headerPanel() {
    if (_deviceMode) {
      final ctx = widget.deviceContext!;
      final template = _controller.template;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CONFIGURACIÓN DE BOARD — DEVICE REAL',
            style: TextStyle(
              color: Color(0xFF38BDF8),
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Device: ${ctx.deviceId} · Perfil: '
            '${ctx.profile?.name ?? 'Sin perfil'}',
            key: const ValueKey('editor-device-name'),
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          Text(
            'Layout: ${template.columns}x${template.rows}',
            key: const ValueKey('editor-device-layout'),
            style: _fieldLabelStyle,
          ),
          const SizedBox(height: 8),
          if (_controller.editMode) _deviceSaveBar(),
        ],
      );
    }
    if (_presetMode) {
      final preset = _controller.activePreset!;
      final template = _controller.template;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'BOARD PRESET EDITOR',
            style: TextStyle(
              color: Color(0xFF38BDF8),
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Preset de tablero: ${preset.name}',
            key: const ValueKey('editor-preset-name'),
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          Text(
            'Layout: ${template.columns}x${template.rows}',
            key: const ValueKey('editor-preset-layout'),
            style: _fieldLabelStyle,
          ),
          const SizedBox(height: 4),
          Text(
            _controller.editMode
                ? 'Editando preset · borrador local en memoria'
                : 'Modo preview · solo lectura',
            key: const ValueKey('editor-dirty-state'),
            style: _fieldLabelStyle,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'BOARD EDITOR — OWNER ONLY',
          style: TextStyle(
            color: Color(0xFF38BDF8),
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _controller.editMode
              ? (_effectiveDirty
                    ? 'Cambios sin guardar · borrador local en memoria'
                    : 'Sin cambios · borrador local en memoria')
              : 'Modo preview · solo lectura',
          key: const ValueKey('editor-dirty-state'),
          style: _fieldLabelStyle,
        ),
      ],
    );
  }

  /// N6.2 §2/R2: dropdown items and the onChanged callback both resolve
  /// from the exact same [effectiveLayoutTemplates] call — a fixture's
  /// template outside the 4-entry generic catalog (Arco's `grid_6x7`) or a
  /// preset's dynamic geometry (`grid_8x4`) can never be an orphaned
  /// `DropdownButton` value, and re-selecting it is a valid no-op (handled
  /// by [BoardEditorController.setLayoutTemplate]) rather than a crash or a
  /// spurious dirty flag.
  Widget _layoutTemplateSelector() {
    final current = _controller.template;
    final catalog = effectiveLayoutTemplates(current);
    final isKnown = availableLayoutTemplates().any((t) => t.id == current.id);
    return Row(
      children: [
        const Text('LayoutTemplate:', style: _fieldLabelStyle),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<String>(
            key: const ValueKey('editor-layout-template'),
            isExpanded: true,
            value: current.id,
            items: [
              for (final template in catalog)
                DropdownMenuItem(
                  value: template.id,
                  child: Text(
                    isKnown || template.id != current.id
                        ? '${template.name} (${template.id})'
                        : '${template.name} (${template.id}) — del fixture',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (id) {
              final next = effectiveLayoutTemplates(
                current,
              ).firstWhere((t) => t.id == id);
              _controller.setLayoutTemplate(next);
            },
          ),
        ),
      ],
    );
  }

  /// N6.5 §25/§26/§27, N6.5.2 §17/§18/§19 — lets the preset pick which
  /// [DeviceCapabilityProfile] to design against, including the explicit
  /// "Sin perfil" option (`null`), without requiring one to keep using
  /// text/icon/image/placeholder/unbound content (N6.4 stays intact).
  /// Switching never touches existing items — a metricKey missing from the
  /// new profile's resolved catalog surfaces as the existing
  /// `metric_not_found` issue on the very next validation pass, never a
  /// silent drop (N6.5 §27/§41, N6.5.2 §19).
  Widget _capabilityProfileSelector() {
    final currentId = _controller.presetProfileId;
    final profiles = _capabilityProfileStore.profiles;
    final isKnown = currentId == null || profiles.any((p) => p.id == currentId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Perfil de capacidades de referencia:',
              style: _fieldLabelStyle,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButton<String?>(
                key: const ValueKey('editor-capability-profile'),
                isExpanded: true,
                value: currentId,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Sin perfil', overflow: TextOverflow.ellipsis),
                  ),
                  for (final entry in profiles)
                    DropdownMenuItem<String?>(
                      value: entry.id,
                      child: Text(
                        '${entry.name} (${entry.id})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (!isKnown)
                    DropdownMenuItem<String?>(
                      value: currentId,
                      child: Text(
                        '$currentId — no encontrado en el registro de perfiles',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) {
                  final resolved = _resolveProfile(id);
                  // N6.5.1: a pending "Agregar métrica" form left open while
                  // switching profiles must never keep pointing at a key the
                  // new profile doesn't have — that `DropdownMenuItem` would
                  // no longer exist, crashing the dropdown on rebuild.
                  if (_pendingMetricKey != null &&
                      resolved.catalog.metricByKey(_pendingMetricKey!) ==
                          null) {
                    setState(() {
                      _pendingMetricKey = null;
                      _pendingIndicatorKeys.clear();
                    });
                  }
                  _controller.setProfile(
                    resolved.profile,
                    resolved.catalog,
                    id: id,
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // N6.5.1 §9 — always visible, independent of the current selection,
        // so it reads as an explanation of the field, not a validation error.
        const Text(
          'Las métricas e indicators disponibles en este Board provienen de '
          'este perfil.',
          style: _fieldLabelStyle,
        ),
      ],
    );
  }

  Widget _titleSection() => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 12,
    runSpacing: 8,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Mostrar título', style: _fieldLabelStyle),
          Switch(
            key: const ValueKey('editor-show-title'),
            value: _controller.showTitle,
            onChanged: _controller.editMode ? _controller.setShowTitle : null,
          ),
        ],
      ),
      if (_controller.editMode)
        SizedBox(
          width: 220,
          child: TextField(
            key: const ValueKey('editor-title-override'),
            decoration: InputDecoration(
              labelText: _presetMode
                  ? 'Título por defecto del Board'
                  : 'Título del Board',
              helperText: _presetMode
                  ? 'Opcional. Si queda vacío, al aplicar el preset a un Device se usará el nombre del Device.'
                  : null,
              helperMaxLines: 5,
            ),
            controller: _titleOverrideController,
            onChanged: _controller.setTitleOverride,
          ),
        ),
      Text(
        'Resuelve a: "${_controller.board.resolveTitle(_fallbackTitle) ?? '(sin título)'}"',
        key: const ValueKey('editor-title-preview'),
        style: _fieldLabelStyle,
      ),
    ],
  );

  String get _fallbackTitle => _deviceMode
      ? widget.deviceContext!.deviceId
      : _presetMode
      ? 'Nombre del Device (al aplicar)'
      : '${previewBoardFixtures[_fixtureIndex].name} · demo';

  Widget _issuesPanel(List<LayoutValidationIssue> issues) => Container(
    key: const ValueKey('editor-issues-panel'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: issues.isEmpty ? const Color(0xFF0F2A1D) : const Color(0xFF351F28),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: issues.isEmpty ? const Color(0xFF34D399) : Colors.orange,
      ),
    ),
    child: issues.isEmpty
        ? const Text(
            'Sin issues de validación',
            style: TextStyle(color: Color(0xFF74E2AC)),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, issue) in issues.indexed)
                InkWell(
                  // N6.2 R5 + N6.3: two collision issues sharing the same
                  // itemId (a big item overlapping two others at once) used
                  // to collide on this key. relatedItemId alone still isn't
                  // enough: N4's `internal_collision` issues (a broken cell
                  // layout design applied to more than one board item) use
                  // the *cell element's* id as itemId/relatedItemId — the
                  // same pair ('value'/'unit', say) can legitimately repeat
                  // across different board items, which carry no other
                  // distinguishing field on this issue shape. The list index
                  // guarantees uniqueness unconditionally, regardless of
                  // what the underlying issue objects happen to share.
                  key: issue.itemId == null
                      ? null
                      : ValueKey(
                          'editor-issue-$i-${issue.code}-${issue.itemId}-'
                          '${issue.relatedItemId ?? "_"}',
                        ),
                  onTap: issue.itemId == null || !_controller.editMode
                      ? null
                      : () => _controller.selectItem(issue.itemId),
                  child: Text(
                    '${issue.code}${issue.itemId == null ? '' : ' · ${issue.itemId}'}: ${issue.message}',
                    style: TextStyle(
                      color: issue.itemId == null
                          ? Colors.white
                          : const Color(0xFF9BE1FF),
                      fontSize: 12,
                      decoration: issue.itemId == null
                          ? TextDecoration.none
                          : TextDecoration.underline,
                    ),
                  ),
                ),
            ],
          ),
  );

  /// A5 — every item is always reachable here regardless of canvas
  /// hit-testing (out of bounds, overlapping, or otherwise invalid). N6.2
  /// §1/R1: an item with a parked invalid draft is flagged the same way, so
  /// an unresolved error on an item you've navigated away from stays
  /// visible, not just the currently-selected one.
  Widget _itemsPanel() {
    final issueItemIds = {
      for (final issue in _controller.issues(_presets))
        if (issue.itemId != null) issue.itemId!,
      ..._itemDrafts.keys,
      if (_selectedFieldError != null && _controller.selectedItemId != null)
        _controller.selectedItemId!,
    };
    return Container(
      key: const ValueKey('editor-items-panel'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1120),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2A3C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Items del Board',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final item in _controller.items)
            InkWell(
              key: ValueKey('editor-item-row-${item.id}'),
              onTap: () => _controller.selectItem(item.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    if (issueItemIds.contains(item.id))
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(
                          Icons.error_outline,
                          size: 14,
                          color: Color(0xFFF87171),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        '${item.id} · ${item.type.name} · '
                        '(${item.placement.x},${item.placement.y}) '
                        '${item.placement.widthCells}×${item.placement.heightCells}',
                        style: TextStyle(
                          color: item.id == _controller.selectedItemId
                              ? const Color(0xFF63D3FA)
                              : const Color(0xFF94A3B8),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _selectedItemPanel(DeviceMetricCatalog catalog) {
    final item = _controller.selectedItem!;
    final content = item.content;
    return Container(
      key: const ValueKey('editor-selected-panel'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1120),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF63D3FA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Seleccionado: ${item.id} (${item.type.name})',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              IconButton(
                key: const ValueKey('editor-move-up'),
                icon: const Icon(Icons.arrow_upward),
                onPressed: () => _controller.moveSelectedBy(0, -1),
              ),
              IconButton(
                key: const ValueKey('editor-move-down'),
                icon: const Icon(Icons.arrow_downward),
                onPressed: () => _controller.moveSelectedBy(0, 1),
              ),
              IconButton(
                key: const ValueKey('editor-move-left'),
                icon: const Icon(Icons.arrow_back),
                onPressed: () => _controller.moveSelectedBy(-1, 0),
              ),
              IconButton(
                key: const ValueKey('editor-move-right'),
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => _controller.moveSelectedBy(1, 0),
              ),
              FilterChip(
                key: const ValueKey('editor-reposition-toggle'),
                label: const Text('Mover con clic'),
                selected: _repositionArmed,
                onSelected: (v) => setState(() => _repositionArmed = v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Ancho:', style: _fieldLabelStyle),
                  _spanStepper(
                    value: item.placement.widthCells,
                    onChanged: (v) => _controller.resizeSelected(widthCells: v),
                    keyPrefix: 'editor-width',
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Alto:', style: _fieldLabelStyle),
                  _spanStepper(
                    value: item.placement.heightCells,
                    onChanged: (v) =>
                        _controller.resizeSelected(heightCells: v),
                    keyPrefix: 'editor-height',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (content is MetricBoardContent)
            _metricEditor(catalog, item, content)
          else if (content is PlaceholderBoardContent)
            _placeholderEditor(catalog, content)
          else
            _nonMetricEditor(content),
          if (_selectedFieldError != null) ...[
            const SizedBox(height: 4),
            Text(
              _selectedFieldError!,
              key: const ValueKey('editor-selected-error'),
              style: _errorStyle,
            ),
          ],
          const SizedBox(height: 8),
          FilledButton.tonal(
            key: const ValueKey('editor-delete'),
            onPressed: _confirmDelete,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF351F28),
            ),
            child: const Text('Eliminar elemento'),
          ),
        ],
      ),
    );
  }

  Widget _spanStepper({
    required int value,
    required ValueChanged<int> onChanged,
    required String keyPrefix,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        key: ValueKey('$keyPrefix-minus'),
        icon: const Icon(Icons.remove, size: 16),
        onPressed: value > 1 ? () => onChanged(value - 1) : null,
      ),
      Text('$value', style: const TextStyle(color: Colors.white)),
      IconButton(
        key: ValueKey('$keyPrefix-plus'),
        icon: const Icon(Icons.add, size: 16),
        onPressed: () => onChanged(value + 1),
      ),
    ],
  );

  Widget _metricEditor(
    DeviceMetricCatalog catalog,
    dynamic item,
    MetricBoardContent content,
  ) {
    final availableIndicators =
        catalog.availableIndicators[content.metricKey] ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_presetMode) ...[
          const Text(
            'Perfil de capacidades de referencia',
            style: TextStyle(color: Color(0xFF63D3FA), fontSize: 11),
          ),
          const Text(
            'Estas métricas no pertenecen a un cliente real. Se usan para '
            'diseñar el preset.',
            style: _fieldLabelStyle,
          ),
          const SizedBox(height: 4),
        ],
        Row(
          children: [
            const Text('metricKey:', style: _fieldLabelStyle),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButton<String>(
                key: const ValueKey('editor-metric-key'),
                isExpanded: true,
                value: catalog.metricByKey(content.metricKey) == null
                    ? null
                    : content.metricKey,
                hint: const Text('métrica desconocida'),
                items: [
                  for (final metric in catalog.metrics)
                    DropdownMenuItem(
                      value: metric.key,
                      child: Text(
                        metric.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (key) {
                  if (key == null) return;
                  _safeUpdateSelected(
                    () => MetricBoardContent(
                      metricKey: key,
                      labelOverride: content.labelOverride,
                      unitOverride: content.unitOverride,
                      cellLayoutPresetId: content.cellLayoutPresetId,
                      indicatorKeys: const [],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('editor-metric-label-override'),
          controller: _selectedMetricLabelController,
          decoration: const InputDecoration(
            labelText: 'Etiqueta visible',
            helperText: 'Vacío = usar valor definido en la métrica',
            helperMaxLines: 2,
          ),
          onChanged: (value) =>
              _safeUpdateSelected(() => content.copyWith(labelOverride: value)),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('editor-metric-unit-override'),
          controller: _selectedMetricUnitController,
          decoration: const InputDecoration(
            labelText: 'Unidad visible',
            helperText: 'Vacío = usar valor definido en la métrica',
            helperMaxLines: 2,
          ),
          onChanged: (value) =>
              _safeUpdateSelected(() => content.copyWith(unitOverride: value)),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              'Diseño de celda:',
              style: _fieldLabelStyle,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButton<String?>(
                key: const ValueKey('editor-metric-preset'),
                isExpanded: true,
                value: content.cellLayoutPresetId,
                items: _presetDropdownItems(
                  width: item.placement.widthCells,
                  height: item.placement.heightCells,
                  currentPresetId: content.cellLayoutPresetId,
                ),
                onChanged: (id) => _safeUpdateSelected(
                  () => MetricBoardContent(
                    metricKey: content.metricKey,
                    labelOverride: content.labelOverride,
                    unitOverride: content.unitOverride,
                    cellLayoutPresetId: id,
                    indicatorKeys: content.indicatorKeys,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (content.cellLayoutPresetId != null &&
            sharedCellLayoutPresetCatalog.byId(content.cellLayoutPresetId!) !=
                null)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('editor-open-cell-layout-editor'),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Editar diseño'),
                onPressed: () => _openCellLayoutEditor(
                  content.cellLayoutPresetId,
                  onApplied: (id) {
                    if (id == content.cellLayoutPresetId) return;
                    _safeUpdateSelected(
                      () => MetricBoardContent(
                        metricKey: content.metricKey,
                        labelOverride: content.labelOverride,
                        unitOverride: content.unitOverride,
                        cellLayoutPresetId: id,
                        indicatorKeys: content.indicatorKeys,
                      ),
                    );
                  },
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('editor-duplicate-cell-layout'),
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: const Text('Duplicar diseño'),
                onPressed: () {
                  final copy = sharedCellLayoutPresetCatalog.duplicate(
                    content.cellLayoutPresetId!,
                  );
                  _safeUpdateSelected(
                    () => MetricBoardContent(
                      metricKey: content.metricKey,
                      labelOverride: content.labelOverride,
                      unitOverride: content.unitOverride,
                      cellLayoutPresetId: copy.id,
                      indicatorKeys: content.indicatorKeys,
                    ),
                  );
                  _openCellLayoutEditor(
                    copy.id,
                    onApplied: (id) {
                      if (id == copy.id) return;
                      _safeUpdateSelected(
                        () => MetricBoardContent(
                          metricKey: content.metricKey,
                          labelOverride: content.labelOverride,
                          unitOverride: content.unitOverride,
                          cellLayoutPresetId: id,
                          indicatorKeys: content.indicatorKeys,
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        if (content.cellLayoutPresetId == null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('editor-create-design-from-default'),
              onPressed: () => _createDesignFromDefault(item, content),
              icon: const Icon(Icons.auto_awesome_outlined, size: 16),
              label: const Text('Crear diseño desde este default'),
            ),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          _presetMode || _deviceMode
              ? 'Indicators disponibles en el perfil'
              : 'Indicators:',
          style: _fieldLabelStyle,
        ),
        if (_presetMode || _deviceMode)
          const Text(
            'N6.5.2: cualquier indicator del perfil es seleccionable para '
            'esta métrica, no solo los sugeridos. El diseño de celda decide '
            'dónde se muestran.',
            style: _fieldLabelStyle,
          ),
        Wrap(
          spacing: 4,
          children: [
            for (final key in availableIndicators)
              FilterChip(
                key: ValueKey('editor-indicator-$key'),
                label: Text(key),
                selected: content.indicatorKeys.contains(key),
                onSelected: (selected) {
                  final next = [...content.indicatorKeys];
                  if (selected) {
                    next.add(key);
                  } else {
                    next.remove(key);
                  }
                  _safeUpdateSelected(
                    () => MetricBoardContent(
                      metricKey: content.metricKey,
                      labelOverride: content.labelOverride,
                      unitOverride: content.unitOverride,
                      cellLayoutPresetId: content.cellLayoutPresetId,
                      indicatorKeys: next,
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }

  /// N6.4 §5/§6/§7: a placeholder is edited entirely separately from a
  /// metric — its own fields, no `DeviceMetricCatalog` dependency to fill
  /// them in — with one bridge back into the metric world: "Convertir a
  /// métrica" (§7/§16), which preserves placement/span (automatic, since
  /// `updateSelectedContent` only ever replaces `content`) — the resulting
  /// [MetricBoardContent] starts on `(default por span)`, which N6.3.1
  /// already guarantees resolves for any span, so the converted item is
  /// never left without a renderer.
  Widget _placeholderEditor(
    DeviceMetricCatalog catalog,
    PlaceholderBoardContent content,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('editor-edit-placeholder-label'),
          decoration: const InputDecoration(labelText: 'Label'),
          controller: _selectedPlaceholderLabelController,
          onChanged: (value) => _safeUpdateSelected(
            () => PlaceholderBoardContent(
              label: value,
              mockValue: content.mockValue,
              unit: content.unit,
              iconKey: content.iconKey,
              style: content.style,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('editor-edit-placeholder-mock'),
                decoration: const InputDecoration(
                  labelText: 'mockValue (preview, nunca real)',
                ),
                controller: _selectedPlaceholderMockValueController,
                onChanged: (value) => _safeUpdateSelected(
                  () => PlaceholderBoardContent(
                    label: content.label,
                    mockValue: value.trim().isEmpty ? null : value,
                    unit: content.unit,
                    iconKey: content.iconKey,
                    style: content.style,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 90,
              child: TextField(
                key: const ValueKey('editor-edit-placeholder-unit'),
                decoration: const InputDecoration(labelText: 'unit'),
                controller: _selectedPlaceholderUnitController,
                onChanged: (value) => _safeUpdateSelected(
                  () => PlaceholderBoardContent(
                    label: content.label,
                    mockValue: content.mockValue,
                    unit: value.trim().isEmpty ? null : value,
                    iconKey: content.iconKey,
                    style: content.style,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _iconKeyPicker(
          keyName: 'editor-edit-placeholder-icon',
          value: content.iconKey,
          allowNone: true,
          onChanged: (v) => _safeUpdateSelected(
            () => PlaceholderBoardContent(
              label: content.label,
              mockValue: content.mockValue,
              unit: content.unit,
              iconKey: v,
              style: content.style,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Text('Estilo:', style: _fieldLabelStyle),
            const SizedBox(width: 8),
            DropdownButton<BoardPlaceholderStyle>(
              key: const ValueKey('editor-edit-placeholder-style'),
              value: content.style,
              items: [
                for (final s in BoardPlaceholderStyle.values)
                  DropdownMenuItem(value: s, child: Text(s.name)),
              ],
              onChanged: (v) => _safeUpdateSelected(
                () => PlaceholderBoardContent(
                  label: content.label,
                  mockValue: content.mockValue,
                  unit: content.unit,
                  iconKey: content.iconKey,
                  style: v ?? content.style,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('editor-convert-placeholder-to-metric'),
          onPressed: () => _convertPlaceholderToMetric(catalog, content),
          icon: const Icon(Icons.swap_horiz, size: 18),
          label: const Text('Convertir a métrica'),
        ),
      ],
    );
  }

  /// N6.4 §7/§23: shows the picker only while it's open; nothing is applied
  /// until "Confirmar", and an empty catalog just yields an empty (but
  /// still safely dismissible) list — never a crash, never a silent no-op.
  void _convertPlaceholderToMetric(
    DeviceMetricCatalog catalog,
    PlaceholderBoardContent content,
  ) {
    String? chosen = catalog.metrics.isEmpty ? null : catalog.metrics.first.key;
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Convertir a métrica'),
          content: SizedBox(
            width: 320,
            child: catalog.metrics.isEmpty
                ? const Text('No hay métricas disponibles en el perfil actual.')
                : DropdownButton<String>(
                    key: const ValueKey('editor-convert-metric-key'),
                    isExpanded: true,
                    value: chosen,
                    items: [
                      for (final metric in catalog.metrics)
                        DropdownMenuItem(
                          value: metric.key,
                          child: Text(
                            metric.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setDialogState(() => chosen = v),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const ValueKey('editor-convert-confirm'),
              onPressed: chosen == null
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      _safeUpdateSelected(
                        () => MetricBoardContent(metricKey: chosen!),
                      );
                    },
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nonMetricEditor(BoardContentConfig content) {
    if (content is ImageBoardContent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Origen:', style: _fieldLabelStyle),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<BoardImageSourceType>(
                  key: const ValueKey('editor-edit-image-source'),
                  isExpanded: true,
                  value: content.sourceType,
                  items: [
                    for (final type in BoardImageSourceType.values)
                      DropdownMenuItem(
                        value: type,
                        child: Text(imageSourceTypeLabel(type)),
                      ),
                  ],
                  onChanged: (v) => _safeUpdateSelected(
                    () => ImageBoardContent(
                      sourceType: v ?? content.sourceType,
                      sourceRef: content.sourceRef,
                      fit: content.fit,
                      altText: content.altText,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            key: const ValueKey('editor-edit-image-ref'),
            decoration: InputDecoration(
              labelText: imageSourceRefLabel(content.sourceType),
            ),
            controller: _selectedSourceRefController,
            onChanged: (value) => _safeUpdateSelected(
              () => ImageBoardContent(
                sourceType: content.sourceType,
                sourceRef: value,
                fit: content.fit,
                altText: content.altText,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Fit:', style: _fieldLabelStyle),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<BoardImageFit>(
                  key: const ValueKey('editor-edit-image-fit'),
                  isExpanded: true,
                  value: content.fit,
                  items: [
                    for (final fit in BoardImageFit.values)
                      DropdownMenuItem(value: fit, child: Text(fit.name)),
                  ],
                  onChanged: (v) => _safeUpdateSelected(
                    () => ImageBoardContent(
                      sourceType: content.sourceType,
                      sourceRef: content.sourceRef,
                      fit: v ?? content.fit,
                      altText: content.altText,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Text(imageFitHelp(content.fit), style: _fieldLabelStyle),
        ],
      );
    }
    if (content is StatusBoardContent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _selectedBindingModeSelector(
            current: content.bindingMode,
            keyPrefix: 'editor-edit-status-binding',
            onUnbound: () => _safeUpdateSelected(() => StatusBoardContent()),
            onDemo: () => _safeUpdateSelected(
              () => StatusBoardContent(
                demoLabel: content.demoLabel ?? 'Operativo',
              ),
            ),
            onBound: () => _safeUpdateSelected(
              () => StatusBoardContent(
                dataSourceId: content.dataSourceId ?? 'device.status',
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (content.bindingMode == BoardBindingMode.bound)
            TextField(
              key: const ValueKey('editor-edit-status-source'),
              decoration: const InputDecoration(labelText: 'dataSourceId'),
              controller: _selectedDataSourceController,
              onChanged: (value) => _safeUpdateSelected(
                () => StatusBoardContent(dataSourceId: value),
              ),
            )
          else if (content.bindingMode == BoardBindingMode.demo)
            TextField(
              key: const ValueKey('editor-edit-status-demo'),
              decoration: const InputDecoration(labelText: 'demoLabel'),
              controller: _selectedDemoLabelController,
              onChanged: (value) => _safeUpdateSelected(
                () => StatusBoardContent(demoLabel: value),
              ),
            )
          else
            const Text(
              'Sin vincular — se podrá vincular luego.',
              style: _fieldLabelStyle,
            ),
        ],
      );
    }
    if (content is TextBoardContent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('editor-edit-text'),
            decoration: const InputDecoration(labelText: 'texto'),
            controller: _selectedTextController,
            onChanged: (value) => _safeUpdateSelected(
              () => TextBoardContent(
                text: value,
                horizontalAlignment: content.horizontalAlignment,
                sizeRole: content.sizeRole,
                fontWeight: content.fontWeight,
                maxLines: content.maxLines,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _textStyleControls(
            alignment: content.horizontalAlignment,
            sizeRole: content.sizeRole,
            weight: content.fontWeight,
            maxLines: content.maxLines,
            keyPrefix: 'editor-edit-text',
            onAlignment: (v) => _safeUpdateSelected(
              () => TextBoardContent(
                text: content.text,
                horizontalAlignment: v,
                sizeRole: content.sizeRole,
                fontWeight: content.fontWeight,
                maxLines: content.maxLines,
              ),
            ),
            onSizeRole: (v) => _safeUpdateSelected(
              () => TextBoardContent(
                text: content.text,
                horizontalAlignment: content.horizontalAlignment,
                sizeRole: v,
                fontWeight: content.fontWeight,
                maxLines: content.maxLines,
              ),
            ),
            onWeight: (v) => _safeUpdateSelected(
              () => TextBoardContent(
                text: content.text,
                horizontalAlignment: content.horizontalAlignment,
                sizeRole: content.sizeRole,
                fontWeight: v,
                maxLines: content.maxLines,
              ),
            ),
            onMaxLines: (v) => _safeUpdateSelected(
              () => TextBoardContent(
                text: content.text,
                horizontalAlignment: content.horizontalAlignment,
                sizeRole: content.sizeRole,
                fontWeight: content.fontWeight,
                maxLines: v,
              ),
            ),
          ),
        ],
      );
    }
    if (content is IconBoardContent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _iconKeyPicker(
            keyName: 'editor-edit-icon-key',
            value: content.iconKey,
            onChanged: (v) => _safeUpdateSelected(
              () => IconBoardContent(
                iconKey: v ?? content.iconKey,
                label: content.label,
                sizeRole: content.sizeRole,
                horizontalAlignment: content.horizontalAlignment,
                verticalAlignment: content.verticalAlignment,
              ),
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            key: const ValueKey('editor-edit-icon-label'),
            decoration: const InputDecoration(labelText: 'Label (opcional)'),
            controller: _selectedIconLabelController,
            onChanged: (value) => _safeUpdateSelected(
              () => IconBoardContent(
                iconKey: content.iconKey,
                label: value.trim().isEmpty ? null : value.trim(),
                sizeRole: content.sizeRole,
                horizontalAlignment: content.horizontalAlignment,
                verticalAlignment: content.verticalAlignment,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _sizeRoleDropdown(
            keyName: 'editor-edit-icon-size',
            value: content.sizeRole,
            onChanged: (v) => _safeUpdateSelected(
              () => IconBoardContent(
                iconKey: content.iconKey,
                label: content.label,
                sizeRole: v,
                horizontalAlignment: content.horizontalAlignment,
                verticalAlignment: content.verticalAlignment,
              ),
            ),
          ),
          _alignmentControls(
            horizontal: content.horizontalAlignment,
            vertical: content.verticalAlignment,
            keyPrefix: 'editor-edit-icon',
            onHorizontal: (v) => _safeUpdateSelected(
              () => IconBoardContent(
                iconKey: content.iconKey,
                label: content.label,
                sizeRole: content.sizeRole,
                horizontalAlignment: v,
                verticalAlignment: content.verticalAlignment,
              ),
            ),
            onVertical: (v) => _safeUpdateSelected(
              () => IconBoardContent(
                iconKey: content.iconKey,
                label: content.label,
                sizeRole: content.sizeRole,
                horizontalAlignment: content.horizontalAlignment,
                verticalAlignment: v,
              ),
            ),
          ),
        ],
      );
    }
    if (content is LatestEventBoardContent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _selectedBindingModeSelector(
            current: content.bindingMode,
            keyPrefix: 'editor-edit-event-binding',
            onUnbound: () => _safeUpdateSelected(
              () => LatestEventBoardContent(fields: content.fields),
            ),
            onDemo: () => _safeUpdateSelected(
              () => LatestEventBoardContent(
                fields: content.fields,
                demoValues:
                    content.demoValues ?? _demoValuesFor(content.fields),
              ),
            ),
            onBound: () => _safeUpdateSelected(
              () => LatestEventBoardContent(
                eventSourceId: content.eventSourceId ?? 'device.latestVehicle',
                fields: content.fields,
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (content.bindingMode == BoardBindingMode.bound)
            TextField(
              key: const ValueKey('editor-edit-event-source'),
              decoration: const InputDecoration(labelText: 'eventSourceId'),
              controller: _selectedDataSourceController,
              onChanged: (value) => _safeUpdateSelected(
                () => LatestEventBoardContent(
                  eventSourceId: value,
                  fields: content.fields,
                ),
              ),
            )
          else if (content.bindingMode == BoardBindingMode.demo)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Demo: ${(content.demoValues ?? const {}).values.join(' · ')}',
                    style: _fieldLabelStyle,
                  ),
                ),
                TextButton(
                  key: const ValueKey('editor-edit-event-demo-regenerate'),
                  onPressed: () => _safeUpdateSelected(
                    () => LatestEventBoardContent(
                      fields: content.fields,
                      demoValues: _demoValuesFor(content.fields),
                    ),
                  ),
                  child: const Text('Regenerar demo'),
                ),
              ],
            )
          else
            const Text(
              'Sin vincular — se podrá vincular luego.',
              style: _fieldLabelStyle,
            ),
          const SizedBox(height: 4),
          const Text('Configuración de fields:', style: _fieldLabelStyle),
          Wrap(
            spacing: 6,
            children: [
              for (final entry in _fieldPresets.entries)
                ActionChip(
                  key: ValueKey('editor-edit-event-fields-${entry.key}'),
                  label: Text(entry.key),
                  onPressed: () => _safeUpdateSelected(
                    () => LatestEventBoardContent(
                      eventSourceId: content.eventSourceId,
                      fields: entry.value,
                      demoValues: content.bindingMode == BoardBindingMode.demo
                          ? _demoValuesFor(entry.value)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
    }
    if (content is DataTableBoardContent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _selectedBindingModeSelector(
            current: content.bindingMode,
            keyPrefix: 'editor-edit-table-binding',
            onUnbound: () => _safeUpdateSelected(
              () => DataTableBoardContent(
                columns: content.columns,
                maxRows: content.maxRows,
                showHeader: content.showHeader,
              ),
            ),
            onDemo: () => _safeUpdateSelected(
              () => DataTableBoardContent(
                columns: content.columns,
                maxRows: content.maxRows,
                showHeader: content.showHeader,
                demoRows: content.demoRows ?? _demoRowsFor(content.columns),
              ),
            ),
            onBound: () => _safeUpdateSelected(
              () => DataTableBoardContent(
                dataSourceId: content.dataSourceId ?? 'device.recentRecords',
                columns: content.columns,
                maxRows: content.maxRows,
                showHeader: content.showHeader,
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (content.bindingMode == BoardBindingMode.bound)
            TextField(
              key: const ValueKey('editor-edit-table-source'),
              decoration: const InputDecoration(labelText: 'dataSourceId'),
              controller: _selectedDataSourceController,
              onChanged: (value) => _safeUpdateSelected(
                () => DataTableBoardContent(
                  dataSourceId: value,
                  columns: content.columns,
                  maxRows: content.maxRows,
                  showHeader: content.showHeader,
                ),
              ),
            )
          else if (content.bindingMode == BoardBindingMode.demo)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Demo: ${(content.demoRows ?? const []).length} fila(s)',
                    style: _fieldLabelStyle,
                  ),
                ),
                TextButton(
                  key: const ValueKey('editor-edit-table-demo-regenerate'),
                  onPressed: () => _safeUpdateSelected(
                    () => DataTableBoardContent(
                      columns: content.columns,
                      maxRows: content.maxRows,
                      showHeader: content.showHeader,
                      demoRows: _demoRowsFor(content.columns),
                    ),
                  ),
                  child: const Text('Regenerar demo'),
                ),
              ],
            )
          else
            const Text(
              'Sin vincular — se podrá vincular luego.',
              style: _fieldLabelStyle,
            ),
          const SizedBox(height: 4),
          const Text('Configuración de columnas:', style: _fieldLabelStyle),
          Wrap(
            spacing: 6,
            children: [
              for (final entry in _columnPresets.entries)
                ActionChip(
                  key: ValueKey('editor-edit-table-columns-${entry.key}'),
                  label: Text(entry.key),
                  onPressed: () => _safeUpdateSelected(
                    () => DataTableBoardContent(
                      dataSourceId: content.dataSourceId,
                      columns: entry.value,
                      maxRows: content.maxRows,
                      showHeader: content.showHeader,
                      demoRows: content.bindingMode == BoardBindingMode.demo
                          ? _demoRowsFor(entry.value)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
    }
    if (content is ChartBoardContent) {
      return TextField(
        key: const ValueKey('editor-edit-chart-source'),
        decoration: const InputDecoration(labelText: 'dataSourceId'),
        controller: _selectedDataSourceController,
        onChanged: (value) => _safeUpdateSelected(
          () => ChartBoardContent(
            dataSourceId: value,
            chartType: content.chartType,
            series: content.series,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _addContentPanel(DeviceMetricCatalog catalog) {
    final pendingResult = _tryBuildPending();
    return Container(
      key: const ValueKey('editor-add-panel'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1120),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2A3C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Agregar contenido',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final type in _addableContentTypes)
                ChoiceChip(
                  key: ValueKey('editor-add-type-${type.name}'),
                  label: Text(boardContentTypeLabel(type)),
                  selected: _pendingType == type,
                  onSelected: (_) => _startAdding(type),
                ),
            ],
          ),
          if (_pendingType != null) ...[
            const SizedBox(height: 12),
            _pendingForm(catalog),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Posición: x=', style: _fieldLabelStyle),
                _numberStepper(
                  value: _pendingX,
                  onChanged: (v) => setState(() => _pendingX = v),
                  keyName: 'editor-pending-x',
                  min: 0,
                ),
                const Text(' y=', style: _fieldLabelStyle),
                _numberStepper(
                  value: _pendingY,
                  onChanged: (v) => setState(() => _pendingY = v),
                  keyName: 'editor-pending-y',
                  min: 0,
                ),
              ],
            ),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Ancho:', style: _fieldLabelStyle),
                    _numberStepper(
                      value: _pendingWidth,
                      onChanged: (v) => setState(() => _pendingWidth = v),
                      keyName: 'editor-pending-width',
                      min: 1,
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Alto:', style: _fieldLabelStyle),
                    _numberStepper(
                      value: _pendingHeight,
                      onChanged: (v) => setState(() => _pendingHeight = v),
                      keyName: 'editor-pending-height',
                      min: 1,
                    ),
                  ],
                ),
              ],
            ),
            if (_pendingIndicatorOverflow != null)
              Text(
                key: const ValueKey('editor-pending-indicator-overflow'),
                'Seleccionaste ${_pendingIndicatorKeys.length} indicators '
                'para ${_pendingResolvedPreset!.indicatorSlotCount} slots disponibles.',
                style: _errorStyle,
              ),
            if (_pendingFieldError != null)
              Text(
                _pendingFieldError!,
                key: const ValueKey('editor-pending-error'),
                style: _errorStyle,
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  key: const ValueKey('editor-confirm-add'),
                  onPressed:
                      pendingResult == null || _pendingIndicatorOverflow != null
                      ? null
                      : _confirmAdd,
                  child: const Text('Agregar'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: const ValueKey('editor-cancel-add'),
                  onPressed: _cancelPending,
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _numberStepper({
    required int value,
    required ValueChanged<int> onChanged,
    required String keyName,
    required int min,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        key: ValueKey('$keyName-minus'),
        icon: const Icon(Icons.remove, size: 16),
        onPressed: value > min ? () => onChanged(value - 1) : null,
      ),
      SizedBox(
        width: 24,
        child: Text(
          '$value',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
      ),
      IconButton(
        key: ValueKey('$keyName-plus'),
        icon: const Icon(Icons.add, size: 16),
        onPressed: () => onChanged(value + 1),
      ),
    ],
  );

  Widget _pendingForm(DeviceMetricCatalog catalog) {
    switch (_pendingType!) {
      case BoardContentType.metric:
        // N6.5.1 §6: "Sin catálogo" (or any catalog with zero metrics) never
        // shows an empty, silently-unusable dropdown — an explicit helper
        // replaces the whole form instead, same pattern already used by
        // `_convertPlaceholderToMetric` for the same situation.
        if (catalog.metrics.isEmpty) {
          return const Text(
            key: ValueKey('editor-pending-metric-empty-catalog'),
            'Seleccioná un perfil de capacidades para agregar métricas.',
            style: _fieldLabelStyle,
          );
        }
        final availableIndicators = _pendingMetricKey == null
            ? const <String>[]
            : catalog.availableIndicators[_pendingMetricKey!] ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: DropdownButton<String>(
                key: const ValueKey('editor-pending-metric-key'),
                isExpanded: true,
                value: _pendingMetricKey,
                items: [
                  for (final metric in catalog.metrics)
                    DropdownMenuItem(
                      value: metric.key,
                      child: Text(
                        metric.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (key) => setState(() {
                  _pendingMetricKey = key;
                  // N6.5.2 §8 — re-selecting a metric resets the prefill to
                  // *that* metric's suggestions, not to whatever was checked
                  // for the previous one.
                  _pendingIndicatorKeys
                    ..clear()
                    ..addAll(_suggestedIndicatorsFor(key));
                }),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Text('Diseño de celda:', style: _fieldLabelStyle),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String?>(
                    key: const ValueKey('editor-pending-preset'),
                    isExpanded: true,
                    value: _pendingPresetId,
                    items: _presetDropdownItems(
                      width: _pendingWidth,
                      height: _pendingHeight,
                      currentPresetId: _pendingPresetId,
                    ),
                    onChanged: (id) => setState(() => _pendingPresetId = id),
                  ),
                ),
              ],
            ),
            if (availableIndicators.isNotEmpty) ...[
              const SizedBox(height: 4),
              const Text('Indicators:', style: _fieldLabelStyle),
              Wrap(
                spacing: 4,
                children: [
                  for (final key in availableIndicators)
                    FilterChip(
                      key: ValueKey('editor-pending-indicator-$key'),
                      label: Text(key),
                      selected: _pendingIndicatorKeys.contains(key),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _pendingIndicatorKeys.add(key);
                        } else {
                          _pendingIndicatorKeys.remove(key);
                        }
                      }),
                    ),
                ],
              ),
            ],
          ],
        );
      case BoardContentType.image:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: DropdownButton<BoardImageSourceType>(
                key: const ValueKey('editor-pending-image-source'),
                isExpanded: true,
                value: _pendingImageSource,
                items: [
                  for (final source in BoardImageSourceType.values)
                    DropdownMenuItem(
                      value: source,
                      child: Text(imageSourceTypeLabel(source)),
                    ),
                ],
                onChanged: (v) => setState(
                  () => _pendingImageSource = v ?? _pendingImageSource,
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              key: const ValueKey('editor-pending-image-ref'),
              controller: _sourceRefController,
              decoration: InputDecoration(
                labelText: imageSourceRefLabel(_pendingImageSource),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: DropdownButton<BoardImageFit>(
                key: const ValueKey('editor-pending-image-fit'),
                isExpanded: true,
                value: _pendingImageFit,
                items: [
                  for (final fit in BoardImageFit.values)
                    DropdownMenuItem(value: fit, child: Text(fit.name)),
                ],
                onChanged: (v) =>
                    setState(() => _pendingImageFit = v ?? _pendingImageFit),
              ),
            ),
            Text(imageFitHelp(_pendingImageFit), style: _fieldLabelStyle),
          ],
        );
      case BoardContentType.chart:
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<BoardChartType>(
              key: const ValueKey('editor-pending-chart-type'),
              value: _pendingChartType,
              items: [
                for (final type in BoardChartType.values)
                  DropdownMenuItem(value: type, child: Text(type.name)),
              ],
              onChanged: (v) =>
                  setState(() => _pendingChartType = v ?? _pendingChartType),
            ),
            SizedBox(
              width: 180,
              child: TextField(
                key: const ValueKey('editor-pending-data-source'),
                controller: _dataSourceController,
                decoration: const InputDecoration(labelText: 'dataSourceId'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        );
      case BoardContentType.status:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _pendingBindingModeSelector(),
            const SizedBox(height: 4),
            if (_pendingBindingMode == BoardBindingMode.bound)
              TextField(
                key: const ValueKey('editor-pending-data-source'),
                controller: _dataSourceController,
                decoration: const InputDecoration(labelText: 'dataSourceId'),
                onChanged: (_) => setState(() {}),
              )
            else if (_pendingBindingMode == BoardBindingMode.demo)
              Text(
                'Demo: ${_pendingDemoValues?['status'] ?? 'Operativo'}',
                style: _fieldLabelStyle,
              )
            else
              const Text(
                'Sin vincular — se podrá vincular luego.',
                style: _fieldLabelStyle,
              ),
          ],
        );
      case BoardContentType.latestEvent:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _pendingBindingModeSelector(),
            const SizedBox(height: 4),
            if (_pendingBindingMode == BoardBindingMode.bound)
              TextField(
                key: const ValueKey('editor-pending-data-source'),
                controller: _dataSourceController,
                decoration: const InputDecoration(labelText: 'eventSourceId'),
                onChanged: (_) => setState(() {}),
              )
            else if (_pendingBindingMode == BoardBindingMode.demo)
              Text(
                'Demo: ${(_pendingDemoValues ?? _demoValuesFor(_pendingFields)).values.join(' · ')}',
                style: _fieldLabelStyle,
              )
            else
              const Text(
                'Sin vincular — se podrá vincular luego.',
                style: _fieldLabelStyle,
              ),
            const SizedBox(height: 4),
            const Text('Configuración de fields:', style: _fieldLabelStyle),
            Wrap(
              spacing: 6,
              children: [
                for (final entry in _fieldPresets.entries)
                  ChoiceChip(
                    key: ValueKey('editor-pending-event-fields-${entry.key}'),
                    label: Text(entry.key),
                    selected: identical(_pendingFields, entry.value),
                    onSelected: (_) => setState(() {
                      _pendingFields = entry.value;
                      _pendingDemoValues = null;
                    }),
                  ),
              ],
            ),
          ],
        );
      case BoardContentType.dataTable:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _pendingBindingModeSelector(),
            const SizedBox(height: 4),
            if (_pendingBindingMode == BoardBindingMode.bound)
              TextField(
                key: const ValueKey('editor-pending-data-source'),
                controller: _dataSourceController,
                decoration: const InputDecoration(labelText: 'dataSourceId'),
                onChanged: (_) => setState(() {}),
              )
            else if (_pendingBindingMode == BoardBindingMode.demo)
              Text(
                'Demo: ${(_pendingDemoRows ?? _demoRowsFor(_pendingColumns)).first.values.join(' · ')}',
                style: _fieldLabelStyle,
              )
            else
              const Text(
                'Sin vincular — se podrá vincular luego.',
                style: _fieldLabelStyle,
              ),
            const SizedBox(height: 4),
            const Text('Configuración de columnas:', style: _fieldLabelStyle),
            Wrap(
              spacing: 6,
              children: [
                for (final entry in _columnPresets.entries)
                  ChoiceChip(
                    key: ValueKey('editor-pending-table-columns-${entry.key}'),
                    label: Text(entry.key),
                    selected: identical(_pendingColumns, entry.value),
                    onSelected: (_) => setState(() {
                      _pendingColumns = entry.value;
                      _pendingDemoRows = null;
                    }),
                  ),
              ],
            ),
          ],
        );
      case BoardContentType.text:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('editor-pending-text'),
              controller: _textController,
              decoration: const InputDecoration(labelText: 'texto'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            _textStyleControls(
              alignment: _pendingTextAlignment,
              sizeRole: _pendingTextSizeRole,
              weight: _pendingTextWeight,
              maxLines: _pendingTextMaxLines,
              keyPrefix: 'editor-pending-text',
              onAlignment: (v) => setState(() => _pendingTextAlignment = v),
              onSizeRole: (v) => setState(() => _pendingTextSizeRole = v),
              onWeight: (v) => setState(() => _pendingTextWeight = v),
              onMaxLines: (v) => setState(() => _pendingTextMaxLines = v),
            ),
          ],
        );
      case BoardContentType.icon:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _iconKeyPicker(
              keyName: 'editor-pending-icon-key',
              value: _pendingIconKey,
              onChanged: (v) =>
                  setState(() => _pendingIconKey = v ?? _pendingIconKey),
            ),
            const SizedBox(height: 4),
            TextField(
              key: const ValueKey('editor-pending-icon-label'),
              controller: _pendingIconLabelController,
              decoration: const InputDecoration(labelText: 'Label (opcional)'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            _sizeRoleDropdown(
              keyName: 'editor-pending-icon-size',
              value: _pendingIconSizeRole,
              onChanged: (v) => setState(() => _pendingIconSizeRole = v),
            ),
            _alignmentControls(
              horizontal: _pendingIconHAlign,
              vertical: _pendingIconVAlign,
              keyPrefix: 'editor-pending-icon',
              onHorizontal: (v) => setState(() => _pendingIconHAlign = v),
              onVertical: (v) => setState(() => _pendingIconVAlign = v),
            ),
          ],
        );
      case BoardContentType.placeholder:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('editor-pending-placeholder-label'),
              controller: _pendingPlaceholderLabelController,
              decoration: const InputDecoration(labelText: 'Label'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('editor-pending-placeholder-mock'),
                    controller: _pendingPlaceholderMockValueController,
                    decoration: const InputDecoration(
                      labelText: 'mockValue (preview, nunca real)',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  child: TextField(
                    key: const ValueKey('editor-pending-placeholder-unit'),
                    controller: _pendingPlaceholderUnitController,
                    decoration: const InputDecoration(labelText: 'unit'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _iconKeyPicker(
              keyName: 'editor-pending-placeholder-icon',
              value: _pendingPlaceholderIconKey,
              allowNone: true,
              onChanged: (v) => setState(() => _pendingPlaceholderIconKey = v),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Text('Estilo:', style: _fieldLabelStyle),
                const SizedBox(width: 8),
                DropdownButton<BoardPlaceholderStyle>(
                  key: const ValueKey('editor-pending-placeholder-style'),
                  value: _pendingPlaceholderStyle,
                  items: [
                    for (final s in BoardPlaceholderStyle.values)
                      DropdownMenuItem(value: s, child: Text(s.name)),
                  ],
                  onChanged: (v) => setState(
                    () => _pendingPlaceholderStyle =
                        v ?? _pendingPlaceholderStyle,
                  ),
                ),
              ],
            ),
          ],
        );
    }
  }

  /// N6.4 §14: unbound/demo/bound selector shared by status/latestEvent/
  /// dataTable's pending form — switching away from "Demo" clears any stale
  /// generated demo values so the next Demo selection regenerates fresh
  /// ones from whatever fields/columns are configured then.
  Widget _pendingBindingModeSelector() => Wrap(
    spacing: 6,
    children: [
      for (final mode in BoardBindingMode.values)
        ChoiceChip(
          key: ValueKey('editor-pending-binding-${mode.name}'),
          label: Text(boardBindingModeLabel(mode)),
          selected: _pendingBindingMode == mode,
          onSelected: (_) => setState(() {
            _pendingBindingMode = mode;
            if (mode != BoardBindingMode.demo) {
              _pendingDemoValues = null;
              _pendingDemoRows = null;
            }
          }),
        ),
    ],
  );

  /// Selected-item counterpart of [_pendingBindingModeSelector] — applies
  /// immediately via `_safeUpdateSelected` (no separate draft state; the
  /// content itself is always the source of truth once an item exists).
  Widget _selectedBindingModeSelector({
    required BoardBindingMode current,
    required String keyPrefix,
    required VoidCallback onUnbound,
    required VoidCallback onDemo,
    required VoidCallback onBound,
  }) => Wrap(
    spacing: 6,
    children: [
      for (final mode in BoardBindingMode.values)
        ChoiceChip(
          key: ValueKey('$keyPrefix-${mode.name}'),
          label: Text(boardBindingModeLabel(mode)),
          selected: current == mode,
          onSelected: (_) => switch (mode) {
            BoardBindingMode.unbound => onUnbound(),
            BoardBindingMode.demo => onDemo(),
            BoardBindingMode.bound => onBound(),
          },
        ),
    ],
  );

  /// N6.4 §10: the one reusable icon selector — every icon/placeholder
  /// field that needs an icon key goes through this, never a bespoke
  /// dropdown of its own. `allowNone` adds a "(sin icono)" option, used by
  /// placeholder since its icon is optional.
  Widget _iconKeyPicker({
    required String keyName,
    required String? value,
    required ValueChanged<String?> onChanged,
    bool allowNone = false,
  }) => Row(
    children: [
      const Text('Icono:', style: _fieldLabelStyle),
      const SizedBox(width: 8),
      Expanded(
        child: DropdownButton<String?>(
          key: ValueKey(keyName),
          isExpanded: true,
          value: value,
          items: [
            if (allowNone)
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('(sin icono)'),
              ),
            for (final key in templateIconKeys)
              DropdownMenuItem<String?>(
                value: key,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(resolveTemplateIcon(key), size: 16),
                    const SizedBox(width: 6),
                    Text(key, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    ],
  );

  Widget _sizeRoleDropdown({
    required String keyName,
    required CellSizeRole value,
    required ValueChanged<CellSizeRole> onChanged,
  }) => Row(
    children: [
      const Text('Tamaño:', style: _fieldLabelStyle),
      const SizedBox(width: 8),
      DropdownButton<CellSizeRole>(
        key: ValueKey(keyName),
        value: value,
        items: [
          for (final s in CellSizeRole.values)
            DropdownMenuItem(value: s, child: Text(s.name)),
        ],
        onChanged: (v) => onChanged(v ?? value),
      ),
    ],
  );

  Widget _alignmentControls({
    required CellHorizontalAlignment horizontal,
    required CellVerticalAlignment vertical,
    required String keyPrefix,
    required ValueChanged<CellHorizontalAlignment> onHorizontal,
    required ValueChanged<CellVerticalAlignment> onVertical,
  }) => Wrap(
    spacing: 12,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Horizontal:', style: _fieldLabelStyle),
          const SizedBox(width: 8),
          DropdownButton<CellHorizontalAlignment>(
            key: ValueKey('$keyPrefix-h-align'),
            value: horizontal,
            items: [
              for (final a in CellHorizontalAlignment.values)
                DropdownMenuItem(value: a, child: Text(a.name)),
            ],
            onChanged: (v) => onHorizontal(v ?? horizontal),
          ),
        ],
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Vertical:', style: _fieldLabelStyle),
          const SizedBox(width: 8),
          DropdownButton<CellVerticalAlignment>(
            key: ValueKey('$keyPrefix-v-align'),
            value: vertical,
            items: [
              for (final a in CellVerticalAlignment.values)
                DropdownMenuItem(value: a, child: Text(a.name)),
            ],
            onChanged: (v) => onVertical(v ?? vertical),
          ),
        ],
      ),
    ],
  );

  Widget _textStyleControls({
    required CellHorizontalAlignment alignment,
    required CellSizeRole sizeRole,
    required CellFontWeight weight,
    required int maxLines,
    required String keyPrefix,
    required ValueChanged<CellHorizontalAlignment> onAlignment,
    required ValueChanged<CellSizeRole> onSizeRole,
    required ValueChanged<CellFontWeight> onWeight,
    required ValueChanged<int> onMaxLines,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Text('Alineación:', style: _fieldLabelStyle),
          const SizedBox(width: 8),
          DropdownButton<CellHorizontalAlignment>(
            key: ValueKey('$keyPrefix-align'),
            value: alignment,
            items: [
              for (final a in CellHorizontalAlignment.values)
                DropdownMenuItem(value: a, child: Text(a.name)),
            ],
            onChanged: (v) => onAlignment(v ?? alignment),
          ),
        ],
      ),
      _sizeRoleDropdown(
        keyName: '$keyPrefix-size',
        value: sizeRole,
        onChanged: onSizeRole,
      ),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Peso:', style: _fieldLabelStyle),
          const SizedBox(width: 8),
          DropdownButton<CellFontWeight>(
            key: ValueKey('$keyPrefix-weight'),
            value: weight,
            items: [
              for (final w in CellFontWeight.values)
                DropdownMenuItem(value: w, child: Text(w.name)),
            ],
            onChanged: (v) => onWeight(v ?? weight),
          ),
          const SizedBox(width: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Líneas:', style: _fieldLabelStyle),
              IconButton(
                key: ValueKey('$keyPrefix-maxlines-minus'),
                icon: const Icon(Icons.remove, size: 16),
                onPressed: maxLines > 1 ? () => onMaxLines(maxLines - 1) : null,
              ),
              Text('$maxLines', style: const TextStyle(color: Colors.white)),
              IconButton(
                key: ValueKey('$keyPrefix-maxlines-plus'),
                icon: const Icon(Icons.add, size: 16),
                onPressed: () => onMaxLines(maxLines + 1),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
