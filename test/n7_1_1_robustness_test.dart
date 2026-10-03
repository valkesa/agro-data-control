import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agro_data_control/board_content/board_content_config.dart';
import 'package:agro_data_control/board_content/board_content_layout.dart';
import 'package:agro_data_control/board_presets/board_preset.dart';
import 'package:agro_data_control/board_presets/board_presets_page.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_catalog.dart';
import 'package:agro_data_control/cell_layout_presets/cell_layout_preset.dart';
import 'package:agro_data_control/device_capabilities/capability_records.dart';
import 'package:agro_data_control/device_capabilities/capability_admin_page.dart';
import 'package:agro_data_control/device_capabilities/capability_metric_definition.dart';
import 'package:agro_data_control/device_capabilities/reference_capability_seeds.dart';
import 'package:agro_data_control/layout_templates/grid_placement.dart';
import 'package:agro_data_control/layout_templates/layout_template.dart';
import 'package:agro_data_control/layout_templates/layout_template_catalog.dart';
import 'package:agro_data_control/services/board_preset_repository.dart';
import 'package:agro_data_control/services/board_validation_rejected.dart';
import 'package:agro_data_control/services/capability_indicator_repository.dart';
import 'package:agro_data_control/services/capability_metric_repository.dart';
import 'package:agro_data_control/services/capability_profile_repository.dart';
import 'package:agro_data_control/services/cell_layout_preset_repository.dart';
import 'package:agro_data_control/services/device_board_config_repository.dart';
import 'package:agro_data_control/services/global_board_configuration_service.dart';
import 'package:agro_data_control/services/layout_template_repository.dart';
import 'package:agro_data_control/device_metric_catalogs/device_metric_catalog.dart';
import 'package:agro_data_control/ui_templates/enums/metric_display_type.dart';

