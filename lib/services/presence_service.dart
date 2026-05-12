import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';

class ActiveUserPresence {
  const ActiveUserPresence({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.role,
    required this.currentSessionId,
    required this.activeSince,
    required this.lastSeenAt,
  });

  final String uid;
  final String displayName;
  final String email;
  final String role;
  final String currentSessionId;
  final DateTime? activeSince;
  final DateTime? lastSeenAt;

  static ActiveUserPresence fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
    return ActiveUserPresence(
      uid: data['uid']?.toString() ?? doc.id,
      displayName: data['displayName']?.toString() ?? '',
      email: data['email']?.toString() ?? '',
      role: data['role']?.toString() ?? '',
      currentSessionId: data['currentSessionId']?.toString() ?? '',
      activeSince: _readDateTime(data['activeSince']),
      lastSeenAt: _readDateTime(data['lastSeenAt']),
    );
  }
}

class UserActivitySession {
  const UserActivitySession({
    required this.sessionId,
    required this.uid,
    required this.displayName,
    required this.email,
    required this.role,
    required this.loginAt,
    required this.activeSince,
    required this.lastSeenAt,
    required this.closedAt,
    required this.closeReason,
    required this.activeDurationSeconds,
    required this.isActive,
    required this.platform,
    required this.userAgent,
  });

  final String sessionId;
  final String uid;
  final String displayName;
  final String email;
  final String role;
  final DateTime? loginAt;
  final DateTime? activeSince;
  final DateTime? lastSeenAt;
  final DateTime? closedAt;
  final String closeReason;
  final int? activeDurationSeconds;
  final bool isActive;
  final String platform;
  final String userAgent;

  bool isFresh(Duration activeThreshold, DateTime now) {
    final DateTime? value = lastSeenAt;
    return isActive &&
        value != null &&
        value.isAfter(now.subtract(activeThreshold));
  }

  DateTime? effectiveClosedAt(Duration activeThreshold, DateTime now) {
    if (!isActive) {
      return closedAt;
    }
    if (isFresh(activeThreshold, now)) {
      return null;
    }
    final DateTime? value = lastSeenAt;
    return value?.add(activeThreshold);
  }

  String effectiveCloseReason(Duration activeThreshold, DateTime now) {
    if (!isActive) {
      return closeReason;
    }
    return isFresh(activeThreshold, now) ? '' : 'inactivity_timeout';
  }

  int? effectiveDurationSeconds(Duration activeThreshold, DateTime now) {
    if (activeDurationSeconds != null && !isActive) {
      return activeDurationSeconds;
    }
    final DateTime? start = activeSince ?? loginAt;
    final DateTime end = effectiveClosedAt(activeThreshold, now) ?? now;
    if (start == null) {
      return null;
    }
    return end.difference(start).inSeconds.clamp(0, 1 << 31);
  }

  static UserActivitySession fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
    return UserActivitySession(
      sessionId: data['sessionId']?.toString() ?? doc.id,
      uid: data['uid']?.toString() ?? '',
      displayName: data['displayName']?.toString() ?? '',
      email: data['email']?.toString() ?? '',
      role: data['role']?.toString() ?? '',
      loginAt: _readDateTime(data['loginAt']),
      activeSince: _readDateTime(data['activeSince']),
      lastSeenAt: _readDateTime(data['lastSeenAt']),
      closedAt: _readDateTime(data['closedAt']),
      closeReason: data['closeReason']?.toString() ?? '',
      activeDurationSeconds: _readInt(data['activeDurationSeconds']),
      isActive: data['isActive'] == true,
      platform: data['platform']?.toString() ?? '',
      userAgent: data['userAgent']?.toString() ?? '',
    );
  }
}

class PresenceService {
  const PresenceService({
    FirebaseFirestore? firestore,
    this.activeThreshold = const Duration(minutes: 5),
  }) : _firestore = firestore;

  final FirebaseFirestore? _firestore;
  final Duration activeThreshold;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _presenceCollection(
    String workspaceId,
  ) {
    return _db.collection(
      FirestorePaths.workspacePresenceCollection(workspaceId),
    );
  }

  CollectionReference<Map<String, dynamic>> _sessionsCollection(
    String workspaceId,
  ) {
    return _db.collection(
      FirestorePaths.workspaceUserSessionsCollection(workspaceId),
    );
  }

  DocumentReference<Map<String, dynamic>> _presenceDoc({
    required String workspaceId,
    required String uid,
  }) {
    return _db.doc(FirestorePaths.workspacePresenceDoc(workspaceId, uid));
  }

  DocumentReference<Map<String, dynamic>> _sessionDoc({
    required String workspaceId,
    required String sessionId,
  }) {
    return _db.doc(
      FirestorePaths.workspaceUserSessionDoc(workspaceId, sessionId),
    );
  }

