class BackendPresenceSnapshot {
  const BackendPresenceSnapshot({
    required this.activeUserCount,
    required this.users,
    required this.receivedAt,
    this.generatedAt,
    this.referenceAt,
    this.stale = false,
  });

  final int activeUserCount;
  final List<BackendPresenceUser> users;
  final DateTime receivedAt;
  final DateTime? generatedAt;
  final DateTime? referenceAt;
  final bool stale;

  bool get hasUsers => users.isNotEmpty;

  BackendPresenceSnapshot copyWith({bool? stale}) {
    return BackendPresenceSnapshot(
      activeUserCount: activeUserCount,
      users: users,
      receivedAt: receivedAt,
      generatedAt: generatedAt,
      referenceAt: referenceAt,
      stale: stale ?? this.stale,
    );
  }

  static BackendPresenceSnapshot? fromSnapshotPayload(
    Map<String, dynamic>? payload, {
    DateTime? receivedAt,
  }) {
    if (payload == null) {
      return null;
    }
    final Object? rawPresence = _firstPath(payload, const <List<String>>[
      <String>['presence'],
      <String>['activeUsers'],
      <String>['connectedUsers'],
    ]);
    final Object? rawUsers = _firstPath(payload, const <List<String>>[
      <String>['presence', 'users'],
      <String>['presence', 'activeUsers'],
      <String>['activeUsers', 'users'],
      <String>['connectedUsers', 'users'],
      <String>['activeUsers'],
      <String>['connectedUsers'],
    ]);

    final List<BackendPresenceUser> users = _parseUsers(rawUsers);
    final int? explicitCount = _readIntFromPaths(payload, const <List<String>>[
      <String>['activeUsersCount'],
      <String>['activeUserCount'],
      <String>['connectedUsersCount'],
      <String>['presence', 'activeUsersCount'],
      <String>['presence', 'activeUserCount'],
      <String>['presence', 'connectedUsersCount'],
      <String>['presence', 'summary', 'activeUsersCount'],
      <String>['presence', 'summary', 'activeUserCount'],
      <String>['activeUsers', 'count'],
      <String>['connectedUsers', 'count'],
    ]);
    if (explicitCount == null && users.isEmpty) {
      return null;
    }

    return BackendPresenceSnapshot(
      activeUserCount: users.isNotEmpty
          ? _uniqueUserCount(users)
          : explicitCount!,
      users: users,
      receivedAt: receivedAt ?? DateTime.now(),
      generatedAt: _readDateTimeFromPresence(rawPresence, const <String>[
        'generatedAt',
        'updatedAt',
        'createdAt',
      ]),
      referenceAt: _readDateTimeFromPresence(rawPresence, const <String>[
        'referenceAt',
        'serverNow',
        'now',
      ]),
    );
  }

  static int _uniqueUserCount(List<BackendPresenceUser> users) {
    final Set<String> keys = <String>{};
    for (final BackendPresenceUser user in users) {
      final String key = user.uid.trim().isNotEmpty
          ? user.uid.trim()
          : user.email.trim().isNotEmpty
          ? user.email.trim()
          : user.displayName.trim();
      if (key.isNotEmpty) {
        keys.add(key);
      }
    }
    return keys.isEmpty ? users.length : keys.length;
  }
}

class BackendPresenceUser {
  const BackendPresenceUser({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.activeSessionCount,
    required this.sessions,
    this.role,
    this.tenantId,
    this.siteIds = const <String>[],
    this.firstSeen,
    this.lastSeen,
    this.connectedSeconds,
  });

  final String uid;
  final String displayName;
  final String email;
  final String? role;
  final String? tenantId;
  final List<String> siteIds;
  final int activeSessionCount;
  final List<BackendPresenceSession> sessions;
  final DateTime? firstSeen;
  final DateTime? lastSeen;
  final int? connectedSeconds;

  String get label {
    if (displayName.trim().isNotEmpty) {
      return displayName.trim();
    }
    if (email.trim().isNotEmpty) {
      return email.trim();
    }
    return uid.trim().isEmpty ? 'Usuario' : uid.trim();
  }
}

class BackendPresenceSession {
  const BackendPresenceSession({
    required this.sessionId,
    this.siteId,
    this.openedAt,
    this.lastSeen,
    this.deviceType,
    this.appVersion,
    this.backendVersion,
    this.ipMasked,
    this.userAgent,
  });

  final String sessionId;
  final String? siteId;
  final DateTime? openedAt;
  final DateTime? lastSeen;
  final String? deviceType;
  final String? appVersion;
  final String? backendVersion;
  final String? ipMasked;
  final String? userAgent;
}

