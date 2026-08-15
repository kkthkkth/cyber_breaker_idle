/// `user_arena` + `profiles(nickname)` 임베드 조회 결과 한 행 —
/// [ArenaScreen]의 도전 상대 카드에 필요한 최소 정보(닉네임/전투력/점수).
class ArenaOpponent {
  const ArenaOpponent({
    required this.userId,
    required this.nickname,
    required this.combatPower,
    required this.score,
  });

  final String userId;
  final String nickname;
  final int combatPower;
  final int score;

  factory ArenaOpponent.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? profile = json['profiles'] as Map<String, dynamic>?;
    final String? nickname = profile?['nickname'] as String?;
    return ArenaOpponent(
      userId: json['user_id'] as String,
      nickname: (nickname == null || nickname.trim().isEmpty) ? '익명의 결투사' : nickname,
      combatPower: (json['combat_power'] as num?)?.toInt() ?? 0,
      score: (json['score'] as num?)?.toInt() ?? ArenaOpponent.defaultScore,
    );
  }

  static const int defaultScore = 1000;
}

/// [ArenaRankingDialog]의 리스트 아이템 — `user_arena` + `profiles(nickname)`
/// 임베드 조회 결과. 순위는 서버 컬럼이 아니라 정렬된 리스트에서의
/// 위치(index+1)로 매긴다([WorldBossRankingEntry]와 같은 관례).
class ArenaRankingEntry {
  const ArenaRankingEntry({required this.userId, required this.nickname, required this.score});

  final String userId;
  final String nickname;
  final int score;

  factory ArenaRankingEntry.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? profile = json['profiles'] as Map<String, dynamic>?;
    final String? nickname = profile?['nickname'] as String?;
    return ArenaRankingEntry(
      userId: json['user_id'] as String,
      nickname: (nickname == null || nickname.trim().isEmpty) ? '익명의 결투사' : nickname,
      score: (json['score'] as num?)?.toInt() ?? ArenaOpponent.defaultScore,
    );
  }
}

/// `arena_ranking_rewards` 테이블의 순위 구간별 차등 보상 한 행 —
/// [WorldBossRankingReward]와 스키마가 동일하지만, 기능적으로 독립된
/// 화면(랭킹 팝업)에서만 쓰여서 별개 클래스로 뒀다(실제 지급 로직은
/// `distribute_arena_rewards` RPC 안에 있고, 여기서는 안내 텍스트용으로만
/// 쓴다).
class ArenaRankingReward {
  const ArenaRankingReward({
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

  String get rewardLabel => switch (rewardType) {
    'gem' => '보석 $rewardAmount개',
    'coin' => '골드 $rewardAmount',
    _ => '$rewardType $rewardAmount',
  };

  String get rankRangeLabel => rankMin == rankMax ? '$rankMin위' : '$rankMin~$rankMax위';

  factory ArenaRankingReward.fromJson(Map<String, dynamic> json) => ArenaRankingReward(
    rankMin: (json['rank_min'] as num).toInt(),
    rankMax: (json['rank_max'] as num).toInt(),
    rewardType: json['reward_type'] as String,
    rewardAmount: (json['reward_amount'] as num).toInt(),
  );
}
