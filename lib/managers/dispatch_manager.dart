import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/consumable_item_model.dart';
import '../models/dispatch_model.dart';
import '../utils/time_util.dart';
import 'affection_manager.dart';
import 'consumable_manager.dart';
import 'game_manager.dart';

/// 파견(아르바이트) 시스템 — [maxSlots]개의 독립된 파견처에 각각
/// [maxCharactersPerMission]명까지 캐릭터를 편성해 [DispatchDuration]만큼
/// 보내고, 완료되면 골드/경험치/호감도 선물 아이템을 정산받는다.
///
/// [ConsumableManager]/[AffectionManager]와 같은 패턴(ChangeNotifier +
/// SharedPreferences 직렬화 싱글턴)을 따른다.
class DispatchManager extends ChangeNotifier {
  DispatchManager._internal() {
    _loadData();
  }

  static final DispatchManager instance = DispatchManager._internal();

  final Random _random = Random();

  /// 동시에 운용 가능한 파견 슬롯 수.
  static const int maxSlots = 3;

  /// 슬롯 하나에 편성 가능한 최대 인원 — 요구사항의 "3명의 잉여 캐릭터를
  /// 편성"에 맞춘 값.
  static const int maxCharactersPerMission = 3;

  /// 인덱스 = 슬롯 번호, null이면 그 슬롯은 비어 있음(파견 대기 중).
  final List<DispatchMission?> _missions = List<DispatchMission?>.filled(maxSlots, null);

  /// 화면에서 읽기 전용으로만 순회하도록 unmodifiable로 노출한다 — 슬롯을
  /// 바꾸는 유일한 통로는 [startDispatch]/[claimReward]뿐이다.
  List<DispatchMission?> get missions => List.unmodifiable(_missions);

  /// 남은 시간 카운트다운을 화면에 반영하기 위한 주기 tick — 활성 임무가
  /// 하나도 없으면 아예 돌리지 않는다(불필요한 배터리 소모 방지).
  ///
  /// [주의] 1초 주기는 "타이머 뼈대"를 보여주기 위한 값이다. 실제 서비스
  /// 단계에서는 초 단위 정밀도가 필요 없으면(예: 분 단위 표시만 한다면)
  /// 주기를 30초~1분으로 늘리거나, 앱이 백그라운드일 때는
  /// [WidgetsBindingObserver]로 감지해 틱을 멈추는 최적화를 고려할 것.
  Timer? _tickTimer;

  bool get _hasActiveMission => _missions.any((mission) => mission != null);

  void _updateTicking() {
    final bool shouldTick = _hasActiveMission;
    final bool isTicking = _tickTimer != null;
    if (shouldTick == isTicking) {
      return;
    }
    if (shouldTick) {
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    } else {
      _tickTimer?.cancel();
      _tickTimer = null;
    }
  }

  bool isSlotBusy(int slotIndex) => _missions[slotIndex] != null;

  /// 이미 다른 파견 슬롯에 편성돼 있는 캐릭터는 중복 편성할 수 없다 —
  /// 호출부(파견 화면의 캐릭터 선택 목록)가 이 체크로 후보를 거른다.
  bool isCharacterDispatched(String characterId) =>
      _missions.any((mission) => mission != null && mission.characterIds.contains(characterId));

  /// [slotIndex]에 [characterIds]를 편성해 [duration]짜리 파견을 시작한다.
  /// 슬롯이 이미 사용 중이거나, 인원수가 범위를 벗어나거나, 이미 다른
  /// 슬롯에 편성된 캐릭터가 섞여 있으면 아무것도 바꾸지 않고 false.
  Future<bool> startDispatch({
    required int slotIndex,
    required List<String> characterIds,
    required DispatchDuration duration,
  }) async {
    if (slotIndex < 0 || slotIndex >= maxSlots || isSlotBusy(slotIndex)) {
      return false;
    }
    if (characterIds.isEmpty || characterIds.length > maxCharactersPerMission) {
      return false;
    }
    if (characterIds.toSet().length != characterIds.length) {
      return false; // 같은 캐릭터를 두 번 편성하는 실수 방지.
    }
    if (characterIds.any(isCharacterDispatched)) {
      return false;
    }

    // [주의] 반드시 NTP를 써야 한다 — 기기 시계로 시작 시각을 찍으면,
    // 시작 직후 시계를 [duration]만큼 앞당겨 바로 완료 처리할 수 있다
    // ([DispatchMission.isCompleteAt] 문서 참고).
    final DateTime now = await getNetworkTime();
    _missions[slotIndex] = DispatchMission(
      slotIndex: slotIndex,
      characterIds: List.unmodifiable(characterIds),
      duration: duration,
      startTime: now,
    );
    _updateTicking();
    _saveData();
    notifyListeners();
    return true;
  }

