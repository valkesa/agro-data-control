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
    return DefaultTabController(
      length: 2,
      child: AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Usuarios',
          style: TextStyle(color: Color(0xFFE5E7EB)),
        ),
        content: SizedBox(
          width: 720,
          height: 520,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Activos'),
                  Tab(text: 'Historial'),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TabBarView(
                  children: [
                    _ActiveUsersView(
                      workspaceId: workspaceId,
                      service: service,
                    ),
                    _SessionHistoryView(
                      workspaceId: workspaceId,
                      service: service,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

class _ActiveUsersView extends StatelessWidget {
  const _ActiveUsersView({required this.workspaceId, required this.service});

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
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Error al cargar usuarios activos:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFFCA5A5)),
                ),
              );
            }

            final List<ActiveUserPresence> users =
                snapshot.data ?? const <ActiveUserPresence>[];
            if (users.isEmpty) {
              return const Center(
                child: Text(
                  'No hay usuarios activos',
                  style: TextStyle(color: Color(0xFF94A3B8)),
                ),
              );
            }

            return ListView.separated(
              itemCount: users.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int index) {
                return _ActiveUserTile(user: users[index]);
              },
            );
          },
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
              _MetaText(
                label: 'Tiempo activo',
                value: _formatDurationBetween(user.activeSince, DateTime.now()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _HistoryViewMode { porEvento, porUsuario }

class _SessionHistoryView extends StatefulWidget {
  const _SessionHistoryView({required this.workspaceId, required this.service});

  final String workspaceId;
  final PresenceService service;

  @override
  State<_SessionHistoryView> createState() => _SessionHistoryViewState();
}

class _SessionHistoryViewState extends State<_SessionHistoryView> {
  _HistoryViewMode _mode = _HistoryViewMode.porEvento;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<UserActivitySession>>(
      stream: widget.service.watchUserSessions(workspaceId: widget.workspaceId),
      builder: (
        BuildContext context,
        AsyncSnapshot<List<UserActivitySession>> snapshot,
      ) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error al cargar historial:\n${snapshot.error}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFFCA5A5)),
            ),
          );
        }

        final List<UserActivitySession> sessions =
            snapshot.data ?? const <UserActivitySession>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _ViewModeButton(
                  icon: Icons.timeline_rounded,
                  label: 'Por evento',
                  selected: _mode == _HistoryViewMode.porEvento,
                  isFirst: true,
                  isLast: false,
                  onTap: () =>
                      setState(() => _mode = _HistoryViewMode.porEvento),
                ),
                _ViewModeButton(
                  icon: Icons.people_alt_rounded,
                  label: 'Por usuario',
                  selected: _mode == _HistoryViewMode.porUsuario,
                  isFirst: false,
                  isLast: true,
                  onTap: () =>
                      setState(() => _mode = _HistoryViewMode.porUsuario),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (sessions.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No hay ingresos registrados',
                    style: TextStyle(color: Color(0xFF94A3B8)),
                  ),
                ),
              )
            else if (_mode == _HistoryViewMode.porEvento)
              Expanded(
                child: ListView.separated(
                  itemCount: sessions.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int index) =>
                      _SessionTile(
                        session: sessions[index],
                        service: widget.service,
                      ),
                ),
              )
            else
              Expanded(
                child: _SessionsByUserView(
                  sessions: sessions,
                  service: widget.service,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.service});

  final UserActivitySession session;
  final PresenceService service;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final DateTime? closedAt = session.effectiveClosedAt(
      service.activeThreshold,
      now,
    );
    final String reason = session.effectiveCloseReason(
      service.activeThreshold,
      now,
    );
    final int? durationSeconds = session.effectiveDurationSeconds(
      service.activeThreshold,
      now,
    );
    final String name = session.displayName.trim().isNotEmpty
        ? session.displayName.trim()
        : session.email.trim().isNotEmpty
        ? session.email.trim()
        : session.uid;

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
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFE5E7EB),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _RolePill(role: session.role),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            session.email.trim().isEmpty ? 'Sin email' : session.email,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _MetaText(
                label: 'Inicio',
                value: _formatDateTime(session.loginAt),
              ),
              _MetaText(label: 'Cierre', value: _formatDateTime(closedAt)),
              _MetaText(
                label: 'Duración',
                value: _formatDurationSeconds(durationSeconds),
              ),
              _MetaText(
                label: 'Motivo',
                value: reason.isEmpty ? 'activa' : reason,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ViewModeButton extends StatelessWidget {
  const _ViewModeButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1E3A5F) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.horizontal(
            left: isFirst ? const Radius.circular(8) : Radius.zero,
            right: isLast ? const Radius.circular(8) : Radius.zero,
          ),
          border: Border.all(
            color: selected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 15,
              color: selected ? const Color(0xFF38BDF8) : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF38BDF8)
                    : const Color(0xFF64748B),
                fontSize: 12,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionsByUserView extends StatelessWidget {
  const _SessionsByUserView({
    required this.sessions,
    required this.service,
  });

  final List<UserActivitySession> sessions;
  final PresenceService service;

  @override
  Widget build(BuildContext context) {
    final Map<String, List<UserActivitySession>> grouped =
        <String, List<UserActivitySession>>{};
    for (final UserActivitySession s in sessions) {
      (grouped[s.uid] ??= <UserActivitySession>[]).add(s);
    }

    final DateTime epoch = DateTime.fromMillisecondsSinceEpoch(0);
    final List<String> sortedUids = grouped.keys.toList()
      ..sort((String a, String b) {
        final DateTime aLatest = grouped[a]!.first.loginAt ?? epoch;
        final DateTime bLatest = grouped[b]!.first.loginAt ?? epoch;
        return bLatest.compareTo(aLatest);
      });

    return ListView.separated(
      itemCount: sortedUids.length,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) => _UserSessionGroup(
        sessions: grouped[sortedUids[index]]!,
        service: service,
      ),
    );
  }
}

