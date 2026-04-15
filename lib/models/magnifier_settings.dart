class MagnifierSettings {
  const MagnifierSettings({required this.zoom, required this.size});

  const MagnifierSettings.defaults() : zoom = 2.0, size = 140.0;

  final double zoom;
  final double size;
}
