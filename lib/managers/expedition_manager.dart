import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/expedition_model.dart';
import '../utils/time_util.dart';
import 'game_manager.dart';
import 'notification_manager.dart';
import 'supabase_manager.dart';
import 'talent_manager.dart';

/// 용병 파견/탐험(Expedition) 시스템을 관장하는 싱글턴 — 지역
/// ([ExpeditionCatalog.regions])당 동시에 임무를 최대 1개까지 진행할 수
/// 있고, 완료되지 않은 임무의 유닛(캐릭터/펫 Equipment)은 다른 지역에
/// 중복으로 보낼 수 없다. 이 프로젝트의 다른 모든 진행형 매니저와 같은
/// 관례: 로컬(SharedPreferences)이 1차 신뢰 소스이고, Supabase
/// `user_expeditions`는 기기 변경/재설치에도 진행도를 지키는 백업/동기화
/// 계층이다.
///
/// 기존 "파견"(part-time job, [DispatchManager]/[DispatchScreen])과는
/// 이름만 비슷할 뿐 완전히 별개의 시스템이다 — 그쪽은 고정 3슬롯 + 골드/
/// 경험치/선물 아이템 보상, 이쪽은 지역 카탈로그 + 골드/보석/특성 포인트
/// 보상이며, 서로의 잠금 상태에 관여하지 않는다(같은 유닛을 두 시스템에
/// "동시에" 보내는 것 자체는 막지 않는다 — 두 기능이 독립적으로 발전할 수
/// 있도록 의도적으로 분리했다).
class ExpeditionManager extends ChangeNotifier {
  ExpeditionManager._internal();

  static final ExpeditionManager instance = ExpeditionManager._internal();

  /// regionId → 진행 중(또는 완료했지만 아직 미수령)인 임무. 지역에 임무가
  /// 없으면(=미진행) 키 자체가 없다.
  final Map<String, ExpeditionMission> _missionsByRegionId = {};

  Map<String, ExpeditionMission> get missionsByRegionId =>
      Map.unmodifiable(_missionsByRegionId);

  ExpeditionMission? missionFor(String regionId) => _missionsByRegionId[regionId];

  Timer? _tickTimer;