class _UserSessionGroup extends StatelessWidget {
  const _UserSessionGroup({required this.sessions, required this.service});

  final List<UserActivitySession> sessions;
  final PresenceService service;

  @override
  Widget build(BuildContext context) {
    final UserActivitySession first = sessions.first;
    final String name = first.displayName.trim().isNotEmpty
        ? first.displayName.trim()
        : first.email.trim().isNotEmpty
        ? first.email.trim()
        : first.uid;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          backgroundColor: const Color(0xFF0F172A),
          collapsedBackgroundColor: const Color(0xFF0F172A),
          iconColor: const Color(0xFF64748B),
          collapsedIconColor: const Color(0xFF64748B),
          title: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
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
                      first.email.trim().isEmpty ? 'Sin email' : first.email,
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
              _RolePill(role: first.role),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${sessions.length} '
                  'sesión${sessions.length == 1 ? '' : 'es'}',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          children: sessions
              .map(
                (UserActivitySession s) => _SessionTileCompact(
                  session: s,
                  service: service,
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _SessionTileCompact extends StatelessWidget {
  const _SessionTileCompact({required this.session, required this.service});

  final UserActivitySession session;
  final PresenceService service;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final DateTime? closedAt = session.effectiveClosedAt(
      service.activeThreshold,
      now,
    );
    final String reason = session.effectiveCloseReason(
      service.activeThreshold,
      now,
    );
    final int? durationSeconds = session.effectiveDurationSeconds(
      service.activeThreshold,
      now,
    );

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: <Widget>[
          _MetaText(
            label: 'Inicio',
            value: _formatDateTime(session.loginAt),
          ),
          _MetaText(label: 'Cierre', value: _formatDateTime(closedAt)),
          _MetaText(
            label: 'Duración',
            value: _formatDurationSeconds(durationSeconds),
          ),
          _MetaText(
            label: 'Motivo',
            value: reason.isEmpty ? 'activa' : reason,
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

String _formatDurationBetween(DateTime? start, DateTime end) {
  if (start == null) {
    return 'N/D';
  }
  return _formatDurationSeconds(end.difference(start).inSeconds);
}

String _formatDurationSeconds(int? seconds) {
  if (seconds == null) {
    return 'N/D';
  }
  final int safeSeconds = seconds.clamp(0, 1 << 31);
  final int hours = safeSeconds ~/ 3600;
  final int minutes = (safeSeconds % 3600) ~/ 60;
  if (hours > 0) {
    return '${hours}h ${minutes}m';
  }
  if (minutes > 0) {
    return '${minutes}m';
  }
  return '${safeSeconds}s';
}
