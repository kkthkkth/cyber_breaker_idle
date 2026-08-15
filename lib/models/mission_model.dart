enum MissionType { daily, weekly, monthly }

enum ActionType { killMonster, upgrade, clearStage }

enum RewardType { gold, gem }

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
