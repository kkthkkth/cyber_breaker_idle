import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/quest_model.dart';
import '../utils/time_util.dart';
import 'potion_manager.dart';
import 'quest_manager.dart';
import 'supabase_manager.dart';

/// 월드보스("용의 동굴") 스케줄/티켓을 관장하는 싱글턴 — 이 프로젝트의
/// 다른 매니저들과 같은 관례를 따른다: **로컬(SharedPreferences)이
/// 게임플레이의 유일한 신뢰 소스**이고, Supabase는 그 위에 얹는 부가적인
/// 백업/동기화 계층이다.
///
/// [start] 호출 이후엔 1초마다 스스로 [isActive]/[timeRemaining]을
/// 재계산해 [notifyListeners]를 부른다 — 화면들은 각자 폴링 타이머를 두는
/// 대신 `AnimatedBuilder(animation: WorldBossManager.instance, ...)`로 그냥
/// 구독하기만 하면 실시간으로 갱신된다(등장 대기중 ↔ 등장중 전환도 이
/// 하나의 타이머가 감지해 [onBossAppeared]를 정확히 한 번만 쏜다).
class WorldBossManager extends ChangeNotifier with WidgetsBindingObserver {
  WorldBossManager._internal();

  static final WorldBossManager instance = WorldBossManager._internal();

  /// 하루 기본 도전 횟수 — "도전하기 (남은횟수/10회)" 표기와 일치.
  static const int maxDailyTickets = 10;

  /// world_boss_config에서 못 불러왔을 때 쓰는 기본값(요구사항 예시 그대로).
  List<int> scheduleHours = const [0, 6, 12, 18];
  int durationMinutes = 60;

  /// "초거대 수치" — world_boss_config.max_hp를 못 불러오면 쓰는 기본값.
  double maxHp = 100000000;

  int ticketsUsedToday = 0;
  int extraTickets = 0;

  /// 실시간 랭킹용 "이번 보스 리젠 회차" 누적 데미지 총합 — 자정이 아니라
  /// [currentSessionId]가 바뀔 때(=새 보스가 리젠될 때) [recordBattleDamage]
  /// 안에서 0으로 리셋된다.
  int totalDamageDealt = 0;

  /// 마지막으로 데미지를 기록했던 세션 ID(`yyyyMMdd_HH`) — 서버의
  /// `last_boss_session`을 그대로 로컬 미러링한다. [recordBattleDamage]가
  /// 이 값과 [currentSessionId]를 비교해 리젠 여부를 판정한다.
  String? _lastBossSession;

  /// 보상 정산 RPC를 이미 찔러본 마지막 세션 ID — [_maybeDistributeRewards]
  /// 가 같은 세션에 대해 매초 반복 호출하는 것을 막는 클라이언트 측 1회성
  /// 가드다(서버 RPC 자체도 중복 지급을 막아주지만, 그렇다고 매초 불필요한
  /// 네트워크 요청을 보낼 이유는 없다).
  String? _lastDistributedSessionId;

  String? _lastResetDate;

  bool _isActive = false;
  Duration _timeRemaining = Duration.zero;

  bool get isActive => _isActive;

  /// [isActive]면 이번 등장이 끝날 때까지 남은 시간, 아니면 다음 등장까지
  /// 남은 시간.
  Duration get timeRemaining => _timeRemaining;

  int get remainingTickets =>
      (maxDailyTickets + extraTickets - ticketsUsedToday).clamp(0, maxDailyTickets + extraTickets);

  /// 지금 이 순간이 속한 보스 리젠 회차 ID(`yyyyMMdd_HH`, 예: 2026년 8월
  /// 13일 12시 보스 = `20260813_12`) — 랭킹 조회([WorldBossRankingDialog])와
  /// 데미지 리셋 판정([recordBattleDamage]) 양쪽이 이 값 하나로 "같은
  /// 회차인지"를 판정한다.
  String get currentSessionId => sessionIdFor(scheduleHours: scheduleHours, now: DateTime.now());

  /// 대기중 → 등장중으로 "방금" 전환된 프레임에 정확히 한 번 호출된다 —
  /// [HomeScreen]이 이 콜백에 토스트를 연결한다(IndexedStack 덕에 항상
  /// 마운트돼 있어 다른 탭을 보는 중에도 알림이 뜬다).
  void Function()? onBossAppeared;

