import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/consumable_item_model.dart';
import '../models/dungeon_reward_config_model.dart';
import '../models/quest_model.dart';
import '../models/weekday_dungeon_model.dart';
import '../utils/time_util.dart';
import 'consumable_manager.dart';
import 'dungeon_reward_manager.dart';
import 'game_manager.dart';
import 'guild_war_manager.dart';
import 'quest_manager.dart';
import 'skill_manager.dart';
import 'supabase_manager.dart';

/// 요일 던전(월~일 매일 다른 보상 던전) 입장 횟수/보상 지급을 관장하는
/// 싱글턴 — [DungeonManager]의 일일 티켓 관례(NTP 기준 자정 리셋)를
/// 그대로 따르되, 남은 입장 횟수를 서버(`daily_dungeon_entry`)에도
/// 동기화한다는 점만 다르다(요구사항: "유저별... 요일 던전 일일 남은
/// 입장 횟수를 저장할 테이블").
class WeekdayDungeonManager extends ChangeNotifier with WidgetsBindingObserver {
  WeekdayDungeonManager._internal();

  static final WeekdayDungeonManager instance = WeekdayDungeonManager._internal();

  static const int maxDailyFreeEntries = 3;

  /// 무료 입장을 다 쓴 뒤 보석으로 추가 입장하는 비용 — 다른 프리미엄
  /// 소비(가챠 1회 등)와 같은 가격대.
  static const int extraEntryCostGems = 100;

  /// 60초 제한 시간 안에서 처치할 몬스터 기본 체력 — 파도가 진행될수록
  /// [waveHpMultiplier]만큼 불어난다.
  static const double baseWaveMonsterHp = 150;
  static const double waveHpMultiplier = 0.15;

  /// 이 파도 수의 배수마다("5의 배수") 보스 파도 — 체력/보상 모두 2배.
  static const int bossWaveInterval = 5;
  static const double bossWaveMultiplier = 2.0;

  int remainingFreeEntries = maxDailyFreeEntries;
  int extraEntriesPurchasedToday = 0;

  String? _lastResetDate;

  /// NTP 기준으로 마지막에 확인한 "오늘의 요일"(1=월 ~ 7=일) —
  /// [checkAndResetDailyCounts]가 매번 갱신한다. [DateTime.now().weekday]를
  /// 직접 쓰면 기기 시계를 원하는 요일로 바꿔놓기만 해도 그날의 보상을
  /// 영구히 고정해서 받아갈 수 있었다(예: 항상 "토요일"로 맞춰 두면 매일
  /// 토요일 보상만 받음) — 반드시 서버(NTP) 시간을 거쳐야 한다. 앱을 아직
  /// 한 번도 [loadData]하지 않은 극초반(위젯 빌드 중 우연히 먼저 읽히는
  /// 경우 등)에만 기기 시계로 임시 폴백한다.
  int _cachedWeekday = DateTime.now().weekday;

  WeekdayDungeonConfig get todayConfig => WeekdayDungeonSchedule.configFor(_cachedWeekday);

