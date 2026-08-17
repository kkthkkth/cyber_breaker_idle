import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/consumable_item_model.dart';
import '../utils/time_util.dart';
import 'consumable_manager.dart';

/// Tracks the player's active game-speed boost. [activeSpeed] is 1 (no
/// boost) or 2/3 while a speed item's timer is running; [gameSpeedMultiplier]
/// is the same value exposed as a multiplier for callers that scale by it.
///
/// 남은 시간을 카운트다운으로만 들고 있으면 앱을 껐다 켰을 때(또는 오래
/// 백그라운드에 있다가 돌아왔을 때) 값을 복구할 기준이 없다 — 그래서
/// [_endTime](버프가 끝나는 절대 시각)을 진짜 소스로 두고, [remainingSeconds]
/// 는 매 틱 그 시각과 [DateTime.now]의 차이로 다시 계산되는 파생값이다.
///
/// [주의] 매초 도는 [_tick]은 성능/배터리 때문에 매번 NTP를 확인할 수는
/// 없어 기기 시계([DateTime.now])로 남은 시간을 계산한다 — 그래서
/// [_resyncIntervalTicks]마다 한 번씩만 [getNetworkTime]으로 다시
/// 검증한다([_maybeResyncWithNetworkTime]). 소비된 아이템 하나로 받는
/// 30분 버프를 기기 시계를 뒤로 돌려 무한정 늘리는 걸 막되(재검증
/// 주기만큼만 유예), 매초 네트워크를 두드리는 비용은 피한다.
class SpeedManager extends ChangeNotifier {
  SpeedManager._internal();

  static final SpeedManager instance = SpeedManager._internal();

  static const int _boostSeconds = 1800;
  static const String _saveKey = 'speed_manager_save';

  /// 이 틱 수(=초)마다 한 번씩 NTP로 [_endTime]을 재검증한다.
  static const int _resyncIntervalTicks = 60;

  int gameSpeedMultiplier = 1;
  int activeSpeed = 1;
  int remainingSeconds = 0;

  /// 버프가 끝나는 절대 시각 — 저장/복구의 진짜 소스. 버프가 없으면 null.
  DateTime? _endTime;

  Timer? _timer;
  int _ticksSinceResync = 0;

  /// Activates (or extends) a 2x/3x speed boost by consuming one matching
  /// item. Returns false — without consuming anything — if a different
  /// speed is already active, or if the player has no item to spend.
  Future<bool> activate(int speed) async {
    assert(speed == 2 || speed == 3);

    if (activeSpeed != 1 && activeSpeed != speed) {
      return false;
    }

    final ConsumableType type =
        speed == 2 ? ConsumableType.speed2x : ConsumableType.speed3x;
    if (!ConsumableManager.instance.consume(type)) {
      return false;
    }

    // 소비 자체는 이미 확정됐으니, 이제부터의 버프 시각 계산만큼은 NTP
    // 기준으로 정확히 앵커링한다 — 기기 시계를 미래로 돌려놓고 활성화한
    // 뒤 되돌리는 식으로 시작 시각을 조작하는 걸 막는다.
    final DateTime now = await getNetworkTime();
    final DateTime base = (activeSpeed == speed && _endTime != null) ? _endTime! : now;
    activeSpeed = speed;
    gameSpeedMultiplier = speed;
    _endTime = base.add(const Duration(seconds: _boostSeconds));
    remainingSeconds = _endTime!.difference(now).inSeconds;
    _ticksSinceResync = 0;

    _startTimer();
    notifyListeners();
    _persist();
    return true;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) => _tick());
  }

  /// [_endTime] 기준으로 남은 시간을 다시 계산한다 — Timer.periodic이 앱이
  /// 백그라운드에 있는 동안 밀리거나 아예 안 돌았어도, 다음 틱에서 실제
  /// 경과 시간을 정확히 따라잡는다(단순 1초씩 빼는 방식이었다면 밀린 만큼
  /// 버프가 실제보다 더 오래 남아있는 것처럼 보였을 것).
  void _tick() {
    final DateTime? endTime = _endTime;
    if (endTime == null) {
      _timer?.cancel();
      _timer = null;
      return;
    }

    final int secondsLeft = endTime.difference(DateTime.now()).inSeconds;
    if (secondsLeft <= 0) {
      _clearBoost();
      _timer?.cancel();
      _timer = null;
      notifyListeners();
      _persist();
      return;
    }

    remainingSeconds = secondsLeft;
    notifyListeners();

    _ticksSinceResync++;
    if (_ticksSinceResync >= _resyncIntervalTicks) {
      _ticksSinceResync = 0;
      unawaited(_maybeResyncWithNetworkTime());
    }
  }

  /// [_resyncIntervalTicks]마다 한 번씩 실제 NTP 시간으로 [_endTime]을
  /// 다시 확인한다 — 그 사이 기기 시계를 뒤로 돌려 [_tick]의 로컬 계산이
  /// "아직 한참 남음"으로 착각하고 있었다면, 실제로는 이미 끝났어야 할
  /// 버프를 여기서 바로 정리한다.
  Future<void> _maybeResyncWithNetworkTime() async {
    final DateTime? endTime = _endTime;
    if (endTime == null) {
      return;
    }
    final DateTime now = await getNetworkTime();
    if (_endTime == null) {
      return; // 재검증하는 동안 다른 경로로 이미 정리됐다면 건드리지 않는다.
    }
    if (!now.isBefore(endTime)) {
      _clearBoost();
      _timer?.cancel();
      _timer = null;
      notifyListeners();
      await _persist();
      return;
    }
    remainingSeconds = endTime.difference(now).inSeconds;
    notifyListeners();
  }

  void _clearBoost() {
    activeSpeed = 1;
    gameSpeedMultiplier = 1;
    remainingSeconds = 0;
    _endTime = null;
  }

  Future<void> _persist() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final DateTime? endTime = _endTime;
    if (endTime == null) {
      await prefs.remove(_saveKey);
      return;
    }
    await prefs.setString(
      _saveKey,
      jsonEncode({
        'activeSpeed': activeSpeed,
        'endTimeMillis': endTime.millisecondsSinceEpoch,
      }),
    );
  }

  /// 앱 시작 시 한 번 호출 — 저장된 종료 시각이 아직 미래면 남은 시간만큼
  /// 타이머를 이어서 돌리고, 이미 지났으면 저장된 값을 지우고 1배속으로
  /// 둔다.
  Future<void> loadBoost() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      return;
    }

    try {
      final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
      final int? endTimeMillis = data['endTimeMillis'] as int?;
      final int? savedSpeed = data['activeSpeed'] as int?;
      if (endTimeMillis == null || savedSpeed == null) {
        await prefs.remove(_saveKey);
        return;
      }

      final DateTime endTime = DateTime.fromMillisecondsSinceEpoch(endTimeMillis);
      final DateTime now = await getNetworkTime();
      final int secondsLeft = endTime.difference(now).inSeconds;

      if (secondsLeft <= 0) {
        await prefs.remove(_saveKey);
        return;
      }

      activeSpeed = savedSpeed;
      gameSpeedMultiplier = savedSpeed;
      _endTime = endTime;
      remainingSeconds = secondsLeft;
      _ticksSinceResync = 0;
      _startTimer();
    } catch (error) {
      debugPrint('[SpeedManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
      return;
    }
    notifyListeners();
  }
}
