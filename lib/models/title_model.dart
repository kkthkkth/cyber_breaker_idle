/// `title_catalog.buff_type` 값 — [TitleManager.bonusFor]가 이 값을 보고
/// [GameManager]의 어느 곱산 체인에 더할지 결정한다. 요구사항 예시
/// ("공격력, 체력 등")를 감안해 이 장르에서 흔한 퍼센트 버프 4종으로
/// 시작한다 — 새 버프 종류가 필요하면 여기 상수 하나 추가 + [GameManager]
/// 의 해당 체인에 [TitleManager.bonusFor] 한 줄만 추가하면 된다.
class TitleBuffType {
  const TitleBuffType._();

  static const String attackPercent = 'attack_percent';
  static const String maxHpPercent = 'max_hp_percent';
  static const String defensePercent = 'defense_percent';
  static const String goldGainPercent = 'gold_gain_percent';
}

/// `title_catalog.condition_type` 값 — [TitleManager.checkAndGrantTitles]가
/// 이 값에 맞는 "현재 진행도" 소스를 찾아 `condition_goal`과 비교한다.
/// 전부 이미 다른 화면(업적 등)에서 추적 중인 값을 그대로 재사용한다 —
/// 칭호 전용 카운터를 새로 만들지 않는다.
class TitleConditionType {
  const TitleConditionType._();

  /// 누적 몬스터 처치 — [AchievementManager.totalMonsterKills].
  static const String monsterKillCount = 'monster_kill_count';

  /// 최고 도달 챕터 — [GameManager.highestReachedChapter].
  static const String highestChapter = 'highest_chapter';

  /// 누적 가챠 횟수 — [AchievementManager.totalGachaPulls].
  static const String gachaCount = 'gacha_count';

  /// 누적 환생 횟수 — [PrestigeManager.prestigeCount].
  static const String prestigeCount = 'prestige_count';

  /// [type]의 한글 조건 설명에 쓰이는 단위 — [PlayerTitle.conditionLabel]이 쓴다.
  static String unitLabel(String type) => switch (type) {
    monsterKillCount => '몬스터 처치',
    highestChapter => '챕터 도달',
    gachaCount => '가챠 횟수',
    prestigeCount => '환생 횟수',
    _ => type,
  };
}

/// `title_catalog` 테이블 한 행 — 로그인 여부와 무관한 공개 카탈로그.
/// 실제 보유/장착 여부는 [TitleManager]가 `user_titles`/
/// `profiles.equipped_title`로 따로 관리한다.
class PlayerTitle {
  const PlayerTitle({
    required this.id,
    required this.name,
    required this.buffType,
    required this.buffValue,
    required this.conditionType,
    required this.conditionGoal,
    this.webpPath,
  });

  final String id;
  final String name;
  final String buffType;
  final double buffValue;
  final String conditionType;
  final double conditionGoal;

  /// null이거나 로드에 실패하면 [TitleBadge]가 이름 텍스트 폴백으로
  /// 대체한다.
  final String? webpPath;

  /// 미획득 칭호 타일에 보여주는 달성 조건 문구 — 예: "몬스터 처치 1,000".
  String get conditionLabel =>
      '${TitleConditionType.unitLabel(conditionType)} ${conditionGoal.toStringAsFixed(0)}';

  /// 장착 중일 때 보여주는 버프 요약 — 예: "공격력 +15%".
  String get buffLabel {
    final String statName = switch (buffType) {
      TitleBuffType.attackPercent => '공격력',
      TitleBuffType.maxHpPercent => '최대 체력',
      TitleBuffType.defensePercent => '방어력',
      TitleBuffType.goldGainPercent => '골드 획득량',
      _ => buffType,
    };
    return '$statName +${(buffValue * 100).toStringAsFixed(0)}%';
  }

  factory PlayerTitle.fromJson(Map<String, dynamic> json) => PlayerTitle(
    id: json['id'].toString(),
    name: json['name'] as String? ?? '이름 없는 칭호',
    buffType: json['buff_type'] as String? ?? '',
    buffValue: (json['buff_value'] as num?)?.toDouble() ?? 0.0,
    conditionType: json['condition_type'] as String? ?? '',
    conditionGoal: (json['condition_goal'] as num?)?.toDouble() ?? 0.0,
    webpPath: json['webp_path'] as String?,
  );
}
