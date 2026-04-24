import 'package:flutter/material.dart';

import '../services/user_management_service.dart';

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  static const UserManagementService _service = UserManagementService();

  late Future<List<UserProfile>> _usersFuture;

  @override
  void initState() {
    super.initState();
    _usersFuture = _service.listAllUsers();
  }

  void _reload() {
    setState(() {
      _usersFuture = _service.listAllUsers();
    });
  }

  Future<void> _editUser(UserProfile user) async {
    if (user.role == UserAppRole.owner) return;
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => _UserAccessDialog(
        user: user,
        service: _service,
      ),
    );
    if (saved == true) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: <Widget>[
          const Expanded(
            child: Text(
              'Gestión de usuarios',
              style: TextStyle(color: Color(0xFFE5E7EB)),
            ),
          ),
          IconButton(
            tooltip: 'Recargar',
            onPressed: _reload,
            icon: const Icon(Icons.refresh, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: FutureBuilder<List<UserProfile>>(
          future: _usersFuture,
          builder: (
            BuildContext context,
            AsyncSnapshot<List<UserProfile>> snapshot,
          ) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return SizedBox(
                height: 120,
                child: Center(
                  child: Text(
                    'Error al cargar usuarios:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFFCA5A5)),
                  ),
                ),
              );
            }

            final List<UserProfile> users =
                snapshot.data ?? <UserProfile>[];
            if (users.isEmpty) {
              return const SizedBox(
                height: 80,
                child: Center(
                  child: Text(
                    'No hay usuarios.',
                    style: TextStyle(color: Color(0xFF94A3B8)),
                  ),
                ),
              );
            }

            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: SingleChildScrollView(
                child: Column(
                  children: users
                      .map(
                        (UserProfile user) => _UserCard(
                          user: user,
                          onEdit: () => _editUser(user),
                        ),
                      )
                      .toList(),
                ),
              ),
            );
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

// ─── User card (read-only, compact) ──────────────────────────────────────────

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user, required this.onEdit});

  final UserProfile user;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final String sitesLabel = user.allowedSiteIds.isEmpty
        ? (user.defaultSiteId != null ? user.defaultSiteId! : 'Sin sites')
        : user.allowedSiteIds.join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // Status dot
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 10, top: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: user.active
                  ? const Color(0xFF22C55E)
                  : const Color(0xFF4B5563),
            ),
          ),
          // Info column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  user.email ?? user.uid,
                  style: const TextStyle(
                    color: Color(0xFFE5E7EB),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: <Widget>[
                    _Chip(
                      label: UserAppRole.label(user.role),
                      color: const Color(0xFF1E3A5F),
                    ),
                    const SizedBox(width: 6),
                    if (user.activeTenantId != null)
                      _Chip(
                        label: user.activeTenantId!,
                        color: const Color(0xFF1E3A2A),
                      ),
                  ],
                ),
                if (user.activeTenantId != null) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    'Sites: $sitesLabel',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Owners are read-only — only editable directly in Firestore
          if (user.role == UserAppRole.owner)
            Tooltip(
              message: 'Los owners solo se configuran desde Firestore',
              child: Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: const Color(0xFF475569),
              ),
            )
          else
            FilledButton.tonal(
              onPressed: onEdit,
              style: FilledButton.styleFrom(
                minimumSize: const Size(72, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Editar', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 10),
      ),
    );
  }
}

// ─── Edit dialog ─────────────────────────────────────────────────────────────

class _UserAccessDialog extends StatefulWidget {
  const _UserAccessDialog({required this.user, required this.service});

  final UserProfile user;
  final UserManagementService service;

  @override
  State<_UserAccessDialog> createState() => _UserAccessDialogState();
}

class _UserAccessDialogState extends State<_UserAccessDialog> {
  late String? _selectedRole;
  late String? _selectedTenantId;
  late Set<String> _selectedSiteIds;

