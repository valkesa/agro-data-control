// Explicit development entrypoint; never selected by the production application.
// No Firebase initialization, authentication bypass route or backend access.
import 'package:flutter/material.dart';
import 'package:agro_data_control/board_presets/board_presets_page.dart';
import 'package:agro_data_control/board_preview/board_editor_page.dart';
import 'package:agro_data_control/board_preview/board_preview_page.dart';
import 'package:agro_data_control/board_preview/board_render_config.dart';
import 'package:agro_data_control/device_capabilities/capability_admin_page.dart';
import 'package:agro_data_control/device_metric_catalogs/device_metric_catalog.dart';

void main() {
  final params = Uri.base.queryParameters;
  final renderConfig = BoardRenderConfig(
    baseCellSize:
        double.tryParse(params['cell'] ?? '') ??
        const BoardRenderConfig().baseCellSize,
    cardGap:
        double.tryParse(params['gap'] ?? '') ??
        const BoardRenderConfig().cardGap,
  );
  // N6.4 §21/§26: `?emptyCatalog=1` opens every BoardPreset's editor against
  // a real, zero-metric DeviceMetricCatalog — manual proof that a preset
  // can be fully designed (text/icon/image/placeholder, at minimum) without
  // any capability profile at all.
  final emptyCatalog = params['emptyCatalog'] == '1'
      ? DeviceMetricCatalog(id: 'empty', name: 'Vacío', metrics: const [])
      : null;
  runApp(
    MaterialApp(
      title: 'AgroData · desarrollo preview',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'monospace',
        scaffoldBackgroundColor: const Color(0xFF020617),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8),
          secondary: Color(0xFF22C55E),
          surface: Color(0xFF0F172A),
        ),
      ),
      home: switch (params['mode']) {
        'editor' => _EditorLauncher(renderConfig: renderConfig),
        'presets' => BoardPresetsPage(
          isOwner: true,
          renderConfig: renderConfig,
          metricCatalog: emptyCatalog,
        ),
        // N6.5.2: renamed from 'metrics' (DeviceMetricCatalogAdminPage) to
        // 'capabilities' (CapabilityAdminPage) — kept accepting the old
        // value too so any bookmarked/scripted URL from before this stage
        // still lands somewhere sensible.
        'capabilities' || 'metrics' => CapabilityAdminPage(isOwner: true),
        // N6.5 §37: the only route that lets a single Chrome session move
        // between the capabilities admin page and Board Presets/Editor via
        // real in-app Navigator.push — every other `mode` value loads its
        // page as `home`, which on a fresh `Page.navigate` starts a new
        // Flutter app instance and loses the shared in-memory stores.
        'hub' => _ToolHub(renderConfig: renderConfig),
        _ => BoardPreviewPage(
          isOwner: true,
          initialIndex: int.tryParse(params['fixture'] ?? '') ?? 0,
          initialGrid: params['grid'] == '1',
          initialCompare: params['compare'] == '1',
          renderConfig: renderConfig,
        ),
      },
    ),
  );
}

/// N6.5 §37 manual-walkthrough hub — three buttons, each pushing a real
/// route so `sharedDeviceCapabilityProfileStore`/`sharedBoardPresetCatalog`
/// stay the same instances across all three pages in one Chrome session.
class _ToolHub extends StatelessWidget {
  const _ToolHub({required this.renderConfig});
  final BoardRenderConfig renderConfig;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    BoardEditorPage(isOwner: true, renderConfig: renderConfig),
              ),
            ),
            child: const Text('Abrir Board Editor'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    BoardPresetsPage(isOwner: true, renderConfig: renderConfig),
              ),
            ),
            child: const Text('Abrir Board Presets'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CapabilityAdminPage(isOwner: true),
              ),
            ),
            child: const Text('Abrir Capacidades'),
          ),
        ],
      ),
    ),
  );
}

/// Pushes [BoardEditorPage] on a real route so A1's exit-confirmation
/// (PopScope intercepting the AppBar back button) is exercisable manually
/// exactly as it works when main.dart pushes it in the real app.
class _EditorLauncher extends StatelessWidget {
  const _EditorLauncher({required this.renderConfig});
  final BoardRenderConfig renderConfig;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                BoardEditorPage(isOwner: true, renderConfig: renderConfig),
          ),
        ),
        child: const Text('Abrir Board Editor'),
      ),
    ),
  );
}
