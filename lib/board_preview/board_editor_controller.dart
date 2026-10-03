import 'package:flutter/foundation.dart';
import '../board_content/board_content_config.dart';
import '../board_content/board_content_layout.dart';
import '../board_content/board_content_validator.dart';
import '../board_presets/board_preset.dart';
import '../board_presets/board_preset_catalog.dart'
    show resolveLayoutTemplateId;
import '../cell_layout_presets/cell_layout_catalog.dart';
import '../device_board_layouts/layout_validation_issue.dart';
import '../device_capabilities/device_capability_profile.dart';
import '../device_metric_catalogs/device_metric_catalog.dart';
import '../layout_templates/grid_placement.dart';
import '../layout_templates/layout_template.dart';
import '../layout_templates/layout_template_catalog.dart';
import 'preview_board_data.dart';

/// What a [BoardEditorController] is currently editing (N6.2 §12). `null`
/// (the default, used by every pre-N6.2 call site) means the classic
/// fixture-demo playground — unchanged behavior. [preset] is implemented by
/// N6.2; [device] is implemented by N7.1 §13 (`BoardEditorController.forDevice`).
enum BoardEditorMode { preset, device }

/// N7.1 §14 — the save lifecycle the UI renders as "Cambios sin guardar" /
/// [Guardar]. [dirty] (pre-existing) answers "is there anything to save";
/// [saveStatus] answers "what is the last save attempt doing/did". No
/// auto-save (§14): [saveStatus] only ever changes in response to an
/// explicit `Guardar` tap, orchestrated by the page layer (the controller
/// itself never touches a repository).
enum BoardSaveStatus { idle, saving, saved, error }

/// In-memory editable snapshot of either a [PreviewBoardFixture] (demo
/// playground) or a [BoardPreset] (N6.2). Never touches Firestore,
/// MetricDefinition, or a real Device — only assembles and reassembles the
/// immutable N3/N4.5 domain objects it already trusts. Validation is never
/// reimplemented here: every mutation is followed by a fresh
/// [BoardContentValidator.validate] call read by the UI.
class BoardEditorController extends ChangeNotifier {
  BoardEditorController({required PreviewBoardFixture initial}) : mode = null {
    _applyFixture(initial);
  }

  /// Edits a [BoardPreset] against a stable validation catalog. Production
  /// callers supply the projection of the complete global metric/indicator
  /// libraries. A profile filter belongs to the page's picker state and is
  /// deliberately absent from this controller, so changing it cannot alter
  /// validation or dirty state. [profile]/[profileId] remain optional for
  /// source compatibility with older tools; preset mode does not mutate them.
  BoardEditorController.forPreset({
    required BoardPreset preset,
    required DeviceMetricCatalog catalog,
    DeviceCapabilityProfile? profile,
    String? profileId,
  }) : mode = BoardEditorMode.preset,
       _presetCatalog = catalog,
       _presetProfile = profile,
       _presetProfileId = profileId {
    _applyPreset(preset);
  }

  /// N7.1 §13 — edits a real Device's [BoardContentLayout] instead of a
  /// [BoardPreset] or demo fixture. `context = Tenant/Site/Device real,
  /// profile = Device real, save = DeviceBoardLayoutRepository` (§13's own
  /// words): [tenantId]/[deviceId] identify the real Device the page layer
  /// will persist through `DeviceBoardConfigRepository` — this controller
  /// never touches Firestore itself, it only carries the identifiers and
  /// the loaded [layout]'s own trazability fields
  /// (`sourceBoardPresetId`/`sourceBoardPresetVersion`) forward unchanged
  /// (§14: editing a Device's board never fabricates new trazability).
  ///
  /// N7.1.1 §9 — [expectedRemoteVersion] is deliberately a *separate*
  /// parameter from [layout]'s own `layoutVersion`: the model's
  /// `layoutVersion` is never allowed to be less than 1 (a content-version
  /// label), while "no remote document exists yet" is a real, distinct
  /// state the page layer must be able to express as `0`. Conflating the
  /// two (letting the page build a never-persisted placeholder `layout`
  /// with the model's default `layoutVersion = 1` and using THAT as the
  /// expected version) is exactly the bug this separation fixes: a Device's
  /// very first save used to always race against a fabricated "expected 1"
  /// while the repository's own transaction correctly computed the true
  /// "actual 0" for a nonexistent document, producing a spurious conflict
  /// on every first save.
  BoardEditorController.forDevice({
    required String tenantId,
    required BoardContentLayout layout,
    required int expectedRemoteVersion,
    required DeviceMetricCatalog catalog,
    DeviceCapabilityProfile? profile,
    String? profileId,
  }) : mode = BoardEditorMode.device,
       _tenantId = tenantId,
       _presetCatalog = catalog,
       _presetProfile = profile,
       _presetProfileId = profileId {
    _applyDeviceLayout(layout, expectedRemoteVersion);
  }

