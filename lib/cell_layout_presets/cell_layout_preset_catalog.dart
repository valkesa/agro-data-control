import 'package:flutter/foundation.dart';
import 'cell_layout_catalog.dart';
import 'cell_layout_preset.dart';

/// Single in-memory instance shared by the Board Editor and the N6.3 cell
/// layout editor for the lifetime of the app session — no Firestore yet
/// (N6.3 §4/§28).
final CellLayoutPresetCatalog sharedCellLayoutPresetCatalog =
    CellLayoutPresetCatalog();

/// Local/in-memory catalog of [CellLayoutPreset]s (N6.3 §4), seeded from the
/// same 7 presets [initialCellLayoutCatalog] already ships. A
/// [ChangeNotifier] so any editor/picker bound to it reacts to
/// create/duplicate/rename/update/delete without a separate stream.
///
/// [CellLayoutPreset] itself has no `description` field (N4's model, never
/// touched by N6.3) — descriptions are tracked here, in the catalog
/// wrapper, keyed by preset id, rather than adding a field to the audited
/// domain model.
class CellLayoutPresetCatalog extends ChangeNotifier {
  CellLayoutPresetCatalog({List<CellLayoutPreset>? initial})
    : _presets = List.of(initial ?? initialCellLayoutCatalog.presets);

  List<CellLayoutPreset> _presets;
  final Map<String, String> _descriptions = {};
  int _nextSeq = 0;

  List<CellLayoutPreset> get presets => List.unmodifiable(_presets);

  void replaceAll(Iterable<CellLayoutPreset> presets) {
    _presets = List.of(presets);
    _descriptions.removeWhere((id, _) => !_presets.any((p) => p.id == id));
    notifyListeners();
  }

  CellLayoutPreset? byId(String id) {
    for (final preset in _presets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  String descriptionOf(String id) => _descriptions[id] ?? '';

  /// Every enabled preset whose span matches — what a "Diseño de celda"
  /// picker for an item of this span should offer.
  List<CellLayoutPreset> availableForSpan(int width, int height) => _presets
      .where(
        (p) => p.enabled && p.widthCells == width && p.heightCells == height,
      )
      .toList();

  /// True for the 7 ids `initialCellLayoutCatalog` ships with — presets any
  /// other Board/BoardPreset in this session may already be referencing by
  /// id (N6.3 §3: "no modificar presets globales accidentalmente").
  bool isSeedGlobal(String id) => initialCellLayoutCatalog.byId(id) != null;

  String _freshId(String base) {
    final used = _presets.map((p) => p.id).toSet();
    var candidate = '$base-${_nextSeq++}';
    while (used.contains(candidate)) {
      candidate = '$base-${_nextSeq++}';
    }
    return candidate;
  }

  /// Creates a new preset "desde default" (N6.3 §22): same composition
  /// [initialCellLayoutCatalog] itself is built from, for the given span.
  CellLayoutPreset create({
    required String name,
    required int width,
    required int height,
    bool icon = false,
    String description = '',
  }) {
    final preset = CellLayoutPreset(
      id: _freshId('cell-new'),
      name: name,
      widthCells: width,
      heightCells: height,
      elements: buildDefaultCellLayoutElements(width, height, icon: icon),
    );
    _presets = [..._presets, preset];
    if (description.isNotEmpty) _descriptions[preset.id] = description;
    notifyListeners();
    return preset;
  }

  /// Structurally-independent copy under a new id (N6.3 §3/§23): elements
  /// are already an unmodifiable *copy* built by [CellLayoutPreset]'s own
  /// constructor, so no later edit to either preset can reach the other's
  /// element list.
  CellLayoutPreset duplicate(String id, {String? name}) {
    final original = byId(id);
    if (original == null) {
      throw ArgumentError('Unknown CellLayoutPreset id "$id"');
    }
    final copy = CellLayoutPreset(
      id: _freshId('${original.id}-copy'),
      name: name ?? '${original.name} (copia)',
      widthCells: original.widthCells,
      heightCells: original.heightCells,
      enabled: true,
      elements: original.elements,
    );
    _presets = [..._presets, copy];
    final description = _descriptions[original.id];
    if (description != null) _descriptions[copy.id] = description;
    notifyListeners();
    return copy;
  }

  void rename(String id, {String? name, String? description}) {
    if (description != null) _descriptions[id] = description;
    _replace(
      id,
      (preset) => CellLayoutPreset(
        id: preset.id,
        name: name ?? preset.name,
        widthCells: preset.widthCells,
        heightCells: preset.heightCells,
        presetVersion: preset.presetVersion,
        enabled: preset.enabled,
        elements: preset.elements,
        createdAt: preset.createdAt,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Replaces the composition (elements/enabled) of an existing preset —
  /// the visual editor's "save" step. Bumps `presetVersion`.
  void update(
    String id, {
    required List<CellLayoutElement> elements,
    bool? enabled,
  }) {
    _replace(
      id,
      (preset) => CellLayoutPreset(
        id: preset.id,
        name: preset.name,
        widthCells: preset.widthCells,
        heightCells: preset.heightCells,
        presetVersion: preset.presetVersion + 1,
        enabled: enabled ?? preset.enabled,
        elements: elements,
        createdAt: preset.createdAt,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Blocked if [isReferenced] — computed by the caller, since this catalog
  /// deliberately does not know about `BoardPreset`/Board items (N6.3 §23).
  ({bool ok, String? reason}) delete(
    String id, {
    required bool Function(String presetId) isReferenced,
  }) {
    if (byId(id) == null) return (ok: false, reason: 'No existe');
    if (isReferenced(id)) {
      return (ok: false, reason: 'Está referenciado por un Preset de tablero');
    }
    _presets = _presets.where((p) => p.id != id).toList();
    _descriptions.remove(id);
    notifyListeners();
    return (ok: true, reason: null);
  }

  void _replace(
    String id,
    CellLayoutPreset Function(CellLayoutPreset current) update,
  ) {
    final index = _presets.indexWhere((p) => p.id == id);
    if (index == -1) return;
    final next = [..._presets];
    next[index] = update(next[index]);
    _presets = next;
    notifyListeners();
  }
}