  Stream<List<ActiveUserPresence>> watchActiveUsers({
    required String workspaceId,
    int limit = 50,
  }) {
    late StreamSubscription<QuerySnapshot<Map<String, dynamic>>> subscription;
    Timer? timer;
    QuerySnapshot<Map<String, dynamic>>? latestSnapshot;

    late StreamController<List<ActiveUserPresence>> controller;
    controller = StreamController<List<ActiveUserPresence>>(
      onListen: () {
        void emit() {
          final QuerySnapshot<Map<String, dynamic>>? snapshot = latestSnapshot;
          if (snapshot == null || controller.isClosed) {
            return;
          }
          controller.add(_activeUsersFromSnapshot(snapshot));
        }

        subscription = _presenceCollection(workspaceId)
            .where('isOnline', isEqualTo: true)
            .orderBy('lastSeenAt', descending: true)
            .limit(limit)
            .snapshots()
            .listen((QuerySnapshot<Map<String, dynamic>> snapshot) {
              latestSnapshot = snapshot;
              emit();
            }, onError: controller.addError);
        timer = Timer.periodic(const Duration(seconds: 30), (_) => emit());
      },
      onCancel: () async {
        timer?.cancel();
        await subscription.cancel();
      },
    );
    return controller.stream;
  }

  List<ActiveUserPresence> _activeUsersFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final DateTime minLastSeen = DateTime.now().subtract(activeThreshold);
    return snapshot.docs
        .map(ActiveUserPresence.fromFirestore)
        .where((ActiveUserPresence user) {
          final DateTime? lastSeenAt = user.lastSeenAt;
          return lastSeenAt != null && lastSeenAt.isAfter(minLastSeen);
        })
        .toList(growable: false);
  }

  Stream<List<UserActivitySession>> watchUserSessions({
    required String workspaceId,
    int limit = 100,
  }) {
    late StreamSubscription<QuerySnapshot<Map<String, dynamic>>> subscription;
    Timer? timer;
    QuerySnapshot<Map<String, dynamic>>? latestSnapshot;
    late StreamController<List<UserActivitySession>> controller;

    controller = StreamController<List<UserActivitySession>>(
      onListen: () {
        void emit() {
          final QuerySnapshot<Map<String, dynamic>>? snapshot = latestSnapshot;
          if (snapshot == null || controller.isClosed) {
            return;
          }
          controller.add(
            snapshot.docs
                .map(UserActivitySession.fromFirestore)
                .toList(growable: false),
          );
        }

        subscription = _sessionsCollection(workspaceId)
            .orderBy('loginAt', descending: true)
            .limit(limit)
            .snapshots()
            .listen((QuerySnapshot<Map<String, dynamic>> snapshot) {
              latestSnapshot = snapshot;
              emit();
            }, onError: controller.addError);
        timer = Timer.periodic(const Duration(seconds: 30), (_) => emit());
      },
      onCancel: () async {
        timer?.cancel();
        await subscription.cancel();
      },
    );
    return controller.stream;
  }

  Future<String?> markOnline({
    required String workspaceId,
    required User user,
    required String? role,
  }) async {
    final String email = user.email ?? '';
    final String displayName = _displayNameFor(user);

    try {
      final DateTime now = DateTime.now();
      final QuerySnapshot<Map<String, dynamic>> activeSessions =
          await _sessionsCollection(workspaceId)
              .where('uid', isEqualTo: user.uid)
              .where('isActive', isEqualTo: true)
              .orderBy('lastSeenAt', descending: true)
              .limit(10)
              .get();

      String? freshSessionId;
      DateTime? freshActiveSince;
      final WriteBatch staleBatch = _db.batch();
      var staleWriteCount = 0;
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in activeSessions.docs) {
        final UserActivitySession session = UserActivitySession.fromFirestore(
          doc,
        );
        final DateTime? lastSeenAt = session.lastSeenAt;
        final DateTime? activeSince = session.activeSince ?? session.loginAt;
        if (lastSeenAt == null || activeSince == null) {
          continue;
        }
        if (session.isFresh(activeThreshold, now)) {
          if (freshSessionId == null) {
            freshSessionId = session.sessionId;
            freshActiveSince = activeSince;
            continue;
          }
          staleBatch.update(doc.reference, <String, Object?>{
            'closedAt': Timestamp.fromDate(now),
            'closeReason': 'session_replaced',
            'activeDurationSeconds': _durationSeconds(activeSince, now),
            'isActive': false,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          staleWriteCount += 1;
          continue;
        }

        final DateTime closedAt = lastSeenAt.add(activeThreshold);
        staleBatch.update(doc.reference, <String, Object?>{
          'closedAt': Timestamp.fromDate(closedAt),
          'closeReason': 'inactivity_timeout',
          'activeDurationSeconds': _durationSeconds(activeSince, closedAt),
          'isActive': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        staleWriteCount += 1;
      }
      if (staleWriteCount > 0) {
        await staleBatch.commit();
      }

      final String sessionId =
          freshSessionId ?? _sessionsCollection(workspaceId).doc().id;
      final DateTime activeSince = freshActiveSince ?? now;
      final WriteBatch batch = _db.batch();
      final DocumentReference<Map<String, dynamic>> sessionRef = _sessionDoc(
        workspaceId: workspaceId,
        sessionId: sessionId,
      );

      if (freshSessionId == null) {
        batch.set(sessionRef, <String, Object?>{
          'sessionId': sessionId,
          'uid': user.uid,
          'displayName': displayName,
          'email': email,
          'role': role ?? '',
          'loginAt': FieldValue.serverTimestamp(),
          'activeSince': FieldValue.serverTimestamp(),
          'lastSeenAt': FieldValue.serverTimestamp(),
          'closedAt': null,
          'closeReason': '',
          'activeDurationSeconds': null,
          'isActive': true,
          'platform': _platformLabel(),
          'userAgent': '',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        batch.set(sessionRef, <String, Object?>{
          'displayName': displayName,
          'email': email,
          'role': role ?? '',
          'lastSeenAt': FieldValue.serverTimestamp(),
          'isActive': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      batch.set(
        _presenceDoc(workspaceId: workspaceId, uid: user.uid),
        <String, Object?>{
          'uid': user.uid,
          'displayName': displayName,
          'email': email,
          'role': role ?? '',
          'isOnline': true,
          'activeSince': Timestamp.fromDate(activeSince),
          'lastSeenAt': FieldValue.serverTimestamp(),
          'currentSessionId': sessionId,
          'platform': _platformLabel(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await batch.commit();
      return sessionId;
    } catch (error, stackTrace) {
      debugPrint('[Presence] markOnline error=$error');
      debugPrint('[Presence] markOnline stack=$stackTrace');
      return null;
    }
  }

  Future<void> heartbeat({
    required String workspaceId,
    required User user,
    required String? role,
    required String sessionId,
  }) async {
    try {
      final WriteBatch batch = _db.batch();
      batch.set(
        _presenceDoc(workspaceId: workspaceId, uid: user.uid),
        <String, Object?>{
          'uid': user.uid,
          'displayName': _displayNameFor(user),
          'email': user.email ?? '',
          'role': role ?? '',
          'isOnline': true,
          'lastSeenAt': FieldValue.serverTimestamp(),
          'currentSessionId': sessionId,
          'platform': _platformLabel(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      batch.set(
        _sessionDoc(workspaceId: workspaceId, sessionId: sessionId),
        <String, Object?>{
          'displayName': _displayNameFor(user),
          'email': user.email ?? '',
          'role': role ?? '',
          'lastSeenAt': FieldValue.serverTimestamp(),
          'isActive': true,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await batch.commit();
    } catch (error, stackTrace) {
      debugPrint('[Presence] heartbeat error=$error');
      debugPrint('[Presence] heartbeat stack=$stackTrace');
    }
  }

  Future<void> markOffline({
    required String workspaceId,
    required User user,
    required String closeReason,
    String? sessionId,
  }) async {
    try {
      final DocumentReference<Map<String, dynamic>> presenceRef = _presenceDoc(
        workspaceId: workspaceId,
        uid: user.uid,
      );
      final DocumentSnapshot<Map<String, dynamic>> presenceSnapshot =
          await presenceRef.get();
      final String? resolvedSessionId =
          sessionId ?? presenceSnapshot.data()?['currentSessionId']?.toString();
      final DateTime now = DateTime.now();
      final WriteBatch batch = _db.batch();

      if (resolvedSessionId != null && resolvedSessionId.isNotEmpty) {
        final DocumentReference<Map<String, dynamic>> sessionRef = _sessionDoc(
          workspaceId: workspaceId,
          sessionId: resolvedSessionId,
        );
        final DocumentSnapshot<Map<String, dynamic>> sessionSnapshot =
            await sessionRef.get();
        final UserActivitySession session = UserActivitySession.fromFirestore(
          sessionSnapshot,
        );
        final DateTime activeSince =
            session.activeSince ?? session.loginAt ?? now;
        batch.set(sessionRef, <String, Object?>{
          'closedAt': Timestamp.fromDate(now),
          'closeReason': closeReason,
          'activeDurationSeconds': _durationSeconds(activeSince, now),
          'isActive': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      batch.set(presenceRef, <String, Object?>{
        'uid': user.uid,
        'displayName': _displayNameFor(user),
        'email': user.email ?? '',
        'isOnline': false,
        'lastSeenAt': Timestamp.fromDate(now),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();
    } catch (error, stackTrace) {
      debugPrint('[Presence] markOffline error=$error');
      debugPrint('[Presence] markOffline stack=$stackTrace');
    }
  }

  String _displayNameFor(User user) {
    final String? displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    final String email = user.email ?? '';
    final int atIndex = email.indexOf('@');
    if (atIndex > 0) {
      return email.substring(0, atIndex);
    }
    return user.uid;
  }

  String _platformLabel() {
    if (kIsWeb) {
      return 'web';
    }
    return defaultTargetPlatform.name;
  }
}

DateTime? _readDateTime(Object? value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  return null;
}

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

int _durationSeconds(DateTime start, DateTime end) {
  return end.difference(start).inSeconds.clamp(0, 1 << 31).toInt();
}
