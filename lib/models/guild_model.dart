import '../constants/guild_emblems.dart';

/// `guilds` 테이블 한 행의 목록용 요약 — [GuildLobbyScreen]의 길드 리스트
/// 카드에 필요한 최소 정보만 담는다. `memberCount`는 별도 컬럼이 아니라
/// PostgREST의 `guild_members(count)` 임베드 집계로 채운다(요구사항에
/// 인원수 컬럼이 명시되지 않아, 실제 멤버 행 수를 세는 쪽이 항상 정확).
class GuildSummary {
  const GuildSummary({
    required this.id,
    required this.name,
    required this.emblem,
    required this.level,
    required this.memberCount,
  });

  final String id;
  final String name;
  final String emblem;
  final int level;
  final int memberCount;

  factory GuildSummary.fromJson(Map<String, dynamic> json) {
    final List<dynamic>? countEmbed = json['guild_members'] as List<dynamic>?;
    final int memberCount = (countEmbed != null && countEmbed.isNotEmpty)
        ? ((countEmbed.first as Map<String, dynamic>)['count'] as num?)?.toInt() ?? 0
        : 0;
    return GuildSummary(
      id: json['id'].toString(),
      name: json['name'] as String,
      emblem: json['emblem'] as String? ?? GuildEmblems.defaultKey,
      level: (json['level'] as num?)?.toInt() ?? 1,
      memberCount: memberCount,
    );
  }
}

/// `guilds` 테이블 한 행 전체 — [GuildMainScreen] 상단 헤더가 쓰는 상세
/// 정보. 실제 컬럼 스키마는 요구사항에 명시되지 않아, 이 장르에서 흔히
/// 쓰는 최소 구성으로 가정했다: `id`, `name`, `emblem`, `level`, `exp`,
/// `notice`, `master_id`.
class GuildInfo {
  const GuildInfo({
    required this.id,
    required this.name,
    required this.emblem,
    required this.level,
    required this.exp,
    required this.notice,
    required this.masterId,
    this.treasuryCoin = 0,
    this.treasuryGem = 0,
  });

  final String id;
  final String name;
  final String emblem;
  final int level;
  final int exp;
  final String notice;
  final String masterId;

  /// 길드 금고(Treasury) — 길드 전쟁 승리 보상(누적 세금 + 최소 보장
  /// 금액)이 여기로 입금된다. 유저 개인 재화([GameManager.gold]/[gems])와
  /// 완전히 분리된 값이라, 길드장이 [GuildWarManager.transferTreasury]로
  /// 명시적으로 분배해야만 개인 재화로 옮겨간다.
  final int treasuryCoin;
  final int treasuryGem;

  factory GuildInfo.fromJson(Map<String, dynamic> json) => GuildInfo(
    id: json['id'].toString(),
    name: json['name'] as String,
    emblem: json['emblem'] as String? ?? GuildEmblems.defaultKey,
    level: (json['level'] as num?)?.toInt() ?? 1,
    exp: (json['exp'] as num?)?.toInt() ?? 0,
    notice: json['notice'] as String? ?? '',
    masterId: json['master_id'] as String? ?? '',
    treasuryCoin: (json['treasury_coin'] as num?)?.toInt() ?? 0,
    treasuryGem: (json['treasury_gem'] as num?)?.toInt() ?? 0,
  );
}

/// [GuildManager.createGuild] 결과 — [SupabaseManager.setNickname]의
/// [NicknameUpdateResult]와 같은 관례: 실패 이유별로 갈래를 나눠서,
/// 호출부([_CreateGuildDialog])가 정확한 안내 문구를 보여줄 수 있게 한다.
enum GuildCreateResult { success, duplicateName, insufficientGems, error }

/// `guild_members.role` 값 — 문자열을 직접 여기저기서 비교하지 않도록
/// enum으로 감싼다.
enum GuildRole { master, elder, member }

GuildRole guildRoleFromString(String? value) => switch (value) {
  'master' => GuildRole.master,
  'elder' => GuildRole.elder,
  _ => GuildRole.member,
};

String guildRoleColumnValue(GuildRole role) => switch (role) {
  GuildRole.master => 'master',
  GuildRole.elder => 'elder',
  GuildRole.member => 'member',
};

String guildRoleLabel(GuildRole role) => switch (role) {
  GuildRole.master => '길드장',
  GuildRole.elder => '부길드장',
  GuildRole.member => '길드원',
};