  Timer? _ticker;

  /// 단위 테스트 전용 — [_refreshStatus]가 실제로 부르는 판정/보상-정산
  /// 로직을 네트워크·타이머 없이 직접 한 번 돌려본다([PotionManager
  /// .debugSeedForTest]와 같은 관례). [onBossAppeared]는 호출하지 않는다
  /// (테스트에서 굳이 필요하면 그 콜백을 직접 assign해서 검증하면 된다).
  @visibleForTesting
  void debugRefreshStatusForTest() => _refreshStatus(fireCallback: false);

  /// 단위 테스트 전용 — [_lastDistributedSessionId]를 직접 읽고 쓴다.
  @visibleForTesting
  String? get debugLastDistributedSessionId => _lastDistributedSessionId;

  @visibleForTesting
  set debugLastDistributedSessionId(String? value) => _lastDistributedSessionId = value;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Fire-and-forget: the override signature must stay void/sync (same
      // convention as DungeonManager.didChangeAppLifecycleState).
      _checkAndResetDailyTickets();
    }
  }

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 채우고, 원격
  /// 설정/유저 데이터를 받아와 갱신을 시도한 뒤(실패해도 캐시로 계속
  /// 진행) 1초 타이머를 시작한다.
  Future<void> loadData() async {
    await _loadLocal();

    final Map<String, dynamic>? config = await SupabaseManager.instance.fetchWorldBossConfig();
    if (config != null) {
      final List<dynamic>? hours = config['schedule_hours'] as List<dynamic>?;
      if (hours != null && hours.isNotEmpty) {
        scheduleHours = hours.map((dynamic e) => (e as num).toInt()).toList();
      }
      durationMinutes = (config['duration_minutes'] as num?)?.toInt() ?? durationMinutes;
      maxHp = (config['max_hp'] as num?)?.toDouble() ?? maxHp;
    }

    final Map<String, dynamic>? userRow = await SupabaseManager.instance.fetchUserWorldBoss();
    if (userRow != null) {
      ticketsUsedToday = (userRow['tickets_used'] as num?)?.toInt() ?? ticketsUsedToday;
      extraTickets = (userRow['extra_tickets'] as num?)?.toInt() ?? extraTickets;
      totalDamageDealt = (userRow['total_damage_dealt'] as num?)?.toInt() ?? totalDamageDealt;
      final dynamic playedDate = userRow['last_played_date'];
      if (playedDate is String) {
        _lastResetDate = playedDate;
      }
      final dynamic bossSession = userRow['last_boss_session'];
      if (bossSession is String) {
        _lastBossSession = bossSession;
      }
    }

    await _checkAndResetDailyTickets();
    _refreshStatus(fireCallback: false);
    await _saveLocal();
    notifyListeners();

    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _refreshStatus());
  }

  void _refreshStatus({bool fireCallback = true}) {
    final bool wasActive = _isActive;
    final ({bool isActive, Duration remaining}) result = computeStatus(
      scheduleHours: scheduleHours,
      durationMinutes: durationMinutes,
      now: DateTime.now(),
    );
    _isActive = result.isActive;
    _timeRemaining = result.remaining;
    notifyListeners();

    if (fireCallback && !wasActive && _isActive) {
      onBossAppeared?.call();
    }

    _maybeDistributeRewardsForClosedSession();
  }

  /// [currentSessionId]가 가리키는 회차의 도전 창이 이미 닫혀 있는데
  /// (`!isActive`) 아직 그 회차에 대해 정산 RPC를 찔러본 적이 없다면
  /// ([_lastDistributedSessionId]와 다르면) 한 번 호출한다 — 매초 도는
  /// [_refreshStatus] 안에서 평가되므로, "등장중 → 대기중으로 막 전환된
  /// 순간"과 "앱을 켰더니 이미 지난 회차가 대기중이던 경우"를 똑같은
  /// 조건 하나로 함께 처리한다([currentSessionId]는 다음 리젠 전까지 같은
  /// 값을 유지하므로, 도전 창이 막 닫힌 시점에도 여전히 "방금 끝난 그
  /// 회차"를 가리킨다). Fire-and-forget — RPC가 DB 단에서 중복 지급을
  /// 막아주므로 실패해도 다음 틱/다음 유저가 다시 시도하면 된다.
  void _maybeDistributeRewardsForClosedSession() {
    if (_isActive) {
      return;
    }
    final String session = currentSessionId;
    if (_lastDistributedSessionId == session) {
      return;
    }
    _lastDistributedSessionId = session;
    unawaited(_saveLocal());
    unawaited(SupabaseManager.instance.distributeWorldBossRewards(session));
  }

  /// 순수 함수로 분리해 둔 실제 스케줄 판정 로직 — 네트워크/타이머 없이
  /// 바로 단위 테스트할 수 있다. [scheduleHours]는 정렬 여부를 가정하지
  /// 않는다(내부에서 직접 정렬).
  static ({bool isActive, Duration remaining}) computeStatus({
    required List<int> scheduleHours,
    required int durationMinutes,
    required DateTime now,
  }) {
    if (scheduleHours.isEmpty) {
      return (isActive: false, remaining: Duration.zero);
    }

    final List<int> sortedHours = List<int>.from(scheduleHours)..sort();

    for (final int hour in sortedHours) {
      final DateTime start = DateTime(now.year, now.month, now.day, hour);
      final DateTime end = start.add(Duration(minutes: durationMinutes));
      if (!now.isBefore(start) && now.isBefore(end)) {
        return (isActive: true, remaining: end.difference(now));
      }
    }

    for (final int hour in sortedHours) {
      final DateTime start = DateTime(now.year, now.month, now.day, hour);
      if (start.isAfter(now)) {
        return (isActive: false, remaining: start.difference(now));
      }
    }

    // 오늘 남은 등장이 없다 — 내일 첫 스케줄까지.
    final DateTime tomorrowFirst = DateTime(now.year, now.month, now.day + 1, sortedHours.first);
    return (isActive: false, remaining: tomorrowFirst.difference(now));
  }

  /// [now]가 속한 "가장 최근에 시작된" 보스 리젠 회차를 `yyyyMMdd_HH`
  /// 형식으로 돌려준다 — 등장 중이든(전투 가능) 이미 끝나고 다음 등장을
  /// 기다리는 중이든, 다음 리젠 전까지는 항상 같은 값을 돌려줘야 랭킹이
  /// "리젠마다"만 초기화된다([computeStatus]처럼 순수 함수라 단위 테스트가
  /// 쉽다).
  static String sessionIdFor({required List<int> scheduleHours, required DateTime now}) {
    if (scheduleHours.isEmpty) {
      return _formatSession(DateTime(now.year, now.month, now.day));
    }

    final List<int> sortedHours = List<int>.from(scheduleHours)..sort();

    DateTime? lastStart;
    for (final int hour in sortedHours) {
      final DateTime start = DateTime(now.year, now.month, now.day, hour);
      if (!start.isAfter(now)) {
        lastStart = start;
      }
    }
    // 오늘 첫 스케줄보다도 이른 시각(자정 직후)이면 어제의 마지막 회차가
    // 아직 "현재 회차"다.
    lastStart ??= DateTime(now.year, now.month, now.day - 1, sortedHours.last);

    return _formatSession(lastStart);
  }

  static String _formatSession(DateTime dateTime) {
    final String year = dateTime.year.toString().padLeft(4, '0');
    final String month = dateTime.month.toString().padLeft(2, '0');
    final String day = dateTime.day.toString().padLeft(2, '0');
    final String hour = dateTime.hour.toString().padLeft(2, '0');
    return '$year$month${day}_$hour';
  }

  /// 오늘의 도전 티켓 1개를 소비한다 — 남은 횟수가 없으면 false(아무것도
  /// 바꾸지 않음).
  Future<bool> consumeTicket() async {
    await _checkAndResetDailyTickets();
    if (remainingTickets <= 0) {
      return false;
    }
    ticketsUsedToday += 1;
    notifyListeners();
    await _saveLocal();
    _syncRemote();
    QuestManager.instance.updateProgress(QuestActionType.worldBossChallenge, 1);
    return true;
  }

  /// 인벤토리의 월드보스 입장 충전권([PotionManager]가 관리하는
  /// `item_type == 'ticket'` 소모품) 1개를 소비해 [extraTickets]를
  /// 올린다 — 재고가 없으면 false.
  Future<bool> chargeExtraTicket(String ticketItemId) async {
    final bool consumed = await PotionManager.instance.consumeItem(ticketItemId);
    if (!consumed) {
      return false;
    }
    extraTickets += 1;
    notifyListeners();
    await _saveLocal();
    _syncRemote();
    return true;
  }

  /// 방금 끝난 월드보스 전투(60초)에서 가한 누적 데미지를 이번 리젠
  /// 회차([currentSessionId])의 [totalDamageDealt]에 더해 로컬+서버에
  /// 반영한다 — [WorldBossBattleScreen]이 결과 팝업을 띄우기 직전에
  /// 호출한다. 로컬에 마지막으로 기록해 둔 회차([_lastBossSession])가
  /// 지금 회차와 다르면(=그 사이 보스가 새로 리젠됐다는 뜻) 합산 전에
  /// 먼저 0으로 리셋한다. [damage]가 0 이하면(공격이 한 번도 안 들어간
  /// 비정상 상황) 아무것도 바꾸지 않는다.
  Future<void> recordBattleDamage(double damage) async {
    if (damage <= 0) {
      return;
    }
    final String session = currentSessionId;
    if (_lastBossSession != session) {
      totalDamageDealt = 0;
      _lastBossSession = session;
    }
    totalDamageDealt += damage.round();
    notifyListeners();
    await _saveLocal();
    _syncRemote();
  }

  void _syncRemote() {
    unawaited(
      SupabaseManager.instance.upsertUserWorldBoss(
        ticketsUsed: ticketsUsedToday,
        extraTickets: extraTickets,
        playedDate: _lastResetDate ?? _formatDate(DateTime.now()),
        totalDamageDealt: totalDamageDealt,
        bossSession: _lastBossSession ?? currentSessionId,
      ),
    );
  }

  /// [DungeonManager.checkAndResetDailyCounts]와 동일한 관례 — 서버(NTP)
  /// 시간 기준 `yyyy-MM-dd` 커서가 오늘과 다르면(기기 시계 조작 방지)
  /// 사용 횟수/보너스 충전권을 0으로 되돌린다.
  Future<void> _checkAndResetDailyTickets() async {
    final DateTime now = await getNetworkTime();
    final String today = _formatDate(now);
    if (_lastResetDate == today) {
      return;
    }
    ticketsUsedToday = 0;
    extraTickets = 0;
    _lastResetDate = today;
    notifyListeners();
    await _saveLocal();
    _syncRemote();
  }

  static String _formatDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static const String _saveKey = 'world_boss_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode({
        'scheduleHours': scheduleHours,
        'durationMinutes': durationMinutes,
        'maxHp': maxHp,
        'ticketsUsedToday': ticketsUsedToday,
        'extraTickets': extraTickets,
        'totalDamageDealt': totalDamageDealt,
        'lastResetDate': _lastResetDate,
        'lastBossSession': _lastBossSession,
        'lastDistributedSessionId': _lastDistributedSessionId,
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
      final List<dynamic>? hours = data['scheduleHours'] as List<dynamic>?;
      if (hours != null && hours.isNotEmpty) {
        scheduleHours = hours.map((dynamic e) => (e as num).toInt()).toList();
      }
      durationMinutes = (data['durationMinutes'] as num?)?.toInt() ?? durationMinutes;
      maxHp = (data['maxHp'] as num?)?.toDouble() ?? maxHp;
      ticketsUsedToday = (data['ticketsUsedToday'] as num?)?.toInt() ?? ticketsUsedToday;
      extraTickets = (data['extraTickets'] as num?)?.toInt() ?? extraTickets;
      totalDamageDealt = (data['totalDamageDealt'] as num?)?.toInt() ?? totalDamageDealt;
      _lastResetDate = data['lastResetDate'] as String?;
      _lastBossSession = data['lastBossSession'] as String?;
      _lastDistributedSessionId = data['lastDistributedSessionId'] as String?;
    } catch (error) {
      debugPrint('[WorldBossManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }
  }
}
