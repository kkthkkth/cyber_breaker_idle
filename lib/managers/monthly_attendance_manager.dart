import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/consumable_item_model.dart';
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

  int get attendanceCount => claimedDays.length;

  int get daysInCurrentMonth {
    final DateTime now = DateTime.now();
    return DateTime(now.year, now.month + 1, 0).day;
  }

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
    final int today = DateTime.now().day;
    return day == today && !isDayClaimed(day);
  }

  Future<bool> claimDay(int day) async {
    _checkMonthRollover();
    if (!isDayClaimable(day)) {
      return false;
    }

    final DateTime target = DateTime(DateTime.now().year, DateTime.now().month, day);
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
    _checkMonthRollover();
    if (!canClaimBox(milestone)) {
      return false;
    }

    ConsumableManager.instance.addItem(boxTypeForMilestone(milestone), 1);
    claimedBoxMilestones.add(milestone);
    notifyListeners();
    await _save();
    return true;
  }

  void _checkMonthRollover() {
    final DateTime now = DateTime.now();
    final String monthKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    if (_currentMonthKey == monthKey) {
      return;
    }

    claimedDays.clear();
    claimedBoxMilestones.clear();
    _currentMonthKey = monthKey;
    notifyListeners();
    _save();
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
    }

    _checkMonthRollover();
    notifyListeners();
  }
}
