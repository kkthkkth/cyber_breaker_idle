/// `quest_catalog.action_type` 컬럼에 들어가는 값들 — [QuestManager
/// .updateProgress] 호출부(GameManager/PotionManager/WorldBossManager/
/// ArenaManager/RuneManager/WeekdayDungeonManager)와 서버 `quest_catalog`
/// 시드 데이터가 반드시 이 문자열로 합의해야 한다. 새 액션 타입을 추가하고
/// 싶으면 여기 상수 하나 추가 + 해당 매니저에서 [QuestManager
/// .updateProgress] 호출 한 줄만 추가하면 된다.
class QuestActionType {
  const QuestActionType._();

  /// 몬스터 처치 — [GameManager._onMonsterDefeated]. 실제 `quest_catalog`
  /// 시드 값과 합의된 이름("kill_monster" — 동사+목적어 순서, 아래
  /// [clearLabyrinth]와 같은 표기 관례).
  static const String monsterKill = 'kill_monster';

  static const String potionUse = 'potion_use';
  static const String worldBossChallenge = 'world_boss_challenge';
  static const String arenaBattle = 'arena_battle';

  /// 요일 던전을 성공적으로 클리어(파도 1개 이상 처치)할 때마다 —
  /// [WeekdayDungeonManager.grantWaveReward]가 성공 판정 직후 호출한다.
  /// 목요일 슬롯("룬의 미궁")뿐 아니라 다른 요일 던전 클리어도 전부 이
  /// 액션으로 잡힌다 — `quest_catalog`가 요일별로 구분된 별도 액션 타입을
  /// 요구하지 않는 한(현재는 요구사항에 없음) 요일 던전 전체를 하나로
  /// 묶는다. 실제 `quest_catalog` 시드 값과 합의된 이름("clear_labyrinth").
  static const String weekdayDungeonClear = 'clear_labyrinth';

  /// 룬을 제작하거나 합성할 때마다 — [RuneManager.craftRune]/[RuneManager
  /// .synthesize] 둘 다 성공 시 이 값으로 진행도를 올린다(제작/합성을
  /// 구분하지 않고 "룬 관련 행동" 하나로 묶는다).
  static const String runeCraftOrSynthesize = 'rune_craft_or_synthesize';
}

/// `quest_catalog.reward_type` 값 — [QuestManager.claimQuest]가 이 값에
/// 맞춰 실제 재화를 지급한다. 알 수 없는 값은 조용히 무시하되 로그를
/// 남긴다(다른 매니저의 `rewardTypeFromString` 관례와 달리 이 프로젝트에
/// 이미 있는 [RewardType](gold/gem만)에 rune_fragment/bp까지 얹으면
/// 매핑을 이 파일이 아닌 mission_model.dart가 떠안게 되므로, 퀘스트
/// 전용 재화 문자열은 여기서 로컬로 처리한다).
class QuestRewardType {
  const QuestRewardType._();

  static const String gold = 'gold';
  static const String gem = 'gem';

  /// 배틀패스 BP 경험치 — [BattlePassManager.addBpExp]로 지급(기존
  /// 시스템의 유일한 보상 종류였다).
  static const String bp = 'bp';

  /// 룬 조각 — [RuneManager.addFragments]로 지급.
  static const String runeFragment = 'rune_fragment';
}

/// `quest_catalog.period_type` 값 — 같은 카탈로그 안에서 일일/주간/월간
/// 퀘스트 풀을 함께 관리한다([QuestManager]가 리셋 주기와 무작위 배정
/// 개수만 다르게 적용한다). 컬럼이 없거나 알 수 없는 값인 기존 행은
/// daily로 취급한다.
enum QuestPeriod { daily, weekly, monthly }

QuestPeriod _questPeriodFromJson(String? raw) => switch (raw) {
  'weekly' => QuestPeriod.weekly,
  'monthly' => QuestPeriod.monthly,
  _ => QuestPeriod.daily,
};

/// `quest_catalog` 테이블 한 행 — 일일/주간/월간 퀘스트 "풀(Pool)"에 속한
/// 후보 하나(공개 데이터, 로그인 여부와 무관). [QuestManager]가 주기가
/// 리셋될 때마다 이 풀에서 무작위로 몇 개를 뽑아 유저에게 배정하고, 실제
/// 배정 여부/진행도/수령 여부는 [QuestProgress]가 따로 담는다 — 카탈로그
/// 자체는 "뽑힐 수 있는 후보 목록"일 뿐 유저별 상태를 갖지 않는다.
class Quest {
  const Quest({
    required this.id,
    required this.actionType,
    required this.description,
    required this.targetCount,
    required this.rewardType,
    required this.rewardAmount,
    this.period = QuestPeriod.daily,
  });

  final String id;
  final String actionType;
  final String description;
  final int targetCount;
  final String rewardType;
  final int rewardAmount;
  final QuestPeriod period;

  factory Quest.fromJson(Map<String, dynamic> json) => Quest(
    id: json['id'].toString(),
    actionType: json['action_type'] as String,
    description: json['description'] as String? ?? '퀘스트',
    targetCount: (json['target_count'] as num?)?.toInt() ?? 1,
    rewardType: json['reward_type'] as String? ?? QuestRewardType.gold,
    rewardAmount: (json['reward_amount'] as num?)?.toInt() ?? 0,
    period: _questPeriodFromJson(json['period_type'] as String?),
  );

  /// 퀘스트 타일/토스트에 그대로 쓸 수 있는 한글 보상 요약 — 예: "골드
  /// x500", "룬 조각 x12".
  String get rewardLabel {
    final String name = switch (rewardType) {
      QuestRewardType.gold => '골드',
      QuestRewardType.gem => '보석',
      QuestRewardType.bp => 'BP',
      QuestRewardType.runeFragment => '룬 조각',
      _ => rewardType,
    };
    return '$name x$rewardAmount';
  }
}

/// `user_quests` 테이블 한 행 — 지금 나에게 배정된 특정 퀘스트에 대한
/// 진행도. 이 맵에 키(quest_id)가 존재한다는 것 자체가 "배정됨"을 뜻한다
/// ([QuestManager] 참고) — 별도의 "배정 목록" 컬럼/필드를 두지 않는다.
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
