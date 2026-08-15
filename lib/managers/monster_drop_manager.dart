import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/consumable_item_model.dart';
import '../models/equipment.dart';
import '../models/monster_drop_model.dart';
import 'consumable_manager.dart';
import 'equipment_manager.dart';
import 'supabase_manager.dart';

/// 몬스터 처치 드랍 테이블(`monster_drop_table`)을 관장하는 싱글턴 —
/// [PotionManager]와 같은 관례를 따른다(로컬 캐시 우선, Supabase는 부가적인
/// 백업/동기화 계층). 온라인 사냥([rollDropsForKill])과 오프라인 방치 보상
/// ([expectedDropsForKills])이 같은 테이블/같은 확률 공식을 공유해서, 두
/// 경로의 드랍률이 서로 어긋나지 않는다.
class MonsterDropTableManager {
  MonsterDropTableManager._internal();

  static final MonsterDropTableManager instance = MonsterDropTableManager._internal();

  final Random _random = Random();

  List<MonsterDropEntry> _table = const [];
  List<MonsterDropEntry> get table => _table;

  /// 단위 테스트 전용 — 실제 드랍 테이블을 네트워크 없이 직접 주입한다
  /// ([PotionManager.debugSeedForTest]와 같은 관례).
  @visibleForTesting
  void debugSeedForTest(List<MonsterDropEntry> table) {
    _table = table;
  }

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 채운 뒤 원격
  /// 테이블을 받아와 갱신을 시도한다.
  Future<void> loadData() async {
    await _loadLocal();

    final List<Map<String, dynamic>> rows = await SupabaseManager.instance.fetchMonsterDropTable();
    if (rows.isEmpty) {
      debugPrint(
        '[MonsterDropTableManager] 드랍 테이블이 비어 있습니다(monster_drop_table 테이블/RLS 정책을 확인하세요). '
        '기존 캐시(${_table.length}건)를 유지합니다.',
      );
    } else {
      final List<MonsterDropEntry> parsed = [];
      for (final Map<String, dynamic> row in rows) {
        try {
          parsed.add(MonsterDropEntry.fromJson(row));
        } catch (error) {
          debugPrint('[MonsterDropTableManager] 드랍 테이블 행 파싱 실패(id=${row['id']}): $error');
        }
      }
      if (parsed.isNotEmpty) {
        _table = parsed;
      } else {
        debugPrint('[MonsterDropTableManager] 파싱 가능한 드랍 항목이 하나도 없습니다 — 컬럼명/타입을 확인하세요.');
      }
    }

    await _saveLocal();
  }

  /// 실제 판정 확률 = `base_chance * (1 + itemDropRate)`, [0,1] 클램프.
  double _effectiveChance(MonsterDropEntry entry, double itemDropRate) =>
      (entry.baseChance * (1 + itemDropRate)).clamp(0.0, 1.0);

  /// 챕터에 맞는 장비 등급 풀 — 5챕터마다 한 등급씩 열린다(N→R→SR→SSR→
  /// SSSR→UR→LR). 정확한 밸런스 데이터가 없어 임의로 정한 값이니, 기획
  /// 수치가 정해지면 이 계산식만 바꾸면 된다. 장비 던전 보스가
  /// `generateGuaranteedLoot(const [ItemGrade.ssr, ItemGrade.sssr])`처럼
  /// 항상 고정 등급을 주는 것과 달리, 여기는 챕터 진행도에 따라 점점
  /// 넓어지는 풀이다.
  static List<ItemGrade> equipmentGradesForChapter(int chapter) {
    final int maxIndex = ((chapter - 1) ~/ 5).clamp(0, ItemGrade.values.length - 1);
    return ItemGrade.values.sublist(0, maxIndex + 1);
  }

  /// 몬스터 1마리를 처치할 때마다 호출 — 테이블의 각 항목을 독립적으로
  /// 굴려서, 당첨된 항목은 그 자리에서 곧장 인벤토리에 지급한다
  /// (equipment는 [EquipmentManager], consumable은 [ConsumableManager]).
  void rollDropsForKill({required int chapter, required double itemDropRate}) {
    for (final MonsterDropEntry entry in _table) {
      if (_random.nextDouble() >= _effectiveChance(entry, itemDropRate)) {
        continue;
      }
      switch (entry.itemType) {
        case MonsterDropItemType.equipment:
          EquipmentManager.instance.generateGuaranteedLoot(equipmentGradesForChapter(chapter));
        case MonsterDropItemType.consumable:
          final ConsumableType? type = entry.consumableType;
          if (type != null) {
            ConsumableManager.instance.addItem(type, 1);
          }
      }
    }
  }

  /// 오프라인 방치 보상 계산용 — 실제로 아이템을 지급하지 않고,
  /// [killCount]번의 처치 동안 기대되는 드랍 수량만 계산해서 돌려준다.
  /// 항목별 기댓값(`effectiveChance * killCount`)을 그대로 반복
  /// 시뮬레이션(수만 번 굴리기)하는 대신, floor는 항상 보장하고 소수부는
  /// 그 비율만큼의 확률로 하나 더 얹는 방식으로 근사한다(예: 기댓값
  /// 2.7이면 항상 2개 + 70% 확률로 1개 더) — 결과가 통계적으로 편향되지
  /// 않으면서도 O(테이블 크기)로 즉시 계산된다.
  ({int equipmentCount, Map<ConsumableType, int> consumables}) expectedDropsForKills({
    required int killCount,
    required int chapter,
    required double itemDropRate,
  }) {
    if (killCount <= 0) {
      return (equipmentCount: 0, consumables: const {});
    }

    int equipmentCount = 0;
    final Map<ConsumableType, int> consumables = {};
    for (final MonsterDropEntry entry in _table) {
      final double expected = _effectiveChance(entry, itemDropRate) * killCount;
      final int count = _roundExpectedValue(expected);
      if (count <= 0) {
        continue;
      }
      switch (entry.itemType) {
        case MonsterDropItemType.equipment:
          equipmentCount += count;
        case MonsterDropItemType.consumable:
          final ConsumableType? type = entry.consumableType;
          if (type != null) {
            consumables[type] = (consumables[type] ?? 0) + count;
          }
      }
    }
    return (equipmentCount: equipmentCount, consumables: consumables);
  }

  int _roundExpectedValue(double expected) {
    final int floor = expected.floor();
    final double remainder = expected - floor;
    return _random.nextDouble() < remainder ? floor + 1 : floor;
  }

  static const String _saveKey = 'monster_drop_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode(_table.map((entry) => entry.toCacheJson()).toList()),
    );
  }

  Future<void> _loadLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      return;
    }
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    _table = decoded
        .map((entry) => MonsterDropEntry.fromJson(entry as Map<String, dynamic>))
        .toList();
  }
}
