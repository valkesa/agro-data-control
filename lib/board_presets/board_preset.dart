import '../board_content/board_content_layout.dart';
import '../device_board_layouts/board_parsing.dart';

/// A reusable, Tenant/Site/Device-agnostic starting configuration for a
/// board (N6.2 §6). Deliberately narrower than [BoardContentLayout]: it
/// carries no `deviceId`, no live data, and its [items] are a *template*
/// list of [BoardContentItem] objects, not a validated snapshot bound to any
/// particular [DeviceMetricCatalog] — that binding only happens when a
/// preset is eventually applied to a real Device (a future stage; this
/// class intentionally never performs that application).
///
/// Editing a [BoardPreset] never mutates another instance: every mutation
/// this codebase performs on a preset goes through [copyWith], which always
/// rebuilds a fresh, structurally-independent `items` list.
class BoardPreset {
  BoardPreset({
    required this.id,
    required this.name,
    this.description = '',
    required this.layoutTemplateId,
    this.showTitleDefault = true,
    this.titleOverride,
    Iterable<BoardContentItem> items = const [],
    this.requiredMetricKeys = const [],
    this.optionalMetricKeys = const [],
    this.capabilityProfileId,
    this.schemaVersion = 1,
    this.presetVersion = 1,
    this.enabled = true,
    this.createdAt,
    this.updatedAt,
  }) : items = List.unmodifiable(items) {
    if (id.trim().isEmpty) throw ArgumentError('BoardPreset.id is required');
    if (name.trim().isEmpty) {
      throw ArgumentError('BoardPreset.name is required');
    }
    if (layoutTemplateId.trim().isEmpty) {
      throw ArgumentError('BoardPreset.layoutTemplateId is required');
    }
  }

  final String id;
  final String name;
  final String description;
  final String layoutTemplateId;
  final bool showTitleDefault;
  final String? titleOverride;
  final List<BoardContentItem> items;

  /// Metric keys a Device must expose in its [DeviceMetricCatalog] before
  /// this preset can be meaningfully applied to it (N6.2 §11). Purely
  /// declarative here — no Device exists yet to validate against.
  final List<String> requiredMetricKeys;

  /// Metric keys the preset can make use of but does not depend on.
  final List<String> optionalMetricKeys;

  /// Legacy-compatible design metadata: the profile that should be selected
  /// initially as a metric/indicator filter when this preset is opened.
  /// It is never the preset's capability contract and is never the exclusive
  /// source used to validate its content. Strict capability validation is
  /// deferred until the preset is applied to a real Device. `null` means
  /// "Todas las métricas". The wire name is retained to avoid a destructive
  /// migration of existing Firestore documents.
  final String? capabilityProfileId;

  final int schemaVersion;
  final int presetVersion;

  /// N7.1 §6/§7 — persistence lifecycle metadata, same convention as
  /// [DeviceTemplateRecord]/[LayoutTemplate]: `enabled` is a soft-disable
  /// flag (a preset is never physically required to disappear from
  /// Firestore just because it stopped being offered), `createdAt`/
  /// `updatedAt` are `null` until the preset has actually been persisted at
  /// least once (every in-memory-only N6.x call site keeps working
  /// unchanged).
  final bool enabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  BoardPreset copyWith({
    String? id,
    String? name,
    String? description,
    String? layoutTemplateId,
    bool? showTitleDefault,
    String? titleOverride,
    bool clearTitleOverride = false,
    Iterable<BoardContentItem>? items,
    List<String>? requiredMetricKeys,
    List<String>? optionalMetricKeys,
    String? capabilityProfileId,
    bool clearCapabilityProfileId = false,
    int? presetVersion,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => BoardPreset(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    layoutTemplateId: layoutTemplateId ?? this.layoutTemplateId,
    showTitleDefault: showTitleDefault ?? this.showTitleDefault,
    titleOverride: clearTitleOverride
        ? null
        : titleOverride ?? this.titleOverride,
    items: items ?? this.items,
    requiredMetricKeys: requiredMetricKeys ?? this.requiredMetricKeys,
    optionalMetricKeys: optionalMetricKeys ?? this.optionalMetricKeys,
    capabilityProfileId: clearCapabilityProfileId
        ? null
        : capabilityProfileId ?? this.capabilityProfileId,
    schemaVersion: schemaVersion,
    presetVersion: presetVersion ?? this.presetVersion,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// N7.1 §2/§7 — persistence round-trip for `boardPresets/{id}`. No
  /// runtime/device-bound data is ever included (§7 "No guardar datos
  /// runtime") — every field here is exactly what [BoardPreset]'s
  /// constructor already accepts.
  factory BoardPreset.fromMap(Map<String, Object?> map) {
    BoardParsing.fields(map, {
      'id',
      'name',
      'description',
      'layoutTemplateId',
      'showTitleDefault',
      'titleOverride',
      'items',
      'requiredMetricKeys',
      'optionalMetricKeys',
      'capabilityProfileId',
      'schemaVersion',
      'presetVersion',
      'enabled',
      'createdAt',
      'updatedAt',
    });
    return BoardPreset(
      id: BoardParsing.string(map['id'], 'id'),
      name: BoardParsing.string(map['name'], 'name'),
      description: (map['description'] as String?) ?? '',
      layoutTemplateId: BoardParsing.string(
        map['layoutTemplateId'],
        'layoutTemplateId',
      ),
      showTitleDefault: (map['showTitleDefault'] as bool?) ?? true,
      titleOverride: map['titleOverride'] as String?,
      items: BoardParsing.list(
        map['items'],
        'items',
      ).map((item) => BoardContentItem.fromMap(BoardParsing.map(item, 'item'))),
      requiredMetricKeys:
          (map['requiredMetricKeys'] as List?)?.cast<String>() ?? const [],
      optionalMetricKeys:
          (map['optionalMetricKeys'] as List?)?.cast<String>() ?? const [],
      capabilityProfileId: map['capabilityProfileId'] as String?,
      schemaVersion: (map['schemaVersion'] as int?) ?? 1,
      presetVersion: (map['presetVersion'] as int?) ?? 1,
      enabled: (map['enabled'] as bool?) ?? true,
      createdAt: BoardParsing.date(map['createdAt'], 'createdAt'),
      updatedAt: BoardParsing.date(map['updatedAt'], 'updatedAt'),
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'layoutTemplateId': layoutTemplateId,
    'showTitleDefault': showTitleDefault,
    'titleOverride': titleOverride,
    'items': items.map((item) => item.toMap()).toList(),
    'requiredMetricKeys': requiredMetricKeys,
    'optionalMetricKeys': optionalMetricKeys,
    'capabilityProfileId': capabilityProfileId,
    'schemaVersion': schemaVersion,
    'presetVersion': presetVersion,
    'enabled': enabled,
    'createdAt': createdAt?.toUtc().toIso8601String(),
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
  };
}
