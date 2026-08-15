import 'package:flutter/material.dart';

enum SkillElement { fire, water, wind, lightning, dark }

extension SkillElementX on SkillElement {
  String get displayName {
    switch (this) {
      case SkillElement.fire:
        return '불';
      case SkillElement.water:
        return '물';
      case SkillElement.wind:
        return '바람';
      case SkillElement.lightning:
        return '번개';
      case SkillElement.dark:
        return '어둠';
    }
  }

  IconData get icon {
    switch (this) {
      case SkillElement.fire:
        return Icons.local_fire_department;
      case SkillElement.water:
        return Icons.water_drop;
      case SkillElement.wind:
        return Icons.air;
      case SkillElement.lightning:
        return Icons.bolt;
      case SkillElement.dark:
        return Icons.dark_mode;
    }
  }

  Color get color {
    switch (this) {
      case SkillElement.fire:
        return const Color(0xFFE74C3C);
      case SkillElement.water:
        return const Color(0xFF3498DB);
      case SkillElement.wind:
        return const Color(0xFF2ECC71);
      case SkillElement.lightning:
        return const Color(0xFFF1C40F);
      case SkillElement.dark:
        return const Color(0xFF9B59B6);
    }
  }
}

class SkillNode {
  SkillNode({
    required this.id,
    required this.name,
    required this.element,
    required this.description,
    required this.maxLevel,
    this.currentLevel = 0,
    required this.baseDamage,
    required this.damageGrowth,
    required this.baseCooldown,
    required this.cooldownReduction,
    this.requiredSkillId,
    this.iconPath,
  });

  final String id;
  final String name;
  final SkillElement element;
  final String description;
  final int maxLevel;
  int currentLevel;
  final double baseDamage;
  final double damageGrowth;
  final double baseCooldown;
  final double cooldownReduction;

  /// id of the skill that must be at level >= 1 before this one can be
  /// learned. Null for a tree's root skill.
  final String? requiredSkillId;

  /// Local `assets/...` path or a network `http(s)://...` URL. Null falls
  /// back to [SkillElementX.icon] — CustomSafeImage renders whichever is set.
  final String? iconPath;

  bool get isLearned => currentLevel > 0;
  bool get isMaxLevel => currentLevel >= maxLevel;

  double get currentDamage =>
      currentLevel <= 0 ? 0 : baseDamage + damageGrowth * (currentLevel - 1);

  double get currentCooldown => currentLevel <= 0
      ? baseCooldown
      : (baseCooldown - cooldownReduction * (currentLevel - 1)).clamp(0.5, baseCooldown);

  double get nextDamage {
    final int nextLevel = currentLevel <= 0 ? 1 : currentLevel + 1;
    return baseDamage + damageGrowth * (nextLevel - 1);
  }

  double get nextCooldown {
    final int nextLevel = currentLevel <= 0 ? 1 : currentLevel + 1;
    return (baseCooldown - cooldownReduction * (nextLevel - 1)).clamp(0.5, baseCooldown);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'element': element.name,
      'description': description,
      'maxLevel': maxLevel,
      'currentLevel': currentLevel,
      'baseDamage': baseDamage,
      'damageGrowth': damageGrowth,
      'baseCooldown': baseCooldown,
      'cooldownReduction': cooldownReduction,
      'requiredSkillId': requiredSkillId,
      'iconPath': iconPath,
    };
  }

  factory SkillNode.fromJson(Map<String, dynamic> json) {
    return SkillNode(
      id: json['id'] as String,
      name: json['name'] as String,
      element: SkillElement.values.byName(json['element'] as String),
      description: json['description'] as String,
      maxLevel: json['maxLevel'] as int,
      currentLevel: json['currentLevel'] as int? ?? 0,
      baseDamage: (json['baseDamage'] as num).toDouble(),
      damageGrowth: (json['damageGrowth'] as num).toDouble(),
      baseCooldown: (json['baseCooldown'] as num).toDouble(),
      cooldownReduction: (json['cooldownReduction'] as num).toDouble(),
      requiredSkillId: json['requiredSkillId'] as String?,
      iconPath: json['iconPath'] as String?,
    );
  }
}

/// 펫 전용 패시브 스킬 종류. 전부 "장착된 펫이 1개 이상 있을 때만" 효과가
/// 합산되는 %가산 보너스이며, 실제 적용 조건은 GameManager 쪽 스탯 계산에서
/// EquipmentManager.equippedItems[EquipType.pet]을 직접 확인해 처리한다.
enum PetPassiveType { coinRate, attackPower, bossDamage, criticalRate }

extension PetPassiveTypeX on PetPassiveType {
  String get displayName {
    switch (this) {
      case PetPassiveType.coinRate:
        return '코인 획득 확률 증가';
      case PetPassiveType.attackPower:
        return '총 공격력 증가';
      case PetPassiveType.bossDamage:
        return '보스 몬스터 데미지 증가';
      case PetPassiveType.criticalRate:
        return '크리티컬 확률 증가';
    }
  }

  String get description {
    switch (this) {
      case PetPassiveType.coinRate:
        return '몬스터 처치 시 획득하는 골드량이 증가합니다.';
      case PetPassiveType.attackPower:
        return '캐릭터의 총 공격력이 증가합니다.';
      case PetPassiveType.bossDamage:
        return '보스 몬스터 상대 데미지가 증가합니다.';
      case PetPassiveType.criticalRate:
        return '크리티컬 확률이 증가합니다.';
    }
  }

  IconData get icon {
    switch (this) {
      case PetPassiveType.coinRate:
        return Icons.monetization_on;
      case PetPassiveType.attackPower:
        return Icons.local_fire_department;
      case PetPassiveType.bossDamage:
        return Icons.whatshot;
      case PetPassiveType.criticalRate:
        return Icons.flash_on;
    }
  }

  /// 레벨 1당 증가하는 %가산 보너스 (예: 0.02 == 레벨당 +2%).
  double get perLevelBonus {
    switch (this) {
      case PetPassiveType.coinRate:
        return 0.02;
      case PetPassiveType.attackPower:
        return 0.02;
      case PetPassiveType.bossDamage:
        return 0.03;
      case PetPassiveType.criticalRate:
        return 0.005;
    }
  }
}

/// 서버 연동 대비 펫 패시브 스킬 저장 단위 — [PetPassiveType]별 현재 레벨만
/// 들고 있고, 실제 수치는 [PetPassiveTypeX.perLevelBonus] * currentLevel로 계산한다.
class PetPassiveSkill {
  PetPassiveSkill({
    required this.type,
    required this.maxLevel,
    this.currentLevel = 0,
  });

  final PetPassiveType type;
  final int maxLevel;
  int currentLevel;

  bool get isMaxLevel => currentLevel >= maxLevel;
  double get bonusValue => currentLevel * type.perLevelBonus;

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'maxLevel': maxLevel,
      'currentLevel': currentLevel,
    };
  }

  factory PetPassiveSkill.fromJson(Map<String, dynamic> json) {
    return PetPassiveSkill(
      type: PetPassiveType.values.byName(json['type'] as String),
      maxLevel: json['maxLevel'] as int,
      currentLevel: json['currentLevel'] as int? ?? 0,
    );
  }
}
