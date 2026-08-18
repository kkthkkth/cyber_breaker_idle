import 'equipment.dart' show ItemGrade;

/// [Equipment.specialStats]에 쓰이는 펫 전용 특수 스탯 키 — 하드코딩된
/// 매직 스트링을 이 상수들로 통일한다. Supabase `pet_stat_metadata
/// .stat_key` 컬럼 값과 정확히 같은 문자열이어야 한다.
class PetSpecialStat {
  const PetSpecialStat._();

  static const String goldGain = 'goldGain';
  static const String dropRateBoost = 'dropRateBoost';
  static const String bossDamage = 'bossDamage';
  static const String finalAttackBoost = 'finalAttackBoost';
  static const String skillCooldownReduction = 'skillCooldownReduction';
  static const String criticalDamageBoost = 'criticalDamageBoost';

  /// 회피율 증가 — [GameManager.effectiveEvasionRate]에 가산으로 반영된다.
  static const String evasionBoost = 'evasionBoost';

  /// 크리티컬 피해 방어(받는 크리티컬 데미지 배율 감소) 증가 —
  /// [GameManager.effectiveCritDefenseRate]에 가산으로 반영된다.
  static const String critDefenseBoost = 'critDefenseBoost';

  static const List<String> values = [
    goldGain,
    dropRateBoost,
    bossDamage,
    finalAttackBoost,
    skillCooldownReduction,
    criticalDamageBoost,
    evasionBoost,
    critDefenseBoost,
  ];

  static String displayName(String key) => switch (key) {
    goldGain => '골드 획득 증가',
    dropRateBoost => '아이템 드랍률 증가',
    bossDamage => '보스 데미지 증가',
    finalAttackBoost => '최종 공격력 증폭',
    skillCooldownReduction => '스킬 쿨타임 감소',
    criticalDamageBoost => '크리티컬 데미지 증폭',
    evasionBoost => '회피율 증가',
    critDefenseBoost => '크리티컬 피해 방어 증가',
    _ => key,
  };
}

/// `pet_stat_metadata` 테이블 한 행 — (스탯 키, 등급) 조합별로 가챠 시점에
/// 굴릴 값의 범위를 정의한다. [PetStatMetadataManager]가 앱 시작 시 전체를
/// 캐싱하고, [EquipmentManager.generateLootOfType]이 펫을 생성할 때마다 이
/// 범위 안에서 값을 뽑는다 — 수치를 코드에 하드코딩하지 않고 서버에서
/// 실시간으로 조정할 수 있게 하기 위함이다.
class PetStatMetadata {
  const PetStatMetadata({
    required this.statKey,
    required this.grade,
    required this.minValue,
    required this.maxValue,
  });

  final String statKey;
  final ItemGrade grade;
  final double minValue;
  final double maxValue;

  factory PetStatMetadata.fromJson(Map<String, dynamic> json) => PetStatMetadata(
    statKey: json['stat_key'] as String,
    grade: _parseGrade(json['grade'] as String),
    minValue: (json['min_value'] as num).toDouble(),
    maxValue: (json['max_value'] as num).toDouble(),
  );

  static ItemGrade _parseGrade(String name) {
    for (final ItemGrade grade in ItemGrade.values) {
      if (grade.name == name) {
        return grade;
      }
    }
    return ItemGrade.n;
  }
}
