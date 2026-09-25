import 'package:flutter/material.dart';

import '../services/device_template_repository.dart';
import '../services/firestore_error_messages.dart';
import '../ui_templates/catalog/agro_ui_templates.dart';
import '../ui_templates/enums/board_slot_size.dart';
import '../ui_templates/enums/metric_status_behavior.dart';
import '../ui_templates/models/device_template.dart';
import '../ui_templates/models/device_template_record.dart';
import '../ui_templates/models/board_slot.dart';
import '../ui_templates/models/metric_definition.dart';
import '../ui_templates/models/table_column.dart';

class TemplateManagementPage extends StatefulWidget {
  const TemplateManagementPage({
    super.key,
    this.repository = const DeviceTemplateRepository(),
  });

  final DeviceTemplateRepository repository;

  @override
  State<TemplateManagementPage> createState() => _TemplateManagementPageState();
}

class _TemplateManagementPageState extends State<TemplateManagementPage> {
  bool _loading = true;
  String? _errorMessage;
  List<DeviceTemplateRecord> _remoteRecords = const <DeviceTemplateRecord>[];

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final List<DeviceTemplateRecord> records = await widget.repository
          .fetchTemplates();
      if (!mounted) return;
      setState(() {
        _remoteRecords = records;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'No se pudieron cargar los templates: ${describeFirestoreError(error)}';
        _loading = false;
      });
    }
  }

  Future<void> _editTemplate(_TemplateEditorRow row) async {
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _TemplateEditorDialog(row: row, repository: widget.repository),
    );
    if (saved != true || !mounted) return;
    await _loadTemplates();
  }

  Future<void> _resetToLocal(_TemplateEditorRow row) async {
    final DeviceTemplate? localTemplate = row.localTemplate;
    if (localTemplate == null) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restaurar desde plantilla local'),
        content: const Text(
          'Esto reemplazará la configuración remota actual por la definición local incluida en la app.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.resetTemplateToLocal(
        template: localTemplate,
        enabled: row.enabled,
        description: row.description,
        tags: row.tags,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Template restaurado.')));
      await _loadTemplates();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo sincronizar: ${describeFirestoreError(error)}',
          ),
        ),
      );
    }
  }

  List<_TemplateEditorRow> _rows() {
    final Map<String, DeviceTemplateRecord> remoteById =
        <String, DeviceTemplateRecord>{
          for (final DeviceTemplateRecord record in _remoteRecords)
            record.template.id: record,
        };
    return <_TemplateEditorRow>[
      for (final DeviceTemplate template in agroUiTemplates)
        _TemplateEditorRow(
          template: remoteById[template.id]?.template ?? template,
          localTemplate: template,
          record: remoteById[template.id],
        ),
      for (final DeviceTemplateRecord record in _remoteRecords)
        if (!agroUiTemplates.any(
          (DeviceTemplate template) => template.id == record.template.id,
        ))
          _TemplateEditorRow(
            template: record.template,
            localTemplate: null,
            record: record,
          ),
    ]..sort((a, b) => a.template.id.compareTo(b.template.id));
  }

  @override
  Widget build(BuildContext context) {
    final List<_TemplateEditorRow> rows = _rows();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Templates UI'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _loadTemplates,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _TemplateErrorState(
              message: _errorMessage!,
              onRetry: _loadTemplates,
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) => _TemplateRowCard(
                row: rows[index],
                onEdit: () => _editTemplate(rows[index]),
                onResetToLocal: rows[index].localTemplate == null
                    ? null
                    : () => _resetToLocal(rows[index]),
              ),
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemCount: rows.length,
            ),
    );
  }
}

class _TemplateEditorRow {
  const _TemplateEditorRow({
    required this.template,
    required this.localTemplate,
    required this.record,
  });

  final DeviceTemplate template;
  final DeviceTemplate? localTemplate;
  final DeviceTemplateRecord? record;

  bool get hasRemote => record != null;
  bool get enabled => record?.enabled ?? true;
  int? get templateVersion => record?.templateVersion;
  String? get description => record?.description;
  List<String> get tags => record?.tags ?? const <String>[];
}

class _TemplateRowCard extends StatelessWidget {
  const _TemplateRowCard({
    required this.row,
    required this.onEdit,
    required this.onResetToLocal,
  });

  final _TemplateEditorRow row;
  final VoidCallback onEdit;
  final VoidCallback? onResetToLocal;

