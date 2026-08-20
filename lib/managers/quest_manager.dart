import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/quest_model.dart';
import '../utils/time_util.dart';
import 'battle_pass_manager.dart';
import 'game_manager.dart';
import 'rune_manager.dart';
import 'supabase_manager.dart';

/// 일일/주간/월간 퀘스트(배틀패스 BM의 핵심 진행 축 중 하나)를 관장하는
/// 싱글턴 — 이 프로젝트의 다른 매니저들과 같은 관례를 따른다: **로컬
/// (SharedPreferences)이 유일한 신뢰 소스**이고, Supabase는 그 위에
/// 얹는 부가적인 백업/동기화 계층이다.
///
/// **DB 기반 무작위 배정 시스템** — `quest_catalog`은 유저별 상태가 없는
/// "풀(Pool)"일 뿐이다. 주기(일일/주간/월간)가 리셋될 때마다 그 풀에서
/// [_pickCount]개를 무작위로 뽑아 유저에게 "배정"하고, [_progress] 맵에
/// 해당 퀘스트 id가 키로 존재하는 것 자체가 "지금 배정되어 있음"을
/// 뜻한다 — 별도의 "배정 목록" 필드를 두지 않는다. 다음 리셋 때는 기존
/// 배정을 전부 지우고 다시 무작위로 뽑는다(진행 중이던 퀘스트라도 유지되지
/// 않는다 — 기존 일일/주간 리셋과 같은 관례).
///
/// 기존에 이미 있던 [MissionManager]("일일 퀘스트" 탭, 완전히 로컬/골드·
/// 보석 보상)와는 별개의 시스템이다 — 이 매니저는 서버 `quest_catalog`을
/// 따르고, 보상 종류가 [Quest.rewardType]에 따라 골드/보석/BP/룬 조각 등
/// 다양하다는 점이 다르다. 기존 미션 시스템은 건드리지 않았다.
///
/// [updateProgress]는 몬스터 처치처럼 아주 잦은 이벤트에서도 호출되므로,
/// 매 호출마다 네트워크 요청을 쏘지 않도록 서버 동기화를 짧게
/// 디바운스한다([_scheduleSync]) — 로컬 상태/배지는 항상 그 자리에서
/// 즉시 반영된다.
class QuestManager extends ChangeNotifier with WidgetsBindingObserver {
  QuestManager._internal();

  static final QuestManager instance = QuestManager._internal();

  static const Duration _syncDebounce = Duration(seconds: 2);

  /// 리셋 때마다 각 주기 풀에서 무작위로 뽑는 개수 — 요구사항: 일일 3개,
  /// 주간 3개, 월간 2개.
  static const int _dailyPickCount = 3;
  static const int _weeklyPickCount = 3;
  static const int _monthlyPickCount = 2;

  final Random _random = Random();

  List<Quest> _catalog = const [];
  final Map<String, QuestProgress> _progress = {};

  Map<String, Quest> get _catalogById => {for (final Quest quest in _catalog) quest.id: quest};

  /// 일일 퀘스트([QuestPeriod.daily]) 리셋 커서 — 자정(NTP 기준)이 지나면
  /// 갱신된다.
  String? _lastResetDate;

  /// 주간 퀘스트([QuestPeriod.weekly]) 리셋 커서 — 그 주의 월요일 날짜
  /// (`yyyy-MM-dd`)를 키로 쓴다. 월요일이 지나면(=이번 주 월요일 키가
  /// 바뀌면) 주간 퀘스트만 리셋된다.
  String? _lastResetWeekKey;

  /// 월간 퀘스트([QuestPeriod.monthly]) 리셋 커서 — 그 달의 `yyyy-MM`을
  /// 키로 쓴다. 1일이 지나면(=이번 달 키가 바뀌면) 월간 퀘스트만
  /// 리셋된다. 일일/주간 커서와 완전히 독립적이다.
  String? _lastResetMonthKey;

  Timer? _syncTimer;
  final Set<String> _dirtyQuestIds = {};

  /// 단위 테스트 전용 — 실제 카탈로그/진행도를 네트워크 없이 직접
  /// 주입한다([PotionManager.debugSeedForTest]와 같은 관례). 저장/서버
  /// 동기화는 건드리지 않는다.
  @visibleForTesting
  void debugSeedForTest({List<Quest>? catalog, Map<String, QuestProgress>? progress}) {
    if (catalog != null) {
      _catalog = catalog;
    }
    if (progress != null) {
      _progress
        ..clear()
        ..addAll(progress);
    }
  }

