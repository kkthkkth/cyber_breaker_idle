import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/collection_model.dart';
import '../models/equipment.dart';
import 'equipment_manager.dart';
import 'game_manager.dart';

class CollectionManager extends ChangeNotifier {
  CollectionManager._internal() {
    collections = _defaultCollections();
  }

  static final CollectionManager instance = CollectionManager._internal();

  late final List<CollectionModel> collections;

  List<CollectionModel> byCategory(CollectionCategory category) =>
      collections.where((collection) => collection.category == category).toList();

  bool _matches(RequiredCollectionItem req, Equipment item) {
    return !item.isEquipped &&
        item.type == req.type &&
        item.grade == req.grade &&
        (req.subId == null || item.subId == req.subId) &&
        item.level >= req.requiredLevel;
  }

  /// 카테고리(캐릭터/장비/펫) 구분 없이 전체 도감을 통틀어 지금 바로
  /// 등록 가능한 미완성 도감이 하나라도 있는지 — 캐시하지 않고 매번
  /// [canRegister]로 다시 계산하므로, 이 값을 읽는 쪽이 CollectionManager와
  /// EquipmentManager(인벤토리)를 함께 구독하기만 하면 항상 최신 상태다.
  bool get hasAnyRegistrableCollection =>
      collections.any((collection) => canRegister(collection));

  /// [hasAnyRegistrableCollection]의 카테고리 한정 버전 — 2Depth "컬렉션"
  /// 탭의 레드닷 판정에 쓰인다(hasCollectionNoti).
  bool hasRegistrableInCategory(CollectionCategory category) =>
      byCategory(category).any((collection) => canRegister(collection));

  /// 인벤토리가 [collection]의 모든 요구 조건(등급/넘버링/레벨/수량)을
  /// 만족하는지 — 이미 완료된 도감은 항상 false.
  bool canRegister(CollectionModel collection) {
    if (collection.isCompleted) {
      return false;
    }
    final List<Equipment> inventory = EquipmentManager.instance.inventory;
    for (final RequiredCollectionItem req in collection.requiredItems) {
      final int matched = inventory.where((item) => _matches(req, item)).length;
      if (matched < req.count) {
        return false;
      }
    }
    return true;
  }

  /// 조건을 만족하면 재료를 인벤토리에서 차감하고, 완료 처리 후 영구
  /// 스탯 보너스를 GameManager에 반영한다. 조건 미충족 시 아무것도 바꾸지
  /// 않고 false를 반환한다.
  bool register(CollectionModel collection) {
    if (!canRegister(collection)) {
      return false;
    }

    final EquipmentManager equipmentManager = EquipmentManager.instance;
    for (final RequiredCollectionItem req in collection.requiredItems) {
      final List<Equipment> matched = equipmentManager.inventory
          .where((item) => _matches(req, item))
          .take(req.count)
          .toList();
      for (final Equipment item in matched) {
        equipmentManager.inventory.remove(item);
      }
    }
    equipmentManager.notifyListeners();
    equipmentManager.saveEquipment();

    collection.isCompleted = true;
    GameManager.instance.addCollectionBonus(collection.rewardStat.type, collection.rewardStat.value);

    notifyListeners();
    saveData();
    return true;
  }

  static const String _saveKey = 'collection_manager_save';

