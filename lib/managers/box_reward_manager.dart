import 'dart:math';

import '../models/box_reward_model.dart';
import '../models/consumable_item_model.dart';
import 'consumable_manager.dart';
import 'game_manager.dart';

/// Owns what's inside each reward-box tier, kept separate from
/// ConsumableManager so drop tables can move to a DB/remote-config later
/// without touching inventory/consume logic — see [_tables].
class BoxRewardManager {
  BoxRewardManager._internal();

  static final BoxRewardManager instance = BoxRewardManager._internal();

  final Random _random = Random();

  // TODO(server): replace with a real fetch of box reward tables once they
  // move to a DB — [openBox] only ever reads through this map.
  static const Map<ConsumableType, List<BoxRewardEntry>> _tables = {
    ConsumableType.normalBox: [
      BoxRewardEntry(kind: BoxRewardKind.gold, amount: 1000, weight: 0.6),
      BoxRewardEntry(kind: BoxRewardKind.dust, amount: 30, weight: 0.4),
    ],
    ConsumableType.advancedBox: [
      BoxRewardEntry(kind: BoxRewardKind.gold, amount: 5000, weight: 0.5),
      BoxRewardEntry(kind: BoxRewardKind.dust, amount: 80, weight: 0.3),
      BoxRewardEntry(
        kind: BoxRewardKind.item,
        amount: 1,
        weight: 0.2,
        itemType: ConsumableType.speed2x,
      ),
    ],
    ConsumableType.heroBox: [
      BoxRewardEntry(kind: BoxRewardKind.gem, amount: 50, weight: 0.4),
      BoxRewardEntry(kind: BoxRewardKind.dust, amount: 150, weight: 0.3),
      BoxRewardEntry(
        kind: BoxRewardKind.item,
        amount: 1,
        weight: 0.3,
        itemType: ConsumableType.premiumGachaTicket,
      ),
    ],
    ConsumableType.legendaryBox: [
      BoxRewardEntry(kind: BoxRewardKind.gem, amount: 200, weight: 0.5),
      BoxRewardEntry(
        kind: BoxRewardKind.item,
        amount: 1,
        weight: 0.3,
        itemType: ConsumableType.crossElementBook,
      ),
      BoxRewardEntry(
        kind: BoxRewardKind.item,
        amount: 3,
        weight: 0.2,
        itemType: ConsumableType.premiumGachaTicket,
      ),
    ],
  };

  List<BoxRewardEntry> tableFor(ConsumableType boxType) =>
      _tables[boxType] ?? const [];

  /// Consumes one [boxType] and grants a weighted-random reward from its
  /// table. Returns null if the player doesn't own one.
  BoxRewardEntry? openBox(ConsumableType boxType) {
    if (!ConsumableManager.instance.consume(boxType)) {
      return null;
    }

    final BoxRewardEntry picked = _weightedPick(tableFor(boxType));
    _grant(picked);
    return picked;
  }

  BoxRewardEntry _weightedPick(List<BoxRewardEntry> entries) {
    final double totalWeight = entries.fold(0.0, (sum, e) => sum + e.weight);
    double roll = _random.nextDouble() * totalWeight;

    for (final BoxRewardEntry entry in entries) {
      if (roll < entry.weight) {
        return entry;
      }
      roll -= entry.weight;
    }
    return entries.last;
  }

  void _grant(BoxRewardEntry entry) {
    switch (entry.kind) {
      case BoxRewardKind.gold:
        GameManager.instance.addGold(entry.amount);
      case BoxRewardKind.gem:
        GameManager.instance.addGems(entry.amount);
      case BoxRewardKind.dust:
        ConsumableManager.instance.addItem(ConsumableType.dust, entry.amount);
      case BoxRewardKind.item:
        if (entry.itemType != null) {
          ConsumableManager.instance.addItem(entry.itemType!, entry.amount);
        }
    }
  }
}
