import 'package:excel/excel.dart';

import 'historical_export_point.dart';
import 'historical_export_variable.dart';

/// One Device's already-fetched points, ready to become a sheet.
class HistoricalExportDeviceData {
  const HistoricalExportDeviceData({
    required this.deviceName,
    required this.points,
  });
  final String deviceName;
  final List<HistoricalExportPoint> points;
}

/// Pure input for [buildHistoricalExportWorkbook] — no Firestore, no
/// dart:html. Keeping every Excel-formatting decision in a function that
/// only takes plain data (not a live Firestore query) is what makes the
/// whole `.xlsx` layout testable with `Excel.decodeBytes` in `flutter test`.
class HistoricalExportRequest {
  const HistoricalExportRequest({
    required this.clientName,
    required this.establishmentName,
    required this.fromDate,
    required this.toDate,
    required this.variables,
    required this.devices,
  });

  final String clientName;
  final String establishmentName;

  /// Calendar dates (ART), inclusive — only used for the header line and
  /// column values, never re-derived from the points themselves (a Device
  /// with zero points in range must still show the requested period).
  final DateTime fromDate;
  final DateTime toDate;

  final List<HistoricalExportVariable> variables;
  final List<HistoricalExportDeviceData> devices;
}

// Built fresh per workbook (never shared module-level `final` instances) —
// the `excel` package's NumFormatMaintainer assigns/caches a numFmtId the
// first time a CellStyle is used, scoped to the Excel instance that saw it
// first; a style built before this stage's own `Excel.createExcel()` (e.g. a
// shared top-level `final`) can end up pointing at a numFmtId that instance
// never registered.
class _ExportCellStyles {
  _ExportCellStyles() : header = CellStyle(bold: true);
  final CellStyle header;
}

String _friendlyDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/'
    '${d.year}';

String _periodLabel(DateTime from, DateTime to) =>
    'Período: ${_friendlyDate(from)} al ${_friendlyDate(to)}';

/// ART local date/time (ART = UTC-3) for display columns — the point's
/// `periodStartUtc` is the hour's start instant, shown as the calendar day
/// and hour an operator in Argentina actually experienced.
DateTime _artLocal(DateTime utc) =>
    utc.toUtc().subtract(const Duration(hours: 3));

/// Compact, sortable label requested for chart X axes: YY.MM.DD.hh.
String historicalExportDateTimeLabel(DateTime periodStartUtc) {
  final art = _artLocal(periodStartUtc);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(art.year % 100)}.${two(art.month)}.${two(art.day)}.${two(art.hour)}';
}

/// Sheet names are capped at 31 chars and can't contain `: \ / ? * [ ]`
/// (the OOXML limit, not this package's) — Devices are user-named, so this
/// must sanitize, not assume a safe name.
String sanitizeSheetName(String raw, Set<String> alreadyUsed) {
  var cleaned = raw.replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ').trim();
  if (cleaned.isEmpty) cleaned = 'Equipo';
  if (cleaned.length > 31) cleaned = cleaned.substring(0, 31);
  var candidate = cleaned;
  var suffix = 2;
  while (alreadyUsed.contains(candidate)) {
    final suffixText = ' ($suffix)';
    final maxBase = 31 - suffixText.length;
    candidate =
        '${cleaned.substring(0, cleaned.length > maxBase ? maxBase : cleaned.length)}$suffixText';
    suffix++;
  }
  return candidate;
}

/// Thin wrapper around explicit `CellIndex`-based writes, with a
/// self-tracked row cursor. Deliberately NOT using [Excel.appendRow]'s
/// implicit row-advance: it silently no-ops on an empty row
/// (`if (row.isEmpty) return;`), which would desync any row-index math a
/// caller does alongside it — this writer makes every row index explicit
/// instead, including the deliberately-blank spacer row between the header
/// block and the data table.
class _SheetWriter {
  _SheetWriter(Excel excel, String sheetName) : sheet = excel[sheetName];
  final Sheet sheet;
  int _row = 0;

