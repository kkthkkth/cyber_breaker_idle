import 'dart:math';

import 'equipment.dart' show ItemGrade, ItemGradeX;

/// 펫 대분류 — 전투 펫은 딜/보스전 위주, 유틸 펫은 재화/드랍 위주로 메인
/// 스탯이 갈린다. 경험치 시스템은 없으므로(요구사항) 레벨/경험치 필드는
/// 두지 않는다 — 스탯은 오직 [PetFactory.generate] 시점에 한 번만 굴려진다.
enum PetCategory { battle, utility }

extension PetCategoryX on PetCategory {
  String get displayName => this == PetCategory.battle ? '전투 펫' : '유틸 펫';
}

/// 펫의 메인/서브 스탯 풀. 전투 펫 메인 스탯은 [bossDamage]/[finalAttackBoost]
/// 중 하나, 유틸 펫 메인 스탯은 [goldGain]/[dropRateBoost] 중 하나로 고정되고
/// (생성 시점에 무작위 선택), 서브 옵션은 이 6종 전체 풀에서 메인 스탯을
/// 제외하고 등급별 개수만큼 중복 없이 뽑힌다. 전부 비율(0.05 == +5%)로
/// 해석된다.
enum PetStatType {
  dropRateBoost,
  goldGain,
  bossDamage,
  finalAttackBoost,
  skillCooldownReduction,
  criticalDamageBoost,
}

extension PetStatTypeX on PetStatType {
  String get displayName {
    switch (this) {
      case PetStatType.dropRateBoost:
        return '아이템 드랍률 증가';
      case PetStatType.goldGain:
        return '골드 획득 증가';
      case PetStatType.bossDamage:
        return '보스 데미지 증가';
      case PetStatType.finalAttackBoost:
        return '최종 공격력 증폭';
      case PetStatType.skillCooldownReduction:
        return '스킬 쿨타임 감소';
      case PetStatType.criticalDamageBoost:
        return '크리티컬 데미지 증폭';
    }
  }
}

/// 펫 한 마리가 가질 수 있는 스탯 한 줄 — 메인 스탯과 서브 옵션 모두 이
/// 클래스로 표현된다. 전부 비율값이라 [displayText]는 항상 "+5.0%" 형태.
class PetOption {
  const PetOption({required this.type, required this.value});

  final PetStatType type;
  final double value;

  String get displayText => '${type.displayName} +${(value * 100).toStringAsFixed(1)}%';

  Map<String, dynamic> toJson() => {'type': type.name, 'value': value};

  factory PetOption.fromJson(Map<String, dynamic> json) {
    return PetOption(
      type: PetStatType.values.byName(json['type'] as String),
      value: (json['value'] as num).toDouble(),
    );
  }
}

class Pet {
  Pet({
    required this.id,
    required this.name,
    required this.category,
    required this.grade,
    required this.mainStat,
    this.subStats = const [],
    this.subId = 1,
    this.isEquipped = false,
  });

  final String id;
  final String name;
  final PetCategory category;
  final ItemGrade grade;

  /// 부위별이 아니라 [category]별로 고정되는 메인 스탯 — [PetFactory.generate]
  /// 가 전투/유틸 후보 2종 중 하나를 무작위로 뽑아 채운다.
  final PetOption mainStat;

  /// 등급이 높을수록 개수가 늘어나는 추가 랜덤 옵션(0~5개).
  final List<PetOption> subStats;

  /// 같은 등급 내 종류(넘버링) — 장비의 subId와 동일한 관례.
  final int subId;

  bool isEquipped;

  /// UI 렌더링용 — 메인 스탯이 항상 최상단에 오고 서브 옵션이 이어진다.
  List<PetOption> get displayOptions => [mainStat, ...subStats];

  String get gradeBadgeLabel => '${grade.displayName}$subId';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category.name,
      'grade': grade.name,
      'mainStat': mainStat.toJson(),
      'subStats': subStats.map((option) => option.toJson()).toList(),
      'subId': subId,
      'isEquipped': isEquipped,
    };
  }

  factory Pet.fromJson(Map<String, dynamic> json) {
    return Pet(
      id: json['id'] as String,
      name: json['name'] as String,
      category: PetCategory.values.byName(json['category'] as String),
      grade: ItemGrade.values.byName(json['grade'] as String),
      mainStat: PetOption.fromJson(json['mainStat'] as Map<String, dynamic>),
      subStats: (json['subStats'] as List<dynamic>?)
              ?.map((entry) => PetOption.fromJson(entry as Map<String, dynamic>))
              .toList() ??
          const [],
      subId: json['subId'] as int? ?? 1,
      isEquipped: json['isEquipped'] as bool? ?? false,
    );
  }
}

