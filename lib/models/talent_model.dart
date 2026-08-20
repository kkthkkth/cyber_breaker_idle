/// [TalentNode.buffType]에 쓰이는 특성 전용 영구 스탯 키 — 이 프로젝트의
/// 다른 %계열 스탯 소스들([ArtifactStat]/[CollectionStatType]/[RuneStat]
/// 등)과 같은 이름 관례를 그대로 따른다. `user_talents.node_id`를 통해
/// [TalentNode]와 연결될 뿐, 이 자체는 Supabase 컬럼이 아니라 노드 정의의
/// `buff_type` 문자열 값이다.
class TalentBuffType {
  const TalentBuffType._();

  static const String attackPercent = 'attackPercent';
  static const String goldGainPercent = 'goldGainPercent';
  static const String criticalRatePercent = 'criticalRatePercent';
  static const String defensePercent = 'defensePercent';

  static const List<String> values = [
    attackPercent,
    goldGainPercent,
    criticalRatePercent,
    defensePercent,
  ];

  static String displayName(String key) => switch (key) {
    attackPercent => '공격력',
    goldGainPercent => '골드 획득량',
    criticalRatePercent => '크리티컬 확률',
    defensePercent => '방어력',
    _ => key,
  };
}

/// 특성(별자리) 트리 노드 하나 — 정의(카탈로그)와 진행도([currentLevel])를
/// 하나로 합쳐 들고 있다([TalentManager]가 앱 시작 시 채워 넣는다,
/// [CollectionModel]/[ArtifactManager]의 [Artifact]와 같은 관례).
///
/// 선행 조건: [prerequisiteNodeIds]에 담긴 노드들이 전부 [requiredPrerequisiteLevel]
/// 이상이어야 이 노드에 첫 포인트를 투자할 수 있다(요구사항 예시: "[기초
/// 근력]을 5레벨 찍어야 [재물 탐구]와 [치명적 일격]이 해금"). 빈 리스트면
/// 선행 조건 없이 언제든 투자할 수 있는 루트 노드다.
class TalentNode {
  const TalentNode({
    required this.id,
    required this.name,
    required this.description,
    required this.maxLevel,
    required this.pointCostPerLevel,
    required this.buffType,
    required this.buffValuePerLevel,
    this.prerequisiteNodeIds = const [],
    this.requiredPrerequisiteLevel = 1,
    this.currentLevel = 0,
  });

  final String id;
  final String name;
  final String description;
  final int maxLevel;

  /// 레벨 1당 드는 특성 포인트 — 지금은 레벨과 무관하게 항상 같은 값이다
  /// (요구사항: "레벨업 요구 포인트" 단수 — 레벨마다 달라지는 곡선이
  /// 필요해지면 이 필드를 함수로 바꾸면 된다).
  final int pointCostPerLevel;

  final List<String> prerequisiteNodeIds;

  /// [prerequisiteNodeIds]에 담긴 노드들이 전부 이 값 이상이어야 한다.
  final int requiredPrerequisiteLevel;

  final String buffType;

  /// 레벨 1당 [buffType]에 붙는 값(비율, 0.01 == +1%) — 레벨을 곱하면 현재
  /// 패시브 수치가 된다([passiveValue]).
  final double buffValuePerLevel;

  final int currentLevel;

  double get passiveValue => buffValuePerLevel * currentLevel;

  bool get isMaxLevel => currentLevel >= maxLevel;

  bool get isRoot => prerequisiteNodeIds.isEmpty;

  TalentNode copyWith({int? currentLevel}) => TalentNode(
    id: id,
    name: name,
    description: description,
    maxLevel: maxLevel,
    pointCostPerLevel: pointCostPerLevel,
    prerequisiteNodeIds: prerequisiteNodeIds,
    requiredPrerequisiteLevel: requiredPrerequisiteLevel,
    buffType: buffType,
    buffValuePerLevel: buffValuePerLevel,
    currentLevel: currentLevel ?? this.currentLevel,
  );

  factory TalentNode.fromCatalogJson(Map<String, dynamic> json) => TalentNode(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    maxLevel: (json['max_level'] as num?)?.toInt() ?? 5,
    pointCostPerLevel: (json['point_cost_per_level'] as num?)?.toInt() ?? 1,
    prerequisiteNodeIds:
        (json['prerequisite_node_ids'] as List<dynamic>?)?.cast<String>() ?? const [],
    requiredPrerequisiteLevel: (json['required_prerequisite_level'] as num?)?.toInt() ?? 1,
    buffType: json['buff_type'] as String,
    buffValuePerLevel: (json['buff_value_per_level'] as num?)?.toDouble() ?? 0.0,
  );
}
