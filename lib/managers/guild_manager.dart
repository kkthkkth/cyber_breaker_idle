import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/guild_model.dart';
import '../utils/time_util.dart';
import 'game_manager.dart';
import 'supabase_manager.dart';

/// 길드 시스템 전반(소속 여부, 길드 정보, 출석체크, 로스터, 레벨 버프)을
/// 관장하는 싱글턴 — 이 프로젝트의 다른 매니저들과 같은 관례를 따른다:
/// **로컬(SharedPreferences)이 게임플레이의 유일한 신뢰 소스**이고,
/// Supabase는 그 위에 얹는 부가적인 백업/동기화 계층이다. 단, 길드
/// 로스터([members])와 길드 자체 정보([guildLevel] 등)는 다른 멤버의
/// 활동으로도 바뀌는 "공유 상태"라 [refreshGuild]/[refreshMembers]를 호출할
/// 때마다 서버 스냅샷으로 통째로 교체된다([MailboxManager]와 같은 성격).
///
/// [attackBonus]/[goldBonus](길드 레벨 기반 패시브 버프)는 앱 시작 시
/// [loadData]가 끝난 직후부터 [GameManager]의 전투 스탯 계산식이 곧바로
/// 읽어가므로, main()에서 다른 전투 관련 매니저들과 함께 반드시 await해야
/// 한다.
class GuildManager extends ChangeNotifier {
  GuildManager._internal();

  static final GuildManager instance = GuildManager._internal();

  /// 길드 창설 비용(보석).
  static const int createCostGems = 1000;

  /// 출석체크 1회당 길드 전체 exp 증가량.
  static const int checkInGuildExpGain = 100;

  /// 출석체크 1회당 지급되는 guild_coin — `system_settings` 테이블의
  /// `guild_attendance_coin_reward` 값을 [loadData]가 앱 시작 시 한 번
  /// 받아와 여기에 캐싱한다(기본 10, 서버에 아직 값이 없거나 네트워크가
  /// 끊겨도 항상 안전한 값으로 동작하도록). 예전엔 이 값이 50으로
  /// 하드코딩돼 있어서 기획이 보상량을 바꾸려면 앱을 다시 빌드해야 했다.
  int guildAttendanceCoinReward = 10;

  // ── 소속 여부 ────────────────────────────────────────────────────
  String? guildId;
  GuildRole? myRole;
  int myContribution = 0;
  String? _lastCheckIn;

  /// [hasCheckedInToday]가 "오늘"로 취급하는 날짜(NTP 기준, yyyy-MM-dd) —
  /// 매번 [DateTime.now()](기기 시계)를 직접 읽지 않고 이 캐시와
  /// 비교한다. 기기 시계가 실제 시간보다 뒤처져 있으면(클럭 드리프트)
  /// 자정이 실제로는 지났는데도 DateTime.now()가 여전히 어제를 가리켜
  /// 출석체크 버튼이 "완료" 상태에 계속 묶이는 문제가 생길 수 있어서다.
  /// [checkAndResetCheckInStatus]가 앱 시작 시([loadData])와 매일 정확한
  /// 로컬 자정([MidnightResetManager])마다 이 값을 NTP로 다시 계산한다.
  String _cachedToday = _formatDate(DateTime.now());

  bool get isInGuild => guildId != null;
  bool get isMaster => myRole == GuildRole.master;
  bool get canManageMembers => myRole == GuildRole.master;

  /// 단위 테스트 전용 — [_lastCheckIn]을 직접 읽고 쓴다([WorldBossManager
  /// .debugLastDistributedSessionId]와 같은 관례). 싱글턴이라 테스트
  /// 파일 안의 여러 테스트가 상태를 공유하므로, [checkIn]을 다시 성공
  /// 시켜야 하는 테스트의 setUp에서 null로 리셋하는 용도로 쓴다.
  @visibleForTesting
  String? get debugLastCheckIn => _lastCheckIn;

  @visibleForTesting
  set debugLastCheckIn(String? value) => _lastCheckIn = value;

  /// 단위 테스트 전용 — [_cachedToday]를 네트워크 호출 없이 직접 조작해
  /// [checkAndResetCheckInStatus]의 날짜-변경 감지 분기를 테스트한다.
  @visibleForTesting
  String get debugCachedToday => _cachedToday;

