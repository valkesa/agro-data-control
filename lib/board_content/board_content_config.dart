import '../cell_layout_presets/cell_layout_preset.dart'
    show
        CellFontWeight,
        CellHorizontalAlignment,
        CellSizeRole,
        CellVerticalAlignment,
        readCellEnum;
import '../device_board_layouts/board_parsing.dart';

enum BoardContentType {
  metric,
  image,
  latestEvent,
  dataTable,
  status,
  text,
  chart,
  // N6.4: free visual design without a MetricDefinition behind it (§1/§3).
  icon,
  placeholder,
}

/// A [StatusBoardContent]/[LatestEventBoardContent]/[DataTableBoardContent]
/// item is always in exactly one of these (N6.4 §14/§15) — derived from
/// which fields are actually set, never a separate persisted flag that could
/// drift out of sync with them:
/// - [unbound]: no real source, no demo value either — "coming later".
/// - [demo]: no real source, but a local preview value is set so the design
///   can be judged visually without a Device/backend.
/// - [bound]: a real semantic source ID is set — resolved exactly as before
///   N6.4, unchanged behavior/tests.
/// Going from `unbound`/`demo` to `bound` later only ever sets the source
/// ID field — it never touches placement, span or any other item state
/// (§15: "sin reconstruir el layout").
enum BoardBindingMode { unbound, demo, bound }

/// Purely presentational grouping for a [PlaceholderBoardContent] — never
/// business/severity semantics (those only exist once real data exists).
enum BoardPlaceholderStyle { neutral, info, success, warning }

enum BoardImageSourceType { asset, url, firestoreStorageRef, deviceMediaRef }

enum BoardImageFit { contain, cover, fill }

enum BoardFieldFormat { text, number, boolean, dateTime, status }

enum BoardChartType { line, bar, area }

T _enum<T extends Enum>(Object? value, List<T> values, String field) {
  for (final item in values) {
    if (item.name == value) return item;
  }
  BoardParsing.fail('invalid_content_config', 'Unsupported $field: $value');
}

void _fields(Map<String, Object?> map, Set<String> allowed) {
  for (final key in map.keys) {
    if (!allowed.contains(key)) {
      BoardParsing.fail('invalid_content_config', 'Unknown content field $key');
    }
  }
}

String _source(Object? value) {
  if (value is! String ||
      !RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_.:/-]*$').hasMatch(value)) {
    BoardParsing.fail(
      'data_source_missing',
      'Expected semantic data source ID',
    );
  }
  return value;
}

void _unique(Iterable<String> keys, String code) {
  final seen = <String>{};
  for (final key in keys) {
    if (!seen.add(key)) BoardParsing.fail(code, 'Repeated key $key');
  }
}

int _positive(Object? value, String field, {int? max}) {
  final number = BoardParsing.integer(value, field);
  if (number < 1 || (max != null && number > max)) {
    BoardParsing.fail('invalid_content_config', 'Invalid $field');
  }
  return number;
}

sealed class BoardContentConfig {
  const BoardContentConfig();
  BoardContentType get type;
  Map<String, Object?> toMap();
  static BoardContentConfig fromMap(String type, Map<String, Object?> map) =>
      switch (type) {
        'metric' => MetricBoardContent.fromMap(map),
        'image' => ImageBoardContent.fromMap(map),
        'latestEvent' => LatestEventBoardContent.fromMap(map),
        'dataTable' => DataTableBoardContent.fromMap(map),
        'status' => StatusBoardContent.fromMap(map),
        'text' => TextBoardContent.fromMap(map),
        'chart' => ChartBoardContent.fromMap(map),
        'icon' => IconBoardContent.fromMap(map),
        'placeholder' => PlaceholderBoardContent.fromMap(map),
        _ => BoardParsing.fail(
          'unsupported_content_type',
          'Unsupported board content type $type',
        ),
      };
}