  @override
  Widget build(BuildContext context) {
    final TextStyle? labelStyle = Theme.of(context).textTheme.labelMedium;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        row.template.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(row.template.id, style: labelStyle),
                    ],
                  ),
                ),
                _StatusChip(
                  label: row.hasRemote ? 'Remoto' : 'Local',
                  color: row.hasRemote ? Colors.green : Colors.blueGrey,
                ),
                const SizedBox(width: 8),
                _StatusChip(
                  label: row.enabled ? 'Activo' : 'Inactivo',
                  color: row.enabled ? Colors.teal : Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: <Widget>[
                Text('Version: ${row.templateVersion ?? '-'}'),
                Text('Metrics: ${row.template.metrics.length}'),
                Text('Slots: ${row.template.boardSlots.length}'),
                Text('Columnas: ${row.template.tableColumns.length}'),
                Text('Preset: ${row.template.boardPreset.wireName}'),
              ],
            ),
            if (row.description != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(row.description!),
            ],
            if (row.tags.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: <Widget>[
                  for (final String tag in row.tags) Chip(label: Text(tag)),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: row.hasRemote ? onEdit : null,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Editar'),
                ),
                FilledButton.tonalIcon(
                  onPressed: onResetToLocal,
                  icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                  label: Text(
                    row.hasRemote
                        ? 'Restaurar desde plantilla local'
                        : 'Crear remoto',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateEditorDialog extends StatefulWidget {
  const _TemplateEditorDialog({required this.row, required this.repository});

  final _TemplateEditorRow row;
  final DeviceTemplateRepository repository;

  @override
  State<_TemplateEditorDialog> createState() => _TemplateEditorDialogState();
}

class _TemplateEditorDialogState extends State<_TemplateEditorDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 4,
    vsync: this,
  );
  late DeviceTemplateRecord _baseRecord = widget.row.record!;
  late bool _enabled = widget.row.enabled;
  late final TextEditingController _nameController = TextEditingController(
    text: widget.row.template.name,
  );
  late final TextEditingController _descriptionController =
      TextEditingController(text: widget.row.description ?? '');
  late final TextEditingController _tagsController = TextEditingController(
    text: widget.row.tags.join(', '),
  );
  late List<_MetricEditState> _metrics = _metricStates(
    widget.row.template.metrics,
  );
  late List<_BoardSlotEditState> _boardSlots = _boardSlotStates(
    widget.row.template.boardSlots,
  );
  late List<_TableColumnEditState> _tableColumns = _tableColumnStates(
    widget.row.template.tableColumns,
  );
  bool _saving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    for (final _MetricEditState metric in _metrics) {
      metric.dispose();
    }
    for (final _TableColumnEditState column in _tableColumns) {
      column.dispose();
    }
    super.dispose();
  }

  bool get _dirty {
    final DeviceTemplate current = _buildTemplate();
    return current.toMap().toString() !=
            _baseRecord.template.toMap().toString() ||
        _enabled != _baseRecord.enabled ||
        _descriptionController.text.trim() != (_baseRecord.description ?? '') ||
        _tags().join(',') != _baseRecord.tags.join(',');
  }

  Future<void> _close() async {
    if (!_dirty) {
      Navigator.of(context).pop(false);
      return;
    }
    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descartar cambios'),
        content: const Text('Hay cambios sin guardar.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Seguir editando'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      Navigator.of(context).pop(false);
    }
  }

  Future<void> _reload() async {
    final DeviceTemplateRecord? fresh = await widget.repository.fetchTemplate(
      _baseRecord.template.id,
    );
    if (fresh == null || !mounted) return;
    setState(() {
      _baseRecord = fresh;
      _enabled = fresh.enabled;
      _nameController.text = fresh.template.name;
      _descriptionController.text = fresh.description ?? '';
      _tagsController.text = fresh.tags.join(', ');
      for (final _MetricEditState metric in _metrics) {
        metric.dispose();
      }
      for (final _TableColumnEditState column in _tableColumns) {
        column.dispose();
      }
      _metrics = _metricStates(fresh.template.metrics);
      _boardSlots = _boardSlotStates(fresh.template.boardSlots);
      _tableColumns = _tableColumnStates(fresh.template.tableColumns);
      _errorMessage = null;
    });
  }

  Future<void> _save() async {
    final String? validationError = _validate();
    if (validationError != null) {
      setState(() => _errorMessage = validationError);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.saveTemplate(
        template: _buildTemplate(),
        expectedTemplateVersion: _baseRecord.templateVersion,
        enabled: _enabled,
        description: _descriptionController.text,
        tags: _tags(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DeviceTemplateVersionConflict catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage =
            'El template cambió en Firestore (v${error.actualVersion}). Recargá antes de guardar.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = 'No se pudo guardar: ${describeFirestoreError(error)}';
      });
    }
  }

  List<String> _tags() {
    return _tagsController.text
        .split(',')
        .map((String tag) => tag.trim())
        .where((String tag) => tag.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  String? _validate() {
    if (_nameController.text.trim().isEmpty) {
      return 'El nombre no puede estar vacío.';
    }
    final Set<int> orders = <int>{};
    for (final _TableColumnEditState column in _tableColumns) {
      final int? order = int.tryParse(column.orderController.text.trim());
      if (order == null || order < 0) {
        return 'El orden de tabla debe ser numérico y no negativo.';
      }
      if (!orders.add(order)) {
        return 'No se permiten órdenes duplicados en Tabla.';
      }
    }
    try {
      _buildTemplate();
    } catch (error) {
      return 'Template inválido: $error';
    }
    return null;
  }

  DeviceTemplate _buildTemplate() {
    return DeviceTemplate(
      id: _baseRecord.template.id,
      name: _nameController.text.trim(),
      boardPreset: _baseRecord.template.boardPreset,
      metrics: <MetricDefinition>[
        for (int i = 0; i < _metrics.length; i++)
          _metrics[i].toMetric(_baseRecord.template.metrics[i]),
      ],
      indicators: _baseRecord.template.indicators,
      boardSlots: <BoardSlot>[
        for (int i = 0; i < _boardSlots.length; i++)
          _boardSlots[i].toSlot(_baseRecord.template.boardSlots[i]),
      ],
      tableSection: _baseRecord.template.tableSection,
      tableColumns: <TableColumn>[
        for (int i = 0; i < _tableColumns.length; i++)
          _tableColumns[i].toColumn(_baseRecord.template.tableColumns[i]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_baseRecord.template.id),
      content: SizedBox(
        width: 860,
        height: 620,
        child: Column(
          children: <Widget>[
            TabBar(
              controller: _tabController,
              tabs: const <Widget>[
                Tab(text: 'General'),
                Tab(text: 'Métricas'),
                Tab(text: 'Tablero'),
                Tab(text: 'Tabla'),
              ],
            ),
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: 12),
              _InlineError(
                message: _errorMessage!,
                onReload: _errorMessage!.contains('Recarg') ? _reload : null,
              ),
            ],
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: <Widget>[
                  _GeneralTemplateEditor(
                    enabled: _enabled,
                    onEnabledChanged: _saving
                        ? null
                        : (bool value) => setState(() => _enabled = value),
                    nameController: _nameController,
                    descriptionController: _descriptionController,
                    tagsController: _tagsController,
                    record: _baseRecord,
                  ),
                  _MetricsTemplateEditor(
                    metrics: _metrics,
                    originals: _baseRecord.template.metrics,
                    saving: _saving,
                    onChanged: () => setState(() {}),
                  ),
                  _BoardSlotsTemplateEditor(
                    slots: _boardSlots,
                    originals: _baseRecord.template.boardSlots,
                    metricLabels: _metricLabels(),
                    saving: _saving,
                    onChanged: () => setState(() {}),
                  ),
                  _TableColumnsTemplateEditor(
                    columns: _tableColumns,
                    originals: _baseRecord.template.tableColumns,
                    metricLabels: _metricLabels(),
                    saving: _saving,
                    onChanged: () => setState(() {}),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : _close,
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }

  Map<String, String> _metricLabels() {
    return <String, String>{
      for (final _MetricEditState metric in _metrics)
        metric.originalKey: metric.labelController.text.trim().isEmpty
            ? metric.originalKey
            : metric.labelController.text.trim(),
    };
  }
}

class _MetricEditState {
  _MetricEditState(MetricDefinition metric)
    : originalKey = metric.key,
      labelController = TextEditingController(text: metric.label),
      shortLabelController = TextEditingController(
        text: metric.shortLabel ?? '',
      ),
      unitController = TextEditingController(text: metric.unit),
      decimalsController = TextEditingController(
        text: metric.decimals.toString(),
      ),
      statusBehavior = metric.statusBehavior;

  final String originalKey;
  final TextEditingController labelController;
  final TextEditingController shortLabelController;
  final TextEditingController unitController;
  final TextEditingController decimalsController;
  MetricStatusBehavior statusBehavior;

  MetricDefinition toMetric(MetricDefinition original) {
    return MetricDefinition(
      key: original.key,
      label: labelController.text.trim(),
      shortLabel: shortLabelController.text.trim().isEmpty
          ? null
          : shortLabelController.text.trim(),
      unit: unitController.text.trim(),
      icon: original.icon,
      sourceField: original.sourceField,
      valueLabelSourceField: original.valueLabelSourceField,
      displayType: original.displayType,
      decimals: int.tryParse(decimalsController.text.trim()) ?? -1,
      transform: original.transform,
      statusBehavior: statusBehavior,
    );
  }

  void dispose() {
    labelController.dispose();
    shortLabelController.dispose();
    unitController.dispose();
    decimalsController.dispose();
  }
}

class _BoardSlotEditState {
  _BoardSlotEditState(BoardSlot slot)
    : visible = slot.visible,
      showLabel = slot.showLabel,
      showIcon = slot.showIcon,
      size = slot.size;

  bool visible;
  bool showLabel;
  bool showIcon;
  BoardSlotSize size;

  BoardSlot toSlot(BoardSlot original) {
    return BoardSlot(
      metricKey: original.metricKey,
      position: original.position,
      size: size,
      visible: visible,
      showLabel: showLabel,
      showIcon: showIcon,
      indicators: original.indicators,
    );
  }
}

class _TableColumnEditState {
  _TableColumnEditState(TableColumn column)
    : visible = column.visible,
      orderController = TextEditingController(text: column.order.toString());

  bool visible;
  final TextEditingController orderController;

  TableColumn toColumn(TableColumn original) {
    return TableColumn(
      metricKey: original.metricKey,
      order: int.tryParse(orderController.text.trim()) ?? -1,
      width: original.width,
      visible: visible,
      indicators: original.indicators,
    );
  }

  void dispose() {
    orderController.dispose();
  }
}

List<_MetricEditState> _metricStates(List<MetricDefinition> metrics) {
  return metrics.map(_MetricEditState.new).toList(growable: false);
}

List<_BoardSlotEditState> _boardSlotStates(List<BoardSlot> slots) {
  return slots.map(_BoardSlotEditState.new).toList(growable: false);
}

List<_TableColumnEditState> _tableColumnStates(List<TableColumn> columns) {
  return columns.map(_TableColumnEditState.new).toList(growable: false);
}

class _GeneralTemplateEditor extends StatelessWidget {
  const _GeneralTemplateEditor({
    required this.enabled,
    required this.onEnabledChanged,
    required this.nameController,
    required this.descriptionController,
    required this.tagsController,
    required this.record,
  });

  final bool enabled;
  final ValueChanged<bool>? onEnabledChanged;
  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final TextEditingController tagsController;
  final DeviceTemplateRecord record;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 16),
      children: <Widget>[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Template activo'),
          value: enabled,
          onChanged: onEnabledChanged,
        ),
        TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: descriptionController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Descripción'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: tagsController,
          decoration: const InputDecoration(labelText: 'Tags'),
        ),
        const SizedBox(height: 18),
        _ReadOnlyFields(
          fields: <String, String>{
            'id': record.template.id,
            'schemaVersion': record.schemaVersion.toString(),
            'templateVersion': record.templateVersion.toString(),
            'createdAt': record.createdAt?.toIso8601String() ?? '-',
            'updatedAt': record.updatedAt?.toIso8601String() ?? '-',
            'boardPreset': record.template.boardPreset.wireName,
          },
        ),
      ],
    );
  }
}

class _MetricsTemplateEditor extends StatelessWidget {
  const _MetricsTemplateEditor({
    required this.metrics,
    required this.originals,
    required this.saving,
    required this.onChanged,
  });

  final List<_MetricEditState> metrics;
  final List<MetricDefinition> originals;
  final bool saving;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 16),
      itemCount: metrics.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final _MetricEditState state = metrics[index];
        final MetricDefinition original = originals[index];
        return _EditorPanel(
          title: original.key,
          subtitle: 'sourceField: ${original.sourceField}',
          child: Column(
            children: <Widget>[
              _ReadOnlyFields(
                fields: <String, String>{
                  'key': original.key,
                  'sourceField': original.sourceField,
                  'displayType': original.displayType.wireName,
                  'transform': original.transform.wireName,
                  'icon': original.icon,
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: state.labelController,
                      enabled: !saving,
                      decoration: const InputDecoration(labelText: 'Label'),
                      onChanged: (_) => onChanged(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: state.shortLabelController,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'Short label',
                      ),
                      onChanged: (_) => onChanged(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: state.unitController,
                      enabled: !saving,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      onChanged: (_) => onChanged(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: state.decimalsController,
                      enabled: !saving,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Decimals'),
                      onChanged: (_) => onChanged(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<MetricStatusBehavior>(
                      initialValue: state.statusBehavior,
                      decoration: const InputDecoration(
                        labelText: 'Status behavior',
                      ),
                      items: <DropdownMenuItem<MetricStatusBehavior>>[
                        for (final MetricStatusBehavior behavior
                            in MetricStatusBehavior.values)
                          DropdownMenuItem<MetricStatusBehavior>(
                            value: behavior,
                            child: Text(behavior.wireName),
                          ),
                      ],
                      onChanged: saving
                          ? null
                          : (MetricStatusBehavior? value) {
                              if (value == null) return;
                              state.statusBehavior = value;
                              onChanged();
                            },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BoardSlotsTemplateEditor extends StatelessWidget {
  const _BoardSlotsTemplateEditor({
    required this.slots,
    required this.originals,
    required this.metricLabels,
    required this.saving,
    required this.onChanged,
  });

  final List<_BoardSlotEditState> slots;
  final List<BoardSlot> originals;
  final Map<String, String> metricLabels;
  final bool saving;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 16),
      itemCount: slots.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final _BoardSlotEditState state = slots[index];
        final BoardSlot original = originals[index];
        return _EditorPanel(
          title: metricLabels[original.metricKey] ?? original.metricKey,
          subtitle: 'metricKey: ${original.metricKey}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _ReadOnlyFields(
                fields: <String, String>{
                  'position': original.position.toString(),
                  'indicators': original.indicators.join(', '),
                },
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  FilterChip(
                    label: const Text('Visible'),
                    selected: state.visible,
                    onSelected: saving
                        ? null
                        : (bool value) {
                            state.visible = value;
                            onChanged();
                          },
                  ),
                  FilterChip(
                    label: const Text('Show label'),
                    selected: state.showLabel,
                    onSelected: saving
                        ? null
                        : (bool value) {
                            state.showLabel = value;
                            onChanged();
                          },
                  ),
                  FilterChip(
                    label: const Text('Show icon'),
                    selected: state.showIcon,
                    onSelected: saving
                        ? null
                        : (bool value) {
                            state.showIcon = value;
                            onChanged();
                          },
                  ),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<BoardSlotSize>(
                      initialValue: state.size,
                      decoration: const InputDecoration(labelText: 'Size'),
                      items: <DropdownMenuItem<BoardSlotSize>>[
                        for (final BoardSlotSize size in BoardSlotSize.values)
                          DropdownMenuItem<BoardSlotSize>(
                            value: size,
                            child: Text(size.wireName),
                          ),
                      ],
                      onChanged: saving
                          ? null
                          : (BoardSlotSize? value) {
                              if (value == null) return;
                              state.size = value;
                              onChanged();
                            },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TableColumnsTemplateEditor extends StatelessWidget {
  const _TableColumnsTemplateEditor({
    required this.columns,
    required this.originals,
    required this.metricLabels,
    required this.saving,
    required this.onChanged,
  });

  final List<_TableColumnEditState> columns;
  final List<TableColumn> originals;
  final Map<String, String> metricLabels;
  final bool saving;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 16),
      itemCount: columns.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final _TableColumnEditState state = columns[index];
        final TableColumn original = originals[index];
        return _EditorPanel(
          title: metricLabels[original.metricKey] ?? original.metricKey,
          subtitle: 'metricKey: ${original.metricKey}',
          child: Row(
            children: <Widget>[
              Expanded(
                child: _ReadOnlyFields(
                  fields: <String, String>{
                    'width': original.width.wireName,
                    'indicators': original.indicators.join(', '),
                  },
                ),
              ),
              const SizedBox(width: 12),
              FilterChip(
                label: const Text('Visible'),
                selected: state.visible,
                onSelected: saving
                    ? null
                    : (bool value) {
                        state.visible = value;
                        onChanged();
                      },
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: state.orderController,
                  enabled: !saving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Orden'),
                  onChanged: (_) => onChanged(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EditorPanel extends StatelessWidget {
  const _EditorPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyFields extends StatelessWidget {
  const _ReadOnlyFields({required this.fields});

  final Map<String, String> fields;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final MapEntry<String, String> entry in fields.entries)
          InputChip(
            label: Text(
              '${entry.key}: ${entry.value.isEmpty ? '-' : entry.value}',
            ),
            onPressed: null,
          ),
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, this.onReload});

  final String message;
  final VoidCallback? onReload;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(message)),
            if (onReload != null)
              TextButton.icon(
                onPressed: onReload,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Recargar'),
              ),
          ],
        ),
      ),
    );
  }
}

class _TemplateErrorState extends StatelessWidget {
  const _TemplateErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final MaterialColor color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: TextStyle(
            color: color.shade800,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