  /// [ExpeditionScreen]이 살아있는 동안 1초마다 카운트다운을 다시 그리기
  /// 위해 구독한다 — 실제 완료 판정은 화면이 없어도(백그라운드) 여전히
  /// NTP 기준으로 정확하다([ExpeditionMission.isCompleteAt]).
  void _ensureTicking() {
    if (_tickTimer != null || _missionsByRegionId.isEmpty) {
      return;
    }
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_missionsByRegionId.isEmpty) {
        _tickTimer?.cancel();
        _tickTimer = null;
        return;
      }
      notifyListeners();
    });
  }

  /// [unitId]([Equipment.id])가 지금 어느 지역이든 이미 파견 중인지 —
  /// 완료됐지만 아직 수령 전인 임무의 유닛도 여전히 "파견 중"으로 취급한다
  /// (보상을 받아야 비로소 복귀한 것이므로).
  bool isUnitDispatched(String unitId) =>
      _missionsByRegionId.values.any((mission) => mission.unitIds.contains(unitId));

  /// [regionId]에 [unitIds]로 파견대를 편성한다 — 1) 지역이 실제로
  /// 존재하고 2) 그 지역에 이미 진행 중인 임무가 없고 3) 최소 인원
  /// ([ExpeditionRegion.minUnits])을 채웠고 4) 유닛 중 하나도 이미 다른
  /// 곳에 파견 중이지 않아야 성공한다. 성공하면 로컬 저장 + Supabase
  /// upsert + 복귀 알림 예약까지 전부 처리한다.
  Future<bool> startExpedition({required String regionId, required List<String> unitIds}) async {
    final ExpeditionRegion? region = ExpeditionCatalog.findById(regionId);
    if (region == null) {
      return false;
    }
    if (_missionsByRegionId.containsKey(regionId)) {
      return false;
    }
    if (unitIds.length < region.minUnits) {
      return false;
    }
    if (unitIds.toSet().length != unitIds.length) {
      return false;
    }
    if (unitIds.any(isUnitDispatched)) {
      return false;
    }

    final DateTime startTime = await getNetworkTime();
    final ExpeditionMission mission = ExpeditionMission(
      regionId: regionId,
      unitIds: unitIds,
      startTime: startTime,
    );
    _missionsByRegionId[regionId] = mission;
    _ensureTicking();

    notifyListeners();
    unawaited(_saveLocal());
    unawaited(
      SupabaseManager.instance.syncExpeditionStart(
        regionId: regionId,
        unitIds: unitIds,
        startTime: startTime,
      ),
    );

    final int regionIndex = ExpeditionCatalog.regions.indexOf(region);
    unawaited(
      NotificationManager.instance.scheduleExpeditionReturn(
        regionIndex: regionIndex,
        delay: region.duration,
        regionName: region.name,
      ),
    );
    return true;
  }

  /// [MyApp.didChangeAppLifecycleState]가 앱이 백그라운드로 내려갈 때마다
  /// 호출 — 진행 중인 모든 임무의 복귀 알림을, 원래 전체 기간이 아니라
  /// "지금부터 남은 시간"으로 다시 예약한다([NotificationManager
  /// .scheduleOfflineReminder] 등과 같은 "백그라운드로 내려갈 때마다
  /// 새로 예약" 관례) — [NotificationManager.cancelAllReminders]가 포그라운드
  /// 복귀 때마다 모든 예약을 지우므로, 몇 시간짜리 탐험 중 앱을 한 번이라도
  /// 열었다 닫으면 이 재예약이 없이는 복귀 알림이 영영 안 울린다.
  Future<void> rescheduleReturnNotifications() async {
    if (_missionsByRegionId.isEmpty) {
      return;
    }
    final DateTime now = await getNetworkTime();
    for (final ExpeditionMission mission in _missionsByRegionId.values) {
      if (mission.isCollected || mission.isCompleteAt(now)) {
        continue;
      }
      final ExpeditionRegion? region = mission.region;
      if (region == null) {
        continue;
      }
      final int regionIndex = ExpeditionCatalog.regions.indexOf(region);
      await NotificationManager.instance.scheduleExpeditionReturn(
        regionIndex: regionIndex,
        delay: mission.remainingAt(now),
        regionName: region.name,
      );
    }
  }

  /// [regionId]의 완료된 임무 보상을 수령한다 — 아직 안 끝났거나 임무
  /// 자체가 없으면 null. 기기 시계 조작으로 조기 수령하는 것을 막기 위해
  /// 완료 여부를 NTP([getNetworkTime])로 다시 검증한다([DispatchManager
  /// .claimReward]와 같은 방어). 성공하면 지역이 다시 미진행 상태로
  /// 돌아가 새 파견대를 편성할 수 있다.
  Future<List<ExpeditionReward>?> claimReward(String regionId) async {
    final ExpeditionMission? mission = _missionsByRegionId[regionId];
    final ExpeditionRegion? region = mission?.region;
    if (mission == null || region == null) {
      return null;
    }
    final DateTime now = await getNetworkTime();
    if (!mission.isCompleteAt(now)) {
      return null;
    }
    // [보안 감사 2026-08-21] [DispatchManager.claimReward]와 같은 이유로
    // 추가 — 위 await 사이에 같은 지역에 대해 이 메서드가 다시 불렸을
    // 수 있으므로, 실제 지급 직전에 아직 이 임무가 그대로 남아 있는지
    // 재확인하고 곧바로(그 사이 await 없이) 제거해 중복 지급을 막는다.
    if (!identical(_missionsByRegionId[regionId], mission)) {
      return null;
    }
    _missionsByRegionId.remove(regionId);

    for (final ExpeditionReward reward in region.rewards) {
      switch (reward.type) {
        case ExpeditionRewardType.gold:
          GameManager.instance.addGold(reward.amount);
        case ExpeditionRewardType.gem:
          GameManager.instance.addGems(reward.amount);
        case ExpeditionRewardType.talentPoint:
          TalentManager.instance.grantTalentPoints(reward.amount);
      }
    }

    notifyListeners();
    unawaited(_saveLocal());
    unawaited(SupabaseManager.instance.syncExpeditionCollected(regionId));
    final int regionIndex = ExpeditionCatalog.regions.indexOf(region);
    unawaited(NotificationManager.instance.cancelExpeditionReturn(regionIndex));
    return region.rewards;
  }

  /// 단위 테스트 전용 — 실제 임무 목록을 네트워크 없이 직접 주입한다
  /// ([ArtifactManager.debugSeedForTest]와 같은 관례).
  @visibleForTesting
  void debugSeedForTest(Map<String, ExpeditionMission> missions) {
    _missionsByRegionId
      ..clear()
      ..addAll(missions);
  }

  static const String _saveKey = 'expedition_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode([for (final ExpeditionMission mission in _missionsByRegionId.values) mission.toJson()]),
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
      for (final dynamic entry in decoded) {
        final ExpeditionMission mission =
            ExpeditionMission.fromJson(entry as Map<String, dynamic>);
        _missionsByRegionId[mission.regionId] = mission;
      }
    } catch (error) {
      debugPrint('[ExpeditionManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }
  }

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 채운 뒤, 서버에
  /// 로컬에 없는 임무가 있으면(기기 변경/재설치) 그것도 합친다. 이미
  /// 로컬에 있는 지역은 로컬을 신뢰한다(로컬이 1차 신뢰 소스 — 서버는
  /// 오직 "이 기기에 아예 기록이 없을 때"의 백업 용도).
  Future<void> loadData() async {
    await _loadLocal();

    final List<Map<String, dynamic>> rows = await SupabaseManager.instance.fetchUserExpeditions();
    for (final Map<String, dynamic> row in rows) {
      try {
        final bool isCollected = row['is_collected'] as bool? ?? false;
        if (isCollected) {
          // 이미 수령 완료된 서버 기록은 로컬에 남아 있을 이유가 없다 —
          // 혹시 로컬에 아직 남아 있다면(예: 수령 직후 저장 실패) 정리한다.
          _missionsByRegionId.remove(row['region_id'] as String?);
          continue;
        }
        final ExpeditionMission remote = ExpeditionMission(
          regionId: row['region_id'] as String,
          unitIds: (row['unit_ids'] as List<dynamic>).cast<String>(),
          startTime: DateTime.parse(row['start_time'] as String),
        );
        _missionsByRegionId.putIfAbsent(remote.regionId, () => remote);
      } catch (error) {
        debugPrint('[ExpeditionManager] 서버 임무 행 파싱 실패: $error');
      }
    }

    _ensureTicking();
    await _saveLocal();
    notifyListeners();
  }
}