/// `guild_members` + `profiles(nickname, last_seen)` 임베드 조회 결과 한 행 —
/// [GuildMainScreen]의 "길드원 목록" 탭 리스트 아이템.
class GuildMember {
  const GuildMember({
    required this.userId,
    required this.nickname,
    required this.role,
    required this.contribution,
    this.lastSeen,
  });

  final String userId;
  final String nickname;
  final GuildRole role;
  final int contribution;

  /// `profiles.last_seen` — [SupabaseManager.updateLastSeen]이 앱 실행
  /// 시/주기적으로 갱신하는 접속 heartbeat. 컬럼이 아직 없거나(마이그레이션
  /// 전) 한 번도 접속한 적 없는 계정이면 null.
  final DateTime? lastSeen;

  /// 접속중(🟢) 판정 기준 — 최근 이 시간 안에 [lastSeen]이 갱신됐으면
  /// 접속중으로 간주한다. [SupabaseManager.lastSeenInterval](하트비트
  /// 주기)보다 충분히 여유 있게 잡아, 하트비트 사이 잠깐의 텀만으로
  /// 오프라인으로 잘못 표시되지 않게 한다.
  static const Duration onlineThreshold = Duration(minutes: 5);

  bool get isOnline {
    final DateTime? seen = lastSeen;
    if (seen == null) {
      return false;
    }
    return DateTime.now().difference(seen) <= onlineThreshold;
  }

  /// 이 앱에서는 닉네임 입력이 필수라(프롤로그 중 [NicknameScreen]을 거치지
  /// 않고는 게임에 진입할 수 없다) 실제 활성 유저의 닉네임이 진짜로
  /// 비어있는 경우는 없다 — 이 플레이스홀더가 보이면 100% `profiles`
  /// 조인이 실패했다는 뜻이다. [GuildManager.refreshMembers]가 이 값을
  /// 그대로 "재조회가 필요한 행" 판정 기준으로 재사용한다.
  static const String unresolvedNicknamePlaceholder = '익명의 모험가';

  factory GuildMember.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? profile = json['profiles'] as Map<String, dynamic>?;
    final String? nickname = profile?['nickname'] as String?;
    final String? lastSeenRaw = profile?['last_seen'] as String?;
    return GuildMember(
      userId: json['user_id'] as String,
      nickname: (nickname == null || nickname.trim().isEmpty)
          ? unresolvedNicknamePlaceholder
          : nickname,
      role: guildRoleFromString(json['role'] as String?),
      contribution: (json['contribution'] as num?)?.toInt() ?? 0,
      lastSeen: lastSeenRaw == null ? null : DateTime.tryParse(lastSeenRaw)?.toLocal(),
    );
  }

  GuildMember copyWith({String? nickname}) => GuildMember(
    userId: userId,
    nickname: nickname ?? this.nickname,
    role: role,
    contribution: contribution,
    lastSeen: lastSeen,
  );
}

/// `guild_messages` + `profiles(nickname)` 임베드 조회(초기 히스토리) 또는
/// Realtime `postgres_changes` INSERT 페이로드(신규 메시지, profiles 임베드
/// 없음) 한 건 — [GuildChatManager]/길드 채팅 탭 리스트 아이템.
class GuildMessage {
  const GuildMessage({
    required this.id,
    required this.guildId,
    required this.userId,
    required this.nickname,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String guildId;
  final String userId;
  final String nickname;
  final String message;
  final DateTime createdAt;

  /// [json]에 `profiles(nickname)` 임베드가 있으면(초기 히스토리 조회) 그
  /// 값을 쓰고, 없으면(Realtime INSERT 페이로드는 임베드를 지원하지 않는다)
  /// [resolveNickname](보통 이미 로드된 [GuildManager.members] 로스터에서
  /// 찾는 콜백)로 대신 채운다 — 두 경로(초기 로드/실시간 수신)가 같은
  /// factory 하나를 공유한다.
  factory GuildMessage.fromJson(
    Map<String, dynamic> json, {
    required String Function(String userId) resolveNickname,
  }) {
    final String userId = json['user_id'] as String;
    final Map<String, dynamic>? profile = json['profiles'] as Map<String, dynamic>?;
    final String? embeddedNickname = profile?['nickname'] as String?;
    final String nickname = (embeddedNickname != null && embeddedNickname.trim().isNotEmpty)
        ? embeddedNickname
        : resolveNickname(userId);
    return GuildMessage(
      id: json['id'].toString(),
      guildId: json['guild_id'].toString(),
      userId: userId,
      nickname: nickname,
      message: json['message'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }
}
