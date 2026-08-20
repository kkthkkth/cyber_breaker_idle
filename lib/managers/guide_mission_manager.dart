import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/guide_mission_model.dart';
import 'game_manager.dart';

/// 초보자 온보딩용 "메인 가이드 미션" — 일일/주간/월간 [QuestManager]와
/// 달리 무작위 배정이 아니라 [sequence]에 정의된 순서를 1번부터 차례로
/// 클리어하는 **선형** 구조다. 항상 딱 하나의 미션만 "진행 중"이고
/// ([currentMission]), 그 미션을 수령([claimCurrent])하면 곧바로 다음
/// 번호가 노출된다. 서버 카탈로그 없이 전부 로컬(SharedPreferences)에만
/// 저장한다 — [QuestManager]/[PrestigeManager]와 달리 Supabase 백업
/// 계층을 얹지 않았다: 신규 유저 1회성 온보딩 콘텐츠라 기기 변경 시
/// 다시 시작해도(=처음부터 다시 노출) 다른 누적형 시스템만큼 손해가
/// 크지 않다는 판단.
class GuideMissionManager extends ChangeNotifier {
  GuideMissionManager._internal();

  static final GuideMissionManager instance = GuideMissionManager._internal();

  /// 테스트용 10단계 시퀀스 — 요구사항 예시(몬스터 처치 → 공격력 강화 →
  /// 스테이지 도달 → 장비 뽑기)를 그대로 확장했다. `stage_reached` 항목의
  /// [GuideMission.targetCount]는 절대 스테이지([GameManager.absoluteStage],
  /// `(chapter-1)*10+stage` 공식)다 — 예: "1-5"는 5, "2-5"는 15. 수치/보상은
  /// 전부 1차 값이고 밸런싱은 추후 실측 후 조정 대상.
  static final List<GuideMission> sequence = [
    const GuideMission(
      id: 'guide_01',
      order: 1,
      actionType: GuideMissionActionType.monsterKill,
      description: '몬스터 10마리 처치하기',
      targetCount: 10,
      rewardType: GuideMissionRewardType.gold,
      rewardAmount: 500,
    ),
    const GuideMission(
      id: 'guide_02',
      order: 2,
      actionType: GuideMissionActionType.attackUpgrade,
      description: '공격력 5회 강화하기',
      targetCount: 5,
      rewardType: GuideMissionRewardType.gold,
      rewardAmount: 800,
    ),
    const GuideMission(
      id: 'guide_03',
      order: 3,
      actionType: GuideMissionActionType.stageReached,
      description: '1-5 스테이지 도달하기',
      targetCount: 5,
      rewardType: GuideMissionRewardType.gem,
      rewardAmount: 20,
    ),
    const GuideMission(
      id: 'guide_04',
      order: 4,
      actionType: GuideMissionActionType.equipmentGachaPull,
      description: '장비 1회 뽑기',
      targetCount: 1,
      rewardType: GuideMissionRewardType.gem,
      rewardAmount: 30,
      shortcut: GuideMissionShortcut.shop,
    ),
    const GuideMission(
      id: 'guide_05',
      order: 5,
      actionType: GuideMissionActionType.monsterKill,
      description: '몬스터 30마리 처치하기',
      targetCount: 30,
      rewardType: GuideMissionRewardType.gold,
      rewardAmount: 1500,
    ),
    const GuideMission(
      id: 'guide_06',
      order: 6,
      actionType: GuideMissionActionType.attackUpgrade,
      description: '공격력 10회 강화하기',
      targetCount: 10,
      rewardType: GuideMissionRewardType.gem,
      rewardAmount: 100,
    ),
    const GuideMission(
      id: 'guide_07',
      order: 7,
      actionType: GuideMissionActionType.stageReached,
      description: '1-10 스테이지 도달하기(보스 처치)',
      targetCount: 10,
      rewardType: GuideMissionRewardType.gold,
      rewardAmount: 3000,
    ),
    const GuideMission(
      id: 'guide_08',
      order: 8,
      actionType: GuideMissionActionType.defenseUpgrade,
      description: '방어력 5회 강화하기',
      targetCount: 5,
      rewardType: GuideMissionRewardType.gem,
      rewardAmount: 40,
    ),
    const GuideMission(
      id: 'guide_09',
      order: 9,
      actionType: GuideMissionActionType.stageReached,
      description: '2-5 스테이지 도달하기',
      targetCount: 15,
      rewardType: GuideMissionRewardType.gold,
      rewardAmount: 5000,
    ),
    const GuideMission(
      id: 'guide_10',
      order: 10,
      actionType: GuideMissionActionType.equipmentGachaPull,
      description: '장비 3회 뽑기',
      targetCount: 3,
      rewardType: GuideMissionRewardType.gem,
      rewardAmount: 150,
      shortcut: GuideMissionShortcut.shop,
    ),
  ];

