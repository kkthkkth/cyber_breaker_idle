import 'dart:convert';

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

  /// [floor]에 해당하는 층 데이터 — 테이블에 없으면 null(호출부가 안내
  /// 문구를 보여주거나, 아직 등록 안 된 층이라 도전을 막는 등 처리한다).
  TowerFloor? floorData(int floor) {
    for (final TowerFloor data in _floors) {
      if (data.floor == floor) {
        return data;
      }
    }
    return null;
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
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    _floors = decoded
        .map((entry) => TowerFloor.fromJson(entry as Map<String, dynamic>))
        .toList();
  }
}
