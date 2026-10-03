import 'package:flutter/material.dart';

import '../board_content/board_content_layout.dart';
import '../board_content/board_content_validator.dart';
import '../board_presets/board_preset_catalog.dart'
    show resolveLayoutTemplateId;
import '../board_preview/board_content_renderer.dart';
import '../board_preview/preview_board_data.dart';
import '../cell_layout_presets/cell_layout_catalog.dart';
import '../device_capabilities/capability_library_store.dart';
import '../device_capabilities/device_capability_profile.dart';
import '../device_metric_catalogs/device_metric_catalog.dart';
import '../layout_templates/layout_template.dart';
import '../models/dashboard_range_settings.dart';
import '../services/device_board_config_repository.dart';
import '../services/global_board_configuration_service.dart';
import '../ui_templates/models/template_data_context.dart';

/// Stable Firestore identities for the deliberately narrow runtime trial.
/// This is the only activation gate; labels and display names never take part.
const String qaRuntimeTenantId = 'qa-structural-test';
const String qaRuntimeSiteId = 'qa-site';
const String qaRuntimeDeviceId = 'qa-device';

bool isQaDeviceBoardRuntimeTarget({
  required String? tenantId,
  required String? siteId,
  required String deviceId,
}) =>
    tenantId == qaRuntimeTenantId &&
    siteId == qaRuntimeSiteId &&
    deviceId == qaRuntimeDeviceId;

enum QaDeviceBoardRuntimeStatus { notTarget, loaded, missing, invalid, error }

class QaDeviceBoardRenderData {
  const QaDeviceBoardRenderData({
    required this.board,
    required this.template,
    required this.catalog,
    required this.cellLayouts,
  });

  final BoardContentLayout board;
  final LayoutTemplate template;
  final DeviceMetricCatalog catalog;
  final CellLayoutCatalog cellLayouts;
}

class QaDeviceBoardRuntimeResult {
  const QaDeviceBoardRuntimeResult(this.status, {this.data, this.message});

  final QaDeviceBoardRuntimeStatus status;
  final QaDeviceBoardRenderData? data;
  final String? message;
}

/// One-shot loader with a per-session/per-Device Future cache. Normal widget
/// rebuilds reuse the same Future and therefore perform no extra reads.
class QaDeviceBoardRuntimeLoader {
  QaDeviceBoardRuntimeLoader({
    DeviceBoardConfigRepository? boardConfigs,
    GlobalBoardConfigurationService? globalConfiguration,
  }) : _boardConfigs = boardConfigs ?? const DeviceBoardConfigRepository(),
       _globalConfiguration =
           globalConfiguration ?? sharedGlobalBoardConfigurationService;

  final DeviceBoardConfigRepository _boardConfigs;
  final GlobalBoardConfigurationService _globalConfiguration;
  final Map<String, Future<QaDeviceBoardRuntimeResult>> _cache = {};

  Future<QaDeviceBoardRuntimeResult> load({
    required String? tenantId,
    required String? siteId,
    required String deviceId,
  }) {
    if (!isQaDeviceBoardRuntimeTarget(
      tenantId: tenantId,
      siteId: siteId,
      deviceId: deviceId,
    )) {
      return Future.value(
        const QaDeviceBoardRuntimeResult(QaDeviceBoardRuntimeStatus.notTarget),
      );
    }
    final key = '$tenantId/$siteId/$deviceId';
    return _cache.putIfAbsent(
      key,
      () => _fetch(tenantId: tenantId!, deviceId: deviceId),
    );
  }

  void invalidate({String deviceId = qaRuntimeDeviceId}) {
    _cache.removeWhere((key, _) => key.endsWith('/$deviceId'));
  }

