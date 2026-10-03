import 'package:flutter/material.dart';
import '../board_content/board_content_layout.dart';
import '../board_content/reference_content_boards.dart';
import '../device_board_layouts/reference_board_layouts.dart';
import '../device_metric_catalogs/device_metric_catalog.dart';
import '../layout_templates/layout_template.dart';
import '../models/dashboard_range_settings.dart';
import '../ui_templates/models/template_data_context.dart';

enum PreviewSeverity { ok, warning, critical, neutral }

class PreviewStatus {
  const PreviewStatus(this.value, this.label, this.severity);
  final String value;
  final String label;
  final PreviewSeverity severity;
}

/// Snapshot in memory supplied once per board. No network, timers or listeners.
class PreviewBoardDataProvider {
  const PreviewBoardDataProvider({
    this.metricData = const TemplateDataContext(source: null),
    this.sources = const {},
    this.media = const {},
    this.rangeSettings = const DashboardRangeSettings.defaults(),
  });
  final TemplateDataContext metricData;
  final Map<String, Object?> sources;
  final Map<String, ImageProvider> media;
  final DashboardRangeSettings rangeSettings;
}

class PreviewBoardFixture {
  const PreviewBoardFixture(
    this.name,
    this.board,
    this.template,
    this.catalog,
    this.data,
  );
  final String name;
  final BoardContentLayout board;
  final LayoutTemplate template;
  final DeviceMetricCatalog catalog;
  final PreviewBoardDataProvider data;
}

final PreviewBoardDataProvider samplePreviewData = PreviewBoardDataProvider(
  metricData: const TemplateDataContext(
    source: {
      'tempInterior': 24.6,
      'humInterior': 64.0,
      'tempExterior': 19.5,
      'humExterior': 72.0,
      'tensionSalidaVentiladores': 450,
      'presionDiferencial': 28,
      'salaAbierta': false,
      'munterAbierto': true,
      'currentCount': 128,
      'nh3': 8,
      'resistencia1': true,
      'resistencia2': false,
      'bombaHumidificador': true,
    },
  ),
  sources: {
    'device.operatingState': const PreviewStatus(
      'operative',
      'Operativo',
      PreviewSeverity.ok,
    ),
    'device.latestVehicle': {
      'timestamp': DateTime(2026, 9, 12, 10, 32),
      'plate': 'AB 123 CD',
      'vehicleType': 'Camión',
      'operator': 'Operador de ejemplo',
      'state': 'Completado',
    },
    'device.recentRecords': List.generate(
      5,
      (i) => <String, Object?>{
        'timestamp': DateTime(2026, 9, 12, 10, 32 - i * 8),
        'plate': [
          'AB 123 CD',
          'AC 456 EF',
          'AD 789 GH',
          'AE 234 IJ',
          'AF 567 KL',
        ][i],
        'vehicleType': 'Camión',
        'operator': 'Empresa de ejemplo',
        'state': 'Completado',
        'product': 'Producto demo',
        'ppm': 300 + i * 5,
      },
    ),
  },
);
// pending.* retains the current resolver's no-data semantics; preview does not
// fabricate live capability values or bypass the production resolver contract.
final List<PreviewBoardFixture> previewBoardFixtures = List.unmodifiable([
  PreviewBoardFixture(
    'Sala',
    roomContentExample.board,
    roomContentExample.template,
    roomContentExample.catalog,
    samplePreviewData,
  ),
  PreviewBoardFixture(
    'Laboratorio',
    BoardContentLayout.fromLegacy(referenceBoardLayouts[1].board),
    referenceBoardLayouts[1].template,
    referenceBoardLayouts[1].catalog,
    samplePreviewData,
  ),
  PreviewBoardFixture(
    'Arco',
    disinfectionContentExample.board,
    disinfectionContentExample.template,
    disinfectionContentExample.catalog,
    samplePreviewData,
  ),
]);
