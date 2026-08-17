/// `battle_pass_rewards` 테이블 한 행 — 특정 레벨의 무료/프리미엄 보상
/// 한 쌍. [BattlePassScreen]의 트랙 한 타일이 이 한 행에 대응한다(요구
/// 사항의 "[레벨 번호] | [무료 보상] | [프리미엄 보상] 3열"이 그대로
/// 한 테이블 행으로 매핑되도록, 무료/프리미엄을 별도 테이블로 쪼개지
/// 않고 한 행에 함께 담는 스키마로 가정했다).
class BattlePassRewardTier {
  const BattlePassRewardTier({
    required this.level,
    required this.freeRewardType,
    required this.freeRewardAmount,
    required this.premiumRewardType,
    required this.premiumRewardAmount,
  });

  final int level;

  /// 'gold' | 'gem' 등 — 서버 값을 그대로 보관한다.
  final String freeRewardType;
  final int freeRewardAmount;
  final String premiumRewardType;
  final int premiumRewardAmount;

  String get freeRewardLabel => _rewardLabel(freeRewardType, freeRewardAmount);
  String get premiumRewardLabel => _rewardLabel(premiumRewardType, premiumRewardAmount);

  static String _rewardLabel(String type, int amount) => switch (type) {
    'gem' => '보석 $amount개',
    'gold' || 'coin' => '골드 $amount',
    _ => '$type $amount',
  };

  factory BattlePassRewardTier.fromJson(Map<String, dynamic> json) => BattlePassRewardTier(
    level: (json['level'] as num).toInt(),
    freeRewardType: json['free_reward_type'] as String? ?? 'gold',
    freeRewardAmount: (json['free_reward_amount'] as num?)?.toInt() ?? 0,
    premiumRewardType: json['premium_reward_type'] as String? ?? 'gem',
    premiumRewardAmount: (json['premium_reward_amount'] as num?)?.toInt() ?? 0,
  );
}

/// `battle_pass_seasons` 테이블 한 행 — 시즌 패스는 이 기간 동안만
/// 유효하다([isActive]). [BattlePassManager]가 앱 시작 시 활성 시즌을
/// 찾아 진행도([BattlePassManager.bpExp] 등)를 그 시즌에 묶는다 — 로컬에
/// 남아있던 진행도가 지난 시즌 것이면 새 시즌으로 넘어가는 순간
/// 자동으로 초기화된다(실제 시즌제 배틀패스의 표준 동작).
class BattlePassSeason {
  const BattlePassSeason({
    required this.id,
    required this.startDate,
    required this.endDate,
  });

  final String id;
  final DateTime startDate;
  final DateTime endDate;

  bool get isActive {
    final DateTime now = DateTime.now();
    return !now.isBefore(startDate) && now.isBefore(endDate);
  }

  Duration get remaining => endDate.difference(DateTime.now());

  factory BattlePassSeason.fromJson(Map<String, dynamic> json) => BattlePassSeason(
    id: json['id'].toString(),
    startDate: DateTime.parse(json['start_date'] as String).toLocal(),
    endDate: DateTime.parse(json['end_date'] as String).toLocal(),
  );
}
