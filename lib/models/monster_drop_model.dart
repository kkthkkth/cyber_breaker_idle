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
///                            ConsumableType.name 값(예: 'dust')일 수도,
///                            "장비 강화 가루"/"하급 체력 물약"처럼 그
///                            어느 enum과도 안 맞는 한글 자유 텍스트일 수도
///                            있다(후자는 [MonsterDropEntry.consumableType]
///                            이 null로 안전 처리되고 [rawItemName]에 원본만
///                            남는다).
///   base_chance   numeric    0.0~1.0, 플레이어 itemDropRate 반영 전 기본 확률
/// ```
class MonsterDropEntry {
  const MonsterDropEntry({
    required this.id,
    required this.itemType,
    required this.baseChance,
    this.consumableType,
    this.rawItemName,
  });

  final String id;
  final MonsterDropItemType itemType;

  /// 0.0~1.0 — 실제 판정 확률은 `base_chance * (1 + itemDropRate)`
  /// ([MonsterDropTableManager._effectiveChance] 참고).
  final double baseChance;

  /// [rawItemName]이 [ConsumableType.name] 또는
  /// [ConsumableTypeX.displayName]과 대소문자/공백 무시하고 정확히 일치할
  /// 때만 값이 있다 — [MonsterDropTableManager.rollDropsForKill]/
  /// [MonsterDropTableManager.expectedDropsForKills]가 실제로 지급할 수
  /// 있는 항목인지 이 필드로 판단한다([TowerFloor.resolvedConsumableType]과
  /// 같은 관례).
  final ConsumableType? consumableType;

  /// `item_name` 컬럼 원본 문자열 그대로 — [ConsumableType]으로 못 풀어낸
  /// 경우("장비 강화 가루", "하급 체력 물약"처럼 그 어느 enum과도 정확히
  /// 안 맞는 한글 텍스트, 또는 아직 게임에 대응 enum 자체가 없는 아이템)
  /// 에도 로그/디버깅용으로 원본 이름을 잃지 않도록 보존한다. [itemType]이
  /// [MonsterDropItemType.equipment]면 null.
  final String? rawItemName;

  factory MonsterDropEntry.fromJson(Map<String, dynamic> json) {
    final String rawType = json['item_type'] as String;
    final MonsterDropItemType itemType = switch (rawType) {
      'equipment' => MonsterDropItemType.equipment,
      'consumable' => MonsterDropItemType.consumable,
      _ => throw ArgumentError('알 수 없는 item_type "$rawType"'),
    };
    final String? rawItemName = json['item_name'] as String?;

    return MonsterDropEntry(
      id: json['id'].toString(),
      itemType: itemType,
      baseChance: (json['base_chance'] as num?)?.toDouble() ?? 0.0,
      consumableType: itemType == MonsterDropItemType.consumable
          ? _resolveConsumableType(rawItemName)
          : null,
      rawItemName: itemType == MonsterDropItemType.consumable ? rawItemName : null,
    );
  }

  /// [name]을 [ConsumableType]으로 풀어본다 — enum 이름(`byName`, 예:
  /// 'dust') 또는 화면에 쓰는 한글 표시명([ConsumableTypeX.displayName],
  /// 예: '가루')과 대소문자/공백 무시하고 정확히 일치할 때만 성공한다.
  /// "장비 강화 가루"/"하급 체력 물약"처럼 그 어느 쪽과도 정확히 일치하지
  /// 않는 자유 텍스트는 null(안전하게 "지급 불가" 취급, [rawItemName]에는
  /// 원본이 그대로 남는다) — 예전엔 [ConsumableType.values.byName]을 직접
  /// 불러서 매칭 안 되는 문자열이 오면 `Invalid argument (name)`
  /// [ArgumentError]를 던졌다([TowerFloor._resolveConsumableType]과 같은
  /// 관례).
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
    'item_type': itemType == MonsterDropItemType.equipment ? 'equipment' : 'consumable',
    'item_name': consumableType?.name ?? rawItemName,
    'base_chance': baseChance,
  };
}
