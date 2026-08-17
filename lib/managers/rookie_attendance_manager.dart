import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/rookie_attendance_model.dart';
import '../utils/time_util.dart';
import 'consumable_manager.dart';
import 'game_manager.dart';
import 'supabase_manager.dart';

/// 신규 유저 전용 7일 출석 트랙 — 기존 [AttendanceManager](15일, 기기
/// 시계 기반, 완전 로컬)와는 별개의 시스템이다. 두 가지가 다르다:
/// 1) [attendanceDays]가 "앱을 연 횟수"가 아니라 [startDate]로부터 실제로
///    지난 달력일 수로 계산된다 — 하루를 건너뛰어도 그 다음 접속 때
///    올바른 날짜로 정확히 따라잡는다(밀리지 않는다).
/// 2) [getNetworkTime](NTP)을 써서 기기 시계 조작으로 하루치를 앞당겨
///    받는 것을 막는다.
/// 3) [startDate]/[claimedDays]를 서버(`rookie_attendance`)에도 동기화해서,
///    재설치만으로 7일 트랙이 다시 시작되는 것을 막는다(서버에 이미
///    기록이 있으면 그 시작일을 그대로 신뢰한다).
class RookieAttendanceManager extends ChangeNotifier {
  RookieAttendanceManager._internal();

  static final RookieAttendanceManager instance = RookieAttendanceManager._internal();

  static const int totalDays = 7;

  DateTime? startDate;
  final Set<int> claimedDays = {};

  /// [loadData]가 계산해 캐싱하는 "오늘의 일차"(1~[totalDays]) — 매
  /// 프레임 다시 계산하지 않고, 앱 시작 시 한 번 확정한다(다른 일일
  /// 매니저들과 같은 관례 — 자정을 걸쳐 오래 켜두는 세션은 다음 재시작
  /// 때 반영된다).
  int _todayIndex = 1;
  int get attendanceDays => _todayIndex;

  bool isClaimed(int day) => claimedDays.contains(day);
  bool isLocked(int day) => day > attendanceDays;
  bool canClaim(int day) => day <= attendanceDays && !isClaimed(day);

  /// HUD 빨간 점 — 지금 받을 수 있는 날짜가 하나라도 있으면 true.
  bool get hasClaimableReward =>
      List.generate(totalDays, (i) => i + 1).any(canClaim);

  /// 7일을 전부 수령했으면(더 이상 이 출석부로 할 게 없으면) true — 화면
  /// 진입점에서 "졸업" 안내로 갈아탈 때 쓸 수 있다.
  bool get isCompleted => claimedDays.length >= totalDays;

  RookieAttendanceReward rewardForDay(int day) => RookieAttendanceSchedule.rewardForDay(day);

  /// 단위 테스트 전용 — 실제 시작일/수령 이력을 네트워크 없이 직접
  /// 주입한다.
  @visibleForTesting
  void debugSeedForTest({DateTime? startDate, int? todayIndex, Set<int>? claimedDays}) {
    if (startDate != null) {
      this.startDate = startDate;
    }
    if (todayIndex != null) {
      _todayIndex = todayIndex;
    }
    if (claimedDays != null) {
      this.claimedDays
        ..clear()
        ..addAll(claimedDays);
    }
  }

  /// [now] 기준으로 [startDate]로부터 며칠째인지(1부터, [totalDays]에서
  /// 캡) — 순수 함수라 테스트하기 쉽다.
  @visibleForTesting
  int computeDayIndex(DateTime now) {
    final DateTime start = startDate!;
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime startDay = DateTime(start.year, start.month, start.day);
    final int elapsed = today.difference(startDay).inDays;
    return (elapsed + 1).clamp(1, totalDays);
  }

  Future<bool> claimReward(int day) async {
    if (!canClaim(day)) {
      return false;
    }

    final RookieAttendanceReward reward = rewardForDay(day);
    switch (reward.kind) {
      case RookieRewardKind.gold:
        GameManager.instance.addGold(reward.amount);
      case RookieRewardKind.gem:
        GameManager.instance.addGems(reward.amount);
      case RookieRewardKind.consumable:
        if (reward.consumableType != null) {
          ConsumableManager.instance.addItem(reward.consumableType!, reward.consumableAmount);
        }
    }

    claimedDays.add(day);
    notifyListeners();
    await _saveLocal();
    unawaited(_syncRemote());
    return true;
  }

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 채운 뒤, 서버에
  /// 이미 시작일이 있으면 그쪽을(더 이른 쪽을) 신뢰하고, 수령 이력은
  /// 로컬/서버 합집합으로 병합한다(둘 중 어느 한쪽에서라도 이미
  /// 지급됐다면 다시 지급하지 않는다).
  Future<void> loadData() async {
    await _loadLocal();

    final Map<String, dynamic>? serverRow =
        await SupabaseManager.instance.fetchRookieAttendance();
    if (serverRow != null) {
      final String? serverStartRaw = serverRow['start_date'] as String?;
      if (serverStartRaw != null) {
        final DateTime? serverStart = DateTime.tryParse(serverStartRaw);
        if (serverStart != null && (startDate == null || serverStart.isBefore(startDate!))) {
          startDate = serverStart;
        }
      }
      final List<dynamic>? serverClaimed = serverRow['claimed_days'] as List<dynamic>?;
      if (serverClaimed != null) {
        claimedDays.addAll(serverClaimed.map((entry) => (entry as num).toInt()));
      }
    }

    final DateTime now = await getNetworkTime();
    // 이 기기/계정에서 처음 관측되는 순간 — 오늘을 1일차로 시작한다.
    startDate ??= DateTime(now.year, now.month, now.day);
    _todayIndex = computeDayIndex(now);

    await _saveLocal();
    unawaited(_syncRemote());
    notifyListeners();
  }

  Future<void> _syncRemote() async {
    final DateTime? start = startDate;
    if (start == null) {
      return;
    }
    await SupabaseManager.instance.upsertRookieAttendance(
      startDate: _formatDate(start),
      claimedDays: claimedDays.toList(),
    );
  }

  static String _formatDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static const String _saveKey = 'rookie_attendance_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode({
        'startDate': startDate?.millisecondsSinceEpoch,
        'claimedDays': claimedDays.toList(),
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
      final int? startMillis = data['startDate'] as int?;
      startDate = startMillis != null ? DateTime.fromMillisecondsSinceEpoch(startMillis) : null;
      final List<dynamic>? claimed = data['claimedDays'] as List<dynamic>?;
      if (claimed != null) {
        claimedDays
          ..clear()
          ..addAll(claimed.map((entry) => entry as int));
      }
    } catch (error) {
      debugPrint('[RookieAttendanceManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }
  }
}
