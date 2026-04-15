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
  final Map<String, String?> _pendingRoles = <String, String?>{};
  final Set<String> _saving = <String>{};

  @override
  void initState() {
    super.initState();
    _usersFuture = _service.listAllUsers();
  }

  void _reload() {
    setState(() {
      _pendingRoles.clear();
      _usersFuture = _service.listAllUsers();
    });
  }

  Future<void> _saveRole(String uid, String? role) async {
    setState(() => _saving.add(uid));
    try {
      await _service.updateUserRole(uid, role);
      if (!mounted) return;
      setState(() {
        _pendingRoles.remove(uid);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rol actualizado.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving.remove(uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
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
        width: 640,
        child: FutureBuilder<List<UserProfile>>(
          future: _usersFuture,
          builder: (context, snapshot) {
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

            final List<UserProfile> users = snapshot.data ?? <UserProfile>[];
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
              constraints: const BoxConstraints(maxHeight: 480),
              child: SingleChildScrollView(
                child: Column(
                  children: users.map((user) => _UserRow(
                    user: user,
                    pendingRole: _pendingRoles[user.uid],
                    isSaving: _saving.contains(user.uid),
                    onRoleChanged: (role) {
                      setState(() => _pendingRoles[user.uid] = role);
                    },
                    onSave: () {
                      final String? role = _pendingRoles.containsKey(user.uid)
                          ? _pendingRoles[user.uid]
                          : user.role;
                      _saveRole(user.uid, role);
                    },
                  )).toList(),
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.pendingRole,
    required this.isSaving,
    required this.onRoleChanged,
    required this.onSave,
  });

  final UserProfile user;
  final String? pendingRole;
  final bool isSaving;
  final ValueChanged<String?> onRoleChanged;
  final VoidCallback onSave;

  bool get _hasPendingChange => pendingRole != null;

  String? get _effectiveRole =>
      _hasPendingChange ? pendingRole : user.role;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _hasPendingChange
              ? const Color(0xFF38BDF8)
              : const Color(0xFF334155),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: user.active
                      ? const Color(0xFF22C55E)
                      : const Color(0xFF4B5563),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  user.email ?? user.uid,
                  style: const TextStyle(
                    color: Color(0xFFE5E7EB),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const SizedBox(width: 16),
              Text(
                user.activeTenantId ?? 'Sin tenant',
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                ),
              ),
              if (user.defaultSiteId != null) ...[
                const Text(
                  '  /  ',
                  style: TextStyle(color: Color(0xFF475569), fontSize: 11),
                ),
                Text(
                  user.defaultSiteId!,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _RoleDropdown(
                  value: _effectiveRole,
                  onChanged: isSaving ? null : onRoleChanged,
                ),
              ),
              const SizedBox(width: 8),
              if (isSaving)
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: Padding(
                    padding: EdgeInsets.all(6),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_hasPendingChange)
                FilledButton(
                  onPressed: onSave,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(64, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Guardar', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleDropdown extends StatelessWidget {
  const _RoleDropdown({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final List<DropdownMenuEntry<String?>> entries = <DropdownMenuEntry<String?>>[
      const DropdownMenuEntry<String?>(
        value: null,
        label: 'Sin rol',
      ),
      ...UserAppRole.all.map(
        (role) => DropdownMenuEntry<String?>(
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
      textStyle: const TextStyle(
        color: Color(0xFFE5E7EB),
        fontSize: 13,
      ),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Color(0xFF1E293B)),
      ),
      dropdownMenuEntries: entries,
    );
  }
}
