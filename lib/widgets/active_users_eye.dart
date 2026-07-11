import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/backend_presence_snapshot.dart';

class ActiveUsersEye extends StatelessWidget {
  const ActiveUsersEye({
    super.key,
    required this.currentUser,
    required this.currentRole,
    required this.presenceListenable,
    required this.presenceDetailsRequested,
  });

  final User currentUser;
  final String? currentRole;
  final ValueListenable<BackendPresenceSnapshot?> presenceListenable;
  final ValueNotifier<bool> presenceDetailsRequested;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BackendPresenceSnapshot?>(
      valueListenable: presenceListenable,
      builder: (BuildContext context, BackendPresenceSnapshot? presence, _) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton.filledTonal(
              onPressed: () => _openDialog(context),
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
            if (presence != null && !presence.stale)
              Positioned(
                right: -4,
                top: -5,
                child: _PresenceBadge(count: presence.activeUserCount),
              ),
          ],
        );
      },
    );
  }

  Future<void> _openDialog(BuildContext context) async {
    presenceDetailsRequested.value = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return _ActiveUsersDialog(
            currentUser: currentUser,
            currentRole: currentRole,
            presenceListenable: presenceListenable,
          );
        },
      );
    } finally {
      presenceDetailsRequested.value = false;
    }
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
  const _ActiveUsersDialog({
    required this.currentUser,
    required this.currentRole,
    required this.presenceListenable,
  });

  final User currentUser;
  final String? currentRole;
  final ValueListenable<BackendPresenceSnapshot?> presenceListenable;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text(
        'Usuarios activos',
        style: TextStyle(color: Color(0xFFE5E7EB)),
      ),
      content: SizedBox(
        width: 720,
        height: 520,
        child: ValueListenableBuilder<BackendPresenceSnapshot?>(
          valueListenable: presenceListenable,
          builder:
              (
                BuildContext context,
                BackendPresenceSnapshot? presence,
                Widget? child,
              ) {
                if (presence == null) {
                  return const _PresenceStateMessage(
                    message: 'Esperando datos de presencia del backend.',
                    detail:
                        'El panel se completa cuando llega un snapshot con presencia.',
                  );
                }
                if (presence.stale) {
                  return _PresenceStateMessage(
                    message: 'Presencia sin actualizar.',
                    detail:
                        'El ultimo snapshot valido se recibio ${_formatRelative(presence.receivedAt)}.',
                  );
                }
                if (!presence.hasUsers) {
                  return _CountOnlyPresenceView(presence: presence);
                }
                return _UsersList(presence: presence);
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

class _CountOnlyPresenceView extends StatelessWidget {
  const _CountOnlyPresenceView({required this.presence});

  final BackendPresenceSnapshot presence;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PresenceSummary(presence: presence),
        const SizedBox(height: 18),
        const _PresenceStateMessage(
          message: 'El backend informo la cantidad de usuarios activos.',
          detail:
              'El detalle se completa con el proximo snapshot mientras este panel permanece abierto.',
        ),
      ],
    );
  }
}

class _UsersList extends StatelessWidget {
  const _UsersList({required this.presence});

  final BackendPresenceSnapshot presence;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PresenceSummary(presence: presence),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: presence.users.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int index) {
              return _ActiveUserTile(user: presence.users[index]);
            },
          ),
        ),
      ],
    );
  }
}

class _PresenceSummary extends StatelessWidget {
  const _PresenceSummary({required this.presence});

  final BackendPresenceSnapshot presence;

