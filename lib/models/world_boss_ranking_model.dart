/// `user_world_boss`(현재 리젠 회차 기준) + `profiles(nickname)` 임베드
/// 조회 결과 한 행 — [WorldBossRankingDialog]의 리스트 아이템. 순위(rank)는
/// 서버 컬럼이 아니라 정렬된 리스트에서의 위치(index+1)로 매긴다.
class WorldBossRankingEntry {
  const WorldBossRankingEntry({
    required this.userId,
    required this.nickname,
    required this.totalDamageDealt,
  });

  final String userId;
  final String nickname;
  final int totalDamageDealt;

  factory WorldBossRankingEntry.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? profile = json['profiles'] as Map<String, dynamic>?;
    final String? nickname = profile?['nickname'] as String?;
    return WorldBossRankingEntry(
      userId: json['user_id'] as String,
      nickname: (nickname == null || nickname.trim().isEmpty) ? '익명의 도전자' : nickname,
      totalDamageDealt: (json['total_damage_dealt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// `world_boss_ranking_rewards` 테이블의 순위 구간별 차등 보상 한 행 —
/// 실제 지급 로직은 아직 없고, 지금은 랭킹 UI에 안내 텍스트를 띄우는
/// 용도로만 쓴다.
class WorldBossRankingReward {
  const WorldBossRankingReward({
    required this.rankMin,
    required this.rankMax,
    required this.rewardType,
    required this.rewardAmount,
  });

  final int rankMin;
  final int rankMax;

  /// 'gem' | 'coin' 등 — 서버 값을 그대로 보관한다.
  final String rewardType;
  final int rewardAmount;

  bool coversRank(int rank) => rank >= rankMin && rank <= rankMax;

  /// "보석 10000개" / "골드 500" 처럼 사람이 읽는 라벨 — 새 재화 타입이
  /// 추가되면 이 switch에 분기 하나만 더하면 된다.
  String get rewardLabel => switch (rewardType) {
    'gem' => '보석 $rewardAmount개',
    'coin' => '골드 $rewardAmount',
    _ => '$rewardType $rewardAmount',
  };

  /// "1위" / "4~10위" 처럼 구간을 사람이 읽는 라벨.
  String get rankRangeLabel => rankMin == rankMax ? '$rankMin위' : '$rankMin~$rankMax위';

  factory WorldBossRankingReward.fromJson(Map<String, dynamic> json) => WorldBossRankingReward(
    rankMin: (json['rank_min'] as num).toInt(),
    rankMax: (json['rank_max'] as num).toInt(),
    rewardType: json['reward_type'] as String,
    rewardAmount: (json['reward_amount'] as num).toInt(),
  );
}
