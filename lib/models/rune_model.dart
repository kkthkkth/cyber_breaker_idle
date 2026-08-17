import 'package:flutter/material.dart';

/// 룬 세 색깔 — 공격형(붉은 룬)/방어형(푸른 룬)/유틸형(초록 룬). 색깔별로
/// 굴릴 수 있는 스탯 풀이 다르다([RuneCatalog]).
enum RuneType { attack, defense, utility }

extension RuneTypeX on RuneType {
  String get displayName => switch (this) {
    RuneType.attack => '공격형',
    RuneType.defense => '방어형',
    RuneType.utility => '유틸형',
  };

  Color get color => switch (this) {
    RuneType.attack => Colors.redAccent,
    RuneType.defense => Colors.blueAccent,
    RuneType.utility => Colors.greenAccent,
  };

  static RuneType fromName(String name) =>
      RuneType.values.firstWhere((type) => type.name == name, orElse: () => RuneType.utility);
}

/// [Rune.statKey]에 쓰이는 룬 전용 패시브 스탯 키 — 매직 스트링을 이
/// 상수들로 통일한다([ArtifactStat]/[PetSpecialStat]과 같은 관례).
class RuneStat {
  const RuneStat._();

  static const String attackPercent = 'attackPercent';
  static const String criticalRatePercent = 'criticalRatePercent';
  static const String criticalDamagePercent = 'criticalDamagePercent';
  static const String defensePercent = 'defensePercent';
  static const String maxHpPercent = 'maxHpPercent';
  static const String evasionRatePercent = 'evasionRatePercent';
  static const String skillCooldownReductionPercent = 'skillCooldownReductionPercent';
  static const String dropRatePercent = 'dropRatePercent';
  static const String goldGainPercent = 'goldGainPercent';

  static String displayName(String key) => switch (key) {
    attackPercent => '공격력 증가',
    criticalRatePercent => '크리티컬 확률 증가',
    criticalDamagePercent => '크리티컬 데미지 증가',
    defensePercent => '방어력 증가',
    maxHpPercent => '최대 체력 증가',
    evasionRatePercent => '회피율 증가',
    skillCooldownReductionPercent => '스킬 쿨타임 감소',
    dropRatePercent => '아이템 드랍률 증가',
    goldGainPercent => '골드 획득량 증가',
    _ => key,
  };
}

class RuneStatDef {
  const RuneStatDef(this.statKey, this.baseValue, this.valuePerLevel);

  final String statKey;
  final double baseValue;
  final double valuePerLevel;
}

/// 룬 색깔별로 실제 나올 수 있는 스탯 풀 — 순수 게임 밸런스 데이터라
/// (skill_tree의 원소별 스킬명처럼) DB 없이 상수로 관리한다. 새 룬을
/// 만들 때([RuneManager.craftRune]) 이 풀에서 무작위로 하나를 고른다.
class RuneCatalog {
  const RuneCatalog._();

  static const Map<RuneType, List<RuneStatDef>> pool = {
    RuneType.attack: [
      RuneStatDef(RuneStat.attackPercent, 0.02, 0.01),
      RuneStatDef(RuneStat.criticalRatePercent, 0.01, 0.005),
      RuneStatDef(RuneStat.criticalDamagePercent, 0.02, 0.01),
    ],
    RuneType.defense: [
      RuneStatDef(RuneStat.defensePercent, 0.02, 0.01),
      RuneStatDef(RuneStat.maxHpPercent, 0.02, 0.01),
      RuneStatDef(RuneStat.evasionRatePercent, 0.01, 0.005),
    ],
    RuneType.utility: [
      RuneStatDef(RuneStat.skillCooldownReductionPercent, 0.01, 0.005),
      RuneStatDef(RuneStat.dropRatePercent, 0.02, 0.01),
      RuneStatDef(RuneStat.goldGainPercent, 0.02, 0.01),
    ],
  };
}

/// 유저가 보유한 룬 하나 — 캐릭터 룬 슬롯([RuneManager.maxSlots], 최대
/// 6개)에 장착하거나 인벤토리에 남겨둘 수 있다. [level]은 요일 던전에서
/// 얻는 "룬 조각"으로 올린다([RuneManager.levelUp]).
class Rune {
  const Rune({
    required this.id,
    required this.type,
    required this.statKey,
    required this.baseValue,
    required this.valuePerLevel,
    this.level = 1,
    this.equippedSlot,
  });

  final String id;
  final RuneType type;
  final String statKey;
  final double baseValue;
  final double valuePerLevel;
  final int level;

  /// null이면 인벤토리에만 있고 미장착 — 0~[RuneManager.maxSlots]-1.
  final int? equippedSlot;

  static const int maxLevel = 10;

  double get value => baseValue + valuePerLevel * (level - 1);

  bool get isMaxLevel => level >= maxLevel;

  bool get isEquipped => equippedSlot != null;

  /// 다음 레벨로 올리는 데 필요한 룬 조각 — 레벨이 오를수록 늘어난다
  /// ([ArtifactManager]의 `fragmentCostForLevel`과 같은 형태의 공식).
  int get nextLevelFragmentCost => 10 * level;

  bool get canLevelUp => !isMaxLevel;

  Rune copyWith({int? level, int? equippedSlot, bool clearSlot = false}) => Rune(
    id: id,
    type: type,
    statKey: statKey,
    baseValue: baseValue,
    valuePerLevel: valuePerLevel,
    level: level ?? this.level,
    equippedSlot: clearSlot ? null : (equippedSlot ?? this.equippedSlot),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'stat_key': statKey,
    'base_value': baseValue,
    'value_per_level': valuePerLevel,
    'level': level,
    'equipped_slot': equippedSlot,
  };

  factory Rune.fromJson(Map<String, dynamic> json) => Rune(
    id: json['id'] as String,
    type: RuneTypeX.fromName(json['type'] as String? ?? 'utility'),
    statKey: json['stat_key'] as String,
    baseValue: (json['base_value'] as num).toDouble(),
    valuePerLevel: (json['value_per_level'] as num).toDouble(),
    level: (json['level'] as num?)?.toInt() ?? 1,
    equippedSlot: (json['equipped_slot'] as num?)?.toInt(),
  );
}
