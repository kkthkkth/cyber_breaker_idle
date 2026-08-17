import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../constants/item_pool_config.dart';
import '../models/consumable_item_model.dart';
import '../models/equipment.dart';
import 'achievement_manager.dart';
import 'consumable_manager.dart';
import 'game_manager.dart';
import 'pet_stat_metadata_manager.dart';
import 'pity_manager.dart';
import 'supabase_manager.dart';

class EquipmentManager extends ChangeNotifier {
  EquipmentManager._internal() {
    _generateTestInventory();
  }

  static final EquipmentManager instance = EquipmentManager._internal();

  final Random _random = Random();
  static const Uuid _uuid = Uuid();

  final List<Equipment> inventory = [];

  final Map<EquipType, Equipment?> equippedItems = {
    for (final EquipType type in EquipType.values) type: null,
  };

  /// 현재 장착 중인 펫(`EquipType.pet`) — [GameManager]/[SkillManager]가
  /// 펫 특수 보너스([Equipment.specialStats])를 읽는 유일한 진입점이다.
  /// 예전엔 이 데이터가 완전히 별개의(그리고 아무도 채우지 않는) 죽은
  /// PetManager에서 왔다 — 이제 실제로 가챠/장착이 이뤄지는 이
  /// [EquipmentManager] 하나로 소스가 통합됐다.
  Equipment? get equippedPet => equippedItems[EquipType.pet];

  /// 지금 장착 중인 장비를 [Equipment.setId]별로 몇 부위 장착했는지 센
  /// 맵(setId가 없는 장비는 집계에서 빠진다) — [EquipmentSetManager]가
  /// 이 맵 하나로 2부위/4부위 세트 효과 발동 여부를 판정한다.
  Map<String, int> get equippedSetCounts {
    final Map<String, int> counts = {};
    for (final Equipment? item in equippedItems.values) {
      final String? setId = item?.setId;
      if (setId == null) {
        continue;
      }
      counts[setId] = (counts[setId] ?? 0) + 1;
    }
    return counts;
  }

  /// [주의: 저장 누락 방지] 예전엔 여기서 notifyListeners()만 부르고
  /// [saveEquipment]를 호출하지 않았다 — 장착 상태가 로컬에도 즉시
  /// 저장되지 않고, 앱이 백그라운드로 밀려날 때(main.dart의
  /// AppLifecycleState 저장)까지 지연됐다. 그 사이 앱이 강제 종료되면
  /// 장착 변경이 그냥 사라졌다(펫 DB 연동 점검 중 발견 — 요구사항
  /// "즉시 DB에 업데이트하는 훅이 누락되어 있다면 추가").
  void equipItem(Equipment item) {
    final Equipment? current = equippedItems[item.type];
    if (current != null) {
      current.isEquipped = false;
    }

    item.isEquipped = true;
    equippedItems[item.type] = item;
    notifyListeners();
    saveEquipment();
  }

  void unequipItem(EquipType type) {
    final Equipment? current = equippedItems[type];
    if (current == null) {
      return;
    }

    current.isEquipped = false;
    equippedItems[type] = null;
    notifyListeners();
    saveEquipment();
  }

  /// [item]의 타입(장비/펫/캐릭터 무엇이든 [item.type] 하나로 판별)에 맞는
  /// 슬롯에 장착하거나, 이미 장착 중이면 해제한다 — ItemDetailDialog의
  /// 장착/해제 버튼이 타입별 분기 없이 이 메서드 하나만 호출하면 된다.
  void toggleEquip(Equipment item) {
    if (item.isEquipped) {
      unequipItem(item.type);
    } else {
      equipItem(item);
    }
  }

  /// [equipmentId] 아이템의 레벨을 1 올린다. 코인이 부족하거나, 아이템을
  /// 찾을 수 없거나, 이미 최고 레벨이면 아무것도 바꾸지 않고 false를 반환한다.
  bool levelUpItem(String equipmentId) {
    final int index = inventory.indexWhere((item) => item.id == equipmentId);
    if (index == -1) {
      return false;
    }

    final Equipment item = inventory[index];
    if (item.isMaxLevel) {
      return false;
    }
    if (!GameManager.instance.spendGold(item.levelUpCost)) {
      return false;
    }

    item.statMultiplier = item.nextLevelStatMultiplier;
    item.level++;
    notifyListeners();
    saveEquipment();
    return true;
  }

  /// Types the "자동 장착" safety net must never touch — pet/character
  /// collectibles are compared/equipped from their own tabs, not swept up
  /// by the gear auto-equip sweep.
  static const Set<EquipType> autoEquipExcludedTypes = {
    EquipType.pet,
    EquipType.character,
  };

