import 'package:flutter/material.dart';

const Color _borderColor = Color(0xFF334155);
const Color _headerColor = Color(0xFF1E293B);
const Color _cellColor = Color(0xFF0F172A);
const Color _textColor = Color(0xFFE5E7EB);
const Color _mutedColor = Color(0xFF94A3B8);
const Color _dashColor = Color(0xFF64748B);

/// Marca "aplica a todos los X hijos de este nivel" — p.ej. un recipient
/// Tenant se hereda por "todos" los Sites y "todos" los Devices.
const String kRecipientSummaryInherited = 'todos';

/// Marca "no definido a este nivel" — ni es el nivel propio del
/// destinatario, ni un nivel heredado desde él.
const String kRecipientSummaryNotApplicable = '-';

/// Una fila de la tabla resumen: un destinatario real (legacy o moderno),
/// con el valor a mostrar en cada columna ya resuelto — pedido del usuario
/// (2026-09-10): "de un pantallazo tengo todo", en vez de tener que
/// cambiar el selector de Device para ver quién recibe qué.
///
/// Regla de las columnas (Global/Tenant/Site/Device), una por nivel:
///  - el nivel donde el destinatario está REALMENTE definido muestra su
///    valor concreto (p.ej. "Laboratorio" en Device para un recipient de
///    device);
///  - los niveles más ESPECÍFICOS que el nivel propio muestran
///    [kRecipientSummaryInherited] ("todos") — se heredan hacia abajo;
///  - los niveles más GENERALES que el nivel propio muestran
///    [kRecipientSummaryNotApplicable] ("-") — no aplica ahí.
class RecipientSummaryRow {
  const RecipientSummaryRow({
    required this.displayName,
    required this.phoneDisplay,
    required this.globalValue,
    required this.tenantValue,
    required this.siteValue,
    required this.deviceValue,
    required this.isLegacy,
  });

  final String displayName;
  final String phoneDisplay;
  final String globalValue;
  final String tenantValue;
  final String siteValue;
  final String deviceValue;

  /// Legacy no es editable desde esta pantalla — se muestra en itálica,
  /// igual criterio visual que los umbrales heredados de otra alerta.
  final bool isLegacy;
}

/// Tabla resumen de TODOS los destinatarios de un Tenant (legacy global +
/// modernos en cualquier nivel Tenant/Site/Device), de solo lectura. La
/// edición sigue siendo exclusiva de [HierarchicalRecipientsSection], que
/// opera sobre el scope actualmente seleccionado — esta tabla es
/// complementaria, no lo reemplaza.
class RecipientsSummaryTable extends StatelessWidget {
  const RecipientsSummaryTable({
    super.key,
    required this.rows,
    this.showGlobalColumn = true,
  });

  final List<RecipientSummaryRow> rows;

  /// Etapa 2026-09-10 (corrección): la columna Global (destinatarios
  /// técnicos legacy de Valke, aplicables a todos los tenants) es
  /// exclusiva de owner — un tenant_admin no debe ver ni la columna ni sus
  /// valores. El caller ya filtra las filas; esto oculta también el header
  /// para no insinuar que existe algo ahí.
  final bool showGlobalColumn;

  static const double _colName = 180;
  static const double _colPhone = 130;
  static const double _colLevel = 110;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double totalBaseWidth =
            _colName + _colPhone + _colLevel * (showGlobalColumn ? 4 : 3);
        final double available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : totalBaseWidth;
        final double scale = available > totalBaseWidth
            ? available / totalBaseWidth
            : 1.0;
        final Widget table = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderRow(scale),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Sin destinatarios (legacy ni modernos) para este tenant.',
                  style: TextStyle(color: _mutedColor, fontSize: 13),
                ),
              )
            else
              for (final RecipientSummaryRow row in rows) _buildRow(row, scale),
          ],
        );
        return Container(
          decoration: BoxDecoration(
            color: _cellColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: table,
          ),
        );
      },
    );
  }

  Widget _buildHeaderRow(double scale) {
    return Container(
      decoration: const BoxDecoration(
        color: _headerColor,
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        children: [
          _headerCell('Destinatario', width: _colName * scale, alignLeft: true),
          _headerCell('Teléfono', width: _colPhone * scale, alignLeft: true),
          if (showGlobalColumn) _headerCell('Global', width: _colLevel * scale),
          _headerCell('Tenant', width: _colLevel * scale),
          _headerCell('Site', width: _colLevel * scale),
          _headerCell('Device', width: _colLevel * scale),
        ],
      ),
    );
  }

  Widget _headerCell(
    String label, {
    required double width,
    bool alignLeft = false,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
      child: Text(
        label,
        textAlign: alignLeft ? TextAlign.left : TextAlign.center,
        style: const TextStyle(
          color: _textColor,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildRow(RecipientSummaryRow row, double scale) {
    final TextStyle nameStyle = TextStyle(
      color: _textColor,
      fontSize: 13,
      fontWeight: FontWeight.w700,
      fontStyle: row.isLegacy ? FontStyle.italic : FontStyle.normal,
    );
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _bodyCell(
            width: _colName * scale,
            alignLeft: true,
            child: Text(
              row.displayName,
              overflow: TextOverflow.ellipsis,
              style: nameStyle,
            ),
          ),
          _bodyCell(
            width: _colPhone * scale,
            alignLeft: true,
            child: Text(
              row.phoneDisplay,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _mutedColor, fontSize: 12),
            ),
          ),
          if (showGlobalColumn)
            _bodyCell(
              width: _colLevel * scale,
              child: _levelCell(row.globalValue),
            ),
          _bodyCell(
            width: _colLevel * scale,
            child: _levelCell(row.tenantValue),
          ),
          _bodyCell(width: _colLevel * scale, child: _levelCell(row.siteValue)),
          _bodyCell(
            width: _colLevel * scale,
            child: _levelCell(row.deviceValue),
          ),
        ],
      ),
    );
  }

  Widget _levelCell(String value) {
    final bool isDash = value == kRecipientSummaryNotApplicable;
    final bool isInherited = value == kRecipientSummaryInherited;
    return Text(
      value,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: isDash ? _dashColor : (isInherited ? _mutedColor : _textColor),
        fontSize: 13,
        fontWeight: isInherited ? FontWeight.w500 : FontWeight.w700,
        fontStyle: isInherited ? FontStyle.italic : FontStyle.normal,
      ),
    );
  }

  Widget _bodyCell({
    required double width,
    required Widget child,
    bool alignLeft = false,
  }) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: _borderColor)),
      ),
      alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
      child: child,
    );
  }
}