  @visibleForTesting
  set debugCachedToday(String value) => _cachedToday = value;

  // ── 길드 정보(공유 상태 — refreshGuild로만 갱신) ────────────────────
  String guildName = '';
  String guildEmblem = 'shield';
  int guildLevel = 1;
  int guildExp = 0;

  /// 길드 금고 — 길드 전쟁 승리 보상이 입금되고, 길드장의
  /// [GuildWarManager.transferTreasury]로만 개인 재화로 빠져나간다. 둘 다
  /// 서버 RPC가 원자적으로 처리하는 공유 상태라 [guildCoins](개인 주화)와
  /// 달리 로컬에서 낙관적으로 증감하지 않고 항상 [refreshGuild]로만
  /// 갱신한다.
  int treasuryCoin = 0;
  int treasuryGem = 0;

  /// [guildLevel]에서 다음 레벨까지 필요한 exp — EXP 바 표시([expRatio])와
  /// 출석체크 레벨업 판정([_applyGuildExpGain])이 공유하는 단일 공식.
  static int expForLevel(int level) => level * 1000;

  double get expRatio {
    final int required = expForLevel(guildLevel);
    return required <= 0 ? 0 : (guildExp / required).clamp(0.0, 1.0);
  }

  String guildNotice = '';
  List<GuildMember> members = const [];

  /// 길드 레벨에 비례해 자동으로 붙는 공격력 증가율(예: 10레벨 = +10%) —
  /// 미가입 상태면 0. [GameManager.attackPower]가 이 값을 그대로 곱산에
  /// 반영한다.
  double get attackBonus => isInGuild ? guildLevel * 0.01 : 0;

  /// 길드 레벨에 비례한 골드 획득량 증가율(예: 10레벨 = +20%) — 미가입
  /// 상태면 0. [GameManager._onMonsterDefeated]가 골드 보상 계산에 곱한다.
  double get goldBonus => isInGuild ? guildLevel * 0.02 : 0;

  int guildCoins = 0;

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 채운 뒤, 서버에서
  /// 소속 여부/길드 정보/guild_coin을 다시 확인해 갱신한다.
  Future<void> loadData() async {
    await _loadLocal();

    final Map<String, dynamic>? membership = await SupabaseManager.instance.fetchMyGuildMembership();
    if (membership != null) {
      guildId = membership['guild_id']?.toString();
      myRole = guildRoleFromString(membership['role'] as String?);
      myContribution = (membership['contribution'] as num?)?.toInt() ?? myContribution;
      final dynamic checkIn = membership['last_check_in'];
      if (checkIn is String) {
        // 서버에서 받은 값을 그대로 저장하면 안 된다 — [_cachedToday]/
        // [hasCheckedInToday]는 항상 "yyyy-MM-dd" 형식으로만 비교하는데,
        // `last_check_in` 컬럼이 timestamptz라면(가능성이 높다) 여기 들어오는
        // 값은 "2026-08-15T05:23:11+00:00" 같은 전체 타임스탬프 문자열이라
        // 절대 그 형식과 같아질 수 없었다. 그 결과 앱을 재시작해 loadData()가
        // 다시 불릴 때마다 오늘 이미 체크인했어도 hasCheckedInToday가 항상
        // false로 나와 버튼이 계속 다시 활성화되고, 하루에 여러 번 보상을
        // 받을 수 있었다([_normalizeCheckInDate] 참고 — 이게 진짜 원인이었다).
        _lastCheckIn = _normalizeCheckInDate(checkIn);
      }
      if (guildId != null) {
        await refreshGuild();
      }
    } else {
      guildId = null;
      myRole = null;
    }

    final int? coins = await SupabaseManager.instance.fetchGuildCoins();
    if (coins != null) {
      guildCoins = coins;
    }

    guildAttendanceCoinReward = await SupabaseManager.instance.fetchSystemSettingInt(
      'guild_attendance_coin_reward',
      fallback: guildAttendanceCoinReward,
    );

    // 자정을 넘긴 채로 다시 실행됐을 수도 있으니(예: 앱을 며칠 만에 다시
    // 켬), MidnightResetManager의 다음 타이머를 기다리지 않고 시작 시점에
    // 바로 한 번 "오늘" 캐시를 NTP 기준으로 맞춘다.
    await checkAndResetCheckInStatus();

    await _saveLocal();
    notifyListeners();
  }

