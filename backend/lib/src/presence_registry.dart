import 'dart:io';

class PresenceRegistry {
  PresenceRegistry({
    this.activeTimeout = const Duration(seconds: 30),
    this.backendVersion = 'current',
  });

  final Duration activeTimeout;
  final String backendVersion;
  final Map<String, PresenceSession> _sessionsById =
      <String, PresenceSession>{};
  int _version = 0;

  void recordSnapshotHeartbeat({
    required String uid,
    required String tenantId,
    required String siteId,
    required String sessionId,
    required DateTime seenAt,
    String? email,
    String? displayName,
    String? userAgent,
    String? ip,
    String? appVersion,
    String? deviceType,
  }) {
    final String cleanedUid = uid.trim();
    final String cleanedSessionId = sessionId.trim();
    final String cleanedTenantId = tenantId.trim();
    final String cleanedSiteId = siteId.trim();
    if (cleanedUid.isEmpty ||
        cleanedSessionId.isEmpty ||
        cleanedTenantId.isEmpty ||
        cleanedSiteId.isEmpty) {
      return;
    }
    _prune(now: seenAt);
    final PresenceSession? existing = _sessionsById[cleanedSessionId];
    if (existing == null) {
      _sessionsById[cleanedSessionId] = PresenceSession(
        sessionId: cleanedSessionId,
        uid: cleanedUid,
        tenantId: cleanedTenantId,
        siteId: cleanedSiteId,
        openedAt: seenAt,
        lastSeen: seenAt,
        email: email?.trim() ?? '',
        displayName: displayName?.trim() ?? '',
        userAgent: userAgent?.trim() ?? '',
        ipMasked: _maskIp(ip),
        appVersion: appVersion?.trim() ?? '',
        deviceType: deviceType?.trim() ?? '',
        backendVersion: backendVersion,
      );
      _version += 1;
      return;
    }
    existing
      ..tenantId = cleanedTenantId
      ..siteId = cleanedSiteId
      ..lastSeen = seenAt
      ..email = _prefer(existing.email, email)
      ..displayName = _prefer(existing.displayName, displayName)
      ..userAgent = _prefer(existing.userAgent, userAgent)
      ..ipMasked = _prefer(existing.ipMasked, _maskIp(ip))
      ..appVersion = _prefer(existing.appVersion, appVersion)
      ..deviceType = _prefer(existing.deviceType, deviceType);
  }

  Map<String, Object?> snapshotJson({
    required String tenantId,
    required String siteId,
    required bool includeDetails,
    DateTime? now,
  }) {
    final DateTime effectiveNow = now ?? DateTime.now().toUtc();
    _prune(now: effectiveNow);
    final List<PresenceSession> scopedSessions = _sessionsById.values
        .where(
          (PresenceSession session) =>
              session.tenantId == tenantId && session.siteId == siteId,
        )
        .toList(growable: false);
    final Map<String, List<PresenceSession>> byUser =
        <String, List<PresenceSession>>{};
    for (final PresenceSession session in scopedSessions) {
      (byUser[session.uid] ??= <PresenceSession>[]).add(session);
    }
    final Map<String, Object?> json = <String, Object?>{
      'generatedAt': effectiveNow.toIso8601String(),
      'activeUsersCount': byUser.length,
      'version': _version,
      'activeTimeoutSeconds': activeTimeout.inSeconds,
    };
    if (includeDetails) {
      final List<Map<String, Object?>> users =
          byUser.entries
              .map((MapEntry<String, List<PresenceSession>> entry) {
                final List<PresenceSession> sessions = entry.value
                  ..sort(
                    (PresenceSession a, PresenceSession b) =>
                        b.lastSeen.compareTo(a.lastSeen),
                  );
                final PresenceSession primary = sessions.first;
                final DateTime firstSeen = sessions
                    .map((PresenceSession session) => session.openedAt)
                    .reduce((DateTime a, DateTime b) => a.isBefore(b) ? a : b);
                final DateTime lastSeen = sessions
                    .map((PresenceSession session) => session.lastSeen)
                    .reduce((DateTime a, DateTime b) => a.isAfter(b) ? a : b);
                final int connectedSeconds = lastSeen
                    .difference(firstSeen)
                    .inSeconds
                    .clamp(0, 1 << 31);
                return <String, Object?>{
                  'uid': entry.key,
                  'displayName': primary.displayName,
                  'email': primary.email,
                  'tenantId': primary.tenantId,
                  'siteIds': sessions
                      .map((PresenceSession session) => session.siteId)
                      .toSet()
                      .toList(growable: false),
                  'activeSessionCount': sessions.length,
                  'firstSeen': firstSeen.toIso8601String(),
                  'lastSeen': lastSeen.toIso8601String(),
                  'connectedSeconds': connectedSeconds,
                  'sessions': sessions
                      .map((PresenceSession session) => session.toJson())
                      .toList(growable: false),
                };
              })
              .toList(growable: false)
            ..sort(
              (Map<String, Object?> a, Map<String, Object?> b) =>
                  (a['displayName']?.toString() ?? a['email']?.toString() ?? '')
                      .toLowerCase()
                      .compareTo(
                        (b['displayName']?.toString() ??
                                b['email']?.toString() ??
                                '')
                            .toLowerCase(),
                      ),
            );
      json['users'] = users;
    }
    return json;
  }

  void _prune({required DateTime now}) {
    final DateTime cutoff = now.subtract(activeTimeout);
    final int before = _sessionsById.length;
    _sessionsById.removeWhere(
      (_, PresenceSession session) => session.lastSeen.isBefore(cutoff),
    );
    if (_sessionsById.length != before) {
      _version += 1;
    }
  }
}

class PresenceSession {
  PresenceSession({
    required this.sessionId,
    required this.uid,
    required this.tenantId,
    required this.siteId,
    required this.openedAt,
    required this.lastSeen,
    required this.email,
    required this.displayName,
    required this.userAgent,
    required this.ipMasked,
    required this.appVersion,
    required this.deviceType,
    required this.backendVersion,
  });

  final String sessionId;
  final String uid;
  String tenantId;
  String siteId;
  final DateTime openedAt;
  DateTime lastSeen;
  String email;
  String displayName;
  String userAgent;
  String ipMasked;
  String appVersion;
  String deviceType;
  String backendVersion;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sessionId': sessionId,
      'siteId': siteId,
      'openedAt': openedAt.toIso8601String(),
      'lastSeen': lastSeen.toIso8601String(),
      if (deviceType.isNotEmpty) 'deviceType': deviceType,
      if (appVersion.isNotEmpty) 'appVersion': appVersion,
      if (backendVersion.isNotEmpty) 'backendVersion': backendVersion,
      if (ipMasked.isNotEmpty) 'ipMasked': ipMasked,
      if (userAgent.isNotEmpty) 'userAgent': userAgent,
    };
  }
}

String _prefer(String current, String? next) {
  final String cleanedNext = next?.trim() ?? '';
  return cleanedNext.isEmpty ? current : cleanedNext;
}

String _maskIp(String? value) {
  final String ip = value?.trim() ?? '';
  if (ip.isEmpty) {
    return '';
  }
  final InternetAddress? parsed = InternetAddress.tryParse(ip);
  final String normalized = parsed?.address ?? ip;
  if (normalized.contains(':')) {
    final List<String> parts = normalized.split(':');
    if (parts.length <= 2) {
      return '***';
    }
    return '${parts.take(2).join(':')}:***';
  }
  final List<String> parts = normalized.split('.');
  if (parts.length != 4) {
    return '***';
  }
  return '${parts[0]}.${parts[1]}.***.${parts[3]}';
}
