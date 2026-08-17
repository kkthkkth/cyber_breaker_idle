import 'package:flutter/foundation.dart';

import '../models/equipment_set_model.dart';
import 'supabase_manager.dart';

/// 장비 세트 효과(2부위/4부위) 카탈로그 관리 — [PetStatMetadataManager]와
/// 같은 성격: 로그인 여부와 무관한 공개 참조 데이터라 로컬 저장 없이
/// 메모리에만 캐시한다. 실제 "지금 몇 부위 장착했는지"는 유저 상태
/// ([EquipmentManager.equippedSetCounts])이므로 이 매니저가 들고 있지
/// 않고, [totalBonus]/[activeBonuses] 호출부가 매번 넘겨준다.
class EquipmentSetManager {
  EquipmentSetManager._internal();

  static final EquipmentSetManager instance = EquipmentSetManager._internal();

  List<EquipmentSetBonus> _catalog = const [];
  List<EquipmentSetBonus> get catalog => _catalog;

  /// 단위 테스트 전용 — 실제 카탈로그를 네트워크 없이 직접 주입한다.
  @visibleForTesting
  void debugSeedForTest(List<EquipmentSetBonus> catalog) {
    _catalog = catalog;
  }

  /// main()이 앱 시작 시 한 번 호출.
  Future<void> loadData() async {
    final List<Map<String, dynamic>> rows =
        await SupabaseManager.instance.fetchEquipmentSets();
    if (rows.isEmpty) {
      debugPrint(
        '[EquipmentSetManager] 세트 카탈로그가 비어 있습니다(equipment_sets 테이블/RLS '
        '정책을 확인하세요). 기존 캐시(${_catalog.length}건)를 유지합니다.',
      );
      return;
    }

    final List<EquipmentSetBonus> catalog = [];
    for (final Map<String, dynamic> row in rows) {
      try {
        catalog.add(EquipmentSetBonus.fromJson(row));
      } catch (error) {
        debugPrint('[EquipmentSetManager] 세트 행 파싱 실패(set_id=${row['set_id']}): $error');
      }
    }
    _catalog = catalog;
  }

  EquipmentSetBonus? _bonusFor(String setId) {
    for (final EquipmentSetBonus bonus in _catalog) {
      if (bonus.setId == setId) {
        return bonus;
      }
    }
    return null;
  }

  /// [equippedCountBySetId](보통 `EquipmentManager.equippedSetCounts`)를
  /// 받아 지금 발동 중인 세트 효과 전부를 나열한다 — 2부위 이상이면
  /// 2부위 효과가, 4부위 이상이고 [EquipmentSetBonus.fourPieceStat]이
  /// 있으면 4부위 효과도 함께(둘 다) 켜진다.
  List<ActiveSetBonus> activeBonuses(Map<String, int> equippedCountBySetId) {
    final List<ActiveSetBonus> results = [];
    equippedCountBySetId.forEach((setId, count) {
      final EquipmentSetBonus? bonus = _bonusFor(setId);
      if (bonus == null) {
        return;
      }
      if (count >= 2) {
        results.add(
          ActiveSetBonus(
            setId: setId,
            setName: bonus.name,
            equippedCount: count,
            stat: bonus.twoPieceStat,
            value: bonus.twoPieceValue,
            isFourPiece: false,
          ),
        );
      }
      if (count >= 4 && bonus.fourPieceStat != null) {
        results.add(
          ActiveSetBonus(
            setId: setId,
            setName: bonus.name,
            equippedCount: count,
            stat: bonus.fourPieceStat!,
            value: bonus.fourPieceValue,
            isFourPiece: true,
          ),
        );
      }
    });
    return results;
  }

  /// [statKey]를 가진 모든 활성 세트 효과의 합계 — [GameManager]가
  /// 공격력/방어력/크리티컬 확률/최대체력 계산마다 호출한다.
  double totalBonus(String statKey, Map<String, int> equippedCountBySetId) =>
      activeBonuses(equippedCountBySetId)
          .where((bonus) => bonus.stat == statKey)
          .fold(0.0, (sum, bonus) => sum + bonus.value);
}