class MetricBoardContent extends BoardContentConfig {
  MetricBoardContent({
    required this.metricKey,
    this.cellLayoutPresetId,
    String? labelOverride,
    String? unitOverride,
    Iterable<String> indicatorKeys = const [],
  }) : labelOverride = _optionalText(labelOverride),
       unitOverride = _optionalText(unitOverride),
       indicatorKeys = List.unmodifiable(indicatorKeys) {
    BoardParsing.string(metricKey, 'metricKey');
    if (cellLayoutPresetId != null) {
      BoardParsing.string(cellLayoutPresetId, 'cellLayoutPresetId');
    }
    for (final key in this.indicatorKeys) {
      BoardParsing.string(key, 'indicatorKey');
    }
  }
  factory MetricBoardContent.fromMap(Map<String, Object?> map) {
    _fields(map, {
      'metricKey',
      'cellLayoutPresetId',
      'indicatorKeys',
      'labelOverride',
      'unitOverride',
    });
    return MetricBoardContent(
      metricKey: BoardParsing.string(map['metricKey'], 'metricKey'),
      labelOverride: _readOverride(map['labelOverride'], 'labelOverride'),
      unitOverride: _readOverride(map['unitOverride'], 'unitOverride'),
      cellLayoutPresetId: map['cellLayoutPresetId'] == null
          ? null
          : BoardParsing.string(
              map['cellLayoutPresetId'],
              'cellLayoutPresetId',
            ),
      indicatorKeys: BoardParsing.list(
        map['indicatorKeys'],
        'indicatorKeys',
      ).map((v) => BoardParsing.string(v, 'indicatorKey')),
    );
  }
  static String? _optionalText(String? value) =>
      value == null || value.trim().isEmpty ? null : value;

  static String? _readOverride(Object? value, String field) {
    if (value == null) return null;
    if (value is! String) {
      BoardParsing.fail('invalid_content_config', '$field must be text');
    }
    return _optionalText(value);
  }

  /// Presentation belongs to the item, never to the shared metric or cell design.
  final String? labelOverride;
  final String? unitOverride;
  MetricBoardContent copyWith({
    String? metricKey,
    String? cellLayoutPresetId,
    bool clearCellLayoutPresetId = false,
    Iterable<String>? indicatorKeys,
    String? labelOverride,
    String? unitOverride,
    bool clearLabelOverride = false,
    bool clearUnitOverride = false,
  }) => MetricBoardContent(
    metricKey: metricKey ?? this.metricKey,
    cellLayoutPresetId: clearCellLayoutPresetId
        ? null
        : cellLayoutPresetId ?? this.cellLayoutPresetId,
    indicatorKeys: indicatorKeys ?? this.indicatorKeys,
    labelOverride: clearLabelOverride
        ? null
        : labelOverride ?? this.labelOverride,
    unitOverride: clearUnitOverride ? null : unitOverride ?? this.unitOverride,
  );

  final String metricKey;
  final String? cellLayoutPresetId;
  final List<String> indicatorKeys;
  @override
  BoardContentType get type => BoardContentType.metric;
  @override
  Map<String, Object?> toMap() => {
    'metricKey': metricKey,
    'cellLayoutPresetId': cellLayoutPresetId,
    'indicatorKeys': indicatorKeys.toList(),
    if (labelOverride != null) 'labelOverride': labelOverride,
    if (unitOverride != null) 'unitOverride': unitOverride,
  };
}

class ImageBoardContent extends BoardContentConfig {
  ImageBoardContent({
    required this.sourceType,
    required this.sourceRef,
    this.fit = BoardImageFit.contain,
    this.altText,
  }) {
    if (sourceType == BoardImageSourceType.url) {
      final uri = Uri.tryParse(sourceRef);
      if (uri == null ||
          !['https', 'http'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          sourceRef.contains(RegExp(r'\s'))) {
        BoardParsing.fail(
          'invalid_content_config',
          'Expected http(s) image URL without credentials',
        );
      }
    } else {
      if (!RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_./-]*$').hasMatch(sourceRef) ||
          sourceRef.split('/').contains('..')) {
        BoardParsing.fail('invalid_content_config', 'Invalid image reference');
      }
    }
    if (altText != null) BoardParsing.string(altText, 'altText');
  }
  factory ImageBoardContent.fromMap(Map<String, Object?> map) {
    _fields(map, {'sourceType', 'sourceRef', 'fit', 'altText'});
    return ImageBoardContent(
      sourceType: _enum(
        map['sourceType'],
        BoardImageSourceType.values,
        'sourceType',
      ),
      sourceRef: BoardParsing.string(map['sourceRef'], 'sourceRef'),
      fit: _enum(map['fit'], BoardImageFit.values, 'fit'),
      altText: map['altText'] == null
          ? null
          : BoardParsing.string(map['altText'], 'altText'),
    );
  }
  final BoardImageSourceType sourceType;
  final String sourceRef;
  final BoardImageFit fit;
  final String? altText;
  @override
  BoardContentType get type => BoardContentType.image;
  @override
  Map<String, Object?> toMap() => {
    'sourceType': sourceType.name,
    'sourceRef': sourceRef,
    'fit': fit.name,
    'altText': altText,
  };
}