  void writeRow(List<CellValue?> values, {CellStyle? styleForAll}) {
    for (var c = 0; c < values.length; c++) {
      final value = values[c];
      if (value == null) continue;
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: _row),
      );
      cell.value = value;
      if (styleForAll != null) cell.cellStyle = styleForAll;
    }
    _row++;
  }

  void skipRow() => _row++;
}

/// Writes the sheet metadata, including the Device and selected metrics,
/// followed by one blank spacer row and the table column headers.
void _writeHeader(
  _SheetWriter writer,
  HistoricalExportRequest request,
  HistoricalExportDeviceData device,
  List<String> columnHeaders,
  _ExportCellStyles styles,
) {
  writer.writeRow([TextCellValue(request.clientName)]);
  writer.writeRow([TextCellValue(request.establishmentName)]);
  writer.writeRow([TextCellValue('Device: ${device.deviceName}')]);
  writer.writeRow([
    TextCellValue(
      'Métricas seleccionadas: ${request.variables.map((variable) => variable.columnHeader).join(', ')}',
    ),
  ]);
  writer.writeRow([
    TextCellValue(_periodLabel(request.fromDate, request.toDate)),
  ]);
  writer.writeRow([TextCellValue('Formato Fecha: año.mes.dia.hora')]);
  writer.skipRow();
  writer.writeRow([
    for (final h in columnHeaders) TextCellValue(h),
  ], styleForAll: styles.header);
}

/// One row per point: readable Fecha and Hora, consolidated Fecha y hora,
/// then one column per selected
/// variable — missing data (no stats, or `sampleCount == 0`) is a blank
/// cell, never a 0/interpolated/carried-over value (see
/// [HistoricalExportVariable.extractAvg]).
void _writeDataRows(
  _SheetWriter writer,
  List<HistoricalExportPoint> points,
  List<HistoricalExportVariable> variables,
) {
  for (final point in points) {
    final art = _artLocal(point.periodStartUtc);
    final row = <CellValue?>[
      TextCellValue(_friendlyDate(art)),
      TextCellValue(
        '${art.hour.toString().padLeft(2, '0')}:'
        '${art.minute.toString().padLeft(2, '0')}',
      ),
      TextCellValue(historicalExportDateTimeLabel(point.periodStartUtc)),
    ];
    for (final variable in variables) {
      final value = variable.extractAvg(point.raw);
      row.add(value == null ? null : DoubleCellValue(value));
    }
    writer.writeRow(row);
  }
}

/// Builds the full `.xlsx` as raw bytes — exactly one sheet per selected
/// Device and no consolidated sheet. Column
/// headers use each variable's friendly label+unit
/// ([HistoricalExportVariable.columnHeader]), never the raw Firestore field
/// name. Rows are already chronological because
/// [HistoricalExportRepository.fetchHourlyRange] orders by `periodStart`.
List<int> buildHistoricalExportWorkbook(HistoricalExportRequest request) {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();
  final usedNames = <String>{};
  final styles = _ExportCellStyles();

  for (final device in request.devices) {
    final sheetName = sanitizeSheetName(device.deviceName, usedNames);
    usedNames.add(sheetName);
    final writer = _SheetWriter(excel, sheetName);
    _writeHeader(writer, request, device, [
      'Fecha',
      'Hora',
      'Fecha y hora',
      for (final v in request.variables) v.columnHeader,
    ], styles);
    _writeDataRows(writer, device.points, request.variables);
    writer.sheet.setColumnWidth(0, 14);
    writer.sheet.setColumnWidth(1, 8);
    writer.sheet.setColumnWidth(2, 16);
  }

  if (defaultSheet != null && !usedNames.contains(defaultSheet)) {
    excel.delete(defaultSheet);
  }

  return excel.encode()!;
}
