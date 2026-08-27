import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/cerdas_models.dart';
import '../services/cerdas_repository.dart';
import '../ui_templates/models/device_template.dart';

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

class CerdasModule extends StatelessWidget {
  const CerdasModule({
    super.key,
    required this.tenantId,
    required this.siteId,
    this.plc1Id,
    this.plc2Id,
    this.plc1Label = 'M1',
    this.plc2Label = 'M2',
    this.cerdas1ContextKey,
    this.cerdas2ContextKey,
    this.userIdentity,
    CerdasRepository? repository,
  }) : repository = repository ?? _repository;

  final String? tenantId;
  final String? siteId;
  final String? plc1Id;
  final String? plc2Id;
  final String plc1Label;
  final String plc2Label;
  final CerdasContextKey? cerdas1ContextKey;
  final CerdasContextKey? cerdas2ContextKey;
  final CerdasUserIdentity? userIdentity;
  final CerdasRepository repository;

  static const CerdasRepository _repository = CerdasRepository();

  @override
  Widget build(BuildContext context) {
    final String? tenantId = this.tenantId;
    final String? siteId = this.siteId;
    if (tenantId == null ||
        tenantId.isEmpty ||
        siteId == null ||
        siteId.isEmpty) {
      return const _FooterMessage(
        text: 'Sin contexto Firestore para cargar cerdas.',
        color: Color(0xFF94A3B8),
      );
    }

    final CerdasContextKey? key1 =
        cerdas1ContextKey ??
        (plc1Id != null && plc1Id!.isNotEmpty
            ? CerdasContextKey.legacy(
                tenantId: tenantId,
                siteId: siteId,
                plcId: plc1Id!,
              )
            : null);
    final CerdasContextKey? key2 =
        cerdas2ContextKey ??
        (plc2Id != null && plc2Id!.isNotEmpty
            ? CerdasContextKey.legacy(
                tenantId: tenantId,
                siteId: siteId,
                plcId: plc2Id!,
              )
            : null);

    if (key1 == null && key2 == null) {
      return const _FooterMessage(
        text: 'Sin salas configuradas.',
        color: Color(0xFF94A3B8),
      );
    }

    return _CerdasContent(
      tenantId: tenantId,
      siteId: siteId,
      cerdas1Key: key1,
      cerdas2Key: key2,
      plc1Label: plc1Label,
      plc2Label: plc2Label,
      repository: repository,
      userIdentity: userIdentity,
    );
  }
}

class CerdasUserIdentity {
  const CerdasUserIdentity({required this.uid, required this.name});

  final String uid;
  final String name;
}

class CerdasControlEntry {
  const CerdasControlEntry({required this.label, required this.contextKey});

  final String label;
  final CerdasContextKey contextKey;
}

bool deviceTemplateSupportsCerdasControl(DeviceTemplate template) {
  return template.metrics.any((metric) => metric.key == 'sowCount');
}

class CerdasDynamicModule extends StatefulWidget {
  const CerdasDynamicModule({
    super.key,
    required this.tenantId,
    required this.siteId,
    required this.entries,
    this.userIdentity,
    CerdasRepository? repository,
  }) : repository = repository ?? CerdasModule._repository;

  final String tenantId;
  final String siteId;
  final List<CerdasControlEntry> entries;
  final CerdasUserIdentity? userIdentity;
  final CerdasRepository repository;

  @override
  State<CerdasDynamicModule> createState() => _CerdasDynamicModuleState();
}

