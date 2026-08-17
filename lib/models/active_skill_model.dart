import 'package:flutter/material.dart';

/// `skill_metadata.skill_type` 컬럼 값 — 광역기(즉발 큰 데미지)와 버프기
/// (일정 시간 공격력/공격속도 증폭) 두 종류만 지원한다. 알 수 없는 값이
/// 들어와도 앱이 죽지 않도록 [ActiveSkillType.fromDb]가 안전하게 광역기로
/// 폴백한다([TowerFloorModel]류의 "유연한 매칭" 관례).
enum ActiveSkillType {
  aoe,
  buff;

  static ActiveSkillType fromDb(String? value) => switch (value) {
    'active_buff' => ActiveSkillType.buff,
    _ => ActiveSkillType.aoe,
  };
}

/// `skill_metadata`(카탈로그) + `user_skills`(유저 진행도)를 합친 뷰
/// 모델 — [SkillManager]가 이 하나로 표시/레벨업/장착/발동을 전부
/// 처리한다.
class ActiveSkill {
  const ActiveSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.basePower,
    required this.powerPerLevel,
    required this.baseCooldown,
    required this.maxLevel,
    required this.levelUpGoldCost,
    this.buffDurationSeconds = 0,
    this.buffAttackPowerBonus = 0,
    this.buffAttackSpeedBonus = 0,
    this.level = 1,
    this.isEquipped = false,
    this.lastUsedAt,
  });

  final String id;
  final String name;
  final String description;
  final ActiveSkillType type;

  /// 광역기 데미지 배율의 기본치 — 최종 데미지는
  /// `(basePower + powerPerLevel * level) * 공격력`([aoeMultiplier] 참고).
  final double basePower;
  final double powerPerLevel;

  /// 기본 쿨타임(초) — 실제 쿨타임은 펫의 스킬 쿨타임 감소 옵션이 적용된
  /// [SkillManager.effectiveActiveSkillCooldown]을 거친다.
  final double baseCooldown;
  final int maxLevel;

  /// 레벨 1→2로 올리는 데 드는 골드 — 레벨이 오를수록
  /// `levelUpGoldCost * (level + 1)`로 늘어난다([nextLevelGoldCost]).
  final double levelUpGoldCost;

  /// 버프기 전용 — 광역기(`type == aoe`)에서는 전부 0으로 무시된다.
  final double buffDurationSeconds;
  final double buffAttackPowerBonus;
  final double buffAttackSpeedBonus;

  /// 스킬은 별도 "습득" 단계 없이 카탈로그에 있으면 즉시 레벨 1로
  /// 사용 가능하다 — 레벨업만 골드로 강화하는 구조.
  final int level;
  final bool isEquipped;

  /// 마지막으로 발동한 시각 — 쿨타임 계산의 진짜 소스([SpeedManager]의
  /// `_endTime` 관례처럼, 남은 시간은 이 값과 [DateTime.now]의 차이로
  /// 매번 다시 계산되는 파생값이다). null이면 아직 한 번도 안 씀.
  final DateTime? lastUsedAt;

  IconData get icon => type == ActiveSkillType.buff ? Icons.bolt : Icons.whatshot;

  /// 광역기 데미지 배율 — 공격력에 곱해 최종 데미지가 된다.
  double get aoeMultiplier => basePower + powerPerLevel * level;

  bool get isMaxLevel => level >= maxLevel;

  int get nextLevelGoldCost => (levelUpGoldCost * (level + 1)).round();

  bool get canLevelUp => !isMaxLevel;

  ActiveSkill copyWith({int? level, bool? isEquipped, DateTime? lastUsedAt}) => ActiveSkill(
    id: id,
    name: name,
    description: description,
    type: type,
    basePower: basePower,
    powerPerLevel: powerPerLevel,
    baseCooldown: baseCooldown,
    maxLevel: maxLevel,
    levelUpGoldCost: levelUpGoldCost,
    buffDurationSeconds: buffDurationSeconds,
    buffAttackPowerBonus: buffAttackPowerBonus,
    buffAttackSpeedBonus: buffAttackSpeedBonus,
    level: level ?? this.level,
    isEquipped: isEquipped ?? this.isEquipped,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
  );

  factory ActiveSkill.fromCatalogJson(Map<String, dynamic> json) => ActiveSkill(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    type: ActiveSkillType.fromDb(json['skill_type'] as String?),
    basePower: (json['base_power'] as num?)?.toDouble() ?? 0,
    powerPerLevel: (json['power_per_level'] as num?)?.toDouble() ?? 0,
    baseCooldown: (json['base_cooldown'] as num?)?.toDouble() ?? 10,
    maxLevel: (json['max_level'] as num?)?.toInt() ?? 20,
    levelUpGoldCost: (json['level_up_gold_cost'] as num?)?.toDouble() ?? 1000,
    buffDurationSeconds: (json['buff_duration_seconds'] as num?)?.toDouble() ?? 0,
    buffAttackPowerBonus: (json['buff_attack_power_bonus'] as num?)?.toDouble() ?? 0,
    buffAttackSpeedBonus: (json['buff_attack_speed_bonus'] as num?)?.toDouble() ?? 0,
  );
}