class BoardDataField {
  BoardDataField({
    required this.key,
    required this.label,
    this.format = BoardFieldFormat.text,
    this.icon,
  }) {
    _source(key);
    BoardParsing.string(label, 'label');
    if (icon != null) BoardParsing.string(icon, 'icon');
  }
  factory BoardDataField.fromMap(Map<String, Object?> map) {
    _fields(map, {'key', 'label', 'format', 'icon'});
    return BoardDataField(
      key: BoardParsing.string(map['key'], 'key'),
      label: BoardParsing.string(map['label'], 'label'),
      format: _enum(map['format'], BoardFieldFormat.values, 'format'),
      icon: map['icon'] == null
          ? null
          : BoardParsing.string(map['icon'], 'icon'),
    );
  }
  final String key;
  final String label;
  final BoardFieldFormat format;
  final String? icon;
  Map<String, Object?> toMap() => {
    'key': key,
    'label': label,
    'format': format.name,
    'icon': icon,
  };
}

class LatestEventBoardContent extends BoardContentConfig {
  LatestEventBoardContent({
    this.eventSourceId,
    required Iterable<BoardDataField> fields,
    Map<String, String>? demoValues,
  }) : fields = List.unmodifiable(fields),
       demoValues = demoValues == null ? null : Map.unmodifiable(demoValues) {
    if (eventSourceId != null) _source(eventSourceId!);
    if (this.fields.isEmpty) {
      BoardParsing.fail(
        'invalid_content_config',
        'Event needs at least one field',
      );
    }
    _unique(this.fields.map((f) => f.key), 'duplicate_field_key');
  }
  factory LatestEventBoardContent.fromMap(Map<String, Object?> map) {
    _fields(map, {'eventSourceId', 'fields', 'demoValues'});
    return LatestEventBoardContent(
      eventSourceId: map['eventSourceId'] == null
          ? null
          : _source(map['eventSourceId']),
      fields: BoardParsing.list(
        map['fields'],
        'fields',
      ).map((f) => BoardDataField.fromMap(BoardParsing.map(f, 'field'))),
      demoValues: map['demoValues'] == null
          ? null
          : BoardParsing.map(
              map['demoValues'],
              'demoValues',
            ).map((k, v) => MapEntry(k, v.toString())),
    );
  }

  /// N6.4 §14/§15: null means unbound — [fields] still describes the shape
  /// (labels/columns) the eventual real event will fill. [demoValues], keyed
  /// by field key, is local preview text only (§11) — never real data.
  final String? eventSourceId;
  final List<BoardDataField> fields;
  final Map<String, String>? demoValues;
  BoardBindingMode get bindingMode => eventSourceId != null
      ? BoardBindingMode.bound
      : demoValues != null
      ? BoardBindingMode.demo
      : BoardBindingMode.unbound;
  @override
  BoardContentType get type => BoardContentType.latestEvent;
  @override
  Map<String, Object?> toMap() => {
    'eventSourceId': eventSourceId,
    'fields': fields.map((f) => f.toMap()).toList(),
    'demoValues': demoValues,
  };
}

class BoardTableColumn {
  BoardTableColumn({required this.field, this.flex = 1}) {
    _positive(flex, 'flex', max: 100);
  }
  factory BoardTableColumn.fromMap(Map<String, Object?> map) {
    _fields(map, {'field', 'flex'});
    return BoardTableColumn(
      field: BoardDataField.fromMap(BoardParsing.map(map['field'], 'field')),
      flex: _positive(map['flex'], 'flex', max: 100),
    );
  }
  final BoardDataField field;
  final int flex;
  Map<String, Object?> toMap() => {'field': field.toMap(), 'flex': flex};
}

