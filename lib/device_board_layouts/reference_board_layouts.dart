import '../device_metric_catalogs/device_metric_catalog.dart';
import '../device_metric_catalogs/reference_metric_catalogs.dart';
import '../layout_templates/grid_placement.dart';
import '../layout_templates/layout_template.dart';
import '../layout_templates/layout_template_catalog.dart';
import 'device_board_layout.dart';

/// Local fixtures only. These device IDs are deliberately synthetic.
class ReferenceBoardLayout {
  const ReferenceBoardLayout(
    this.label,
    this.board,
    this.template,
    this.catalog,
  );
  final String label;
  final DeviceBoardLayout board;
  final LayoutTemplate template;
  final DeviceMetricCatalog catalog;
}

DeviceBoardLayoutItem _item(
  String id,
  String key,
  int x,
  int y,
  int w,
  int h, {
  List<String> indicators = const [],
}) => DeviceBoardLayoutItem(
  id: id,
  metricKey: key,
  placement: GridPlacement(x: x, y: y, widthCells: w, heightCells: h),
  indicatorKeys: indicators,
);

final List<ReferenceBoardLayout> referenceBoardLayouts = List.unmodifiable([
  ReferenceBoardLayout(
    'Sala',
    DeviceBoardLayout(
      deviceId: 'example-room',
      layoutTemplateId: 'grid_6x4',
      items: [
        _item(
          'temperature-main',
          'tempInterior',
          0,
          0,
          2,
          2,
          indicators: [
            'calefaccionEtapa1',
            'calefaccionEtapa2',
            'humidificacion',
          ],
        ),
        _item('humidity', 'humedadInterior', 2, 0, 2, 1),
        _item('dew-point', 'dewPointDelta', 4, 0, 2, 1),
        _item('outside-temperature', 'tempExterior', 2, 1, 2, 1),
        _item('outside-humidity', 'humedadExterior', 4, 1, 2, 1),
        _item('fan', 'fan', 0, 2, 2, 1),
        _item('pressure', 'presion', 2, 2, 2, 1),
        _item('room-door', 'puertaSala', 4, 2, 1, 1),
        _item('equipment-door', 'puertaMunters', 5, 2, 1, 1),
        _item('sows', 'sowCount', 0, 3, 2, 1),
        _item('ammonia', 'nh3', 2, 3, 1, 1),
        _item('co2', 'co2', 3, 3, 1, 1),
        _item('water', 'agua', 4, 3, 2, 1),
      ],
    ),
    initialLayoutTemplateCatalog.byId('grid_6x4')!,
    referenceMetricCatalogById('environment_room_v1')!,
  ),
  ReferenceBoardLayout(
    'Laboratorio',
    DeviceBoardLayout(
      deviceId: 'example-laboratory',
      layoutTemplateId: 'grid_6x1',
      items: [
        _item('temperature', 'tempInterior', 0, 0, 3, 1),
        _item('humidity', 'humedadInterior', 3, 0, 3, 1),
      ],
    ),
    initialLayoutTemplateCatalog.byId('grid_6x1')!,
    referenceMetricCatalogById('laboratory_v1')!,
  ),
  ReferenceBoardLayout(
    'Arco',
    DeviceBoardLayout(
      deviceId: 'example-disinfection',
      layoutTemplateId: 'grid_6x1',
      items: [
        _item('disinfected', 'vehiclesDisinfectedDaily', 0, 0, 2, 1),
        _item('total', 'vehiclesTotalDaily', 2, 0, 2, 1),
        _item('level', 'disinfectantLevel', 4, 0, 2, 1),
      ],
    ),
    initialLayoutTemplateCatalog.byId('grid_6x1')!,
    referenceMetricCatalogById('disinfection_arch_v1')!,
  ),
]);
