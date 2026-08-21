import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/consumable_item_model.dart';
import '../models/equipment.dart';
import '../models/game_config_model.dart';
import '../utils/time_util.dart';
import 'battle_pass_manager.dart';
import 'consumable_manager.dart';
import 'equipment_manager.dart';
import 'game_manager.dart';
import 'monster_drop_manager.dart';
import 'rune_manager.dart';
import 'supabase_manager.dart';

class OfflineRewardManager with WidgetsBindingObserver {
  OfflineRewardManager._internal();

  static final OfflineRewardManager instance = OfflineRewardManager._internal();

  /// 최소 10분 이상 자리를 비웠을 때만 보상을 계산한다(요구사항: "오프라인
  /// 시간이 최소 10분 이상 지났을 때만"). 한때 웹(localhost) 테스트
  /// 편의를 위해 1분으로 낮춰뒀던 적이 있는데, 2026-08-21 요구사항에서
  /// 10분을 다시 명시적으로 요청해 원복했다 — 테스트 중 너무 안 뜬다
  /// 싶으면 이 상수 하나만 잠깐 낮추면 된다.
  static const int _minOfflineSeconds = 600;
  static const String _lastExitTimeKey = 'offline_reward_last_exit_time';

  /// [startPeriodicAutoSave]가 만드는 반복 타이머 — 웹(localhost 포함)은
  /// 탭을 그냥 닫을 때 [AppLifecycleState.paused]/[detached]가 신뢰성 있게
  /// 오지 않는 경우가 많아([didChangeAppLifecycleState] 문서 참고),
  /// 생명주기 이벤트 하나에만 의존하면 "마지막 접속 시각"이 훨씬 이전
  /// 값(마지막으로 resumed됐던 시점)에 멈춰 있을 수 있다. 이 타이머는
  /// 그와 무관하게 주기적으로 "지금"을 계속 저장해 둬서, 탭이 갑자기
  /// 죽어도 최소한 이 주기 이내의 오차로 마지막 접속 시각을 복구할 수
  /// 있게 한다.
  Timer? _periodicSaveTimer;

  /// Swappable at runtime once fetched from a real config endpoint — see
  /// [GameConfig.fromJson].
  GameConfig config = const GameConfig();

