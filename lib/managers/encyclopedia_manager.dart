import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/item_pool_config.dart';
import '../models/collection_model.dart';
import '../models/encyclopedia_model.dart';
import '../models/equipment.dart';
import 'character_manifest_manager.dart';
import 'collection_manager.dart';
import 'equipment_manager.dart';
import 'game_manager.dart';

/// 도감(Encyclopedia) — "실제로 존재하는(아트가 준비된) 전체 마스터 목록"을
/// 그대로 한 칸씩 펼쳐서 보여준다. 유저가 보유했는지와 무관하게 매 등급·매
/// 넘버링(subId)이 전부 칸으로 나오고, 보유 여부는 [isOwned]가 실시간으로
/// 판정한다 — 그래서 미보유 항목도(회색조로) 항상 그리드에 노출된다.
/// [CollectionManager]의 세트 수집(컬렉션) 요구 아이템과는 별개의, 더 넓은
/// "전체 등록" 개념이다.
///
/// 캐릭터는 [CharacterManifestManager](원격 `characters.json`)에 실제로
/// 등록된 만큼만 칸이 생긴다 — 펫/장비는 여전히 [ItemPoolConfig]의 등급별
/// 개수를 그대로 쓴다(둘 다 아직 캐릭터처럼 개별 파츠 아트 관리 체계로
/// 옮기지 않았다).
class EncyclopediaManager extends ChangeNotifier {
  EncyclopediaManager._internal() {
    entries = _buildEntries();
  }

  static final EncyclopediaManager instance = EncyclopediaManager._internal();

  late final List<EncyclopediaEntry> entries;

  /// "장비" 카테고리에 속하는 모든 부위 — 캐릭터/펫을 제외한 나머지 전부.
  /// [ItemPoolConfig.maxEquipmentCount]가 부위 구분 없이 등급당 개수
  /// 하나로 관리되므로, 나열된 부위마다 같은 등급별 개수를 그대로 적용한다.
  static const List<EquipType> _equipmentTypes = [
    EquipType.weapon,
    EquipType.helmet,
    EquipType.armor,
    EquipType.shield,
    EquipType.boots,
    EquipType.ring,
    EquipType.glove,
    EquipType.belt,
    EquipType.relic,
  ];

  static List<EncyclopediaEntry> _buildEntries() {
    final List<EncyclopediaEntry> result = [];

    void addGrade(CollectionCategory category, EquipType type, ItemGrade grade, int count) {
      for (int subId = 1; subId <= count; subId++) {
        result.add(EncyclopediaEntry(category: category, type: type, grade: grade, subId: subId));
      }
    }

    for (final ItemGrade grade in ItemGrade.values) {
      for (final int subId in CharacterManifestManager.instance.subIdsFor(grade)) {
        result.add(
          EncyclopediaEntry(
            category: CollectionCategory.character,
            type: EquipType.character,
            grade: grade,
            subId: subId,
          ),
        );
      }
      addGrade(
        CollectionCategory.pet,
        EquipType.pet,
        grade,
        ItemPoolConfig.maxPetCount[grade] ?? 0,
      );
      for (final EquipType type in _equipmentTypes) {
        addGrade(
          CollectionCategory.equipment,
          type,
          grade,
          ItemPoolConfig.maxEquipmentCount[grade] ?? 0,
        );
      }
    }

    return result;
  }

  List<EncyclopediaEntry> byCategory(CollectionCategory category) =>
      entries.where((entry) => entry.category == category).toList();

  /// 이 카테고리 안에 "보유했지만 아직 보상을 안 받은" 항목이 하나라도
  /// 있는지 — 2Depth "도감" 탭의 레드닷 판정(hasEncyclopediaNoti)에 쓰인다.
  bool hasClaimableInCategory(CollectionCategory category) =>
      byCategory(category).any((entry) => !entry.isRewarded && isOwned(entry));

  /// 카테고리 불문 전체를 통틀어 "도감 보상"이나 "컬렉션 등록" 중 하나라도
  /// 가능한 게 있는지 — 슬롯(하위) → 2Depth → 1Depth를 거쳐 올라온 알림을
  /// 최종적으로 종합하는 지점. 캐릭터 화면의 [수집] 버튼, 하단 네비게이션
  /// 바의 [캐릭터] 탭 아이콘처럼 도감/컬렉션 화면 바깥의 상위 UI가 이
  /// 하나만 구독하면 전체 체인이 자동으로 연결된다.
  bool get hasAnyCollectionReward =>
      entries.any((entry) => !entry.isRewarded && isOwned(entry)) ||
      CollectionManager.instance.hasAnyRegistrableCollection;

  /// 보상을 이미 받았다면(=한 번이라도 보유가 확정됐다면) 항상 true. 아직
  /// 안 받았다면 현재 인벤토리(장착/미장착 모두 포함)에 같은 조합이 있는지로
  /// 실시간 판정한다.
  bool isOwned(EncyclopediaEntry entry) {
    if (entry.isRewarded) {
      return true;
    }
    return EquipmentManager.instance.inventory.any(
      (item) =>
          item.type == entry.type && item.grade == entry.grade && item.subId == entry.subId,
    );
  }

  /// 보유 중이고 아직 보상을 안 받았다면 보석을 지급하고 [EncyclopediaEntry.isRewarded]를
  /// 굳힌다. 이미 받았거나 보유하지 않았다면 아무것도 하지 않고 false.
  bool claimReward(EncyclopediaEntry entry) {
    if (entry.isRewarded || !isOwned(entry)) {
      return false;
    }

    entry.isRewarded = true;
    GameManager.instance.addGems(entry.gemReward);
    notifyListeners();
    saveData();
    return true;
  }

  static const String _saveKey = 'encyclopedia_manager_save';

  Future<void> saveData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> rewardedIds = entries
        .where((entry) => entry.isRewarded)
        .map((entry) => entry.id)
        .toList();
    await prefs.setString(_saveKey, jsonEncode({'rewardedIds': rewardedIds}));
  }

  Future<void> loadData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      return;
    }

    final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
    final List<dynamic> rewardedIds = data['rewardedIds'] as List<dynamic>? ?? [];
    for (final EncyclopediaEntry entry in entries) {
      if (rewardedIds.contains(entry.id)) {
        entry.isRewarded = true;
      }
    }
    notifyListeners();
  }
}