  late Future<List<TenantInfo>> _tenantsFuture;
  Future<List<SiteInfo>>? _sitesFuture;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.user.role;
    _selectedTenantId = widget.user.activeTenantId;
    _selectedSiteIds = <String>{
      ...widget.user.allowedSiteIds,
      if (widget.user.allowedSiteIds.isEmpty &&
          widget.user.defaultSiteId != null)
        widget.user.defaultSiteId!,
    };
    _tenantsFuture = widget.service.listTenants();
    if (_selectedTenantId != null) {
      _sitesFuture = widget.service.listSitesForTenant(_selectedTenantId!);
    }
  }

  void _onTenantChanged(String? tenantId) {
    setState(() {
      _selectedTenantId = tenantId;
      _selectedSiteIds = <String>{};
      _sitesFuture = tenantId != null
          ? widget.service.listSitesForTenant(tenantId)
          : null;
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await widget.service.updateUserAccess(
        uid: widget.user.uid,
        role: _selectedRole,
        tenantId: _selectedTenantId,
        allowedSiteIds: _selectedSiteIds.toList(),
        previousTenantId: widget.user.activeTenantId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Editar acceso',
            style: TextStyle(color: Color(0xFFE5E7EB), fontSize: 16),
          ),
          const SizedBox(height: 2),
          Text(
            widget.user.email ?? widget.user.uid,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // ── Rol ──────────────────────────────────────────────────
            _SectionLabel('Rol'),
            const SizedBox(height: 6),
            _RoleDropdown(
              value: _selectedRole,
              onChanged: _isSaving
                  ? null
                  : (String? v) => setState(() => _selectedRole = v),
            ),
            const SizedBox(height: 18),
            // ── Tenant ───────────────────────────────────────────────
            _SectionLabel('Tenant'),
            const SizedBox(height: 6),
            FutureBuilder<List<TenantInfo>>(
              future: _tenantsFuture,
              builder: (
                BuildContext context,
                AsyncSnapshot<List<TenantInfo>> snapshot,
              ) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _LoadingRow();
                }
                if (snapshot.hasError) {
                  return _ErrorLabel('Error cargando tenants');
                }
                final List<TenantInfo> tenants =
                    snapshot.data ?? <TenantInfo>[];
                return _TenantDropdown(
                  tenants: tenants,
                  value: _selectedTenantId,
                  enabled: !_isSaving,
                  onChanged: _onTenantChanged,
                );
              },
            ),
            const SizedBox(height: 18),
            // ── Sites ────────────────────────────────────────────────
            _SectionLabel('Sites'),
            const SizedBox(height: 6),
            if (_selectedTenantId == null)
              const Text(
                'Seleccioná un tenant primero.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
              )
            else if (_sitesFuture == null)
              const SizedBox.shrink()
            else
              FutureBuilder<List<SiteInfo>>(
                future: _sitesFuture,
                builder: (
                  BuildContext context,
                  AsyncSnapshot<List<SiteInfo>> snapshot,
                ) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const _LoadingRow();
                  }
                  if (snapshot.hasError) {
                    return _ErrorLabel('Error cargando sites');
                  }
                  final List<SiteInfo> sites =
                      snapshot.data ?? <SiteInfo>[];
                  if (sites.isEmpty) {
                    return const Text(
                      'Este tenant no tiene sites configurados.',
                      style:
                          TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    );
                  }
                  return _SiteCheckboxList(
                    sites: sites,
                    selectedIds: _selectedSiteIds,
                    enabled: !_isSaving,
                    onChanged: (String siteId, bool checked) {
                      setState(() {
                        if (checked) {
                          _selectedSiteIds.add(siteId);
                        } else {
                          _selectedSiteIds.remove(siteId);
                        }
                      });
                    },
                  );
                },
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          style: FilledButton.styleFrom(
            minimumSize: const Size(80, 36),
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

// ─── Small helpers ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 28,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text(
            'Cargando...',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ErrorLabel extends StatelessWidget {
  const _ErrorLabel(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12),
    );
  }
}

// ─── Role dropdown ────────────────────────────────────────────────────────────

class _RoleDropdown extends StatelessWidget {
  const _RoleDropdown({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final List<DropdownMenuEntry<String?>> entries =
        <DropdownMenuEntry<String?>>[
      const DropdownMenuEntry<String?>(value: null, label: 'Sin rol'),
      ...UserAppRole.all.map(
        (String role) => DropdownMenuEntry<String?>(
          value: role,
          label: UserAppRole.label(role),
        ),
      ),
    ];

    return DropdownMenu<String?>(
      initialSelection: value,
      enabled: onChanged != null,
      onSelected: onChanged,
      width: double.infinity,
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        filled: true,
        fillColor: Color(0xFF1E293B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: Color(0xFF334155)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: Color(0xFF334155)),
        ),
      ),
      textStyle: const TextStyle(color: Color(0xFFE5E7EB), fontSize: 13),
      menuStyle: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(Color(0xFF1E293B)),
      ),
      dropdownMenuEntries: entries,
    );
  }
}

// ─── Tenant dropdown ──────────────────────────────────────────────────────────

class _TenantDropdown extends StatelessWidget {
  const _TenantDropdown({
    required this.tenants,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final List<TenantInfo> tenants;
  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final List<DropdownMenuEntry<String?>> entries =
        <DropdownMenuEntry<String?>>[
      const DropdownMenuEntry<String?>(value: null, label: 'Sin tenant'),
      ...tenants.map(
        (TenantInfo t) =>
            DropdownMenuEntry<String?>(value: t.tenantId, label: t.name),
      ),
    ];

    return DropdownMenu<String?>(
      initialSelection: value,
      enabled: enabled && tenants.isNotEmpty,
      onSelected: (String? v) => onChanged(v),
      width: double.infinity,
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        filled: true,
        fillColor: Color(0xFF1E293B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: Color(0xFF334155)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: Color(0xFF334155)),
        ),
      ),
      textStyle: const TextStyle(color: Color(0xFFE5E7EB), fontSize: 13),
      menuStyle: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(Color(0xFF1E293B)),
      ),
      dropdownMenuEntries: entries,
    );
  }
}

// ─── Site checkboxes ──────────────────────────────────────────────────────────

class _SiteCheckboxList extends StatelessWidget {
  const _SiteCheckboxList({
    required this.sites,
    required this.selectedIds,
    required this.enabled,
    required this.onChanged,
  });

  final List<SiteInfo> sites;
  final Set<String> selectedIds;
  final bool enabled;
  final void Function(String siteId, bool checked) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: sites.map((SiteInfo site) {
          final bool isChecked = selectedIds.contains(site.siteId);
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: enabled ? () => onChanged(site.siteId, !isChecked) : null,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: isChecked,
                      onChanged: enabled
                          ? (bool? v) => onChanged(site.siteId, v ?? false)
                          : null,
                      side: const BorderSide(color: Color(0xFF475569)),
                      activeColor: const Color(0xFF3B82F6),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          site.name,
                          style: const TextStyle(
                            color: Color(0xFFE5E7EB),
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          site.siteId,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