  /// [sequence]를 가리키는 커서 — [sequence.length]에 도달하면(=
  /// [isAllCompleted]) 더 이상 진행 중인 미션이 없다.
  int _currentIndex = 0;
  int _currentCount = 0;

  GuideMission? get currentMission =>
      _currentIndex < sequence.length ? sequence[_currentIndex] : null;

  int get currentCount => _currentCount;

  bool get isAllCompleted => _currentIndex >= sequence.length;

  /// [_MainNavigationScreenState]가 앱 시작 시 자기 자신의 탭 전환 메서드를
  /// 여기 연결해 둔다([GameManager.onChapterAdvanced]와 같은 콜백 관례) —
  /// [GuideMissionBanner]는 홈 탭 내부 위젯이라 그 조상인
  /// `_MainNavigationScreenState`의 사설 상태(`_selectedIndex`)에 직접
  /// 접근할 방법이 없기 때문이다.
  void Function(int tabIndex)? onRequestTabSwitch;

  /// 단위 테스트 전용 — 실제 진행 상태를 네트워크/저장소 없이 직접
  /// 주입한다([PotionManager.debugSeedForTest]와 같은 관례).
  @visibleForTesting
  void debugSeedForTest({required int currentIndex, required int currentCount}) {
    _currentIndex = currentIndex;
    _currentCount = currentCount;
  }

  /// [actionType]에 해당하는 "누적 카운트" 이벤트를 [amount]만큼 반영한다
  /// (목표치에서 멈춘다) — 지금 진행 중인 미션([currentMission])의
  /// actionType과 다르면 아무것도 하지 않는다. 이미 목표치를 채우고 수령
  /// 대기 중이어도 더 늘어나지 않는다.
  void updateProgress(String actionType, int amount) {
    final GuideMission? mission = currentMission;
    if (mission == null || amount <= 0 || mission.actionType != actionType) {
      return;
    }
    if (_currentCount >= mission.targetCount) {
      return;
    }
    _currentCount = (_currentCount + amount).clamp(0, mission.targetCount);
    notifyListeners();
    unawaited(_saveLocal());
  }

  /// [actionType]이 "누적 카운트"가 아니라 "지금 관측된 절대값"을 보고하는
  /// 이벤트([GuideMissionActionType.stageReached] 등)에 쓴다 — 이미 그
  /// 값 이상을 관측했으면(게임 진행상 값이 줄어들 일은 없지만 방어적으로)
  /// 아무것도 하지 않는다.
  void reportAbsoluteValue(String actionType, int value) {
    final GuideMission? mission = currentMission;
    if (mission == null || mission.actionType != actionType) {
      return;
    }
    final int next = value.clamp(0, mission.targetCount);
    if (next <= _currentCount) {
      return;
    }
    _currentCount = next;
    notifyListeners();
    unawaited(_saveLocal());
  }

  /// 지금 진행 중인 미션의 보상을 수령한다 — 목표 달성 전이면 아무것도
  /// 바꾸지 않고 null. 성공하면 보상을 지급하고 커서를 다음 미션으로
  /// 옮긴 뒤, 방금 수령한 [GuideMission]을 돌려준다(호출부가 토스트에
  /// [GuideMission.rewardLabel]을 쓸 수 있도록).
  Future<GuideMission?> claimCurrent() async {
    final GuideMission? mission = currentMission;
    if (mission == null || _currentCount < mission.targetCount) {
      return null;
    }
    await _grantReward(mission.rewardType, mission.rewardAmount);
    _currentIndex++;
    _currentCount = 0;
    notifyListeners();
    await _saveLocal();
    return mission;
  }

  Future<void> _grantReward(String rewardType, int amount) async {
    if (amount <= 0) {
      return;
    }
    switch (rewardType) {
      case GuideMissionRewardType.gold:
        GameManager.instance.addGold(amount);
      case GuideMissionRewardType.gem:
        GameManager.instance.addGems(amount);
      default:
        debugPrint('[GuideMissionManager] 알 수 없는 보상 타입: $rewardType');
    }
  }

  /// main()이 앱 시작 시 한 번 호출.
  Future<void> loadData() async {
    await _loadLocal();
    notifyListeners();
  }

  static const String _saveKey = 'guide_mission_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode({'currentIndex': _currentIndex, 'currentCount': _currentCount}),
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
      _currentIndex = (data['currentIndex'] as num?)?.toInt() ?? _currentIndex;
      _currentCount = (data['currentCount'] as num?)?.toInt() ?? _currentCount;
    } catch (error) {
      debugPrint('[GuideMissionManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }
  }
}
