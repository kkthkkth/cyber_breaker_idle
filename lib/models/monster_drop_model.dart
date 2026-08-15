import 'consumable_item_model.dart';

/// [MonsterDropEntry.itemType]의 두 갈래 — 'equipment'면 그 자리에서
/// 무작위 장비를 생성해 지급하고, 'consumable'이면 [MonsterDropEntry
/// .consumableType]에 해당하는 소모품을 지급한다.
enum MonsterDropItemType { equipment, consumable }

/// Supabase `monster_drop_table` 테이블의 행 하나 — 몬스터 처치 시 독립적으로
/// 굴리는 드랍 항목 하나. 기존 [DropTable]/[DropEntry](소모품 전용, 하드코딩된
/// 더미 표)를 DB 기반으로 대체·확장한 버전이다.
///
/// 실제 컬럼 스키마(요구사항에 정확한 컬럼명이 없어 이 장르에서 흔히 쓰는
/// 최소 구성으로 가정했다 — 실제 컬럼명이 다르면 이 파일과
/// [SupabaseManager.fetchMonsterDropTable]만 고치면 된다):
/// ```
/// monster_drop_table
///   id            text/uuid  PK
///   item_type     text       'equipment' | 'consumable'
///   item_name     text?      item_type이 'consumable'일 때만 사용 —
///                            ConsumableType.name 값(예: 'dust')
///   base_chance   numeric    0.0~1.0, 플레이어 itemDropRate 반영 전 기본 확률
/// ```
class MonsterDropEntry {
  const MonsterDropEntry({
    required this.id,
    required this.itemType,
    required this.baseChance,
    this.consumableType,
  });

  final String id;
  final MonsterDropItemType itemType;

  /// 0.0~1.0 — 실제 판정 확률은 `base_chance * (1 + itemDropRate)`
  /// ([MonsterDropTableManager._effectiveChance] 참고).
  final double baseChance;

  /// [itemType]이 [MonsterDropItemType.consumable]일 때만 값이 있다.
  final ConsumableType? consumableType;

  factory MonsterDropEntry.fromJson(Map<String, dynamic> json) {
    final String rawType = json['item_type'] as String;
    final MonsterDropItemType itemType = switch (rawType) {
      'equipment' => MonsterDropItemType.equipment,
      'consumable' => MonsterDropItemType.consumable,
      _ => throw ArgumentError('알 수 없는 item_type "$rawType"'),
    };
    final String? itemName = json['item_name'] as String?;
    // consumable인데 item_name이 ConsumableType에 없는 값이면
    // ConsumableType.values.byName이 ArgumentError를 던진다 — 이 행 하나만
    // 건너뛰도록 호출부(MonsterDropTableManager.loadData)가 try/catch로
    // 감싼다([PotionManager.loadData]와 같은 관례).
    final ConsumableType? consumableType = itemType == MonsterDropItemType.consumable
        ? ConsumableType.values.byName(itemName!)
        : null;

    return MonsterDropEntry(
      id: json['id'].toString(),
      itemType: itemType,
      baseChance: (json['base_chance'] as num?)?.toDouble() ?? 0.0,
      consumableType: consumableType,
    );
  }

  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'item_type': itemType == MonsterDropItemType.equipment ? 'equipment' : 'consumable',
    'item_name': consumableType?.name,
    'base_chance': baseChance,
  };
}