  final BoardEditorMode? mode;

  PreviewBoardFixture? _active;
  BoardPreset? _pristinePreset;
  BoardContentLayout? _pristineDeviceLayout;
  String? _tenantId;
  DeviceMetricCatalog? _presetCatalog;
  DeviceCapabilityProfile? _presetProfile;
  String? _presetProfileId;
  late LayoutTemplate _template;
  late List<BoardContentItem> _items;
  late bool _showTitle;
  String? _titleOverride;
  late String _deviceId;
  late int _layoutVersion;
  String? _sourceBoardPresetId;
  int? _sourceBoardPresetVersion;
  int _nextSeq = 0;

  /// N7.1.1 §9 — device mode only: what the page layer must send as
  /// `expectedLayoutVersion` on the next save. `0` means "no remote
  /// document exists yet" — see [BoardEditorController.forDevice]'s doc
  /// comment. Distinct from [_layoutVersion] (the content's own version
  /// label, always ≥1).
  int _expectedRemoteVersion = 0;

  /// N7.1.1 §7/§8 — monotonic local edit counter (A4's "revisión local
  /// monotónica"), incremented by every mutator alongside [_dirty]. The
  /// page layer captures this right before an async save; [markSaved]
  /// compares it against the *current* value to tell whether any edit
  /// happened while that save was in flight.
  int _revision = 0;

  String? selectedItemId;
  bool editMode = true;
  bool _dirty = false;
  BoardSaveStatus _saveStatus = BoardSaveStatus.idle;
  String? _saveError;

  PreviewBoardFixture get activeFixture => _active!;
  BoardPreset? get activePreset => _pristinePreset;
  LayoutTemplate get template => _template;
  List<BoardContentItem> get items => List.unmodifiable(_items);
  bool get showTitle => _showTitle;
  String? get titleOverride => _titleOverride;
  bool get dirty => _dirty;
  DeviceMetricCatalog get catalog => _presetCatalog ?? _active!.catalog;

  /// Only meaningful in device mode ([mode] == [BoardEditorMode.device]).
  String? get tenantId => _tenantId;
  String get deviceId => _deviceId;

  /// The `layoutVersion` the currently-loaded Device board was fetched at —
  /// what the page layer must pass back as `expectedLayoutVersion` to
  /// `DeviceBoardConfigRepository.saveLayout` (N7.1 §15). Unrelated to
  /// preset mode, where a preset's own `presetVersion` is tracked
  /// separately by the page layer, not by this controller. Purely a display
  /// label ("Guardado · vN") — see [expectedRemoteVersion] for what the
  /// page layer must actually send on save (N7.1.1 §9).
  int get loadedLayoutVersion => _layoutVersion;

  /// N7.1.1 §9 — the real `expectedLayoutVersion` for the next save; `0`
  /// exactly when no remote document exists yet (never fabricated from
  /// [loadedLayoutVersion]'s ≥1 content-version label). See
  /// [BoardEditorController.forDevice].
  int get expectedRemoteVersion => _expectedRemoteVersion;

  /// Version of the last confirmed [BoardPreset] baseline. Preset editing
  /// keeps a local draft until an explicit save succeeds.
  int get loadedPresetVersion => _pristinePreset?.presetVersion ?? 0;