class DataTableBoardContent extends BoardContentConfig {
  DataTableBoardContent({
    this.dataSourceId,
    required Iterable<BoardTableColumn> columns,
    this.maxRows = 20,
    this.showHeader = true,
    Iterable<Map<String, String>>? demoRows,
  }) : columns = List.unmodifiable(columns),
       demoRows = demoRows == null
           ? null
           : List.unmodifiable(demoRows.map(Map<String, String>.unmodifiable)) {
    if (dataSourceId != null) _source(dataSourceId!);
    _positive(maxRows, 'maxRows', max: 1000);
    if (this.columns.isEmpty) {
      BoardParsing.fail('invalid_content_config', 'Table needs columns');
    }
    _unique(this.columns.map((c) => c.field.key), 'duplicate_column_key');
  }
  factory DataTableBoardContent.fromMap(Map<String, Object?> map) {
    _fields(map, {
      'dataSourceId',
      'columns',
      'maxRows',
      'showHeader',
      'demoRows',
    });
    return DataTableBoardContent(
      dataSourceId: map['dataSourceId'] == null
          ? null
          : _source(map['dataSourceId']),
      columns: BoardParsing.list(
        map['columns'],
        'columns',
      ).map((c) => BoardTableColumn.fromMap(BoardParsing.map(c, 'column'))),
      maxRows: _positive(map['maxRows'], 'maxRows', max: 1000),
      showHeader: BoardParsing.boolean(map['showHeader'], 'showHeader'),
      demoRows: map['demoRows'] == null
          ? null
          : BoardParsing.list(map['demoRows'], 'demoRows').map(
              (r) => BoardParsing.map(
                r,
                'demoRow',
              ).map((k, v) => MapEntry(k, v.toString())),
            ),
    );
  }

  /// N6.4 §14/§15: null means unbound. [demoRows], each row a field-key →
  /// display-text map, is local preview data only (§11) — never real data.
  final String? dataSourceId;
  final List<BoardTableColumn> columns;
  final int maxRows;
  final bool showHeader;
  final List<Map<String, String>>? demoRows;
  BoardBindingMode get bindingMode => dataSourceId != null
      ? BoardBindingMode.bound
      : demoRows != null
      ? BoardBindingMode.demo
      : BoardBindingMode.unbound;
  @override
  BoardContentType get type => BoardContentType.dataTable;
  @override
  Map<String, Object?> toMap() => {
    'dataSourceId': dataSourceId,
    'columns': columns.map((c) => c.toMap()).toList(),
    'maxRows': maxRows,
    'showHeader': showHeader,
    'demoRows': demoRows,
  };
}

class StatusBoardContent extends BoardContentConfig {
  StatusBoardContent({this.dataSourceId, this.demoLabel}) {
    if (dataSourceId != null) _source(dataSourceId!);
    if (demoLabel != null) BoardParsing.string(demoLabel, 'demoLabel');
  }
  factory StatusBoardContent.fromMap(Map<String, Object?> map) {
    _fields(map, {'dataSourceId', 'demoLabel'});
    return StatusBoardContent(
      dataSourceId: map['dataSourceId'] == null
          ? null
          : _source(map['dataSourceId']),
      demoLabel: map['demoLabel'] == null
          ? null
          : BoardParsing.string(map['demoLabel'], 'demoLabel'),
    );
  }

  /// N6.4 §14/§15: null means no real source is bound yet — never a
  /// fabricated placeholder ID. [demoLabel] (e.g. "Operativo") lets the
  /// design be previewed anyway; it is never written to any catalog.
  final String? dataSourceId;
  final String? demoLabel;
  BoardBindingMode get bindingMode => dataSourceId != null
      ? BoardBindingMode.bound
      : demoLabel != null
      ? BoardBindingMode.demo
      : BoardBindingMode.unbound;
  @override
  BoardContentType get type => BoardContentType.status;
  @override
  Map<String, Object?> toMap() => {
    'dataSourceId': dataSourceId,
    'demoLabel': demoLabel,
  };
}

