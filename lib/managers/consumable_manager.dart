import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/consumable_item_model.dart';
import '../models/drop_table_model.dart';
import 'skill_manager.dart';

/// Owns the player's consumable stacks (speed boosts, tickets, dust, etc).
/// Backed by dummy starting stock for now; once consumables move to a DB,
/// replace [_dummyInventory] with a real fetch — [inventory] is what every
/// reader (UI grids, [countOf]/[consume]) actually goes through.
class ConsumableManager extends ChangeNotifier {
  ConsumableManager._internal() {
    loadInventoryData();
  }

  static final ConsumableManager instance = ConsumableManager._internal();

  final Random _random = Random();

  /// Swappable at runtime once fetched from a real drop-rate config — see
  /// [DropTable.fromJson].
  DropTable dropTable = DropTable.defaultTable;

  final List<ConsumableItem> inventory = _dummyInventory();

  static List<ConsumableItem> _dummyInventory() {
    return ConsumableType.values
        .map(
          (type) => ConsumableItem(
            id: type.name,
            type: type,
            name: type.displayName,
            count: 1,
          ),
        )
        .toList();
  }

  int countOf(ConsumableType type) => _find(type)?.count ?? 0;

  bool hasItem(ConsumableType type, {int amount = 1}) =>
      countOf(type) >= amount;

  void addItem(ConsumableType type, int amount) {
    if (amount <= 0) {
      return;
    }
    final ConsumableItem? existing = _find(type);
    if (existing != null) {
      existing.count += amount;
    } else {
      inventory.add(
        ConsumableItem(id: type.name, type: type, name: type.displayName, count: amount),
      );
    }
    notifyListeners();
    saveInventoryData();
  }

  bool consume(ConsumableType type, {int amount = 1}) {
    final ConsumableItem? item = _find(type);
    if (item == null || item.count < amount) {
      return false;
    }
    item.count -= amount;
    notifyListeners();
    saveInventoryData();
    return true;
  }

  ConsumableItem? _find(ConsumableType type) {
    for (final ConsumableItem item in inventory) {
      if (item.type == type) {
        return item;
      }
    }
    return null;
  }

  /// Rolls every entry in [dropTable] independently and adds whatever hits
  /// into [inventory]. Call this on monster/boss kills.
  List<ConsumableType> rollDrops() {
    final List<ConsumableType> dropped = [];
    for (final DropEntry entry in dropTable.entries) {
      if (_random.nextDouble() < entry.dropRate) {
        addItem(entry.type, 1);
        dropped.add(entry.type);
      }
    }
    return dropped;
  }

  /// Consumes one 스킬 초기화권, refunding every spent skill point and
  /// unlocking [SkillManager.chosenElement]. Returns false if none owned.
  bool useSkillReset() {
    if (!consume(ConsumableType.skillReset)) {
      return false;
    }
    SkillManager.instance.resetAllSkills();
    return true;
  }

  static const String _saveKey = 'consumable_manager_save';

  Future<void> saveInventoryData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String json = jsonEncode(
      inventory.map((item) => item.toJson()).toList(),
    );
    await prefs.setString(_saveKey, json);
  }

  Future<void> loadInventoryData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      return;
    }

    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    inventory
      ..clear()
      ..addAll(
        decoded.map(
          (entry) => ConsumableItem.fromJson(entry as Map<String, dynamic>),
        ),
      );

    notifyListeners();
  }
}