List<BackendPresenceUser> _parseUsers(Object? rawUsers) {
  if (rawUsers is! List) {
    return const <BackendPresenceUser>[];
  }
  final List<BackendPresenceUser> users = <BackendPresenceUser>[];
  for (final Object? rawUser in rawUsers) {
    if (rawUser is! Map) {
      continue;
    }
    final Map<Object?, Object?> data = rawUser;
    final List<BackendPresenceSession> sessions = _parseSessions(
      data['sessions'],
    );
    final int sessionCount =
        _readInt(data['activeSessionCount']) ??
        _readInt(data['sessionCount']) ??
        _readInt(data['sessionsCount']) ??
        (sessions.isEmpty ? 1 : sessions.length);
    users.add(
      BackendPresenceUser(
        uid: _readString(data['uid']),
        displayName: _readString(data['displayName']).isNotEmpty
            ? _readString(data['displayName'])
            : _readString(data['name']),
        email: _readString(data['email']),
        role: _readNullableString(data['role']),
        tenantId: _readNullableString(data['tenantId']),
        siteIds: _readStringList(data['siteIds']).isNotEmpty
            ? _readStringList(data['siteIds'])
            : _readNullableString(data['siteId']) == null
            ? const <String>[]
            : <String>[_readNullableString(data['siteId'])!],
        activeSessionCount: sessionCount,
        sessions: sessions,
        firstSeen:
            _readDateTime(data['firstSeen']) ??
            _readDateTime(data['firstSeenAt']) ??
            _readDateTime(data['openedAt']),
        lastSeen:
            _readDateTime(data['lastSeen']) ??
            _readDateTime(data['lastSeenAt']),
        connectedSeconds:
            _readInt(data['connectedSeconds']) ??
            _readInt(data['totalConnectedSeconds']),
      ),
    );
  }
  return List<BackendPresenceUser>.unmodifiable(users);
}

List<BackendPresenceSession> _parseSessions(Object? rawSessions) {
  if (rawSessions is! List) {
    return const <BackendPresenceSession>[];
  }
  final List<BackendPresenceSession> sessions = <BackendPresenceSession>[];
  for (final Object? rawSession in rawSessions) {
    if (rawSession is! Map) {
      continue;
    }
    final Map<Object?, Object?> data = rawSession;
    sessions.add(
      BackendPresenceSession(
        sessionId: _readString(data['sessionId']).isNotEmpty
            ? _readString(data['sessionId'])
            : _readString(data['id']),
        siteId: _readNullableString(data['siteId']),
        openedAt:
            _readDateTime(data['openedAt']) ??
            _readDateTime(data['firstSeen']) ??
            _readDateTime(data['firstSeenAt']),
        lastSeen:
            _readDateTime(data['lastSeen']) ??
            _readDateTime(data['lastSeenAt']),
        deviceType: _readNullableString(data['deviceType']),
        appVersion: _readNullableString(data['appVersion']),
        backendVersion: _readNullableString(data['backendVersion']),
        ipMasked:
            _readNullableString(data['ipMasked']) ??
            _readNullableString(data['lastIpMasked']),
        userAgent: _readNullableString(data['userAgent']),
      ),
    );
  }
  return List<BackendPresenceSession>.unmodifiable(sessions);
}

Object? _firstPath(Map<String, dynamic> payload, List<List<String>> paths) {
  for (final List<String> path in paths) {
    final Object? value = _readPath(payload, path);
    if (value != null) {
      return value;
    }
  }
  return null;
}

int? _readIntFromPaths(Map<String, dynamic> payload, List<List<String>> paths) {
  for (final List<String> path in paths) {
    final int? value = _readInt(_readPath(payload, path));
    if (value != null) {
      return value;
    }
  }
  return null;
}

Object? _readPath(Map<String, dynamic> payload, List<String> path) {
  Object? current = payload;
  for (final String segment in path) {
    if (current is Map) {
      current = current[segment];
    } else {
      return null;
    }
  }
  return current;
}

DateTime? _readDateTimeFromPresence(Object? rawPresence, List<String> keys) {
  if (rawPresence is! Map) {
    return null;
  }
  for (final String key in keys) {
    final DateTime? value = _readDateTime(rawPresence[key]);
    if (value != null) {
      return value;
    }
  }
  return null;
}

String _readString(Object? value) => value?.toString().trim() ?? '';

String? _readNullableString(Object? value) {
  final String parsed = _readString(value);
  return parsed.isEmpty ? null : parsed;
}

List<String> _readStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .map((Object? item) => item?.toString().trim() ?? '')
      .where((String item) => item.isNotEmpty)
      .toList(growable: false);
}

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

DateTime? _readDateTime(Object? value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value.trim());
  }
  return null;
}
