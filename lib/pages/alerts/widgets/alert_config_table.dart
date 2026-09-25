import 'package:flutter/material.dart';

import '../../../models/hierarchical_alert_catalog.dart';
import '../../../models/hierarchical_alert_config.dart';

const Color _borderColor = Color(0xFF334155);
const Color _headerColor = Color(0xFF1E293B);
const Color _cellColor = Color(0xFF0F172A);
const Color _textColor = Color(0xFFE5E7EB);
const Color _mutedColor = Color(0xFF94A3B8);
const Color _dashColor = Color(0xFF64748B);

// Anchos BASE (sin escalar) — pedido del usuario (2026-09-08): la tabla debe
// ensancharse/angostarse con el resize de la ventana en vez de quedar en un
// ancho fijo. `build()` calcula un factor de escala vía LayoutBuilder y lo
// aplica a estos anchos: si hay más espacio disponible que el ancho base
// total, la tabla crece para ocupar todo el ancho (sin scroll horizontal);
// si hay menos, se usan los anchos base y aparece scroll horizontal (igual
// que antes).
const double _colOrder = 40;
const double _colAlert = 200;
// Pedido del usuario (2026-09-09): todas las columnas salvo "#" y "Alerta"
// comparten un único ancho angosto (antes variaban entre 60 y 96px, lo que
// generaba un grid disparejo y forzaba scroll horizontal en pantallas
// normales).
const double _colUniform = 68;
const double _colBool = _colUniform;
const double _colDelay = _colUniform;
const double _colCooldown = _colUniform;
const double _colThreshold = _colUniform;
const double _colSensorFailure = _colUniform;
const double _colMargin = _colUniform;

/// Key determinística por celda (`alertId` + nombre de campo) — pública
/// para que los widget tests puedan targetear una celda exacta en vez de
/// depender de orden/posición en el árbol (la tabla tiene ~9 filas × ~11
/// columnas, muchas con controles del mismo tipo).
Key alertCellKey(String alertId, String field) =>
    ValueKey('alert-cell-$alertId-$field');

const List<String> _thresholdFieldOrder = <String>[
  'min',
  'max',
  'sensorFailureMin',
  'margin',
];

double _thresholdColumnWidth(String field) {
  return switch (field) {
    'sensorFailureMin' => _colSensorFailure,
    'margin' => _colMargin,
    _ => _colThreshold,
  };
}

String _thresholdColumnLabel(String field) {
  return switch (field) {
    'min' => 'Min',
    'max' => 'Max',
    'sensorFailureMin' => 'Min falla\nsensor',
    'margin' => 'Margen',
    _ => field,
  };
}

double? _thresholdValueOf(AlertThresholds t, String field) {
  return switch (field) {
    'min' => t.min,
    'max' => t.max,
    'margin' => t.margin,
    'sensorFailureMin' => t.sensorFailureMin,
    _ => null,
  };
}

AlertThresholds _thresholdsWith(
  AlertThresholds t,
  String field,
  double? value,
) {
  return switch (field) {
    'min' => AlertThresholds(
      min: value,
      max: t.max,
      margin: t.margin,
      sensorFailureMin: t.sensorFailureMin,
    ),
    'max' => AlertThresholds(
      min: t.min,
      max: value,
      margin: t.margin,
      sensorFailureMin: t.sensorFailureMin,
    ),
    'margin' => AlertThresholds(
      min: t.min,
      max: t.max,
      margin: value,
      sensorFailureMin: t.sensorFailureMin,
    ),
    'sensorFailureMin' => AlertThresholds(
      min: t.min,
      max: t.max,
      margin: t.margin,
      sensorFailureMin: value,
    ),
    _ => t,
  };
}

const String _delayTooltip =
    'Minutos que la alerta debe permanecer activa antes de enviar el '
    'primer WhatsApp.';
const String _cooldownTooltip =
    'Tiempo mínimo que debe pasar para volver a enviar el WhatsApp de esta '
    'alerta, aunque la condición se cumpla de nuevo antes.';

/// Vista de tabla de "Configuración → Alertas (jerárquico)" — pedido del
/// usuario (2026-09-08) para reemplazar las cards expandibles por una
/// grilla densa, todo visible a la vez, muy similar al diálogo legacy
/// (`_AlertSettingsTable` en `main.dart`).
///
/// No reimplementa NINGUNA regla de negocio: solo cambia la presentación.
/// El resolver de herencia, el diff de qué se guarda, y el link de campos
/// espejados (`AlertDefinition.thresholdLinks`) son exactamente los mismos
/// que ya usaba `AlertConfigCard` — esta tabla llama a las mismas
/// funciones/callbacks provistos por la pantalla padre.
class AlertConfigTable extends StatelessWidget {
  const AlertConfigTable({
    super.key,
    required this.definitions,
    required this.canEdit,
    required this.effectiveFor,
    required this.draftFor,
    required this.onFieldChanged,
    required this.resolveLinkedAlert,
  });

