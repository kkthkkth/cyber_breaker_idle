import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mission_model.dart' show RewardType;
import 'game_manager.dart';

class AttendanceManager extends ChangeNotifier {
  AttendanceManager._internal();

  static final AttendanceManager instance = AttendanceManager._internal();

  static const int totalDays = 15;

  DateTime? lastLoginDate;
  int attendanceDays = 0;
  final Set<int> claimedDays = {};

  bool isClaimed(int day) => claimedDays.contains(day);
  bool isLocked(int day) => day > attendanceDays;
  bool canClaim(int day) => day == attendanceDays && !isClaimed(day);

  /// Drives the HUD red-dot: true iff today's day is reached and unclaimed.
  bool get hasClaimableReward => attendanceDays >= 1 && canClaim(attendanceDays);

  ({RewardType type, int amount}) rewardForDay(int day) {
    if (day % 5 == 0) {
      return (type: RewardType.gem, amount: 20 * (day ~/ 5));
    }
    return (type: RewardType.gold, amount: 200 * day);
  }

  static const String _saveKey = 'attendance_manager_save';

  /// Call once at app startup. Bumps [attendanceDays] the first time the
  /// player opens the app on a given calendar day.
  Future<void> checkDailyLogin() async {
    await _load();

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime? lastDay = lastLoginDate;

    final bool isNewDay = lastDay == null ||
        DateTime(lastDay.year, lastDay.month, lastDay.day).isBefore(today);

    if (isNewDay) {
      if (attendanceDays < totalDays) {
        attendanceDays++;
      }
      lastLoginDate = today;
      await _save();
    }

    notifyListeners();
  }

  Future<bool> claimReward(int day) async {
    if (!canClaim(day)) {
      return false;
    }

    final ({RewardType type, int amount}) reward = rewardForDay(day);
    switch (reward.type) {
      case RewardType.gold:
        GameManager.instance.addGold(reward.amount);
      case RewardType.gem:
        GameManager.instance.addGems(reward.amount);
    }

    claimedDays.add(day);
    await _save();
    notifyListeners();
    return true;
  }

  Future<void> _save() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> data = {
      'lastLoginDate': lastLoginDate?.millisecondsSinceEpoch,
      'attendanceDays': attendanceDays,
      'claimedDays': claimedDays.toList(),
    };
    await prefs.setString(_saveKey, jsonEncode(data));
  }

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      return;
    }

    final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
    attendanceDays = data['attendanceDays'] as int? ?? 0;

    final int? lastMillis = data['lastLoginDate'] as int?;
    lastLoginDate =
        lastMillis != null ? DateTime.fromMillisecondsSinceEpoch(lastMillis) : null;

    final List<dynamic>? claimed = data['claimedDays'] as List<dynamic>?;
    if (claimed != null) {
      claimedDays
        ..clear()
        ..addAll(claimed.map((e) => e as int));
    }
  }
}
