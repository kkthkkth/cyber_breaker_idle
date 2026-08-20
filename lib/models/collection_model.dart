import 'equipment.dart';

/// 도감 카테고리 — 제작/상점 화면과 동일한 3분류를 그대로 재사용한다.
enum CollectionCategory { character, equipment, pet }

extension CollectionCategoryX on CollectionCategory {
  String get displayName {
    switch (this) {
      case CollectionCategory.character:
        return '캐릭터';
      case CollectionCategory.equipment:
        return '장비';
      case CollectionCategory.pet:
        return '펫';
    }
  }
}

/// 도감 완성 보상으로 지급 가능한 영구 스탯 종류. 공격 계열(attackPower/
/// criticalRate) 두 가지에 이어, 플레이어 HP 시스템 도입과 함께 방어
/// 계열 4종(defense/defenseRate/evasionRate/critDefenseRate), 그리고 최대
/// 체력(maxHpPercent, 다른 %계열 최대체력 보너스와 같은 이름 관례 —
/// ArtifactStat.maxHpPercent/EquipmentSetStat.maxHpPercent 참고)도
/// 지원한다 — 전부 GameManager의 "장착 여부와 무관하게 항상 합산되는"
/// collectionBonuses 맵 하나로 처리된다.
enum CollectionStatType {
  attackPower,
  criticalRate,
  defense,
  defenseRate,
  evasionRate,
  critDefenseRate,
  maxHpPercent,
}

extension CollectionStatTypeX on CollectionStatType {
  String get displayName {
    switch (this) {
      case CollectionStatType.attackPower:
        return '공격력';
      case CollectionStatType.criticalRate:
        return '크리티컬 확률';
      case CollectionStatType.defense:
        return '방어력';
      case CollectionStatType.defenseRate:
        return '방어율';
      case CollectionStatType.evasionRate:
        return '회피율';
      case CollectionStatType.critDefenseRate:
        return '크리티컬 방어율';
      case CollectionStatType.maxHpPercent:
        return '최대 체력';
    }
  }
}

/// 도감 완성 시 영구 지급되는 스탯 하나. [value]는 두 타입 모두 비율로
/// 해석된다(예: 0.05 == +5%).
class CollectionRewardStat {
  const CollectionRewardStat({required this.type, required this.value});

  final CollectionStatType type;
  final double value;

  String get displayText => '${type.displayName} +${(value * 100).toStringAsFixed(0)}%';

  Map<String, dynamic> toJson() => {'type': type.name, 'value': value};

  factory CollectionRewardStat.fromJson(Map<String, dynamic> json) {
    return CollectionRewardStat(
      type: CollectionStatType.values.byName(json['type'] as String),
      value: (json['value'] as num).toDouble(),
    );
  }
}

/// 도감 한 칸을 채우기 위해 요구되는 아이템 조건 하나. [subId]가 null이면
/// 등급만 맞으면 되고, 지정돼 있으면 정확히 그 종류(넘버링)만 인정한다.
class RequiredCollectionItem {
  const RequiredCollectionItem({
    required this.type,
    required this.grade,
    this.subId,
    this.requiredLevel = 0,
    this.count = 1,
  });

  final EquipType type;
  final ItemGrade grade;
  final int? subId;
  final int requiredLevel;
  final int count;

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'grade': grade.name,
      'subId': subId,
      'requiredLevel': requiredLevel,
      'count': count,
    };
  }

  factory RequiredCollectionItem.fromJson(Map<String, dynamic> json) {
    return RequiredCollectionItem(
      type: EquipType.values.byName(json['type'] as String),
      grade: ItemGrade.values.byName(json['grade'] as String),
      subId: json['subId'] as int?,
      requiredLevel: json['requiredLevel'] as int? ?? 0,
      count: json['count'] as int? ?? 1,
    );
  }
}

/// 서버 연동을 고려해 정의/진행상태를 분리한 도감 항목. [isCompleted]만
/// 플레이어별 진행 상태이고, 나머지는 서버가 내려주는 정적 정의에 해당한다
/// — CollectionManager가 앱 실행 시 더미로 채워 넣는다.
class CollectionModel {
  CollectionModel({
    required this.id,
    required this.category,
    required this.title,
    required this.requiredItems,
    required this.rewardStat,
    this.isCompleted = false,
  });

  final String id;
  final CollectionCategory category;
  final String title;
  final List<RequiredCollectionItem> requiredItems;
  final CollectionRewardStat rewardStat;
  bool isCompleted;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category': category.name,
      'title': title,
      'requiredItems': requiredItems.map((item) => item.toJson()).toList(),
      'rewardStat': rewardStat.toJson(),
      'isCompleted': isCompleted,
    };
  }

  factory CollectionModel.fromJson(Map<String, dynamic> json) {
    return CollectionModel(
      id: json['id'] as String,
      category: CollectionCategory.values.byName(json['category'] as String),
      title: json['title'] as String,
      requiredItems: (json['requiredItems'] as List<dynamic>)
          .map((entry) => RequiredCollectionItem.fromJson(entry as Map<String, dynamic>))
          .toList(),
      rewardStat: CollectionRewardStat.fromJson(json['rewardStat'] as Map<String, dynamic>),
      isCompleted: json['isCompleted'] as bool? ?? false,
    );
  }
}
