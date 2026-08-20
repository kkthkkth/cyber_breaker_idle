import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/guild_boss_model.dart';
import '../utils/time_util.dart';
import 'guild_manager.dart';
import 'supabase_manager.dart';

/// 길드 레이드(공유 보스) 탭이 쓰는 싱글턴 — [GuildManager]와 달리 보스
/// 체력([boss])은 길드원 전원이 공유하는 상태라 로컬에 캐시하지 않고
/// 매번 서버에서 최신값을 받아온다([GuildManager.members]와 같은 성격).
/// 로컬에 남는 건 "오늘 몇 번 도전했는지"(개인별 카운터, [DungeonManager]
/// 류의 다른 일일 카운터와 같은 관례)뿐이다.
///
/// 공격([submitDamage])은 `guild_boss_attack` RPC 하나로 원자적으로
/// 처리된다 — 여러 길드원이 거의 동시에 공격해도 데미지가 유실되지 않고,
/// 보스가 죽는 순간의 다음 레벨 스폰/참여자 길드 주화 지급까지 그 RPC
/// 안에서 전부 끝난다([SupabaseManager.attackGuildBoss] 문서 참고).
class GuildRaidManager extends ChangeNotifier {
  GuildRaidManager._internal();

  static final GuildRaidManager instance = GuildRaidManager._internal();

  /// 유저 1인당 하루 최대 도전 횟수.
  static const int maxDailyAttempts = 2;

  /// 서버에 아직 이 길드의 보스 행이 없을 때(최초 진입) 클라이언트가
  /// 임시로 보여줄 1레벨 기본값 — 실제 값은 [refreshBoss]가 서버에서
  /// 받아오는 순간 덮어써진다. [GuildBoss.defaultMaxHp]와 값을 공유한다
  /// (그쪽은 서버 응답 자체가 손상됐을 때의 폴백, 이쪽은 행이 아예 없을
  /// 때의 폴백 — 두 경우 모두 같은 기본값을 쓰는 게 자연스러워 상수를
  /// 하나로 합쳤다).
  static const int defaultBossMaxHp = GuildBoss.defaultMaxHp;

  GuildBoss? boss;
  int remainingAttemptsToday = maxDailyAttempts;
  String? _lastResetDate;

  bool get hasAttemptsLeft => remainingAttemptsToday > 0;

  /// 단위 테스트 전용 — 실제 네트워크 없이 상태를 직접 주입한다
  /// ([RookieAttendanceManager.debugSeedForTest]와 같은 관례).
  @visibleForTesting
  void debugSeedForTest({GuildBoss? boss, int? remainingAttemptsToday, String? lastResetDate}) {
    if (boss != null) {
      this.boss = boss;
    }
    if (remainingAttemptsToday != null) {
      this.remainingAttemptsToday = remainingAttemptsToday;
    }
    if (lastResetDate != null) {
      _lastResetDate = lastResetDate;
    }
  }

  /// 단위 테스트 전용 — [checkAndResetDailyAttempts]를 네트워크 없이 직접
  /// 한 번 돌려본다.
  @visibleForTesting
  Future<void> debugCheckAndResetForTest(DateTime now) => _checkAndResetDailyAttempts(now);

  /// 단위 테스트 전용 — [_lastResetDate]를 직접 읽고 쓴다(null로도 되돌릴
  /// 수 있어 "첫 관측" 분기를 테스트할 수 있다).
  @visibleForTesting
  String? get debugLastResetDate => _lastResetDate;

  @visibleForTesting
  set debugLastResetDate(String? value) => _lastResetDate = value;

  /// main()이 앱 시작 시 한 번 호출 — 로컬 도전 횟수 카운터만 복원한다
  /// (보스 자체는 길드 탭에 실제로 들어갈 때 [refreshBoss]가 받아온다).
  Future<void> loadData() async {
    await _loadLocal();
    final DateTime now = await getNetworkTime();
    await _checkAndResetDailyAttempts(now);
    notifyListeners();
  }

