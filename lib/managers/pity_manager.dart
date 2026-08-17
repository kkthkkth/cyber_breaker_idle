import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_manager.dart';

/// 가챠 종류별로 독립적인 천장(피티) 카운터 — 캐릭터/펫/장비 세 뽑기가
/// 서로 영향을 주지 않고 각자 [PityManager.pityThreshold]회마다 최고
/// 등급을 확정 지급한다.
enum GachaPityCategory { character, pet, equipment }

/// 캐릭터/펫/장비 가챠의 천장(확정 뽑기) 카운터를 관장하는 싱글턴 —
/// [PrestigeManager]와 같은 관례(로컬 캐시가 1차 신뢰 소스, Supabase
/// `profiles`는 기기 변경/재설치에도 지켜주는 백업 계층).
///
/// [EquipmentManager.generateLootOfType]/[EquipmentManager.drawMultipleGacha]
/// (상점의 실제 가챠 버튼이 부르는 진입점들)만 이 매니저를 건드린다 — 던전
/// 보스 드랍/필드 드랍/무한의 탑 보상 같은 다른 장비 획득 경로는 천장
/// 카운트에 전혀 영향을 주지 않는다. 재화를 쓰는 진짜 가챠만 세어야
/// "천장"이라는 개념이 의미가 있고, 몬스터 처치 같은 매우 잦은 이벤트까지
/// 함께 셌다가는 순식간에 천장을 채워 보장 등급이 무의미해진다.
class PityManager extends ChangeNotifier {
  PityManager._internal();

  static final PityManager instance = PityManager._internal();

  /// 이 횟수에 도달하면(카운트가 0에서 시작해 이 값에 닿는 순간) 그 뽑기가
  /// 무조건 최고 등급으로 확정되고 카운터가 0으로 리셋된다.
  static const int pityThreshold = 100;

  int characterPityCount = 0;
  int petPityCount = 0;
  int equipmentPityCount = 0;

  int countFor(GachaPityCategory category) => switch (category) {
    GachaPityCategory.character => characterPityCount,
    GachaPityCategory.pet => petPityCount,
    GachaPityCategory.equipment => equipmentPityCount,
  };

  void _setCount(GachaPityCategory category, int value) {
    switch (category) {
      case GachaPityCategory.character:
        characterPityCount = value;
      case GachaPityCategory.pet:
        petPityCount = value;
      case GachaPityCategory.equipment:
        equipmentPityCount = value;
    }
  }

  /// [category]의 천장까지 남은 횟수 — UI 텍스트("천장까지 N회")가 그대로
  /// 쓴다.
  int remainingFor(GachaPityCategory category) =>
      (pityThreshold - countFor(category)).clamp(0, pityThreshold);

  /// 0.0~1.0 — 게이지 바 채움 비율(천장에 가까울수록 1에 가깝다).
  double progressFor(GachaPityCategory category) => countFor(category) / pityThreshold;

  /// 단위 테스트 전용 — 실제 카운트를 네트워크 없이 직접 주입한다
  /// ([PrestigeManager.debugSeedForTest]와 같은 관례).
  @visibleForTesting
  void debugSeedForTest({int? character, int? pet, int? equipment}) {
    if (character != null) characterPityCount = character;
    if (pet != null) petPityCount = pet;
    if (equipment != null) equipmentPityCount = equipment;
  }

  /// 뽑기 1회를 [category] 카운트에 반영하고, 이번 뽑기가 천장에 걸리는지
  /// 판정한다 — true면 호출부가 반드시 최고 등급을 지급해야 한다(카운터는
  /// 이미 0으로 리셋된 상태). [EquipmentManager]의 가챠 전용 진입점에서만
  /// 호출해야 한다(클래스 문서 참고).
  bool rollAndConsumePity(GachaPityCategory category) {
    final int next = countFor(category) + 1;
    final bool hitPity = next >= pityThreshold;
    _setCount(category, hitPity ? 0 : next);
    notifyListeners();
    unawaited(_saveLocal());
    unawaited(
      SupabaseManager.instance.updatePityData(
        character: characterPityCount,
        pet: petPityCount,
        equipment: equipmentPityCount,
      ),
    );
    return hitPity;
  }

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 채운 뒤, 서버 값과
  /// 비교해 더 진행된(=천장에 더 가까운) 쪽을 신뢰한다. 카운터가 적게
  /// 보이는 건 유저에게 손해고 많이 보이는 건 기껏해야 이득이라, 로컬/
  /// 서버 중 하나가 동기화에 실패해 뒤처져 있어도 유저에게 불리한 방향으로
  /// 덮어쓰지 않는다.
  Future<void> loadData() async {
    await _loadLocal();

    final ({int character, int pet, int equipment})? remote =
        await SupabaseManager.instance.fetchPityData();
    if (remote == null) {
      return;
    }
    final int mergedCharacter = max(characterPityCount, remote.character);
    final int mergedPet = max(petPityCount, remote.pet);
    final int mergedEquipment = max(equipmentPityCount, remote.equipment);
    if (mergedCharacter != characterPityCount ||
        mergedPet != petPityCount ||
        mergedEquipment != equipmentPityCount) {
      characterPityCount = mergedCharacter;
      petPityCount = mergedPet;
      equipmentPityCount = mergedEquipment;
      await _saveLocal();
    }
    notifyListeners();
  }

  static const String _saveKey = 'pity_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode({
        'characterPityCount': characterPityCount,
        'petPityCount': petPityCount,
        'equipmentPityCount': equipmentPityCount,
      }),
    );
  }

  Future<void> _loadLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      return;
    }
    try {
      final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
      characterPityCount = (data['characterPityCount'] as num?)?.toInt() ?? characterPityCount;
      petPityCount = (data['petPityCount'] as num?)?.toInt() ?? petPityCount;
      equipmentPityCount = (data['equipmentPityCount'] as num?)?.toInt() ?? equipmentPityCount;
    } catch (error) {
      debugPrint('[PityManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }
  }
}
