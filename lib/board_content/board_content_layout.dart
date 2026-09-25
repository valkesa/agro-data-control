import '../device_board_layouts/board_parsing.dart';
import '../device_board_layouts/device_board_layout.dart';
import '../layout_templates/grid_placement.dart';
import 'board_content_config.dart';

class BoardContentItem {
  BoardContentItem({
    required this.id,
    required this.placement,
    required this.content,
  }) {
    BoardParsing.string(id, 'id');
  }
  factory BoardContentItem.fromMap(Map<String, Object?> map) {
    BoardParsing.fields(map, {'id', 'type', 'placement', 'content'});
    final p = BoardParsing.map(map['placement'], 'placement');
    BoardParsing.fields(p, {'x', 'y', 'widthCells', 'heightCells'});
    return BoardContentItem(
      id: BoardParsing.string(map['id'], 'id'),
      placement: GridPlacement(
        x: BoardParsing.integer(p['x'], 'x'),
        y: BoardParsing.integer(p['y'], 'y'),
        widthCells: BoardParsing.integer(p['widthCells'], 'widthCells'),
        heightCells: BoardParsing.integer(p['heightCells'], 'heightCells'),
      ),
      content: BoardContentConfig.fromMap(
        BoardParsing.string(map['type'], 'type'),
        BoardParsing.map(map['content'], 'content'),
      ),
    );
  }
  factory BoardContentItem.fromLegacy(DeviceBoardLayoutItem item) =>
      BoardContentItem(
        id: item.id,
        placement: item.placement,
        content: MetricBoardContent(
          metricKey: item.metricKey,
          cellLayoutPresetId: item.cellLayoutPresetId,
          indicatorKeys: item.indicatorKeys,
        ),
      );
  final String id;
  final GridPlacement placement;
  final BoardContentConfig content;
  BoardContentType get type => content.type;
  DeviceBoardLayoutItem toMetricItem() {
    final config = content;
    if (config is! MetricBoardContent) {
      BoardParsing.fail(
        'non_metric_content',
        'Only metric content can convert to N3',
      );
    }
    return DeviceBoardLayoutItem(
      id: id,
      metricKey: config.metricKey,
      placement: placement,
      cellLayoutPresetId: config.cellLayoutPresetId,
      indicatorKeys: config.indicatorKeys,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'type': type.name,
    'placement': {
      'x': placement.x,
      'y': placement.y,
      'widthCells': placement.widthCells,
      'heightCells': placement.heightCells,
    },
    'content': content.toMap(),
  };
}

/// Schema 2 board. Shares metadata validation with N3 rather than changing its
/// public metric-only API. Explicit migration is lossless for all N3 fields.
class BoardContentLayout {
  BoardContentLayout({
    required String deviceId,
    required String layoutTemplateId,
    bool showTitle = true,
    String? titleOverride,
    int layoutVersion = 1,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? capabilityProfileId,
    String? sourceBoardPresetId,
    int? sourceBoardPresetVersion,
    required Iterable<BoardContentItem> items,
  }) : _metadata = DeviceBoardLayout(
         deviceId: deviceId,
         layoutTemplateId: layoutTemplateId,
         showTitle: showTitle,
         titleOverride: titleOverride,
         layoutVersion: layoutVersion,
         createdAt: createdAt,
         updatedAt: updatedAt,
         capabilityProfileId: capabilityProfileId,
         sourceBoardPresetId: sourceBoardPresetId,
         sourceBoardPresetVersion: sourceBoardPresetVersion,
         items: const [],
       ),
       items = List.unmodifiable(items);
  factory BoardContentLayout.fromLegacy(DeviceBoardLayout board) =>
      BoardContentLayout(
        deviceId: board.deviceId,
        layoutTemplateId: board.layoutTemplateId,
        showTitle: board.showTitle,
        titleOverride: board.titleOverride,
        layoutVersion: board.layoutVersion,
        createdAt: board.createdAt,
        updatedAt: board.updatedAt,
        capabilityProfileId: board.capabilityProfileId,
        sourceBoardPresetId: board.sourceBoardPresetId,
        sourceBoardPresetVersion: board.sourceBoardPresetVersion,
        items: board.items.map(BoardContentItem.fromLegacy),
      );
  factory BoardContentLayout.fromMap(Map<String, Object?> map) {
    final version = BoardParsing.integer(map['schemaVersion'], 'schemaVersion');
    if (version == 1) {
      return BoardContentLayout.fromLegacy(DeviceBoardLayout.fromMap(map));
    }
    if (version != 2) {
      BoardParsing.fail(
        'unsupported_schema_version',
        'Unsupported board content schema',
      );
    }
    // N3 metadata parser rejects unknown top-level fields and invalid titles/dates.
    final header = DeviceBoardLayout.fromMap({
      ...map,
      'schemaVersion': 1,
      'items': <Object?>[],
    });
    return BoardContentLayout(
      deviceId: header.deviceId,
      layoutTemplateId: header.layoutTemplateId,
      showTitle: header.showTitle,
      titleOverride: header.titleOverride,
      layoutVersion: header.layoutVersion,
      createdAt: header.createdAt,
      updatedAt: header.updatedAt,
      capabilityProfileId: header.capabilityProfileId,
      sourceBoardPresetId: header.sourceBoardPresetId,
      sourceBoardPresetVersion: header.sourceBoardPresetVersion,
      items: BoardParsing.list(
        map['items'],
        'items',
      ).map((v) => BoardContentItem.fromMap(BoardParsing.map(v, 'item'))),
    );
  }
  final DeviceBoardLayout _metadata;
  final List<BoardContentItem> items;
  int get schemaVersion => 2;
  String get deviceId => _metadata.deviceId;
  String get layoutTemplateId => _metadata.layoutTemplateId;
  bool get showTitle => _metadata.showTitle;
  String? get titleOverride => _metadata.titleOverride;
  int get layoutVersion => _metadata.layoutVersion;
  DateTime? get createdAt => _metadata.createdAt;
  DateTime? get updatedAt => _metadata.updatedAt;
  String? get capabilityProfileId => _metadata.capabilityProfileId;
  String? get sourceBoardPresetId => _metadata.sourceBoardPresetId;
  int? get sourceBoardPresetVersion => _metadata.sourceBoardPresetVersion;
  String? resolveTitle(String deviceName) => _metadata.resolveTitle(deviceName);

  /// Deliberately rejects non-metric boards; never discards content on downgrade.
  DeviceBoardLayout toLegacy() => DeviceBoardLayout(
    deviceId: deviceId,
    layoutTemplateId: layoutTemplateId,
    showTitle: showTitle,
    titleOverride: titleOverride,
    layoutVersion: layoutVersion,
    createdAt: createdAt,
    updatedAt: updatedAt,
    capabilityProfileId: capabilityProfileId,
    sourceBoardPresetId: sourceBoardPresetId,
    sourceBoardPresetVersion: sourceBoardPresetVersion,
    items: items.map((i) => i.toMetricItem()),
  );
  Map<String, Object?> toMap() => {
    ..._metadata.toMap(),
    'schemaVersion': schemaVersion,
    'items': items.map((i) => i.toMap()).toList(),
  };
}
