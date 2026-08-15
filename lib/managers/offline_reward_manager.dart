import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/consumable_item_model.dart';
import '../models/equipment.dart';
import '../models/game_config_model.dart';
import '../utils/time_util.dart';
import 'consumable_manager.dart';
import 'equipment_manager.dart';
import 'game_manager.dart';
import 'monster_drop_manager.dart';

class OfflineRewardManager with WidgetsBindingObserver {
  OfflineRewardManager._internal();

  static final OfflineRewardManager instance = OfflineRewardManager._internal();

  static const int _minOfflineSeconds = 60;
  static const String _lastExitTimeKey = 'offline_reward_last_exit_time';

  /// Swappable at runtime once fetched from a real config endpoint — see
  /// [GameConfig.fromJson].
  GameConfig config = const GameConfig();

  /// Fired once a qualifying offline gap is measured. The UI layer (see
  /// main.dart) hooks this to show [OfflineRewardDialog]. [equipmentCount]/
  /// [consumableDrops] are the *expected* item-drop totals for the gap
  /// (see [MonsterDropTableManager.expectedDropsForKills]) — nothing is
  /// actually granted yet; that happens in [claimReward] once the player
  /// dismisses the popup, mirroring how [rewardGold] already worked.
  void Function({
    required int offlineSeconds,
    required int rewardGold,
    required int equipmentCount,
    required Map<ConsumableType, int> consumableDrops,
  })?
  onRewardCalculated;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _saveExitTime();
    } else if (state == AppLifecycleState.resumed) {
      checkOfflineReward();
    }
  }

  /// [DateTime.now()](기기 시계) 대신 [getNetworkTime]을 쓰는 이유: 이
  /// 매니저는 "나간 시각"과 "돌아온 시각"의 차이만으로 보상을 계산하는데,
  /// 기기 시계는 사용자가 얼마든지 앞뒤로 조작할 수 있다 — 시계를 미래로
  /// 돌려놓고 앱을 나갔다 들어오면(또는 반대로 과거로 되감아 놓고 나갔다가
  /// 원래대로 돌려놓으면) 실제로는 몇 초도 안 지났는데 몇 시간어치 보상을
  /// 받거나, 음수 구간이 나올 수 있었다. 다른 매니저들(DungeonManager의
  /// 일일 초기화 등)이 전부 NTP 기준으로 "오늘 날짜"를 판정하는 것과 같은
  /// 이유 — 이 매니저만 예외적으로 기기 시계를 직접 썼던 것이 이번 점검에서
  /// 찾은 실질적인 문제였다(단, millisecondsSinceEpoch 기반 차이 계산
  /// 자체는 로컬/UTC 어느 쪽으로 만든 DateTime이든 절대 시각차만 보므로
  /// 애초에 "타임존 불일치" 버그는 없었다 — 진짜 문제는 시계 자체가
  /// 조작될 수 있다는 점이었다).
  Future<void> _saveExitTime() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final DateTime now = await getNetworkTime();
    await prefs.setInt(_lastExitTimeKey, now.millisecondsSinceEpoch);
  }

  /// Call on app start (see main.dart) and whenever the app resumes from the
  /// background. Measures the offline gap and, if it clears the 60s floor,
  /// fires [onRewardCalculated] with the computed gold/아이템 — actually
  /// crediting anything happens in [claimReward], only once the player taps
  /// through the popup. The exit-time marker is refreshed either way.
  Future<void> checkOfflineReward() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int? lastExitMillis = prefs.getInt(_lastExitTimeKey);

    final DateTime now = await getNetworkTime();
    await prefs.setInt(_lastExitTimeKey, now.millisecondsSinceEpoch);

    if (lastExitMillis == null) {
      return;
    }

    final DateTime lastExitTime = DateTime.fromMillisecondsSinceEpoch(lastExitMillis);
    final int rawOfflineSeconds = now.difference(lastExitTime).inSeconds;
    // 방어 코드: NTP 조회 자체가 실패해 기기 시계로 폴백했거나, 그 사이
    // 기기 시계가 되감겼다면 음수가 나올 수 있다 — 0 미만은 0으로,
    // [maxOfflineHours]를 넘는 값은 그 상한으로 잘라낸다(요구사항: "최대
    // 방치 한도 시간... 초과된 시간은 잘라내도록 Clamp").
    final int maxOfflineSeconds = config.maxOfflineHours * 3600;
    final int offlineSeconds = rawOfflineSeconds.clamp(0, maxOfflineSeconds);

    if (offlineSeconds < _minOfflineSeconds) {
      return;
    }

    final double goldPerSecond = GameManager.instance.goldPerHour / 3600;
    final int rewardGold =
        (offlineSeconds * goldPerSecond * config.offlineRewardEfficiency).round();

    final int estimatedKillCount =
        (GameManager.instance.estimatedKillsPerHour * offlineSeconds / 3600).round();
    final ({int equipmentCount, Map<ConsumableType, int> consumables}) drops =
        MonsterDropTableManager.instance.expectedDropsForKills(
          killCount: estimatedKillCount,
          chapter: GameManager.instance.chapter,
          itemDropRate: GameManager.instance.itemDropRate,
        );

    if (rewardGold > 0 || drops.equipmentCount > 0 || drops.consumables.isNotEmpty) {
      onRewardCalculated?.call(
        offlineSeconds: offlineSeconds,
        rewardGold: rewardGold,
        equipmentCount: drops.equipmentCount,
        consumableDrops: drops.consumables,
      );
    }
  }

  /// 팝업이 닫힌 뒤 실제로 보상을 지급한다 — [equipmentCount]개의 무작위
  /// 장비(현재 챕터 수준 등급 풀)와 [consumableDrops]에 담긴 소모품들을
  /// [MonsterDropTableManager.equipmentGradesForChapter]와 같은 기준으로
  /// 생성/지급한다.
  void claimReward({
    required int rewardGold,
    int equipmentCount = 0,
    Map<ConsumableType, int> consumableDrops = const {},
  }) {
    GameManager.instance.addGold(rewardGold);

    final List<ItemGrade> grades =
        MonsterDropTableManager.equipmentGradesForChapter(GameManager.instance.chapter);
    for (int i = 0; i < equipmentCount; i++) {
      EquipmentManager.instance.generateGuaranteedLoot(grades);
    }

    consumableDrops.forEach((type, count) {
      if (count > 0) {
        ConsumableManager.instance.addItem(type, count);
      }
    });
  }
}