  /// For every gear slot (excluding [autoEquipExcludedTypes]), equips the
  /// highest-`statMultiplier` item currently in the inventory if it's
  /// stronger than what's already equipped there.
  void autoEquipBestItems() {
    for (final EquipType type in EquipType.values) {
      if (autoEquipExcludedTypes.contains(type)) {
        continue;
      }

      final List<Equipment> candidates =
          inventory.where((item) => item.type == type).toList();
      if (candidates.isEmpty) {
        continue;
      }

      final Equipment best = candidates.reduce(
        (a, b) => b.statMultiplier > a.statMultiplier ? b : a,
      );

      final Equipment? current = equippedItems[type];
      final bool isUpgrade = current == null || best.statMultiplier > current.statMultiplier;
      if (isUpgrade && current?.id != best.id) {
        equipItem(best);
      }
    }
  }

  static const String _inventoryKey = 'equipment_inventory';

  /// 로컬(SharedPreferences)에 전체 인벤토리를 저장한 뒤, 보유 펫(`EquipType
  /// .pet`)만 골라 Supabase에도 백업한다([_syncPetsToRemote] 참고) — 펫이
  /// 아닌 장비만 바뀐 호출이어도 매번 함께 동기화한다. 개별 변경마다
  /// "이번에 펫이 바뀌었는지"를 따로 추적하는 것보다 훨씬 단순하고, 펫
  /// 개수가 많지 않아(수십 마리 수준) 매번 통째로 보내도 부담이 적다.
  Future<void> saveEquipment() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String inventoryJson = jsonEncode(
      inventory.map((item) => item.toJson()).toList(),
    );
    await prefs.setString(_inventoryKey, inventoryJson);
    debugPrint('Equipment saved: ${inventory.length} items');
    unawaited(_syncPetsToRemote());
  }

  /// 현재 보유 펫 전체와 장착 중인 펫 id를 Supabase에 백업한다 — 다른
  /// 백그라운드 동기화 메서드들과 같은 fire-and-forget 관례(실패해도
  /// 로컬 저장은 이미 끝났으므로 게임 진행을 막지 않는다).
  Future<void> _syncPetsToRemote() async {
    final List<Map<String, dynamic>> pets = inventory
        .where((item) => item.type == EquipType.pet)
        .map((item) => item.toJson())
        .toList();
    await SupabaseManager.instance.syncUserPets(pets);
    await SupabaseManager.instance.updateEquippedPetId(equippedItems[EquipType.pet]?.id);
  }

  // equippedItems isn't persisted separately — it's fully derivable from
  // inventory's `isEquipped`/`type` fields, so re-deriving it on load avoids
  // the two structures ever drifting out of sync.
  Future<void> loadEquipment() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? inventoryJson = prefs.getString(_inventoryKey);
    if (inventoryJson == null) {
      debugPrint('Equipment loaded: no saved data found under "$_inventoryKey"');
      // 이 기기에 저장된 적이 전혀 없다 — 재설치/새 기기일 수 있으니
      // Supabase에 예전에 백업해 둔 펫이 있는지 확인해 복구를 시도한다
      // (생성자의 _generateTestInventory가 이미 채워 둔 임시 테스트
      // 아이템은 건드리지 않고 그 위에 그대로 더한다).
      await _restorePetsFromRemote();
      return;
    }

    try {
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
    } catch (error) {
      debugPrint('[EquipmentManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
      return;
    }

    notifyListeners();
    debugPrint('Equipment loaded: ${inventory.length} items');
  }

  /// [loadEquipment]가 이 기기에 저장된 적이 전혀 없을 때만(신규 설치/
  /// 재설치) 호출 — Supabase `user_pets`/`profiles.equipped_pet_id`에
  /// 예전에 백업해 둔 펫이 있으면 [inventory]에 복구한다. 이미 로컬 저장
  /// 이력이 있는 정상적인 재실행에서는 절대 호출되지 않으므로, 원격
  /// 데이터가 뒤처져 있어도 방금 로컬에서 불러온 최신 상태를 덮어쓸
  /// 위험이 없다.
  Future<void> _restorePetsFromRemote() async {
    final List<Map<String, dynamic>> rows = await SupabaseManager.instance.fetchUserPets();
    if (rows.isEmpty) {
      return;
    }

    final List<Equipment> restoredPets = [];
    for (final Map<String, dynamic> row in rows) {
      try {
        final Map<String, dynamic>? data = row['data'] as Map<String, dynamic>?;
        if (data == null) {
          continue;
        }
        restoredPets.add(Equipment.fromJson(data));
      } catch (error) {
        debugPrint('[EquipmentManager] 원격 펫 복구 실패(id=${row['id']}): $error');
      }
    }
    if (restoredPets.isEmpty) {
      return;
    }

    final String? remoteEquippedId = await SupabaseManager.instance.fetchEquippedPetId();
    // [버그 방어] 원격이 가리키는 장착 펫 id가 방금 복구한 목록 중 어디에도
    // 없으면(예: 그 펫만 유실/불일치) 예외를 던지거나 잘못된 펫을 장착
    // 처리하지 않고, 조용히 미장착 상태로 남긴다.
    Equipment? equippedPet;
    if (remoteEquippedId != null) {
      for (final Equipment pet in restoredPets) {
        if (pet.id == remoteEquippedId) {
          equippedPet = pet;
          break;
        }
      }
    }
    for (final Equipment pet in restoredPets) {
      pet.isEquipped = identical(pet, equippedPet);
    }

    inventory.addAll(restoredPets);
    equippedItems[EquipType.pet] = equippedPet;

    notifyListeners();
    debugPrint('Equipment loaded: ${restoredPets.length} pets restored from Supabase');
    // 복구된 펫을 로컬에도 즉시 반영해 둔다 — 다음 실행부터는 이
    // 복구 경로를 다시 타지 않고 로컬 저장분을 바로 불러온다.
    await saveEquipment();
  }

  /// [서약(Oath) 스탯 보너스 연결 지점 — 아직 미연결, 스켈레톤 설명]
  ///
  /// [AffectionManager.statMultiplierBonus]가 서약한 캐릭터에게 10%
  /// 배율 보너스를 이미 계산해 주지만, 이 메서드는 아직 그 값을 읽지
  /// 않는다 — 장비 전체(무기/방어구/캐릭터...)의 `statMultiplier`를
  /// 단순 합산하는 이 공식은 프로젝트 전투 밸런스의 핵심이라, 검증
  /// 없이 여기서 바로 곱해 넣는 건 리스크가 크다고 판단해 일부러
  /// 손대지 않았다. 실제로 연결하려면:
  ///
  /// ```dart
  /// double getTotalEquipmentMultiplier() {
  ///   double sum = 0.0;
  ///   for (final Equipment item in equippedItems.values) {
  ///     double itemMultiplier = item.statMultiplier;
  ///     if (item.type == EquipType.character) {
  ///       // 캐릭터 슬롯에만 서약 보너스를 곱한다 — gradeBadgeLabel이
  ///       // AffectionManager가 쓰는 characterId와 동일한 키다.
  ///       itemMultiplier *= AffectionManager.instance
  ///           .statMultiplierBonus(item.gradeBadgeLabel);
  ///     }
  ///     sum += itemMultiplier;
  ///   }
  ///   return sum;
  /// }
  /// ```
  ///
  /// 이렇게 캐릭터 슬롯에만 곱하도록 분기해야 무기/방어구 같은 다른
  /// 슬롯까지 실수로 보너스를 받는 걸 막을 수 있다. 적용하기 전에
  /// 기존 전투 밸런스 테스트(스테이지 클리어 시간 등)로 영향을 확인할
  /// 것.
  double getTotalEquipmentMultiplier() {
    return equippedItems.values
        .whereType<Equipment>()
        .fold(0.0, (double sum, Equipment item) => sum + item.statMultiplier);
  }

  /// 장착된 아이템 하나의 mainStat + subStats 중 [type]과 일치하는 값을
  /// 전부 더한다 — [EquipmentFactory]로 생성된(=subStats가 실제로 채워진)
  /// 신규 아이템의 옵션을 게임 연산에 반영하는 공용 통로.
  double _sumStatValue(Equipment item, EquipmentStatType type) {
    double total = 0;
    final EquipmentOption? mainStat = item.mainStat;
    if (mainStat != null && mainStat.type == type) {
      total += mainStat.value;
    }
    for (final EquipmentOption option in item.subStats) {
      if (option.type == type) {
        total += option.value;
      }
    }
    return total;
  }

  /// 장착된 모든 아이템에 걸쳐 [type] 옵션 값을 합산한다 — attack/
  /// attackSpeed/criticalRate/criticalDamage처럼 레거시 전용 필드가 없는
  /// 스탯은 이 메서드 하나로 충분하다(GameManager가 직접 호출).
  double getTotalSubStatBonus(EquipmentStatType type) => equippedItems.values
      .whereType<Equipment>()
      .fold(0.0, (double sum, Equipment item) => sum + _sumStatValue(item, type));

  // 아래 4개는 defenseOption 등 레거시 필드 기반으로 이미 저장된 예전
  // 아이템(subStats가 비어 있음)과, EquipmentFactory로 새로 생성돼
  // subStats/mainStat에 값이 들어간 신규 아이템 양쪽을 모두 더한다 —
  // 두 소스는 아이템 하나당 한쪽만 채워지므로 이중 합산될 일이 없다.
  double getTotalDefenseBonus() => equippedItems.values
      .whereType<Equipment>()
      .fold(
        0.0,
        (double sum, Equipment item) =>
            sum + item.defenseOption + _sumStatValue(item, EquipmentStatType.defense),
      );

  double getTotalDefenseRateBonus() => equippedItems.values
      .whereType<Equipment>()
      .fold(
        0.0,
        (double sum, Equipment item) =>
            sum + item.defenseRateOption + _sumStatValue(item, EquipmentStatType.defenseRate),
      );

  double getTotalEvasionRateBonus() => equippedItems.values
      .whereType<Equipment>()
      .fold(
        0.0,
        (double sum, Equipment item) =>
            sum + item.evasionRateOption + _sumStatValue(item, EquipmentStatType.evasionRate),
      );

  double getTotalCritDefenseRateBonus() => equippedItems.values
      .whereType<Equipment>()
      .fold(
        0.0,
        (double sum, Equipment item) =>
            sum +
            item.critDefenseRateOption +
            _sumStatValue(item, EquipmentStatType.critDefenseRate),
      );

  /// "순수 장비" 부위 — pet/character/relic은 각자 전용 뽑기(shop_screen.dart의
  /// [generateLootOfType] 호출부)로만 나와야 하므로 여기엔 포함하지 않는다.
  /// [generateGuaranteedLoot]/[generateRandomLoot]의 기본 타입 풀이자, 상점
  /// "장비" 박스·필드 드랍·장비 던전 보스가 전부 이 풀을 공유한다.
  static const List<EquipType> _gearTypes = [
    EquipType.weapon,
    EquipType.helmet,
    EquipType.armor,
    EquipType.shield,
    EquipType.boots,
    EquipType.ring,
    EquipType.glove,
    EquipType.belt,
  ];

  Equipment generateRandomLoot() => generateGuaranteedLoot(ItemGrade.values);

  /// Draws [count] random items (e.g. the coin gacha's "11회 연속 뽑기") and
  /// returns every item drawn, so the UI can show the full result list
  /// instead of only the best one. 이 메서드는 상점 장비 가챠 버튼
  /// (`shop_screen.dart`)의 유일한 호출부라 — 매 개별 뽑기마다
  /// [PityManager]의 장비 천장 카운터를 소비하고, 천장에 걸리면
  /// [_generatePityEquipmentLoot]로 확정 최고 등급을 지급한다.
  /// [generateRandomLoot]/[generateGuaranteedLoot] 자체는 던전 보스 드랍/
  /// 필드 드랍 등 가챠가 아닌 다른 경로도 함께 쓰므로 건드리지 않는다
  /// ([PityManager] 클래스 문서 참고).
  List<Equipment> drawMultipleGacha(int count) {
    return List.generate(count, (_) {
      AchievementManager.instance.recordGachaPull();
      final bool hitPity = PityManager.instance.rollAndConsumePity(GachaPityCategory.equipment);
      return hitPity ? _generatePityEquipmentLoot() : generateRandomLoot();
    });
  }

  /// 장비 가챠 천장(확정) 지급 — [_gearTypes] 중 실제로 최고 등급 컨텐츠가
  /// 있는 타입만 후보로 놓고 그 최고 등급을 확정 생성한다. 일반
  /// [generateGuaranteedLoot]처럼 타입을 먼저 무작위로 고른 뒤 등급을
  /// 맞추면, 하필 그 타입에 최고 등급 컨텐츠가 없을 때
  /// [_pickAvailableGrade]의 폴백이 낮은 등급으로 조용히 떨어뜨려 천장
  /// 보장이 깨질 수 있어 — 타입과 등급을 함께, 이 함수 안에서만 직접
  /// 계산한다.
  Equipment _generatePityEquipmentLoot() {
    ItemGrade topGrade = ItemGrade.n;
    for (final ItemGrade grade in ItemGrade.values) {
      final bool anyTypeHasContent =
          _gearTypes.any((type) => ItemPoolConfig.maxCount(type, grade) > 0);
      if (anyTypeHasContent) {
        // ItemGrade.values는 낮은→높은 등급 순이라, 끝까지 훑으면 실제
        // 컨텐츠가 있는 가장 높은 등급이 남는다.
        topGrade = grade;
      }
    }
    final List<EquipType> eligibleTypes =
        _gearTypes.where((type) => ItemPoolConfig.maxCount(type, topGrade) > 0).toList();
    final EquipType type = eligibleTypes.isNotEmpty
        ? eligibleTypes[_random.nextInt(eligibleTypes.length)]
        : _gearTypes[_random.nextInt(_gearTypes.length)];

    final Equipment loot = EquipmentFactory.generate(
      type: type,
      grade: topGrade,
      id: _uuid.v4(),
      name: '${topGrade.displayName} ${type.displayName}',
      subId: _rollSubId(type, topGrade, _random),
      statMultiplier: _rollStatMultiplier(topGrade),
    );

    inventory.add(loot);
    notifyListeners();
    return loot;
  }

  /// Rolls loot whose grade is restricted to [allowedGrades] — used by
  /// content (e.g. the equipment dungeon boss) that guarantees a high-tier
  /// drop instead of the full random spread. [allowedTypes] defaults to
  /// [_gearTypes] so every caller that doesn't explicitly ask for a specific
  /// category (pet/character/relic — see [generateLootOfType]) only ever
  /// gets pure gear back.
  Equipment generateGuaranteedLoot(
    List<ItemGrade> allowedGrades, {
    List<EquipType> allowedTypes = _gearTypes,
  }) {
    final EquipType type = allowedTypes[_random.nextInt(allowedTypes.length)];
    final ItemGrade grade = _pickAvailableGrade(type, allowedGrades, _random);

    final Equipment loot = EquipmentFactory.generate(
      type: type,
      grade: grade,
      id: _uuid.v4(),
      name: '${grade.displayName} ${type.displayName}',
      subId: _rollSubId(type, grade, _random),
      statMultiplier: _rollStatMultiplier(grade),
    );

    inventory.add(loot);
    notifyListeners();
    return loot;
  }

  /// Rolls loot restricted to a single [type] (e.g. `EquipType.pet` for the
  /// shop's pet gacha) — grade is still random within [allowedGrades],
  /// unless a pity category applies for [type] (character/pet) and this
  /// roll hits the threshold ([PityManager]), in which case the highest
  /// grade actually available for [type] is force-granted instead. Every
  /// current caller of this method is a real shop gacha button
  /// (`shop_screen.dart`) — no other code path uses it — so it's safe to
  /// always consult [PityManager] here without an opt-in flag.
  Equipment generateLootOfType(
    EquipType type, {
    List<ItemGrade> allowedGrades = ItemGrade.values,
  }) {
    AchievementManager.instance.recordGachaPull();
    final GachaPityCategory? pityCategory = switch (type) {
      EquipType.character => GachaPityCategory.character,
      EquipType.pet => GachaPityCategory.pet,
      _ => null,
    };
    final bool hitPity =
        pityCategory != null && PityManager.instance.rollAndConsumePity(pityCategory);
    final ItemGrade grade = hitPity
        ? _topAvailableGrade(type, allowedGrades)
        : _pickAvailableGrade(type, allowedGrades, _random);

    // 펫 전용 특수 스탯(골드 획득/드랍률/보스 데미지 등) — DB
    // (pet_stat_metadata) 기반 등급별 값 범위에서 굴린다. 펫이 아닌
    // 타입은 항상 빈 맵.
    final Map<String, double> specialStats = type == EquipType.pet
        ? PetStatMetadataManager.instance.rollSpecialStats(grade)
        : const {};

    final Equipment loot = EquipmentFactory.generate(
      type: type,
      grade: grade,
      id: _uuid.v4(),
      name: '${grade.displayName} ${type.displayName}',
      subId: _rollSubId(type, grade, _random),
      statMultiplier: _rollStatMultiplier(grade),
      specialStats: specialStats,
    );

    inventory.add(loot);
    notifyListeners();
    return loot;
  }

  /// 프롤로그 클리어 시 1회 지급되는 초반 동료 — N1은 항상 확정 지급하고
  /// 곧바로 장착까지 해준다(에스텔은 [prologueStory]의 연출과 맞춰 R등급
  /// 후보 중 하나로 지급되되, 장착은 하지 않고 인벤토리에만 추가된다).
  /// [StoryManager.markPrologueCleared]와 짝을 이루는 1회성 호출이라
  /// 호출부([MyApp])가 직접 중복 호출 여부를 관리한다.
  List<Equipment> grantStarterCharacters() {
    final Equipment starter = EquipmentFactory.generate(
      type: EquipType.character,
      grade: ItemGrade.n,
      id: _uuid.v4(),
      name: '${ItemGrade.n.displayName} ${EquipType.character.displayName}',
      subId: 1,
      statMultiplier: _rollStatMultiplier(ItemGrade.n),
    );
    inventory.add(starter);
    equipItem(starter);

    final ItemGrade companionGrade = _pickAvailableGrade(
      EquipType.character,
      const [ItemGrade.n, ItemGrade.r],
      _random,
    );
    final Equipment companion = EquipmentFactory.generate(
      type: EquipType.character,
      grade: companionGrade,
      id: _uuid.v4(),
      name: '${companionGrade.displayName} ${EquipType.character.displayName}',
      subId: _rollSubId(EquipType.character, companionGrade, _random),
      statMultiplier: _rollStatMultiplier(companionGrade),
    );
    inventory.add(companion);

    notifyListeners();
    saveEquipment();
    return [starter, companion];
  }

  /// 시즌1 메인 스토리 챕터 1 완료 보상 — 확정 N1 지급. [grantStarterCharacters]
  /// (프롤로그 보상)와는 별개의 독립적인 지급 계기라, 프롤로그에서 이미 N1을
  /// 받았어도 중복 보유가 정상이다(장착 캐릭터가 아직 없을 때만 자동 장착).
  /// [MainStoryManager]가 챕터 2 스토리 종료 직후("챕터 1을 막 완료했다"는
  /// 뜻) 이 메서드를 호출한다.
  Equipment grantChapter1Character() {
    final Equipment reward = EquipmentFactory.generate(
      type: EquipType.character,
      grade: ItemGrade.n,
      id: _uuid.v4(),
      name: '${ItemGrade.n.displayName} ${EquipType.character.displayName}',
      subId: 1,
      statMultiplier: _rollStatMultiplier(ItemGrade.n),
    );
    inventory.add(reward);
    if (equippedItems[EquipType.character] == null) {
      equipItem(reward);
    }

    notifyListeners();
    saveEquipment();
    return reward;
  }

  /// 시즌1 메인 스토리 챕터 2 완료 보상 — R등급 캐릭터 1명을 무작위 넘버링으로
  /// 지급한다(이미 메인 캐릭터가 장착돼 있을 시점이라 자동 장착은 하지
  /// 않는다). [MainStoryManager]가 챕터 3 스토리 종료 직후 이 메서드를 호출한다.
  Equipment grantChapter2Character() {
    final int subId = _rollSubId(EquipType.character, ItemGrade.r, _random);
    final Equipment reward = EquipmentFactory.generate(
      type: EquipType.character,
      grade: ItemGrade.r,
      id: _uuid.v4(),
      name: '${ItemGrade.r.displayName} ${EquipType.character.displayName}',
      subId: subId,
      statMultiplier: _rollStatMultiplier(ItemGrade.r),
    );
    inventory.add(reward);

    notifyListeners();
    saveEquipment();
    return reward;
  }

  /// Dust granted per grade when disassembling gear. Swappable at runtime
  /// once these rates move to a DB — [disassembleItems] only ever reads
  /// through this map.
  Map<ItemGrade, int> dustRewardByGrade = const {
    ItemGrade.n: 1,
    ItemGrade.r: 5,
    ItemGrade.sr: 10,
    ItemGrade.ssr: 20,
    ItemGrade.sssr: 50,
    ItemGrade.ur: 100,
    ItemGrade.lr: 200,
  };

  /// Pawprint granted per grade when disassembling *pet* gear — same shape
  /// as [dustRewardByGrade], just a separate pet-only currency.
  Map<ItemGrade, int> pawprintRewardByGrade = const {
    ItemGrade.n: 1,
    ItemGrade.r: 5,
    ItemGrade.sr: 10,
    ItemGrade.ssr: 20,
    ItemGrade.sssr: 50,
    ItemGrade.ur: 100,
    ItemGrade.lr: 200,
  };

  /// Removes the given (non-equipped) equipment ids from [inventory] and
  /// grants their combined reward via ConsumableManager: 가루 for regular
  /// gear, 발바닥(pawprint) for `EquipType.pet` items.
  ({int dust, int pawprints}) disassembleItems(List<String> equipmentIds) {
    int totalDust = 0;
    int totalPawprints = 0;
    inventory.removeWhere((item) {
      if (item.isEquipped || !equipmentIds.contains(item.id)) {
        return false;
      }
      if (item.type == EquipType.pet) {
        totalPawprints += pawprintRewardByGrade[item.grade] ?? 0;
      } else {
        totalDust += dustRewardByGrade[item.grade] ?? 0;
      }
      return true;
    });

    if (totalDust > 0) {
      ConsumableManager.instance.addItem(ConsumableType.dust, totalDust);
    }
    if (totalPawprints > 0) {
      ConsumableManager.instance.addItem(ConsumableType.pawprint, totalPawprints);
    }
    notifyListeners();
    return (dust: totalDust, pawprints: totalPawprints);
  }

  /// [currentStar]에서 한 단계 진화하는 데 필요한 만렙(Lv.50) 동일 아이템
  /// 개수 — ★0→1/1→2/2→3은 3개, ★3→4는 4개, ★4→5는 5개.
  static int materialCountForStarUp(int currentStar) {
    switch (currentStar) {
      case 0:
      case 1:
      case 2:
        return 3;
      case 3:
        return 4;
      default:
        return 5;
    }
  }

  /// 만렙(Lv.50) 아이템을 (type, grade, subId, star)로 묶는다 — 이 조건을
  /// 하나라도 벗어나면 애초에 "동일한 아이템"으로 취급하지 않는다(별 진화
  /// 합성 후보에서 제외). 장착 중인 아이템도 후보에 포함된다 —
  /// [synthesizeGroup]이 장착 중이던 아이템이 재료로 소모되면 결과물을
  /// 자동으로 그 슬롯에 다시 장착해 주므로 여기서 미리 걸러낼 필요가 없다.
  Map<String, List<Equipment>> groupSynthesizableEquipment() {
    final Map<String, List<Equipment>> groups = {};
    for (final Equipment item in inventory) {
      if (!item.isMaxLevel) {
        continue;
      }
      final String key = '${item.type.name}_${item.grade.name}_${item.subId}_${item.star}';
      groups.putIfAbsent(key, () => []).add(item);
    }
    return groups;
  }

  /// (type, grade, subId, star)가 모두 일치하는 만렙 아이템을
  /// [materialCountForStarUp]개 소모해 별이 1 오르고 레벨이 0으로
  /// 초기화된 아이템 1개를 만든다. 이미 최고 별(★5)이거나 재료가 부족하면
  /// null.
  ///
  /// 소모되는 재료 중 장착 중인 아이템이 하나 있었다면(캐릭터/장비/펫
  /// 슬롯 전부 동일하게 적용) — 그 아이템은 곧 인벤토리에서 사라지므로,
  /// 새로 만들어진 상위 아이템을 같은 슬롯에 즉시 자동 장착한다
  /// ([equipItem] 참고 — GameManager.attackPower 등 스탯 게터가 매번
  /// equippedItems를 새로 읽으므로 전투 화면에도 별도 배선 없이 바로
  /// 반영되고, EquipmentManager를 구독 중인 UI(SynthesisView/StatPanel
  /// 등)도 notifyListeners() 한 번으로 즉시 리빌드된다).
  Equipment? synthesizeGroup(EquipType type, ItemGrade grade, int subId, int star) {
    if (star >= Equipment.maxStar) {
      return null;
    }

    final int required = materialCountForStarUp(star);
    final List<Equipment> candidates = inventory
        .where(
          (item) =>
              item.isMaxLevel &&
              item.type == type &&
              item.grade == grade &&
              item.subId == subId &&
              item.star == star,
        )
        .toList();
    if (candidates.length < required) {
      return null;
    }

    // 미장착 사본을 먼저 소모하고, 그것만으로 모자랄 때만 장착 중인
    // 사본까지 손댄다 — 여분이 충분한데도 굳이 장착 슬롯을 건드릴 필요는
    // 없다(같은 타입이라 장착 중인 사본은 최대 1개뿐이라 순서만 뒤로
    // 미루면 충분하다).
    final List<Equipment> consumed = [
      ...candidates.where((item) => !item.isEquipped),
      ...candidates.where((item) => item.isEquipped),
    ].take(required).toList();
    final bool wasEquipped = consumed.any((item) => item.isEquipped);

    for (final Equipment item in consumed) {
      inventory.remove(item);
    }

    final Equipment result = EquipmentFactory.generate(
      type: type,
      grade: grade,
      id: _uuid.v4(),
      name: '${grade.displayName} ${type.displayName}',
      subId: subId,
      statMultiplier: _rollStatMultiplier(grade),
      star: star + 1,
    );
    inventory.add(result);

    if (wasEquipped) {
      // equipItem()이 기존 장착 해제 + 새 아이템 장착 + notifyListeners()를
      // 전부 처리한다 — 아래에서 별도로 notifyListeners()를 부르지 않는다.
      equipItem(result);
    } else {
      notifyListeners();
    }
    saveEquipment();
    return result;
  }

  /// 진화 가능한 (type, grade, subId, star) 묶음을 더 이상 없을 때까지
  /// 반복 진화시킨다 — 재료가 넉넉하면 같은 묶음이 연속으로 여러 번
  /// 진화할 수 있다. 만들어진 결과물은 레벨 0에서 시작하므로 그 자리에서
  /// 곧바로 다시 재료가 되지는 않는다.
  List<Equipment> autoSynthesizeAll() {
    final List<Equipment> produced = [];

    while (true) {
      final Map<String, List<Equipment>> groups = groupSynthesizableEquipment();
      Equipment? result;

      for (final List<Equipment> group in groups.values) {
        final Equipment sample = group.first;
        final int required = materialCountForStarUp(sample.star);
        if (sample.star >= Equipment.maxStar || group.length < required) {
          continue;
        }
        result = synthesizeGroup(sample.type, sample.grade, sample.subId, sample.star);
        if (result != null) {
          break;
        }
      }

      if (result == null) {
        break;
      }
      produced.add(result);
    }

    return produced;
  }

  double _rollStatMultiplier(ItemGrade grade) {
    final (double min, double max) range = switch (grade) {
      ItemGrade.n => (0.05, 0.10),
      ItemGrade.r => (0.10, 0.25),
      ItemGrade.sr => (0.25, 0.50),
      ItemGrade.ssr => (0.50, 1.00),
      ItemGrade.sssr => (1.00, 1.50),
      ItemGrade.ur => (1.50, 3.00),
      ItemGrade.lr => (3.00, 5.00),
    };

    final double value =
        range.$1 + _random.nextDouble() * (range.$2 - range.$1);
    return double.parse(value.toStringAsFixed(2));
  }

  /// [allowedGrades] 중 [type]에 실제 콘텐츠가 있는(=[ItemPoolConfig.maxCount] >
  /// 0인) 등급만 후보로 남겨 그중 하나를 무작위로 뽑는다. 그중 하나도 없으면
  /// (예: 프리미엄 캐릭터 소환처럼 상위 등급만 허용했는데 그 등급들엔 아직
  /// 캐릭터 아트가 하나도 없는 경우) 등급 제한 자체를 풀고 이 타입에
  /// 콘텐츠가 있는 가장 낮은 등급으로 안전하게 대체한다 — 이래도 하나도
  /// 없으면(타입 자체에 설정이 전혀 없으면) 마지막 방어선으로 N을 반환한다.
  ItemGrade _pickAvailableGrade(EquipType type, List<ItemGrade> allowedGrades, Random random) {
    final List<ItemGrade> valid =
        allowedGrades.where((grade) => ItemPoolConfig.maxCount(type, grade) > 0).toList();
    if (valid.isNotEmpty) {
      return valid[random.nextInt(valid.length)];
    }

    final List<ItemGrade> anyValid =
        ItemGrade.values.where((grade) => ItemPoolConfig.maxCount(type, grade) > 0).toList();
    if (anyValid.isNotEmpty) {
      return anyValid.first;
    }
    return ItemGrade.n;
  }

  /// [_pickAvailableGrade]와 같은 후보 계산(=[allowedGrades] 중 [type]에
  /// 실제 콘텐츠가 있는 등급들, 없으면 [type]에 콘텐츠가 있는 아무 등급)을
  /// 쓰되, 무작위 대신 그중 "가장 높은" 등급을 돌려준다 — 가챠 천장
  /// ([PityManager])이 걸렸을 때 이 타입에서 실제로 뽑을 수 있는 최고
  /// 등급을 확정 지급하는 용도. `ItemGrade.values`가 낮은→높은 순으로
  /// 선언돼 있어, 필터링된 리스트의 마지막 원소가 항상 최고 등급이다.
  ItemGrade _topAvailableGrade(EquipType type, List<ItemGrade> allowedGrades) {
    final List<ItemGrade> valid =
        allowedGrades.where((grade) => ItemPoolConfig.maxCount(type, grade) > 0).toList();
    if (valid.isNotEmpty) {
      return valid.last;
    }

    final List<ItemGrade> anyValid =
        ItemGrade.values.where((grade) => ItemPoolConfig.maxCount(type, grade) > 0).toList();
    return anyValid.isNotEmpty ? anyValid.last : ItemGrade.n;
  }

  /// [type] + [grade] 조합에 실제로 존재하는 개수([ItemPoolConfig.maxCount])
  /// 범위 안에서 하나를 무작위로 뽑는다 — 모든 생성 경로(가챠/필드 드랍/
  /// 테스트 인벤토리)가 이걸 거친다. 개수가 0이면(설정에 없는 조합) 안전하게
  /// 1을 반환한다.
  int _rollSubId(EquipType type, ItemGrade grade, Random random) {
    final int maxCount = ItemPoolConfig.maxCount(type, grade);
    return maxCount > 0 ? random.nextInt(maxCount) + 1 : 1;
  }

  void _generateTestInventory() {
    final Random random = Random();
    final List<EquipType> types = EquipType.values;

    for (int i = 0; i < 10; i++) {
      final EquipType type = types[random.nextInt(types.length)];
      final ItemGrade grade = _pickAvailableGrade(type, ItemGrade.values, random);
      final double statMultiplier =
          double.parse((1.0 + grade.index * 0.5 + random.nextDouble()).toStringAsFixed(2));

      inventory.add(
        EquipmentFactory.generate(
          type: type,
          grade: grade,
          id: _uuid.v4(),
          name: '${grade.displayName} ${type.displayName}',
          subId: _rollSubId(type, grade, random),
          statMultiplier: statMultiplier,
        ),
      );
    }
  }
}
