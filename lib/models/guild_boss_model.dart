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

  double get hpRatio => maxHp <= 0 ? 0 : (currentHp / maxHp).clamp(0.0, 1.0);

  factory GuildBoss.fromJson(Map<String, dynamic> json) => GuildBoss(
    guildId: json['guild_id'].toString(),
    level: (json['level'] as num?)?.toInt() ?? 1,
    maxHp: (json['max_hp'] as num?)?.toInt() ?? 0,
    currentHp: (json['current_hp'] as num?)?.toInt() ?? 0,
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

  factory GuildBossAttackResult.fromJson(Map<String, dynamic> json) => GuildBossAttackResult(
    newLevel: (json['new_level'] as num?)?.toInt() ?? 1,
    newMaxHp: (json['new_max_hp'] as num?)?.toInt() ?? 0,
    newCurrentHp: (json['new_current_hp'] as num?)?.toInt() ?? 0,
    defeated: json['defeated'] as bool? ?? false,
    coinReward: (json['coin_reward'] as num?)?.toInt() ?? 0,
  );
}
