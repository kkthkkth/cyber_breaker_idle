/// 초보자 가이드 미션 전용 액션 타입 — [QuestActionType](일일/주간/월간
/// DB 카탈로그 전용)과는 별개의 문자열 집합이다. [GuideMissionManager]는
/// 서버 카탈로그 없이 로컬 하드코딩 시퀀스([GuideMissionManager.sequence])
/// 만 다루므로 서버와 문자열을 합의할 필요가 없지만, 두 시스템의 어휘를
/// 분리해 두면 한쪽 액션 타입이 늘어나거나 의미가 바뀌어도 다른 쪽에
/// 영향이 없다.
class GuideMissionActionType {
  const GuideMissionActionType._();

  /// 몬스터 처치 — [GameManager._onMonsterDefeated]가 호출한다.
  static const String monsterKill = 'kill_monster';

  /// 공격력 골드 강화 — [GameManager.upgradeAttack]이 성공(골드 지불)할
  /// 때마다 호출한다.
  static const String attackUpgrade = 'upgrade_attack';

  /// 방어력 골드 강화 — [GameManager.upgradeDefense]가 성공할 때마다
  /// 호출한다.
  static const String defenseUpgrade = 'upgrade_defense';

  /// 절대 스테이지([GameManager.absoluteStage]) 도달 — "누적 카운트"가
  /// 아니라 "지금까지 도달한 절대값"을 그대로 보고하는 이벤트라
  /// [GuideMissionManager.updateProgress]가 아니라
  /// [GuideMissionManager.reportAbsoluteValue]로만 반영된다.
  static const String stageReached = 'stage_reached';

  /// 장비 가챠 뽑기 — [EquipmentManager.drawMultipleGacha]가 호출될 때마다
  /// 뽑은 개수만큼 호출한다.
  static const String equipmentGachaPull = 'equipment_gacha_pull';
}

/// [GuideMission.rewardType] 값 — [QuestRewardType]과 같은 어휘지만
/// (지금은) 골드/보석만 쓴다. 별도 클래스로 둔 이유는 [GuideMissionActionType]
/// 과 같다 — 가이드 미션 전용 어휘를 DB 기반 퀘스트 시스템과 분리해 둔다.
class GuideMissionRewardType {
  const GuideMissionRewardType._();

  static const String gold = 'gold';
  static const String gem = 'gem';
}

/// [GuideMissionBanner]의 "바로가기" 버튼이 눌렸을 때 이동할 하단 탭 —
/// [GuideMission.shortcut]이 null이면(대부분의 액션 타입) 이미 홈 탭
/// 안에서(배틀 뷰/강화 패널) 진행되는 미션이라 이동할 곳이 없다는 뜻이고,
/// 배너는 버튼 자체를 그리지 않는다.
enum GuideMissionShortcut {
  /// 샵 탭(main.dart `_navTabs` 순서의 index 0) — 장비 가챠 뽑기 미션.
  shop(0);

  const GuideMissionShortcut(this.tabIndex);

  final int tabIndex;
}

/// 초보자 가이드 미션 시퀀스의 항목 하나 — [GuideMissionManager.sequence]
/// (1번부터 순서대로 클리어하는 선형 리스트, 서버 없이 로컬 하드코딩)의
/// 원소. 무작위 배정을 쓰는 DB 기반 [Quest]와 달리 [order] 순서 그대로,
/// 항상 하나씩만 진행된다.
class GuideMission {
  const GuideMission({
    required this.id,
    required this.order,
    required this.actionType,
    required this.description,
    required this.targetCount,
    required this.rewardType,
    required this.rewardAmount,
    this.shortcut,
  });

  final String id;
  final int order;
  final String actionType;
  final String description;
  final int targetCount;
  final String rewardType;
  final int rewardAmount;

  /// [GuideMissionBanner]의 "바로가기" 버튼이 이동할 탭 — null이면 버튼을
  /// 아예 그리지 않는다.
  final GuideMissionShortcut? shortcut;

  /// 배너/토스트에 그대로 쓸 수 있는 한글 보상 요약 — 예: "보석 x100".
  String get rewardLabel {
    final String name = switch (rewardType) {
      GuideMissionRewardType.gold => '골드',
      GuideMissionRewardType.gem => '보석',
      _ => rewardType,
    };
    return '$name x$rewardAmount';
  }
}
