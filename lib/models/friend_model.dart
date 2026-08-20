/// `friendships.status` 값 — 이 프로젝트는 거절/삭제를 별도 상태로 두지
/// 않고 행 자체를 지운다([FriendManager.declineRequest] 참고). accepted가
/// 된 이후에는 [FriendEntry] 쪽에서만 다뤄지고, 이 값 자체를 다시 참조할
/// 일이 없다.
class FriendshipStatus {
  const FriendshipStatus._();

  static const String pending = 'pending';
  static const String accepted = 'accepted';
}

/// 온라인 판정 기준 — `profiles.last_seen`이 이 시간 이내면 온라인으로
/// 취급한다(요구사항: "5분 이내면 🟢, 그 이상이면 ⚪").
const Duration onlineThreshold = Duration(minutes: 5);

/// [FriendEntry]/[FriendRequestEntry]/[UserSearchResult]가 공유하는 "이
/// 유저가 최근에 접속했는지" 판정 + 표시 텍스트 포맷팅. `profiles
/// .last_seen`은 UTC ISO8601 문자열로 저장되므로([SupabaseManager
/// .updateLastSeen]), 비교도 항상 UTC 기준으로 한다.
mixin OnlinePresence {
  DateTime? get lastSeen;

  bool get isOnline =>
      lastSeen != null && DateTime.now().toUtc().difference(lastSeen!) <= onlineThreshold;

  /// 친구 목록 타일에 그대로 쓰는 문구 — 온라인이면 "온라인", 아니면
  /// "N분/시간/일 전 접속", 접속 기록 자체가 없으면(아직 한 번도
  /// [SupabaseManager.updateLastSeen]이 불리지 않은 극초반 계정) "접속
  /// 기록 없음".
  String get presenceLabel {
    final DateTime? seen = lastSeen;
    if (seen == null) {
      return '접속 기록 없음';
    }
    if (isOnline) {
      return '온라인';
    }
    final Duration gap = DateTime.now().toUtc().difference(seen);
    if (gap.inMinutes < 60) {
      return '${gap.inMinutes}분 전 접속';
    }
    if (gap.inHours < 24) {
      return '${gap.inHours}시간 전 접속';
    }
    return '${gap.inDays}일 전 접속';
  }

  static DateTime? parseLastSeen(dynamic raw) {
    if (raw is! String) {
      return null;
    }
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }
}

/// `profiles.equipped_character`([Equipment.gradeBadgeLabel] 형식, 예:
/// "N1")를 읽어 [CharacterFacePortrait]에 그대로 넘길 수 있게 정리한다 —
/// 비어있으면(아직 갱신된 적 없는 옛 계정 등) null로 취급해 호출부가
/// 기본 아바타 아이콘으로 대체할 수 있게 한다.
String? parseEquippedCharacter(dynamic raw) {
  if (raw is! String || raw.trim().isEmpty) {
    return null;
  }
  return raw;
}

/// 내 친구 목록 한 명 — [FriendManager.friends]가 `friendships`(accepted)
/// + `profiles`(닉네임/전투력/최종 접속)를 클라이언트에서 합쳐 만든다.
class FriendEntry with OnlinePresence {
  const FriendEntry({
    required this.userId,
    required this.nickname,
    required this.combatPower,
    required this.lastSeen,
    this.equippedCharacter,
  });

  final String userId;
  final String nickname;
  final int combatPower;
  final String? equippedCharacter;

  @override
  final DateTime? lastSeen;

  factory FriendEntry.fromProfileJson(Map<String, dynamic> json) {
    final String? nickname = json['nickname'] as String?;
    return FriendEntry(
      userId: json['id'] as String,
      nickname: (nickname == null || nickname.trim().isEmpty) ? '익명의 모험가' : nickname,
      combatPower: (json['combat_power'] as num?)?.toInt() ?? 0,
      lastSeen: OnlinePresence.parseLastSeen(json['last_seen']),
      equippedCharacter: parseEquippedCharacter(json['equipped_character']),
    );
  }
}

/// [FriendManager.incomingRequests] 한 건 — 나에게 친구 요청을 보낸 사람.
class FriendRequestEntry with OnlinePresence {
  const FriendRequestEntry({
    required this.userId,
    required this.nickname,
    required this.combatPower,
    required this.lastSeen,
    this.equippedCharacter,
  });

  final String userId;
  final String nickname;
  final int combatPower;
  final String? equippedCharacter;

  @override
  final DateTime? lastSeen;

  factory FriendRequestEntry.fromProfileJson(Map<String, dynamic> json) {
    final String? nickname = json['nickname'] as String?;
    return FriendRequestEntry(
      userId: json['id'] as String,
      nickname: (nickname == null || nickname.trim().isEmpty) ? '익명의 모험가' : nickname,
      combatPower: (json['combat_power'] as num?)?.toInt() ?? 0,
      lastSeen: OnlinePresence.parseLastSeen(json['last_seen']),
      equippedCharacter: parseEquippedCharacter(json['equipped_character']),
    );
  }
}

/// [FriendManager.search] 결과 한 명 — [relationStatus]로 이미 친구거나
/// 이미 요청을 보낸 상대인지 알 수 있다(그 경우 [FriendSearchTab]이
/// "친구 요청" 버튼 대신 현재 상태를 보여준다).
class UserSearchResult {
  const UserSearchResult({
    required this.userId,
    required this.nickname,
    required this.combatPower,
    required this.relationStatus,
    this.equippedCharacter,
  });

  final String userId;
  final String nickname;
  final int combatPower;
  final String? equippedCharacter;

  /// null(관계 없음) / [FriendshipStatus.pending] / [FriendshipStatus.accepted].
  final String? relationStatus;

  factory UserSearchResult.fromProfileJson(Map<String, dynamic> json, {String? relationStatus}) {
    final String? nickname = json['nickname'] as String?;
    return UserSearchResult(
      userId: json['id'] as String,
      nickname: (nickname == null || nickname.trim().isEmpty) ? '익명의 모험가' : nickname,
      combatPower: (json['combat_power'] as num?)?.toInt() ?? 0,
      relationStatus: relationStatus,
      equippedCharacter: parseEquippedCharacter(json['equipped_character']),
    );
  }
}