  /// Last confirmed preset, used to restore the surrounding local catalog
  /// when the user explicitly discards the isolated editor draft.
  BoardPreset? get confirmedPreset => _pristinePreset;

  /// N7.1.1 §7/§8 — see [_revision]'s doc comment.
  int get revision => _revision;
  String? get sourceBoardPresetId => _sourceBoardPresetId;
  int? get sourceBoardPresetVersion => _sourceBoardPresetVersion;

  /// N7.1 §14 — see [BoardSaveStatus]. Never mutated by this controller on
  /// its own: only [markSaving]/[markSaved]/[markSaveError], called by the
  /// page layer around its own `DeviceBoardConfigRepository.saveLayout`
  /// call.
  BoardSaveStatus get saveStatus => _saveStatus;
  String? get saveError => _saveError;

  /// The source [DeviceCapabilityProfile] [catalog] was resolved from
  /// (N6.5.2 §8) — `null` in fixture mode, when no profile is selected
  /// ("Sin perfil"), or when [catalog] was an explicit test/tool override.
  /// Only ever read for `suggestedIndicatorsByMetric`; never consulted by
  /// validation or rendering.
  DeviceCapabilityProfile? get profile => _presetProfile;

  /// Only meaningful in preset mode; `null` in fixture mode or when
  /// [catalog] was supplied as an explicit override rather than resolved
  /// from the preset's own `capabilityProfileId` (N6.5 §25, renamed N6.5.2
  /// §17).
  String? get presetProfileId => _presetProfileId;