  /// 단위 테스트 전용 — [_checkAndReset](일일+주간+월간 전부)을 네트워크
  /// 폴백(NTP 실패 시 기기 시간)만으로 직접 한 번 돌려본다.
  @visibleForTesting
  Future<void> debugCheckAndResetForTest() => _checkAndReset();

  /// 단위 테스트 전용 — [_lastResetDate]를 직접 읽고 쓴다.
  @visibleForTesting
  String? get debugLastResetDate => _lastResetDate;

  @visibleForTesting
  set debugLastResetDate(String? value) => _lastResetDate = value;

  /// 단위 테스트 전용 — [_lastResetWeekKey]를 직접 읽고 쓴다.
  @visibleForTesting
  String? get debugLastResetWeekKey => _lastResetWeekKey;

  @visibleForTesting
  set debugLastResetWeekKey(String? value) => _lastResetWeekKey = value;

  /// 단위 테스트 전용 — [_lastResetMonthKey]를 직접 읽고 쓴다.
  @visibleForTesting
  String? get debugLastResetMonthKey => _lastResetMonthKey;

  @visibleForTesting
  set debugLastResetMonthKey(String? value) => _lastResetMonthKey = value;

  /// 지금 배정되어 있는(=[_progress]에 키가 존재하는) 퀘스트만 표시용으로
  /// 묶는다. 카탈로그에서 사라진(id를 못 찾는) 배정은 조용히 건너뛴다.
  List<QuestDisplayItem> get questsWithProgress {
    final Map<String, Quest> catalogById = _catalogById;
    return [
      for (final MapEntry<String, QuestProgress> entry in _progress.entries)
        if (catalogById[entry.key] case final Quest quest)
          QuestDisplayItem(quest: quest, progress: entry.value),
    ];
  }

  List<QuestDisplayItem> get dailyQuests =>
      questsWithProgress.where((item) => item.quest.period == QuestPeriod.daily).toList();

  List<QuestDisplayItem> get weeklyQuests =>
      questsWithProgress.where((item) => item.quest.period == QuestPeriod.weekly).toList();

  List<QuestDisplayItem> get monthlyQuests =>
      questsWithProgress.where((item) => item.quest.period == QuestPeriod.monthly).toList();

