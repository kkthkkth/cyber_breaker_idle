import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/consumable_item_model.dart';
import '../models/item_model.dart';
import 'consumable_manager.dart';
import 'game_manager.dart';

class GachaManager extends ChangeNotifier {
  GachaManager._internal();

  static final GachaManager instance = GachaManager._internal();

  static const int singlePullCost = 100;
  static const int synthesisRequirement = 5;

  final Random _random = Random();

  /// Swappable at runtime once a real gacha config is fetched from the
  /// server — everything below only ever reads through this field.
  GachaRate premiumRate = GachaRate.premiumDefault;

  /// Item templates to draw from, grouped by rarity. Dummy data for now;
  /// replace via [replaceCatalog] once item definitions live in a DB —
  /// drawPremiumGacha/synthesizeItem don't need to change at all.
  Map<ItemRarity, List<Item>> itemCatalog = _defaultCatalog();

  final List<Item> inventory = [];

  void replaceCatalog(Map<ItemRarity, List<Item>> catalog) {
    itemCatalog = catalog;
  }

  /// Draws [times] items from [premiumRate], paying with 고급 장비 뽑기권
  /// tickets when available (10 tickets → 11-pull bonus, 1 ticket → 1 pull)
  /// and falling back to `singlePullCost * times` gems otherwise. Returns
  /// the drawn items (already merged into [inventory]), or an empty list if
  /// the player couldn't afford it.
  List<Item> drawPremiumGacha(int times) {
    if (times <= 0) {
      return [];
    }

    int drawCount = _drawCountUsingTickets(times);
    if (drawCount == 0) {
      final int cost = singlePullCost * times;
      if (!GameManager.instance.spendGems(cost)) {
        return [];
      }
      drawCount = times;
    }

    final List<Item> results = [];
    for (int i = 0; i < drawCount; i++) {
      final ItemRarity rarity = premiumRate.roll(_random);
      final Item template = _pickTemplate(rarity);
      results.add(_addToInventory(template));
    }

    notifyListeners();
    saveGachaInventory();
    return results;
  }

  /// Returns how many items to draw if [times] can be covered by tickets
  /// (consuming them in the process), or 0 if gems should be used instead.
  int _drawCountUsingTickets(int times) {
    if (times == 10 &&
        ConsumableManager.instance
            .consume(ConsumableType.premiumGachaTicket, amount: 10)) {
      return 11;
    }
    if (times == 1 &&
        ConsumableManager.instance
            .consume(ConsumableType.premiumGachaTicket, amount: 1)) {
      return 1;
    }
    return 0;
  }

  Item _pickTemplate(ItemRarity rarity) {
    final List<Item> pool = itemCatalog[rarity] ?? const [];
    assert(pool.isNotEmpty, 'No catalog entries for rarity $rarity');
    return pool[_random.nextInt(pool.length)];
  }

  Item _addToInventory(Item template) {
    final int index = inventory.indexWhere((item) => item.id == template.id);
    if (index != -1) {
      inventory[index].count++;
      return inventory[index];
    }

    final Item newItem = Item(
      id: template.id,
      name: template.name,
      rarity: template.rarity,
      baseStat: template.baseStat,
      count: 1,
    );
    inventory.add(newItem);
    return newItem;
  }

  /// Consumes [synthesisRequirement] copies of the item with [itemId] and
  /// grants one random item of the next rarity tier up. Returns false if
  /// the item doesn't exist, doesn't have enough copies, or is already the
  /// highest rarity.
  bool synthesizeItem(String itemId) {
    final int index = inventory.indexWhere((item) => item.id == itemId);
    if (index == -1) {
      return false;
    }

    final Item source = inventory[index];
    if (source.count < synthesisRequirement) {
      return false;
    }

    final int nextRarityIndex = source.rarity.index + 1;
    if (nextRarityIndex >= ItemRarity.values.length) {
      return false;
    }

    final ItemRarity nextRarity = ItemRarity.values[nextRarityIndex];
    final Item upgraded = _pickTemplate(nextRarity);

    source.count -= synthesisRequirement;
    if (source.count <= 0) {
      inventory.removeAt(index);
    }
    _addToInventory(upgraded);

    notifyListeners();
    saveGachaInventory();
    return true;
  }

  static const String _saveKey = 'gacha_manager_save';

  Future<void> saveGachaInventory() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String json = jsonEncode(inventory.map((item) => item.toJson()).toList());
    await prefs.setString(_saveKey, json);
  }

  Future<void> loadGachaInventory() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      return;
    }

    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      inventory
        ..clear()
        ..addAll(decoded.map((entry) => Item.fromJson(entry as Map<String, dynamic>)));
    } catch (error) {
      debugPrint('[GachaManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
      return;
    }

    notifyListeners();
  }

  static Map<ItemRarity, List<Item>> _defaultCatalog() {
    return {
      ItemRarity.normal: [
        Item(id: 'normal_sword', name: '낡은 검', rarity: ItemRarity.normal, baseStat: 5),
        Item(id: 'normal_shield', name: '낡은 방패', rarity: ItemRarity.normal, baseStat: 5),
      ],
      ItemRarity.rare: [
        Item(id: 'rare_sword', name: '단련된 검', rarity: ItemRarity.rare, baseStat: 15),
        Item(id: 'rare_armor', name: '단련된 갑옷', rarity: ItemRarity.rare, baseStat: 15),
      ],
      ItemRarity.epic: [
        Item(id: 'epic_sword', name: '마법 검', rarity: ItemRarity.epic, baseStat: 40),
        Item(id: 'epic_ring', name: '마법 반지', rarity: ItemRarity.epic, baseStat: 40),
      ],
      ItemRarity.legendary: [
        Item(id: 'legendary_sword', name: '용살의 검', rarity: ItemRarity.legendary, baseStat: 100),
        Item(id: 'legendary_armor', name: '용비늘 갑옷', rarity: ItemRarity.legendary, baseStat: 100),
      ],
      ItemRarity.mythic: [
        Item(id: 'mythic_sword', name: '태초의 검', rarity: ItemRarity.mythic, baseStat: 250),
      ],
    };
  }
}