  BoardContentItem? get selectedItem {
    final id = selectedItemId;
    if (id == null) return null;
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Rebuilds the current preset draft without mutating the catalog that
  /// supplied the baseline. Persistence belongs to the page/caller layer.
  BoardPreset get presetDraft {
    if (mode != BoardEditorMode.preset || _pristinePreset == null) {
      throw StateError('presetDraft is only available in preset mode');
    }
    return _pristinePreset!.copyWith(
      layoutTemplateId: _template.id,
      items: _items,
      showTitleDefault: _showTitle,
      titleOverride: _titleOverride,
      clearTitleOverride: _titleOverride == null,
      presetVersion: _pristinePreset!.presetVersion + 1,
    );
  }

  /// Rebuilt immutable board — the single object every validator/renderer
  /// downstream consumes. Never mutated in place. In device mode, carries
  /// [_presetProfileId]/[_sourceBoardPresetId]/[_sourceBoardPresetVersion]
  /// forward exactly as loaded (§14 — editing never fabricates new
  /// trazability); in preset/fixture mode those are always `null`, matching
  /// pre-N7.1 behavior.
  BoardContentLayout get board => BoardContentLayout(
    deviceId: _deviceId,
    layoutTemplateId: _template.id,
    showTitle: _showTitle,
    titleOverride: _titleOverride,
    layoutVersion: _layoutVersion,
    capabilityProfileId: mode == BoardEditorMode.device
        ? _presetProfileId
        : null,
    sourceBoardPresetId: _sourceBoardPresetId,
    sourceBoardPresetVersion: _sourceBoardPresetVersion,
    items: _items,
  );

  List<LayoutValidationIssue> issues(CellLayoutCatalog presets) =>
      BoardContentValidator.validate(board, _template, catalog, presets);

  void _applyFixture(PreviewBoardFixture fixture) {
    _active = fixture;
    _pristinePreset = null;
    _template = fixture.template;
    _items = List.of(fixture.board.items);
    _showTitle = fixture.board.showTitle;
    _titleOverride = fixture.board.titleOverride;
    _deviceId = fixture.board.deviceId;
    _layoutVersion = fixture.board.layoutVersion;
    selectedItemId = null;
    _nextSeq = 0;
  }

  // N6.5: Reset (§34) restores board content/title exactly as before, but
  // deliberately leaves the current metric-catalog selection alone — same
  // treatment as `_fixtureIndex` in fixture mode, which Reset never reverts
  // either. Switching catalogs is session-level navigation, not a draft.
  void _applyPreset(BoardPreset preset) {
    _pristinePreset = preset;
    _active = null;
    _template = resolveLayoutTemplateId(preset.layoutTemplateId);
    _items = List.of(preset.items);
    _showTitle = preset.showTitleDefault;
    _titleOverride = preset.titleOverride;
    _deviceId = preset.id;
    _layoutVersion = 1;
    selectedItemId = null;
    _nextSeq = 0;
  }

  /// N7.1 §13 — loads a real Device's persisted [BoardContentLayout] the
  /// same way `_applyPreset` loads a [BoardPreset]: [layout.layoutVersion]
  /// becomes [loadedLayoutVersion] (a display label only — N7.1.1 §9), and
  /// `sourceBoardPresetId`/`sourceBoardPresetVersion` are carried forward
  /// untouched, never recomputed here. [expectedRemoteVersion] is the real
  /// value the next save must send — see [BoardEditorController.forDevice].
  void _applyDeviceLayout(
    BoardContentLayout layout,
    int expectedRemoteVersion,
  ) {
    _pristineDeviceLayout = layout;
    _active = null;
    _pristinePreset = null;
    _template = resolveLayoutTemplateId(layout.layoutTemplateId);
    _items = List.of(layout.items);
    _showTitle = layout.showTitle;
    _titleOverride = layout.titleOverride;
    _deviceId = layout.deviceId;
    _layoutVersion = layout.layoutVersion;
    _expectedRemoteVersion = expectedRemoteVersion;
    _revision = 0;
    _sourceBoardPresetId = layout.sourceBoardPresetId;
    _sourceBoardPresetVersion = layout.sourceBoardPresetVersion;
    selectedItemId = null;
    _nextSeq = 0;
  }

  /// Switches to a different pristine fixture (Sala/Laboratorio/Arco). Only
  /// meaningful in fixture mode ([mode] == null).
  void applyFixture(PreviewBoardFixture fixture) {
    _applyFixture(fixture);
    _dirty = false;
    notifyListeners();
  }

  /// Restores the pristine state: the fixture reference in fixture mode,
  /// the [BoardPreset] snapshot taken when the editor was opened in preset
  /// mode, or the [BoardContentLayout] last loaded/saved in device mode
  /// (N6.2 §3 — Reset must fully clear ephemeral state; the page layer
  /// clears its own drafts/controllers on top of this).
  void reset() {
    switch (mode) {
      case BoardEditorMode.preset:
        _applyPreset(_pristinePreset!);
      case BoardEditorMode.device:
        // Resetting discards local edits only — it never changes what the
        // remote document actually is, so the same expected-remote-version
        // baseline carries through unchanged.
        _applyDeviceLayout(_pristineDeviceLayout!, _expectedRemoteVersion);
      case null:
        _applyFixture(_active!);
    }
    _dirty = false;
    _saveStatus = BoardSaveStatus.idle;
    _saveError = null;
    notifyListeners();
  }

  void toggleEditMode() {
    editMode = !editMode;
    notifyListeners();
  }

  /// N7.1.1 §7/§8 — every mutator goes through this instead of setting
  /// `_dirty = true` directly, so [_revision] can never drift out of sync
  /// with "is there an unsaved edit". See [markSaved].
  void _markDirty() {
    _dirty = true;
    _revision++;
  }

  /// N7.1 §14 — called by the page layer right before it starts an async
  /// `DeviceBoardConfigRepository.saveLayout` call.
  void markSaving() {
    _saveStatus = BoardSaveStatus.saving;
    _saveError = null;
    notifyListeners();
  }

  /// N7.1 §14, revised N7.1.1 §7/§8 (finding A4) — called after a
  /// successful save. [sentLayout]/[sentRevision] are exactly what the page
  /// layer sent and what [revision] read right before that `await` started;
  /// [savedLayoutVersion] is what the repository returned.
  ///
  /// The remote document is now unambiguously `sentLayout` at
  /// `savedLayoutVersion` — that always becomes the new [reset] baseline and
  /// the new [expectedRemoteVersion] for the next save, regardless of
  /// anything else. What differs is whether the *editable* state also jumps
  /// to that confirmed content:
  /// - `sentRevision == revision` (nothing changed locally while the save
  ///   was in flight): yes — this is the normal case, dirty clears, "Cambios
  ///   sin guardar" disappears.
  /// - `sentRevision != revision` (the user kept editing during the
  ///   `await`): no — the in-progress edits are real, newer, and were never
  ///   sent; they stay on screen and [dirty] stays `true`, so a follow-up
  ///   Guardar sends *them* next, now correctly checked against
  ///   `savedLayoutVersion` instead of the stale version that would have
  ///   produced a spurious conflict. This is the exact bug A4 reported:
  ///   before this fix, [markSaved] adopted whatever was on screen *at
  ///   call time* as "saved", silently discarding the fact that it was
  ///   never transmitted.
  void markSaved({
    required BoardContentLayout sentLayout,
    required int savedLayoutVersion,
    required int sentRevision,
  }) {
    final BoardContentLayout confirmed = BoardContentLayout(
      deviceId: sentLayout.deviceId,
      layoutTemplateId: sentLayout.layoutTemplateId,
      showTitle: sentLayout.showTitle,
      titleOverride: sentLayout.titleOverride,
      layoutVersion: savedLayoutVersion,
      capabilityProfileId: sentLayout.capabilityProfileId,
      sourceBoardPresetId: sentLayout.sourceBoardPresetId,
      sourceBoardPresetVersion: sentLayout.sourceBoardPresetVersion,
      items: sentLayout.items,
    );
    _pristineDeviceLayout = confirmed;
    _expectedRemoteVersion = savedLayoutVersion;
    if (sentRevision == _revision) {
      _layoutVersion = confirmed.layoutVersion;
      _template = resolveLayoutTemplateId(confirmed.layoutTemplateId);
      _items = List.of(confirmed.items);
      _showTitle = confirmed.showTitle;
      _titleOverride = confirmed.titleOverride;
      _sourceBoardPresetId = confirmed.sourceBoardPresetId;
      _sourceBoardPresetVersion = confirmed.sourceBoardPresetVersion;
      _dirty = false;
    }
    _saveStatus = BoardSaveStatus.saved;
    _saveError = null;
    notifyListeners();
  }

  /// Confirms an explicitly persisted preset draft as the new reset
  /// baseline. The revision guard mirrors [markSaved]: edits made while an
  /// asynchronous save was in flight remain dirty instead of being lost.
  void markPresetSaved({
    required BoardPreset sentPreset,
    required int savedPresetVersion,
    required int sentRevision,
  }) {
    if (mode != BoardEditorMode.preset) {
      throw StateError('markPresetSaved is only available in preset mode');
    }
    final confirmed = sentPreset.copyWith(presetVersion: savedPresetVersion);
    _pristinePreset = confirmed;
    if (sentRevision == _revision) {
      _applyPreset(confirmed);
      _dirty = false;
    }
    _saveStatus = BoardSaveStatus.saved;
    _saveError = null;
    notifyListeners();
  }

  /// N7.1 §14/§15 — a failed save (validation rejected it, a
  /// [FirestoreVersionConflict] fired, or any other error). [dirty] is
  /// deliberately left untouched: the user's edits are still there,
  /// unsaved, exactly as `.md` says "No pisar silenciosamente" — nothing is
  /// discarded just because a save attempt failed.
  void markSaveError(String message) {
    _saveStatus = BoardSaveStatus.error;
    _saveError = message;
    notifyListeners();
  }

  void selectItem(String? id) {
    selectedItemId = id;
    notifyListeners();
  }

  /// Selecting the layout template already in effect is a no-op (N6.2 §2):
  /// no exception, no spurious dirty flag, no rebuild. Always resolve/apply
  /// from [effectiveLayoutTemplates] on the caller's side, never a separate
  /// filtered list, so the dropdown and this callback can never disagree
  /// about which templates exist.
  void setLayoutTemplate(LayoutTemplate next) {
    if (next.id == _template.id) return;
    _template = next;
    _markDirty();
    notifyListeners();
  }

  String _freshId(BoardContentType type) {
    final used = _items.map((i) => i.id).toSet();
    var candidate = '${type.name}-${_nextSeq++}';
    while (used.contains(candidate)) {
      candidate = '${type.name}-${_nextSeq++}';
    }
    return candidate;
  }

  /// Adds [content] at [x],[y] with the given span. No collision/bounds
  /// pre-check here on purpose: the change always applies and the resulting
  /// issues (if any) surface through [issues], matching N1-N5's philosophy
  /// of never hiding invalid state behind silently-blocked UI actions.
  String addItem({
    required BoardContentConfig content,
    required int x,
    required int y,
    required int widthCells,
    required int heightCells,
  }) {
    final id = _freshId(content.type);
    final item = BoardContentItem(
      id: id,
      placement: GridPlacement(
        x: x,
        y: y,
        widthCells: widthCells,
        heightCells: heightCells,
      ),
      content: content,
    );
    _items = [..._items, item];
    selectedItemId = id;
    _markDirty();
    notifyListeners();
    return id;
  }

  void removeSelected() {
    final id = selectedItemId;
    if (id == null) return;
    _items = _items.where((i) => i.id != id).toList();
    selectedItemId = null;
    _markDirty();
    notifyListeners();
  }

  void _replaceSelected(BoardContentItem next) {
    final id = selectedItemId;
    if (id == null) return;
    _items = [
      for (final item in _items)
        if (item.id == id) next else item,
    ];
    selectedItemId = next.id;
    _markDirty();
    notifyListeners();
  }

  void moveSelectedTo(int x, int y) {
    final current = selectedItem;
    if (current == null) return;
    _replaceSelected(
      BoardContentItem(
        id: current.id,
        placement: GridPlacement(
          x: x,
          y: y,
          widthCells: current.placement.widthCells,
          heightCells: current.placement.heightCells,
        ),
        content: current.content,
      ),
    );
  }

  void moveSelectedBy(int dx, int dy) {
    final current = selectedItem;
    if (current == null) return;
    final nextX = current.placement.x + dx;
    final nextY = current.placement.y + dy;
    if (nextX < 0 || nextY < 0) return;
    moveSelectedTo(nextX, nextY);
  }

  void resizeSelected({int? widthCells, int? heightCells}) {
    final current = selectedItem;
    if (current == null) return;
    _replaceSelected(
      BoardContentItem(
        id: current.id,
        placement: GridPlacement(
          x: current.placement.x,
          y: current.placement.y,
          widthCells: widthCells ?? current.placement.widthCells,
          heightCells: heightCells ?? current.placement.heightCells,
        ),
        content: current.content,
      ),
    );
  }

  void updateSelectedContent(BoardContentConfig content) {
    final current = selectedItem;
    if (current == null) return;
    _replaceSelected(
      BoardContentItem(
        id: current.id,
        placement: current.placement,
        content: content,
      ),
    );
  }

  void setShowTitle(bool value) {
    _showTitle = value;
    _markDirty();
    notifyListeners();
  }

  void setTitleOverride(String? value) {
    _titleOverride = (value == null || value.trim().isEmpty) ? null : value;
    _markDirty();
    notifyListeners();
  }
}

/// Catalog of every [LayoutTemplate] the editor's layout selector can offer,
/// independent of any fixture — the same generic list N1 already defines.
List<LayoutTemplate> availableLayoutTemplates() =>
    initialLayoutTemplateCatalog.templates;

/// The single collection the LayoutTemplate dropdown AND its onChanged
/// callback must both resolve from (N6.2 §2/R2): the generic catalog, plus
/// [current] appended only when it is not already one of those entries (a
/// fixture like Arco using `grid_6x7`, or a preset using a dynamic geometry
/// like `grid_8x4`). Selecting the appended entry is a valid no-op — see
/// [BoardEditorController.setLayoutTemplate].
List<LayoutTemplate> effectiveLayoutTemplates(LayoutTemplate current) {
  final templates = availableLayoutTemplates();
  if (templates.any((t) => t.id == current.id)) return templates;
  return [...templates, current];
}