  /// [guildId] 길드의 상세 정보를 서버에서 다시 받아온다 — 다른 멤버의
  /// 출석체크 등으로 바뀐 레벨/exp/공지를 반영할 때 호출한다(예:
  /// [GuildMainScreen]이 열릴 때마다).
  Future<void> refreshGuild() async {
    final String? id = guildId;
    if (id == null) {
      return;
    }
    final Map<String, dynamic>? row = await SupabaseManager.instance.fetchGuild(id);
    if (row == null) {
      return;
    }
    final GuildInfo info = GuildInfo.fromJson(row);
    guildName = info.name;
    guildEmblem = info.emblem;
    guildLevel = info.level;
    guildExp = info.exp;
    guildNotice = info.notice;
    treasuryCoin = info.treasuryCoin;
    treasuryGem = info.treasuryGem;
    notifyListeners();
    await _saveLocal();
  }

  /// 길드원 로스터를 서버에서 다시 받아온다 — [GuildMainScreen]의
  /// "길드원 목록" 탭이 열릴 때 호출한다.
  Future<void> refreshMembers() async {
    final String? id = guildId;
    if (id == null) {
      members = const [];
      notifyListeners();
      return;
    }
    final List<Map<String, dynamic>> rows = await SupabaseManager.instance.fetchGuildMembers(id);
    members = rows.map(GuildMember.fromJson).toList();
    notifyListeners();
  }

  /// [name] 길드명이 이미 사용 중인지 — [GuildLobbyScreen]의 창설 팝업이
  /// 실시간 중복 확인에 쓴다.
  Future<bool> isNameTaken(String name) => SupabaseManager.instance.isGuildNameTaken(name);

