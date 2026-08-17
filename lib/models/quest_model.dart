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

  /// 요일 던전을 성공적으로 클리어(파도 1개 이상 처치)할 때마다 —
  /// [WeekdayDungeonManager.grantWaveReward]가 성공 판정 직후 호출한다.
  static const String weekdayDungeonClear = 'weekday_dungeon_clear';

  /// 룬을 제작하거나 합성할 때마다 — [RuneManager.craftRune]/[RuneManager
  /// .synthesize] 둘 다 성공 시 이 값으로 진행도를 올린다(제작/합성을
  /// 구분하지 않고 "룬 관련 행동" 하나로 묶는다).
  static const String runeCraftOrSynthesize = 'rune_craft_or_synthesize';
}

/// `quests.period` 값 — 같은 카탈로그/진행도 테이블 안에서 일일/주간
/// 퀘스트를 함께 관리한다([QuestManager]가 리셋 주기만 다르게 적용한다).
/// 컬럼이 아직 없는(마이그레이션 전) 기존 행은 전부 daily로 취급한다 —
/// 기존 일일 퀘스트 동작을 그대로 보존한다.
enum QuestPeriod { daily, weekly }

QuestPeriod _questPeriodFromJson(String? raw) => switch (raw) {
  'weekly' => QuestPeriod.weekly,
  _ => QuestPeriod.daily,
};

/// `quests` 테이블 한 행 — 오늘(또는 이번 주)의 퀘스트 카탈로그(공개
/// 데이터, 로그인 여부와 무관). 실제 진행도/수령 여부는 [QuestProgress]가
/// 따로 담는다.
class Quest {
  const Quest({
    required this.id,
    required this.actionType,
    required this.title,
    required this.targetCount,
    required this.rewardBp,
    this.period = QuestPeriod.daily,
  });

  final String id;
  final String actionType;
  final String title;
  final int targetCount;
  final int rewardBp;
  final QuestPeriod period;

  factory Quest.fromJson(Map<String, dynamic> json) => Quest(
    id: json['id'].toString(),
    actionType: json['action_type'] as String,
    title: json['title'] as String? ?? '일일 퀘스트',
    targetCount: (json['target_count'] as num?)?.toInt() ?? 1,
    rewardBp: (json['reward_bp'] as num?)?.toInt() ?? 0,
    period: _questPeriodFromJson(json['period'] as String?),
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
