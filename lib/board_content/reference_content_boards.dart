import '../device_board_layouts/reference_board_layouts.dart';
import '../device_metric_catalogs/device_metric_catalog.dart';
import '../device_metric_catalogs/reference_metric_catalogs.dart';
import '../layout_templates/grid_placement.dart';
import '../layout_templates/layout_template.dart';
import 'board_content_config.dart';
import 'board_content_layout.dart';

class ReferenceContentBoard {
  const ReferenceContentBoard(
    this.name,
    this.board,
    this.template,
    this.catalog,
  );
  final String name;
  final BoardContentLayout board;
  final LayoutTemplate template;
  final DeviceMetricCatalog catalog;
}

BoardContentItem _item(
  String id,
  int x,
  int y,
  int w,
  int h,
  BoardContentConfig content,
) => BoardContentItem(
  id: id,
  placement: GridPlacement(x: x, y: y, widthCells: w, heightCells: h),
  content: content,
);
final _fields = <BoardDataField>[
  BoardDataField(
    key: 'timestamp',
    label: 'Fecha / hora',
    format: BoardFieldFormat.dateTime,
  ),
  BoardDataField(key: 'plate', label: 'Patente'),
  BoardDataField(key: 'vehicleType', label: 'Tipo'),
  BoardDataField(key: 'operator', label: 'Empresa / conductor'),
  BoardDataField(
    key: 'state',
    label: 'Estado',
    format: BoardFieldFormat.status,
  ),
];

/// Semantic references only: no asset, event feed or records are fetched.
final ReferenceContentBoard disinfectionContentExample = ReferenceContentBoard(
  'Arco conceptual',
  BoardContentLayout(
    deviceId: 'example-disinfection',
    layoutTemplateId: 'grid_6x7',
    items: [
      _item(
        'hero',
        0,
        0,
        4,
        4,
        ImageBoardContent(
          sourceType: BoardImageSourceType.deviceMediaRef,
          sourceRef: 'hero',
          fit: BoardImageFit.cover,
          altText: 'Imagen del dispositivo',
        ),
      ),
      _item(
        'disinfected',
        4,
        0,
        2,
        1,
        MetricBoardContent(metricKey: 'vehiclesDisinfectedDaily'),
      ),
      _item(
        'vehicles',
        4,
        1,
        2,
        1,
        MetricBoardContent(metricKey: 'vehiclesTotalDaily'),
      ),
      _item(
        'level',
        4,
        2,
        2,
        1,
        MetricBoardContent(metricKey: 'disinfectantLevel'),
      ),
      _item(
        'operating-state',
        4,
        3,
        2,
        1,
        StatusBoardContent(dataSourceId: 'device.operatingState'),
      ),
      _item(
        'latest',
        0,
        4,
        6,
        1,
        LatestEventBoardContent(
          eventSourceId: 'device.latestVehicle',
          fields: _fields,
        ),
      ),
      _item(
        'records',
        0,
        5,
        6,
        2,
        DataTableBoardContent(
          dataSourceId: 'device.recentRecords',
          columns: [
            for (final field in _fields)
              BoardTableColumn(
                field: field,
                flex: field.key == 'operator' ? 2 : 1,
              ),
            BoardTableColumn(
              field: BoardDataField(key: 'product', label: 'Producto'),
            ),
            BoardTableColumn(
              field: BoardDataField(
                key: 'ppm',
                label: 'PPM',
                format: BoardFieldFormat.number,
              ),
            ),
          ],
          maxRows: 10,
        ),
      ),
    ],
  ),
  LayoutTemplate(id: 'grid_6x7', name: '6 × 7', columns: 6, rows: 7),
  referenceMetricCatalogById('disinfection_arch_v1')!,
);

final ReferenceContentBoard roomContentExample = ReferenceContentBoard(
  'Sala métrica',
  BoardContentLayout.fromLegacy(referenceBoardLayouts.first.board),
  referenceBoardLayouts.first.template,
  referenceBoardLayouts.first.catalog,
);