  /// 보석 [createCostGems]개를 소모해 새 길드를 만들고 즉시 그 길드의
  /// master로 가입한다 — 이름 중복 확인을 재화 차감보다 먼저 하므로,
  /// 이름이 이미 있으면 보석은 건드리지도 않는다.
  Future<GuildCreateResult> createGuild({required String name, required String emblem}) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty || await isNameTaken(trimmed)) {
      return GuildCreateResult.duplicateName;
    }
    if (!GameManager.instance.spendGems(createCostGems)) {
      return GuildCreateResult.insufficientGems;
    }

    final String? newGuildId = await SupabaseManager.instance.createGuild(
      name: trimmed,
      emblem: emblem,
    );
    if (newGuildId == null) {
      return GuildCreateResult.error;
    }

    guildId = newGuildId;
    myRole = GuildRole.master;
    myContribution = 0;
    _lastCheckIn = null;
    guildName = trimmed;
    guildEmblem = emblem;
    guildLevel = 1;
    guildExp = 0;
    guildNotice = '';
    notifyListeners();
    await _saveLocal();
    return GuildCreateResult.success;
  }

  /// [targetGuildId]에 일반 길드원으로 즉시 가입한다.
  Future<bool> joinGuild(String targetGuildId) async {
    if (isInGuild) {
      return false;
    }
    final bool success = await SupabaseManager.instance.joinGuild(targetGuildId);
    if (!success) {
      return false;
    }
    guildId = targetGuildId;
    myRole = GuildRole.member;
    myContribution = 0;
    _lastCheckIn = null;
    notifyListeners();
    await _saveLocal();
    await refreshGuild();
    return true;
  }

  /// 길드를 탈퇴한다 — [SupabaseManager.leaveGuild]가 서버에서 guild_coin을
  /// 0으로 초기화하고 guild_members 행을 삭제하는 데 성공했을 때만 로컬
  /// 상태를 "길드 없음"으로 되돌린다([createGuild]/[joinGuild]와 같은
  /// "서버 먼저, 성공해야 로컬 반영" 관례 — 길드 소속 여부는 다른 길드원과도
  /// 얽힌 공유 상태라 로컬을 먼저 낙관적으로 바꾸면 안 된다). 성공하면
  /// [isInGuild]가 false가 되어 [GuildScreen]이 자동으로 [GuildLobbyScreen]
  /// (가입 화면)으로 되돌아간다.
  Future<bool> leaveGuild() async {
    final String? id = guildId;
    if (id == null) {
      return false;
    }
    final bool success = await SupabaseManager.instance.leaveGuild(id);
    if (!success) {
      return false;
    }

    guildId = null;
    myRole = null;
    myContribution = 0;
    guildCoins = 0;
    _lastCheckIn = null;
    guildName = '';
    guildEmblem = 'shield';
    guildLevel = 1;
    guildExp = 0;
    guildNotice = '';
    members = const [];

    notifyListeners();
    await _saveLocal();
    return true;
  }

  /// 오늘 이미 출석체크를 했는지 — UI가 버튼 활성/비활성을 미리 보여줄
  /// 때 쓰는 낙관적 판정. [DateTime.now()](기기 시계)를 직접 비교하지
  /// 않고 [_cachedToday](NTP 기준으로 캐시된 "오늘")와 비교한다 — 실제
  /// 처리([checkIn])는 서버 시간(NTP) 기준으로 한 번 더 확인한다.
  bool get hasCheckedInToday {
    final String? last = _lastCheckIn;
    if (last == null) {
      return false;
    }
    return last == _cachedToday;
  }

  /// 로컬 자정이 실제로(NTP 기준) 지났으면 [_cachedToday]를 갱신하고
  /// [hasCheckedInToday]를 다시 계산해 UI([GuildMainScreen] 출석체크
  /// 버튼)를 즉시 다시 그리게 한다 — [MidnightResetManager]가 정확히
  /// 다음 로컬 자정에 이 메서드를 호출한다(DungeonManager
  /// .checkAndResetDailyCounts()/MissionManager.checkAndResetMissions()와
  /// 같은 패턴). 다른 매니저들과 달리 길드 출석은 리셋할 카운터가 따로
  /// 없어 "오늘" 캐시만 새로 고치면 되고, [_lastCheckIn](과거 체크인
  /// 기록) 자체는 건드리지 않는다 — 앱을 켠 채로 자정을 넘기지 않고
  /// 다음날 새로 실행했을 때는 [loadData]가 이 메서드를 한 번 더 불러
  /// 캐시를 최신 상태로 맞춘다.
  Future<void> checkAndResetCheckInStatus() async {
    final DateTime now = await getNetworkTime();
    final String today = _formatDate(now);
    if (_cachedToday == today) {
      return;
    }
    _cachedToday = today;
    notifyListeners();
  }

  /// 길드 출석체크 — 서버 RPC(`guild_check_in`)가 exp/guild_coin 증가와
  /// "오늘 이미 체크인했는지" 판정을 원자적으로 처리한다(여러 멤버가
  /// 거의 동시에 체크인해도 증가분이 유실되지 않는다 — 예전엔
  /// 클라이언트가 로컬 exp를 읽어 더한 값을 통째로 덮어써서 경쟁 조건이
  /// 있었다). RPC가 성공하면 그 결과를 로컬에도 곧바로 반영해 UI(exp바/
  /// 코인)가 다음 새로고침을 기다리지 않고 즉시 갱신되게 한다 — 단, 이
  /// 로컬 반영은 낙관적 미러링이라 다른 멤버의 활동까지 실시간으로
  /// 따라잡지는 못한다(그건 [refreshGuild]가 할 일).
  ///
  /// 오늘 이미 체크인했으면(로컬 캐시 기준) RPC조차 시도하지 않고
  /// false — 실제 최종 판정은 RPC 안에서도 한 번 더 이뤄지므로, 로컬
  /// 캐시가 기기 재설치 등으로 어긋나 있어도 중복 지급되지는 않는다.
  Future<bool> checkIn() async {
    final String? id = guildId;
    if (id == null) {
      return false;
    }
    if (hasCheckedInToday) {
      return false;
    }

    final bool success = await SupabaseManager.instance.guildCheckIn(
      guildId: id,
      expAmount: checkInGuildExpGain,
      coinAmount: guildAttendanceCoinReward,
    );
    if (!success) {
      return false;
    }

    final DateTime now = await getNetworkTime();
    _lastCheckIn = _formatDate(now);
    // 이미 손에 쥔 NTP 시각으로 "오늘" 캐시도 같이 맞춰서, 자정 근처에
    // 체크인했을 때 hasCheckedInToday가 기기 시계와 어긋난 값을 잠깐이라도
    // 보여주는 일이 없게 한다.
    _cachedToday = _lastCheckIn!;
    // exp와 마찬가지로 실제 증가분 자체는 RPC가 이미 원자적으로 반영했다 —
    // 이 로컬 증가는 UI가 다음 새로고침을 기다리지 않고 즉시 갱신되게 하는
    // 낙관적 미러링이다.
    guildCoins += guildAttendanceCoinReward;
    final int levelBefore = guildLevel;
    _applyGuildExpGain(checkInGuildExpGain);

    notifyListeners();
    await _saveLocal();

    // exp 자체는 RPC가 이미 원자적으로 반영했다 — 레벨은 그 결과와
    // 무관하게 이 클라이언트가 로컬에서 계산한 값이므로, 레벨업이 실제로
    // 일어났을 때만 별도로 밀어 넣는다(요구사항: "레벨업 판정도 로컬에서
    // 경험치를 갱신한 후 필요하다면 서버에 레벨만 update").
    if (guildLevel != levelBefore) {
      unawaited(SupabaseManager.instance.updateGuildLevel(id, guildLevel));
    }
    return true;
  }

  /// 길드 상점 구매 등, 체크인 외의 경로에서 길드 주화를 소비한다 —
  /// [GameManager.spendGold]와 같은 패턴(동기 API, 서버 동기화는 내부에서
  /// fire-and-forget). 재화가 부족하면 아무것도 바꾸지 않고 false. 출석
  /// 체크의 코인 지급은 길드 exp와 함께 원자적으로 처리해야 해서 여전히
  /// [SupabaseManager.guildCheckIn] RPC를 거치지만, 여긴 이 유저 개인의
  /// 주화만 바뀌는 경로라 RPC 없이 곧장 upsert해도 안전하다.
  bool spendGuildCoins(int amount) {
    if (amount <= 0 || guildCoins < amount) {
      return false;
    }
    guildCoins -= amount;
    notifyListeners();
    unawaited(_saveLocal());
    unawaited(SupabaseManager.instance.updateGuildCoins(guildCoins));
    return true;
  }

  /// 길드 던전 클리어 보상 등, 체크인 외의 경로에서 길드 주화를 지급한다.
  void addGuildCoins(int amount) {
    if (amount <= 0) {
      return;
    }
    guildCoins += amount;
    notifyListeners();
    unawaited(_saveLocal());
    unawaited(SupabaseManager.instance.updateGuildCoins(guildCoins));
  }

  /// [AffectionManager._applyGain]과 같은 EXP 바 패턴 — [gain]을 더해
  /// [expForLevel] 문턱을 넘을 때마다 레벨을 올리고 초과분을 이월한다.
  /// 로컬 exp가 서버의 최신 합계와 잠깐 어긋나 있을 수 있어(다른 멤버의
  /// 체크인은 [refreshGuild]를 다시 부르기 전까진 반영되지 않는다) 레벨업
  /// 판정도 그 스냅샷 기준의 낙관적 계산이다 — 실제 exp 증가 자체는 이제
  /// [SupabaseManager.guildCheckIn] RPC가 원자적으로 처리한다.
  void _applyGuildExpGain(int gain) {
    int exp = guildExp + gain;
    int level = guildLevel;
    while (exp >= expForLevel(level)) {
      exp -= expForLevel(level);
      level += 1;
    }
    guildExp = exp;
    guildLevel = level;
  }

  /// 길드 공지사항을 바꾼다 — 길드장이 아니면 아무것도 하지 않고 false.
  Future<bool> updateNotice(String notice) async {
    final String? id = guildId;
    if (id == null || !isMaster) {
      return false;
    }
    guildNotice = notice;
    notifyListeners();
    await _saveLocal();
    unawaited(SupabaseManager.instance.updateGuildNotice(id, notice));
    return true;
  }

  /// 길드 엠블럼을 바꾼다 — 길드장이 아니면 아무것도 하지 않고 false.
  Future<bool> updateEmblem(String emblem) async {
    final String? id = guildId;
    if (id == null || !isMaster) {
      return false;
    }
    guildEmblem = emblem;
    notifyListeners();
    await _saveLocal();
    unawaited(SupabaseManager.instance.updateGuildEmblem(id, emblem));
    return true;
  }

  /// [targetUserId]를 부길드장(elder)으로 위임한다 — 길드장 전용.
  Future<bool> promoteToElder(String targetUserId) async {
    final String? id = guildId;
    if (id == null || !canManageMembers) {
      return false;
    }
    await SupabaseManager.instance.updateGuildMemberRole(id, targetUserId, 'elder');
    await refreshMembers();
    return true;
  }

  /// [targetUserId]를 길드에서 추방한다 — 길드장 전용.
  Future<bool> kickMember(String targetUserId) async {
    final String? id = guildId;
    if (id == null || !canManageMembers) {
      return false;
    }
    await SupabaseManager.instance.kickGuildMember(id, targetUserId);
    await refreshMembers();
    return true;
  }

  static String _formatDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  /// `guild_members.last_check_in`이 순수 날짜("2026-08-15")든 전체
  /// 타임스탬프("2026-08-15T05:23:11+00:00", timestamptz 컬럼이면 이 쪽일
  /// 가능성이 높다)든 상관없이, 항상 [_formatDate]와 같은 "yyyy-MM-dd"
  /// 로컬 달력 날짜 문자열로 정규화한다 — [hasCheckedInToday]/[_cachedToday]가
  /// 전부 이 형식으로만 비교하기 때문에, 여기서 정규화하지 않으면 형식이
  /// 어긋나 절대 같아지지 않는다(과거 버그의 원인). `.toLocal()`을 거치는
  /// 이유는, 타임스탬프에 UTC 오프셋이 붙어 있으면 자정 근처(예: KST
  /// 00~09시는 UTC로는 아직 전날)에 체크인한 기록이 로컬 기준 달력 날짜와
  /// 다르게 해석될 수 있어서다 — "로컬 기준 오늘"과 비교해야 한다는 요구사항
  /// 그대로다. 파싱 자체가 안 되는 값(알 수 없는 형식)이면 그 값을 그대로
  /// 반환해 최소한 예전과 같은 동작(그리고 눈에 보이는 로그)이라도 유지한다.
  static String? _normalizeCheckInDate(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final DateTime? parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      debugPrint('[GuildManager] last_check_in 형식을 해석하지 못했습니다: "$raw"');
      return raw;
    }
    return _formatDate(parsed.toLocal());
  }

  /// 단위 테스트 전용 — private static인 [_normalizeCheckInDate]를 감싸는
  /// 얇은 창구([debugLastCheckIn]과 같은 관례).
  @visibleForTesting
  static String? debugNormalizeCheckInDate(String? raw) => _normalizeCheckInDate(raw);

  static const String _saveKey = 'guild_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode({
        'guildId': guildId,
        'myRole': myRole != null ? guildRoleColumnValue(myRole!) : null,
        'myContribution': myContribution,
        'lastCheckIn': _lastCheckIn,
        'guildName': guildName,
        'guildEmblem': guildEmblem,
        'guildLevel': guildLevel,
        'guildExp': guildExp,
        'guildNotice': guildNotice,
        'guildCoins': guildCoins,
        'treasuryCoin': treasuryCoin,
        'treasuryGem': treasuryGem,
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
      guildId = data['guildId'] as String?;
      final String? roleValue = data['myRole'] as String?;
      myRole = roleValue != null ? guildRoleFromString(roleValue) : null;
      myContribution = (data['myContribution'] as num?)?.toInt() ?? myContribution;
      _lastCheckIn = data['lastCheckIn'] as String?;
      guildName = data['guildName'] as String? ?? guildName;
      guildEmblem = data['guildEmblem'] as String? ?? guildEmblem;
      guildLevel = (data['guildLevel'] as num?)?.toInt() ?? guildLevel;
      guildExp = (data['guildExp'] as num?)?.toInt() ?? guildExp;
      guildNotice = data['guildNotice'] as String? ?? guildNotice;
      guildCoins = (data['guildCoins'] as num?)?.toInt() ?? guildCoins;
      treasuryCoin = (data['treasuryCoin'] as num?)?.toInt() ?? treasuryCoin;
      treasuryGem = (data['treasuryGem'] as num?)?.toInt() ?? treasuryGem;
    } catch (error) {
      debugPrint('[GuildManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }
  }
}
