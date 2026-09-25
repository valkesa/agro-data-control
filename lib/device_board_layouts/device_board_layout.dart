import '../layout_templates/grid_placement.dart';
import '../layout_templates/layout_template.dart';
import 'board_parsing.dart';

class DeviceBoardLayoutItem {
  DeviceBoardLayoutItem({
    required this.id,
    required this.metricKey,
    required this.placement,
    this.cellLayoutPresetId,
    Iterable<String> indicatorKeys = const [],
  }) : indicatorKeys = List.unmodifiable(indicatorKeys) {
    BoardParsing.string(id, 'id');
    BoardParsing.string(metricKey, 'metricKey');
    if (cellLayoutPresetId != null) {
      BoardParsing.string(cellLayoutPresetId, 'cellLayoutPresetId');
    }
    for (final key in this.indicatorKeys) {
      BoardParsing.string(key, 'indicatorKey');
    }
  }
  factory DeviceBoardLayoutItem.fromMap(Map<String, Object?> map) {
    BoardParsing.fields(map, {
      'id',
      'metricKey',
      'placement',
      'cellLayoutPresetId',
      'indicatorKeys',
    });
    final placement = BoardParsing.map(map['placement'], 'placement');
    BoardParsing.fields(placement, {'x', 'y', 'widthCells', 'heightCells'});
    return DeviceBoardLayoutItem(
      id: BoardParsing.string(map['id'], 'id'),
      metricKey: BoardParsing.string(map['metricKey'], 'metricKey'),
      placement: GridPlacement(
        x: BoardParsing.integer(placement['x'], 'x'),
        y: BoardParsing.integer(placement['y'], 'y'),
        widthCells: BoardParsing.integer(placement['widthCells'], 'widthCells'),
        heightCells: BoardParsing.integer(
          placement['heightCells'],
          'heightCells',
        ),
      ),
      cellLayoutPresetId: map['cellLayoutPresetId'] == null
          ? null
          : BoardParsing.string(
              map['cellLayoutPresetId'],
              'cellLayoutPresetId',
            ),
      indicatorKeys: BoardParsing.list(
        map['indicatorKeys'],
        'indicatorKeys',
      ).map((key) => BoardParsing.string(key, 'indicatorKey')),
    );
  }
  final String id;
  final String metricKey;
  final GridPlacement placement;
  final String? cellLayoutPresetId;
  final List<String> indicatorKeys;

  int internalColumns(LayoutTemplate template) =>
      placement.internalColumns(template);
  int internalRows(LayoutTemplate template) => placement.internalRows(template);

  Map<String, Object?> toMap() => {
    'id': id,
    'metricKey': metricKey,
    'placement': {
      'x': placement.x,
      'y': placement.y,
      'widthCells': placement.widthCells,
      'heightCells': placement.heightCells,
    },
    'cellLayoutPresetId': cellLayoutPresetId,
    'indicatorKeys': indicatorKeys.toList(),
  };
}

