import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/equipment.dart' show ItemGrade;
import '../models/pet_model.dart';

/// 펫 인벤토리/장착과, 장착된 펫의 옵션 수치를 실제 게임 연산에 꽂아 넣을
/// 합산 값을 제공하는 컨트롤러. 슬롯은 한 번에 1마리만 장착 가능 —
/// [equippedPet]의 mainStat+subStats를 [getTotalBonus]가 타입별로 더한다.
class PetManager extends ChangeNotifier {
  PetManager._internal();

  static final PetManager instance = PetManager._internal();

  final List<Pet> inventory = [];
  String? equippedPetId;

  Pet? get equippedPet {
    final String? id = equippedPetId;
    if (id == null) {
      return null;
    }
    for (final Pet pet in inventory) {
      if (pet.id == id) {
        return pet;
      }
    }
    return null;
  }

  /// 장착된 펫의 메인+서브 옵션 중 [type]과 일치하는 값을 전부 더한다.
  /// 장착된 펫이 없으면 0 — 호출부에서 별도로 null 체크할 필요가 없다.
  double getTotalBonus(PetStatType type) {
    final Pet? pet = equippedPet;
    if (pet == null) {
      return 0;
    }
    double total = 0;
    for (final PetOption option in pet.displayOptions) {
      if (option.type == type) {
        total += option.value;
      }
    }
    return total;
  }

  double get goldGainBonus => getTotalBonus(PetStatType.goldGain);
  double get dropRateBonus => getTotalBonus(PetStatType.dropRateBoost);
  double get bossDamageBonus => getTotalBonus(PetStatType.bossDamage);
  double get finalAttackBoost => getTotalBonus(PetStatType.finalAttackBoost);
  double get skillCooldownReduction => getTotalBonus(PetStatType.skillCooldownReduction);
  double get criticalDamageBoost => getTotalBonus(PetStatType.criticalDamageBoost);

  /// [PetFactory]로 새 펫 한 마리를 굴려 인벤토리에 추가한다.
  Pet rollPet(PetCategory category, ItemGrade grade) {
    final Pet pet = PetFactory.generate(
      category: category,
      grade: grade,
      id: '${DateTime.now().microsecondsSinceEpoch}_${inventory.length}',
      name: '${grade.name.toUpperCase()} ${category.displayName}',
    );
    inventory.add(pet);
    notifyListeners();
    saveGame();
    return pet;
  }

  void equipPet(String id) {
    if (!inventory.any((pet) => pet.id == id)) {
      return;
    }
    for (final Pet pet in inventory) {
      pet.isEquipped = pet.id == id;
    }
    equippedPetId = id;
    notifyListeners();
    saveGame();
  }

  void unequipPet() {
    for (final Pet pet in inventory) {
      pet.isEquipped = false;
    }
    equippedPetId = null;
    notifyListeners();
    saveGame();
  }

  static const String _saveKey = 'pet_manager_save';

  Future<void> saveGame() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> data = {
      'inventory': inventory.map((pet) => pet.toJson()).toList(),
      'equippedPetId': equippedPetId,
    };
    await prefs.setString(_saveKey, jsonEncode(data));
  }

  Future<void> loadGame() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      return;
    }

    final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
    final List<dynamic>? savedInventory = data['inventory'] as List<dynamic>?;
    inventory
      ..clear()
      ..addAll(
        (savedInventory ?? const [])
            .map((entry) => Pet.fromJson(entry as Map<String, dynamic>)),
      );
    equippedPetId = data['equippedPetId'] as String?;
    notifyListeners();
  }
}