  bool get canEnterFree => remainingFreeEntries > 0;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      checkAndResetDailyCounts();
    }
  }

  /// 무료 입장권 하나를 소모한다 — 없으면 false(아무것도 바꾸지 않음).
  Future<bool> consumeFreeEntry() async {
    await checkAndResetDailyCounts();
    if (remainingFreeEntries <= 0) {
      return false;
    }
    remainingFreeEntries--;
    notifyListeners();
    await _saveAndSync();
    return true;
  }

  /// 보석 [extraEntryCostGems]개를 소모해 추가 입장한다 — 보석이 부족하면
  /// false(재화도 차감되지 않음).
  Future<bool> consumeEntryWithGems() async {
    await checkAndResetDailyCounts();
    if (!GameManager.instance.spendGems(extraEntryCostGems)) {
      return false;
    }
    GuildWarManager.instance.reportTaxableSpend(gemSpent: extraEntryCostGems);
    extraEntriesPurchasedToday++;
    notifyListeners();
    await _saveAndSync();
    return true;
  }

  /// [waves]파도를 클리어했을 때(제한 시간 종료 시점) 오늘의 던전 종류에
  /// 맞는 보상을 실제로 지급한다 — [IdleGame]은 파도 수만 세고, 실제
  /// 재화 지급 로직은 요일별 분기가 있는 이 매니저가 전담한다.
  ({String label, int amount})? grantWaveReward(int waves) {
    if (waves <= 0) {
      return null;
    }
    // 주간 퀘스트("요일 던전 N회 클리어") 진행도 — 파도를 하나라도
    // 처치했으면(이 함수가 여기까지 왔으면) 성공한 클리어로 취급한다.
    QuestManager.instance.updateProgress(QuestActionType.weekdayDungeonClear, 1);

    final WeekdayDungeonRewardType type = todayConfig.rewardType;
    switch (type) {
      case WeekdayDungeonRewardType.gold:
        final int amount = waves * 200;
        GameManager.instance.addGold(amount);
        return (label: '골드', amount: amount);
      case WeekdayDungeonRewardType.gem:
        final int amount = waves * 3;
        GameManager.instance.addGems(amount);
        return (label: '보석', amount: amount);
      case WeekdayDungeonRewardType.enhanceStone:
        final int amount = waves * 5;
        ConsumableManager.instance.addItem(ConsumableType.enhanceStone, amount);
        return (label: '강화석', amount: amount);
      case WeekdayDungeonRewardType.runeFragment:
        // 하드코딩된 waves*8 대신 DungeonRewardManager(Supabase
        // dungeon_rewards_config 테이블) 기반으로 지급한다(요구사항:
        // "룬의 미궁: 클리어 시... DB 연동 로직을 통해 룬 조각을 지급").
        // 파도 하나당 한 번씩 독립적으로 굴려서, 파도를 많이 깰수록 더
        // 많은 기회를 준다는 기존 감각을 유지한다. 룬 조각은 이제 이
        // 경로가 유일한 획득처다(요구사항: "룬 조각 획득처를 명확히").
        int totalFragments = 0;
        for (int i = 0; i < waves; i++) {
          final List<DungeonRewardGrant> grants =
              DungeonRewardManager.instance.grantRewardsFor(DungeonRewardManager.runeLabyrinth);
          for (final DungeonRewardGrant grant in grants) {
            if (grant.itemType == DungeonRewardItemType.runeFragment) {
              totalFragments += grant.quantity;
            }
          }
        }
        return (label: '룬 조각', amount: totalFragments);
      case WeekdayDungeonRewardType.skillCurrency:
        final int amount = (waves / 3).ceil().clamp(1, 1 << 30);
        SkillManager.instance.addSkillPoints(amount);
        return (label: '스킬 포인트', amount: amount);
      case WeekdayDungeonRewardType.combined:
        // 토/일 "통합" 던전 — 평일 한 종류씩 몰아주는 대신 조금씩 전부
        // 지급한다(요구사항: "선택 또는 통합"). 룬 조각은 더 이상 여기서
        // 새지 않는다 — 룬의 미궁(목요일) 하나로 획득처를 명확히 하기
        // 위해 뺐다(요구사항: "일반 몬스터 사냥에서는... 절대 드랍되지
        // 않게" 연장선 — 이 통합 던전도 "룬 조각 전용" 던전은 아니므로).
        GameManager.instance.addGold(waves * 80);
        GameManager.instance.addGems((waves / 2).ceil());
        return (label: '골드·보석', amount: waves);
    }
  }

  /// 단위 테스트 전용 — 실제 일일 카운터를 네트워크 없이 직접 주입한다.
  @visibleForTesting
  void debugSeedForTest({int? remainingFreeEntries, int? extraEntriesPurchasedToday}) {
    if (remainingFreeEntries != null) {
      this.remainingFreeEntries = remainingFreeEntries;
    }
    if (extraEntriesPurchasedToday != null) {
      this.extraEntriesPurchasedToday = extraEntriesPurchasedToday;
    }
  }

  Future<void> checkAndResetDailyCounts() async {
    final DateTime now = await getNetworkTime();
    // 날짜가 안 바뀌어 아래 리셋이 스킵되는 호출에서도 요일 캐시는 항상
    // 최신 NTP 기준으로 다시 맞춘다 — 다만 날짜가 그대로면(_lastResetDate
    // == today) 같은 달력일이라 요일도 항상 그대로이므로, 실제로 값이
    // 바뀌는 건 자정을 실제로 넘겼을 때뿐이다.
    _cachedWeekday = now.weekday;
    final String today = _formatDate(now);
    if (_lastResetDate == today) {
      return;
    }

    remainingFreeEntries = maxDailyFreeEntries;
    extraEntriesPurchasedToday = 0;
    _lastResetDate = today;

    notifyListeners();
    await _saveAndSync();
  }

  static String _formatDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static const String _saveKey = 'weekday_dungeon_manager_save';

  Future<void> _saveAndSync() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode({
        'remainingFreeEntries': remainingFreeEntries,
        'extraEntriesPurchasedToday': extraEntriesPurchasedToday,
        'lastResetDate': _lastResetDate,
      }),
    );
    if (_lastResetDate != null) {
      unawaited(
        SupabaseManager.instance.upsertDailyDungeonEntry(
          date: _lastResetDate!,
          remainingFreeEntries: remainingFreeEntries,
          extraEntriesPurchased: extraEntriesPurchasedToday,
        ),
      );
    }
  }

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 채운 뒤, 서버에
  /// "오늘 날짜" 행이 있으면(다른 기기에서 이미 소모한 입장 횟수) 그
  /// 값을 신뢰한다.
  Future<void> loadData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
        remainingFreeEntries =
            data['remainingFreeEntries'] as int? ?? remainingFreeEntries;
        extraEntriesPurchasedToday =
            data['extraEntriesPurchasedToday'] as int? ?? extraEntriesPurchasedToday;
        _lastResetDate = data['lastResetDate'] as String?;
      } catch (error) {
        debugPrint('[WeekdayDungeonManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
      }
    }

    final DateTime now = await getNetworkTime();
    final String today = _formatDate(now);

    final Map<String, dynamic>? serverRow =
        await SupabaseManager.instance.fetchDailyDungeonEntry();
    if (serverRow != null && serverRow['entry_date'] == today) {
      remainingFreeEntries =
          (serverRow['remaining_free_entries'] as num?)?.toInt() ?? remainingFreeEntries;
      extraEntriesPurchasedToday =
          (serverRow['extra_entries_purchased'] as num?)?.toInt() ?? extraEntriesPurchasedToday;
      _lastResetDate = today;
    }

    await checkAndResetDailyCounts();
    notifyListeners();
  }
}
