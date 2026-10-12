/// `AgroData_<cliente>_<establecimiento>_<desde>_<hasta>.xlsx`, con nombres
/// sanitizados — nunca caracteres inválidos para un nombre de archivo, nunca
/// espacios (para que el nombre quede legible sin comillas en cualquier SO).
String buildHistoricalExportFilename({
  required String clientName,
  required String establishmentName,
  required DateTime from,
  required DateTime to,
}) {
  String part(String raw) {
    final noSpaces = raw.trim().split(RegExp(r'\s+')).join();
    final transliterated = _stripDiacritics(noSpaces);
    final sanitized = transliterated.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return sanitized.isEmpty ? 'sin-nombre' : sanitized;
  }

  String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  return 'AgroData_${part(clientName)}_${part(establishmentName)}_'
      '${dateKey(from)}_${dateKey(to)}.xlsx';
}

const Map<String, String> _diacritics = {
  'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n',
  'Á': 'A', 'É': 'E', 'Í': 'I', 'Ó': 'O', 'Ú': 'U', 'Ü': 'U', 'Ñ': 'N',
};

String _stripDiacritics(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_diacritics[char] ?? char);
  }
  return buffer.toString();
}