  /// 테스트 전용 — 실제 몇 시간을 기다리지 않고도 [claimReward]의 성공
  /// 경로를 검증할 수 있도록, 해당 슬롯의 시작 시각을 과거로 돌려 즉시
  /// 완료 상태로 만든다. 프로덕션 코드에서는 호출하지 않는다.
  @visibleForTesting
  void debugForceComplete(int slotIndex) {
    final DispatchMission? mission = _missions[slotIndex];
    if (mission == null) {
      return;
    }
    _missions[slotIndex] = DispatchMission(
      slotIndex: mission.slotIndex,
      characterIds: mission.characterIds,
      duration: mission.duration,
      startTime: DateTime.now().subtract(mission.duration.duration).subtract(const Duration(minutes: 1)),
    );
    notifyListeners();
  }

  /// 골드 보상 — 소요 시간 × 인원수에 비례하는 더미 공식. DB 연동 시 이
  /// 메서드만 서버 테이블 조회로 바꾸면 된다([AffectionManager
  /// .affectionGainForGift]와 같은 패턴).
  int _goldRewardFor(DispatchMission mission) {
    final int hours = mission.duration.duration.inHours;
    return hours * 100 * mission.characterIds.length;
  }

  /// 경험치 보상 — [DispatchRewardResult.exp] 참고(아직 실제 소비처 없는
  /// 더미 값).
  int _expRewardFor(DispatchMission mission) {
    final int hours = mission.duration.duration.inHours;
    return hours * 20 * mission.characterIds.length;
  }

  /// 편성된 캐릭터 각각에 대해 독립적으로 굴려서, 파견 시간이 길수록(=
  /// 위험 부담이 클수록) 호감도 선물 아이템을 더 잘 얻도록 한 더미 확률표
  /// — DB 연동 시 이 메서드만 바꾸면 된다.
  List<ConsumableType> _rollGiftDrops(DispatchMission mission) {
    final double dropChance = switch (mission.duration) {
      DispatchDuration.twoHours => 0.15,
      DispatchDuration.fourHours => 0.30,
      DispatchDuration.eightHours => 0.50,
    };

    final List<ConsumableType> dropped = [];
    for (final _ in mission.characterIds) {
      if (_random.nextDouble() >= dropChance) {
        continue;
      }
      final List<ConsumableType> giftPool = AffectionManager.giftTypes;
      dropped.add(giftPool[_random.nextInt(giftPool.length)]);
    }
    return dropped;
  }

  /// [slotIndex]의 파견을 정산하고 슬롯을 비운다. 슬롯이 비어 있거나
  /// 아직 완료 전이면(=[DispatchMission.isComplete]가 false) null.
  Future<DispatchRewardResult?> claimReward(int slotIndex) async {
    if (slotIndex < 0 || slotIndex >= maxSlots) {
      return null;
    }
    final DispatchMission? mission = _missions[slotIndex];
    if (mission == null) {
      return null;
    }
    // 로컬(기기 시계) [DispatchMission.isComplete]는 버튼 활성/비활성을
    // 미리 보여주는 낙관적 판정일 뿐이다 — 실제 지급 직전에 NTP로 한 번 더
    // 확인한다.
    final DateTime now = await getNetworkTime();
    if (!mission.isCompleteAt(now)) {
      return null;
    }

    final int gold = _goldRewardFor(mission);
    final int exp = _expRewardFor(mission);
    final List<ConsumableType> gifts = _rollGiftDrops(mission);

    GameManager.instance.addGold(gold);
    for (final ConsumableType type in gifts) {
      ConsumableManager.instance.addItem(type, 1);
    }

    _missions[slotIndex] = null;
    _updateTicking();
    _saveData();
    notifyListeners();

    return DispatchRewardResult(gold: gold, exp: exp, giftItems: gifts);
  }

  static const String _saveKey = 'dispatch_manager_save';

  Future<void> _pendingSave = Future<void>.value();

  /// [AffectionManager]와 같은 이유로 직렬 저장 큐를 쓴다 — 연타/짧은
  /// 간격의 중복 호출로 저장 순서가 뒤바뀌어 오래된 스냅샷이 최신 상태를
  /// 덮어쓰는 걸 막는다.
  Future<void> _saveData() {
    final Future<void> next = _pendingSave.then((_) => _writeData());
    _pendingSave = next;
    return next;
  }

  Future<void> _writeData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>?> json = _missions
        .map((mission) => mission?.toJson())
        .toList();
    await prefs.setString(_saveKey, jsonEncode(json));
  }

  Future<void> _loadData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      return;
    }

    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      for (int i = 0; i < decoded.length && i < maxSlots; i++) {
        final dynamic entry = decoded[i];
        if (entry != null) {
          _missions[i] = DispatchMission.fromJson(entry as Map<String, dynamic>);
        }
      }
    } catch (error) {
      debugPrint('[DispatchManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
      return;
    }

    _updateTicking();
    notifyListeners();
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }
}