  /// 목표를 달성했지만 아직 수령하지 않은 퀘스트가 하나라도 있는지(일일+
  /// 주간+월간 통틀어) — [_DailyQuestHudButton]의 빨간 뱃지가 이 값을
  /// 그대로 구독한다.
  bool get hasClaimableQuest => questsWithProgress.any((item) => item.isClaimable);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Fire-and-forget: the override signature must stay void/sync (same
      // convention as DungeonManager.didChangeAppLifecycleState).
      _checkAndReset();
    }
  }

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 채우고, 서버에서
  /// 카탈로그/현재 배정을 다시 확인한 뒤, 자정/월요일/1일이 지났으면
  /// 각각 리셋(=재배정)한다.
  Future<void> loadData() async {
    await _loadLocal();

    final List<Map<String, dynamic>> catalogRows =
        await SupabaseManager.instance.fetchQuestCatalog();
    if (catalogRows.isNotEmpty) {
      _catalog = catalogRows.map(Quest.fromJson).toList();
    }

    final List<Map<String, dynamic>> progressRows =
        await SupabaseManager.instance.fetchUserQuests();
    for (final Map<String, dynamic> row in progressRows) {
      final String? questId = row['quest_id']?.toString();
      if (questId == null) {
        continue;
      }
      _progress[questId] = QuestProgress.fromJson(row);
    }

    // 서버에서 받아온 배정이 "이번 주기"보다 오래된 배정일 수도 있으므로,
    // 병합이 끝난 뒤에 리셋(재배정) 여부를 다시 판정한다.
    await _checkAndReset();
    await _saveLocal();
    notifyListeners();
  }

  /// [actionType]에 해당하는(그리고 아직 수령 전인) 지금 배정된 모든
  /// 퀘스트의 진행도를 [amount]만큼 올린다(목표치에서 멈춘다). 게임
  /// 곳곳(GameManager 몬스터 처치, PotionManager 물약 사용, WorldBossManager
  /// 도전, ArenaManager 전투, WeekdayDungeonManager 요일 던전 클리어,
  /// RuneManager 룬 제작/합성 등)에서 호출한다.
  void updateProgress(String actionType, int amount) {
    if (amount <= 0) {
      return;
    }
    final Map<String, Quest> catalogById = _catalogById;
    bool changed = false;
    for (final MapEntry<String, QuestProgress> entry in _progress.entries) {
      final Quest? quest = catalogById[entry.key];
      if (quest == null || quest.actionType != actionType) {
        continue;
      }
      final QuestProgress current = entry.value;
      if (current.isClaimed || current.currentCount >= quest.targetCount) {
        continue;
      }
      final int nextCount = (current.currentCount + amount).clamp(0, quest.targetCount);
      _progress[entry.key] = current.copyWith(currentCount: nextCount);
      _dirtyQuestIds.add(entry.key);
      changed = true;
    }
    if (!changed) {
      return;
    }
    notifyListeners();
    unawaited(_saveLocal());
    _scheduleSync();
  }

  void _scheduleSync() {
    _syncTimer ??= Timer(_syncDebounce, _flushSync);
  }

  /// 앱이 백그라운드로 내려가기 직전([MyApp.didChangeAppLifecycleState])
  /// 등, [_syncDebounce](2초) 타이머가 스스로 발화할 때까지 기다릴 여유가
  /// 없을 때 대기 중인 진행도 동기화를 즉시 흘려보낸다.
  Future<void> flushPendingSync() async {
    _syncTimer?.cancel();
    await _flushSync();
  }

  Future<void> _flushSync() async {
    _syncTimer = null;
    final List<String> ids = _dirtyQuestIds.toList();
    _dirtyQuestIds.clear();
    if (ids.isEmpty) {
      return;
    }
    await SupabaseManager.instance.upsertUserQuestProgressBatch([
      for (final String id in ids)
        if (_progress[id] case final QuestProgress progress)
          {'quest_id': id, 'current_count': progress.currentCount, 'is_claimed': progress.isClaimed},
    ]);
  }

  /// [questId] 퀘스트의 보상을 수령한다 — 목표 달성 전이거나 이미
  /// 수령했으면(또는 애초에 배정되어 있지 않으면) 아무것도 바꾸지 않고
  /// null. 성공하면 방금 수령한 [Quest]를 돌려준다 — 호출부(UI)가
  /// [Quest.rewardLabel]로 토스트 메시지를 만들 수 있도록.
  Future<Quest?> claimQuest(String questId) async {
    final Quest? quest = _catalogById[questId];
    if (quest == null) {
      return null;
    }
    final QuestProgress current = _progress[questId] ?? QuestProgress.zero;
    if (current.isClaimed || current.currentCount < quest.targetCount) {
      return null;
    }

    _progress[questId] = current.copyWith(isClaimed: true);
    notifyListeners();
    await _saveLocal();

    // 클레임은 디바운스하지 않는다 — 유저가 직접 누른 일회성 행동이라
    // 즉시 서버에 반영해야 한다.
    unawaited(
      SupabaseManager.instance.upsertUserQuestProgressBatch([
        {'quest_id': questId, 'current_count': quest.targetCount, 'is_claimed': true},
      ]),
    );
    await _grantReward(quest.rewardType, quest.rewardAmount);
    return quest;
  }

  /// [Quest.rewardType]에 맞는 매니저로 실제 재화를 지급한다 — 알 수 없는
  /// 타입은 게임을 죽이지 않고 로그만 남긴다([QuestRewardType] 참고).
  Future<void> _grantReward(String rewardType, int amount) async {
    if (amount <= 0) {
      return;
    }
    switch (rewardType) {
      case QuestRewardType.gold:
        GameManager.instance.addGold(amount);
      case QuestRewardType.gem:
        GameManager.instance.addGems(amount);
      case QuestRewardType.bp:
        await BattlePassManager.instance.addBpExp(amount);
      case QuestRewardType.runeFragment:
        RuneManager.instance.addFragments(amount);
      default:
        debugPrint('[QuestManager] 알 수 없는 보상 타입: $rewardType');
    }
  }

  /// 일일/주간/월간 커서를 각각 독립적으로 확인하고, 필요하면 해당
  /// 주기만 재배정한다.
  Future<void> _checkAndReset() async {
    final DateTime now = await getNetworkTime();
    await _checkAndResetPeriod(
      period: QuestPeriod.daily,
      currentKey: _formatDate(now),
      lastKey: _lastResetDate,
      setLastKey: (value) => _lastResetDate = value,
      pickCount: _dailyPickCount,
    );
    await _checkAndResetPeriod(
      period: QuestPeriod.weekly,
      currentKey: _mondayKeyOf(now),
      lastKey: _lastResetWeekKey,
      setLastKey: (value) => _lastResetWeekKey = value,
      pickCount: _weeklyPickCount,
    );
    await _checkAndResetPeriod(
      period: QuestPeriod.monthly,
      currentKey: _monthKeyOf(now),
      lastKey: _lastResetMonthKey,
      setLastKey: (value) => _lastResetMonthKey = value,
      pickCount: _monthlyPickCount,
    );
  }

  /// [DungeonManager.checkAndResetDailyCounts]와 동일한 관례 — 서버(NTP)
  /// 시간 기준 커서가 이전과 다르면(기기 시계 조작 방지) 해당 주기
  /// ([period])만 재배정한다.
  ///
  /// 로컬 커서가 아예 없는데(최초 실행, 또는 재설치로 로컬 캐시만 사라진
  /// 경우) 서버 병합으로 이미 이번 주기 배정이 있는 경우는 예외로 취급한다
  /// — [loadData]가 이 메서드를 부르기 직전에 서버 `user_quests`를 이미
  /// 병합해 둔 상태라, 그 배정이 실제로는 "이번 주기" 배정일 수도 있다
  /// (재설치 케이스). 무작정 다시 뽑으면 재설치한 유저가 다른 기기/세션에서
  /// 이미 쌓아 둔 진행도를 잃어버리므로, 이 경우엔 커서만 잡고 배정은
  /// 그대로 둔다([WorldBossManager._maybeDistributeRewardsForClosedSession]
  /// /[ArenaManager._checkWeeklySettlement]과 같은 "첫 관측은 베이스라인만"
  /// 관례).
  Future<void> _checkAndResetPeriod({
    required QuestPeriod period,
    required String currentKey,
    required String? lastKey,
    required void Function(String) setLastKey,
    required int pickCount,
  }) async {
    final bool cursorChanged = lastKey != currentKey;
    setLastKey(currentKey);

    final bool hasAssignment = _progress.keys.any(
      (id) => _catalogById[id]?.period == period,
    );

    if (!cursorChanged && hasAssignment) {
      return;
    }
    if (lastKey == null && hasAssignment) {
      await _saveLocal();
      return;
    }
    await _reassign(period, pickCount);
  }

  /// [period] 풀에서 [pickCount]개를 무작위로 새로 뽑아 유저에게 배정한다
  /// — 기존에 이 주기에 배정돼 있던 항목은 진행도까지 통째로 사라진다
  /// (같은 커서 안에서 다시 리셋될 일은 없으므로 안전하다).
  Future<void> _reassign(QuestPeriod period, int pickCount) async {
    final Map<String, Quest> catalogById = _catalogById;
    final List<String> oldIds = _progress.keys
        .where((id) => catalogById[id]?.period == period)
        .toList();
    for (final String id in oldIds) {
      _progress.remove(id);
    }

    final List<Quest> pool = _catalog.where((quest) => quest.period == period).toList()
      ..shuffle(_random);
    final List<Quest> picked = pool.take(pickCount).toList();
    for (final Quest quest in picked) {
      _progress[quest.id] = QuestProgress.zero;
    }

    notifyListeners();
    await _saveLocal();

    if (oldIds.isNotEmpty) {
      await SupabaseManager.instance.deleteUserQuestsByIds(oldIds);
    }
    if (picked.isNotEmpty) {
      await SupabaseManager.instance.upsertUserQuestProgressBatch([
        for (final Quest quest in picked)
          {'quest_id': quest.id, 'current_count': 0, 'is_claimed': false},
      ]);
    }
  }

  static String _formatDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  /// [date]가 속한 주(월요일 시작)의 월요일 날짜를 `yyyy-MM-dd`로 —
  /// [DateTime.weekday]는 월=1~일=7이라 `weekday - 1`일만큼 뒤로 가면
  /// 그 주의 월요일이 나온다.
  static String _mondayKeyOf(DateTime date) {
    final DateTime monday = date.subtract(Duration(days: date.weekday - 1));
    return _formatDate(monday);
  }

  /// [date]가 속한 달의 `yyyy-MM` 키.
  static String _monthKeyOf(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    return '${date.year}-$month';
  }

  static const String _saveKey = 'quest_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode({
        'lastResetDate': _lastResetDate,
        'lastResetWeekKey': _lastResetWeekKey,
        'lastResetMonthKey': _lastResetMonthKey,
        'progress': _progress.map(
          (key, value) => MapEntry(key, {
            'current_count': value.currentCount,
            'is_claimed': value.isClaimed,
          }),
        ),
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
      _lastResetDate = data['lastResetDate'] as String?;
      _lastResetWeekKey = data['lastResetWeekKey'] as String?;
      _lastResetMonthKey = data['lastResetMonthKey'] as String?;
      final Map<String, dynamic>? progressJson = data['progress'] as Map<String, dynamic>?;
      if (progressJson != null) {
        _progress.clear();
        progressJson.forEach((key, value) {
          _progress[key] = QuestProgress.fromJson(value as Map<String, dynamic>);
        });
      }
    } catch (error) {
      debugPrint('[QuestManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }
  }
}
