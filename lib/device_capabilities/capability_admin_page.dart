import 'package:flutter/material.dart';
import '../services/global_board_configuration_service.dart';
import '../services/capability_profile_repository.dart';
import '../board_presets/board_preset_catalog.dart';
import '../board_presets/board_preset_metric_references.dart';
import '../ui_templates/board/template_icon_resolver.dart';
import '../ui_templates/enums/metric_display_type.dart';
import '../ui_templates/enums/metric_status_behavior.dart';
import '../ui_templates/enums/metric_transform.dart';
import 'capability_indicator_definition.dart';
import 'capability_library_store.dart';
import 'capability_metric_definition.dart';
import 'capability_records.dart';
import 'capability_reference_utils.dart';
import 'capability_validation.dart';
import 'device_capability_profile.dart';
import 'device_capability_profile_store.dart';
import 'indicator_binding.dart';
import 'metric_binding.dart';

const _labelStyle = TextStyle(color: Color(0xFF94A3B8), fontSize: 12);
const _errorStyle = TextStyle(color: Color(0xFFF87171), fontSize: 12);
const _sectionTitleStyle = TextStyle(
  color: Colors.white,
  fontWeight: FontWeight.w700,
  fontSize: 15,
);

/// N6.5.2 §10 — "Capacidades", the admin surface replacing N6.5's
/// `DeviceMetricCatalogAdminPage`: three tabs (Métricas / Indicators /
/// Perfiles), matching the architecture split (§1-§4) — a metric or
/// indicator is administered once, globally; a profile only *references*
/// them by key plus its own binding (§4/§5/§14). Owner-only, entirely
/// in-memory (§25).
class CapabilityAdminPage extends StatefulWidget {
  CapabilityAdminPage({
    super.key,
    required this.isOwner,
    MetricLibraryStore? metricLibrary,
    IndicatorLibraryStore? indicatorLibrary,
    DeviceCapabilityProfileStore? profileStore,
    BoardPresetCatalog? presetCatalog,
    GlobalBoardConfigurationService? configurationService,
  }) : metricLibrary = metricLibrary ?? MetricLibraryStore(),
       indicatorLibrary = indicatorLibrary ?? IndicatorLibraryStore(),
       profileStore = profileStore ?? DeviceCapabilityProfileStore(),
       presetCatalog = presetCatalog ?? BoardPresetCatalog(initial: const []),
       configurationService =
           configurationService ?? sharedGlobalBoardConfigurationService,
       firestoreBacked =
           metricLibrary == null &&
           indicatorLibrary == null &&
           profileStore == null &&
           presetCatalog == null;

  final bool isOwner;
  final MetricLibraryStore metricLibrary;
  final IndicatorLibraryStore indicatorLibrary;
  final DeviceCapabilityProfileStore profileStore;
  final BoardPresetCatalog presetCatalog;
  final GlobalBoardConfigurationService configurationService;
  final bool firestoreBacked;

  @override
  State<CapabilityAdminPage> createState() => _CapabilityAdminPageState();
}

class _CapabilityAdminPageState extends State<CapabilityAdminPage> {
  bool _loading = false;
  bool _hydrating = false;
  bool _syncScheduled = false;
  String? _persistenceError;
  final Map<String, CapabilityMetricRecord> _metricBaseline = {};
  final Map<String, CapabilityIndicatorRecord> _indicatorBaseline = {};
  final Map<String, CapabilityProfileRecord> _profileBaseline = {};
  String? _selectedMetricKey;
  String? _selectedIndicatorKey;
  String? _selectedProfileId;
  String? _selectedProfileMetricKey;

  final _metricLabelController = TextEditingController();
  final _metricShortLabelController = TextEditingController();
  final _metricUnitController = TextEditingController();
  final _metricDecimalsController = TextEditingController();
  final _indicatorLabelController = TextEditingController();
  final _profileNameController = TextEditingController();
  final _profileDescriptionController = TextEditingController();

  String? _syncedMetricKey;
  String? _syncedIndicatorKey;
  String? _syncedProfileId;
  String? _metricFieldError;

  @override
  void initState() {
    super.initState();
    widget.metricLibrary.addListener(_onChanged);
    widget.indicatorLibrary.addListener(_onChanged);
    widget.profileStore.addListener(_onChanged);
    if (widget.firestoreBacked) _load();
  }

