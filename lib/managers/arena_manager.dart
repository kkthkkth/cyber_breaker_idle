import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/arena_model.dart';
import '../models/quest_model.dart';
import '../utils/time_util.dart';
import 'game_manager.dart';
import 'quest_manager.dart';
import 'supabase_manager.dart';

/// 비동기 PvP 결투장("Arena")을 관장하는 싱글턴 — 이 프로젝트의 다른
/// 매니저들과 같은 관례를 따른다: **로컬(SharedPreferences)이 게임플레이의
/// 유일한 신뢰 소스**이고, Supabase는 그 위에 얹는 부가적인 백업/동기화
/// 계층이다.
///
/// [loadData] 호출 이후엔 [MidnightResetManager]와 같은 방식(다음 경계
/// 시각까지 정확히 한 번짜리 [Timer] 예약 → 발화 시 처리 → 재예약)으로
/// "다음 월요일 00시"를 기다렸다가 시즌 정산을 시도한다.
class ArenaManager extends ChangeNotifier with WidgetsBindingObserver {
  ArenaManager._internal();

  static final ArenaManager instance = ArenaManager._internal();

  static const int defaultScore = 1000;
  static const int winScoreGain = 20;
  static const int lossScoreLoss = 10;

  /// 도전 상대 후보를 고르는 점수 범위(±).
  static const int matchScoreRange = 200;

  int score = defaultScore;
  int wins = 0;
  int losses = 0;

  /// 클라이언트가 마지막으로 인지한 시즌 ID(`yyyy-Www`) — 서버 DB 컬럼이
  /// 아니라 순수 로컬 캐시다. [_checkWeeklySettlement]가 이 값과 지금
  /// 계산한 시즌 ID를 비교해 "그 사이 월요일이 지나갔는지"를 판정한다.
  String? _lastKnownSeasonId;

  Timer? _weeklyTimer;

  /// 단위 테스트 전용 — [_checkWeeklySettlement]를 네트워크/타이머 예약
  /// 없이 직접 한 번 돌려본다([WorldBossManager.debugRefreshStatusForTest]
  /// 와 같은 관례).
  @visibleForTesting
  Future<void> debugCheckWeeklySettlementForTest() => _checkWeeklySettlement();

  /// 단위 테스트 전용 — [_lastKnownSeasonId]를 직접 읽고 쓴다.
  @visibleForTesting
  String? get debugLastKnownSeasonId => _lastKnownSeasonId;

  @visibleForTesting
  set debugLastKnownSeasonId(String? value) => _lastKnownSeasonId = value;

  /// 공격력/최대체력을 하나의 비교 가능한 숫자로 뭉친 "전투력" — 서버의
  /// `user_arena.combat_power`에 동기화해 다른 유저가 나를 상대로
  /// 매칭/전투 시뮬레이션할 때 참조하게 한다. 공격력에 더 큰 가중치를 둬
  /// 딜러 위주 성장이 반영되게 했다(요구사항: "전투력과 공격력 스탯을
  /// 기반으로 승패가 나뉘도록").
  int get myCombatPower =>
      (GameManager.instance.attackPower * 2 + GameManager.instance.maxHp).round();

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 채우고, 서버에서
  /// 점수/승패 기록을 다시 확인한 뒤, 시즌 경계를 이미 지났는지 확인하고
  /// 다음 경계 타이머를 예약한다.
  Future<void> loadData() async {
    await _loadLocal();

    final Map<String, dynamic>? row = await SupabaseManager.instance.fetchMyArenaStats();
    if (row != null) {
      score = (row['score'] as num?)?.toInt() ?? score;
      wins = (row['wins'] as num?)?.toInt() ?? wins;
      losses = (row['losses'] as num?)?.toInt() ?? losses;
    }

    await _checkWeeklySettlement();
    await _saveLocal();
    notifyListeners();

    unawaited(syncCombatPower());
    unawaited(_scheduleNextWeeklyCheck());
  }