class _CerdasDynamicModuleState extends State<CerdasDynamicModule> {
  void _openDialog(CerdasControlEntry entry, String type) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MovementDialog(
        tenantId: widget.tenantId,
        siteId: widget.siteId,
        cerdasKey: entry.contextKey,
        plcLabel: entry.label,
        type: type,
        repository: widget.repository,
        userIdentity: widget.userIdentity,
      ),
    );
  }

  void _openHistoryDialog(CerdasControlEntry entry) {
    showDialog<void>(
      context: context,
      builder: (_) => _HistoryDialog(
        plcLabel: entry.label,
        stream: widget.repository.watchPigMovementsForKey(
          entry.contextKey,
          limit: 50,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<CerdasControlEntry> entries = widget.entries;
    if (entries.isEmpty) {
      return const _FooterMessage(
        text: 'Sin salas configuradas.',
        color: Color(0xFF94A3B8),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < entries.length; i++)
          _DynamicCerdasEntryRow(
            key: Key('cerdas-dynamic-row-${entries[i].contextKey.debugLabel}'),
            entry: entries[i],
            repository: widget.repository,
            backgroundColor: i.isEven
                ? const Color(0xFF0F172A)
                : const Color(0xFF1E293B),
            onIngreso: () => _openDialog(entries[i], 'in'),
            onEgreso: () => _openDialog(entries[i], 'out'),
            onHistory: () => _openHistoryDialog(entries[i]),
          ),
      ],
    );
  }
}

class _DynamicCerdasEntryRow extends StatefulWidget {
  const _DynamicCerdasEntryRow({
    super.key,
    required this.entry,
    required this.repository,
    required this.backgroundColor,
    required this.onIngreso,
    required this.onEgreso,
    required this.onHistory,
  });

  final CerdasControlEntry entry;
  final CerdasRepository repository;
  final Color backgroundColor;
  final VoidCallback onIngreso;
  final VoidCallback onEgreso;
  final VoidCallback onHistory;

  @override
  State<_DynamicCerdasEntryRow> createState() => _DynamicCerdasEntryRowState();
}

class _DynamicCerdasEntryRowState extends State<_DynamicCerdasEntryRow> {
  late Stream<PigStatsRecord?> _statsStream;

  @override
  void initState() {
    super.initState();
    _statsStream = widget.repository.watchPigStatsForKey(
      widget.entry.contextKey,
    );
  }

  @override
  void didUpdateWidget(covariant _DynamicCerdasEntryRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.entry.contextKey != widget.entry.contextKey) {
      _statsStream = widget.repository.watchPigStatsForKey(
        widget.entry.contextKey,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PigStatsRecord?>(
      stream: _statsStream,
      builder: (BuildContext context, AsyncSnapshot<PigStatsRecord?> snapshot) {
        final int? count = snapshot.data?.currentCount;
        return Container(
          margin: const EdgeInsets.only(bottom: 2),
          color: widget.backgroundColor,
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
          child: Row(
            children: <Widget>[
              Expanded(
                flex: 4,
                child: Text(
                  widget.entry.label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData
                      ? '--'
                      : count == null
                      ? 'Sin datos'
                      : '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF38BDF8),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _ActionIcons(
                onIngreso: widget.onIngreso,
                onEgreso: widget.onEgreso,
                onHistory: widget.onHistory,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Widget that owns all streams — two-column layout matching other modules
// ---------------------------------------------------------------------------

class _CerdasContent extends StatefulWidget {
  const _CerdasContent({
    required this.tenantId,
    required this.siteId,
    this.cerdas1Key,
    this.cerdas2Key,
    required this.plc1Label,
    required this.plc2Label,
    required this.repository,
    this.userIdentity,
  });

  final String tenantId;
  final String siteId;
  final CerdasContextKey? cerdas1Key;
  final CerdasContextKey? cerdas2Key;
  final String plc1Label;
  final String plc2Label;
  final CerdasRepository repository;
  final CerdasUserIdentity? userIdentity;

  @override
  State<_CerdasContent> createState() => _CerdasContentState();
}

class _CerdasContentState extends State<_CerdasContent> {
  Stream<PigStatsRecord?>? _plc1StatsStream;
  Stream<List<PigMovementRecord>>? _plc1MovementsStream;
  Stream<PigStatsRecord?>? _plc2StatsStream;
  Stream<List<PigMovementRecord>>? _plc2MovementsStream;

  @override
  void initState() {
    super.initState();
    if (widget.cerdas1Key != null) {
      _plc1StatsStream = widget.repository.watchPigStatsForKey(
        widget.cerdas1Key!,
      );
      _plc1MovementsStream = widget.repository.watchPigMovementsForKey(
        widget.cerdas1Key!,
      );
    }
    if (widget.cerdas2Key != null) {
      _plc2StatsStream = widget.repository.watchPigStatsForKey(
        widget.cerdas2Key!,
      );
      _plc2MovementsStream = widget.repository.watchPigMovementsForKey(
        widget.cerdas2Key!,
      );
    }
  }

  void _openDialog(
    BuildContext ctx,
    CerdasContextKey key,
    String plcLabel,
    String type,
  ) {
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => _MovementDialog(
        tenantId: widget.tenantId,
        siteId: widget.siteId,
        cerdasKey: key,
        plcLabel: plcLabel,
        type: type,
        repository: widget.repository,
        userIdentity: widget.userIdentity,
      ),
    );
  }

  void _openHistoryDialog(
    BuildContext ctx,
    CerdasContextKey key,
    String plcLabel,
  ) {
    showDialog<void>(
      context: ctx,
      builder: (_) => _HistoryDialog(
        plcLabel: plcLabel,
        stream: widget.repository.watchPigMovementsForKey(key, limit: 50),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Wrap in two null-safe StreamBuilders and compose rows
    final Stream<PigStatsRecord?> plc1Stats =
        _plc1StatsStream ?? const Stream<PigStatsRecord?>.empty();
    final Stream<List<PigMovementRecord>> plc1Movements =
        _plc1MovementsStream ?? const Stream<List<PigMovementRecord>>.empty();
    final Stream<PigStatsRecord?> plc2Stats =
        _plc2StatsStream ?? const Stream<PigStatsRecord?>.empty();
    final Stream<List<PigMovementRecord>> plc2Movements =
        _plc2MovementsStream ?? const Stream<List<PigMovementRecord>>.empty();

    return StreamBuilder<PigStatsRecord?>(
      stream: plc1Stats,
      builder: (_, AsyncSnapshot<PigStatsRecord?> s1) =>
          StreamBuilder<List<PigMovementRecord>>(
            stream: plc1Movements,
            builder: (_, AsyncSnapshot<List<PigMovementRecord>> m1) =>
                StreamBuilder<PigStatsRecord?>(
                  stream: plc2Stats,
                  builder: (_, AsyncSnapshot<PigStatsRecord?> s2) =>
                      StreamBuilder<List<PigMovementRecord>>(
                        stream: plc2Movements,
                        builder:
                            (
                              BuildContext context,
                              AsyncSnapshot<List<PigMovementRecord>> m2,
                            ) => _buildRows(context, s1, m1, s2, m2),
                      ),
                ),
          ),
    );
  }

  Widget _buildRows(
    BuildContext context,
    AsyncSnapshot<PigStatsRecord?> s1,
    AsyncSnapshot<List<PigMovementRecord>> m1,
    AsyncSnapshot<PigStatsRecord?> s2,
    AsyncSnapshot<List<PigMovementRecord>> m2,
  ) {
    final int count1 = s1.data?.currentCount ?? 0;
    final int count2 = s2.data?.currentCount ?? 0;
    final bool loading1 =
        s1.connectionState == ConnectionState.waiting && !s1.hasData;
    final bool loading2 =
        s2.connectionState == ConnectionState.waiting && !s2.hasData;

    final String? error1 = s1.hasError
        ? 'Error: ${s1.error}'
        : m1.hasError
        ? 'Error: ${m1.error}'
        : null;
    final String? error2 = s2.hasError
        ? 'Error: ${s2.error}'
        : m2.hasError
        ? 'Error: ${m2.error}'
        : null;

    final CerdasContextKey? key1 = widget.cerdas1Key;
    final CerdasContextKey? key2 = widget.cerdas2Key;

    int i = 0;
    Color rc() =>
        (i++ % 2 == 0) ? const Color(0xFF0F172A) : const Color(0xFF1E293B);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // ── Stock actual ──────────────────────────────────────────────────
        _CerdasRow(
          label: 'Stock actual',
          backgroundColor: rc(),
          m1Child: loading1
              ? const _ValueText('--', color: Color(0xFF94A3B8))
              : _ValueText(
                  '$count1 ${count1 == 1 ? 'cerda' : 'cerdas'}',
                  color: const Color(0xFF38BDF8),
                  bold: true,
                ),
          m2Child: loading2
              ? const _ValueText('--', color: Color(0xFF94A3B8))
              : _ValueText(
                  '$count2 ${count2 == 1 ? 'cerda' : 'cerdas'}',
                  color: const Color(0xFF38BDF8),
                  bold: true,
                ),
        ),

        // ── Acciones ──────────────────────────────────────────────────────
        _CerdasRow(
          label: '',
          backgroundColor: rc(),
          m1Child: key1 != null
              ? _ActionIcons(
                  onIngreso: () =>
                      _openDialog(context, key1, widget.plc1Label, 'in'),
                  onEgreso: () =>
                      _openDialog(context, key1, widget.plc1Label, 'out'),
                  onHistory: () =>
                      _openHistoryDialog(context, key1, widget.plc1Label),
                )
              : const SizedBox.shrink(),
          m2Child: key2 != null
              ? _ActionIcons(
                  onIngreso: () =>
                      _openDialog(context, key2, widget.plc2Label, 'in'),
                  onEgreso: () =>
                      _openDialog(context, key2, widget.plc2Label, 'out'),
                  onHistory: () =>
                      _openHistoryDialog(context, key2, widget.plc2Label),
                )
              : const SizedBox.shrink(),
        ),

        // ── Errores ───────────────────────────────────────────────────────
        if (error1 != null || error2 != null)
          _CerdasRow(
            label: '',
            backgroundColor: null,
            m1Child: error1 != null
                ? _ValueText(error1, color: const Color(0xFFFCA5A5))
                : const SizedBox.shrink(),
            m2Child: error2 != null
                ? _ValueText(error2, color: const Color(0xFFFCA5A5))
                : const SizedBox.shrink(),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pig count widget used in collapsed section header (extraWidget)
// ---------------------------------------------------------------------------

class CerdasPigCountWidget extends StatefulWidget {
  const CerdasPigCountWidget({
    super.key,
    required this.tenantId,
    required this.siteId,
    required this.plcId,
  });

  final String tenantId;
  final String siteId;
  final String plcId;

  static const CerdasRepository _repository = CerdasRepository();

  @override
  State<CerdasPigCountWidget> createState() => _CerdasPigCountWidgetState();
}

class _CerdasPigCountWidgetState extends State<CerdasPigCountWidget> {
  late final Stream<PigStatsRecord?> _stream;

  @override
  void initState() {
    super.initState();
    _stream = CerdasPigCountWidget._repository.watchPigStats(
      tenantId: widget.tenantId,
      siteId: widget.siteId,
      plcId: widget.plcId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PigStatsRecord?>(
      stream: _stream,
      builder: (BuildContext context, AsyncSnapshot<PigStatsRecord?> snap) {
        final int? count = snap.data?.currentCount;
        return Text(
          count == null ? '--' : '$count',
          style: const TextStyle(
            color: Color(0xFF38BDF8),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Movement dialog (ingreso and egreso)
// ---------------------------------------------------------------------------

class _MovementDialog extends StatefulWidget {
  const _MovementDialog({
    required this.tenantId,
    required this.siteId,
    required this.cerdasKey,
    required this.plcLabel,
    required this.type,
    required this.repository,
    this.userIdentity,
  });

  final String tenantId;
  final String siteId;
  final CerdasContextKey cerdasKey;
  final String plcLabel;
  final String type;
  final CerdasRepository repository;
  final CerdasUserIdentity? userIdentity;

  @override
  State<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends State<_MovementDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _quantityController = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _errorMessage;

  late final Stream<List<PigExitReasonRecord>> _reasonsStream;
  PigExitReasonRecord? _selectedReason;

  bool get _isOut => widget.type == 'out';

  @override
  void initState() {
    super.initState();
    _reasonsStream = widget.repository.watchPigExitReasons(
      tenantId: widget.tenantId,
      siteId: widget.siteId,
    );
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  CerdasUserIdentity? get _currentUser {
    final CerdasUserIdentity? userIdentity = widget.userIdentity;
    if (userIdentity != null) {
      return userIdentity;
    }
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return null;
    }
    return CerdasUserIdentity(
      uid: user.uid,
      name: user.displayName ?? user.email ?? user.uid,
    );
  }

  Future<void> _save(List<PigExitReasonRecord> reasons) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_isOut && _selectedReason == null) {
      setState(() {
        _errorMessage = 'Seleccioná un motivo de egreso.';
      });
      return;
    }

    final CerdasUserIdentity? user = _currentUser;
    if (user == null) {
      setState(() {
        _errorMessage = 'Usuario no autenticado.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      await widget.repository.addPigMovementForKey(
        widget.cerdasKey,
        type: widget.type,
        date: _date,
        quantity: int.parse(_quantityController.text.trim()),
        reasonId: _isOut ? _selectedReason?.reasonId : null,
        reasonName: _isOut ? _selectedReason?.name : null,
        userId: user.uid,
        userName: user.name,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorMessage = 'Error inesperado: $e';
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) {
      setState(() {
        _date = picked;
      });
    }
  }

  Future<void> _addNewReason() async {
    final TextEditingController ctrl = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          'Nuevo motivo de egreso',
          style: TextStyle(color: Color(0xFFE5E7EB), fontSize: 14),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(color: Color(0xFFE5E7EB), fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'Nombre del motivo',
            hintStyle: TextStyle(color: Color(0xFF94A3B8)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF334155)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF38BDF8)),
            ),
          ),
          onSubmitted: (String v) {
            if (v.trim().isNotEmpty) Navigator.of(ctx).pop(v.trim());
          },
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
          ),
          TextButton(
            onPressed: () {
              final String v = ctrl.text.trim();
              if (v.isNotEmpty) Navigator.of(ctx).pop(v);
            },
            child: const Text(
              'Agregar',
              style: TextStyle(color: Color(0xFF38BDF8)),
            ),
          ),
        ],
      ),
    );
    ctrl.dispose();

    if (name == null || name.isEmpty || !mounted) return;

    final CerdasUserIdentity? user = _currentUser;
    if (user == null) return;

    try {
      final PigExitReasonRecord newReason = await widget.repository
          .addPigExitReason(
            tenantId: widget.tenantId,
            siteId: widget.siteId,
            name: name,
            userId: user.uid,
          );
      if (mounted) {
        setState(() {
          _selectedReason = newReason;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'No se pudo crear el motivo: $e';
        });
      }
    }
  }

  String _formatDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final String title = _isOut
        ? 'Registrar egreso — ${widget.plcLabel}'
        : 'Registrar ingreso — ${widget.plcLabel}';

    return Dialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF334155)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFFE5E7EB),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              StreamBuilder<List<PigExitReasonRecord>>(
                stream: _reasonsStream,
                builder: (_, AsyncSnapshot<List<PigExitReasonRecord>> snap) =>
                    _buildForm(snap.data ?? const <PigExitReasonRecord>[]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm(List<PigExitReasonRecord> reasons) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Fecha
          _FormLabel('Fecha'),
          const SizedBox(height: 4),
          InkWell(
            onTap: _saving ? null : _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.calendar_today_outlined,
                    color: Color(0xFF94A3B8),
                    size: 14,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDate(_date),
                    style: const TextStyle(
                      color: Color(0xFFE5E7EB),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Cantidad
          _FormLabel('Cantidad'),
          const SizedBox(height: 4),
          TextFormField(
            controller: _quantityController,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            style: const TextStyle(color: Color(0xFFE5E7EB), fontSize: 13),
            decoration: _inputDecoration('Ej: 10'),
            validator: (String? value) {
              if (value == null || value.trim().isEmpty) {
                return 'Ingresá una cantidad.';
              }
              final int? n = int.tryParse(value.trim());
              if (n == null || n <= 0) {
                return 'La cantidad debe ser mayor a 0.';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),

          // Motivo (solo egreso)
          if (_isOut) ...<Widget>[
            Row(
              children: <Widget>[
                const _FormLabel('Motivo'),
                const Spacer(),
                Tooltip(
                  message: 'Agregar nuevo motivo',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _saving ? null : _addNewReason,
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(
                        Icons.add_circle_outline,
                        color: Color(0xFF38BDF8),
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _ReasonDropdown(
              reasons: reasons,
              selectedReason: _selectedReason,
              enabled: !_saving,
              onChanged: (PigExitReasonRecord? r) {
                setState(() {
                  _selectedReason = r;
                  _errorMessage = null;
                });
              },
            ),
            const SizedBox(height: 12),
          ],

          // Usuario (solo lectura)
          _FormLabel('Usuario'),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Text(
              _currentUser?.name ?? '—',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),

          // Error
          if (_errorMessage != null) ...<Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF3B1313),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFEF4444)),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Botones
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
              ),
              _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF38BDF8),
                      ),
                    )
                  : FilledButton(
                      onPressed: () => _save(reasons),
                      style: FilledButton.styleFrom(
                        backgroundColor: _isOut
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF22C55E),
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(fontSize: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        _isOut ? 'Registrar egreso' : 'Registrar ingreso',
                      ),
                    ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reason dropdown
// ---------------------------------------------------------------------------

class _ReasonDropdown extends StatelessWidget {
  const _ReasonDropdown({
    required this.reasons,
    required this.selectedReason,
    required this.enabled,
    required this.onChanged,
  });

  final List<PigExitReasonRecord> reasons;
  final PigExitReasonRecord? selectedReason;
  final bool enabled;
  final ValueChanged<PigExitReasonRecord?> onChanged;

  @override
  Widget build(BuildContext context) {
    final List<PigExitReasonRecord> effectiveReasons = <PigExitReasonRecord>[
      ...reasons,
      if (selectedReason != null &&
          !reasons.any(
            (PigExitReasonRecord r) => r.reasonId == selectedReason!.reasonId,
          ))
        selectedReason!,
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DropdownButton<String>(
        value: selectedReason?.reasonId,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        style: const TextStyle(color: Color(0xFFE5E7EB), fontSize: 13),
        dropdownColor: const Color(0xFF1E293B),
        hint: const Text(
          'Seleccioná un motivo',
          style: TextStyle(color: Color(0xFF475569), fontSize: 13),
        ),
        icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF94A3B8)),
        items: effectiveReasons.map((PigExitReasonRecord r) {
          return DropdownMenuItem<String>(
            value: r.reasonId,
            child: Text(
              r.name,
              style: const TextStyle(color: Color(0xFFE5E7EB), fontSize: 13),
            ),
          );
        }).toList(),
        onChanged: enabled
            ? (String? value) {
                final PigExitReasonRecord? found = effectiveReasons
                    .where((PigExitReasonRecord r) => r.reasonId == value)
                    .firstOrNull;
                onChanged(found);
              }
            : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent movements history box
// ---------------------------------------------------------------------------

class _HistoryDialog extends StatelessWidget {
  const _HistoryDialog({required this.plcLabel, required this.stream});

  final String plcLabel;
  final Stream<List<PigMovementRecord>> stream;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF334155)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 500),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.history, color: Color(0xFF94A3B8), size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Historial — $plcLabel',
                    style: const TextStyle(
                      color: Color(0xFFE5E7EB),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close,
                        color: Color(0xFF94A3B8),
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: Color(0xFF334155), height: 1),
              const SizedBox(height: 8),
              Flexible(
                child: StreamBuilder<List<PigMovementRecord>>(
                  stream: stream,
                  builder:
                      (
                        BuildContext context,
                        AsyncSnapshot<List<PigMovementRecord>> snap,
                      ) {
                        if (snap.connectionState == ConnectionState.waiting &&
                            !snap.hasData) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF38BDF8),
                              ),
                            ),
                          );
                        }
                        if (snap.hasError) {
                          return Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              'Error: ${snap.error}',
                              style: const TextStyle(
                                color: Color(0xFFFCA5A5),
                                fontSize: 12,
                              ),
                            ),
                          );
                        }
                        final List<PigMovementRecord> movements =
                            snap.data ?? const <PigMovementRecord>[];
                        if (movements.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Sin movimientos registrados.',
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 12,
                              ),
                            ),
                          );
                        }
                        return ListView.separated(
                          shrinkWrap: true,
                          itemCount: movements.length,
                          separatorBuilder: (_, _) => const Divider(
                            color: Color(0xFF1E3148),
                            height: 1,
                          ),
                          itemBuilder: (BuildContext context, int index) {
                            final PigMovementRecord m = movements[index];
                            final Color typeColor = m.isIn
                                ? const Color(0xFF22C55E)
                                : const Color(0xFFEF4444);
                            final String sign = m.isIn ? '+' : '−';
                            final String dateLabel = m.date != null
                                ? '${_two(m.date!.day)}/${_two(m.date!.month)}/${m.date!.year}'
                                : '--';
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: <Widget>[
                                  Text(
                                    '$sign${m.quantity}',
                                    style: TextStyle(
                                      color: typeColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          dateLabel,
                                          style: const TextStyle(
                                            color: Color(0xFFE5E7EB),
                                            fontSize: 12,
                                          ),
                                        ),
                                        if (m.isOut && m.reasonName != null)
                                          Text(
                                            m.reasonName!,
                                            style: const TextStyle(
                                              color: Color(0xFF94A3B8),
                                              fontSize: 11,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    m.userName,
                                    style: const TextStyle(
                                      color: Color(0xFF475569),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Two-column row — same flex ratios as the rest of the comparison page
// ---------------------------------------------------------------------------

class _CerdasRow extends StatelessWidget {
  const _CerdasRow({
    required this.label,
    required this.m1Child,
    required this.m2Child,
    this.backgroundColor,
  });

  final String label;
  final Widget m1Child;
  final Widget m2Child;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      color: backgroundColor,
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFFCBD5E1),
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          Expanded(flex: 4, child: m1Child),
          Expanded(flex: 4, child: m2Child),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Circular + / - action icons
// ---------------------------------------------------------------------------

class _ActionIcons extends StatelessWidget {
  const _ActionIcons({
    required this.onIngreso,
    required this.onEgreso,
    required this.onHistory,
  });

  final VoidCallback onIngreso;
  final VoidCallback onEgreso;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _CircleIconButton(
          icon: Icons.add_circle,
          color: const Color(0xFF22C55E),
          tooltip: 'Registrar ingreso de cerda',
          onTap: onIngreso,
        ),
        const SizedBox(width: 6),
        _CircleIconButton(
          icon: Icons.remove_circle,
          color: const Color(0xFFEF4444),
          tooltip: 'Registrar salida de cerda',
          onTap: onEgreso,
        ),
        const SizedBox(width: 6),
        _CircleIconButton(
          icon: Icons.history,
          color: const Color(0xFF94A3B8),
          tooltip: 'Ver historial de movimientos',
          onTap: onHistory,
        ),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared small widgets
// ---------------------------------------------------------------------------

class _ValueText extends StatelessWidget {
  const _ValueText(
    this.value, {
    this.bold = false,
    this.color = const Color(0xFFE5E7EB),
  });

  final String value;
  final bool bold;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      ),
    );
  }
}

class _FormLabel extends StatelessWidget {
  const _FormLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _FooterMessage extends StatelessWidget {
  const _FooterMessage({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: TextStyle(color: color, fontSize: 12));
  }
}

InputDecoration _inputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 13),
    filled: true,
    fillColor: const Color(0xFF0F172A),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: Color(0xFF334155)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: Color(0xFF38BDF8)),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: Color(0xFFEF4444)),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: Color(0xFFEF4444)),
    ),
    errorStyle: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 11),
  );
}

String _two(int v) => v.toString().padLeft(2, '0');
