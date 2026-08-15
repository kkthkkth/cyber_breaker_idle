/// `quests.action_type` 컬럼에 들어가는 값들 — [QuestManager.updateProgress]
/// 호출부(GameManager/PotionManager/WorldBossManager/ArenaManager)와 서버
/// `quests` 테이블 시드 데이터가 반드시 이 문자열로 합의해야 한다. 새
/// 액션 타입을 추가하고 싶으면 여기 상수 하나 추가 + 해당 매니저에서
/// [QuestManager.updateProgress] 호출 한 줄만 추가하면 된다.
class QuestActionType {
  const QuestActionType._();

  static const String monsterKill = 'monster_kill';
  static const String potionUse = 'potion_use';
  static const String worldBossChallenge = 'world_boss_challenge';
  static const String arenaBattle = 'arena_battle';
}

/// `quests` 테이블 한 행 — 오늘의 일일 퀘스트 카탈로그(공개 데이터, 로그인
/// 여부와 무관). 실제 진행도/수령 여부는 [QuestProgress]가 따로 담는다.
class Quest {
  const Quest({
    required this.id,
    required this.actionType,
    required this.title,
    required this.targetCount,
    required this.rewardBp,
  });

  final String id;
  final String actionType;
  final String title;
  final int targetCount;
  final int rewardBp;

  factory Quest.fromJson(Map<String, dynamic> json) => Quest(
    id: json['id'].toString(),
    actionType: json['action_type'] as String,
    title: json['title'] as String? ?? '일일 퀘스트',
    targetCount: (json['target_count'] as num?)?.toInt() ?? 1,
    rewardBp: (json['reward_bp'] as num?)?.toInt() ?? 0,
  );
}

/// `user_quests` 테이블 한 행 — 특정 퀘스트에 대한 내 오늘의 진행도.
class QuestProgress {
  const QuestProgress({required this.currentCount, required this.isClaimed});

  final int currentCount;
  final bool isClaimed;

  static const QuestProgress zero = QuestProgress(currentCount: 0, isClaimed: false);

  QuestProgress copyWith({int? currentCount, bool? isClaimed}) => QuestProgress(
    currentCount: currentCount ?? this.currentCount,
    isClaimed: isClaimed ?? this.isClaimed,
  );

  factory QuestProgress.fromJson(Map<String, dynamic> json) => QuestProgress(
    currentCount: (json['current_count'] as num?)?.toInt() ?? 0,
    isClaimed: json['is_claimed'] as bool? ?? false,
  );
}

/// [QuestScreen]이 실제로 그리는 단위 — 카탈로그([Quest])와 내 진행도
/// ([QuestProgress])를 합쳐 둔 뷰 모델. [QuestManager.questsWithProgress]가
/// 만들어 준다.
class QuestDisplayItem {
  const QuestDisplayItem({required this.quest, required this.progress});

  final Quest quest;
  final QuestProgress progress;

  bool get isComplete => progress.currentCount >= quest.targetCount;
  bool get isClaimable => isComplete && !progress.isClaimed;
  double get ratio =>
      quest.targetCount <= 0 ? 0 : (progress.currentCount / quest.targetCount).clamp(0.0, 1.0);
}
