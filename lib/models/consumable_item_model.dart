import 'package:flutter/material.dart';

enum ConsumableType {
  speed2x,
  speed3x,
  skillReset,
  premiumGachaTicket,
  crossElementBook,
  dust,
  goldDungeonTicket,
  equipDungeonTicket,
  towerSweepTicket,
  normalBox,
  advancedBox,
  heroBox,
  legendaryBox,
  pawprint,

  // 호감도 전용 선물 아이템 — 등급(꽃 < 초콜릿 < 보석) 순으로 호감도
  // 상승폭이 커진다. AffectionManager.affectionGainForGift 참고.
  giftFlower,
  giftChocolate,
  giftJewelry,

  // 서약(Oath) 전용 1회성 소모품 — 장비 슬롯에 끼는 장비가 아니라, 호감도
  // Lv.MAX에서 [AffectionManager.tryOath]가 1개 소모하고 해당 캐릭터의
  // AffectionData.isOathed를 영구 true로 바꾼다.
  oathRing,

  // 요일 던전(수요일) 전용 보상 재화 — 지금은 순수 수집/보관용이며, 장비
  // 레벨업 비용(Equipment.levelUpCost)은 여전히 골드만 쓴다. 이 재화를
  // 실제 강화 소모 자원으로 편입하는 건 별도 밸런스 결정이 필요해 이번
  // 범위엔 넣지 않았다.
  enhanceStone,
}

extension ConsumableTypeX on ConsumableType {
  String get displayName {
    switch (this) {
      case ConsumableType.speed2x:
        return '2배속 이용권';
      case ConsumableType.speed3x:
        return '3배속 이용권';
      case ConsumableType.skillReset:
        return '스킬 초기화권';
      case ConsumableType.premiumGachaTicket:
        return '고급 장비 뽑기권';
      case ConsumableType.crossElementBook:
        return '다른 속성 스킬권';
      case ConsumableType.dust:
        return '가루';
      case ConsumableType.goldDungeonTicket:
        return '골드 던전 충전권';
      case ConsumableType.equipDungeonTicket:
        return '장비 던전 충전권';
      case ConsumableType.towerSweepTicket:
        return '무한의 탑 소탕 충전권';
      case ConsumableType.normalBox:
        return '일반 상자';
      case ConsumableType.advancedBox:
        return '고급 상자';
      case ConsumableType.heroBox:
        return '영웅 상자';
      case ConsumableType.legendaryBox:
        return '전설 상자';
      case ConsumableType.pawprint:
        return '발바닥';
      case ConsumableType.giftFlower:
        return '꽃다발';
      case ConsumableType.giftChocolate:
        return '초콜릿';
      case ConsumableType.giftJewelry:
        return '보석';
      case ConsumableType.oathRing:
        return '서약의 반지';
      case ConsumableType.enhanceStone:
        return '강화석';
    }
  }

  IconData get icon {
    switch (this) {
      case ConsumableType.speed2x:
      case ConsumableType.speed3x:
        return Icons.fast_forward;
      case ConsumableType.skillReset:
        return Icons.refresh;
      case ConsumableType.premiumGachaTicket:
        return Icons.confirmation_number;
      case ConsumableType.crossElementBook:
        return Icons.menu_book;
      case ConsumableType.dust:
        return Icons.grain;
      case ConsumableType.goldDungeonTicket:
        return Icons.monetization_on;
      case ConsumableType.equipDungeonTicket:
        return Icons.shield_moon;
      case ConsumableType.towerSweepTicket:
        return Icons.stairs;
      case ConsumableType.normalBox:
      case ConsumableType.advancedBox:
      case ConsumableType.heroBox:
      case ConsumableType.legendaryBox:
        return Icons.card_giftcard;
      case ConsumableType.pawprint:
        return Icons.pets;
      case ConsumableType.giftFlower:
        return Icons.local_florist;
      case ConsumableType.giftChocolate:
        return Icons.cake;
      case ConsumableType.giftJewelry:
        return Icons.diamond;
      case ConsumableType.oathRing:
        return Icons.diamond_outlined;
      case ConsumableType.enhanceStone:
        return Icons.construction;
    }
  }

  /// Border/accent color for chest-tier UI (calendar box row, box-open
  /// dialog). Only meaningful for the 4 box types; other types are unused.
  Color get boxColor {
    switch (this) {
      case ConsumableType.normalBox:
        return const Color(0xFF9E9E9E);
      case ConsumableType.advancedBox:
        return const Color(0xFF2ECC71);
      case ConsumableType.heroBox:
        return const Color(0xFF3498DB);
      case ConsumableType.legendaryBox:
        return const Color(0xFFF1C40F);
      default:
        return const Color(0xFF6C4FCE);
    }
  }
}

/// Server-ready consumable stack. Dummy inventories are hand-built for now;
/// once consumables move to a DB, decode a list of these directly from the
/// response — nothing downstream needs to change.
class ConsumableItem {
  ConsumableItem({
    required this.id,
    required this.type,
    required this.name,
    required this.count,
    this.iconPath,
  });

  final String id;
  final ConsumableType type;
  final String name;
  int count;

  /// Local `assets/...` path or a network `http(s)://...` URL. Null falls
  /// back to [ConsumableTypeX.icon] (a built-in Material icon) — set this
  /// once real art/CDN icons exist and CustomSafeImage will render it
  /// automatically (asset vs network is picked by [String.startsWith]).
  final String? iconPath;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'name': name,
      'count': count,
      'iconPath': iconPath,
    };
  }

  factory ConsumableItem.fromJson(Map<String, dynamic> json) {
    return ConsumableItem(
      id: json['id'] as String,
      type: ConsumableType.values.byName(json['type'] as String),
      name: json['name'] as String,
      count: json['count'] as int,
      iconPath: json['iconPath'] as String?,
    );
  }
}
