import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tower_floor_model.dart';
import 'supabase_manager.dart';

/// 무한의 탑 층별 몬스터 스탯/보상 카탈로그(`tower_floors`)를 관장하는
/// 싱글턴 — [PotionManager]/[GuildShopManager]와 같은 관례(로컬 캐시 우선,
/// Supabase는 부가적인 백업/동기화 계층)를 따른다. 이 매니저는 "각 층이
/// 어떤 스탯/보상을 갖는지"만 책임지고, "유저가 지금 몇 층까지 깼는지"는
/// [DungeonManager.highestClearedFloor]가 별도로(profiles 테이블과 동기화)
/// 관리한다.
class TowerFloorManager {
  TowerFloorManager._internal();

  static final TowerFloorManager instance = TowerFloorManager._internal();

  List<TowerFloor> _floors = const [];
  List<TowerFloor> get floors => _floors;

  /// 단위 테스트 전용 — 실제 층 테이블을 네트워크 없이 직접 주입한다
  /// ([PotionManager.debugSeedForTest]와 같은 관례).
  @visibleForTesting
  void debugSeedForTest(List<TowerFloor> floors) {
    _floors = floors;
  }

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 채운 뒤 원격
  /// 테이블을 받아와 갱신을 시도한다.
  Future<void> loadData() async {
    await _loadLocal();

    final List<Map<String, dynamic>> rows = await SupabaseManager.instance.fetchTowerFloors();
    if (rows.isEmpty) {
      debugPrint(
        '[TowerFloorManager] 층 테이블이 비어 있습니다(tower_floors 테이블/RLS 정책을 확인하세요). '
        '기존 캐시(${_floors.length}건)를 유지합니다.',
      );
    } else {
      final List<TowerFloor> parsed = [];
      for (final Map<String, dynamic> row in rows) {
        try {
          parsed.add(TowerFloor.fromJson(row));
        } catch (error) {
          debugPrint('[TowerFloorManager] 층 데이터 파싱 실패(floor=${row['floor']}): $error');
        }
      }
      if (parsed.isNotEmpty) {
        parsed.sort((a, b) => a.floor.compareTo(b.floor));
        _floors = parsed;
      } else {
        debugPrint('[TowerFloorManager] 파싱 가능한 층 데이터가 하나도 없습니다 — 컬럼명/타입을 확인하세요.');
      }
    }

    await _saveLocal();
  }

  /// [floor]에 해당하는 층 데이터 — DB에 그 층이 직접 등록돼 있으면 그
  /// 값을 그대로 쓰고, 시딩된 최고 층보다 더 높은 층이면(예: 101층인데
  /// 100층까지만 등록됨) 그 최고 층을 기준으로 [_syntheticFloorData]가
  /// 지수 스케일링 공식으로 즉석에서 만들어 준다 — "무한"의 탑이 실제로
  /// DB 시딩 범위를 넘어서도 끝없이 이어지게 한다(요구사항: "층수가
  /// 올라감에 따라... 지수/지속 스케일링 공식으로 커지도록"). 카탈로그
  /// 자체가 아직 한 번도 로드되지 않았으면(완전히 비어 있으면) null —
  /// 이 경우만 호출부가 "아직 불러오는 중" 안내를 보여준다.
  TowerFloor? floorData(int floor) {
    if (_floors.isEmpty) {
      return null;
    }
    for (final TowerFloor data in _floors) {
      if (data.floor == floor) {
        return data;
      }
    }
    final TowerFloor highestSeeded = _floors.last;
    if (floor > highestSeeded.floor) {
      return _syntheticFloorData(floor, anchor: highestSeeded);
    }
    // 시딩된 범위 안인데 특정 층 하나만 빠진 경우(운영 실수로 생긴 구멍) —
    // 존재하지 않는 층으로 잘못 클리어 처리되는 사고를 막기 위해
    // 예전처럼 null을 돌려준다(합성 대상은 "최고 시딩 층 이후"로만
    // 한정한다).
    return null;
  }

  /// [anchor](DB에 마지막으로 등록된 층)를 기준으로, 그보다 [floor]가
  /// 얼마나 더 높은지에 비례해 몬스터 HP/공격력/보상을 지수적으로
  /// 키운다. 매 층 5% 안팎으로 계속 불어나는 "지속 스케일링" 곡선이라,
  /// 층이 아무리 높아져도 멈추지 않는다. 밸런스 수치는 정확한 기획 데이터
  /// 없이 임의로 정한 값이니, 실제 수치가 정해지면 이 두 상수만 바꾸면
  /// 된다.
  static const double _hpGrowthPerFloor = 1.05;
  static const double _attackGrowthPerFloor = 1.04;
  static const double _goldGrowthPerFloor = 1.03;

  TowerFloor _syntheticFloorData(int floor, {required TowerFloor anchor}) {
    final int stepsBeyondAnchor = floor - anchor.floor;
    // anchor 자체의 HP/ATK가 0으로 시딩돼 있으면(운영 데이터 미비) 최소
    // 바닥값을 깔아 스케일링이 0에서 영원히 0으로만 남는 사고를 막는다.
    final double baseHp = anchor.monsterHp > 0 ? anchor.monsterHp : 60;
    final double baseAttack = anchor.monsterAttack > 0 ? anchor.monsterAttack : 10;
    final int baseGold = anchor.rewardGold > 0 ? anchor.rewardGold : floor * 30;

    return TowerFloor(
      floor: floor,
      monsterHp: baseHp * pow(_hpGrowthPerFloor, stepsBeyondAnchor),
      monsterAttack: baseAttack * pow(_attackGrowthPerFloor, stepsBeyondAnchor),
      // 보석은 완만하게(5층마다 +1) — 골드/HP처럼 매 층 복리로 불리면
      // 너무 빨리 인플레이션이 난다.
      rewardGem: anchor.rewardGem + (stepsBeyondAnchor ~/ 5),
      rewardGold: (baseGold * pow(_goldGrowthPerFloor, stepsBeyondAnchor)).round(),
    );
  }

  static const String _saveKey = 'tower_floor_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode(_floors.map((floor) => floor.toCacheJson()).toList()),
    );
  }

  Future<void> _loadLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      return;
    }
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      _floors = decoded
          .map((entry) => TowerFloor.fromJson(entry as Map<String, dynamic>))
          .toList();
    } catch (error) {
      debugPrint('[TowerFloorManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }
  }
}
