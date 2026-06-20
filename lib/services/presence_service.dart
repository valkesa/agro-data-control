import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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

class UserActivitySessionPage {
  const UserActivitySessionPage({
    required this.sessions,
    required this.lastDocument,
    required this.hasMore,
  });

  final List<UserActivitySession> sessions;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMore;
}

class PresenceService {
  const PresenceService({
    FirebaseFirestore? firestore,
    this.activeThreshold = const Duration(minutes: 5),
    this.writeTimeout = const Duration(seconds: 12),
  }) : _firestore = firestore;

  final FirebaseFirestore? _firestore;
  final Duration activeThreshold;
  final Duration writeTimeout;

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

  Future<List<ActiveUserPresence>> fetchActiveUsers({
    required String workspaceId,
    int limit = 50,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot =
        await _presenceCollection(workspaceId)
            .where('isOnline', isEqualTo: true)
            .orderBy('lastSeenAt', descending: true)
            .limit(limit)
            .get();
    final DateTime minLastSeen = DateTime.now().subtract(activeThreshold);
    final List<ActiveUserPresence> activeUsers = snapshot.docs
        .map(ActiveUserPresence.fromFirestore)
        .where((ActiveUserPresence user) {
          final DateTime? lastSeenAt = user.lastSeenAt;
          return lastSeenAt != null && lastSeenAt.isAfter(minLastSeen);
        })
        .toList(growable: false);
    debugPrint(
      '[Presence] fetchActiveUsers docs=${snapshot.docs.length} '
      'active=${activeUsers.length}',
    );
    return activeUsers;
  }

  Future<UserActivitySessionPage> fetchUserSessionsPage({
    required String workspaceId,
    int pageSize = 30,
    DocumentSnapshot<Map<String, dynamic>>? startAfterDocument,
  }) async {
    Query<Map<String, dynamic>> query = _sessionsCollection(
      workspaceId,
    ).orderBy('loginAt', descending: true).limit(pageSize);
    if (startAfterDocument != null) {
      query = query.startAfterDocument(startAfterDocument);
    }
    final QuerySnapshot<Map<String, dynamic>> snapshot = await query.get();
    final List<UserActivitySession> sessions = snapshot.docs
        .map(UserActivitySession.fromFirestore)
        .toList(growable: false);
    return UserActivitySessionPage(
      sessions: sessions,
      lastDocument: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      hasMore: snapshot.docs.length == pageSize,
    );
  }

  Future<String?> markOnline({
    required String workspaceId,
    required User user,
    required String? role,
  }) async {
    final String email = user.email ?? '';
    final String displayName = _displayNameFor(user);
    final DateTime now = DateTime.now();
    final String sessionId = _sessionsCollection(workspaceId).doc().id;
    final DateTime activeSince = now;
    debugPrint(
      '[Presence] markOnline start '
      'path=${FirestorePaths.workspacePresenceDoc(workspaceId, user.uid)} '
      'uid=${user.uid} role=${role ?? ''}',
    );

    final bool presenceConfirmed = await _writePresence(
      workspaceId: workspaceId,
      user: user,
      role: role,
      sessionId: sessionId,
      activeSince: activeSince,
      now: now,
      source: 'markOnline',
    );
    if (!presenceConfirmed) {
      return null;
    }

    // Session history is best-effort and must never block presence startup.
    unawaited(
      _writeSessionHistory(
        workspaceId: workspaceId,
        user: user,
        role: role,
        sessionId: sessionId,
        displayName: displayName,
        email: email,
        now: now,
      ),
    );

    return sessionId;
  }

  Future<bool> _writePresence({
    required String workspaceId,
    required User user,
    required String? role,
    required String sessionId,
    required DateTime activeSince,
    required DateTime now,
    required String source,
  }) async {
    final DocumentReference<Map<String, dynamic>> presenceRef = _presenceDoc(
      workspaceId: workspaceId,
      uid: user.uid,
    );
    try {
      return await _setAndConfirmPresence(
        presenceRef: presenceRef,
        workspaceId: workspaceId,
        user: user,
        role: role,
        sessionId: sessionId,
        activeSince: activeSince,
        now: now,
        source: source,
      );
    } on TimeoutException catch (error, stackTrace) {
      debugPrint('[Presence] $source presence write timeout=$error');
      debugPrint('[Presence] $source presence write stack=$stackTrace');
      return _writePresenceRest(
        workspaceId: workspaceId,
        user: user,
        role: role,
        sessionId: sessionId,
        activeSince: activeSince,
        now: DateTime.now(),
        source: '$source rest',
      );
    } catch (error, stackTrace) {
      debugPrint('[Presence] $source presence write error=$error');
      debugPrint('[Presence] $source presence write stack=$stackTrace');
      return false;
    }
  }

  Future<bool> _setAndConfirmPresence({
    required DocumentReference<Map<String, dynamic>> presenceRef,
    required String workspaceId,
    required User user,
    required String? role,
    required String sessionId,
    required DateTime activeSince,
    required DateTime now,
    required String source,
  }) async {
    await presenceRef
        .set(<String, Object?>{
          'uid': user.uid,
          'displayName': _displayNameFor(user),
          'email': user.email ?? '',
          'role': role ?? '',
          'isOnline': true,
          'activeSince': Timestamp.fromDate(activeSince),
          'lastSeenAt': Timestamp.fromDate(now),
          'currentSessionId': sessionId,
          'platform': _platformLabel(),
          'updatedAt': Timestamp.fromDate(now),
        })
        .timeout(writeTimeout);
    debugPrint(
      '[Presence] $source presence write success '
      'workspace=$workspaceId sessionId=$sessionId',
    );
    final DocumentSnapshot<Map<String, dynamic>> confirmed = await presenceRef
        .get(const GetOptions(source: Source.server))
        .timeout(writeTimeout);
    final DateTime? confirmedLastSeen = _readDateTime(
      confirmed.data()?['lastSeenAt'],
    );
    debugPrint(
      '[Presence] $source presence server confirm exists=${confirmed.exists} '
      'lastSeenAt=${confirmedLastSeen?.toIso8601String() ?? 'null'}',
    );
    return confirmed.exists;
  }

  Future<bool> _writePresenceRest({
    required String workspaceId,
    required User user,
    required String? role,
    required String sessionId,
    required DateTime activeSince,
    required DateTime now,
    required String source,
  }) async {
    try {
      final String token = await user.getIdToken(true) ?? '';
      final Uri uri = _firestoreDocumentUri(
        FirestorePaths.workspacePresenceDoc(workspaceId, user.uid),
      );
      final http.Response response = await http
          .patch(
            uri,
            headers: <String, String>{
              'authorization': 'Bearer $token',
              'content-type': 'application/json',
            },
            body: jsonEncode(<String, Object?>{
              'fields': <String, Object?>{
                'uid': _stringValue(user.uid),
                'displayName': _stringValue(_displayNameFor(user)),
                'email': _stringValue(user.email ?? ''),
                'role': _stringValue(role ?? ''),
                'isOnline': _boolValue(true),
                'activeSince': _timestampValue(activeSince),
                'lastSeenAt': _timestampValue(now),
                'currentSessionId': _stringValue(sessionId),
                'platform': _stringValue(_platformLabel()),
                'updatedAt': _timestampValue(now),
              },
            }),
          )
          .timeout(writeTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint(
          '[Presence] $source presence REST write success '
          'workspace=$workspaceId sessionId=$sessionId',
        );
        return true;
      }
      debugPrint(
        '[Presence] $source presence REST write failed '
        'status=${response.statusCode} body=${response.body}',
      );
      return false;
    } catch (error, stackTrace) {
      debugPrint('[Presence] $source presence REST write error=$error');
      debugPrint('[Presence] $source presence REST write stack=$stackTrace');
      return false;
    }
  }

  Uri _firestoreDocumentUri(String documentPath) {
    final String projectId = Firebase.app().options.projectId;
    return Uri.https(
      'firestore.googleapis.com',
      '/v1/projects/$projectId/databases/(default)/documents/$documentPath',
    );
  }

  Map<String, String> _stringValue(String value) {
    return <String, String>{'stringValue': value};
  }

  Map<String, bool> _boolValue(bool value) {
    return <String, bool>{'booleanValue': value};
  }

  Map<String, String> _timestampValue(DateTime value) {
    return <String, String>{'timestampValue': value.toUtc().toIso8601String()};
  }

  Map<String, String> _nullValue() {
    return <String, String>{'nullValue': 'NULL_VALUE'};
  }

  Future<void> _writeSessionHistory({
    required String workspaceId,
    required User user,
    required String? role,
    required String sessionId,
    required String displayName,
    required String email,
    required DateTime now,
  }) async {
    try {
      await _closeExistingSessions(
        workspaceId: workspaceId,
        uid: user.uid,
        currentSessionId: sessionId,
        now: now,
      );
      final DocumentReference<Map<String, dynamic>> sessionRef = _sessionDoc(
        workspaceId: workspaceId,
        sessionId: sessionId,
      );
      await sessionRef
          .set(<String, Object?>{
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
          })
          .timeout(writeTimeout);
      debugPrint(
        '[Presence] markOnline session create success '
        'workspace=$workspaceId sessionId=$sessionId',
      );
    } on TimeoutException catch (error, stackTrace) {
      debugPrint('[Presence] markOnline session write timeout=$error');
      debugPrint('[Presence] markOnline session write stack=$stackTrace');
      await _writeSessionHistoryRest(
        workspaceId: workspaceId,
        user: user,
        role: role,
        sessionId: sessionId,
        displayName: displayName,
        email: email,
        now: now,
      );
    } catch (error, stackTrace) {
      debugPrint('[Presence] markOnline session write error=$error');
      debugPrint('[Presence] markOnline session write stack=$stackTrace');
    }
  }

  Future<void> _writeSessionHistoryRest({
    required String workspaceId,
    required User user,
    required String? role,
    required String sessionId,
    required String displayName,
    required String email,
    required DateTime now,
  }) async {
    try {
      final String token = await user.getIdToken(true) ?? '';
      final Uri uri = _firestoreDocumentUri(
        FirestorePaths.workspaceUserSessionDoc(workspaceId, sessionId),
      );
      final http.Response response = await http
          .patch(
            uri,
            headers: <String, String>{
              'authorization': 'Bearer $token',
              'content-type': 'application/json',
            },
            body: jsonEncode(<String, Object?>{
              'fields': <String, Object?>{
                'sessionId': _stringValue(sessionId),
                'uid': _stringValue(user.uid),
                'displayName': _stringValue(displayName),
                'email': _stringValue(email),
                'role': _stringValue(role ?? ''),
                'loginAt': _timestampValue(now),
                'activeSince': _timestampValue(now),
                'lastSeenAt': _timestampValue(now),
                'closedAt': _nullValue(),
                'closeReason': _stringValue(''),
                'activeDurationSeconds': _nullValue(),
                'isActive': _boolValue(true),
                'platform': _stringValue(_platformLabel()),
                'userAgent': _stringValue(''),
                'createdAt': _timestampValue(now),
                'updatedAt': _timestampValue(now),
              },
            }),
          )
          .timeout(writeTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint(
          '[Presence] markOnline session REST create success '
          'workspace=$workspaceId sessionId=$sessionId',
        );
        return;
      }
      debugPrint(
        '[Presence] markOnline session REST write failed '
        'status=${response.statusCode} body=${response.body}',
      );
    } catch (error, stackTrace) {
      debugPrint('[Presence] markOnline session REST write error=$error');
      debugPrint('[Presence] markOnline session REST write stack=$stackTrace');
    }
  }

  Future<void> _closeExistingSessions({
    required String workspaceId,
    required String uid,
    required String currentSessionId,
    required DateTime now,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> activeSessions =
        await _sessionsCollection(workspaceId)
            .where('uid', isEqualTo: uid)
            .where('isActive', isEqualTo: true)
            .orderBy('lastSeenAt', descending: true)
            .limit(10)
            .get();

    final WriteBatch staleBatch = _db.batch();
    var staleWriteCount = 0;
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in activeSessions.docs) {
      final UserActivitySession session = UserActivitySession.fromFirestore(
        doc,
      );
      if (session.sessionId == currentSessionId) {
        continue;
      }
      final DateTime? lastSeenAt = session.lastSeenAt;
      final DateTime? activeSince = session.activeSince ?? session.loginAt;
      if (lastSeenAt == null || activeSince == null) {
        continue;
      }
      final DateTime closedAt = session.isFresh(activeThreshold, now)
          ? now
          : lastSeenAt.add(activeThreshold);
      staleBatch.update(doc.reference, <String, Object?>{
        'closedAt': Timestamp.fromDate(closedAt),
        'closeReason': session.isFresh(activeThreshold, now)
            ? 'session_replaced'
            : 'inactivity_timeout',
        'activeDurationSeconds': _durationSeconds(activeSince, closedAt),
        'isActive': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      staleWriteCount += 1;
    }
    if (staleWriteCount > 0) {
      await staleBatch.commit();
    }
  }

  Future<void> heartbeat({
    required String workspaceId,
    required User user,
    required String? role,
    required String sessionId,
  }) async {
    final DateTime now = DateTime.now();
    try {
      await _presenceDoc(workspaceId: workspaceId, uid: user.uid)
          .set(<String, Object?>{
            'uid': user.uid,
            'displayName': _displayNameFor(user),
            'email': user.email ?? '',
            'role': role ?? '',
            'isOnline': true,
            'lastSeenAt': Timestamp.fromDate(now),
            'currentSessionId': sessionId,
            'platform': _platformLabel(),
            'updatedAt': Timestamp.fromDate(now),
          }, SetOptions(merge: true))
          .timeout(writeTimeout);
      debugPrint(
        '[Presence] heartbeat presence write success '
        'workspace=$workspaceId sessionId=$sessionId',
      );
    } on TimeoutException catch (error, stackTrace) {
      debugPrint('[Presence] heartbeat presence write timeout=$error');
      debugPrint('[Presence] heartbeat presence write stack=$stackTrace');
      await _writePresenceRest(
        workspaceId: workspaceId,
        user: user,
        role: role,
        sessionId: sessionId,
        activeSince: now,
        now: now,
        source: 'heartbeat rest',
      );
    } catch (error, stackTrace) {
      debugPrint('[Presence] heartbeat presence write error=$error');
      debugPrint('[Presence] heartbeat presence write stack=$stackTrace');
      return;
    }

    try {
      await _sessionDoc(
        workspaceId: workspaceId,
        sessionId: sessionId,
      ).set(<String, Object?>{
        'displayName': _displayNameFor(user),
        'email': user.email ?? '',
        'role': role ?? '',
        'lastSeenAt': FieldValue.serverTimestamp(),
        'isActive': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint(
        '[Presence] heartbeat session write success '
        'workspace=$workspaceId sessionId=$sessionId',
      );
    } catch (error, stackTrace) {
      debugPrint('[Presence] heartbeat session write error=$error');
      debugPrint('[Presence] heartbeat session write stack=$stackTrace');
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