  final List<AlertDefinition> definitions;
  final bool canEdit;

  /// Efectivo ACTUAL de una alerta (ya considerando cualquier draft sin
  /// guardar de esta misma pantalla, no solo lo último leído de Firestore).
  final EffectiveAlertConfig Function(String alertId) effectiveFor;

  /// Draft actual de una alerta en el scope que se está editando — `null`
  /// en un campo significa "sigue heredando ese campo".
  final AlertConfigOverride Function(String alertId) draftFor;

  final void Function(
    String alertId,
    AlertConfigOverride Function(AlertConfigOverride current) update,
  )
  onFieldChanged;

  final EffectiveAlertConfig Function(String alertId) resolveLinkedAlert;

  static double get _totalBaseWidth =>
      _colOrder +
      _colAlert +
      _colBool * 3 +
      _colDelay +
      _colCooldown +
      _thresholdFieldOrder
          .map(_thresholdColumnWidth)
          .fold(0.0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double totalBaseWidth = _totalBaseWidth;
        final double available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : totalBaseWidth;
        // Si hay más ancho disponible que el que ocupa la tabla en su
        // tamaño base, se escala hacia arriba para ocupar todo el ancho.
        // Si hay menos, se usa el tamaño base y aparece scroll horizontal —
        // nunca se achica por debajo del base, para que los campos sigan
        // siendo usables. El SingleChildScrollView queda SIEMPRE presente
        // (aunque el contenido ya ocupe todo el ancho, no molesta) para
        // que un cálculo de `scale` desactualizado (p. ej. durante un
        // resize) nunca produzca un overflow visual — a lo sumo deja un
        // scroll de 0px.
        final double scale = available > totalBaseWidth
            ? available / totalBaseWidth
            : 1.0;
        final Widget table = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGroupHeaderRow(scale),
            _buildColumnHeaderRow(scale),
            for (final AlertDefinition definition in definitions)
              _buildAlertRow(definition, scale),
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

  /// "Umbrales" (Etapa 2026-09-08, pedido del usuario) va únicamente arriba
  /// de Min/Max — "Min falla sensor" y "Margen" quedan sin agrupador,
  /// porque conceptualmente no son parte del mismo par min/max de una
  /// alerta con rango.
  Widget _buildGroupHeaderRow(double scale) {
    return Container(
      color: _headerColor,
      child: Row(
        children: [
          SizedBox(
            width:
                (_colOrder +
                    _colAlert +
                    _colBool * 3 +
                    _colDelay +
                    _colCooldown) *
                scale,
          ),
          _headerCell('Umbrales', width: (_colThreshold * 2) * scale),
          SizedBox(width: (_colSensorFailure + _colMargin) * scale),
        ],
      ),
    );
  }

  Widget _buildColumnHeaderRow(double scale) {
    return Container(
      decoration: const BoxDecoration(
        color: _headerColor,
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        children: [
          _headerCell('#', width: _colOrder * scale),
          _headerCell('Alerta', width: _colAlert * scale, alignLeft: true),
          _headerCell('Activada', width: _colBool * scale),
          _headerCell('Mostrar\nen App', width: _colBool * scale),
          _headerCell('WhatsApp', width: _colBool * scale),
          _headerCell(
            'Delay WA\nmin',
            width: _colDelay * scale,
            tooltip: _delayTooltip,
          ),
          _headerCell(
            'Cooldown\nmin',
            width: _colCooldown * scale,
            tooltip: _cooldownTooltip,
          ),
          for (final String field in _thresholdFieldOrder)
            _headerCell(
              _thresholdColumnLabel(field),
              width: _thresholdColumnWidth(field) * scale,
            ),
        ],
      ),
    );
  }

  Widget _headerCell(
    String label, {
    required double width,
    bool alignLeft = false,
    String? tooltip,
  }) {
    final Widget content = Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
      alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
      child: Text(
        label,
        textAlign: alignLeft ? TextAlign.left : TextAlign.center,
        style: const TextStyle(
          color: _textColor,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    if (tooltip == null) return content;
    return Tooltip(message: tooltip, child: content);
  }

  Widget _buildAlertRow(AlertDefinition definition, double scale) {
    final EffectiveAlertConfig effective = effectiveFor(definition.id);
    final AlertConfigOverride draft = draftFor(definition.id);
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _bodyCell(
            width: _colOrder * scale,
            child: _CompactIntCell(
              key: alertCellKey(definition.id, 'order'),
              value: draft.order,
              effectiveValue: effective.order,
              enabled: canEdit,
              onChanged: (v) =>
                  onFieldChanged(definition.id, (c) => c.copyWith(order: v)),
            ),
          ),
          _bodyCell(
            width: _colAlert * scale,
            alignLeft: true,
            child: Text(
              definition.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _textColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _bodyCell(
            width: _colBool * scale,
            child: _CompactBoolCell(
              key: alertCellKey(definition.id, 'enabled'),
              value: draft.enabled,
              effectiveValue: effective.enabled,
              enabled: canEdit,
              onChanged: (v) =>
                  onFieldChanged(definition.id, (c) => c.copyWith(enabled: v)),
            ),
          ),
          _bodyCell(
            width: _colBool * scale,
            child: definition.supportsVisual
                ? _CompactBoolCell(
                    key: alertCellKey(definition.id, 'visualEnabled'),
                    value: draft.visualEnabled,
                    effectiveValue: effective.visualEnabled,
                    enabled: canEdit,
                    onChanged: (v) => onFieldChanged(
                      definition.id,
                      (c) => c.copyWith(visualEnabled: v),
                    ),
                  )
                : const _DashCell(),
          ),
          _bodyCell(
            width: _colBool * scale,
            child: definition.supportsWhatsapp
                ? _CompactBoolCell(
                    key: alertCellKey(definition.id, 'whatsappEnabled'),
                    value: draft.whatsappEnabled,
                    effectiveValue: effective.whatsappEnabled,
                    enabled: canEdit,
                    onChanged: (v) => onFieldChanged(
                      definition.id,
                      (c) => c.copyWith(whatsappEnabled: v),
                    ),
                  )
                : const _DashCell(),
          ),
          _bodyCell(
            width: _colDelay * scale,
            child: definition.supportsWhatsappDelay
                ? _CompactIntCell(
                    key: alertCellKey(definition.id, 'whatsappDelayMinutes'),
                    value: draft.whatsappDelayMinutes,
                    effectiveValue: effective.whatsappDelayMinutes,
                    enabled: canEdit,
                    onChanged: (v) => onFieldChanged(
                      definition.id,
                      (c) => c.copyWith(whatsappDelayMinutes: v),
                    ),
                  )
                : const _DashCell(),
          ),
          _bodyCell(
            width: _colCooldown * scale,
            child: _CompactIntCell(
              key: alertCellKey(definition.id, 'cooldownMinutes'),
              value: draft.cooldownMinutes,
              effectiveValue: effective.cooldownMinutes,
              enabled: canEdit,
              onChanged: (v) => onFieldChanged(
                definition.id,
                (c) => c.copyWith(cooldownMinutes: v),
              ),
            ),
          ),
          for (final String field in _thresholdFieldOrder)
            _bodyCell(
              width: _thresholdColumnWidth(field) * scale,
              child: _buildThresholdCell(definition, draft, effective, field),
            ),
        ],
      ),
    );
  }

  Widget _buildThresholdCell(
    AlertDefinition definition,
    AlertConfigOverride draft,
    EffectiveAlertConfig effective,
    String field,
  ) {
    if (!definition.applicableThresholdFields.contains(field)) {
      return const _DashCell();
    }
    final String? linkedAlertId = definition.thresholdLinks[field];
    if (linkedAlertId != null) {
      final EffectiveAlertConfig linked = resolveLinkedAlert(linkedAlertId);
      return _LinkedCell(
        key: alertCellKey(definition.id, 'threshold.$field'),
        value: _thresholdValueOf(linked.thresholds, field),
      );
    }
    return _CompactDoubleCell(
      key: alertCellKey(definition.id, 'threshold.$field'),
      value: _thresholdValueOf(draft.thresholds, field),
      effectiveValue: _thresholdValueOf(effective.thresholds, field),
      enabled: canEdit,
      onChanged: (v) => onFieldChanged(
        definition.id,
        (c) => c.copyWith(thresholds: _thresholdsWith(c.thresholds, field, v)),
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
      constraints: const BoxConstraints(minHeight: 46),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: _borderColor)),
      ),
      alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
      child: child,
    );
  }
}

