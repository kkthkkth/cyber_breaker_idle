enum MissionType { daily, weekly, monthly }

enum ActionType { killMonster, upgrade, clearStage }

enum RewardType { gold, gem }

/// 서버가 내려주는 자유 문자열 보상 타입("gold"/"coin"/"gem" 등)을
/// [RewardType]으로 풀어준다 — "gold"와 "coin"을 같은 뜻의 동의어로
/// 취급한다(서버 데이터가 두 표기를 섞어 쓰기 때문). 알 수 없는 문자열은
/// null. [BattlePassManager]/[MailboxManager] 둘 다 예전엔 이 매핑을
/// 각자 독립된 switch 문으로 중복 구현했다 — 한쪽만 새 재화 타입을
/// 추가하고 다른 쪽을 깜빡하거나, 오타(`'gem'` vs `'gems'`)가 나도
/// 컴파일 타임에 잡히지 않고 그냥 조용히 무시되는 위험이 있었다.
RewardType? rewardTypeFromString(String? raw) => switch (raw) {
  'gold' || 'coin' => RewardType.gold,
  'gem' => RewardType.gem,
  _ => null,
};

class Mission {
  Mission({
    required this.id,
    required this.missionType,
    required this.actionType,
    required this.title,
    required this.description,
    required this.targetValue,
    this.currentValue = 0,
    required this.rewardType,
    required this.rewardAmount,
    this.isCleared = false,
    this.isRewardClaimed = false,
  });

  final String id;
  final MissionType missionType;
  final ActionType actionType;
  final String title;
  final String description;
  final int targetValue;
  int currentValue;
  final RewardType rewardType;
  final int rewardAmount;
  bool isCleared;
  bool isRewardClaimed;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'missionType': missionType.name,
      'actionType': actionType.name,
      'title': title,
      'description': description,
      'targetValue': targetValue,
      'currentValue': currentValue,
      'rewardType': rewardType.name,
      'rewardAmount': rewardAmount,
      'isCleared': isCleared,
      'isRewardClaimed': isRewardClaimed,
    };
  }

  factory Mission.fromJson(Map<String, dynamic> json) {
    return Mission(
      id: json['id'] as String,
      missionType: MissionType.values.byName(json['missionType'] as String),
      actionType: ActionType.values.byName(json['actionType'] as String),
      title: json['title'] as String,
      description: json['description'] as String,
      targetValue: json['targetValue'] as int,
      currentValue: json['currentValue'] as int? ?? 0,
      rewardType: RewardType.values.byName(json['rewardType'] as String),
      rewardAmount: json['rewardAmount'] as int,
      isCleared: json['isCleared'] as bool? ?? false,
      isRewardClaimed: json['isRewardClaimed'] as bool? ?? false,
    );
  }
}