  @override
  void dispose() {
    widget.metricLibrary.removeListener(_onChanged);
    widget.indicatorLibrary.removeListener(_onChanged);
    widget.profileStore.removeListener(_onChanged);
    _metricLabelController.dispose();
    _metricShortLabelController.dispose();
    _metricUnitController.dispose();
    _metricDecimalsController.dispose();
    _indicatorLabelController.dispose();
    _profileNameController.dispose();
    _profileDescriptionController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
    if (!widget.firestoreBacked || _hydrating || _syncScheduled) return;
    _syncScheduled = true;
    Future<void>.microtask(_persistChanges);
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _persistenceError = null;
    });
    try {
      final snapshot = await widget.configurationService.load(refresh: refresh);
      _hydrating = true;
      widget.metricLibrary.replaceAll(
        snapshot.metrics.where((r) => r.enabled).map((r) => r.metric),
      );
      widget.indicatorLibrary.replaceAll(
        snapshot.indicators.where((r) => r.enabled).map((r) => r.indicator),
      );
      widget.profileStore.replaceAll(
        snapshot.profiles.where((r) => r.profile.enabled).map((r) => r.profile),
      );
      widget.presetCatalog.replaceAll(
        snapshot.boardPresets.where((p) => p.enabled),
      );
      _metricBaseline
        ..clear()
        ..addEntries(snapshot.metrics.map((r) => MapEntry(r.metric.key, r)));
      _indicatorBaseline
        ..clear()
        ..addEntries(
          snapshot.indicators.map((r) => MapEntry(r.indicator.key, r)),
        );
      _profileBaseline
        ..clear()
        ..addEntries(snapshot.profiles.map((r) => MapEntry(r.profile.id, r)));
      _hydrating = false;
      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (error) {
      _hydrating = false;
      if (mounted) {
        setState(() {
          _loading = false;
          _persistenceError = '$error';
        });
      }
    }
  }

  Future<void> _persistChanges() async {
    _syncScheduled = false;
    if (mounted) setState(() => _loading = true);
    try {
      final currentMetrics = {
        for (final m in widget.metricLibrary.metrics) m.key: m,
      };
      for (final entry in currentMetrics.entries) {
        final old = _metricBaseline[entry.key];
        if (old == null) {
          await widget.configurationService.metrics.create(entry.value);
        } else if (old.metric.toMap().toString() !=
            entry.value.toMap().toString()) {
          await widget.configurationService.metrics.save(
            metric: entry.value,
            enabled: old.enabled,
            expectedVersion: old.recordVersion,
          );
        }
      }
      for (final removed in _metricBaseline.keys.toSet().difference(
        currentMetrics.keys.toSet(),
      )) {
        await widget.configurationService.metrics.setEnabled(removed, false);
      }

      final currentIndicators = {
        for (final i in widget.indicatorLibrary.indicators) i.key: i,
      };
      for (final entry in currentIndicators.entries) {
        final old = _indicatorBaseline[entry.key];
        if (old == null) {
          await widget.configurationService.indicators.create(entry.value);
        } else if (old.indicator.toMap().toString() !=
            entry.value.toMap().toString()) {
          await widget.configurationService.indicators.save(
            indicator: entry.value,
            enabled: old.enabled,
            expectedVersion: old.recordVersion,
          );
        }
      }
      for (final removed in _indicatorBaseline.keys.toSet().difference(
        currentIndicators.keys.toSet(),
      )) {
        await widget.configurationService.indicators.setEnabled(removed, false);
      }

      final currentProfiles = {
        for (final p in widget.profileStore.profiles) p.id: p,
      };
      for (final entry in currentProfiles.entries) {
        final old = _profileBaseline[entry.key];
        if (old == null) {
          await widget.configurationService.profiles.create(entry.value);
        } else if (old.profile.toMap().toString() !=
            entry.value.toMap().toString()) {
          await widget.configurationService.profiles.save(
            profile: entry.value,
            expectedVersion: old.profile.profileVersion,
          );
        }
      }
      for (final removed in _profileBaseline.keys.toSet().difference(
        currentProfiles.keys.toSet(),
      )) {
        await widget.configurationService.profiles.setEnabled(removed, false);
      }
      widget.configurationService.invalidate();
      await _load(refresh: true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _persistenceError = 'No se pudo guardar: $error';
        });
      }
    }
  }

  CapabilityMetricDefinition? get _selectedMetric {
    final key = _selectedMetricKey;
    if (key == null) return null;
    return widget.metricLibrary.byKey(key);
  }

  CapabilityIndicatorDefinition? get _selectedIndicator {
    final key = _selectedIndicatorKey;
    if (key == null) return null;
    return widget.indicatorLibrary.byKey(key);
  }

  DeviceCapabilityProfile? get _selectedProfile {
    final id = _selectedProfileId;
    if (id == null) return null;
    return widget.profileStore.byId(id);
  }

  void _syncControllers() {
    final metric = _selectedMetric;
    if (_syncedMetricKey != _selectedMetricKey) {
      _syncedMetricKey = _selectedMetricKey;
      _metricLabelController.text = metric?.label ?? '';
      _metricShortLabelController.text = metric?.shortLabel ?? '';
      _metricUnitController.text = metric?.defaultUnit ?? '';
      _metricDecimalsController.text = '${metric?.decimals ?? 0}';
      _metricFieldError = null;
    }
    final indicator = _selectedIndicator;
    if (_syncedIndicatorKey != _selectedIndicatorKey) {
      _syncedIndicatorKey = _selectedIndicatorKey;
      _indicatorLabelController.text = indicator?.label ?? '';
    }
    final profile = _selectedProfile;
    if (_syncedProfileId != _selectedProfileId) {
      _syncedProfileId = _selectedProfileId;
      _profileNameController.text = profile?.name ?? '';
      _profileDescriptionController.text = profile?.description ?? '';
      _selectedProfileMetricKey = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOwner) {
      return const Scaffold(
        body: Center(child: Text('Capacidades disponible solo para owner')),
      );
    }
    _syncControllers();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Capacidades'),
          actions: [
            if (widget.firestoreBacked)
              IconButton(
                tooltip: 'Actualizar desde Firestore',
                onPressed: _loading ? null : () => _load(refresh: true),
                icon: const Icon(Icons.refresh),
              ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(
                key: ValueKey('capability-admin-tab-metrics'),
                text: 'Métricas',
              ),
              Tab(
                key: ValueKey('capability-admin-tab-indicators'),
                text: 'Indicators',
              ),
              Tab(
                key: ValueKey('capability-admin-tab-profiles'),
                text: 'Perfiles',
              ),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (_persistenceError != null)
                    MaterialBanner(
                      content: Text(_persistenceError!),
                      actions: [
                        TextButton(
                          onPressed: () => _load(refresh: true),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _metricsTab(),
                        _indicatorsTab(),
                        _profilesTab(),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _scrollBody(Widget child) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1400),
      child: child,
    ),
  );

  Widget _twoColumn(Widget left, Widget right) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 900;
      if (wide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 360, child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [left, const SizedBox(height: 16), right],
      );
    },
  );

  Widget _panel({required String title, required List<Widget> children}) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1120),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1F2A3C)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: _sectionTitleStyle),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      );

  // ===========================================================================
  // Tab 1 — Métricas (§11)
  // ===========================================================================

  Widget _metricsTab() {
    final metrics = widget.metricLibrary.metrics;
    final selected = _selectedMetric;
    return _scrollBody(
      _twoColumn(
        _panel(
          title: 'BIBLIOTECA DE MÉTRICAS',
          children: [
            for (final metric in metrics)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: metric.key == _selectedMetricKey
                      ? const Color(0xFF1E293B)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    key: ValueKey('capability-admin-metric-${metric.key}'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () =>
                        setState(() => _selectedMetricKey = metric.key),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            metric.label,
                            style: const TextStyle(color: Colors.white),
                          ),
                          Text(
                            '${metric.key} · ${metric.displayType.wireName}'
                            '${metric.defaultUnit.isEmpty ? '' : ' · ${metric.defaultUnit}'}',
                            style: _labelStyle,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey('capability-admin-new-metric'),
              onPressed: _createMetric,
              icon: const Icon(Icons.add),
              label: const Text('Nueva métrica'),
            ),
          ],
        ),
        selected == null
            ? _panel(
                title: 'DETALLE DE MÉTRICA',
                children: const [
                  Text(
                    'Elegí una métrica para ver/editar sus detalles.',
                    style: _labelStyle,
                  ),
                ],
              )
            : _panel(
                title: 'DETALLE · ${selected.label}',
                children: [_metricEditor(selected)],
              ),
      ),
    );
  }

  Widget _metricEditor(CapabilityMetricDefinition metric) {
    void commit(CapabilityMetricDefinition next) {
      setState(() => _metricFieldError = null);
      widget.metricLibrary.upsert(next);
    }

    void fail(String message) => setState(() => _metricFieldError = message);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('metricKey: ${metric.key} (no editable)', style: _labelStyle),
        if (_metricFieldError != null) ...[
          const SizedBox(height: 4),
          Text(_metricFieldError!, style: _errorStyle),
        ],
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('capability-admin-metric-label'),
          controller: _metricLabelController,
          decoration: const InputDecoration(
            labelText: 'Label',
            helperText:
                'Nombre visible completo de la métrica (ej. "Temperatura interior")',
          ),
          onChanged: (value) {
            if (value.trim().isEmpty) {
              fail('El label no puede estar vacío');
              return;
            }
            commit(metric.copyWith(label: value.trim()));
          },
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('capability-admin-metric-short-label'),
          controller: _metricShortLabelController,
          decoration: const InputDecoration(
            labelText: 'shortLabel (opcional)',
            helperText:
                'Nombre corto para espacios reducidos (ej. "Temp. int."). '
                'Vacío = se usa el Label completo.',
          ),
          onChanged: (value) => commit(
            metric.copyWith(
              shortLabel: value.trim().isEmpty ? null : value.trim(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('capability-admin-metric-unit'),
          controller: _metricUnitController,
          decoration: const InputDecoration(
            labelText: 'Unidad por defecto (puede estar vacía)',
          ),
          onChanged: (value) => commit(metric.copyWith(defaultUnit: value)),
        ),
        const SizedBox(height: 8),
        _iconKeyPicker(
          key: const ValueKey('capability-admin-metric-icon'),
          value: metric.icon,
          onChanged: (value) => commit(metric.copyWith(icon: value)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('displayType:', style: _labelStyle),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButton<MetricDisplayType>(
                key: const ValueKey('capability-admin-metric-display-type'),
                isExpanded: true,
                value: metric.displayType,
                items: [
                  for (final type in MetricDisplayType.values)
                    DropdownMenuItem(value: type, child: Text(type.wireName)),
                ],
                onChanged: (type) {
                  if (type == null) return;
                  commit(
                    metric.copyWith(
                      displayType: type,
                      decimals: _isNumericDisplayType(type)
                          ? metric.decimals
                          : 0,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_isNumericDisplayType(metric.displayType))
          TextField(
            key: const ValueKey('capability-admin-metric-decimals'),
            controller: _metricDecimalsController,
            decoration: const InputDecoration(labelText: 'Decimales (0-20)'),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              final parsed = int.tryParse(value.trim());
              if (parsed == null || parsed < 0 || parsed > 20) {
                fail('Decimales debe ser un entero entre 0 y 20');
                return;
              }
              commit(metric.copyWith(decimals: parsed));
            },
          )
        else
          const Text(
            'Decimales no aplica: displayType no es numérico.',
            style: _labelStyle,
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('statusBehavior:', style: _labelStyle),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButton<MetricStatusBehavior>(
                key: const ValueKey('capability-admin-metric-status-behavior'),
                isExpanded: true,
                value: metric.statusBehavior,
                items: [
                  for (final behavior in MetricStatusBehavior.values)
                    DropdownMenuItem(
                      value: behavior,
                      child: Text(behavior.wireName),
                    ),
                ],
                onChanged: (behavior) {
                  if (behavior == null) return;
                  commit(metric.copyWith(statusBehavior: behavior));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          metric.statusBehavior == MetricStatusBehavior.alarmState
              ? 'alarmState: el valor cambia de color y puede marcarse como '
                    'alerta según los umbrales de alarma configurados para '
                    'esta métrica.'
              : 'none: el valor siempre se muestra en el mismo color, sin '
                    'evaluar umbrales de alarma.',
          style: _labelStyle,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('capability-admin-duplicate-metric'),
              onPressed: () => _duplicateMetric(metric),
              icon: const Icon(Icons.copy),
              label: const Text('Duplicar'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('capability-admin-delete-metric'),
              onPressed: () => _confirmDeleteMetric(metric),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Eliminar'),
            ),
          ],
        ),
      ],
    );
  }

  /// Validates before ever constructing a [MetricBinding]/[IndicatorBinding]
  /// — both throw on an invalid `sourceField` (same `CatalogValidation.source`
  /// regex the rest of the codebase uses), which must never surface as an
  /// uncaught exception from a dialog's confirm button.
  String? _sourceFieldError(String value) {
    if (value.isEmpty) return 'sourceField no puede estar vacío';
    try {
      CapabilityValidation.source(value);
      return null;
    } catch (_) {
      return 'sourceField inválido — usá un alias o clave.punteada';
    }
  }

  bool _isNumericDisplayType(MetricDisplayType type) =>
      type == MetricDisplayType.number ||
      type == MetricDisplayType.percentage ||
      type == MetricDisplayType.counter;

  String? _metricKeyError(String key, {String? ignoring}) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return 'metricKey no puede estar vacío';
    if (trimmed != key || trimmed.contains(' ')) {
      return 'metricKey no puede contener espacios';
    }
    if (trimmed != ignoring && widget.metricLibrary.byKey(trimmed) != null) {
      return 'metricKey "$trimmed" ya existe en la biblioteca';
    }
    return null;
  }

  void _createMetric() {
    final keyController = TextEditingController();
    final labelController = TextEditingController();
    final unitController = TextEditingController();
    var iconKey = templateIconKeys.first;
    var displayType = MetricDisplayType.number;
    var decimals = 0;
    String? error;
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Nueva métrica'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      key: const ValueKey('new-capability-metric-key'),
                      controller: keyController,
                      decoration: const InputDecoration(labelText: 'metricKey'),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('new-capability-metric-label'),
                      controller: labelController,
                      decoration: const InputDecoration(labelText: 'Label'),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('new-capability-metric-unit'),
                      controller: unitController,
                      decoration: const InputDecoration(
                        labelText: 'Unidad por defecto',
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<String>(
                      key: const ValueKey('new-capability-metric-icon'),
                      isExpanded: true,
                      value: iconKey,
                      items: [
                        for (final key in templateIconKeys)
                          DropdownMenuItem(value: key, child: Text(key)),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => iconKey = value ?? iconKey),
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<MetricDisplayType>(
                      key: const ValueKey('new-capability-metric-display-type'),
                      isExpanded: true,
                      value: displayType,
                      items: [
                        for (final type in MetricDisplayType.values)
                          DropdownMenuItem(
                            value: type,
                            child: Text(type.wireName),
                          ),
                      ],
                      onChanged: (type) => setDialogState(
                        () => displayType = type ?? displayType,
                      ),
                    ),
                    if (_isNumericDisplayType(displayType)) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('Decimales:', style: _labelStyle),
                          IconButton(
                            key: const ValueKey(
                              'new-capability-metric-decimals-minus',
                            ),
                            icon: const Icon(Icons.remove, size: 16),
                            onPressed: decimals > 0
                                ? () => setDialogState(() => decimals--)
                                : null,
                          ),
                          Text('$decimals'),
                          IconButton(
                            key: const ValueKey(
                              'new-capability-metric-decimals-plus',
                            ),
                            icon: const Icon(Icons.add, size: 16),
                            onPressed: () => setDialogState(() => decimals++),
                          ),
                        ],
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(error!, style: _errorStyle),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                key: const ValueKey('new-capability-metric-confirm'),
                onPressed: () {
                  final key = keyController.text.trim();
                  final label = labelController.text.trim();
                  final keyError = _metricKeyError(key);
                  if (keyError != null) {
                    setDialogState(() => error = keyError);
                    return;
                  }
                  if (label.isEmpty) {
                    setDialogState(
                      () => error = 'El label no puede estar vacío',
                    );
                    return;
                  }
                  final metric = CapabilityMetricDefinition(
                    key: key,
                    label: label,
                    defaultUnit: unitController.text,
                    icon: iconKey,
                    displayType: displayType,
                    decimals: decimals,
                  );
                  widget.metricLibrary.upsert(metric);
                  Navigator.of(context).pop();
                  setState(() => _selectedMetricKey = metric.key);
                },
                child: const Text('Crear'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _duplicateMetric(CapabilityMetricDefinition metric) {
    final newKey = '${metric.key}_copy';
    final resolvedKey = widget.metricLibrary.byKey(newKey) == null
        ? newKey
        : '${newKey}_${DateTime.now().millisecondsSinceEpoch % 10000}';
    final copy = widget.metricLibrary.duplicate(
      metric.key,
      newKey: resolvedKey,
    );
    setState(() => _selectedMetricKey = copy.key);
  }

  void _confirmDeleteMetric(CapabilityMetricDefinition metric) {
    final refs = widget.profileStore.findMetricKeyReferences(metric.key);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminar "${metric.label}"'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (refs.isNotEmpty) ...[
                Text(
                  key: const ValueKey(
                    'capability-metric-delete-reference-warning',
                  ),
                  'Está referenciada por ${refs.length} perfil(es): '
                  '${refs.map((r) => r.profileName).join(', ')}.',
                  style: _errorStyle,
                ),
                const SizedBox(height: 8),
              ] else
                const Text(
                  'No está referenciada por ningún perfil.',
                  style: _labelStyle,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('capability-metric-delete-confirm'),
            onPressed: refs.isNotEmpty
                ? null
                : () {
                    widget.metricLibrary.remove(metric.key);
                    Navigator.of(context).pop();
                    setState(() => _selectedMetricKey = null);
                  },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Tab 2 — Indicators (§12)
  // ===========================================================================

  Widget _indicatorsTab() {
    final indicators = widget.indicatorLibrary.indicators;
    final selected = _selectedIndicator;
    return _scrollBody(
      _twoColumn(
        _panel(
          title: 'BIBLIOTECA DE INDICATORS',
          children: [
            for (final indicator in indicators)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: indicator.key == _selectedIndicatorKey
                      ? const Color(0xFF1E293B)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    key: ValueKey(
                      'capability-admin-indicator-${indicator.key}',
                    ),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () =>
                        setState(() => _selectedIndicatorKey = indicator.key),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            indicator.label,
                            style: const TextStyle(color: Colors.white),
                          ),
                          Text(indicator.key, style: _labelStyle),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey('capability-admin-new-indicator'),
              onPressed: _createIndicator,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo indicator'),
            ),
          ],
        ),
        selected == null
            ? _panel(
                title: 'DETALLE DE INDICATOR',
                children: const [
                  Text(
                    'Elegí un indicator para ver/editar sus detalles.',
                    style: _labelStyle,
                  ),
                ],
              )
            : _panel(
                title: 'DETALLE · ${selected.label}',
                children: [_indicatorEditor(selected)],
              ),
      ),
    );
  }

  Widget _indicatorEditor(CapabilityIndicatorDefinition indicator) {
    void commit(CapabilityIndicatorDefinition next) =>
        widget.indicatorLibrary.upsert(next);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'indicatorKey: ${indicator.key} (no editable)',
          style: _labelStyle,
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('capability-admin-indicator-label'),
          controller: _indicatorLabelController,
          decoration: const InputDecoration(
            labelText: 'Label',
            helperText:
                'Nombre visible del indicator (ej. "Calefacción etapa 1")',
          ),
          onChanged: (value) {
            if (value.trim().isEmpty) return;
            commit(indicator.copyWith(label: value.trim()));
          },
        ),
        const SizedBox(height: 8),
        _iconKeyPicker(
          key: const ValueKey('capability-admin-indicator-icon'),
          value: indicator.defaultIcon,
          onChanged: (value) => commit(indicator.copyWith(defaultIcon: value)),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('capability-admin-duplicate-indicator'),
              onPressed: () => _duplicateIndicator(indicator),
              icon: const Icon(Icons.copy),
              label: const Text('Duplicar'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('capability-admin-delete-indicator'),
              onPressed: () => _confirmDeleteIndicator(indicator),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Eliminar'),
            ),
          ],
        ),
      ],
    );
  }

  String? _indicatorKeyError(String key, {String? ignoring}) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return 'indicatorKey no puede estar vacío';
    if (trimmed != key || trimmed.contains(' ')) {
      return 'indicatorKey no puede contener espacios';
    }
    if (trimmed != ignoring && widget.indicatorLibrary.byKey(trimmed) != null) {
      return 'indicatorKey "$trimmed" ya existe en la biblioteca';
    }
    return null;
  }

  void _createIndicator() {
    final keyController = TextEditingController();
    final labelController = TextEditingController();
    var iconKey = templateIconKeys.first;
    String? error;
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nuevo indicator'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const ValueKey('new-capability-indicator-key'),
                  controller: keyController,
                  decoration: const InputDecoration(labelText: 'indicatorKey'),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('new-capability-indicator-label'),
                  controller: labelController,
                  decoration: const InputDecoration(labelText: 'Label'),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 8),
                DropdownButton<String>(
                  key: const ValueKey('new-capability-indicator-icon'),
                  isExpanded: true,
                  value: iconKey,
                  items: [
                    for (final key in templateIconKeys)
                      DropdownMenuItem(value: key, child: Text(key)),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => iconKey = value ?? iconKey),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: _errorStyle),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const ValueKey('new-capability-indicator-confirm'),
              onPressed: () {
                final key = keyController.text.trim();
                final label = labelController.text.trim();
                final keyError = _indicatorKeyError(key);
                if (keyError != null) {
                  setDialogState(() => error = keyError);
                  return;
                }
                if (label.isEmpty) {
                  setDialogState(() => error = 'El label no puede estar vacío');
                  return;
                }
                final indicator = CapabilityIndicatorDefinition(
                  key: key,
                  label: label,
                  defaultIcon: iconKey,
                );
                widget.indicatorLibrary.upsert(indicator);
                Navigator.of(context).pop();
                setState(() => _selectedIndicatorKey = indicator.key);
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }

  void _duplicateIndicator(CapabilityIndicatorDefinition indicator) {
    final newKey = '${indicator.key}_copy';
    final resolvedKey = widget.indicatorLibrary.byKey(newKey) == null
        ? newKey
        : '${newKey}_${DateTime.now().millisecondsSinceEpoch % 10000}';
    final copy = widget.indicatorLibrary.duplicate(
      indicator.key,
      newKey: resolvedKey,
    );
    setState(() => _selectedIndicatorKey = copy.key);
  }

  void _confirmDeleteIndicator(CapabilityIndicatorDefinition indicator) {
    final refs = widget.profileStore.findIndicatorKeyReferences(indicator.key);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminar "${indicator.label}"'),
        content: SizedBox(
          width: 360,
          child: refs.isNotEmpty
              ? Text(
                  key: const ValueKey(
                    'capability-indicator-delete-reference-warning',
                  ),
                  'Está referenciado por ${refs.length} perfil(es): '
                  '${refs.map((r) => r.profileName).join(', ')}.',
                  style: _errorStyle,
                )
              : const Text(
                  'No está referenciado por ningún perfil.',
                  style: _labelStyle,
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('capability-indicator-delete-confirm'),
            onPressed: refs.isNotEmpty
                ? null
                : () {
                    widget.indicatorLibrary.remove(indicator.key);
                    Navigator.of(context).pop();
                    setState(() => _selectedIndicatorKey = null);
                  },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Tab 3 — Perfiles (§13/§14/§8)
  // ===========================================================================

  Widget _profilesTab() {
    final profiles = widget.profileStore.profiles;
    final selected = _selectedProfile;
    return _scrollBody(
      _twoColumn(
        _panel(
          title: 'PERFILES DE CAPACIDADES',
          children: [
            for (final profile in profiles)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: profile.id == _selectedProfileId
                      ? const Color(0xFF1E293B)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    key: ValueKey('capability-admin-profile-${profile.id}'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () =>
                        setState(() => _selectedProfileId = profile.id),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  profile.name,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              if (!profile.enabled)
                                const Text('deshabilitado', style: _errorStyle),
                            ],
                          ),
                          Text(
                            '${profile.id} · ${profile.metricKeys.length} métricas · '
                            '${profile.indicatorKeys.length} indicators',
                            style: _labelStyle,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey('capability-admin-new-profile'),
              onPressed: _createProfile,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo perfil'),
            ),
          ],
        ),
        selected == null
            ? _panel(
                title: 'DETALLE DE PERFIL',
                children: const [
                  Text(
                    'Elegí un perfil para ver/editar sus detalles.',
                    style: _labelStyle,
                  ),
                ],
              )
            : _panel(
                title: 'DETALLE · ${selected.name}',
                children: [_profileEditor(selected)],
              ),
      ),
    );
  }

  Widget _profileEditor(DeviceCapabilityProfile profile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('capability-admin-profile-name'),
          controller: _profileNameController,
          decoration: const InputDecoration(labelText: 'Nombre'),
          onChanged: (value) {
            if (value.trim().isEmpty) return;
            widget.profileStore.rename(profile.id, name: value.trim());
          },
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('capability-admin-profile-description'),
          controller: _profileDescriptionController,
          decoration: const InputDecoration(labelText: 'Descripción'),
          onChanged: (value) =>
              widget.profileStore.rename(profile.id, description: value),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Habilitado', style: _labelStyle),
            Switch(
              key: const ValueKey('capability-admin-profile-enabled'),
              value: profile.enabled,
              onChanged: (value) =>
                  widget.profileStore.setEnabled(profile.id, value),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('capability-admin-duplicate-profile'),
              onPressed: () {
                final copy = widget.profileStore.duplicate(profile.id);
                setState(() => _selectedProfileId = copy.id);
              },
              icon: const Icon(Icons.copy),
              label: const Text('Duplicar'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('capability-admin-delete-profile'),
              onPressed: () => _confirmDeleteProfile(profile),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Eliminar'),
            ),
          ],
        ),
        const Divider(color: Color(0xFF1F2A3C), height: 32),
        _profileMetricsSection(profile),
        const Divider(color: Color(0xFF1F2A3C), height: 32),
        _profileIndicatorsSection(profile),
        if (profile.metricKeys.isNotEmpty) ...[
          const Divider(color: Color(0xFF1F2A3C), height: 32),
          _profileSuggestedSection(profile),
        ],
      ],
    );
  }

  Widget _profileMetricsSection(DeviceCapabilityProfile profile) {
    final available = widget.metricLibrary.metrics
        .where((m) => !profile.metricKeys.contains(m.key))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Métricas del perfil', style: _sectionTitleStyle),
        const SizedBox(height: 4),
        for (final key in profile.metricKeys)
          _profileMetricRow(profile, key, widget.metricLibrary.byKey(key)),
        const SizedBox(height: 8),
        if (available.isNotEmpty)
          OutlinedButton.icon(
            key: const ValueKey('capability-admin-profile-add-metric'),
            onPressed: () => _addMetricToProfile(profile, available),
            icon: const Icon(Icons.add),
            label: const Text('Agregar métrica'),
          )
        else
          const Text(
            'Todas las métricas de la biblioteca ya están agregadas.',
            style: _labelStyle,
          ),
      ],
    );
  }

  Widget _profileMetricRow(
    DeviceCapabilityProfile profile,
    String key,
    CapabilityMetricDefinition? global,
  ) {
    final binding = profile.metricBindings[key];
    final selected = key == _selectedProfileMetricKey;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? const Color(0xFF1E293B) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      key: ValueKey('capability-admin-profile-metric-$key'),
                      onTap: () => setState(
                        () => _selectedProfileMetricKey = selected ? null : key,
                      ),
                      child: Text(
                        '${global?.label ?? key} ($key)',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  IconButton(
                    key: ValueKey(
                      'capability-admin-profile-edit-metric-binding-$key',
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => _editMetricBinding(profile, key, binding),
                  ),
                  IconButton(
                    key: ValueKey(
                      'capability-admin-profile-remove-metric-$key',
                    ),
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () =>
                        widget.profileStore.removeMetric(profile.id, key),
                  ),
                ],
              ),
              if (binding != null)
                Text('sourceField: ${binding.sourceField}', style: _labelStyle),
            ],
          ),
        ),
      ),
    );
  }

  void _addMetricToProfile(
    DeviceCapabilityProfile profile,
    List<CapabilityMetricDefinition> available,
  ) {
    var chosen = available.first.key;
    final sourceFieldController = TextEditingController();
    String? error;
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Agregar métrica al perfil'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButton<String>(
                  key: const ValueKey('capability-admin-add-metric-key'),
                  isExpanded: true,
                  value: chosen,
                  items: [
                    for (final metric in available)
                      DropdownMenuItem(
                        value: metric.key,
                        child: Text(metric.label),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => chosen = value ?? chosen),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey(
                    'capability-admin-add-metric-source-field',
                  ),
                  controller: sourceFieldController,
                  decoration: const InputDecoration(
                    labelText: 'sourceField (obligatorio)',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: _errorStyle),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const ValueKey('capability-admin-add-metric-confirm'),
              onPressed: () {
                final sourceField = sourceFieldController.text.trim();
                final fieldError = _sourceFieldError(sourceField);
                if (fieldError != null) {
                  setDialogState(() => error = fieldError);
                  return;
                }
                widget.profileStore.addMetric(
                  profile.id,
                  chosen,
                  MetricBinding(sourceField: sourceField),
                );
                Navigator.of(context).pop();
              },
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
  }

  void _editMetricBinding(
    DeviceCapabilityProfile profile,
    String metricKey,
    MetricBinding? binding,
  ) {
    final sourceFieldController = TextEditingController(
      text: binding?.sourceField ?? '',
    );
    final unitOverrideController = TextEditingController(
      text: binding?.unitOverride ?? '',
    );
    var transform = binding?.transform ?? MetricTransform.none;
    String? error;
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Binding de "$metricKey"'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const ValueKey(
                    'capability-admin-metric-binding-source-field',
                  ),
                  controller: sourceFieldController,
                  decoration: const InputDecoration(labelText: 'sourceField'),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey(
                    'capability-admin-metric-binding-unit-override',
                  ),
                  controller: unitOverrideController,
                  decoration: const InputDecoration(
                    labelText: 'unitOverride (vacío = usar el de la métrica)',
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButton<MetricTransform>(
                  key: const ValueKey(
                    'capability-admin-metric-binding-transform',
                  ),
                  isExpanded: true,
                  value: transform,
                  items: [
                    for (final t in MetricTransform.values)
                      DropdownMenuItem(value: t, child: Text(t.wireName)),
                  ],
                  onChanged: (t) =>
                      setDialogState(() => transform = t ?? transform),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: _errorStyle),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const ValueKey('capability-admin-metric-binding-confirm'),
              onPressed: () {
                final sourceField = sourceFieldController.text.trim();
                final fieldError = _sourceFieldError(sourceField);
                if (fieldError != null) {
                  setDialogState(() => error = fieldError);
                  return;
                }
                widget.profileStore.setMetricBinding(
                  profile.id,
                  metricKey,
                  MetricBinding(
                    sourceField: sourceField,
                    transform: transform,
                    unitOverride: unitOverrideController.text.trim().isEmpty
                        ? null
                        : unitOverrideController.text.trim(),
                  ),
                );
                Navigator.of(context).pop();
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileIndicatorsSection(DeviceCapabilityProfile profile) {
    final available = widget.indicatorLibrary.indicators
        .where((i) => !profile.indicatorKeys.contains(i.key))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Indicators del perfil', style: _sectionTitleStyle),
        const SizedBox(height: 4),
        for (final key in profile.indicatorKeys)
          _profileIndicatorRow(
            profile,
            key,
            widget.indicatorLibrary.byKey(key),
          ),
        const SizedBox(height: 8),
        if (available.isNotEmpty)
          OutlinedButton.icon(
            key: const ValueKey('capability-admin-profile-add-indicator'),
            onPressed: () => _addIndicatorToProfile(profile, available),
            icon: const Icon(Icons.add),
            label: const Text('Agregar indicator'),
          )
        else
          const Text(
            'Todos los indicators de la biblioteca ya están agregados.',
            style: _labelStyle,
          ),
      ],
    );
  }

  Widget _profileIndicatorRow(
    DeviceCapabilityProfile profile,
    String key,
    CapabilityIndicatorDefinition? global,
  ) {
    final binding = profile.indicatorBindings[key];
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${global?.label ?? key} ($key)',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                IconButton(
                  key: ValueKey(
                    'capability-admin-profile-edit-indicator-binding-$key',
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => _editIndicatorBinding(profile, key, binding),
                ),
                IconButton(
                  key: ValueKey(
                    'capability-admin-profile-remove-indicator-$key',
                  ),
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () =>
                      widget.profileStore.removeIndicator(profile.id, key),
                ),
              ],
            ),
            if (binding != null)
              Text('sourceField: ${binding.sourceField}', style: _labelStyle),
          ],
        ),
      ),
    );
  }

  void _addIndicatorToProfile(
    DeviceCapabilityProfile profile,
    List<CapabilityIndicatorDefinition> available,
  ) {
    var chosen = available.first.key;
    final sourceFieldController = TextEditingController();
    String? error;
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Agregar indicator al perfil'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButton<String>(
                  key: const ValueKey('capability-admin-add-indicator-key'),
                  isExpanded: true,
                  value: chosen,
                  items: [
                    for (final indicator in available)
                      DropdownMenuItem(
                        value: indicator.key,
                        child: Text(indicator.label),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => chosen = value ?? chosen),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey(
                    'capability-admin-add-indicator-source-field',
                  ),
                  controller: sourceFieldController,
                  decoration: const InputDecoration(
                    labelText: 'sourceField (obligatorio)',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: _errorStyle),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const ValueKey('capability-admin-add-indicator-confirm'),
              onPressed: () {
                final sourceField = sourceFieldController.text.trim();
                final fieldError = _sourceFieldError(sourceField);
                if (fieldError != null) {
                  setDialogState(() => error = fieldError);
                  return;
                }
                widget.profileStore.addIndicator(
                  profile.id,
                  chosen,
                  IndicatorBinding(sourceField: sourceField),
                );
                Navigator.of(context).pop();
              },
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
  }

  void _editIndicatorBinding(
    DeviceCapabilityProfile profile,
    String indicatorKey,
    IndicatorBinding? binding,
  ) {
    final sourceFieldController = TextEditingController(
      text: binding?.sourceField ?? '',
    );
    String? error;
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Binding de "$indicatorKey"'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const ValueKey(
                    'capability-admin-indicator-binding-source-field',
                  ),
                  controller: sourceFieldController,
                  decoration: const InputDecoration(labelText: 'sourceField'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: _errorStyle),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const ValueKey('capability-admin-indicator-binding-confirm'),
              onPressed: () {
                final sourceField = sourceFieldController.text.trim();
                final fieldError = _sourceFieldError(sourceField);
                if (fieldError != null) {
                  setDialogState(() => error = fieldError);
                  return;
                }
                widget.profileStore.setIndicatorBinding(
                  profile.id,
                  indicatorKey,
                  IndicatorBinding(sourceField: sourceField),
                );
                Navigator.of(context).pop();
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileSuggestedSection(DeviceCapabilityProfile profile) {
    final metricKey = _selectedProfileMetricKey;
    if (metricKey == null) {
      return const Text(
        'Elegí una métrica del perfil (arriba) para ver/editar sus indicators '
        'sugeridos.',
        style: _labelStyle,
      );
    }
    final suggested =
        profile.suggestedIndicatorsByMetric[metricKey] ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sugeridos para "$metricKey"', style: _sectionTitleStyle),
        const SizedBox(height: 4),
        const Text(
          'Son solo una sugerencia inicial para el Board Editor — nunca una '
          'restricción; cualquier indicator del perfil sigue siendo '
          'seleccionable ahí.',
          style: _labelStyle,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          children: [
            for (final key in profile.indicatorKeys)
              FilterChip(
                key: ValueKey('capability-admin-suggested-$key'),
                label: Text(key),
                selected: suggested.contains(key),
                onSelected: (selected) {
                  final next = [...suggested];
                  if (selected) {
                    next.add(key);
                  } else {
                    next.remove(key);
                  }
                  widget.profileStore.setSuggestedIndicators(
                    profile.id,
                    metricKey,
                    next,
                  );
                },
              ),
          ],
        ),
      ],
    );
  }

  void _createProfile() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final trimmed = nameController.text.trim();
          return AlertDialog(
            title: const Text('Nuevo perfil'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const ValueKey('new-capability-profile-name'),
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('new-capability-profile-description'),
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: 'Descripción'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                key: const ValueKey('new-capability-profile-confirm'),
                onPressed: trimmed.isEmpty
                    ? null
                    : () {
                        final created = widget.profileStore.create(
                          name: trimmed,
                          description: descriptionController.text.trim(),
                        );
                        Navigator.of(context).pop();
                        setState(() => _selectedProfileId = created.id);
                      },
                child: const Text('Crear'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteProfile(DeviceCapabilityProfile profile) {
    final refs = widget.presetCatalog.findProfileReferences(profile.id);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminar "${profile.name}"'),
        content: SizedBox(
          width: 360,
          child: refs.isNotEmpty
              ? Text(
                  key: const ValueKey(
                    'capability-profile-delete-reference-warning',
                  ),
                  'Está referenciado por ${refs.length} BoardPreset(s): '
                  '${refs.map((r) => r.presetName).join(', ')}.',
                  style: _errorStyle,
                )
              : const Text(
                  'No está referenciado por ningún BoardPreset.',
                  style: _labelStyle,
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('capability-profile-delete-confirm'),
            onPressed: refs.isNotEmpty
                ? null
                : () {
                    widget.profileStore.delete(profile.id);
                    Navigator.of(context).pop();
                    setState(() => _selectedProfileId = null);
                  },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  Widget _iconKeyPicker({
    required Key key,
    required String value,
    required ValueChanged<String> onChanged,
  }) => Row(
    children: [
      const Text('icon:', style: _labelStyle),
      const SizedBox(width: 8),
      Expanded(
        child: DropdownButton<String>(
          key: key,
          isExpanded: true,
          value: value,
          items: [
            for (final iconKey in templateIconKeys)
              DropdownMenuItem(
                value: iconKey,
                child: Row(
                  children: [
                    Icon(resolveTemplateIcon(iconKey), size: 18),
                    const SizedBox(width: 8),
                    Text(iconKey),
                  ],
                ),
              ),
          ],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      ),
    ],
  );
}
