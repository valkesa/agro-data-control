import 'package:flutter/material.dart';

/// Shared preview design-system tokens; all content types use this shell.
abstract final class BoardCardTokens {
  static const surface = Color(0xFF0F172A);
  static const boardCardBorder = Color(0xFF536074);
  static const boardCardBorderHover = Color(0xFF8190A5);
  static const boardCardBorderSelected = Color(0xFF63D3FA);
  static const boardCardBorderInvalid = Color(0xFFF87171);
  static const borderWidth = 1.0;
  static const radius = 8.0;
}

/// Paint and clip without deflating the logical grid constraints.
/// [gap] is the single source for the inset between adjacent cards; it
/// comes from [BoardRenderConfig.cardGap], never hardcoded per renderer.
class BoardPreviewCard extends StatefulWidget {
  const BoardPreviewCard({
    super.key,
    required this.child,
    required this.gap,
    this.selected = false,
    this.invalid = false,
    this.onTap,
  });
  final Widget child;
  final double gap;
  final bool selected;
  final bool invalid;
  final VoidCallback? onTap;
  @override
  State<BoardPreviewCard> createState() => _BoardPreviewCardState();
}

class _BoardPreviewCardState extends State<BoardPreviewCard> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) {
    final borderColor = widget.invalid
        ? BoardCardTokens.boardCardBorderInvalid
        : widget.selected
        ? BoardCardTokens.boardCardBorderSelected
        : hovered
        ? BoardCardTokens.boardCardBorderHover
        : BoardCardTokens.boardCardBorder;
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipPath(
              clipper: _CardClipper(widget.gap),
              child: ColoredBox(
                color: BoardCardTokens.surface,
                child: widget.child,
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.all(widget.gap),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        BoardCardTokens.radius,
                      ),
                      border: Border.all(
                        color: borderColor,
                        width: widget.selected
                            ? BoardCardTokens.borderWidth * 2
                            : BoardCardTokens.borderWidth,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardClipper extends CustomClipper<Path> {
  const _CardClipper(this.gap);
  final double gap;
  @override
  Path getClip(Size size) => Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(gap),
        const Radius.circular(BoardCardTokens.radius),
      ),
    );
  @override
  bool shouldReclip(_CardClipper oldClipper) => oldClipper.gap != gap;
}
