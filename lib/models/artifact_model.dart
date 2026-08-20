/// [Artifact.statKey]에 쓰이는 유물 전용 패시브 스탯 키 — 매직 스트링을
/// 이 상수들로 통일한다. Supabase `artifacts.stat_key` 컬럼 값과 정확히
/// 같은 문자열이어야 한다([PetSpecialStat]과 같은 관례).
class ArtifactStat {
  const ArtifactStat._();

  static const String attackPercent = 'attackPercent';
  static const String defensePercent = 'defensePercent';
  static const String maxHpPercent = 'maxHpPercent';
  static const String goldGainPercent = 'goldGainPercent';
  static const String dropRatePercent = 'dropRatePercent';

  // 아래 8개는 [GameManager]가 이미 "특수 스탯 10종 뼈대"로 정의해 둔
  // goldGain/itemDropRate(=위 2개, 이미 연결됨)를 제외한 나머지 8종을
  // 그대로 유물 스탯으로도 노출한 것 — comprehensive_stats_dialog.dart의
  // 4개 카테고리("성장 및 유틸리티"/"생존 및 유지력"/"특수 공격 능력")에
  // 이미 표시 자리가 있던 값들이라, 유물이 레벨업할수록 그 화면의 숫자가
  // 바로 오르는 걸 확인할 수 있다(GameManager.expGain/moveSpeed/accuracy/
  // lifeSteal/hpRegen/bossDamageBonus/armorPenetration/skillDamage getter
  // 참고). [hpRegenFlat]만 비율이 아니라 고정 수치(초당 체력)라는 점이
  // 다르다.
  static const String expGainPercent = 'expGainPercent';
  static const String moveSpeedPercent = 'moveSpeedPercent';
  static const String accuracyPercent = 'accuracyPercent';
  static const String lifeStealPercent = 'lifeStealPercent';
  static const String hpRegenFlat = 'hpRegenFlat';
  static const String bossDamageBonusPercent = 'bossDamageBonusPercent';
  static const String armorPenetrationPercent = 'armorPenetrationPercent';
  static const String skillDamagePercent = 'skillDamagePercent';

  static const List<String> values = [
    attackPercent,
    defensePercent,
    maxHpPercent,
    goldGainPercent,
    dropRatePercent,
    expGainPercent,
    moveSpeedPercent,
    accuracyPercent,
    lifeStealPercent,
    hpRegenFlat,
    bossDamageBonusPercent,
    armorPenetrationPercent,
    skillDamagePercent,
  ];

  static String displayName(String key) => switch (key) {
    attackPercent => '공격력 증가',
    defensePercent => '방어력 증가',
    maxHpPercent => '최대 체력 증가',
    goldGainPercent => '골드 획득 증가',
    dropRatePercent => '아이템 드랍률 증가',
    expGainPercent => '경험치 획득 증가',
    moveSpeedPercent => '이동 속도 증가',
    accuracyPercent => '명중률 증가',
    lifeStealPercent => '흡혈',
    hpRegenFlat => '초당 체력 회복',
    bossDamageBonusPercent => '보스 피해 증가',
    armorPenetrationPercent => '방어구 관통',
    skillDamagePercent => '스킬 피해량 증가',
    _ => key,
  };
}

/// `artifacts`(카탈로그) + `user_artifacts`(유저 진행도)를 합친 뷰 모델 —
/// [ArtifactManager]가 이 하나로 표시/레벨업/패시브 합산을 전부 처리한다.
/// [level]이 0이면 "조각만 있고 아직 한 번도 레벨업하지 않은" 상태로,
/// 패시브 효과가 없다(요구사항: "레벨이 오를수록... 영구적으로 상승").
class Artifact {
  const Artifact({
    required this.id,
    required this.name,
    required this.statKey,
    required this.valuePerLevel,
    required this.maxLevel,
    this.level = 0,
    this.fragmentCount = 0,
  });

  final String id;
  final String name;
  final String statKey;

  /// 레벨 1당 [statKey]에 붙는 값(비율, 0.01 == +1%) — 레벨을 곱하면 현재
  /// 패시브 수치가 된다([passiveValue]).
  final double valuePerLevel;
  final int maxLevel;

  final int level;
  final int fragmentCount;

  double get passiveValue => valuePerLevel * level;

  bool get isMaxLevel => level >= maxLevel;

  /// 다음 레벨(level+1)로 올리는 데 필요한 조각 수 — 레벨이 오를수록
  /// 10개씩 더 필요해진다(1→2: 10개, 19→20: 200개) — 보석 가챠로 조각을
  /// 계속 모으게 만드는 장기 소모처.
  static int fragmentCostForLevel(int level) => 10 * (level + 1);

  int get nextLevelFragmentCost => fragmentCostForLevel(level);

  bool get canLevelUp => !isMaxLevel && fragmentCount >= nextLevelFragmentCost;

  Artifact copyWith({int? level, int? fragmentCount}) => Artifact(
    id: id,
    name: name,
    statKey: statKey,
    valuePerLevel: valuePerLevel,
    maxLevel: maxLevel,
    level: level ?? this.level,
    fragmentCount: fragmentCount ?? this.fragmentCount,
  );

  factory Artifact.fromCatalogJson(Map<String, dynamic> json) => Artifact(
    id: json['id'] as String,
    name: json['name'] as String,
    statKey: json['stat_key'] as String,
    valuePerLevel: (json['value_per_level'] as num).toDouble(),
    maxLevel: (json['max_level'] as num?)?.toInt() ?? 20,
  );
}
