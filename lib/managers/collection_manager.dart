import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/collection_model.dart';
import '../models/equipment.dart';
import 'equipment_manager.dart';
import 'game_manager.dart';
import 'supabase_manager.dart';

/// 세트 수집(컬렉션) 정의와 진행 상태를 관장하는 싱글턴.
///
/// 정의(title/requiredItems/rewardStat)는 Supabase `master_collections`
/// 테이블에서 온다([SupabaseManager.fetchMasterCollections]) — 앱 재배포
/// 없이 세트를 추가/삭제(비활성)/보상 조정을 할 수 있다. 진행 상태
/// (isCompleted)만 플레이어별 로컬 저장값이다.
class CollectionManager extends ChangeNotifier {
  CollectionManager._internal();

  static final CollectionManager instance = CollectionManager._internal();

  List<CollectionModel> collections = [];

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

  /// 정의 자체(=[collections])의 로컬 캐시 — Supabase가 실패했을 때(오프라인
  /// 등) 지난번에 받아 둔 세트 목록으로 폴백한다. 진행 상태([_saveKey])와
  /// 별개의 키다 — 정의는 서버가 언제든 바꿀 수 있는 데이터, 진행 상태는
  /// 순수 로컬 플레이어 데이터라 저장 주기와 무효화 조건이 다르다.
  static const String _definitionCacheKey = 'collection_manager_definitions_cache';

  /// 완료 여부(isCompleted)만 저장한다 — 정의는 매번 [loadData]가 서버/캐시
  /// 에서 다시 받아오므로 여기 포함할 필요가 없다.
  Future<void> saveData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> completedIds = collections
        .where((collection) => collection.isCompleted)
        .map((collection) => collection.id)
        .toList();
    await prefs.setString(_saveKey, jsonEncode({'completedIds': completedIds}));
  }

  /// 1) 세트 정의를 로컬 캐시로 먼저 채우고(있다면), 2) Supabase
  /// `master_collections`에서 최신 정의를 받아와 덮어쓴다(실패하거나 빈
  /// 결과가 오면 — 네트워크 실패와 "정말로 활성 세트가 없음"을 구분할 수
  /// 없으므로 — 캐시가 이미 있는 한 그 캐시를 유지한다). 3) 마지막으로
  /// 로컬에 저장된 완료 여부를 그 정의 목록 위에 얹는다.
  Future<void> loadData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final String? cachedDefinitions = prefs.getString(_definitionCacheKey);
    if (cachedDefinitions != null) {
      try {
        final List<dynamic> decoded = jsonDecode(cachedDefinitions) as List<dynamic>;
        collections = decoded
            .map((entry) => CollectionModel.fromJson(entry as Map<String, dynamic>))
            .toList();
      } catch (error) {
        debugPrint('[CollectionManager] 로컬 정의 캐시가 손상되어 건너뜁니다: $error');
      }
    }

    final List<Map<String, dynamic>> rows = await SupabaseManager.instance.fetchMasterCollections();
    if (rows.isNotEmpty) {
      collections = parseRows(rows);
      await prefs.setString(
        _definitionCacheKey,
        jsonEncode(collections.map((collection) => collection.toJson()).toList()),
      );
    } else if (collections.isEmpty) {
      debugPrint(
        '[CollectionManager] master_collections 조회 결과가 비어 있습니다 '
        '(네트워크 실패 또는 실제로 활성 세트가 없음) — 컬렉션이 빈 상태로 시작됩니다.',
      );
    }

    final String? savedProgress = prefs.getString(_saveKey);
    if (savedProgress != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(savedProgress) as Map<String, dynamic>;
        final List<dynamic> completedIds = data['completedIds'] as List<dynamic>? ?? [];
        for (final CollectionModel collection in collections) {
          if (completedIds.contains(collection.id)) {
            collection.isCompleted = true;
          }
        }
      } catch (error) {
        debugPrint('[CollectionManager] 로컬 진행 상태 데이터가 손상되어 건너뜁니다: $error');
      }
    }
    notifyListeners();
  }

  /// Supabase 행 목록을 [CollectionModel] 목록으로 파싱한다 — 순수 함수라
  /// 네트워크 없이 단위 테스트할 수 있다. `required_items`/`reward_stat`
  /// jsonb 컬럼은 [RequiredCollectionItem]/[CollectionRewardStat]의 기존
  /// `toJson`/`fromJson`과 정확히 같은 키(type/grade/subId/requiredLevel/
  /// count, type/value)를 쓰도록 설계했다 — 그 모델들의 `fromJson`을 그대로
  /// 재사용해 새로운 파싱 로직을 따로 만들지 않는다. 행 하나가 깨져 있어도
  /// (필수 컬럼 누락, enum 이름 오타 등) 그 행만 건너뛴다 — 세트 하나의
  /// 오타 때문에 전체 컬렉션 목록이 깨지면 안 되기 때문이다.
  @visibleForTesting
  static List<CollectionModel> parseRows(List<Map<String, dynamic>> rows) {
    final List<CollectionModel> result = [];
    for (final Map<String, dynamic> row in rows) {
      try {
        final List<dynamic> requiredItemsRaw = row['required_items'] as List<dynamic>;
        result.add(
          CollectionModel(
            id: row['id'] as String,
            category: CollectionCategory.values.byName(row['category'] as String),
            title: row['title'] as String,
            requiredItems: requiredItemsRaw
                .map(
                  (entry) => RequiredCollectionItem.fromJson(entry as Map<String, dynamic>),
                )
                .toList(),
            rewardStat: CollectionRewardStat.fromJson(row['reward_stat'] as Map<String, dynamic>),
          ),
        );
      } catch (error) {
        debugPrint('[CollectionManager] master_collections 행 파싱 실패(id=${row['id']}): $error');
      }
    }
    return result;
  }
}
