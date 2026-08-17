import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/quest_model.dart';
import '../utils/time_util.dart';
import 'battle_pass_manager.dart';
import 'supabase_manager.dart';

/// 일일 퀘스트(배틀패스 BM의 핵심 진행 축)를 관장하는 싱글턴 — 이
/// 프로젝트의 다른 매니저들과 같은 관례를 따른다: **로컬(SharedPreferences)
/// 이 유일한 신뢰 소스**이고, Supabase는 그 위에 얹는 부가적인 백업/동기화
/// 계층이다.
///
/// 기존에 이미 있던 [MissionManager]("일일 퀘스트" 탭, 완전히 로컬/골드·
/// 보석 보상)와는 별개의 새 시스템이다 — 이 매니저는 서버 `quests` 테이블
/// 카탈로그를 따르고, 보상이 배틀패스 BP 경험치([BattlePassManager
/// .addBpExp])로 들어간다는 점이 다르다. 기존 미션 시스템은 건드리지
/// 않았다.
///
/// [updateProgress]는 몬스터 처치처럼 아주 잦은 이벤트에서도 호출되므로,
/// 매 호출마다 네트워크 요청을 쏘지 않도록 서버 동기화를 짧게
/// 디바운스한다([_scheduleSync]) — 로컬 상태/배지는 항상 그 자리에서
/// 즉시 반영된다.
class QuestManager extends ChangeNotifier with WidgetsBindingObserver {
  QuestManager._internal();

  static final QuestManager instance = QuestManager._internal();

  static const Duration _syncDebounce = Duration(seconds: 2);

  List<Quest> _catalog = const [];
  final Map<String, QuestProgress> _progress = {};

  /// 일일 퀘스트([QuestPeriod.daily]) 리셋 커서 — 자정(NTP 기준)이 지나면
  /// 갱신된다.
  String? _lastResetDate;

  /// 주간 퀘스트([QuestPeriod.weekly]) 리셋 커서 — 그 주의 월요일 날짜
  /// (`yyyy-MM-dd`)를 키로 쓴다. 월요일이 지나면(=이번 주 월요일 키가
  /// 바뀌면) 주간 퀘스트만 리셋된다 — 일일 퀘스트와 완전히 독립된 별도
  /// 커서라 서로의 리셋 타이밍에 영향을 주지 않는다.
  String? _lastResetWeekKey;

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

  /// 단위 테스트 전용 — [_checkAndReset](일일+주간 둘 다)을 네트워크
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

  List<QuestDisplayItem> get questsWithProgress => [
    for (final Quest quest in _catalog)
      QuestDisplayItem(quest: quest, progress: _progress[quest.id] ?? QuestProgress.zero),
  ];

  List<QuestDisplayItem> get dailyQuests =>
      questsWithProgress.where((item) => item.quest.period == QuestPeriod.daily).toList();

  List<QuestDisplayItem> get weeklyQuests =>
      questsWithProgress.where((item) => item.quest.period == QuestPeriod.weekly).toList();

  /// 목표를 달성했지만 아직 수령하지 않은 퀘스트가 하나라도 있는지(일일+
  /// 주간 통틀어) — [QuestHudButton]의 빨간 뱃지가 이 값을 그대로 구독한다.
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
  /// 카탈로그/오늘(+이번 주) 진행도를 다시 확인한 뒤, 자정/월요일이
  /// 지났으면 각각 리셋한다.
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

