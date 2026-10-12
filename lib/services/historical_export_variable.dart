/// Exportación de históricos a Excel — declarativo, nunca hardcodeado en la
/// lógica de consulta/armado de filas. Hoy el pipeline de históricos por hora
/// (`DeviceEnvironmentHistoryService` en el backend) solo produce exactamente
/// estas dos variables (`temperature`/`humidity`, un sub-mapa `{avg, min,
/// max, sampleCount}` cada una dentro del mismo documento `historyHourly`),
/// pero el exportador no debe conocer eso: agregar una variable futura es
/// agregar una entrada acá, nada más — ni la consulta a Firestore ni el
/// armado de filas/hoja referencian `temperature`/`humidity` por nombre en
/// ningún otro lugar.
class HistoricalExportVariable {
  const HistoricalExportVariable({
    required this.key,
    required this.label,
    required this.unit,
  });

  /// Nombre del campo tal como aparece en el documento `historyHourly`
  /// (`doc[key]` es el sub-mapa `{avg, min, max, sampleCount}`).
  final String key;

  /// Etiqueta amigable para el cliente — nunca el nombre técnico de
  /// Firestore en el Excel.
  final String label;

  /// Vacío si la variable no tiene unidad definida.
  final String unit;

  String get columnHeader => unit.isEmpty ? label : '$label ($unit)';

  /// `null` cuando el documento no trae esta variable, o cuando
  /// `sampleCount` es 0 (esa hora no tuvo muestras reales) — en ambos casos
  /// el llamador debe dejar la celda vacía, nunca inventar/interpolar un
  /// valor.
  double? extractAvg(Map<String, Object?> doc) {
    final raw = doc[key];
    if (raw is! Map) return null;
    final avg = raw['avg'];
    final sampleCount = raw['sampleCount'];
    if (avg is! num || !avg.isFinite) return null;
    if (sampleCount is! num || sampleCount <= 0) return null;
    return avg.toDouble();
  }
}

/// Registro central de variables exportables. Agregar una variable nueva al
/// pipeline de históricos (presente o futura) solo requiere agregar una
/// entrada acá.
const List<HistoricalExportVariable> kHistoricalExportVariables = [
  HistoricalExportVariable(
    key: 'temperature',
    label: 'Temperatura interior',
    unit: '°C',
  ),
  HistoricalExportVariable(
    key: 'humidity',
    label: 'Humedad interior',
    unit: '%',
  ),
];
