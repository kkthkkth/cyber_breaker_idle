import 'package:flutter/material.dart';

import 'consumable_item_model.dart';

/// 제작 결과가 무엇으로 지급되는지 — 대부분은 [ConsumableType] 아이템이지만,
/// SP 제작(스킬 SP/펫 SP)이나 펫 던전 충전권처럼 소비형 아이템이 아닌
/// 재화/카운터 직접 증가 방식도 있어 분리해 둔다.
enum CraftRewardType { item, characterSp, petSp, petDungeonTicket }

/// Server-ready crafting recipe: spend [requiredAmount] of a tab-level
/// currency (가루/발바닥/보석 — chosen by the screen, not the recipe) for a
/// [successRate] chance at the reward described by [rewardType].
class CraftRecipe {
  const CraftRecipe({
    this.targetItemType,
    required this.requiredAmount,
    required this.successRate,
    this.rewardType = CraftRewardType.item,
  }) : assert(
         rewardType != CraftRewardType.item || targetItemType != null,
         'rewardType이 item이면 targetItemType이 필요합니다.',
       );

  /// [rewardType]이 [CraftRewardType.item]일 때만 사용된다.
  final ConsumableType? targetItemType;
  final int requiredAmount;
  final double successRate;
  final CraftRewardType rewardType;

  String get displayName {
    switch (rewardType) {
      case CraftRewardType.item:
        return targetItemType!.displayName;
      case CraftRewardType.characterSp:
        return '캐릭터 SP';
      case CraftRewardType.petSp:
        return '펫 SP';
      case CraftRewardType.petDungeonTicket:
        return '펫 던전 충전권';
    }
  }

  IconData get icon {
    switch (rewardType) {
      case CraftRewardType.item:
        return targetItemType!.icon;
      case CraftRewardType.characterSp:
        return Icons.auto_awesome;
      case CraftRewardType.petSp:
        return Icons.pets;
      case CraftRewardType.petDungeonTicket:
        return Icons.confirmation_number;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'targetItemType': targetItemType?.name,
      'requiredAmount': requiredAmount,
      'successRate': successRate,
      'rewardType': rewardType.name,
    };
  }

  factory CraftRecipe.fromJson(Map<String, dynamic> json) {
    final String? itemTypeName = json['targetItemType'] as String?;
    return CraftRecipe(
      targetItemType:
          itemTypeName != null ? ConsumableType.values.byName(itemTypeName) : null,
      requiredAmount: json['requiredAmount'] as int,
      successRate: (json['successRate'] as num).toDouble(),
      rewardType: CraftRewardType.values.byName(
        json['rewardType'] as String? ?? CraftRewardType.item.name,
      ),
    );
  }

  /// Dummy recipe pool for now; once recipes move to a DB, decode a list of
  /// these directly from the response — CraftingScreen only ever reads
  /// through this list.
  static const List<CraftRecipe> defaultRecipes = [
    CraftRecipe(
      targetItemType: ConsumableType.speed2x,
      requiredAmount: 20,
      successRate: 0.9,
    ),
    CraftRecipe(
      targetItemType: ConsumableType.skillReset,
      requiredAmount: 80,
      successRate: 0.5,
    ),
    CraftRecipe(
      targetItemType: ConsumableType.premiumGachaTicket,
      requiredAmount: 100,
      successRate: 0.4,
    ),
    CraftRecipe(
      targetItemType: ConsumableType.crossElementBook,
      requiredAmount: 60,
      successRate: 0.6,
    ),
    CraftRecipe(
      targetItemType: ConsumableType.goldDungeonTicket,
      requiredAmount: 40,
      successRate: 0.7,
    ),
    CraftRecipe(
      targetItemType: ConsumableType.equipDungeonTicket,
      requiredAmount: 40,
      successRate: 0.7,
    ),
    CraftRecipe(
      targetItemType: ConsumableType.towerSweepTicket,
      requiredAmount: 50,
      successRate: 0.6,
    ),
    CraftRecipe(
      requiredAmount: 40,
      successRate: 0.7,
      rewardType: CraftRewardType.petDungeonTicket,
    ),
  ];

  /// 캐릭터 SP 제작 — 캐릭터 탭의 [제작] 서브 탭 전용. 원래 [defaultRecipes]에
  /// 섞여 있었지만 탭 구조가 카테고리(장비/펫/캐릭터/소모품) 기준으로
  /// 바뀌면서 캐릭터 탭 쪽으로 옮겼다.
  static const List<CraftRecipe> characterCraftRecipes = [
    CraftRecipe(
      requiredAmount: 500,
      successRate: 1.0,
      rewardType: CraftRewardType.characterSp,
    ),
  ];

  /// Dummy "장비 소환 상자" pool for the 장비제작 tab — 가루로 상자를 제작한다.
  static const List<CraftRecipe> equipmentCraftRecipes = [
    CraftRecipe(
      targetItemType: ConsumableType.normalBox,
      requiredAmount: 40,
      successRate: 0.9,
    ),
    CraftRecipe(
      targetItemType: ConsumableType.advancedBox,
      requiredAmount: 80,
      successRate: 0.7,
    ),
    CraftRecipe(
      targetItemType: ConsumableType.heroBox,
      requiredAmount: 150,
      successRate: 0.5,
    ),
    CraftRecipe(
      targetItemType: ConsumableType.legendaryBox,
      requiredAmount: 300,
      successRate: 0.3,
    ),
  ];

  /// Dummy "펫 소환 상자" pool for the 펫제작 탭 — 발바닥으로 상자를 제작한다.
  static const List<CraftRecipe> petCraftRecipes = [
    CraftRecipe(
      requiredAmount: 500,
      successRate: 1.0,
      rewardType: CraftRewardType.petSp,
    ),
    CraftRecipe(
      targetItemType: ConsumableType.normalBox,
      requiredAmount: 40,
      successRate: 0.9,
    ),
    CraftRecipe(
      targetItemType: ConsumableType.advancedBox,
      requiredAmount: 80,
      successRate: 0.7,
    ),
    CraftRecipe(
      targetItemType: ConsumableType.heroBox,
      requiredAmount: 150,
      successRate: 0.5,
    ),
    CraftRecipe(
      targetItemType: ConsumableType.legendaryBox,
      requiredAmount: 300,
      successRate: 0.3,
    ),
  ];
}
