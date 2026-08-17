import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/consumable_item_model.dart';
import '../utils/time_util.dart';
import 'consumable_manager.dart';
import 'game_manager.dart';

enum DailyRewardType { coin, dust, gem }

/// Manual-claim monthly attendance calendar: one grid cell per day of the
/// current month, reward type driven by weekday, plus 4 milestone chests at
/// 1/10/20/30 cumulative claimed days.
class MonthlyAttendanceManager extends ChangeNotifier {
  MonthlyAttendanceManager._internal();

  static final MonthlyAttendanceManager instance =
      MonthlyAttendanceManager._internal();

  static const List<int> boxMilestones = [1, 10, 20, 30];

  final Set<int> claimedDays = {};
  final Set<int> claimedBoxMilestones = {};
  String? _currentMonthKey;

  /// NTP 기준으로 마지막에 확인한 "지금" — [isDayClaimable]/
  /// [daysInCurrentMonth] 같은 동기 getter가 즉시 읽을 수 있도록 캐시해
  /// 둔다. 기기 시계(DateTime.now())를 직접 쓰면 하루씩 앞당겼다 되돌리는
  /// 식으로 한 달치(+마일스톤 상자 4개) 보상을 몇 분 만에 전부 파밍할 수
  /// 있었다 — 실제 지급([claimDay]/[claimBox])은 이 캐시가 아니라 항상
  /// 그 시점에 새로 받아온 NTP 시간으로 한 번 더 검증한다(GuildManager
  /// .checkIn()과 같은 "낙관적 로컬 판정 + 실제 처리는 NTP 재확인" 관례).
  DateTime _cachedNow = DateTime.now();

  Future<void> _refreshCachedNow() async {
    _cachedNow = await getNetworkTime();
  }

  /// [MonthlyAttendanceView]가 화면에 들어설 때 호출 — 앱을 오래 켜둔 채로
  /// 자정/월말을 넘긴 세션에서도 [_cachedNow](= "오늘" 표시 판정)가
  /// 최신 NTP 시간으로 갱신되게 한다. 순수 표시 갱신용이라, 이걸 안 불러도
  /// 실제 지급([claimDay]/[claimBox])의 보안성에는 영향이 없다 — 그
  /// 경로는 항상 이 시점의 캐시와 무관하게 새 NTP 시간으로 다시 검증한다.
  Future<void> refreshToday() => _checkMonthRollover();

  int get attendanceCount => claimedDays.length;

  int get daysInCurrentMonth => DateTime(_cachedNow.year, _cachedNow.month + 1, 0).day;

  /// Mon/Tue/Thu = coin, Wed/Fri = dust, Sat/Sun = gem.
  DailyRewardType rewardTypeForWeekday(int weekday) {
    switch (weekday) {
      case DateTime.monday:
      case DateTime.tuesday:
      case DateTime.thursday:
        return DailyRewardType.coin;
      case DateTime.wednesday:
      case DateTime.friday:
        return DailyRewardType.dust;
      default:
        return DailyRewardType.gem;
    }
  }

  int rewardAmountForType(DailyRewardType type) {
    switch (type) {
      case DailyRewardType.coin:
        return 500;
      case DailyRewardType.dust:
        return 20;
      case DailyRewardType.gem:
        return 5;
    }
  }

  bool isDayClaimed(int day) => claimedDays.contains(day);

  /// Only today is claimable — a past day that was never clicked is
  /// permanently missed (shown as a grey X in the calendar) rather than
  /// staying open for catch-up.
  bool isDayClaimable(int day) {
    return day == _cachedNow.day && !isDayClaimed(day);
  }

  Future<bool> claimDay(int day) async {
    await _checkMonthRollover();
    // 로컬 캐시가 아니라 지금 막 받아온 NTP 시간으로 다시 한 번 확인한다
    // — [isDayClaimable]은 UI가 즉시 읽는 낙관적 판정이라 기기 시계
    // 조작을 그대로 반영할 수 있다.
    final DateTime now = await getNetworkTime();
    _cachedNow = now;
    if (day != now.day || isDayClaimed(day)) {
      return false;
    }

    final DateTime target = DateTime(now.year, now.month, day);
    final DailyRewardType type = rewardTypeForWeekday(target.weekday);
    final int amount = rewardAmountForType(type);

    switch (type) {
      case DailyRewardType.coin:
        GameManager.instance.addGold(amount);
      case DailyRewardType.gem:
        GameManager.instance.addGems(amount);
      case DailyRewardType.dust:
        ConsumableManager.instance.addItem(ConsumableType.dust, amount);
    }

    claimedDays.add(day);
    notifyListeners();
    await _save();
    return true;
  }

  ConsumableType boxTypeForMilestone(int milestone) {
    switch (milestone) {
      case 1:
        return ConsumableType.normalBox;
      case 10:
        return ConsumableType.advancedBox;
      case 20:
        return ConsumableType.heroBox;
      default:
        return ConsumableType.legendaryBox;
    }
  }

  bool isBoxClaimed(int milestone) => claimedBoxMilestones.contains(milestone);

  bool canClaimBox(int milestone) =>
      attendanceCount >= milestone && !isBoxClaimed(milestone);

  Future<bool> claimBox(int milestone) async {
    await _checkMonthRollover();
    if (!canClaimBox(milestone)) {
      return false;
    }

    ConsumableManager.instance.addItem(boxTypeForMilestone(milestone), 1);
    claimedBoxMilestones.add(milestone);
    notifyListeners();
    await _save();
    return true;
  }

  /// [주의] 반드시 [getNetworkTime](NTP)을 써야 한다 — 기기 시계를 다음
  /// 달로 앞당겨 이번 달 보상을 전부 받은 뒤, 다시 이번 달로 되돌리면
  /// (이 롤오버 판정만 기기 시계를 썼을 경우) claimedDays/
  /// claimedBoxMilestones가 초기화돼 "이번 달"을 몇 번이고 다시 받을 수
  /// 있었다.
  Future<void> _checkMonthRollover() async {
    await _refreshCachedNow();
    final DateTime now = _cachedNow;
    final String monthKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    if (_currentMonthKey == monthKey) {
      return;
    }

    claimedDays.clear();
    claimedBoxMilestones.clear();
    _currentMonthKey = monthKey;
    notifyListeners();
    await _save();
  }

  static const String _saveKey = 'monthly_attendance_manager_save';

  Future<void> _save() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> data = {
      'currentMonthKey': _currentMonthKey,
      'claimedDays': claimedDays.toList(),
      'claimedBoxMilestones': claimedBoxMilestones.toList(),
    };
    await prefs.setString(_saveKey, jsonEncode(data));
  }

  Future<void> loadData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);

    if (raw != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
        _currentMonthKey = data['currentMonthKey'] as String?;

        final List<dynamic>? days = data['claimedDays'] as List<dynamic>?;
        if (days != null) {
          claimedDays
            ..clear()
            ..addAll(days.map((e) => e as int));
        }

        final List<dynamic>? boxes = data['claimedBoxMilestones'] as List<dynamic>?;
        if (boxes != null) {
          claimedBoxMilestones
            ..clear()
            ..addAll(boxes.map((e) => e as int));
        }
      } catch (error) {
        debugPrint('[MonthlyAttendanceManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
      }
    }

    await _checkMonthRollover();
    notifyListeners();
  }
}
