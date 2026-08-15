import 'dart:math';

import 'package:flutter/material.dart';

enum ItemRarity { normal, rare, epic, legendary, mythic }

extension ItemRarityX on ItemRarity {
  String get displayName {
    switch (this) {
      case ItemRarity.normal:
        return '노멀';
      case ItemRarity.rare:
        return '레어';
      case ItemRarity.epic:
        return '에픽';
      case ItemRarity.legendary:
        return '레전더리';
      case ItemRarity.mythic:
        return '신화';
    }
  }
}

Color getRarityColor(ItemRarity rarity) {
  switch (rarity) {
    case ItemRarity.normal:
      return const Color(0xFF9E9E9E);
    case ItemRarity.rare:
      return const Color(0xFF2ECC71);
    case ItemRarity.epic:
      return const Color(0xFF9B59B6);
    case ItemRarity.legendary:
      return const Color(0xFFE67E22);
    case ItemRarity.mythic:
      return const Color(0xFFFF3B3B);
  }
}

class Item {
  Item({
    required this.id,
    required this.name,
    required this.rarity,
    required this.baseStat,
    this.count = 1,
  });

  final String id;
  final String name;
  final ItemRarity rarity;
  final double baseStat;
  int count;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'rarity': rarity.name,
      'baseStat': baseStat,
      'count': count,
    };
  }

  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      id: json['id'] as String,
      name: json['name'] as String,
      rarity: ItemRarity.values.byName(json['rarity'] as String),
      baseStat: (json['baseStat'] as num).toDouble(),
      count: json['count'] as int? ?? 1,
    );
  }
}

/// Holds the drop-weight table for a gacha banner. Kept separate from
/// [GachaManager] so the whole thing can be replaced wholesale with a
/// server-fetched table later (see [GachaRate.fromJson]).
class GachaRate {
  const GachaRate(this.weights);

  final Map<ItemRarity, double> weights;

  static const GachaRate premiumDefault = GachaRate({
    ItemRarity.normal: 0.40,
    ItemRarity.rare: 0.30,
    ItemRarity.epic: 0.20,
    ItemRarity.legendary: 0.09,
    ItemRarity.mythic: 0.01,
  });

  Map<String, dynamic> toJson() {
    return {
      for (final MapEntry<ItemRarity, double> entry in weights.entries)
        entry.key.name: entry.value,
    };
  }

  factory GachaRate.fromJson(Map<String, dynamic> json) {
    return GachaRate({
      for (final MapEntry<String, dynamic> entry in json.entries)
        ItemRarity.values.byName(entry.key): (entry.value as num).toDouble(),
    });
  }

  /// Weighted-random rarity roll. Falls back to the rarest tier if the
  /// weights don't sum to exactly 1.0 (defensive against bad DB data).
  ItemRarity roll(Random random) {
    final double target = random.nextDouble();
    double cumulative = 0;
    for (final ItemRarity rarity in ItemRarity.values) {
      cumulative += weights[rarity] ?? 0;
      if (target < cumulative) {
        return rarity;
      }
    }
    return ItemRarity.values.last;
  }
}