    // 서버에서 받아온 값이 "오늘"/"이번 주"보다 오래된 값일 수도 있으므로,
    // 병합이 끝난 뒤에 리셋 여부를 다시 판정한다 — 리셋 대상이면 방금
    // 병합한 값도 전부 0으로 덮어써진다.
    await _checkAndReset();
    await _saveLocal();
    notifyListeners();
  }

  /// [actionType]에 해당하는(그리고 아직 수령 전인) 모든 퀘스트의 진행도를
  /// [amount]만큼 올린다(목표치에서 멈춘다). 게임 곳곳(GameManager 몬스터
  /// 처치, PotionManager 물약 사용, WorldBossManager 도전, ArenaManager
  /// 전투 등)에서 호출한다.
  void updateProgress(String actionType, int amount) {
    if (amount <= 0) {
      return;
    }
    bool changed = false;
    for (final Quest quest in _catalog) {
      if (quest.actionType != actionType) {
        continue;
      }
      final QuestProgress current = _progress[quest.id] ?? QuestProgress.zero;
      if (current.isClaimed || current.currentCount >= quest.targetCount) {
        continue;
      }
      final int nextCount = (current.currentCount + amount).clamp(0, quest.targetCount);
      _progress[quest.id] = current.copyWith(currentCount: nextCount);
      _dirtyQuestIds.add(quest.id);
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
  /// 없을 때 대기 중인 진행도 동기화를 즉시 흘려보낸다 — 그러지 않으면
  /// 타이머가 실제로 발화하기 전에 앱 프로세스가 죽어(백그라운드 킬/기기
  /// 재부팅 등) 마지막 몇 번의 진행도 증가분이 서버에 영원히 반영되지
  /// 않을 수 있다. 로컬 저장([_saveLocal])은 [updateProgress]에서 이미
  /// 즉시 끝나 있어 이 기기에서는 안전하지만, 이 플러시 없이는 재설치/기기
  /// 변경 시 그 몇 번의 증가분만큼 서버 값이 뒤처져 있을 수 있다.
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

  /// [questId] 퀘스트의 보상(BP 경험치)을 수령한다 — 목표 달성 전이거나
  /// 이미 수령했으면 아무것도 바꾸지 않고 false.
  Future<bool> claimQuest(String questId) async {
    Quest? quest;
    for (final Quest candidate in _catalog) {
      if (candidate.id == questId) {
        quest = candidate;
        break;
      }
    }
    if (quest == null) {
      return false;
    }
    final QuestProgress current = _progress[questId] ?? QuestProgress.zero;
    if (current.isClaimed || current.currentCount < quest.targetCount) {
      return false;
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
    await BattlePassManager.instance.addBpExp(quest.rewardBp);
    return true;
  }

  /// [DungeonManager.checkAndResetDailyCounts]와 동일한 관례 — 서버(NTP)
  /// 시간 기준 `yyyy-MM-dd` 커서가 오늘과 다르면(기기 시계 조작 방지)
  /// 모든 퀘스트 진행도를 0/미수령으로 되돌린다.
  ///
  /// 로컬 커서가 아예 없는 경우(최초 실행, 또는 재설치로 로컬 캐시만
  /// 사라진 경우)는 예외로 취급한다 — [loadData]가 이 메서드를 부르기
  /// 직전에 서버 `user_quests`를 이미 병합해 둔 상태라, 그 값이 실제로는
  /// "오늘" 진행도일 수도 있다(재설치 케이스). 무작정 지우면 재설치한
  /// 유저가 다른 기기/세션에서 이미 쌓아 둔 오늘의 진행도를 잃어버리므로,
  /// 이 경우엔 지우지 않고 오늘 날짜로 기준점만 잡는다([WorldBossManager
  /// ._maybeDistributeRewardsForClosedSession]/[ArenaManager
  /// ._checkWeeklySettlement]과 같은 "첫 관측은 베이스라인만" 관례).
  /// 일일 커서와 주간 커서를 각각 독립적으로 확인/리셋한다 — 자정만
  /// 지났으면 일일 퀘스트만, 월요일이 됐으면 주간 퀘스트만(자정도 같이
  /// 지났으면 둘 다) 리셋된다.
  Future<void> _checkAndReset() async {
    final DateTime now = await getNetworkTime();
    await _checkAndResetPeriod(
      period: QuestPeriod.daily,
      currentKey: _formatDate(now),
      lastKey: _lastResetDate,
      setLastKey: (value) => _lastResetDate = value,
    );
    await _checkAndResetPeriod(
      period: QuestPeriod.weekly,
      currentKey: _mondayKeyOf(now),
      lastKey: _lastResetWeekKey,
      setLastKey: (value) => _lastResetWeekKey = value,
    );
  }

  /// [DungeonManager.checkAndResetDailyCounts]와 동일한 관례 — 서버(NTP)
  /// 시간 기준 커서가 이전과 다르면(기기 시계 조작 방지) 해당 주기
  /// ([period])의 퀘스트 진행도만 0/미수령으로 되돌린다.
  ///
  /// 로컬 커서가 아예 없는 경우(최초 실행, 또는 재설치로 로컬 캐시만
  /// 사라진 경우)는 예외로 취급한다 — [loadData]가 이 메서드를 부르기
  /// 직전에 서버 `user_quests`를 이미 병합해 둔 상태라, 그 값이 실제로는
  /// "이번 주기" 진행도일 수도 있다(재설치 케이스). 무작정 지우면 재설치한
  /// 유저가 다른 기기/세션에서 이미 쌓아 둔 진행도를 잃어버리므로, 이
  /// 경우엔 지우지 않고 커서만 잡는다([WorldBossManager
  /// ._maybeDistributeRewardsForClosedSession]/[ArenaManager
  /// ._checkWeeklySettlement]과 같은 "첫 관측은 베이스라인만" 관례).
  Future<void> _checkAndResetPeriod({
    required QuestPeriod period,
    required String currentKey,
    required String? lastKey,
    required void Function(String) setLastKey,
  }) async {
    if (lastKey == currentKey) {
      return;
    }
    if (lastKey == null) {
      setLastKey(currentKey);
      await _saveLocal();
      return;
    }
    setLastKey(currentKey);

    final List<Quest> resetTargets =
        _catalog.where((quest) => quest.period == period).toList();
    for (final Quest quest in resetTargets) {
      _progress.remove(quest.id);
    }
    notifyListeners();
    await _saveLocal();

    // 서버도 같은 리셋 상태로 맞춘다 — 이 주기에 해당하는 퀘스트가 아직
    // 카탈로그에 없으면(예: 주간 카탈로그가 비어 있는 상태에서 daily만
    // 리셋되는 경우) 보낼 게 없으니 건너뛴다.
    if (resetTargets.isNotEmpty) {
      await SupabaseManager.instance.upsertUserQuestProgressBatch([
        for (final Quest quest in resetTargets)
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

  static const String _saveKey = 'quest_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode({
        'lastResetDate': _lastResetDate,
        'lastResetWeekKey': _lastResetWeekKey,
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