class _DashCell extends StatelessWidget {
  const _DashCell();

  @override
  Widget build(BuildContext context) {
    return const Text(
      '-',
      style: TextStyle(
        color: _dashColor,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// Valor heredado de OTRA alerta (`AlertDefinition.thresholdLinks`) —
/// nunca editable acá, en itálica para distinguirlo de un valor propio,
/// igual criterio visual que el excel de referencia del usuario.
class _LinkedCell extends StatelessWidget {
  const _LinkedCell({super.key, required this.value});

  final double? value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value?.toString() ?? '-',
      style: const TextStyle(
        color: _mutedColor,
        fontSize: 13,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// Switch compacto Sí/No con reset a "Heredar" — mismo criterio que el
/// resto de la app: tocar el switch siempre pasa a un valor explícito
/// propio de este scope (nunca hace falta "confirmar" el valor ya
/// mostrado, un Switch solo dispara `onChanged` al cambiar de estado); el
/// ícono de reset solo aparece cuando ya hay un override propio.
class _CompactBoolCell extends StatelessWidget {
  const _CompactBoolCell({
    super.key,
    required this.value,
    required this.effectiveValue,
    required this.enabled,
    required this.onChanged,
  });

  final bool? value;
  final bool effectiveValue;
  final bool enabled;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final bool displayed = value ?? effectiveValue;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.scale(
          scale: 0.72,
          child: Switch(
            value: displayed,
            onChanged: enabled ? (v) => onChanged(v) : null,
          ),
        ),
        if (value != null)
          SizedBox(
            height: 18,
            child: IconButton(
              tooltip: 'Volver a heredar',
              icon: const Icon(Icons.replay, size: 13),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 22, height: 18),
              visualDensity: VisualDensity.compact,
              color: _mutedColor,
              onPressed: enabled ? () => onChanged(null) : null,
            ),
          ),
      ],
    );
  }
}

InputDecoration _compactDecoration() {
  return const InputDecoration(
    isDense: true,
    contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    filled: true,
    fillColor: Color(0xFF111827),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(6)),
      borderSide: BorderSide(color: Color(0xFF475569)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(6)),
      borderSide: BorderSide(color: Color(0xFF475569)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(6)),
      borderSide: BorderSide(color: Color(0xFF38BDF8)),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(6)),
      borderSide: BorderSide(color: Color(0xFF334155)),
    ),
  );
}

