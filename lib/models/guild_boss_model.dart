/// `guild_bosses` 테이블 한 행 — 길드마다 정확히 하나씩 존재하는 "현재
/// 도전 중인 레이드 보스"의 공유 상태(길드원 전원이 같은 값을 본다).
/// 실제 컬럼 스키마는 요구사항에 명시되지 않아, 이 장르에서 흔히 쓰는
/// 최소 구성으로 가정했다: `guild_id`(uuid, PK/guilds.id 참조), `level`
/// (int), `max_hp`(bigint), `current_hp`(bigint).
class GuildBoss {
  const GuildBoss({
    required this.guildId,
    required this.level,
    required this.maxHp,
    required this.currentHp,
  });

  final String guildId;
  final int level;
  final int maxHp;
  final int currentHp;

  /// 서버 응답이 손상됐거나(레거시 null 컬럼 등 — `guild_bosses.current_hp`
  /// null 제약 위반 버그가 실제로 있었다, `supabase/guild_boss_null_hp_fix.sql`
  /// 참고) `guild_bosses` 행 자체가 아직 없을 때 안전하게 쓰는 기본 최대
  /// 체력 — [GuildRaidManager.refreshBoss]의 "행 없음" 폴백과
  /// [fromJson]의 null 방어가 공유하는 단일 소스.
  static const int defaultMaxHp = 100000;

  double get hpRatio => maxHp <= 0 ? 0 : (currentHp / maxHp).clamp(0.0, 1.0);

  /// [json]의 `max_hp`/`current_hp`가 null이어도(서버 쪽 버그로 실제
  /// 관측된 사례 — 위 [defaultMaxHp] 문서 참고) 0(=죽어 있는 것처럼 보이는
  /// 깨진 상태)이 아니라 정상적인 1레벨 보스로 안전하게 대체한다.
  factory GuildBoss.fromJson(Map<String, dynamic> json) => GuildBoss(
    guildId: json['guild_id'].toString(),
    level: (json['level'] as num?)?.toInt() ?? 1,
    maxHp: (json['max_hp'] as num?)?.toInt() ?? defaultMaxHp,
    currentHp: (json['current_hp'] as num?)?.toInt() ?? defaultMaxHp,
  );
}

/// `guild_boss_attack` RPC의 반환 행 — [SupabaseManager.attackGuildBoss]
/// 참고. [coinReward]는 이번 호출로 "나"에게 실제로 지급된 길드 주화만
/// 담는다(보스가 이번 공격으로 죽지 않았으면 항상 0).
class GuildBossAttackResult {
  const GuildBossAttackResult({
    required this.newLevel,
    required this.newMaxHp,
    required this.newCurrentHp,
    required this.defeated,
    required this.coinReward,
  });

  final int newLevel;
  final int newMaxHp;
  final int newCurrentHp;
  final bool defeated;
  final int coinReward;

  /// [GuildBoss.fromJson]과 같은 이유로 `new_max_hp`/`new_current_hp`
  /// null도 0이 아니라 [GuildBoss.defaultMaxHp]로 안전하게 대체한다.
  factory GuildBossAttackResult.fromJson(Map<String, dynamic> json) => GuildBossAttackResult(
    newLevel: (json['new_level'] as num?)?.toInt() ?? 1,
    newMaxHp: (json['new_max_hp'] as num?)?.toInt() ?? GuildBoss.defaultMaxHp,
    newCurrentHp: (json['new_current_hp'] as num?)?.toInt() ?? GuildBoss.defaultMaxHp,
    defeated: json['defeated'] as bool? ?? false,
    coinReward: (json['coin_reward'] as num?)?.toInt() ?? 0,
  );
}

/// `guild_boss_participants` 테이블 한 행 — `guild_boss_attack` RPC가
/// 공격마다 직접 누적 기록하는, 길드원별 "이 보스에게 지금까지 넣은 총
/// 데미지"([SupabaseManager.attackGuildBoss] 문서 참고). 이 클라이언트
/// 코드는 이 테이블에 쓰지 않고 오직 랭킹 표시용으로 읽기만 한다
/// ([SupabaseManager.fetchGuildBossLeaderboard]).
///
/// 실제 컬럼 스키마는 요구사항에 명시되지 않아, 이미 있는 `guild_bosses`
/// 문서 및 자매 랭킹 테이블([SupabaseManager.fetchWorldBossRanking]의
/// `user_world_boss.total_damage_dealt`)과 같은 이름 관례로 가정했다:
/// `guild_id`(uuid), `user_id`(uuid), `total_damage_dealt`(bigint).
class GuildRaidContribution {
  const GuildRaidContribution({
    required this.userId,
    required this.nickname,
    required this.totalDamageDealt,
  });

  final String userId;
  final String nickname;
  final int totalDamageDealt;

  /// `profiles(nickname)` 임베드(user_id → profiles.id 외래키 전제,
  /// [fetchWorldBossRanking]과 같은 관례)가 없거나 null이면 "익명"으로
  /// 안전하게 대체한다.
  factory GuildRaidContribution.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? profile = json['profiles'] as Map<String, dynamic>?;
    return GuildRaidContribution(
      userId: json['user_id'].toString(),
      nickname: profile?['nickname'] as String? ?? '익명',
      totalDamageDealt: (json['total_damage_dealt'] as num?)?.toInt() ?? 0,
    );
  }
}
