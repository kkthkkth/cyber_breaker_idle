import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/consumable_item_model.dart';
import 'consumable_manager.dart';

/// Tracks the player's active game-speed boost. [activeSpeed] is 1 (no
/// boost) or 2/3 while a speed item's timer is running; [gameSpeedMultiplier]
/// is the same value exposed as a multiplier for callers that scale by it.
///
/// 남은 시간을 카운트다운으로만 들고 있으면 앱을 껐다 켰을 때(또는 오래
/// 백그라운드에 있다가 돌아왔을 때) 값을 복구할 기준이 없다 — 그래서
/// [_endTime](버프가 끝나는 절대 시각)을 진짜 소스로 두고, [remainingSeconds]
/// 는 매 틱 그 시각과 [DateTime.now]의 차이로 다시 계산되는 파생값이다.
class SpeedManager extends ChangeNotifier {
  SpeedManager._internal();

  static final SpeedManager instance = SpeedManager._internal();

  static const int _boostSeconds = 1800;
  static const String _saveKey = 'speed_manager_save';

  int gameSpeedMultiplier = 1;
  int activeSpeed = 1;
  int remainingSeconds = 0;

  /// 버프가 끝나는 절대 시각 — 저장/복구의 진짜 소스. 버프가 없으면 null.
  DateTime? _endTime;

  Timer? _timer;

  /// Activates (or extends) a 2x/3x speed boost by consuming one matching
  /// item. Returns false — without consuming anything — if a different
  /// speed is already active, or if the player has no item to spend.
  bool activate(int speed) {
    assert(speed == 2 || speed == 3);

    if (activeSpeed != 1 && activeSpeed != speed) {
      return false;
    }

    final ConsumableType type =
        speed == 2 ? ConsumableType.speed2x : ConsumableType.speed3x;
    if (!ConsumableManager.instance.consume(type)) {
      return false;
    }

    final DateTime now = DateTime.now();
    final DateTime base = (activeSpeed == speed && _endTime != null) ? _endTime! : now;
    activeSpeed = speed;
    gameSpeedMultiplier = speed;
    _endTime = base.add(const Duration(seconds: _boostSeconds));
    remainingSeconds = _endTime!.difference(now).inSeconds;

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
      final int secondsLeft = endTime.difference(DateTime.now()).inSeconds;

      if (secondsLeft <= 0) {
        await prefs.remove(_saveKey);
        return;
      }

      activeSpeed = savedSpeed;
      gameSpeedMultiplier = savedSpeed;
      _endTime = endTime;
      remainingSeconds = secondsLeft;
      _startTimer();
    } catch (error) {
      debugPrint('[SpeedManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
      return;
    }
    notifyListeners();
  }
}