  @override
  Widget build(BuildContext context) {
    final int sessionCount = presence.users.fold<int>(
      0,
      (int total, BackendPresenceUser user) => total + user.activeSessionCount,
    );
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        _SummaryPill(
          label: 'Usuarios',
          value: presence.activeUserCount.toString(),
        ),
        if (sessionCount > 0)
          _SummaryPill(label: 'Sesiones', value: sessionCount.toString()),
        _SummaryPill(
          label: 'Snapshot',
          value: _formatRelative(presence.receivedAt),
        ),
      ],
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
          ),
          const SizedBox(width: 7),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFE5E7EB),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveUserTile extends StatelessWidget {
  const _ActiveUserTile({required this.user});

  final BackendPresenceUser user;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
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
                      user.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFE5E7EB),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (user.email.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        user.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _SessionCountPill(count: user.activeSessionCount),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              if (user.firstSeen != null)
                _MetaText(
                  label: 'Inicio',
                  value: _formatDateTime(user.firstSeen),
                ),
              if (user.lastSeen != null)
                _MetaText(
                  label: 'Ultima actividad',
                  value: _formatRelative(user.lastSeen!),
                ),
              if (user.connectedSeconds != null)
                _MetaText(
                  label: 'Tiempo conectado',
                  value: _formatDurationSeconds(user.connectedSeconds!),
                ),
              if (user.siteIds.isNotEmpty)
                _MetaText(label: 'Sitios', value: user.siteIds.join(', ')),
            ],
          ),
          if (user.sessions.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...user.sessions.map(_SessionTile.new),
          ],
        ],
      ),
    );
  }
}

class _SessionCountPill extends StatelessWidget {
  const _SessionCountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF082F49),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF0EA5E9)),
      ),
      child: Text(
        '$count ${count == 1 ? 'sesion' : 'sesiones'}',
        style: const TextStyle(
          color: Color(0xFFBAE6FD),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile(this.session);

  final BackendPresenceSession session;

  @override
  Widget build(BuildContext context) {
    final List<String> details = <String>[
      if (session.deviceType?.trim().isNotEmpty == true) session.deviceType!,
      if (session.appVersion?.trim().isNotEmpty == true)
        'App ${session.appVersion}',
      if (session.backendVersion?.trim().isNotEmpty == true)
        'Backend ${session.backendVersion}',
      if (session.ipMasked?.trim().isNotEmpty == true) session.ipMasked!,
    ];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 5,
        children: [
          _MetaText(
            label: 'Sesion',
            value: session.sessionId.trim().isEmpty
                ? 'sin id'
                : _shortSessionId(session.sessionId),
          ),
          if (session.siteId?.trim().isNotEmpty == true)
            _MetaText(label: 'Sitio', value: session.siteId!),
          if (session.lastSeen != null)
            _MetaText(
              label: 'Ultima actividad',
              value: _formatRelative(session.lastSeen!),
            ),
          if (details.isNotEmpty)
            _MetaText(label: 'Cliente', value: details.join(' · ')),
        ],
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
            style: const TextStyle(color: Color(0xFF64748B)),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(color: Color(0xFFCBD5E1)),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 11, height: 1.2),
    );
  }
}

class _PresenceStateMessage extends StatelessWidget {
  const _PresenceStateMessage({required this.message, this.detail});

  final String message;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFE5E7EB),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime? value) {
  if (value == null) {
    return '-';
  }
  final DateTime local = value.toLocal();
  return '${_two(local.day)}/${_two(local.month)} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

String _formatRelative(DateTime value) {
  final Duration diff = DateTime.now().difference(value.toLocal());
  if (diff.inSeconds < 10) {
    return 'ahora';
  }
  if (diff.inSeconds < 60) {
    return 'hace ${diff.inSeconds}s';
  }
  if (diff.inMinutes < 60) {
    return 'hace ${diff.inMinutes}min';
  }
  if (diff.inHours < 24) {
    return 'hace ${diff.inHours}h';
  }
  return _formatDateTime(value);
}

String _formatDurationSeconds(int seconds) {
  if (seconds < 60) {
    return '${seconds}s';
  }
  final int minutes = seconds ~/ 60;
  if (minutes < 60) {
    return '${minutes}min';
  }
  final int hours = minutes ~/ 60;
  final int remMinutes = minutes % 60;
  return remMinutes == 0 ? '${hours}h' : '${hours}h ${remMinutes}min';
}

String _shortSessionId(String value) {
  final String trimmed = value.trim();
  if (trimmed.length <= 10) {
    return trimmed;
  }
  return '${trimmed.substring(0, 4)}...${trimmed.substring(trimmed.length - 4)}';
}

String _two(int value) => value.toString().padLeft(2, '0');
