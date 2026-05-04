import 'package:flutter/material.dart';

import '../services/presence_service.dart';
import '../services/user_management_service.dart';

class ActiveUsersEye extends StatelessWidget {
  const ActiveUsersEye({
    super.key,
    required this.workspaceId,
    this.service = const PresenceService(),
  });

  final String workspaceId;
  final PresenceService service;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ActiveUserPresence>>(
      stream: service.watchActiveUsers(workspaceId: workspaceId),
      builder:
          (
            BuildContext context,
            AsyncSnapshot<List<ActiveUserPresence>> snapshot,
          ) {
            final List<ActiveUserPresence> users =
                snapshot.data ?? const <ActiveUserPresence>[];
            final int count = users.length;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton.filledTonal(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (BuildContext context) => _ActiveUsersDialog(
                      workspaceId: workspaceId,
                      service: service,
                    ),
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF111827),
                    foregroundColor: const Color(0xFFE5E7EB),
                    side: const BorderSide(color: Color(0xFF334155)),
                    padding: const EdgeInsets.all(11),
                    minimumSize: const Size.square(42),
                  ),
                  tooltip: 'Usuarios activos',
                  icon: const Icon(Icons.visibility_rounded, size: 21),
                ),
                Positioned(
                  right: -4,
                  top: -5,
                  child: _PresenceBadge(count: count),
                ),
              ],
            );
          },
    );
  }
}

class _PresenceBadge extends StatelessWidget {
  const _PresenceBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final String label = count > 99 ? '99+' : count.toString();
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF38BDF8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF0F172A), width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF082F49),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ActiveUsersDialog extends StatelessWidget {
  const _ActiveUsersDialog({required this.workspaceId, required this.service});

  final String workspaceId;
  final PresenceService service;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Usuarios activos',
        style: TextStyle(color: Color(0xFFE5E7EB)),
      ),
      content: SizedBox(
        width: 560,
        child: StreamBuilder<List<ActiveUserPresence>>(
          stream: service.watchActiveUsers(workspaceId: workspaceId),
          builder:
              (
                BuildContext context,
                AsyncSnapshot<List<ActiveUserPresence>> snapshot,
              ) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
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
                        'Error al cargar usuarios activos:\n${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFFCA5A5)),
                      ),
                    ),
                  );
                }

                final List<ActiveUserPresence> users =
                    snapshot.data ?? const <ActiveUserPresence>[];
                if (users.isEmpty) {
                  return const SizedBox(
                    height: 90,
                    child: Center(
                      child: Text(
                        'No hay usuarios activos',
                        style: TextStyle(color: Color(0xFF94A3B8)),
                      ),
                    ),
                  );
                }

                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 460),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: users.length,
                    separatorBuilder: (BuildContext context, int index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (BuildContext context, int index) {
                      return _ActiveUserTile(user: users[index]);
                    },
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

class _ActiveUserTile extends StatelessWidget {
  const _ActiveUserTile({required this.user});

  final ActiveUserPresence user;

  @override
  Widget build(BuildContext context) {
    final String name = user.displayName.trim().isNotEmpty
        ? user.displayName.trim()
        : user.email.trim().isNotEmpty
        ? user.email.trim()
        : user.uid;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 5),
                child: Icon(Icons.circle, size: 9, color: Color(0xFF22C55E)),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFE5E7EB),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.email.trim().isEmpty ? 'Sin email' : user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _RolePill(role: user.role),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _MetaText(
                label: 'Activo desde',
                value: _formatDateTime(user.activeSince),
              ),
              _MetaText(
                label: 'Última actividad',
                value: _formatRelativeDateTime(user.lastSeenAt),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A5F),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        UserAppRole.label(role),
        style: const TextStyle(
          color: Color(0xFFBFDBFE),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDateTime(DateTime? value) {
  if (value == null) {
    return 'N/D';
  }
  final DateTime local = value.toLocal();
  final String day = local.day.toString().padLeft(2, '0');
  final String month = local.month.toString().padLeft(2, '0');
  final String year = local.year.toString();
  final String hour = local.hour.toString().padLeft(2, '0');
  final String minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/$year $hour:$minute';
}

String _formatRelativeDateTime(DateTime? value) {
  if (value == null) {
    return 'N/D';
  }
  final Duration age = DateTime.now().difference(value.toLocal());
  if (age.inSeconds < 60) {
    return 'hace ${age.inSeconds.clamp(0, 59)} seg';
  }
  if (age.inMinutes < 60) {
    return 'hace ${age.inMinutes} min';
  }
  return _formatDateTime(value);
}
