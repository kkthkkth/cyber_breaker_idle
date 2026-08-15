import 'consumable_item_model.dart';

/// `tower_floors.reward_item_type` 값 — 'consumable' 또는 'equipment'.
/// 그 외 값이거나 컬럼이 비어 있으면 [unknown]으로 안전하게 처리한다(파싱
/// 예외를 던지지 않는다).
enum TowerRewardItemKind { consumable, equipment, unknown }

/// Supabase `tower_floors` 테이블의 행 하나 — 무한의 탑 한 층의 몬스터
/// 스탯/보상을 담는다. 예전엔 이 전부(몬스터 HP `60 * 1.25^(floor-1)`,
/// 보석 보상 `50 + floor*10`, 소탕 골드 `floor*30`)가 코드에 하드코딩된
/// 수학 공식이었다 — 이 모델이 그 공식들을 완전히 대체한다.
///
/// 실제 컬럼 스키마(유저가 직접 확인해 준 실제 구성 — 100층까지 등록됨):
/// ```
/// tower_floors
///   floor_number       integer  PK, 1부터 시작
///   monster_hp         numeric
///   monster_atk        numeric
///   reward_gem         integer
///   reward_gold        integer
///   reward_item_type   text?    'consumable' | 'equipment'
///   reward_item_name   text?    ConsumableType.name 값일 수도, "장비 강화
///                                가루" 같은 한글 표시명일 수도 있다.
/// ```
class TowerFloor {
  const TowerFloor({
    required this.floor,
    required this.monsterHp,
    required this.monsterAttack,
    required this.rewardGem,
    required this.rewardGold,
    this.rewardItemKind = TowerRewardItemKind.unknown,
    this.rewardItemName,
    this.resolvedConsumableType,
  });

  final int floor;
  final double monsterHp;

  /// 이 엔진의 던전형 전투(무한의 탑 포함)는 전부 "플레이어→몬스터"
  /// 단방향 공격 구조라 몬스터가 실제로 플레이어 체력을 깎지는 않는다
  /// (골드 던전/장비 던전/펫 산책로/길드 던전 전부 동일한 구조적 한계).
  /// 그래도 요구사항대로 DB 값을 그대로 들고 있다가 입장 배너/전투 화면에
  /// 표시는 한다 — 실제로 플레이어에게 피해를 주게 하려면 메인 스테이지
  /// 수준의 양방향 전투 구조가 추가로 필요하다.
  final double monsterAttack;

  final int rewardGem;
  final int rewardGold;

  final TowerRewardItemKind rewardItemKind;

  /// `reward_item_name` 원본 문자열 그대로 — [ConsumableType.name] 값일
  /// 수도, "장비 강화 가루"처럼 그 어느 enum과도 안 맞는 한글 표시명일
  /// 수도 있다. 팝업/배너는 무엇이 들어있든 이 텍스트를 그대로 보여주면
  /// 되므로 항상 자연스럽게 표시된다(요구사항: "해당 텍스트가 자연스럽게
  /// 표시되도록").
  final String? rewardItemName;

  /// [rewardItemName]이 [ConsumableType.name] 또는
  /// [ConsumableTypeX.displayName]과 대소문자/공백 무시하고 정확히 일치할
  /// 때만 값이 있다 — 있으면 지급 로직이 [ConsumableManager.addItem]으로
  /// 곧장 인벤토리에 넣을 수 있다. null이면(그 어느 쪽과도 안 맞는 자유
  /// 텍스트, 예: "장비 강화 가루") 실제로 인벤토리에 넣을 방법이 없으므로
  /// 지급은 건너뛰고 결과 팝업에 텍스트로만 안내한다 — 짐작으로 엉뚱한
  /// 아이템을 지급하는 것보다 안전하다.
  final ConsumableType? resolvedConsumableType;

  bool get hasReward => rewardItemName != null && rewardItemName!.isNotEmpty;

  factory TowerFloor.fromJson(Map<String, dynamic> json) {
    final String? rawName = json['reward_item_name'] as String?;
    final String? itemName = (rawName == null || rawName.isEmpty) ? null : rawName;

    return TowerFloor(
      floor: (json['floor_number'] as num).toInt(),
      monsterHp: (json['monster_hp'] as num?)?.toDouble() ?? 0,
      monsterAttack: (json['monster_atk'] as num?)?.toDouble() ?? 0,
      rewardGem: (json['reward_gem'] as num?)?.toInt() ?? 0,
      rewardGold: (json['reward_gold'] as num?)?.toInt() ?? 0,
      rewardItemKind: _parseItemKind(json['reward_item_type'] as String?),
      rewardItemName: itemName,
      resolvedConsumableType: _resolveConsumableType(itemName),
    );
  }

  static TowerRewardItemKind _parseItemKind(String? raw) {
    switch (raw) {
      case 'consumable':
        return TowerRewardItemKind.consumable;
      case 'equipment':
        return TowerRewardItemKind.equipment;
      default:
        return TowerRewardItemKind.unknown;
    }
  }

  /// [name]을 [ConsumableType]으로 풀어본다 — enum 이름(`byName`, 예:
  /// 'dust') 또는 화면에 쓰는 한글 표시명([ConsumableTypeX.displayName],
  /// 예: '가루')과 대소문자/공백 무시하고 정확히 일치할 때만 성공한다.
  /// "장비 강화 가루"처럼 그 어느 쪽과도 정확히 일치하지 않는 자유 텍스트는
  /// 그냥 null을 돌려준다 — 예전엔 [ConsumableType.values.byName]을 직접
  /// 불러서 매칭 안 되는 문자열이 오면 ArgumentError를 던졌다(요구사항:
  /// "파싱 에러가 나지 않도록").
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
    'floor_number': floor,
    'monster_hp': monsterHp,
    'monster_atk': monsterAttack,
    'reward_gem': rewardGem,
    'reward_gold': rewardGold,
    'reward_item_type': switch (rewardItemKind) {
      TowerRewardItemKind.consumable => 'consumable',
      TowerRewardItemKind.equipment => 'equipment',
      TowerRewardItemKind.unknown => null,
    },
    'reward_item_name': rewardItemName,
  };
}