/// A structurally valid configuration may become semantically invalid when its
/// catalog changes. Always run DeviceBoardLayoutValidator before consumption;
/// decoding never repairs, drops or rearranges items.
class DeviceBoardLayout {
  DeviceBoardLayout({
    required this.deviceId,
    required this.layoutTemplateId,
    this.showTitle = true,
    this.titleOverride,
    this.schemaVersion = supportedSchemaVersion,
    this.layoutVersion = 1,
    required Iterable<DeviceBoardLayoutItem> items,
    this.createdAt,
    this.updatedAt,
    this.capabilityProfileId,
    this.sourceBoardPresetId,
    this.sourceBoardPresetVersion,
  }) : items = List.unmodifiable(items) {
    BoardParsing.string(deviceId, 'deviceId');
    BoardParsing.string(layoutTemplateId, 'layoutTemplateId');
    if (schemaVersion != supportedSchemaVersion) {
      BoardParsing.fail(
        'unsupported_schema_version',
        'Unsupported board schema $schemaVersion',
      );
    }
    if (layoutVersion < 1) {
      BoardParsing.fail(
        'invalid_layout_version',
        'layoutVersion must be positive',
      );
    }
    if (titleOverride != null && titleOverride!.trim().isEmpty) {
      BoardParsing.fail(
        'invalid_title_override',
        'titleOverride must be non-empty or null',
      );
    }
  }
  static const supportedSchemaVersion = 1;
  factory DeviceBoardLayout.fromMap(Map<String, Object?> map) {
    BoardParsing.fields(map, {
      'deviceId',
      'layoutTemplateId',
      'showTitle',
      'titleOverride',
      'schemaVersion',
      'layoutVersion',
      'items',
      'createdAt',
      'updatedAt',
      'capabilityProfileId',
      'sourceBoardPresetId',
      'sourceBoardPresetVersion',
    });
    return DeviceBoardLayout(
      deviceId: BoardParsing.string(map['deviceId'], 'deviceId'),
      layoutTemplateId: BoardParsing.string(
        map['layoutTemplateId'],
        'layoutTemplateId',
      ),
      showTitle: BoardParsing.boolean(map['showTitle'], 'showTitle'),
      titleOverride: _readTitle(map['titleOverride']),
      schemaVersion: BoardParsing.integer(
        map['schemaVersion'],
        'schemaVersion',
      ),
      layoutVersion: BoardParsing.integer(
        map['layoutVersion'],
        'layoutVersion',
      ),
      items: BoardParsing.list(map['items'], 'items').map(
        (item) => DeviceBoardLayoutItem.fromMap(BoardParsing.map(item, 'item')),
      ),
      createdAt: BoardParsing.date(map['createdAt'], 'createdAt'),
      updatedAt: BoardParsing.date(map['updatedAt'], 'updatedAt'),
      capabilityProfileId: map['capabilityProfileId'] as String?,
      sourceBoardPresetId: map['sourceBoardPresetId'] as String?,
      sourceBoardPresetVersion: map['sourceBoardPresetVersion'] as int?,
    );
  }
  final String deviceId;
  final String layoutTemplateId;
  final bool showTitle;
  final String? titleOverride;
  final int schemaVersion;
  final int layoutVersion;
  final List<DeviceBoardLayoutItem> items;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// N7.1 §0/§3 — which [DeviceCapabilityProfile] (by id) this Device is
  /// currently assigned, independent of [sourceBoardPresetId]: a Device
  /// keeps its own profile assignment even after the [BoardPreset] it was
  /// originally applied from is edited or deleted.
  final String? capabilityProfileId;

  /// N7.1 §0/§6/§9 — optional trazability only, never a functional
  /// dependency: which [BoardPreset] (and which of its [BoardPreset.
  /// presetVersion] snapshots) this layout's [items] were deep-copied from
  /// when last applied/reset. Editing or deleting that preset never
  /// touches this layout — see [DeviceBoardConfigRepository.applyPreset].
  final String? sourceBoardPresetId;
  final int? sourceBoardPresetVersion;

  /// The current name is supplied at use time and is never persisted here.
  String? resolveTitle(String deviceName) =>
      showTitle ? titleOverride ?? deviceName : null;
  Map<String, Object?> toMap() => {
    'deviceId': deviceId,
    'layoutTemplateId': layoutTemplateId,
    'showTitle': showTitle,
    'titleOverride': titleOverride,
    'schemaVersion': schemaVersion,
    'layoutVersion': layoutVersion,
    'items': items.map((item) => item.toMap()).toList(),
    'createdAt': createdAt?.toUtc().toIso8601String(),
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
    'capabilityProfileId': capabilityProfileId,
    'sourceBoardPresetId': sourceBoardPresetId,
    'sourceBoardPresetVersion': sourceBoardPresetVersion,
  };
}

String? _readTitle(Object? value) {
  if (value == null || value is String) return value as String?;
  BoardParsing.fail(
    'invalid_title_override',
    'titleOverride must be a string or null',
  );
}
