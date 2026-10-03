import '../board_presets/board_preset.dart';
import '../cell_layout_presets/cell_layout_preset.dart';
import '../device_capabilities/capability_records.dart';
import '../layout_templates/layout_template.dart';
import 'board_preset_repository.dart';
import 'capability_indicator_repository.dart';
import 'capability_metric_repository.dart';
import 'capability_profile_repository.dart';
import 'cell_layout_preset_repository.dart';
import 'layout_template_repository.dart';

/// A coherent, one-shot view of every global Board dependency. Consumers
/// never combine a remote BoardPreset with process-local seed catalogs.
class GlobalBoardConfigurationSnapshot {
  const GlobalBoardConfigurationSnapshot({
    required this.layouts,
    required this.cellLayouts,
    required this.metrics,
    required this.indicators,
    required this.profiles,
    required this.boardPresets,
  });

  final List<LayoutTemplate> layouts;
  final List<CellLayoutPreset> cellLayouts;
  final List<CapabilityMetricRecord> metrics;
  final List<CapabilityIndicatorRecord> indicators;
  final List<CapabilityProfileRecord> profiles;
  final List<BoardPreset> boardPresets;
}

/// Session cache for global Board administration. The first load costs six
/// collection reads; cache hits cost zero. Mutating callers invalidate the
/// cache and explicitly reload after the confirmed write.
class GlobalBoardConfigurationService {
  GlobalBoardConfigurationService({
    this.layoutTemplates = const LayoutTemplateRepository(),
    this.cellLayoutPresets = const CellLayoutPresetRepository(),
    this.metrics = const CapabilityMetricRepository(),
    this.indicators = const CapabilityIndicatorRepository(),
    this.profiles = const CapabilityProfileRepository(),
    this.boardPresets = const BoardPresetRepository(),
  });

  final LayoutTemplateRepository layoutTemplates;
  final CellLayoutPresetRepository cellLayoutPresets;
  final CapabilityMetricRepository metrics;
  final CapabilityIndicatorRepository indicators;
  final CapabilityProfileRepository profiles;
  final BoardPresetRepository boardPresets;

  GlobalBoardConfigurationSnapshot? _cached;
  Future<GlobalBoardConfigurationSnapshot>? _inFlight;

  Future<GlobalBoardConfigurationSnapshot> load({bool refresh = false}) {
    if (refresh) invalidate();
    final cached = _cached;
    if (cached != null) return Future.value(cached);
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  void invalidate() => _cached = null;

  Future<GlobalBoardConfigurationSnapshot> _fetch() async {
    final values = await Future.wait<Object>([
      layoutTemplates.fetchAll(),
      cellLayoutPresets.fetchAll(),
      metrics.fetchAll(),
      indicators.fetchAll(),
      profiles.fetchAll(),
      boardPresets.fetchAll(),
    ]);
    return _cached = GlobalBoardConfigurationSnapshot(
      layouts: values[0] as List<LayoutTemplate>,
      cellLayouts: values[1] as List<CellLayoutPreset>,
      metrics: values[2] as List<CapabilityMetricRecord>,
      indicators: values[3] as List<CapabilityIndicatorRecord>,
      profiles: values[4] as List<CapabilityProfileRecord>,
      boardPresets: values[5] as List<BoardPreset>,
    );
  }
}

final GlobalBoardConfigurationService sharedGlobalBoardConfigurationService =
    GlobalBoardConfigurationService();
