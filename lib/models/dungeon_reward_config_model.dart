import 'consumable_item_model.dart';

/// [DungeonRewardConfigEntry.itemType]의 갈래 — 어떤 매니저가 실제 지급을
/// 책임지는지가 이 값 하나로 갈린다([DungeonRewardManager.grantRewardsFor]
/// 참고).
enum DungeonRewardItemType { gold, gem, runeFragment, consumable, equipment }

/// Supabase `dungeon_rewards_config` 테이블의 행 하나 — 던전 클리어 시
/// 독립적으로 굴리는 보상 항목 하나([MonsterDropEntry]의 던전 보상 버전).
///
/// 실제 컬럼 스키마(요구사항에 정확한 컬럼명이 없어 [MonsterDropEntry]와
/// 같은 관례로 이 장르에서 흔히 쓰는 최소 구성으로 가정했다 — 실제
/// 컬럼명이 다르면 이 파일과 [SupabaseManager.fetchDungeonRewardsConfig]만
/// 고치면 된다):
/// ```
/// dungeon_rewards_config
///   id             text/uuid  PK
///   dungeon_type   text       던전을 구분하는 문자열 키
///                             (예: 'rune_labyrinth', 'guild_victory_sanctuary')
///   item_type      text       'gold' | 'gem' | 'rune_fragment' | 'consumable' | 'equipment'
///   item_name      text?      item_type이 'consumable'일 때만 사용 — [MonsterDropEntry
///                             .rawItemName]과 같은 관례(ConsumableType과 못 풀리면
///                             null로 안전 처리).
///   probability    numeric    0.0~1.0, 클리어 1회당 이 항목이 당첨될 확률
///   min_quantity   int        당첨 시 최소 지급 수량
///   max_quantity   int        당첨 시 최대 지급 수량(포함) — min과 같으면 고정 수량
/// ```
class DungeonRewardConfigEntry {
  const DungeonRewardConfigEntry({
    required this.id,
    required this.dungeonType,
    required this.itemType,
    required this.probability,
    required this.minQuantity,
    required this.maxQuantity,
    this.consumableType,
    this.rawItemName,
  });

  final String id;
  final String dungeonType;
  final DungeonRewardItemType itemType;

  /// 0.0~1.0 — [DungeonRewardManager.grantRewardsFor]가 클리어마다 이
  /// 확률로 한 번 굴린다(몬스터 드랍처럼 itemDropRate 보정 없이 그 자체가
  /// 최종 확률이다 — 던전 보상은 스탯의 영향을 받지 않는 고정 확률로
  /// 설계했다).
  final double probability;

  final int minQuantity;
  final int maxQuantity;

  /// [MonsterDropEntry.consumableType]과 같은 관례 — [itemType]이
  /// [DungeonRewardItemType.consumable]일 때만 값이 있다.
  final ConsumableType? consumableType;

  /// `item_name` 컬럼 원본 — [ConsumableType]으로 못 풀어낸 경우에도
  /// 로그/디버깅용으로 원본을 보존한다.
  final String? rawItemName;

  factory DungeonRewardConfigEntry.fromJson(Map<String, dynamic> json) {
    final String rawType = json['item_type'] as String;
    final DungeonRewardItemType itemType = switch (rawType) {
      'gold' => DungeonRewardItemType.gold,
      'gem' => DungeonRewardItemType.gem,
      'rune_fragment' => DungeonRewardItemType.runeFragment,
      'consumable' => DungeonRewardItemType.consumable,
      'equipment' => DungeonRewardItemType.equipment,
      _ => throw ArgumentError('알 수 없는 item_type "$rawType"'),
    };
    final String? rawItemName = json['item_name'] as String?;

    return DungeonRewardConfigEntry(
      id: json['id'].toString(),
      dungeonType: json['dungeon_type'] as String,
      itemType: itemType,
      probability: (json['probability'] as num?)?.toDouble() ?? 0.0,
      minQuantity: (json['min_quantity'] as num?)?.toInt() ?? 0,
      maxQuantity: (json['max_quantity'] as num?)?.toInt() ?? 0,
      consumableType: itemType == DungeonRewardItemType.consumable
          ? _resolveConsumableType(rawItemName)
          : null,
      rawItemName: itemType == DungeonRewardItemType.consumable ? rawItemName : null,
    );
  }

  /// [MonsterDropEntry._resolveConsumableType]과 완전히 같은 매칭 규칙 —
  /// enum 이름 또는 한글 표시명과 대소문자/공백 무시하고 정확히 일치할
  /// 때만 성공한다.
  static ConsumableType? _resolveConsumableType(String? name) {
    if (name == null) {
      return null;
    }
    final String normalized = name.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    for (final ConsumableType type in ConsumableType.values) {
      if (type.name.toLowerCase() == normalized ||
          type.displayName.toLowerCase() == normalized) {
        return type;
      }
    }
    return null;
  }

  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'dungeon_type': dungeonType,
    'item_type': switch (itemType) {
      DungeonRewardItemType.gold => 'gold',
      DungeonRewardItemType.gem => 'gem',
      DungeonRewardItemType.runeFragment => 'rune_fragment',
      DungeonRewardItemType.consumable => 'consumable',
      DungeonRewardItemType.equipment => 'equipment',
    },
    'item_name': consumableType?.name ?? rawItemName,
    'probability': probability,
    'min_quantity': minQuantity,
    'max_quantity': maxQuantity,
  };
}

/// [DungeonRewardManager.grantRewardsFor] 한 번 호출로 실제 지급된 보상
/// 하나 — 클리어 결과 다이얼로그가 "무엇을 얼마나 받았는지" 보여줄 때
/// 쓴다.
class DungeonRewardGrant {
  const DungeonRewardGrant({
    required this.itemType,
    required this.quantity,
    this.consumableType,
  });

  final DungeonRewardItemType itemType;
  final int quantity;
  final ConsumableType? consumableType;

  /// 결과 다이얼로그/토스트에 그대로 쓸 수 있는 한글 요약 — 예:
  /// "룬 조각 x12", "골드 x500".
  String get label {
    final String name = switch (itemType) {
      DungeonRewardItemType.gold => '골드',
      DungeonRewardItemType.gem => '보석',
      DungeonRewardItemType.runeFragment => '룬 조각',
      DungeonRewardItemType.consumable => consumableType?.displayName ?? '소모품',
      DungeonRewardItemType.equipment => '장비',
    };
    return '$name x$quantity';
  }
}