  /// 정의(title/requiredItems/rewardStat)는 매번 [_defaultCollections]로
  /// 다시 생성되므로(서버 연동 시 정의는 서버가 내려줌), 여기서는 완료된
  /// id 목록만 플레이어 진행 상태로 저장한다.
  Future<void> saveData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> completedIds = collections
        .where((collection) => collection.isCompleted)
        .map((collection) => collection.id)
        .toList();
    await prefs.setString(_saveKey, jsonEncode({'completedIds': completedIds}));
  }

  Future<void> loadData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      return;
    }

    final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
    final List<dynamic> completedIds = data['completedIds'] as List<dynamic>? ?? [];
    for (final CollectionModel collection in collections) {
      if (completedIds.contains(collection.id)) {
        collection.isCompleted = true;
      }
    }
    notifyListeners();
  }

  // TODO(server): replace with a real fetch of collection definitions —
  // everything above only ever reads/writes through [collections].
  static List<CollectionModel> _defaultCollections() {
    return [
      CollectionModel(
        id: 'char_n_collector',
        category: CollectionCategory.character,
        title: '초급 캐릭터 수집가 I',
        requiredItems: const [
          RequiredCollectionItem(type: EquipType.character, grade: ItemGrade.n, subId: 1, count: 3),
        ],
        rewardStat: const CollectionRewardStat(type: CollectionStatType.attackPower, value: 0.02),
      ),
      CollectionModel(
        id: 'char_sr_collector',
        category: CollectionCategory.character,
        title: '중급 캐릭터 수집가 II',
        requiredItems: const [
          RequiredCollectionItem(
            type: EquipType.character,
            grade: ItemGrade.sr,
            subId: 1,
            requiredLevel: 5,
            count: 2,
          ),
        ],
        rewardStat: const CollectionRewardStat(type: CollectionStatType.criticalRate, value: 0.02),
      ),
      CollectionModel(
        id: 'char_ur_collector',
        category: CollectionCategory.character,
        title: '전설 캐릭터 수집가 III',
        requiredItems: const [
          RequiredCollectionItem(type: EquipType.character, grade: ItemGrade.ur, subId: 1, count: 1),
        ],
        rewardStat: const CollectionRewardStat(type: CollectionStatType.attackPower, value: 0.10),
      ),
      CollectionModel(
        id: 'equip_weapon_set',
        category: CollectionCategory.equipment,
        title: '초급 무기 수집가 I',
        requiredItems: const [
          RequiredCollectionItem(type: EquipType.weapon, grade: ItemGrade.n, subId: 1, count: 4),
        ],
        rewardStat: const CollectionRewardStat(type: CollectionStatType.attackPower, value: 0.03),
      ),
      CollectionModel(
        id: 'equip_armor_set',
        category: CollectionCategory.equipment,
        title: '방어구 마스터 II',
        requiredItems: const [
          RequiredCollectionItem(
            type: EquipType.armor,
            grade: ItemGrade.ssr,
            subId: 1,
            requiredLevel: 10,
            count: 1,
          ),
          RequiredCollectionItem(
            type: EquipType.shield,
            grade: ItemGrade.ssr,
            subId: 2,
            requiredLevel: 10,
            count: 1,
          ),
        ],
        rewardStat: const CollectionRewardStat(type: CollectionStatType.defenseRate, value: 0.03),
      ),
      CollectionModel(
        id: 'equip_relic_set',
        category: CollectionCategory.equipment,
        title: '유물 발굴가 III',
        requiredItems: const [
          RequiredCollectionItem(type: EquipType.relic, grade: ItemGrade.lr, subId: 1, count: 1),
        ],
        rewardStat: const CollectionRewardStat(type: CollectionStatType.defense, value: 0.15),
      ),
      CollectionModel(
        id: 'pet_n_collector',
        category: CollectionCategory.pet,
        title: '초급 펫 조련사 I',
        requiredItems: const [
          RequiredCollectionItem(type: EquipType.pet, grade: ItemGrade.r, subId: 1, count: 3),
        ],
        rewardStat: const CollectionRewardStat(type: CollectionStatType.evasionRate, value: 0.02),
      ),
      CollectionModel(
        id: 'pet_sssr_collector',
        category: CollectionCategory.pet,
        title: '희귀 펫 조련사 II',
        requiredItems: const [
          RequiredCollectionItem(
            type: EquipType.pet,
            grade: ItemGrade.sssr,
            subId: 1,
            requiredLevel: 3,
            count: 1,
          ),
        ],
        rewardStat: const CollectionRewardStat(type: CollectionStatType.critDefenseRate, value: 0.025),
      ),
      CollectionModel(
        id: 'pet_lr_collector',
        category: CollectionCategory.pet,
        title: '펫 마스터 III',
        requiredItems: const [
          RequiredCollectionItem(type: EquipType.pet, grade: ItemGrade.lr, subId: 1, count: 1),
        ],
        rewardStat: const CollectionRewardStat(type: CollectionStatType.attackPower, value: 0.20),
      ),
    ];
  }
}
