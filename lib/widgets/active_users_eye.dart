import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/presence_service.dart';
import '../services/user_management_service.dart';

class ActiveUsersEye extends StatefulWidget {
  const ActiveUsersEye({
    super.key,
    required this.workspaceId,
    required this.currentUser,
    required this.currentRole,
    this.service = const PresenceService(),
  });

  final String workspaceId;
  final User currentUser;
  final String? currentRole;
  final PresenceService service;

  @override
  State<ActiveUsersEye> createState() => _ActiveUsersEyeState();
}

class _ActiveUsersEyeState extends State<ActiveUsersEye>
    with WidgetsBindingObserver {
  static const Duration _badgeRefreshInterval = Duration(minutes: 5);
  static const Duration _countdownTick = Duration(seconds: 1);

  int _lastKnownCount = 1;
  bool _hasLoadError = false;
  bool _appVisible = true;
  bool _dialogOpen = false;
  bool _badgeRequestInFlight = false;
  DateTime? _nextBadgeRefreshAt;
  Timer? _badgeRefreshTimer;
  Timer? _countdownTimer;
  String _countdownLabel = '--:--';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final AppLifecycleState? lifecycleState =
        WidgetsBinding.instance.lifecycleState;
    _appVisible =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    if (_appVisible) {
      _startCountdown();
      unawaited(_refreshBadgeCount());
    }
  }

  @override
  void didUpdateWidget(covariant ActiveUsersEye oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceId != widget.workspaceId ||
        oldWidget.service != widget.service) {
      _cancelBadgeRefreshTimer();
      _nextBadgeRefreshAt = null;
      if (_appVisible && !_dialogOpen) {
        unawaited(_refreshBadgeCount());
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool visible = state == AppLifecycleState.resumed;
    if (_appVisible == visible) {
      return;
    }
    _appVisible = visible;
    if (!visible) {
      _cancelBadgeRefreshTimer();
      _stopCountdown();
      return;
    }
    _startCountdown();
    if (_isBadgeRefreshDue) {
      unawaited(_refreshBadgeCount());
    } else {
      _scheduleNextBadgeRefresh();
      _updateCountdownLabel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelBadgeRefreshTimer();
    _stopCountdown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton.filledTonal(
              onPressed: _openDialog,
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
              child: _PresenceBadge(
                count: _lastKnownCount,
                hasError: _hasLoadError,
              ),
            ),
          ],
        ),
        const SizedBox(height: 1),
        SizedBox(
          height: 10,
          child: Text(
            _appVisible ? _countdownLabel : 'pausa',
            maxLines: 1,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openDialog() async {
    _dialogOpen = true;
    _cancelBadgeRefreshTimer();
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => _ActiveUsersDialog(
        workspaceId: widget.workspaceId,
        currentUser: widget.currentUser,
        currentRole: widget.currentRole,
        service: widget.service,
        onActiveUsersChanged: _handleActiveUsersChanged,
        onActiveUsersError: _handleActiveUsersError,
      ),
    );
    _dialogOpen = false;
    if (_appVisible) {
      if (_isBadgeRefreshDue) {
        unawaited(_refreshBadgeCount());
      } else {
        _scheduleNextBadgeRefresh();
      }
    }
  }

  void _handleActiveUsersChanged(List<ActiveUserPresence> users) {
    if (!mounted) {
      return;
    }
    _markBadgeFresh(users.length);
  }

  void _handleActiveUsersError(Object error) {
    debugPrint('[Presence] active users load error=$error');
    if (!mounted) {
      return;
    }
    _markBadgeError();
  }

  bool get _isBadgeRefreshDue {
    final DateTime? next = _nextBadgeRefreshAt;
    return next == null || !DateTime.now().isBefore(next);
  }

  List<ActiveUserPresence> _withCurrentUser(List<ActiveUserPresence> users) {
    if (users.any(
      (ActiveUserPresence user) => user.uid == widget.currentUser.uid,
    )) {
      return users;
    }
    return <ActiveUserPresence>[
      _presenceForCurrentUser(widget.currentUser, widget.currentRole),
      ...users,
    ];
  }

  Future<void> _refreshBadgeCount() async {
    if (!_appVisible || _dialogOpen || _badgeRequestInFlight) {
      return;
    }
    _badgeRequestInFlight = true;
    try {
      final List<ActiveUserPresence> loaded = await widget.service
          .fetchActiveUsers(workspaceId: widget.workspaceId);
      if (!mounted || !_appVisible || _dialogOpen) {
        return;
      }
      _markBadgeFresh(_withCurrentUser(loaded).length);
    } catch (error) {
      debugPrint('[Presence] badge refresh error=$error');
      if (!mounted || !_appVisible || _dialogOpen) {
        return;
      }
      _markBadgeError();
    } finally {
      _badgeRequestInFlight = false;
    }
  }

  void _markBadgeFresh(int count) {
    _nextBadgeRefreshAt = DateTime.now().add(_badgeRefreshInterval);
    setState(() {
      _lastKnownCount = count;
      _hasLoadError = false;
    });
    _updateCountdownLabel();
    if (_appVisible && !_dialogOpen) {
      _scheduleNextBadgeRefresh();
    }
  }

  void _markBadgeError() {
    _nextBadgeRefreshAt = DateTime.now().add(_badgeRefreshInterval);
    setState(() {
      _hasLoadError = true;
    });
    _updateCountdownLabel();
    if (_appVisible && !_dialogOpen) {
      _scheduleNextBadgeRefresh();
    }
  }

  void _scheduleNextBadgeRefresh() {
    _cancelBadgeRefreshTimer();
    if (!_appVisible || _dialogOpen) {
      return;
    }
    final DateTime next = _nextBadgeRefreshAt ?? DateTime.now();
    final Duration delay = next.difference(DateTime.now());
    _badgeRefreshTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(_refreshBadgeCount()),
    );
  }

  void _cancelBadgeRefreshTimer() {
    _badgeRefreshTimer?.cancel();
    _badgeRefreshTimer = null;
  }

  void _startCountdown() {
    _countdownTimer ??= Timer.periodic(
      _countdownTick,
      (_) => _updateCountdownLabel(),
    );
    _updateCountdownLabel();
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  void _updateCountdownLabel() {
    if (!mounted) {
      return;
    }
    final DateTime? next = _nextBadgeRefreshAt;
    final String label;
    if (!_appVisible) {
      label = _countdownLabel;
    } else if (next == null) {
      label = '--:--';
    } else {
      final Duration remaining = next.difference(DateTime.now());
      final int totalSeconds = remaining.isNegative ? 0 : remaining.inSeconds;
      final int minutes = totalSeconds ~/ 60;
      final int seconds = totalSeconds % 60;
      label =
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    setState(() {
      _countdownLabel = label;
    });
  }
}

class _PresenceBadge extends StatelessWidget {
  const _PresenceBadge({required this.count, required this.hasError});

  final int count;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final String label = hasError
        ? '!'
        : count > 99
        ? '99+'
        : count.toString();
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: hasError ? const Color(0xFFF87171) : const Color(0xFF38BDF8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF0F172A), width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: hasError ? const Color(0xFF450A0A) : const Color(0xFF082F49),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ActiveUsersDialog extends StatefulWidget {
  const _ActiveUsersDialog({
    required this.workspaceId,
    required this.currentUser,
    required this.currentRole,
    required this.service,
    required this.onActiveUsersChanged,
    required this.onActiveUsersError,
  });

  final String workspaceId;
  final User currentUser;
  final String? currentRole;
  final PresenceService service;
  final ValueChanged<List<ActiveUserPresence>> onActiveUsersChanged;
  final ValueChanged<Object> onActiveUsersError;

  @override
  State<_ActiveUsersDialog> createState() => _ActiveUsersDialogState();
}

class _ActiveUsersDialogState extends State<_ActiveUsersDialog>
    with SingleTickerProviderStateMixin {
  static const Duration _autoCloseDelay = Duration(seconds: 25);

  late final TabController _tabController;
  Timer? _autoCloseTimer;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);
    _autoCloseTimer = Timer(_autoCloseDelay, _closeIfOpen);
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging || _tabController.index != _tabIndex) {
      setState(() {
        _tabIndex = _tabController.index;
      });
    }
  }

  void _closeIfOpen() {
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Usuarios', style: TextStyle(color: Color(0xFFE5E7EB))),
      content: SizedBox(
        width: 720,
        height: 520,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Activos'),
                Tab(text: 'Historial'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _ActiveUsersView(
                    active: _tabIndex == 0,
                    workspaceId: widget.workspaceId,
                    currentUser: widget.currentUser,
                    currentRole: widget.currentRole,
                    service: widget.service,
                    onUsersChanged: widget.onActiveUsersChanged,
                    onLoadError: widget.onActiveUsersError,
                  ),
                  _SessionHistoryView(
                    active: _tabIndex == 1,
                    workspaceId: widget.workspaceId,
                    service: widget.service,
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
    );
  }
}

class _ActiveUsersView extends StatefulWidget {
  const _ActiveUsersView({
    required this.active,
    required this.workspaceId,
    required this.currentUser,
    required this.currentRole,
    required this.service,
    required this.onUsersChanged,
    required this.onLoadError,
  });

  final bool active;
  final String workspaceId;
  final User currentUser;
  final String? currentRole;
  final PresenceService service;
  final ValueChanged<List<ActiveUserPresence>> onUsersChanged;
  final ValueChanged<Object> onLoadError;

  @override
  State<_ActiveUsersView> createState() => _ActiveUsersViewState();
}

class _ActiveUsersViewState extends State<_ActiveUsersView> {
  static const Duration _refreshInterval = Duration(seconds: 15);

  Timer? _refreshTimer;
  List<ActiveUserPresence>? _users;
  Object? _error;
  bool _loading = true;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _startPolling();
    }
  }

  @override
  void didUpdateWidget(covariant _ActiveUsersView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      if (widget.active) {
        _startPolling();
      } else {
        _stopPolling();
      }
    }
    if (oldWidget.workspaceId != widget.workspaceId ||
        oldWidget.service != widget.service) {
      _requestGeneration += 1;
      setState(() {
        _users = null;
        _error = null;
        _loading = true;
      });
      if (widget.active) {
        _loadUsers();
      }
    }
  }

  @override
  void dispose() {
    _stopPolling();
    _requestGeneration += 1;
    super.dispose();
  }

  void _startPolling() {
    if (_refreshTimer != null) {
      return;
    }
    _loadUsers();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _loadUsers());
  }

  void _stopPolling() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _requestGeneration += 1;
  }

  Future<void> _loadUsers() async {
    final int generation = _requestGeneration;
    try {
      final List<ActiveUserPresence> loaded = await widget.service
          .fetchActiveUsers(workspaceId: widget.workspaceId);
      final List<ActiveUserPresence> users = _withCurrentUser(loaded);
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _users = users;
        _error = null;
        _loading = false;
      });
      widget.onUsersChanged(users);
    } catch (error) {
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
      widget.onLoadError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _users == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _users == null) {
      return Center(
        child: Text(
          'Error al cargar usuarios activos:\n$_error',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFFCA5A5)),
        ),
      );
    }

    final List<ActiveUserPresence> users =
        _users ?? const <ActiveUserPresence>[];
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
  }

  List<ActiveUserPresence> _withCurrentUser(List<ActiveUserPresence> users) {
    if (users.any(
      (ActiveUserPresence user) => user.uid == widget.currentUser.uid,
    )) {
      return users;
    }
    return <ActiveUserPresence>[
      _presenceForCurrentUser(widget.currentUser, widget.currentRole),
      ...users,
    ];
  }
}