class _CompactIntCell extends StatefulWidget {
  const _CompactIntCell({
    super.key,
    required this.value,
    required this.effectiveValue,
    required this.enabled,
    required this.onChanged,
  });

  final int? value;
  final int effectiveValue;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  @override
  State<_CompactIntCell> createState() => _CompactIntCellState();
}

class _CompactIntCellState extends State<_CompactIntCell> {
  late final TextEditingController _controller = TextEditingController(
    text: (widget.value ?? widget.effectiveValue).toString(),
  );

  @override
  void didUpdateWidget(covariant _CompactIntCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String text = (widget.value ?? widget.effectiveValue).toString();
    if (_controller.text != text) _controller.text = text;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: _controller,
        enabled: widget.enabled,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        style: TextStyle(
          color: widget.enabled ? _textColor : _dashColor,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
        decoration: _compactDecoration(),
        onChanged: (text) {
          final int? parsed = int.tryParse(text.trim());
          if (parsed == null) return;
          widget.onChanged(parsed == widget.effectiveValue ? null : parsed);
        },
      ),
    );
  }
}

class _CompactDoubleCell extends StatefulWidget {
  const _CompactDoubleCell({
    super.key,
    required this.value,
    required this.effectiveValue,
    required this.enabled,
    required this.onChanged,
  });

  final double? value;
  final double? effectiveValue;
  final bool enabled;
  final ValueChanged<double?> onChanged;

  @override
  State<_CompactDoubleCell> createState() => _CompactDoubleCellState();
}

class _CompactDoubleCellState extends State<_CompactDoubleCell> {
  late final TextEditingController _controller = TextEditingController(
    text: (widget.value ?? widget.effectiveValue)?.toString() ?? '',
  );

  @override
  void didUpdateWidget(covariant _CompactDoubleCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String text =
        (widget.value ?? widget.effectiveValue)?.toString() ?? '';
    if (_controller.text != text) _controller.text = text;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: _controller,
        enabled: widget.enabled,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: TextStyle(
          color: widget.enabled ? _textColor : _dashColor,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
        decoration: _compactDecoration(),
        onChanged: (text) {
          if (text.trim().isEmpty) {
            widget.onChanged(null);
            return;
          }
          final double? parsed = double.tryParse(text.trim());
          if (parsed == null) return;
          widget.onChanged(parsed == widget.effectiveValue ? null : parsed);
        },
      ),
    );
  }
}
