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

  /// [now]가 이 시즌 기간 안에 있는지 — 호출부([BattlePassManager
  /// .loadData])가 반드시 NTP로 받아온 시간을 넘겨야 한다. 기기 시계
  /// (DateTime.now())로 판정하면, 시계를 시즌 시작 전/종료 후로 돌려서
  /// 아직 열리지 않은 시즌의 보상을 미리 받거나 이미 끝난 시즌의
  /// 프리미엄 패스(보석 결제)를 계속 열어 두고 파밍할 수 있었다.
  bool isActiveAt(DateTime now) => !now.isBefore(startDate) && now.isBefore(endDate);

  /// "시즌 종료까지 D-N" 같은 순수 표시용 남은 기간 — 초 단위로 정확할
  /// 필요가 없는 카운트다운 라벨이라 기기 시계를 그대로 써도 안전하다
  /// (이 값 자체가 무언가를 지급/해금하지 않는다 — 실제 활성 여부 판정은
  /// 항상 [isActiveAt]을 거친다).
  Duration get remaining => endDate.difference(DateTime.now());

  factory BattlePassSeason.fromJson(Map<String, dynamic> json) => BattlePassSeason(
    id: json['id'].toString(),
    startDate: DateTime.parse(json['start_date'] as String).toLocal(),
    endDate: DateTime.parse(json['end_date'] as String).toLocal(),
  );
}