void main() {
  test(
    'A3 — repository rejects an invalid board before touching Firestore',
    () async {
      final invalid = BoardContentLayout(
        deviceId: 'device-1',
        layoutTemplateId: 'grid_6x4',
        items: [
          BoardContentItem(
            id: 'a',
            placement: GridPlacement(x: 0, y: 0, widthCells: 2, heightCells: 2),
            content: TextBoardContent(text: 'A'),
          ),
          BoardContentItem(
            id: 'b',
            placement: GridPlacement(x: 1, y: 1, widthCells: 2, heightCells: 2),
            content: TextBoardContent(text: 'B'),
          ),
        ],
      );

      expect(
        () => const DeviceBoardConfigRepository().saveLayout(
          tenantId: 'tenant-a',
          deviceId: 'device-1',
          layout: invalid,
          expectedLayoutVersion: 0,
          metricCatalog: emptyDeviceMetricCatalog,
          cellLayoutCatalog: CellLayoutCatalog(const []),
        ),
        throwsA(
          isA<BoardValidationRejected>().having(
            (e) => e.issues.map((issue) => issue.code),
            'codes',
            contains('placement_collision'),
          ),
        ),
      );
    },
  );

  test(
    'A1/A13/A15 — global snapshot is coherent and cached per session',
    () async {
      final layouts = _Layouts();
      final cells = _Cells();
      final metrics = _Metrics();
      final indicators = _Indicators();
      final profiles = _Profiles();
      final presets = _Presets();
      final service = GlobalBoardConfigurationService(
        layoutTemplates: layouts,
        cellLayoutPresets: cells,
        metrics: metrics,
        indicators: indicators,
        profiles: profiles,
        boardPresets: presets,
      );

      final first = await service.load();
      final cached = await service.load();
      expect(identical(first, cached), isTrue);
      expect(layouts.reads, 1);
      expect(cells.reads, 1);
      expect(metrics.reads, 1);
      expect(indicators.reads, 1);
      expect(profiles.reads, 1);
      expect(presets.reads, 1);

      final refreshed = await service.load(refresh: true);
      expect(identical(first, refreshed), isFalse);
      expect(layouts.reads, 2);
      expect(presets.reads, 2);
    },
  );

  testWidgets('A1 — capability admin loads the effective Firestore snapshot', (
    tester,
  ) async {
    final service = _SnapshotService(
      metrics: [
        CapabilityMetricRecord(
          metric: CapabilityMetricDefinition(
            key: 'remote_temp',
            label: 'Temperatura remota',
            defaultUnit: '°C',
            icon: 'thermometer',
            displayType: MetricDisplayType.number,
            decimals: 1,
          ),
          schemaVersion: 1,
          enabled: true,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: CapabilityAdminPage(isOwner: true, configurationService: service),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Temperatura remota'), findsOneWidget);
  });

  testWidgets(
    'seed global completo abre BoardPreset sin invalid_default_preset',
    (tester) async {
      final preset = BoardPreset(
        id: 'preset-seeded',
        name: 'Preset sembrado',
        layoutTemplateId: 'grid_6x4',
        capabilityProfileId: 'environment_room_v1',
      );
      final service = _SnapshotService(
        layouts: initialLayoutTemplateCatalog.templates,
        cellLayouts: initialCellLayoutCatalog.presets,
        metrics: [
          for (final metric in sharedMetricLibraryStore.metrics)
            CapabilityMetricRecord(
              metric: metric,
              schemaVersion: 1,
              enabled: true,
            ),
        ],
        indicators: [
          for (final indicator in sharedIndicatorLibraryStore.indicators)
            CapabilityIndicatorRecord(
              indicator: indicator,
              schemaVersion: 1,
              enabled: true,
            ),
        ],
        profiles: [
          for (final profile in sharedDeviceCapabilityProfileStore.profiles)
            CapabilityProfileRecord(profile: profile),
        ],
        boardPresets: [preset],
      );
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: BoardPresetsPage(isOwner: true, configurationService: service),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('preset-edit-preset-seeded')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('BOARD PRESET EDITOR'), findsOneWidget);
      expect(
        find.textContaining(
          'Default must reference an enabled preset of matching span',
        ),
        findsNothing,
      );
    },
  );

  testWidgets('A7 — delete warns with aggregate Device usage count', (
    tester,
  ) async {
    final repository = _DeletingPresets();
    final service = _SnapshotService(
      boardRepository: repository,
      boardPresets: [repository.preset],
    );
    repository.onDelete = () => service.currentPresets = const [];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: BoardPresetsPage(isOwner: true, configurationService: service),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preset-delete-preset-a')));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 Devices'), findsOneWidget);
    expect(find.textContaining('NO serán modificados'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();
    expect(repository.deleted, isTrue);
    expect(find.byKey(const ValueKey('preset-row-preset-a')), findsNothing);
  });

  test('A6 — every global create uses a transaction and typed conflict', () {
    const files = [
      'layout_template_repository.dart',
      'cell_layout_preset_repository.dart',
      'capability_metric_repository.dart',
      'capability_indicator_repository.dart',
      'capability_profile_repository.dart',
      'board_preset_repository.dart',
    ];
    for (final name in files) {
      final source = File('lib/services/$name').readAsStringSync();
      final createBody = source.substring(
        source.indexOf('Future<void> create('),
        source.indexOf('Future<int> save('),
      );
      expect(createBody, contains('runTransaction<bool>'), reason: name);
      expect(createBody, contains('FirestoreAlreadyExists'), reason: name);
      expect(
        createBody,
        isNot(contains('await reference.get()')),
        reason: '$name must not use a racy pre-read',
      );
    }
  });
}

class _SnapshotService extends GlobalBoardConfigurationService {
  _SnapshotService({
    List<LayoutTemplate> layouts = const [],
    List<CellLayoutPreset> cellLayouts = const [],
    List<CapabilityMetricRecord> metrics = const [],
    List<CapabilityIndicatorRecord> indicators = const [],
    List<CapabilityProfileRecord> profiles = const [],
    List<BoardPreset> boardPresets = const [],
    BoardPresetRepository? boardRepository,
  }) : _layouts = layouts,
       _cellLayouts = cellLayouts,
       _metrics = metrics,
       _indicators = indicators,
       _profiles = profiles,
       currentPresets = boardPresets,
       super(boardPresets: boardRepository ?? _Presets());

  final List<LayoutTemplate> _layouts;
  final List<CellLayoutPreset> _cellLayouts;
  final List<CapabilityMetricRecord> _metrics;
  final List<CapabilityIndicatorRecord> _indicators;
  final List<CapabilityProfileRecord> _profiles;
  List<BoardPreset> currentPresets;

  @override
  Future<GlobalBoardConfigurationSnapshot> load({bool refresh = false}) async =>
      GlobalBoardConfigurationSnapshot(
        layouts: _layouts,
        cellLayouts: _cellLayouts,
        metrics: _metrics,
        indicators: _indicators,
        profiles: _profiles,
        boardPresets: currentPresets,
      );
}

class _DeletingPresets extends BoardPresetRepository {
  final preset = BoardPreset(
    id: 'preset-a',
    name: 'Preset A',
    layoutTemplateId: 'grid_6x4',
  );
  bool deleted = false;
  void Function()? onDelete;

  @override
  Future<int> countDeviceUsages(String presetId) async => 3;

  @override
  Future<void> delete(String presetId, {int? expectedVersion}) async {
    deleted = true;
    onDelete?.call();
  }
}

class _Layouts extends LayoutTemplateRepository {
  int reads = 0;
  @override
  Future<List<LayoutTemplate>> fetchAll() async {
    reads++;
    return const [];
  }
}

class _Cells extends CellLayoutPresetRepository {
  int reads = 0;
  @override
  Future<List<CellLayoutPreset>> fetchAll() async {
    reads++;
    return const [];
  }
}

class _Metrics extends CapabilityMetricRepository {
  int reads = 0;
  @override
  Future<List<CapabilityMetricRecord>> fetchAll() async {
    reads++;
    return const [];
  }
}

class _Indicators extends CapabilityIndicatorRepository {
  int reads = 0;
  @override
  Future<List<CapabilityIndicatorRecord>> fetchAll() async {
    reads++;
    return const [];
  }
}

class _Profiles extends CapabilityProfileRepository {
  int reads = 0;
  @override
  Future<List<CapabilityProfileRecord>> fetchAll() async {
    reads++;
    return const [];
  }
}

class _Presets extends BoardPresetRepository {
  int reads = 0;
  @override
  Future<List<BoardPreset>> fetchAll() async {
    reads++;
    return const [];
  }
}