  /// 지금 계산한 [myCombatPower]를 서버에 반영한다 — [ArenaScreen]이 열릴
  /// 때마다 호출해, 다른 유저가 나를 상대로 매칭할 때 참조하는 값을
  /// 최신으로 유지한다.
  Future<void> syncCombatPower() {
    return SupabaseManager.instance.upsertMyArenaStats(
      score: score,
      wins: wins,
      losses: losses,
      combatPower: myCombatPower,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Fire-and-forget: the override signature must stay void/sync (same
      // convention as DungeonManager.didChangeAppLifecycleState).
      _checkWeeklySettlement();
    }
  }

  Future<void> _scheduleNextWeeklyCheck() async {
    _weeklyTimer?.cancel();
    final DateTime now = await getNetworkTime();
    final Duration delay = nextMondayMidnight(now).difference(now);
    _weeklyTimer = Timer(delay, () async {
      await _checkWeeklySettlement();
      unawaited(_scheduleNextWeeklyCheck());
    });
  }

  /// [now] 기준 다음 "월요일 00:00"(엄격히 이후)을 돌려준다 —
  /// [MidnightResetManager._durationUntilNextMidnight]과 같은 성격의
  /// 순수 계산이라 네트워크/타이머 없이 단위 테스트할 수 있다.
  static DateTime nextMondayMidnight(DateTime now) {
    final int daysUntilMonday = (DateTime.monday - now.weekday) % 7;
    DateTime candidate = DateTime(now.year, now.month, now.day + daysUntilMonday);
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 7));
    }
    return candidate;
  }

  /// [now]가 속한 ISO-8601 주차를 `yyyy-Www` 형식으로 돌려준다(예:
  /// 2026년 8월 17일(월)이 속한 주 = `2026-W34`). ISO 규칙대로, 그 주의
  /// 목요일이 속한 연도를 주차의 "연도"로 쓴다(연말/연초 경계에서 달력
  /// 연도와 어긋날 수 있는 걸 표준대로 처리하기 위함) — [computeStatus]
  /// 처럼 순수 함수라 네트워크/타이머 없이 단위 테스트할 수 있다.
  static String seasonIdFor(DateTime now) {
    final DateTime date = DateTime(now.year, now.month, now.day);
    final DateTime thursday = date.add(Duration(days: 4 - date.weekday));
    final DateTime firstDayOfYear = DateTime(thursday.year, 1, 1);
    final int weekNumber = (thursday.difference(firstDayOfYear).inDays / 7).floor() + 1;
    return '${thursday.year}-W${weekNumber.toString().padLeft(2, '0')}';
  }

  /// 시즌이 바뀌었는지 확인하고, 바뀌었다면(=그 사이 월요일 00시가
  /// 지났다면) 방금 끝난 시즌의 정산 RPC를 찌른 뒤 로컬 점수를
  /// [defaultScore]로 리셋한다. 앱을 처음 설치한 직후(=[_lastKnownSeasonId]
  /// 가 아직 없음)에는 "정산할 이전 시즌"이 없으므로 지금 시즌을 기준점으로
  /// 저장만 하고 RPC는 부르지 않는다 — 안 그러면 신규 유저마다 매번 불필요한
  /// 정산 요청이 나간다.
  Future<void> _checkWeeklySettlement() async {
    final DateTime now = await getNetworkTime();
    final String currentSeason = seasonIdFor(now);

    if (_lastKnownSeasonId == null) {
      _lastKnownSeasonId = currentSeason;
      await _saveLocal();
      return;
    }
    if (_lastKnownSeasonId == currentSeason) {
      return;
    }

    final String settledSeason = _lastKnownSeasonId!;
    _lastKnownSeasonId = currentSeason;
    score = defaultScore;
    notifyListeners();
    await _saveLocal();

    unawaited(SupabaseManager.instance.distributeArenaRewards(settledSeason));
    unawaited(syncCombatPower());
  }

  /// 내 점수 근처(±[matchScoreRange]) 상대 후보를 넉넉히 받아온 뒤
  /// 그중 3명을 무작위로 골라 돌려준다.
  Future<List<ArenaOpponent>> fetchOpponents() async {
    final List<Map<String, dynamic>> rows = await SupabaseManager.instance
        .fetchArenaOpponentCandidates(score);
    final List<ArenaOpponent> candidates = rows.map(ArenaOpponent.fromJson).toList()..shuffle();
    return candidates.take(3).toList();
  }

  /// 전투 결과를 반영한다 — 승리면 +[winScoreGain]점/[wins]+1, 패배면
  /// -[lossScoreLoss]점(0 밑으로는 안 내려감)/[losses]+1.
  Future<void> reportBattleResult({required bool won}) async {
    if (won) {
      score += winScoreGain;
      wins += 1;
    } else {
      score = score - lossScoreLoss;
      if (score < 0) {
        score = 0;
      }
      losses += 1;
    }
    notifyListeners();
    await _saveLocal();
    unawaited(
      SupabaseManager.instance.upsertMyArenaStats(
        score: score,
        wins: wins,
        losses: losses,
        combatPower: myCombatPower,
      ),
    );
    QuestManager.instance.updateProgress(QuestActionType.arenaBattle, 1);
  }

  /// [combatPower] 하나만 아는 상대를 실제로 때릴 수 있는 공격력/최대체력
  /// 값으로 환원한다 — [myCombatPower]와 같은 `attack*2 + hp` 비율을
  /// 그대로 거꾸로 풀어(공격력 25%, 체력 50%) 같은 전투력이면 나와 거의
  /// 대등하게 싸우도록 맞췄다.
  static ({double attack, double maxHp}) statsFromCombatPower(int combatPower) {
    return (attack: combatPower * 0.25, maxHp: combatPower * 0.5);
  }

  /// 1:1 자동 전투를 라운드 단위로 시뮬레이션한다 — 매 라운드 서로의
  /// 공격력만큼 상대 체력을 깎고, 둘 다 죽지 않은 라운드까지의 체력
  /// 변화 이력을 그대로 돌려줘서 [ArenaBattleScreen]이 그 이력을 따라
  /// 애니메이션을 재생할 수 있게 한다. 무한 라운드를 막기 위해
  /// [maxRounds]에서 강제 종료하며, 그 시점까지도 승부가 안 났으면(둘 다
  /// 생존) 더 높은 공격력 쪽이 이긴 것으로 판정한다 — 같은 라운드에 둘
  /// 다 죽으면 마찬가지로 더 높은 공격력 쪽이 이긴다(선제 타격 우세로
  /// 해석).
  static ({List<double> myHpHistory, List<double> opponentHpHistory, bool won}) simulateBattle({
    required double myAttack,
    required double myMaxHp,
    required double opponentAttack,
    required double opponentMaxHp,
    int maxRounds = 50,
  }) {
    final List<double> myHistory = [myMaxHp];
    final List<double> opponentHistory = [opponentMaxHp];
    double myHp = myMaxHp;
    double opponentHp = opponentMaxHp;

    for (int round = 0; round < maxRounds; round++) {
      myHp = (myHp - opponentAttack).clamp(0, myMaxHp);
      opponentHp = (opponentHp - myAttack).clamp(0, opponentMaxHp);
      myHistory.add(myHp);
      opponentHistory.add(opponentHp);
      if (myHp <= 0 || opponentHp <= 0) {
        break;
      }
    }

    // 승패가 명확한 두 경우(상대만 죽음 / 나만 죽음)를 먼저 가르고, 그
    // 외(둘 다 죽음 = 동시 KO, 둘 다 생존 = maxRounds 소진)는 전부 공격력
    // 비교로 판정한다.
    final bool won;
    if (myHp <= 0 && opponentHp > 0) {
      won = false;
    } else if (opponentHp <= 0 && myHp > 0) {
      won = true;
    } else {
      won = myAttack >= opponentAttack;
    }
    return (myHpHistory: myHistory, opponentHpHistory: opponentHistory, won: won);
  }

  static const String _saveKey = 'arena_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode({
        'score': score,
        'wins': wins,
        'losses': losses,
        'lastKnownSeasonId': _lastKnownSeasonId,
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
      score = (data['score'] as num?)?.toInt() ?? score;
      wins = (data['wins'] as num?)?.toInt() ?? wins;
      losses = (data['losses'] as num?)?.toInt() ?? losses;
      _lastKnownSeasonId = data['lastKnownSeasonId'] as String?;
    } catch (error) {
      debugPrint('[ArenaManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }
  }
}