class TextBoardContent extends BoardContentConfig {
  TextBoardContent({
    required this.text,
    this.horizontalAlignment = CellHorizontalAlignment.start,
    this.sizeRole = CellSizeRole.md,
    this.fontWeight = CellFontWeight.normal,
    this.maxLines = 3,
  }) {
    BoardParsing.string(text, 'text');
    if (RegExp(r'<[^>]*>').hasMatch(text)) {
      BoardParsing.fail(
        'invalid_content_config',
        'Only plain text is supported',
      );
    }
    if (maxLines < 1) {
      BoardParsing.fail('invalid_content_config', 'maxLines must be positive');
    }
  }
  factory TextBoardContent.fromMap(Map<String, Object?> map) {
    _fields(map, {
      'text',
      'horizontalAlignment',
      'sizeRole',
      'fontWeight',
      'maxLines',
    });
    return TextBoardContent(
      text: BoardParsing.string(map['text'], 'text'),
      horizontalAlignment: map['horizontalAlignment'] == null
          ? CellHorizontalAlignment.start
          : readCellEnum(
              map['horizontalAlignment'],
              CellHorizontalAlignment.values,
              'horizontalAlignment',
            ),
      sizeRole: map['sizeRole'] == null
          ? CellSizeRole.md
          : readCellEnum(map['sizeRole'], CellSizeRole.values, 'sizeRole'),
      fontWeight: map['fontWeight'] == null
          ? CellFontWeight.normal
          : readCellEnum(
              map['fontWeight'],
              CellFontWeight.values,
              'fontWeight',
            ),
      maxLines: map['maxLines'] == null
          ? 3
          : BoardParsing.integer(map['maxLines'], 'maxLines'),
    );
  }

  /// N6.4 §9: `text` is a first-class design element, not only a demo stub —
  /// same styling knobs a cell's label/value element already has.
  final String text;
  final CellHorizontalAlignment horizontalAlignment;
  final CellSizeRole sizeRole;
  final CellFontWeight fontWeight;
  final int maxLines;
  @override
  BoardContentType get type => BoardContentType.text;
  @override
  Map<String, Object?> toMap() => {
    'text': text,
    'horizontalAlignment': horizontalAlignment.name,
    'sizeRole': sizeRole.name,
    'fontWeight': fontWeight.name,
    'maxLines': maxLines,
  };
}

/// N6.4 §4: a single icon as an independent board item — no metric, no
/// data, just a semantic glyph occupying its own [GridPlacement].
class IconBoardContent extends BoardContentConfig {
  IconBoardContent({
    required this.iconKey,
    this.label,
    this.sizeRole = CellSizeRole.lg,
    this.horizontalAlignment = CellHorizontalAlignment.center,
    this.verticalAlignment = CellVerticalAlignment.center,
  }) {
    BoardParsing.string(iconKey, 'iconKey');
    if (label != null) BoardParsing.string(label, 'label');
  }
  factory IconBoardContent.fromMap(Map<String, Object?> map) {
    _fields(map, {
      'iconKey',
      'label',
      'sizeRole',
      'horizontalAlignment',
      'verticalAlignment',
    });
    return IconBoardContent(
      iconKey: BoardParsing.string(map['iconKey'], 'iconKey'),
      label: map['label'] == null
          ? null
          : BoardParsing.string(map['label'], 'label'),
      sizeRole: map['sizeRole'] == null
          ? CellSizeRole.lg
          : readCellEnum(map['sizeRole'], CellSizeRole.values, 'sizeRole'),
      horizontalAlignment: map['horizontalAlignment'] == null
          ? CellHorizontalAlignment.center
          : readCellEnum(
              map['horizontalAlignment'],
              CellHorizontalAlignment.values,
              'horizontalAlignment',
            ),
      verticalAlignment: map['verticalAlignment'] == null
          ? CellVerticalAlignment.center
          : readCellEnum(
              map['verticalAlignment'],
              CellVerticalAlignment.values,
              'verticalAlignment',
            ),
    );
  }
  final String iconKey;
  final String? label;
  final CellSizeRole sizeRole;
  final CellHorizontalAlignment horizontalAlignment;
  final CellVerticalAlignment verticalAlignment;
  @override
  BoardContentType get type => BoardContentType.icon;
  @override
  Map<String, Object?> toMap() => {
    'iconKey': iconKey,
    'label': label,
    'sizeRole': sizeRole.name,
    'horizontalAlignment': horizontalAlignment.name,
    'verticalAlignment': verticalAlignment.name,
  };
}