ActiveUserPresence _presenceForCurrentUser(User user, String? role) {
  final DateTime now = DateTime.now();
  final String email = user.email ?? '';
  final String displayName = user.displayName?.trim().isNotEmpty == true
      ? user.displayName!.trim()
      : email.contains('@')
      ? email.substring(0, email.indexOf('@'))
      : user.uid;
  return ActiveUserPresence(
    uid: user.uid,
    displayName: displayName,
    email: email,
    role: role ?? '',
    currentSessionId: '',
    activeSince: now,
    lastSeenAt: now,
  );
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
  const _SessionHistoryView({
    required this.active,
    required this.workspaceId,
    required this.service,
  });

  final bool active;
  final String workspaceId;
  final PresenceService service;

  @override
  State<_SessionHistoryView> createState() => _SessionHistoryViewState();
}

class _SessionHistoryViewState extends State<_SessionHistoryView> {
  static const int _pageSize = 30;

  _HistoryViewMode _mode = _HistoryViewMode.porEvento;
  final List<UserActivitySession> _sessions = <UserActivitySession>[];
  UserActivitySessionPage? _lastPage;
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _loadSessions();
    }
  }

  @override
  void didUpdateWidget(covariant _SessionHistoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceId != widget.workspaceId ||
        oldWidget.service != widget.service) {
      _resetSessions();
    }
    if (oldWidget.active != widget.active &&
        widget.active &&
        _sessions.isEmpty) {
      _loadSessions();
    }
  }

  void _resetSessions() {
    _sessions.clear();
    _lastPage = null;
    _loading = false;
    _hasMore = true;
    _error = null;
    if (widget.active) {
      _loadSessions();
    }
  }

  Future<void> _loadSessions() async {
    if (_loading || !_hasMore) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final UserActivitySessionPage page = await widget.service
          .fetchUserSessionsPage(
            workspaceId: widget.workspaceId,
            pageSize: _pageSize,
            startAfterDocument: _lastPage?.lastDocument,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _sessions.addAll(page.sessions);
        _lastPage = page;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Widget _buildLoadMoreButton() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Text(
            'No hay mas sesiones',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Center(
        child: TextButton(
          onPressed: _loadSessions,
          child: const Text('Cargar mas'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _sessions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _sessions.isEmpty) {
      return Center(
        child: Text(
          'Error al cargar historial:\n$_error',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFFCA5A5)),
        ),
      );
    }

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
              onTap: () => setState(() => _mode = _HistoryViewMode.porEvento),
            ),
            _ViewModeButton(
              icon: Icons.people_alt_rounded,
              label: 'Por usuario',
              selected: _mode == _HistoryViewMode.porUsuario,
              isFirst: false,
              isLast: true,
              onTap: () => setState(() => _mode = _HistoryViewMode.porUsuario),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Error al cargar mas sesiones: $_error',
              style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12),
            ),
          ),
        if (_sessions.isEmpty)
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
              itemCount: _sessions.length + 1,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int index) {
                if (index == _sessions.length) {
                  return _buildLoadMoreButton();
                }
                return _SessionTile(
                  session: _sessions[index],
                  service: widget.service,
                );
              },
            ),
          )
        else
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: _SessionsByUserView(
                    sessions: _sessions,
                    service: widget.service,
                  ),
                ),
                _buildLoadMoreButton(),
              ],
            ),
          ),
      ],
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
              color: selected
                  ? const Color(0xFF38BDF8)
                  : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF38BDF8)
                    : const Color(0xFF64748B),
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionsByUserView extends StatelessWidget {
  const _SessionsByUserView({required this.sessions, required this.service});

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
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
                (UserActivitySession s) =>
                    _SessionTileCompact(session: s, service: service),
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
          _MetaText(label: 'Inicio', value: _formatDateTime(session.loginAt)),
          _MetaText(label: 'Cierre', value: _formatDateTime(closedAt)),
          _MetaText(
            label: 'Duración',
            value: _formatDurationSeconds(durationSeconds),
          ),
          _MetaText(label: 'Motivo', value: reason.isEmpty ? 'activa' : reason),
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
