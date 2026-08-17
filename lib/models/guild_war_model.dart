/// `guild_war_config` 테이블(싱글턴 1행)의 LiveOps 설정값 — 세금 비율,
/// 최소 보장 보상, 휘장 버프 수치까지 전부 앱 재배포 없이 서버에서 바꿀
/// 수 있게 한다.
class GuildWarConfig {
  const GuildWarConfig({
    required this.taxRate,
    required this.minRewardCoin,
    required this.minRewardGem,
    required this.badgeBuffGoldRate,
    required this.badgeBuffCritDmg,
  });

  final double taxRate;
  final int minRewardCoin;
  final int minRewardGem;
  final double badgeBuffGoldRate;
  final double badgeBuffCritDmg;

  /// 서버 조회 실패(오프라인 등) 시 쓰는 안전한 기본값 — 요구사항에 적힌
  /// 기본 수치 그대로.
  static const GuildWarConfig fallback = GuildWarConfig(
    taxRate: 0.001,
    minRewardCoin: 10000,
    minRewardGem: 100,
    badgeBuffGoldRate: 0.2,
    badgeBuffCritDmg: 0.1,
  );

  factory GuildWarConfig.fromJson(Map<String, dynamic> json) => GuildWarConfig(
    taxRate: (json['tax_rate'] as num?)?.toDouble() ?? fallback.taxRate,
    minRewardCoin: (json['min_reward_coin'] as num?)?.toInt() ?? fallback.minRewardCoin,
    minRewardGem: (json['min_reward_gem'] as num?)?.toInt() ?? fallback.minRewardGem,
    badgeBuffGoldRate: (json['badge_buff_gold_rate'] as num?)?.toDouble() ?? fallback.badgeBuffGoldRate,
    badgeBuffCritDmg: (json['badge_buff_crit_dmg'] as num?)?.toDouble() ?? fallback.badgeBuffCritDmg,
  );
}

/// `global_tax_pool` 테이블(싱글턴 1행) — 서버 전체 유저가 가챠/요일 던전에
/// 소모한 재화의 [GuildWarConfig.taxRate]만큼 실시간으로 누적된다. 길드
/// 전쟁 신청 화면 중앙에 화려하게 보여주는 값이 바로 이것.
class GlobalTaxPool {
  const GlobalTaxPool({required this.coinPool, required this.gemPool});

  final int coinPool;
  final int gemPool;

  static const GlobalTaxPool zero = GlobalTaxPool(coinPool: 0, gemPool: 0);

  factory GlobalTaxPool.fromJson(Map<String, dynamic> json) => GlobalTaxPool(
    coinPool: (json['coin_pool'] as num?)?.toInt() ?? 0,
    gemPool: (json['gem_pool'] as num?)?.toInt() ?? 0,
  );
}

/// `guild_wars.status` 값.
enum GuildWarStatus { applied, matched, destroyed, settled }

GuildWarStatus _statusFromString(String? value) => switch (value) {
  'matched' => GuildWarStatus.matched,
  'destroyed' => GuildWarStatus.destroyed,
  'settled' => GuildWarStatus.settled,
  _ => GuildWarStatus.applied,
};

/// `guild_wars.result` 값 — 정산 전(아직 [GuildWarStatus.settled]가 아님)에는
/// 항상 null.
enum GuildWarResult { win, lose, draw }

GuildWarResult? _resultFromString(String? value) => switch (value) {
  'win' => GuildWarResult.win,
  'lose' => GuildWarResult.lose,
  'draw' => GuildWarResult.draw,
  _ => null,
};

/// `guild_wars` 테이블 한 행 — 내 길드의 이번 주 전쟁 상태(신청/매칭/거점
/// 체력/결과)를 통째로 담는다.
class GuildWar {
  const GuildWar({
    required this.id,
    required this.weekKey,
    required this.guildId,
    this.opponentGuildId,
    required this.baseMaxHp,
    required this.baseCurrentHp,
    required this.baseDefense,
    required this.status,
    this.result,
  });

  final String id;
  final String weekKey;
  final String guildId;
  final String? opponentGuildId;
  final int baseMaxHp;
  final int baseCurrentHp;
  final int baseDefense;
  final GuildWarStatus status;
  final GuildWarResult? result;

  double get baseHpRatio => baseMaxHp <= 0 ? 0 : (baseCurrentHp / baseMaxHp).clamp(0.0, 1.0);

  bool get isMatched => status == GuildWarStatus.matched || status == GuildWarStatus.destroyed;

  factory GuildWar.fromJson(Map<String, dynamic> json) => GuildWar(
    id: json['id'].toString(),
    weekKey: json['week_key'] as String,
    guildId: json['guild_id'].toString(),
    opponentGuildId: json['opponent_guild_id']?.toString(),
    baseMaxHp: (json['base_max_hp'] as num?)?.toInt() ?? 0,
    baseCurrentHp: (json['base_current_hp'] as num?)?.toInt() ?? 0,
    baseDefense: (json['base_defense'] as num?)?.toInt() ?? 0,
    status: _statusFromString(json['status'] as String?),
    result: _resultFromString(json['result'] as String?),
  );
}

/// `guild_war_attack` RPC의 반환 행 — [SupabaseManager.attackGuildWarBase]
/// 참고.
class GuildWarAttackResult {
  const GuildWarAttackResult({required this.newCurrentHp, required this.baseDestroyed});

  final int newCurrentHp;
  final bool baseDestroyed;

  factory GuildWarAttackResult.fromJson(Map<String, dynamic> json) => GuildWarAttackResult(
    newCurrentHp: (json['new_current_hp'] as num?)?.toInt() ?? 0,
    baseDestroyed: json['base_destroyed'] as bool? ?? false,
  );
}
