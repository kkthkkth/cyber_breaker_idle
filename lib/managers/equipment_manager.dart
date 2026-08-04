import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/equipment.dart';

class EquipmentManager extends ChangeNotifier {
  EquipmentManager._internal() {
    _generateTestInventory();
  }

  static final EquipmentManager instance = EquipmentManager._internal();

  final Random _random = Random();

  final List<Equipment> inventory = [];

  final Map<EquipType, Equipment?> equippedItems = {
    for (final EquipType type in EquipType.values) type: null,
  };

  void equipItem(Equipment item) {
    final Equipment? current = equippedItems[item.type];
    if (current != null) {
      current.isEquipped = false;
    }

    item.isEquipped = true;
    equippedItems[item.type] = item;
    notifyListeners();
  }

  void unequipItem(EquipType type) {
    final Equipment? current = equippedItems[type];
    if (current == null) {
      return;
    }

    current.isEquipped = false;
    equippedItems[type] = null;
    notifyListeners();
  }

  static const String _inventoryKey = 'equipment_inventory';

  Future<void> saveEquipment() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String inventoryJson = jsonEncode(
      inventory.map((item) => item.toJson()).toList(),
    );
    await prefs.setString(_inventoryKey, inventoryJson);
    debugPrint('Equipment saved: ${inventory.length} items');
  }

  // equippedItems isn't persisted separately — it's fully derivable from
  // inventory's `isEquipped`/`type` fields, so re-deriving it on load avoids
  // the two structures ever drifting out of sync.
  Future<void> loadEquipment() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? inventoryJson = prefs.getString(_inventoryKey);
    if (inventoryJson == null) {
      debugPrint('Equipment loaded: no saved data found under "$_inventoryKey"');
      return;
    }

    final List<dynamic> decoded = jsonDecode(inventoryJson) as List<dynamic>;
    final List<Equipment> loadedItems = decoded
        .map((entry) => Equipment.fromJson(entry as Map<String, dynamic>))
        .toList();

    inventory
      ..clear()
      ..addAll(loadedItems);

    for (final EquipType type in EquipType.values) {
      equippedItems[type] = null;
    }
    for (final Equipment item in loadedItems) {
      if (item.isEquipped) {
        equippedItems[item.type] = item;
      }
    }

    notifyListeners();
    debugPrint('Equipment loaded: ${inventory.length} items');
  }

  double getTotalEquipmentMultiplier() {
    return equippedItems.values
        .whereType<Equipment>()
        .fold(0.0, (double sum, Equipment item) => sum + item.statMultiplier);
  }

  Equipment generateRandomLoot() => generateGuaranteedLoot(ItemGrade.values);

  /// Rolls loot whose grade is restricted to [allowedGrades] — used by
  /// content (e.g. the equipment dungeon boss) that guarantees a high-tier
  /// drop instead of the full random spread.
  Equipment generateGuaranteedLoot(List<ItemGrade> allowedGrades) {
    final List<EquipType> types = EquipType.values;

    final EquipType type = types[_random.nextInt(types.length)];
    final ItemGrade grade = allowedGrades[_random.nextInt(allowedGrades.length)];
    final double statMultiplier = _rollStatMultiplier(grade);

    final Equipment loot = Equipment(
      id: 'item_${DateTime.now().microsecondsSinceEpoch}',
      name: '${grade.displayName} ${type.displayName}',
      type: type,
      grade: grade,
      statMultiplier: statMultiplier,
      isEquipped: false,
    );

    inventory.add(loot);
    notifyListeners();
    return loot;
  }

  double _rollStatMultiplier(ItemGrade grade) {
    final (double min, double max) range = switch (grade) {
      ItemGrade.normal => (0.05, 0.10),
      ItemGrade.rare => (0.10, 0.25),
      ItemGrade.unique => (0.25, 0.50),
      ItemGrade.epic => (0.50, 1.00),
      ItemGrade.legendary => (1.00, 1.50),
      ItemGrade.mythic => (1.50, 3.00),
    };

    final double value =
        range.$1 + _random.nextDouble() * (range.$2 - range.$1);
    return double.parse(value.toStringAsFixed(2));
  }

  void _generateTestInventory() {
    final Random random = Random();
    final List<EquipType> types = EquipType.values;
    final List<ItemGrade> grades = ItemGrade.values;

    for (int i = 0; i < 10; i++) {
      final EquipType type = types[random.nextInt(types.length)];
      final ItemGrade grade = grades[random.nextInt(grades.length)];
      final double statMultiplier =
          double.parse((1.0 + grade.index * 0.5 + random.nextDouble()).toStringAsFixed(2));

      inventory.add(
        Equipment(
          id: 'item_${DateTime.now().microsecondsSinceEpoch}_$i',
          name: '${grade.displayName} ${type.displayName}',
          type: type,
          grade: grade,
          statMultiplier: statMultiplier,
          isEquipped: false,
        ),
      );
    }
  }
}