/// 카테고리별 고정 메인 스탯 + 등급별 랜덤 서브 옵션을 굴려 [Pet]을 만드는
/// 생성 팩토리. lib/models/equipment.dart의 EquipmentFactory와 동일한
/// 구간-분리 공식을 재사용해 등급이 오를수록 수치가 무조건 높게 나온다.
class PetFactory {
  PetFactory._();

  static final Random _random = Random();

  static const Map<PetCategory, List<PetStatType>> _mainStatCandidates = {
    PetCategory.battle: [PetStatType.bossDamage, PetStatType.finalAttackBoost],
    PetCategory.utility: [PetStatType.goldGain, PetStatType.dropRateBoost],
  };

  /// 등급별 추가 서브 옵션 개수.
  static const Map<ItemGrade, int> _subStatCountByGrade = {
    ItemGrade.n: 0,
    ItemGrade.r: 1,
    ItemGrade.sr: 2,
    ItemGrade.ssr: 2,
    ItemGrade.sssr: 3,
    ItemGrade.ur: 4,
    ItemGrade.lr: 5,
  };

  /// N등급(gradeIndex 0)에서 나올 수 있는 서브 옵션의 최저 수치.
  static const Map<PetStatType, double> _subStatBaseFloor = {
    PetStatType.dropRateBoost: 0.01,
    PetStatType.goldGain: 0.02,
    PetStatType.bossDamage: 0.02,
    PetStatType.finalAttackBoost: 0.02,
    PetStatType.skillCooldownReduction: 0.01,
    PetStatType.criticalDamageBoost: 0.02,
  };

  /// 메인 스탯은 같은 타입의 서브 옵션보다 항상 굵게 나오도록 baseFloor에
  /// 곱해주는 배수.
  static const double _mainStatFloorMultiplier = 1.5;

  /// 등급 1단계당 구간(min~max)이 통째로 위로 올라가는 배수 — 다음 등급의
  /// 최저치가 이전 등급의 최대치보다 항상 크려면 _gradeGrowth >
  /// 1 + _gradeWidthRatio여야 한다(1.5 > 1.25 ✓).
  static const double _gradeGrowth = 1.5;
  static const double _gradeWidthRatio = 0.25;

  static Pet generate({
    required PetCategory category,
    required ItemGrade grade,
    required String id,
    required String name,
    int subId = 1,
  }) {
    final List<PetStatType> candidates = _mainStatCandidates[category]!;
    final PetStatType mainStatType = candidates[_random.nextInt(candidates.length)];

    final PetOption mainStat = PetOption(
      type: mainStatType,
      value: _rollValue(_subStatBaseFloor[mainStatType]! * _mainStatFloorMultiplier, grade),
    );

    final int subStatCount = _subStatCountByGrade[grade] ?? 0;
    final List<PetOption> subStats = _rollUniqueSubStats(
      excluding: mainStatType,
      count: subStatCount,
      grade: grade,
    );

    return Pet(
      id: id,
      name: name,
      category: category,
      grade: grade,
      mainStat: mainStat,
      subStats: subStats,
      subId: subId,
    );
  }

  /// [excluding](메인 스탯 타입)을 뺀 나머지 풀에서 [count]개를 중복 없이
  /// 뽑는다. Set으로 뽑힌 타입을 추적하면서 while로 채우되, 풀 자체가
  /// [count]보다 작으면 assert로 즉시 드러나게 한다 — LR(5개) 펫은 풀이
  /// 정확히 5개(6종 - 메인 스탯 1개)라 여유가 없으므로 특히 중요하다.
  static List<PetOption> _rollUniqueSubStats({
    required PetStatType excluding,
    required int count,
    required ItemGrade grade,
  }) {
    final List<PetStatType> pool =
        PetStatType.values.where((statType) => statType != excluding).toList();
    assert(
      count <= pool.length,
      '서브 옵션 풀(${pool.length}개)보다 많은 $count개를 요청했습니다.',
    );

    final Set<PetStatType> chosen = {};
    while (chosen.length < count && chosen.length < pool.length) {
      chosen.add(pool[_random.nextInt(pool.length)]);
    }

    return chosen
        .map(
          (statType) => PetOption(
            type: statType,
            value: _rollValue(_subStatBaseFloor[statType]!, grade),
          ),
        )
        .toList();
  }

  static double _rollValue(double baseFloor, ItemGrade grade) {
    final double floor = baseFloor * pow(_gradeGrowth, grade.index);
    final double max = floor * (1 + _gradeWidthRatio);
    final double value = floor + _random.nextDouble() * (max - floor);
    return double.parse(value.toStringAsFixed(4));
  }
}
