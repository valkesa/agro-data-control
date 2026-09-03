import 'package:flutter/material.dart';

import '../services/device_template_repository.dart';
import '../services/firestore_error_messages.dart';
import '../ui_templates/catalog/agro_ui_templates.dart';
import '../ui_templates/models/device_template.dart';
import '../ui_templates/models/device_template_record.dart';

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

  Future<void> _editMetadata(_TemplateEditorRow row) async {
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _TemplateMetadataDialog(row: row, repository: widget.repository),
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
        title: const Text('Sincronizar template local'),
        content: Text(
          'Se va a reemplazar el documento remoto "${row.template.id}" por '
          'la definicion local actual.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sincronizar'),
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
      ).showSnackBar(const SnackBar(content: Text('Template sincronizado.')));
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
                onEdit: () => _editMetadata(rows[index]),
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
                  label: const Text('Metadata'),
                ),
                FilledButton.tonalIcon(
                  onPressed: onResetToLocal,
                  icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                  label: Text(
                    row.hasRemote ? 'Sincronizar local' : 'Crear remoto',
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

class _TemplateMetadataDialog extends StatefulWidget {
  const _TemplateMetadataDialog({required this.row, required this.repository});

  final _TemplateEditorRow row;
  final DeviceTemplateRepository repository;

  @override
  State<_TemplateMetadataDialog> createState() =>
      _TemplateMetadataDialogState();
}

class _TemplateMetadataDialogState extends State<_TemplateMetadataDialog> {
  late bool _enabled = widget.row.enabled;
  late final TextEditingController _descriptionController =
      TextEditingController(text: widget.row.description ?? '');
  late final TextEditingController _tagsController = TextEditingController(
    text: widget.row.tags.join(', '),
  );
  bool _saving = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.repository.updateTemplateMetadata(
        templateId: widget.row.template.id,
        enabled: _enabled,
        description: _descriptionController.text,
        tags: _tagsController.text
            .split(',')
            .map((String tag) => tag.trim())
            .where((String tag) => tag.isNotEmpty)
            .toList(growable: false),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar: ${describeFirestoreError(error)}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.row.template.id),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Template activo'),
              value: _enabled,
              onChanged: _saving
                  ? null
                  : (bool value) => setState(() => _enabled = value),
            ),
            TextField(
              controller: _descriptionController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Descripcion'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tagsController,
              decoration: const InputDecoration(labelText: 'Tags'),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
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