  /// Fired once a qualifying offline gap is measured. The UI layer (see
  /// main.dart) hooks this to show [OfflineRewardDialog]. [equipmentCount]/
  /// [consumableDrops] are the *expected* item-drop totals for the gap
  /// (see [MonsterDropTableManager.expectedDropsForKills]) — nothing is
  /// actually granted yet; that happens in [claimReward] once the player
  /// dismisses the popup, mirroring how [rewardGold] already worked.
  /// [bpExpGained]/[runeFragmentsGained]도 같은 관례 — 표시용으로 미리
  /// 계산해 넘기고, 실제 지급은 [claimReward]가 그대로 이어받는다(요구사항:
  /// "N시간 M분 동안 방치하여... 경험치(BP), 룬 조각(시간 비례)").
  void Function({
    required int offlineSeconds,
    required int rewardGold,
    required int equipmentCount,
    required Map<ConsumableType, int> consumableDrops,
    required int bpExpGained,
    required int runeFragmentsGained,
  })?
  onRewardCalculated;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _saveExitTime();
    } else if (state == AppLifecycleState.resumed) {
      checkOfflineReward();
    }
  }

  /// main()이 앱 시작 시 한 번 호출 — [_periodicSaveTimer] 문서 참고.
  ///
  /// [SupabaseManager.startLastSeenHeartbeat]와 달리 **즉시 한 번 쓰지
  /// 않는다** — 이 시점(main() 실행 중)엔 아직
  /// `_MainNavigationScreenState.initState()`의 [checkOfflineReward]가
  /// 실행되기 전이라, 여기서 곧바로 [_saveExitTime]을 부르면 "이전 세션이
  /// 남긴 마지막 접속 시각"이 "지금"으로 덮어써져 버려서
  /// [checkOfflineReward]가 실제 방치 시간을 영원히 0으로 계산하게 된다
  /// (실측 확인됨 — 매우 심각한 회귀였을 것). 그래서 첫 기록은 [interval]
  /// 이 한 번 지난 뒤부터 시작한다 — 그때는 이미 [checkOfflineReward]가
  /// 이전 값을 다 읽고 소비한 뒤이므로 안전하다. 중복 호출해도 안전하도록
  /// 기존 타이머가 있으면 먼저 취소한다(예: 핫 리스타트).
  void startPeriodicAutoSave({
    Duration interval = const Duration(seconds: 30),
  }) {
    _periodicSaveTimer?.cancel();
    _periodicSaveTimer = Timer.periodic(interval, (_) => _saveExitTime());
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
  /// background. Measures the offline gap and, if it clears the 10분 floor,
  /// fires [onRewardCalculated] with the computed gold/아이템 — actually
  /// crediting anything happens in [claimReward], only once the player taps
  /// through the popup. The exit-time marker is refreshed either way.
  Future<void> checkOfflineReward() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int? lastExitMillis = prefs.getInt(_lastExitTimeKey);

    final DateTime now = await getNetworkTime();
    await prefs.setInt(_lastExitTimeKey, now.millisecondsSinceEpoch);

    DateTime? lastExitTime = lastExitMillis != null
        ? DateTime.fromMillisecondsSinceEpoch(lastExitMillis)
        : null;

    // 이 기기에 로컬 종료 시각 기록이 없다(최초 실행/재설치/기기 변경 등)
    // — profiles.last_seen(길드 접속중 하트비트로 이미 관리되던 값,
    // SupabaseManager.updateLastSeen 참고)을 대체 기준 시각으로 써서, 그
    // 경우에도 오프라인 보상을 완전히 놓치지 않게 한다. 하트비트가 2분마다
    // 갱신되는 값이라 실제 종료 시각보다 최대 몇 분 앞설 수 있지만, 10분
    // 최소 문턱과 [offlineRewardEfficiency] 감쇠를 감안하면 무시할 수 있는
    // 오차다.
    lastExitTime ??= await SupabaseManager.instance.fetchLastSeen();

    if (lastExitTime == null) {
      return;
    }

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

    // highestReachedChapter의 몬스터를 처치했을 때 받는 골드(펫/길드/
    // 오버클럭/유물 보너스까지 반영, GameManager.offlineGoldPerMinute 참고)를
    // 기준으로 분당 획득량을 내고, 여기에 오프라인 시간을 곱한다.
    final double goldPerSecond = GameManager.instance.offlineGoldPerMinute / 60;
    final int rewardGold =
        (offlineSeconds * goldPerSecond * config.offlineRewardEfficiency)
            .round();

    final int estimatedKillCount =
        (GameManager.instance.estimatedKillsPerHour * offlineSeconds / 3600)
            .round();
    final ({int equipmentCount, Map<ConsumableType, int> consumables}) drops =
        MonsterDropTableManager.instance.expectedDropsForKills(
          killCount: estimatedKillCount,
          chapter: GameManager.instance.chapter,
          itemDropRate: GameManager.instance.itemDropRate,
        );

    // BP 경험치/룬 조각도 골드와 같은 "방치 시간에 정비례" 공식이다 —
    // 여기서 한 번만 계산해서 표시(팝업)와 지급([claimReward])이 항상
    // 같은 값을 쓰게 한다(예전엔 claimReward가 BP를 따로 다시 계산해서
    // 팝업에 안 보이는 채로 조용히 지급하고 있었다).
    final int bpExpGained =
        (offlineSeconds / 60 * BattlePassManager.bpExpPerOfflineMinute).round();
    final int runeFragmentsGained =
        (offlineSeconds / 60 * RuneManager.runeFragmentsPerOfflineMinute)
            .round();

    if (rewardGold > 0 ||
        drops.equipmentCount > 0 ||
        drops.consumables.isNotEmpty ||
        bpExpGained > 0 ||
        runeFragmentsGained > 0) {
      onRewardCalculated?.call(
        offlineSeconds: offlineSeconds,
        rewardGold: rewardGold,
        equipmentCount: drops.equipmentCount,
        consumableDrops: drops.consumables,
        bpExpGained: bpExpGained,
        runeFragmentsGained: runeFragmentsGained,
      );
    }
  }

  /// 팝업이 닫힌 뒤 실제로 보상을 지급한다 — [equipmentCount]개의 무작위
  /// 장비(현재 챕터 수준 등급 풀)와 [consumableDrops]에 담긴 소모품들을
  /// [MonsterDropTableManager.equipmentGradesForChapter]와 같은 기준으로
  /// 생성/지급한다. profiles.last_seen도 지금 시각으로 즉시 갱신한다
  /// (요구사항) — 2분 주기 하트비트를 기다리지 않고 바로 최신화해서, 이
  /// 방치 구간이 다시 이중으로 계산되는 일이 없게 한다. [bpExpGained]/
  /// [runeFragmentsGained]는 [checkOfflineReward]가 이미 계산해 넘긴
  /// 값을 그대로 지급한다(팝업에 보여준 숫자와 실제로 받는 숫자가 항상
  /// 같도록) — 활성 시즌이 없으면 BattlePassManager.addBpExp가, 0이면
  /// RuneManager.addFragments가 스스로 아무 일도 하지 않는다.
  ///
  /// [doubled]는 [OfflineRewardDialog]가 pop한 값 그대로다 — 광고를 끝까지
  /// 봤을 때만 true(요구사항: "광고 보고 보상 2배 수령"). 실제 지급 배율을
  /// 다이얼로그가 아니라 여기서 최종 확정하는 이유는, 다이얼로그의
  /// 카운트업 애니메이션이 보여주는 "진행 중인" 값이 아니라 사용자가
  /// 최종적으로 선택한 배율만 신뢰해야 하기 때문이다(둘이 서로 다른
  /// 소스를 보면 화면에 보인 숫자와 실제로 받은 재화가 어긋날 수 있다).
  void claimReward({
    required int rewardGold,
    required int offlineSeconds,
    int equipmentCount = 0,
    Map<ConsumableType, int> consumableDrops = const {},
    int bpExpGained = 0,
    int runeFragmentsGained = 0,
    bool doubled = false,
  }) {
    final int multiplier = doubled ? 2 : 1;
    GameManager.instance.addGold(rewardGold * multiplier);
    unawaited(SupabaseManager.instance.updateLastSeen());

    unawaited(BattlePassManager.instance.addBpExp(bpExpGained * multiplier));
    RuneManager.instance.addFragments(runeFragmentsGained * multiplier);

    final List<ItemGrade> grades =
        MonsterDropTableManager.equipmentGradesForChapter(
          GameManager.instance.chapter,
        );
    for (int i = 0; i < equipmentCount * multiplier; i++) {
      EquipmentManager.instance.generateGuaranteedLoot(grades);
    }

    consumableDrops.forEach((type, count) {
      final int total = count * multiplier;
      if (total > 0) {
        ConsumableManager.instance.addItem(type, total);
      }
    });
  }
}