/// N6.4 §5/§6: "acá habrá una métrica o dato real más adelante" — a design
/// stub completely separate from [MetricBoardContent]/`MetricDefinition`.
/// Never contaminates `DeviceMetricCatalog`; [mockValue] is local preview
/// text only, never persisted as real data (§11).
///
/// §17 explicitly reuses [CellLayoutPreset] "cuando sea razonable" — this
/// one is the documented exception. `CellLayoutCanvas`'s resolved-content
/// path (the renderer both the production board and the cell-design editor
/// share) derives a `value`/`unit` element's text by calling
/// `TemplateDataResolver.resolveMetric` against a real, non-null
/// `MetricDefinition` — it never reads free text for those two element
/// types. Giving a placeholder a `cellLayoutPresetId` would therefore
/// require either fabricating a `MetricDefinition` to feed it (exactly what
/// §6 forbids) or changing that shared renderer's contract for every metric
/// item too — a materially larger, riskier change than this stage's scope.
/// A placeholder instead gets its own small, fixed, purpose-built layout
/// (see `PlaceholderBoardRenderer`) — genuinely simpler than a second
/// composition *engine*, and never diverges from `CellLayoutPreset`'s own
/// geometry model since it does not attempt one at all.
class PlaceholderBoardContent extends BoardContentConfig {
  PlaceholderBoardContent({
    required this.label,
    this.mockValue,
    this.unit,
    this.iconKey,
    this.style = BoardPlaceholderStyle.neutral,
  }) {
    BoardParsing.string(label, 'label');
    if (mockValue != null) BoardParsing.string(mockValue, 'mockValue');
    if (unit != null) BoardParsing.string(unit, 'unit');
    if (iconKey != null) BoardParsing.string(iconKey, 'iconKey');
  }
  factory PlaceholderBoardContent.fromMap(Map<String, Object?> map) {
    _fields(map, {'label', 'mockValue', 'unit', 'iconKey', 'style'});
    return PlaceholderBoardContent(
      label: BoardParsing.string(map['label'], 'label'),
      mockValue: map['mockValue'] == null
          ? null
          : BoardParsing.string(map['mockValue'], 'mockValue'),
      unit: map['unit'] == null
          ? null
          : BoardParsing.string(map['unit'], 'unit'),
      iconKey: map['iconKey'] == null
          ? null
          : BoardParsing.string(map['iconKey'], 'iconKey'),
      style: map['style'] == null
          ? BoardPlaceholderStyle.neutral
          : _enum(map['style'], BoardPlaceholderStyle.values, 'style'),
    );
  }
  final String label;
  final String? mockValue;
  final String? unit;
  final String? iconKey;
  final BoardPlaceholderStyle style;
  @override
  BoardContentType get type => BoardContentType.placeholder;
  @override
  Map<String, Object?> toMap() => {
    'label': label,
    'mockValue': mockValue,
    'unit': unit,
    'iconKey': iconKey,
    'style': style.name,
  };
}

class BoardChartSeries {
  BoardChartSeries({required this.key, required this.label}) {
    _source(key);
    BoardParsing.string(label, 'label');
  }
  factory BoardChartSeries.fromMap(Map<String, Object?> map) {
    _fields(map, {'key', 'label'});
    return BoardChartSeries(
      key: BoardParsing.string(map['key'], 'key'),
      label: BoardParsing.string(map['label'], 'label'),
    );
  }
  final String key;
  final String label;
  Map<String, Object?> toMap() => {'key': key, 'label': label};
}

class ChartBoardContent extends BoardContentConfig {
  ChartBoardContent({
    required this.dataSourceId,
    required this.chartType,
    required Iterable<BoardChartSeries> series,
  }) : series = List.unmodifiable(series) {
    _source(dataSourceId);
    if (this.series.isEmpty) {
      BoardParsing.fail('invalid_content_config', 'Chart needs series');
    }
    _unique(this.series.map((s) => s.key), 'duplicate_series_key');
  }
  factory ChartBoardContent.fromMap(Map<String, Object?> map) {
    _fields(map, {'dataSourceId', 'chartType', 'series'});
    return ChartBoardContent(
      dataSourceId: _source(map['dataSourceId']),
      chartType: _enum(map['chartType'], BoardChartType.values, 'chartType'),
      series: BoardParsing.list(
        map['series'],
        'series',
      ).map((s) => BoardChartSeries.fromMap(BoardParsing.map(s, 'series'))),
    );
  }
  final String dataSourceId;
  final BoardChartType chartType;
  final List<BoardChartSeries> series;
  @override
  BoardContentType get type => BoardContentType.chart;
  @override
  Map<String, Object?> toMap() => {
    'dataSourceId': dataSourceId,
    'chartType': chartType.name,
    'series': series.map((s) => s.toMap()).toList(),
  };
}
