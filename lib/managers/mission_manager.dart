import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mission_model.dart';
import '../utils/time_util.dart';
import 'game_manager.dart';

class MissionManager extends ChangeNotifier with WidgetsBindingObserver {
  MissionManager._internal();

  static final MissionManager instance = MissionManager._internal();

  final Random _random = Random();

  List<Mission> activeMissions = [];

  String? _lastDailyReset;
  String? _lastWeeklyReset;
  String? _lastMonthlyReset;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Fire-and-forget: the override signature must stay void/sync.
      checkAndResetMissions();
    }
  }

  /// Zeroes out progress/claim state for whichever mission tiers have
  /// rolled over — daily at midnight, weekly at Monday midnight, monthly on
  /// the 1st — since the last check. Safe to call repeatedly; saves only
  /// when something actually reset.
  Future<void> checkAndResetMissions() async {
    final DateTime now = await getNetworkTime();
    final String today = _formatDate(now);
    final String thisMonday = _formatDate(
      now.subtract(Duration(days: now.weekday - 1)),
    );
    final String thisMonth = _formatMonth(now);

    bool changed = false;

    if (_lastDailyReset != today) {
      _resetMissionsOfType(MissionType.daily);
      _lastDailyReset = today;
      changed = true;
    }

    if (_lastWeeklyReset != thisMonday) {
      _resetMissionsOfType(MissionType.weekly);
      _lastWeeklyReset = thisMonday;
      changed = true;
    }

    if (_lastMonthlyReset != thisMonth) {
      _resetMissionsOfType(MissionType.monthly);
      _lastMonthlyReset = thisMonth;
      changed = true;
    }

    if (changed) {
      notifyListeners();
      await saveData();
    }
  }

  void _resetMissionsOfType(MissionType type) {
    for (final Mission mission in activeMissions) {
      if (mission.missionType != type) {
        continue;
      }
      mission.currentValue = 0;
      mission.isCleared = false;
      mission.isRewardClaimed = false;
    }
  }

  static String _formatDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static String _formatMonth(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    return '${date.year}-$month';
  }

  static const String _saveKey = 'mission_manager_save';

  Future<void> saveData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> data = {
      'activeMissions': activeMissions.map((m) => m.toJson()).toList(),
      'lastDailyReset': _lastDailyReset,
      'lastWeeklyReset': _lastWeeklyReset,
      'lastMonthlyReset': _lastMonthlyReset,
    };
    await prefs.setString(_saveKey, jsonEncode(data));
  }

  /// Loads persisted missions/reset dates, falling back to
  /// [loadMissionsFromDB] on a fresh install, then immediately runs
  /// [checkAndResetMissions] so a reset that happened while the app was
  /// closed is applied right away.
  Future<void> loadData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);

    if (raw != null) {
      final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
      final List<dynamic>? savedMissions =
          data['activeMissions'] as List<dynamic>?;
      if (savedMissions != null && savedMissions.isNotEmpty) {
        activeMissions = savedMissions
            .map((entry) => Mission.fromJson(entry as Map<String, dynamic>))
            .toList();
      }
      _lastDailyReset = data['lastDailyReset'] as String?;
      _lastWeeklyReset = data['lastWeeklyReset'] as String?;
      _lastMonthlyReset = data['lastMonthlyReset'] as String?;
    }

    if (activeMissions.isEmpty) {
      await loadMissionsFromDB();
    }

    await checkAndResetMissions();
    notifyListeners();
  }

  List<Mission> missionsOfType(MissionType type) =>
      activeMissions.where((mission) => mission.missionType == type).toList();

  /// Simulates fetching today's mission set from a backend.
  ///
  /// Replace the body of this method with the real API call once the
  /// mission pool moves server-side, e.g.:
  /// ```
  /// final response = await http.get(Uri.parse('$apiBase/missions'));
  /// activeMissions = (jsonDecode(response.body) as List)
  ///     .map((e) => Mission.fromJson(e as Map<String, dynamic>))
  ///     .toList();
  /// ```
  /// Everything downstream (updateProgress/claimReward/the UI) already
  /// works purely off `activeMissions`, so no other code needs to change.
  Future<void> loadMissionsFromDB() async {
    // TODO(server): replace with a real network call — see doc comment above.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    activeMissions = [
      ..._pickRandom(_dailyPool, 3),
      ..._pickRandom(_weeklyPool, 3),
      ..._pickRandom(_monthlyPool, 3),
    ];
    notifyListeners();
  }

  List<Mission> _pickRandom(List<Mission> pool, int count) {
    final List<Mission> shuffled = List<Mission>.of(pool)..shuffle(_random);
    // Clone via toJson/fromJson so each active mission is an independent
    // instance — the pool entries are static templates and must never be
    // mutated directly (they get re-picked on every reload).
    return shuffled
        .take(count)
        .map((template) => Mission.fromJson(template.toJson()))
        .toList();
  }

  /// Call this wherever a trackable game action happens (see integration
  /// notes in idle_game.dart / home_screen.dart).
  void updateProgress(ActionType actionType, int amount) {
    bool changed = false;

    for (final Mission mission in activeMissions) {
      if (mission.actionType != actionType || mission.isCleared) {
        continue;
      }

      mission.currentValue =
          (mission.currentValue + amount).clamp(0, mission.targetValue);
      if (mission.currentValue >= mission.targetValue) {
        mission.isCleared = true;
      }
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }

  bool claimReward(String id) {
    final int index = activeMissions.indexWhere((mission) => mission.id == id);
    if (index == -1) {
      return false;
    }

    final Mission mission = activeMissions[index];
    if (!mission.isCleared || mission.isRewardClaimed) {
      return false;
    }

    switch (mission.rewardType) {
      case RewardType.gold:
        GameManager.instance.addGold(mission.rewardAmount);
      case RewardType.gem:
        GameManager.instance.addGems(mission.rewardAmount);
    }

    mission.isRewardClaimed = true;
    notifyListeners();
    return true;
  }

  static final List<Mission> _dailyPool = [
    Mission(
      id: 'daily_kill_20',
      missionType: MissionType.daily,
      actionType: ActionType.killMonster,
      title: '몬스터 처치',
      description: '몬스터를 20마리 처치하세요',
      targetValue: 20,
      rewardType: RewardType.gold,
      rewardAmount: 500,
    ),
    Mission(
      id: 'daily_kill_50',
      missionType: MissionType.daily,
      actionType: ActionType.killMonster,
      title: '몬스터 대량 처치',
      description: '몬스터를 50마리 처치하세요',
      targetValue: 50,
      rewardType: RewardType.gold,
      rewardAmount: 1000,
    ),
    Mission(
      id: 'daily_upgrade_3',
      missionType: MissionType.daily,
      actionType: ActionType.upgrade,
      title: '강화하기',
      description: '아무 능력치나 3회 강화하세요',
      targetValue: 3,
      rewardType: RewardType.gold,
      rewardAmount: 300,
    ),
    Mission(
      id: 'daily_clear_5',
      missionType: MissionType.daily,
      actionType: ActionType.clearStage,
      title: '스테이지 클리어',
      description: '스테이지를 5회 클리어하세요',
      targetValue: 5,
      rewardType: RewardType.gem,
      rewardAmount: 10,
    ),
    Mission(
      id: 'daily_clear_10',
      missionType: MissionType.daily,
      actionType: ActionType.clearStage,
      title: '스테이지 다수 클리어',
      description: '스테이지를 10회 클리어하세요',
      targetValue: 10,
      rewardType: RewardType.gem,
      rewardAmount: 20,
    ),
  ];

  static final List<Mission> _weeklyPool = [
    Mission(
      id: 'weekly_kill_300',
      missionType: MissionType.weekly,
      actionType: ActionType.killMonster,
      title: '주간 몬스터 처치',
      description: '몬스터를 300마리 처치하세요',
      targetValue: 300,
      rewardType: RewardType.gold,
      rewardAmount: 5000,
    ),
    Mission(
      id: 'weekly_upgrade_15',
      missionType: MissionType.weekly,
      actionType: ActionType.upgrade,
      title: '주간 강화',
      description: '아무 능력치나 15회 강화하세요',
      targetValue: 15,
      rewardType: RewardType.gold,
      rewardAmount: 3000,
    ),
    Mission(
      id: 'weekly_clear_50',
      missionType: MissionType.weekly,
      actionType: ActionType.clearStage,
      title: '주간 스테이지 클리어',
      description: '스테이지를 50회 클리어하세요',
      targetValue: 50,
      rewardType: RewardType.gem,
      rewardAmount: 80,
    ),
    Mission(
      id: 'weekly_kill_500',
      missionType: MissionType.weekly,
      actionType: ActionType.killMonster,
      title: '주간 몬스터 사냥',
      description: '몬스터를 500마리 처치하세요',
      targetValue: 500,
      rewardType: RewardType.gold,
      rewardAmount: 8000,
    ),
  ];

  static final List<Mission> _monthlyPool = [
    Mission(
      id: 'monthly_kill_2000',
      missionType: MissionType.monthly,
      actionType: ActionType.killMonster,
      title: '월간 몬스터 처치',
      description: '몬스터를 2000마리 처치하세요',
      targetValue: 2000,
      rewardType: RewardType.gold,
      rewardAmount: 30000,
    ),
    Mission(
      id: 'monthly_upgrade_60',
      missionType: MissionType.monthly,
      actionType: ActionType.upgrade,
      title: '월간 강화',
      description: '아무 능력치나 60회 강화하세요',
      targetValue: 60,
      rewardType: RewardType.gem,
      rewardAmount: 150,
    ),
    Mission(
      id: 'monthly_clear_200',
      missionType: MissionType.monthly,
      actionType: ActionType.clearStage,
      title: '월간 스테이지 클리어',
      description: '스테이지를 200회 클리어하세요',
      targetValue: 200,
      rewardType: RewardType.gem,
      rewardAmount: 300,
    ),
  ];
}
