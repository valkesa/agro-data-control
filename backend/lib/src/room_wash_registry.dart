class RoomKey {
  const RoomKey({
    required this.tenantId,
    required this.siteId,
    required this.roomId,
  });

  final String tenantId;
  final String siteId;
  final String roomId;

  @override
  bool operator ==(Object other) {
    return other is RoomKey &&
        other.tenantId == tenantId &&
        other.siteId == siteId &&
        other.roomId == roomId;
  }

  @override
  int get hashCode => Object.hash(tenantId, siteId, roomId);
}

class RoomWashState {
  const RoomWashState({
    required this.key,
    required this.washedAt,
    this.createdAt,
    this.createdByUid,
    this.roomNumber,
  });

  final RoomKey key;
  final DateTime washedAt;
  final DateTime? createdAt;
  final String? createdByUid;
  final int? roomNumber;
}

class RoomWashRegistry {
  RoomWashRegistry({this.washWindow = const Duration(hours: 2)});

  final Duration washWindow;
  final Map<RoomKey, RoomWashState> _latestByRoom = <RoomKey, RoomWashState>{};

  int get count => _latestByRoom.length;

  int get size => _latestByRoom.length;

  int sizeForTenantSite({required String tenantId, required String siteId}) {
    return _latestByRoom.keys
        .where(
          (RoomKey key) => key.tenantId == tenantId && key.siteId == siteId,
        )
        .length;
  }

  RoomWashState registerWash({
    required String tenantId,
    required String siteId,
    required String roomId,
    int? roomNumber,
    required DateTime washedAt,
    DateTime? createdAt,
    String? createdByUid,
  }) {
    final RoomKey key = RoomKey(
      tenantId: tenantId,
      siteId: siteId,
      roomId: roomId,
    );
    final RoomWashState state = RoomWashState(
      key: key,
      roomNumber: roomNumber,
      washedAt: washedAt,
      createdAt: createdAt,
      createdByUid: createdByUid,
    );
    final RoomWashState? current = _latestByRoom[key];
    if (current == null || !washedAt.isBefore(current.washedAt)) {
      _latestByRoom[key] = state;
      return state;
    }
    return current;
  }

  RoomWashState? latestWashFor({
    required String tenantId,
    required String siteId,
    required String roomId,
  }) {
    return _latestByRoom[RoomKey(
      tenantId: tenantId,
      siteId: siteId,
      roomId: roomId,
    )];
  }

  bool isWithinWashWindow({
    required String tenantId,
    required String siteId,
    required String roomId,
    required DateTime now,
  }) {
    final RoomWashState? state = latestWashFor(
      tenantId: tenantId,
      siteId: siteId,
      roomId: roomId,
    );
    if (state == null || now.isBefore(state.washedAt)) {
      return false;
    }
    return now.isBefore(state.washedAt.add(washWindow));
  }

  void clearAll() {
    _latestByRoom.clear();
  }

  void clearForTenantSite({required String tenantId, required String siteId}) {
    _latestByRoom.removeWhere(
      (RoomKey key, _) => key.tenantId == tenantId && key.siteId == siteId,
    );
  }

  void clearForRoom({
    required String tenantId,
    required String siteId,
    required String roomId,
  }) {
    _latestByRoom.remove(
      RoomKey(tenantId: tenantId, siteId: siteId, roomId: roomId),
    );
  }
}
