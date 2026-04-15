import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../models/magnifier_settings.dart';

class PressMagnifierRegion extends StatefulWidget {
  const PressMagnifierRegion({
    super.key,
    required this.settings,
    required this.child,
    this.controller,
  });

  final MagnifierSettings settings;
  final Widget child;
  final PressMagnifierController? controller;

  @override
  State<PressMagnifierRegion> createState() => _PressMagnifierRegionState();
}

class _PressMagnifierRegionState extends State<PressMagnifierRegion> {
  OverlayEntry? _overlayEntry;
  Offset? _globalPosition;

  @override
  void initState() {
    super.initState();
    widget.controller?._bind(this);
  }

  @override
  void didUpdateWidget(covariant PressMagnifierRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._unbind(this);
      widget.controller?._bind(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._unbind(this);
    _removeMagnifier();
    super.dispose();
  }

  void _showMagnifier(Offset globalPosition) {
    _globalPosition = globalPosition;
    final OverlayState overlay = Overlay.of(context, rootOverlay: true);

    _overlayEntry ??= OverlayEntry(builder: _buildOverlay);
    if (!(_overlayEntry?.mounted ?? false)) {
      overlay.insert(_overlayEntry!);
    } else {
      _overlayEntry!.markNeedsBuild();
    }
  }

  Widget _buildOverlay(BuildContext context) {
    final Offset? globalPosition = _globalPosition;
    if (globalPosition == null) {
      return const SizedBox.shrink();
    }

    final double size = widget.settings.size;
    final double left = globalPosition.dx - (size / 2);
    final double top = globalPosition.dy - size - 24;

    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: RawMagnifier(
              size: Size.square(size),
              magnificationScale: widget.settings.zoom,
              decoration: MagnifierDecoration(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFF94A3B8), width: 1.5),
                ),
                shadows: const [
                  BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 18,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _updateMagnifier(Offset globalPosition) {
    _globalPosition = globalPosition;
    _overlayEntry?.markNeedsBuild();
  }

  void _removeMagnifier() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _globalPosition = null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: (details) => _showMagnifier(details.globalPosition),
      onLongPressMoveUpdate: (details) =>
          _updateMagnifier(details.globalPosition),
      onLongPressEnd: (_) => _removeMagnifier(),
      onLongPressCancel: _removeMagnifier,
      child: widget.child,
    );
  }
}

class PressMagnifierController {
  _PressMagnifierRegionState? _state;
  int? _activePointer;

  void _bind(_PressMagnifierRegionState state) {
    _state = state;
  }

  void _unbind(_PressMagnifierRegionState state) {
    if (_state == state) {
      _state = null;
    }
  }

  void startTrackedPointer(PointerDownEvent event) {
    _activePointer = event.pointer;
    WidgetsBinding.instance.pointerRouter.addGlobalRoute(_handlePointerEvent);
    _state?._showMagnifier(event.position);
  }

  void _handlePointerEvent(PointerEvent event) {
    if (event.pointer != _activePointer) {
      return;
    }
    if (event is PointerMoveEvent || event is PointerHoverEvent) {
      _state?._updateMagnifier(event.position);
      return;
    }
    if (event is PointerUpEvent) {
      hide();
    }
  }

  void show(Offset globalPosition) => _state?._showMagnifier(globalPosition);

  void update(Offset globalPosition) =>
      _state?._updateMagnifier(globalPosition);

  void hide() {
    if (_activePointer != null) {
      WidgetsBinding.instance.pointerRouter.removeGlobalRoute(
        _handlePointerEvent,
      );
      _activePointer = null;
    }
    _state?._removeMagnifier();
  }
}