  Future<QaDeviceBoardRuntimeResult> _fetch({
    required String tenantId,
    required String deviceId,
  }) async {
    try {
      final board = await _boardConfigs.fetchOne(
        tenantId: tenantId,
        deviceId: deviceId,
      );
      if (board == null) {
        debugPrint(
          '[BoardRuntime] QA Device → missing boardConfig, using legacy',
        );
        return const QaDeviceBoardRuntimeResult(
          QaDeviceBoardRuntimeStatus.missing,
        );
      }

      final global = await _globalConfiguration.load();
      final profile = global.profiles
          .where(
            (record) =>
                record.profile.enabled &&
                record.profile.id == board.capabilityProfileId,
          )
          .map((record) => record.profile)
          .cast<DeviceCapabilityProfile?>()
          .firstOrNull;
      if (profile == null) {
        return _invalid(
          'capabilityProfileId "${board.capabilityProfileId}" no disponible',
        );
      }

      final metrics = MetricLibraryStore(
        initial: global.metrics
            .where((record) => record.enabled)
            .map((record) => record.metric)
            .toList(),
      );
      final indicators = IndicatorLibraryStore(
        initial: global.indicators
            .where((record) => record.enabled)
            .map((record) => record.indicator)
            .toList(),
      );
      final catalog = profile.resolve(metrics, indicators);
      final cellLayouts = CellLayoutCatalog(
        global.cellLayouts.where((preset) => preset.enabled).toList(),
      );
      final persistedTemplate = global.layouts
          .where(
            (template) =>
                template.enabled && template.id == board.layoutTemplateId,
          )
          .cast<LayoutTemplate?>()
          .firstOrNull;
      final template =
          persistedTemplate ?? resolveLayoutTemplateId(board.layoutTemplateId);
      final issues = BoardContentValidator.validate(
        board,
        template,
        catalog,
        cellLayouts,
      );
      if (issues.isNotEmpty) {
        return _invalid(
          issues.map((issue) => '${issue.code}: ${issue.message}').join('; '),
        );
      }

      debugPrint(
        '[BoardRuntime] QA Device → configured board loaded '
        'v${board.layoutVersion}',
      );
      return QaDeviceBoardRuntimeResult(
        QaDeviceBoardRuntimeStatus.loaded,
        data: QaDeviceBoardRenderData(
          board: board,
          template: template,
          catalog: catalog,
          cellLayouts: cellLayouts,
        ),
      );
    } on ArgumentError catch (error) {
      return _invalid(error.toString());
    } on StateError catch (error) {
      return _invalid(error.toString());
    } on FormatException catch (error) {
      return _invalid(error.toString());
    } catch (error) {
      debugPrint(
        '[BoardRuntime] QA Device → boardConfig read error, using legacy: '
        '$error',
      );
      return QaDeviceBoardRuntimeResult(
        QaDeviceBoardRuntimeStatus.error,
        message: error.toString(),
      );
    }
  }

  QaDeviceBoardRuntimeResult _invalid(String message) {
    debugPrint(
      '[BoardRuntime] QA Device → invalid boardConfig, using legacy: $message',
    );
    return QaDeviceBoardRuntimeResult(
      QaDeviceBoardRuntimeStatus.invalid,
      message: message,
    );
  }
}

final QaDeviceBoardRuntimeLoader sharedQaDeviceBoardRuntimeLoader =
    QaDeviceBoardRuntimeLoader();

/// Runtime boundary used by Home/TABLERO. Every non-QA context returns the
/// already-built legacy card immediately and never invokes the loader.
class QaDeviceBoardRuntimeCard extends StatefulWidget {
  const QaDeviceBoardRuntimeCard({
    super.key,
    required this.tenantId,
    required this.siteId,
    required this.deviceId,
    required this.deviceName,
    required this.liveData,
    required this.legacyChild,
    this.reloadToken = 0,
    this.loader,
    this.rangeSettings = const DashboardRangeSettings.defaults(),
  });

  final String? tenantId;
  final String? siteId;
  final String deviceId;
  final String deviceName;
  final Object? liveData;
  final Widget legacyChild;
  final int reloadToken;
  final QaDeviceBoardRuntimeLoader? loader;
  final DashboardRangeSettings rangeSettings;

  @override
  State<QaDeviceBoardRuntimeCard> createState() =>
      _QaDeviceBoardRuntimeCardState();
}

class _QaDeviceBoardRuntimeCardState extends State<QaDeviceBoardRuntimeCard> {
  Future<QaDeviceBoardRuntimeResult>? _result;

  bool get _isTarget => isQaDeviceBoardRuntimeTarget(
    tenantId: widget.tenantId,
    siteId: widget.siteId,
    deviceId: widget.deviceId,
  );

  QaDeviceBoardRuntimeLoader get _loader =>
      widget.loader ?? sharedQaDeviceBoardRuntimeLoader;

  @override
  void initState() {
    super.initState();
    _loadIfTarget();
  }

  @override
  void didUpdateWidget(covariant QaDeviceBoardRuntimeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId ||
        oldWidget.siteId != widget.siteId ||
        oldWidget.deviceId != widget.deviceId ||
        oldWidget.reloadToken != widget.reloadToken ||
        oldWidget.loader != widget.loader) {
      _loadIfTarget();
    }
  }

  void _loadIfTarget() {
    _result = _isTarget
        ? _loader.load(
            tenantId: widget.tenantId,
            siteId: widget.siteId,
            deviceId: widget.deviceId,
          )
        : null;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isTarget) return widget.legacyChild;
    return FutureBuilder<QaDeviceBoardRuntimeResult>(
      future: _result,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            key: const ValueKey('qa-board-runtime-loading'),
            constraints: const BoxConstraints(minHeight: 280),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        final result = snapshot.data;
        if (result?.status != QaDeviceBoardRuntimeStatus.loaded ||
            result?.data == null) {
          return widget.legacyChild;
        }
        final renderData = result!.data!;
        return KeyedSubtree(
          key: ValueKey(
            'qa-board-runtime-loaded-v${renderData.board.layoutVersion}',
          ),
          child: BoardContentRenderer(
            board: renderData.board,
            template: renderData.template,
            catalog: renderData.catalog,
            presets: renderData.cellLayouts,
            data: PreviewBoardDataProvider(
              metricData: TemplateDataContext(source: widget.liveData),
              rangeSettings: widget.rangeSettings,
            ),
            deviceName: widget.deviceName,
          ),
        );
      },
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
