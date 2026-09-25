import 'package:flutter/material.dart';
import '../ui_templates/board/device_board_renderer.dart';
import '../ui_templates/catalog/agro_ui_templates.dart';
import 'board_content_renderer.dart';
import 'preview_board_data.dart';
import 'board_render_config.dart';

class BoardPreviewPage extends StatefulWidget {
  const BoardPreviewPage({
    super.key,
    required this.isOwner,
    this.initialIndex = 0,
    this.initialGrid = false,
    this.initialCompare = false,
    this.renderConfig = const BoardRenderConfig(),
  });
  final bool isOwner;
  final int initialIndex;
  final bool initialGrid;
  final bool initialCompare;
  final BoardRenderConfig renderConfig;
  @override
  State<BoardPreviewPage> createState() => _BoardPreviewPageState();
}

class _BoardPreviewPageState extends State<BoardPreviewPage> {
  late int index;
  late bool grid;
  late bool compare;
  @override
  void initState() {
    super.initState();
    index = widget.initialIndex.clamp(0, previewBoardFixtures.length - 1);
    grid = widget.initialGrid;
    compare = widget.initialCompare;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOwner) {
      return const Scaffold(
        body: Center(child: Text('Preview disponible solo para owner')),
      );
    }
    final fixture = previewBoardFixtures[index];
    return Scaffold(
      appBar: AppBar(title: const Text('Board Preview')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'NUEVO RENDERER — PREVIEW',
                  style: TextStyle(
                    color: Color(0xFF38BDF8),
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Datos sintéticos locales · no se guarda configuración',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < previewBoardFixtures.length; i++)
                      ChoiceChip(
                        label: Text(previewBoardFixtures[i].name),
                        selected: index == i,
                        onSelected: (_) => setState(() => index = i),
                      ),
                    FilterChip(
                      label: const Text('Mostrar grilla'),
                      selected: grid,
                      onSelected: (v) => setState(() => grid = v),
                    ),
                    if (index == 0)
                      FilterChip(
                        label: const Text('Comparar actual'),
                        selected: compare,
                        onSelected: (v) => setState(() => compare = v),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                BoardContentRenderer(
                  board: fixture.board,
                  template: fixture.template,
                  catalog: fixture.catalog,
                  data: fixture.data,
                  deviceName: '${fixture.name} · demo',
                  showGrid: grid,
                  renderConfig: widget.renderConfig,
                ),
                if (index == 0 && compare) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Renderer actual · mismos datos sintéticos',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  DeviceBoardRenderer(
                    template: getTemplateById('room_climate')!,
                    deviceData: fixture.data.metricData,
                    title: 'Sala · comparación actual',
                  ),
                ],
                const SizedBox(height: 20),
                const Text(
                  'Las capacidades pendientes muestran “Sin datos”. Imagen ilustrativa y gráficos sin datos reales.',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
