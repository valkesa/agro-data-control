import 'package:flutter/material.dart';

import '../../../models/hierarchical_alert_catalog.dart';
import '../../../models/hierarchical_alert_recipient.dart';

const Map<AlertConfigScope, String> _scopeLabels = {
  AlertConfigScope.tenant: 'Tenant',
  AlertConfigScope.site: 'Site',
  AlertConfigScope.device: 'Device',
  AlertConfigScope.room: 'Room',
};

/// "Destinatarios WhatsApp" (Etapa B5 §24-§30): sección separada dentro de
/// Configuración → Alertas, asociada al scope actualmente seleccionado.
///
/// Dos listas con roles distintos, a propósito:
///  - Efectivos: lo que realmente recibiría un WhatsApp en este scope, con
///    origen — los heredados se muestran solo lectura (§25).
///  - Propios de este scope: TODOS los documentos que viven en el scope
///    actual (incluidos los deshabilitados), porque son los únicos que este
///    scope puede administrar (activar/desactivar/eliminar, §29/§30).
class HierarchicalRecipientsSection extends StatefulWidget {
  const HierarchicalRecipientsSection({
    super.key,
    required this.scope,
    required this.scopeName,
    required this.canEdit,
    required this.effectiveRecipients,
    required this.ownScopeRecipients,
    required this.onAdd,
    required this.onSetEnabled,
    required this.onDelete,
  });

  final AlertConfigScope scope;

  /// Nombre concreto del nodo actualmente seleccionado (p.ej. "Las Heras"
  /// para Site, "Laboratorio" para Device) — pedido 2026-09-10: sin esto
  /// no quedaba claro DÓNDE se agregaba un destinatario nuevo, solo se
  /// veía el nombre genérico del scope ("Site") sin decir cuál.
  final String scopeName;
  final bool canEdit;
  final List<HierarchicalAlertRecipient> effectiveRecipients;
  final Map<String, AlertRecipientOverride> ownScopeRecipients;

  /// Devuelve un mensaje de error, o `null` si se agregó con éxito.
  final Future<String?> Function({
    required String displayName,
    required String phoneE164,
  })
  onAdd;
  final Future<void> Function(String recipientId, bool enabled) onSetEnabled;
  final Future<void> Function(String recipientId) onDelete;

  @override
  State<HierarchicalRecipientsSection> createState() =>
      _HierarchicalRecipientsSectionState();
}

class _HierarchicalRecipientsSectionState
    extends State<HierarchicalRecipientsSection> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  String? _formError;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submitAdd() async {
    final String name = _nameController.text.trim();
    final String phone = _phoneController.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      setState(() => _formError = 'Nombre y teléfono son obligatorios.');
      return;
    }
    if (!isValidAlertRecipientPhoneE164(
      normalizeAlertRecipientPhoneE164(phone),
    )) {
      setState(
        () => _formError = 'Teléfono inválido — usar formato E.164 (+549...).',
      );
      return;
    }
    // Etapa B5 §27: bloquear duplicado heredado en vez de crear uno nuevo.
    final HierarchicalAlertRecipient? conflict = findInheritedConflict(
      phoneE164: phone,
      targetScope: widget.scope,
      effectiveRecipients: widget.effectiveRecipients,
    );
    if (conflict != null) {
      setState(
        () => _formError =
            'Este destinatario ya se hereda desde ${_scopeLabels[conflict.scope]}.',
      );
      return;
    }
    if (widget.ownScopeRecipients.values.any(
      (r) => r.normalizedPhone == normalizeAlertRecipientPhoneE164(phone),
    )) {
      setState(
        () => _formError =
            'Ya existe un destinatario con ese teléfono en este scope.',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _formError = null;
    });
    final String? error = await widget.onAdd(
      displayName: name,
      phoneE164: phone,
    );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _formError = error;
    });
    if (error == null) {
      _nameController.clear();
      _phoneController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Etapa 2026-09-10: la lista efectiva de solo lectura
            // ("Destinatarios configurados en el sistema jerárquico") se
            // sacó de acá — quedó redundante con `RecipientsSummaryTable`,
            // que ya muestra el panorama completo del Tenant de un
            // pantallazo. Esta sección queda enfocada en lo único que
            // sigue siendo exclusivo de acá: administrar (agregar/activar/
            // desactivar/eliminar) los destinatarios propios del scope
            // actual. `widget.effectiveRecipients` se sigue usando para
            // `findInheritedConflict` al agregar (§27), aunque ya no se
            // renderice.
            Text(
              'Propios de ${_scopeLabels[widget.scope]}: ${widget.scopeName}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            if (widget.ownScopeRecipients.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'No hay destinatarios propios de este scope todavía.',
                  style: TextStyle(color: Color(0xFF94A3B8)),
                ),
              )
            else
              for (final AlertRecipientOverride o
                  in widget.ownScopeRecipients.values)
                _OwnRecipientRow(
                  recipient: o,
                  canEdit: widget.canEdit,
                  onSetEnabled: (enabled) => widget.onSetEnabled(o.id, enabled),
                  onDelete: () => widget.onDelete(o.id),
                ),
            if (widget.canEdit) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'Se va a agregar en: ',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                    TextSpan(
                      text:
                          '${widget.scopeName} (${_scopeLabels[widget.scope]})',
                      style: const TextStyle(
                        color: Color(0xFFE5E7EB),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono (+549...)',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _submitting ? null : _submitAdd,
                    child: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Agregar'),
                  ),
                ],
              ),
              if (_formError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _formError!,
                    style: const TextStyle(
                      color: Color(0xFFFCA5A5),
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OwnRecipientRow extends StatelessWidget {
  const _OwnRecipientRow({
    required this.recipient,
    required this.canEdit,
    required this.onSetEnabled,
    required this.onDelete,
  });

  final AlertRecipientOverride recipient;
  final bool canEdit;
  final ValueChanged<bool> onSetEnabled;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Switch(
            value: recipient.enabled,
            onChanged: canEdit ? onSetEnabled : null,
          ),
          Expanded(
            child: Text(
              '${recipient.displayName} — ${recipient.phoneE164}',
              style: TextStyle(
                color: recipient.enabled
                    ? const Color(0xFFE5E7EB)
                    : const Color(0xFF64748B),
              ),
            ),
          ),
          if (canEdit)
            IconButton(
              tooltip: 'Eliminar (acción administrativa)',
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => _confirmDelete(context),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar destinatario'),
        content: Text(
          '¿Eliminar a ${recipient.displayName} (${recipient.phoneE164})? '
          'Esta acción es distinta de deshabilitar y no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) onDelete();
  }
}
