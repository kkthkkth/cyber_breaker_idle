import 'dart:async';

import '../utils/time_util.dart';
import 'dungeon_manager.dart';
import 'guild_manager.dart';
import 'guild_war_manager.dart';
import 'mission_manager.dart';
import 'weekday_dungeon_manager.dart';

/// Schedules a single [Timer] that fires exactly at the next local
/// midnight, applies the daily dungeon/mission resets, then reschedules
/// itself for the following midnight — so resets happen live while the app
/// stays in the foreground without ever polling per-frame or per-second.
class MidnightResetManager {
  MidnightResetManager._internal();

  static final MidnightResetManager instance =
      MidnightResetManager._internal();

  Timer? _midnightTimer;

  /// Call once at app startup.
  void start() {
    _scheduleMidnightReset();
  }

  Future<Duration> _durationUntilNextMidnight() async {
    final DateTime now = await getNetworkTime();
    final DateTime nextMidnight = DateTime(now.year, now.month, now.day + 1);
    return nextMidnight.difference(now);
  }

  Future<void> _scheduleMidnightReset() async {
    _midnightTimer?.cancel();
    final Duration delay = await _durationUntilNextMidnight();
    _midnightTimer = Timer(delay, () async {
      await DungeonManager.instance.checkAndResetDailyCounts();
      await MissionManager.instance.checkAndResetMissions();
      // 요일 던전의 "오늘 요일" 캐시도 여기서 새로 고쳐야, 백그라운드로
      // 내려가지 않고 자정을 넘긴 긴 세션에서도 다음 날 보상으로 즉시
      // 바뀐다(didChangeAppLifecycleState(resumed)만으로는 이 경우를 못
      // 잡는다).
      await WeekdayDungeonManager.instance.checkAndResetDailyCounts();
      // 길드 출석체크는 리셋할 카운터가 없어 "오늘" 캐시만 새로 고치면
      // 되지만, 그래야 화면을 나갔다 들어오지 않아도 정확히 이 순간
      // 출석체크 버튼이 즉시 활성화된다.
      await GuildManager.instance.checkAndResetCheckInStatus();
      // 길드 전쟁 정산 — 월요일(=일요일 자정이 막 지난 시점)에만 내부에서
      // 실제로 실행된다([GuildWarManager.checkAndSettleIfDue] 문서 참고).
      await GuildWarManager.instance.checkAndSettleIfDue();
      _scheduleMidnightReset();
    });
  }

  void dispose() {
    _midnightTimer?.cancel();
    _midnightTimer = null;
  }
}