  /// [DungeonManager.checkAndResetDailyCounts]와 동일한 관례 — 서버(NTP)
  /// 기준 날짜가 바뀌었으면 도전 횟수를 초기화한다. 로컬 커서가 없으면
  /// (최초 실행) 지우지 않고 기준점만 잡는다.
  Future<void> _checkAndResetDailyAttempts(DateTime now) async {
    final String today = _formatDate(now);
    if (_lastResetDate == today) {
      return;
    }
    final bool isFirstObservation = _lastResetDate == null;
    _lastResetDate = today;
    if (!isFirstObservation) {
      remainingAttemptsToday = maxDailyAttempts;
    }
    notifyListeners();
    await _saveLocal();
  }

  /// 길드 레이드 탭에 들어설 때마다 호출 — 다른 길드원의 공격으로 바뀐
  /// 보스 체력을 최신으로 받아온다. 서버에 아직 이 길드의 보스 행이 없으면
  /// (최초 진입) [defaultBossMaxHp]짜리 1레벨 보스로 취급한다 — 실제
  /// 행은 첫 공격([submitDamage])이 `guild_boss_attack` RPC를 통해 서버에서
  /// 만든다.
  Future<void> refreshBoss() async {
    final String? guildId = GuildManager.instance.guildId;
    if (guildId == null) {
      return;
    }
    final DateTime now = await getNetworkTime();
    await _checkAndResetDailyAttempts(now);

    final Map<String, dynamic>? row = await SupabaseManager.instance.fetchGuildBoss(guildId);
    boss = row != null
        ? GuildBoss.fromJson(row)
        : GuildBoss(guildId: guildId, level: 1, maxHp: defaultBossMaxHp, currentHp: defaultBossMaxHp);
    notifyListeners();
  }

  /// 도전 1회를 소모한다 — 오늘 이미 [maxDailyAttempts]번 다 썼으면 false
  /// (아무것도 바꾸지 않음).
  Future<bool> consumeAttempt() async {
    final DateTime now = await getNetworkTime();
    await _checkAndResetDailyAttempts(now);
    if (!hasAttemptsLeft) {
      return false;
    }
    remainingAttemptsToday -= 1;
    notifyListeners();
    await _saveLocal();
    return true;
  }

  /// 전투 종료 시점에 이번 도전에서 누적한 총 데미지([totalDamage])를
  /// 서버에 한 번에 제출한다 — RPC가 성공하면 [boss]를 응답값으로 갱신하고,
  /// 이번 공격으로 보스가 죽어 내게 길드 주화가 지급됐다면([coinReward] >
  /// 0) [GuildManager.addGuildCoins]로 로컬 잔액도 즉시 반영한다. 실패
  /// (오프라인 등)하면 null — 호출부([GuildRaidScreen])가 "결과 반영 실패"
  /// 안내를 보여줄 수 있다.
  Future<GuildBossAttackResult?> submitDamage(int totalDamage) async {
    final String? guildId = GuildManager.instance.guildId;
    if (guildId == null || totalDamage <= 0) {
      return null;
    }
    final GuildBossAttackResult? result = await SupabaseManager.instance.attackGuildBoss(
      guildId: guildId,
      damage: totalDamage,
    );
    if (result == null) {
      return null;
    }
    boss = GuildBoss(
      guildId: guildId,
      level: result.newLevel,
      maxHp: result.newMaxHp,
      currentHp: result.newCurrentHp,
    );
    if (result.coinReward > 0) {
      GuildManager.instance.addGuildCoins(result.coinReward);
    }
    notifyListeners();
    return result;
  }

  static String _formatDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static const String _saveKey = 'guild_raid_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode({
        'remainingAttemptsToday': remainingAttemptsToday,
        'lastResetDate': _lastResetDate,
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
      remainingAttemptsToday = (data['remainingAttemptsToday'] as num?)?.toInt() ?? maxDailyAttempts;
      _lastResetDate = data['lastResetDate'] as String?;
    } catch (error) {
      debugPrint('[GuildRaidManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }
  }
}
