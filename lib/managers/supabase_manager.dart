import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/guild_boss_model.dart';

/// 닉네임 설정([SupabaseManager.setNickname]) 결과 — [NicknameScreen]이
/// 이 값 하나로 성공/중복/기타 오류 세 갈래를 정확히 구분해 보여준다.
enum NicknameUpdateResult { success, duplicate, error }

/// Supabase 인증(게스트/구글 로그인)과 `profiles` 테이블 동기화를 담당하는
/// 싱글턴 — 이 프로젝트의 다른 매니저들과 같은 관례(정적 [instance])를
/// 따른다. 로컬 저장(SharedPreferences)이 여전히 게임 진행의 유일한 신뢰
/// 소스이고, 이 매니저는 그 위에 얹는 부가적인 클라우드 동기화 계층이다.
///
/// 로그인이 아닌 나머지 메서드([fetchNickname]/[setNickname]/[updateGold])
/// 는 백그라운드 동기화라 실패해도(오프라인 등) 조용히 넘어가고 로컬 게임
/// 진행을 막지 않는다(RemoteSpriteLoader의 방어적 네트워크 호출 관례와
/// 동일). 반면 [signInAsGuest]/[signInWithGoogle]은 유저가 버튼을 누르고
/// 결과를 실시간으로 기다리는 포그라운드 동작이라 예외를 삼키지 않고
/// 그대로 던진다 — 자세한 이유는 각 메서드 문서 참고.
class SupabaseManager {
  SupabaseManager._internal();

  static final SupabaseManager instance = SupabaseManager._internal();

  static const String _profilesTable = 'profiles';

  SupabaseClient get _client => Supabase.instance.client;

  /// 현재 로그인된 유저의 id — 로그인 전이거나 세션이 없으면 null.
  String? get currentUserId => _client.auth.currentUser?.id;

  /// 게스트(익명) 로그인을 수행하고 `profiles` 테이블에 해당 유저 행을
  /// 만든다. [LoginScreen]의 "게스트로 시작하기" 경고 다이얼로그에서
  /// "확인"을 눌렀을 때만 호출된다 — 되돌릴 수 없는(기기 변경/재설치 시
  /// 데이터가 사라지는) 계정을 만드는 동작이라, 유저 동의 없이 앱 시작
  /// 시점에 자동으로 호출하지 않는다.
  ///
  /// [주의] 로그인/게스트/구글 시작 함수들은 다른 매니저 메서드([updateGold]
  /// 등)와 달리 예외를 여기서 삼키지 않고 그대로 던진다 — 이건 유저가 버튼을
  /// 누르고 그 결과를 실시간으로 기다리는 포그라운드 동작이라(백그라운드
  /// 동기화가 아니라), 실패 이유를 호출부([LoginScreen])가 즉시 화면에
  /// 보여줄 수 있어야 한다(예: `signInAnonymously()`가 Supabase 대시보드의
  /// "Anonymous sign-ins"가 꺼져 있을 때 던지는
  /// `AuthApiException(anonymous_provider_disabled)` — 이 정보 없이는
  /// "버튼이 먹통"으로만 보인다).
  Future<bool> signInAsGuest() async {
    final AuthResponse response = await _client.auth.signInAnonymously();
    final User? user = response.user;
    if (user == null) {
      debugPrint('[SupabaseManager] 게스트 로그인 실패: user가 null입니다.');
      return false;
    }
    await _upsertProfile(userId: user.id, loginType: 'guest');
    return true;
  }

  /// 모바일에서 딥링크로 앱에 돌아오기 위한 리다이렉트 스킴 — Android
  /// 인텐트 필터(AndroidManifest.xml)/iOS URL Scheme에 등록해 둔 것과
  /// 반드시 같은 값이어야 한다.
  static const String _mobileRedirectTo = 'cyberbreaker://login-callback';

  /// [signInWithGoogle]의 redirectTo — 웹은 지금 이 페이지가 떠 있는 origin
  /// (`Uri.base`)으로 되돌아와야 로컬 `flutter run -d chrome` 테스트든 실제
  /// 배포된 도메인이든 항상 맞게 동작한다(고정 문자열로 박아두면 로컬
  /// 테스트마다 포트가 달라질 때 깨진다). 이 값을 Supabase 대시보드의
  /// Authentication > URL Configuration > Redirect URLs에도 등록해야
  /// 리다이렉트가 거부되지 않는다.
  static String get _googleRedirectTo => kIsWeb ? Uri.base.toString() : _mobileRedirectTo;

  /// 구글 로그인 — 플랫폼별 네이티브 SDK(`google_sign_in`) 대신 Supabase가
  /// 직접 제공하는 OAuth 리다이렉트 플로우(`signInWithOAuth`)를 쓴다. 웹에서
  /// `google_sign_in`의 `authenticate()`가 아예 지원되지 않는 문제
  /// (`UnimplementedError: authenticate is not supported on the web`)와,
  /// 그로 인해 필요했던 `<meta name="google-signin-client_id">` 설정까지
  /// 한 번에 없앤다 — 웹/모바일 어디서든 이 함수 하나로 동작한다.
  ///
  /// [주의] 이 함수가 리턴하는 bool은 "브라우저(또는 시스템 로그인 창)를
  /// 여는 데 성공했는지"만 뜻한다 — 실제 로그인 성공 여부는 여기서 알 수
  /// 없다(웹은 페이지 자체가 구글로 리다이렉트됐다가 돌아오므로, 이 Future가
  /// 끝까지 resolve되지 않고 페이지가 통째로 새로고침될 수도 있다). 실제
  /// 완료 처리(프로필 upsert 등)는 [LoginScreen]이
  /// `auth.onAuthStateChange`의 [AuthChangeEvent.signedIn]을 구독해서
  /// 처리한다 — [upsertGoogleProfile] 참고.
  ///
  /// [signInAsGuest]와 같은 이유로 예외를 여기서 삼키지 않는다 — 특히
  /// Android에서 브라우저를 여는 데 실패하면(예: AndroidManifest.xml에
  /// `<queries>`로 https VIEW 인텐트를 선언해 두지 않아 Android 11+ 패키지
  /// 가시성 제한에 걸리는 경우) `launchUrl`이 예외를 던지는데, 이걸 그대로
  /// 호출부에 전달해야 "버튼이 먹통"이 아니라 실제 원인이 화면에 보인다.
  Future<bool> signInWithGoogle() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _googleRedirectTo,
    );
  }

  /// [signInWithGoogle]의 리다이렉트가 실제로 완료된 뒤(웹은 페이지 복귀,
  /// 모바일은 딥링크 복귀 → `onAuthStateChange`의 signedIn 이벤트) 호출한다
  /// — [signInAsGuest]와 동일한 upsert를 `login_type: 'google'`로 수행한다.
  Future<void> upsertGoogleProfile(User user) => _upsertProfile(userId: user.id, loginType: 'google');

  /// [userId]로 `profiles` 행을 만든다(이미 있으면 존재만 확인).
  ///
  /// [주의] upsert 페이로드에는 일부러 `id`/`login_type`만 담는다 —
  /// `nickname`/`level`/`gold` 같은 진행 데이터를 매번 같이 올리면, 이미
  /// 진행 중인 유저가 로그인할 때마다(=이 함수가 다시 불릴 때마다) 서버에
  /// 저장된 실제 값이 기본값/null로 덮어써지는 심각한 사고가 난다. 닉네임은
  /// [setNickname]처럼 해당 컬럼 하나만 건드리는 전용 함수로만 갱신한다.
  Future<void> _upsertProfile({required String userId, required String loginType}) {
    return _client.from(_profilesTable).upsert({
      'id': userId,
      'login_type': loginType,
    });
  }

  /// 현재 유저의 저장된 닉네임을 조회한다 — 로그인 직후(자동 로그인 포함)
  /// [LoginScreen]이 이 값으로 닉네임 설정 화면을 건너뛸지 판단한다. 아직
  /// 로그인 전이거나 조회 실패 시 null(= "닉네임 없음"과 동일하게 취급되어
  /// 안전한 쪽인 닉네임 설정 화면으로 보내진다).
  Future<String?> fetchNickname() async {
    final String? userId = currentUserId;
    if (userId == null) {
      return null;
    }
    try {
      final Map<String, dynamic>? row = await _client
          .from(_profilesTable)
          .select('nickname')
          .eq('id', userId)
          .maybeSingle();
      final String? nickname = row?['nickname'] as String?;
      return (nickname == null || nickname.trim().isEmpty) ? null : nickname;
    } catch (error) {
      debugPrint('[SupabaseManager] 닉네임 조회 실패: $error');
      return null;
    }
  }

  /// 접속 상태([GuildMember.isOnline]) 판정용 하트비트 주기 — 이 간격마다
  /// [updateLastSeen]이 자동으로 다시 불린다([startLastSeenHeartbeat]).
  /// [GuildMember.onlineThreshold](5분)보다 충분히 짧게 잡아, 하트비트
  /// 사이의 텀만으로 온라인 유저가 오프라인으로 잘못 보이지 않게 한다.
  static const Duration lastSeenInterval = Duration(minutes: 2);

  Timer? _lastSeenTimer;

  /// 현재 유저의 `profiles.last_seen`을 지금 시각(UTC)으로 갱신한다 —
  /// 실패해도(오프라인 등) 조용히 넘어간다(다른 백그라운드 동기화 메서드와
  /// 같은 관례). 로그인 전이면 아무것도 하지 않는다.
  Future<void> updateLastSeen() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client
          .from(_profilesTable)
          .update({'last_seen': DateTime.now().toUtc().toIso8601String()})
          .eq('id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] last_seen 갱신 실패: $error');
    }
  }

  /// 현재 유저의 `profiles.last_seen`을 읽어온다 — [OfflineRewardManager]가
  /// 이 기기에 로컬 종료 시각 기록이 없을 때(최초 실행/재설치/기기 변경 등)
  /// 오프라인 보상 계산의 대체 기준 시각으로 쓴다. 실패하거나 로그인
  /// 전이거나 값이 없으면 null.
  Future<DateTime?> fetchLastSeen() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final Map<String, dynamic>? row = await _client
          .from(_profilesTable)
          .select('last_seen')
          .eq('id', userId)
          .maybeSingle();
      final String? raw = row?['last_seen'] as String?;
      return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
    } catch (error) {
      debugPrint('[SupabaseManager] last_seen 조회 실패: $error');
      return null;
    }
  }

  /// 앱 실행 시(main()) 한 번 호출 — 즉시 한 번 [updateLastSeen]을 실행하고,
  /// 이후 [lastSeenInterval]마다 반복한다. 앱이 포그라운드에 떠 있는 동안
  /// 계속 "접속중"으로 보이게 하는 것이 목적이라, 백그라운드로 밀려날 때
  /// 멈추거나 다시 포그라운드로 돌아왔을 때 즉시 갱신하는 처리는 호출부
  /// (main.dart의 [WidgetsBindingObserver])가 [updateLastSeen]을 직접
  /// 호출해서 보완한다.
  void startLastSeenHeartbeat() {
    unawaited(updateLastSeen());
    _lastSeenTimer?.cancel();
    _lastSeenTimer = Timer.periodic(lastSeenInterval, (_) => updateLastSeen());
  }

  /// 앱 종료/테스트 정리용 — 보통 호출할 필요는 없다(앱이 살아있는 동안은
  /// 계속 하트비트를 보내야 하므로).
  void stopLastSeenHeartbeat() {
    _lastSeenTimer?.cancel();
    _lastSeenTimer = null;
  }

  /// [nickname]이 이미 다른 유저가 쓰고 있는지 확인한 뒤, 비어있으면 현재
  /// 유저의 `profiles.nickname`을 갱신한다.
  ///
  /// 중복 체크와 실제 update 사이에는 아주 짧은 틈이 있어(TOCTOU), 그
  /// 사이 다른 유저가 같은 닉네임을 먼저 가져갈 수도 있다 — 그 경우 DB의
  /// UNIQUE 제약이 막아주므로, `update`가 unique_violation(Postgres 코드
  /// 23505)으로 실패하면 사전 체크를 통과했더라도 [NicknameUpdateResult
  /// .duplicate]로 취급한다. 두 경로 모두 결국 "중복" 하나로 귀결되므로
  /// [NicknameScreen]은 분기 없이 안전하다.
  Future<NicknameUpdateResult> setNickname(String nickname) async {
    final String? userId = currentUserId;
    if (userId == null) {
      debugPrint('[SupabaseManager] setNickname 실패: 로그인된 유저가 없습니다.');
      return NicknameUpdateResult.error;
    }

    try {
      final bool taken = await _isNicknameTaken(nickname);
      if (taken) {
        return NicknameUpdateResult.duplicate;
      }

      await _client.from(_profilesTable).update({'nickname': nickname}).eq('id', userId);
      return NicknameUpdateResult.success;
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        return NicknameUpdateResult.duplicate;
      }
      debugPrint('[SupabaseManager] 닉네임 설정 실패: $error');
      return NicknameUpdateResult.error;
    } catch (error) {
      debugPrint('[SupabaseManager] 닉네임 설정 실패: $error');
      return NicknameUpdateResult.error;
    }
  }

  Future<bool> _isNicknameTaken(String nickname) async {
    final Map<String, dynamic>? row = await _client
        .from(_profilesTable)
        .select('id')
        .eq('nickname', nickname)
        .maybeSingle();
    return row != null;
  }

  /// 현재 유저의 `gold`를 [amount]로 갱신한다 — 증감이 아니라 "지금 로컬
  /// 상태의 최종값을 그대로 반영"하는 절대값 push다. 호출부는 보통
  /// `SupabaseManager.instance.updateGold(GameManager.instance.gold)`처럼
  /// [GameManager.gold]를 그대로 넘기면 된다(예: [GameManager.addGold]
  /// 끝에서, 또는 주기적인 자동 저장 시점에). 아직 로그인 전이면(유저 id가
  /// 없으면) 아무 것도 하지 않는다.
  Future<void> updateGold(int amount) async {
    final String? userId = currentUserId;
    if (userId == null) {
      debugPrint('[SupabaseManager] updateGold 실패: 로그인된 유저가 없습니다.');
      return;
    }

    try {
      await _client.from(_profilesTable).update({'gold': amount}).eq('id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] gold 업데이트 실패: $error');
    }
  }

  /// 현재 유저의 `profiles.highest_tower_floor`(무한의 탑 최고 클리어 층,
  /// 기본 0) — 못 불러오면 null(호출부가 로컬 캐시를 유지).
  Future<int?> fetchHighestTowerFloor() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final Map<String, dynamic>? row = await _client
          .from(_profilesTable)
          .select('highest_tower_floor')
          .eq('id', userId)
          .maybeSingle();
      return (row?['highest_tower_floor'] as num?)?.toInt();
    } catch (error) {
      debugPrint('[SupabaseManager] 무한의 탑 최고 층수 조회 실패: $error');
      return null;
    }
  }

  /// `profiles.highest_tower_floor`를 [floor](절대값)로 덮어쓴다 —
  /// [updateGold]와 같은 "로컬이 먼저 확정한 값을 그대로 push" 관례.
  /// [DungeonManager]가 층을 클리어해 [DungeonManager.highestClearedFloor]를
  /// 올릴 때마다 호출한다.
  Future<void> updateHighestTowerFloor(int floor) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client
          .from(_profilesTable)
          .update({'highest_tower_floor': floor})
          .eq('id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] 무한의 탑 최고 층수 동기화 실패: $error');
    }
  }

  /// 현재 유저의 `profiles.highest_reached_chapter`(역대 최고 도달 챕터,
  /// 기본 1) — 못 불러오면 null(호출부가 로컬 캐시를 유지).
  Future<int?> fetchHighestReachedChapter() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final Map<String, dynamic>? row = await _client
          .from(_profilesTable)
          .select('highest_reached_chapter')
          .eq('id', userId)
          .maybeSingle();
      return (row?['highest_reached_chapter'] as num?)?.toInt();
    } catch (error) {
      debugPrint('[SupabaseManager] 최고 도달 챕터 조회 실패: $error');
      return null;
    }
  }

  /// `profiles.highest_reached_chapter`를 [chapter](절대값)로 덮어쓴다 —
  /// [updateHighestTowerFloor]와 같은 "로컬이 먼저 확정한 값을 그대로 push"
  /// 관례. [GameManager]가 새 최고 챕터를 기록할 때마다 호출한다 — 명예의
  /// 전당 랭킹([fetchTopRankingProfiles])의 1순위 정렬 기준이 이 컬럼이다.
  Future<void> updateHighestReachedChapter(int chapter) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client
          .from(_profilesTable)
          .update({'highest_reached_chapter': chapter})
          .eq('id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] 최고 도달 챕터 동기화 실패: $error');
    }
  }

  // ── 명예의 전당 (RankingManager 전용) ───────────────────────────────
  //
  // `profiles`에는 길드 FK가 없어(길드 소속은 `guild_members`가 별도로
  // 관리) 한 번의 PostgREST 임베드로 "랭킹 + 길드명"을 동시에 가져올 수
  // 없다 — [fetchTopRankingProfiles]로 랭킹 100명을 먼저 뽑고,
  // [fetchGuildNamesForUsers]로 그 유저 id들의 길드명만 한 번 더 조회해
  // [RankingManager]가 클라이언트에서 합친다.
  /// 최고 도달 챕터 내림차순(1순위) → 환생 횟수 내림차순(2순위)으로 상위
  /// 100명을 가져온다.
  Future<List<Map<String, dynamic>>> fetchTopRankingProfiles() async {
    try {
      final List<dynamic> rows = await _client
          .from(_profilesTable)
          .select('id, nickname, highest_reached_chapter, prestige_count')
          .order('highest_reached_chapter', ascending: false)
          .order('prestige_count', ascending: false)
          .limit(100);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 랭킹 프로필 조회 실패: $error');
      return const [];
    }
  }

  /// 무한의 탑 랭킹 — 최고 클리어 층수(`profiles.highest_tower_floor`)
  /// 내림차순으로 상위 100명([RankingCategory.towerFloor]). 이 컬럼은
  /// 이미 [DungeonManager.clearFloor]가 층을 처음 깰 때마다 동기화해 둔
  /// 값이라, 랭킹 전용으로 새로 만든 컬럼이 아니다 — highest_reached_chapter
  /// 랭킹과는 별도 기준으로 확장한 것뿐이다.
  Future<List<Map<String, dynamic>>> fetchTopTowerRankingProfiles() async {
    try {
      final List<dynamic> rows = await _client
          .from(_profilesTable)
          .select('id, nickname, highest_tower_floor')
          .order('highest_tower_floor', ascending: false)
          .limit(100);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 무한의 탑 랭킹 조회 실패: $error');
      return const [];
    }
  }

  /// [userIds]에 속한 유저들의 소속 길드명 — `guild_members`를
  /// `guilds(name)` 임베드로 조회한다(한 유저는 최대 한 길드에만 속하므로
  /// 1:1 매핑). 길드가 없는 유저는 결과에 아예 나타나지 않는다.
  Future<List<Map<String, dynamic>>> fetchGuildNamesForUsers(List<String> userIds) async {
    if (userIds.isEmpty) {
      return const [];
    }
    try {
      final List<dynamic> rows = await _client
          .from(_guildMembersTable)
          .select('user_id, guilds(name)')
          .inFilter('user_id', userIds);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 랭킹 길드명 조회 실패: $error');
      return const [];
    }
  }

  /// 현재 유저의 `profiles.prestige_count`/`prestige_core_points`(오버클럭
  /// 실행 횟수/누적 코어 포인트, 둘 다 기본 0) — 못 불러오면 null(호출부가
  /// 로컬 캐시를 유지).
  Future<({int count, int corePoints})?> fetchPrestigeData() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final Map<String, dynamic>? row = await _client
          .from(_profilesTable)
          .select('prestige_count, prestige_core_points')
          .eq('id', userId)
          .maybeSingle();
      if (row == null) {
        return null;
      }
      return (
        count: (row['prestige_count'] as num?)?.toInt() ?? 0,
        corePoints: (row['prestige_core_points'] as num?)?.toInt() ?? 0,
      );
    } catch (error) {
      debugPrint('[SupabaseManager] 오버클럭 데이터 조회 실패: $error');
      return null;
    }
  }

  /// `profiles.prestige_count`/`prestige_core_points`를 덮어쓴다 —
  /// [updateHighestTowerFloor]와 같은 "로컬이 먼저 확정한 값을 그대로
  /// push" 관례. [PrestigeManager.prestige]가 성공할 때마다 호출한다.
  Future<void> updatePrestigeData({required int count, required int corePoints}) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client
          .from(_profilesTable)
          .update({'prestige_count': count, 'prestige_core_points': corePoints})
          .eq('id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] 오버클럭 데이터 동기화 실패: $error');
    }
  }

  /// 현재 유저의 `profiles.character_pity_count`/`pet_pity_count`/
  /// `equipment_pity_count`(가챠 종류별 천장 카운터, 전부 기본 0) — 못
  /// 불러오면 null(호출부가 로컬 캐시를 유지).
  Future<({int character, int pet, int equipment})?> fetchPityData() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final Map<String, dynamic>? row = await _client
          .from(_profilesTable)
          .select('character_pity_count, pet_pity_count, equipment_pity_count')
          .eq('id', userId)
          .maybeSingle();
      if (row == null) {
        return null;
      }
      return (
        character: (row['character_pity_count'] as num?)?.toInt() ?? 0,
        pet: (row['pet_pity_count'] as num?)?.toInt() ?? 0,
        equipment: (row['equipment_pity_count'] as num?)?.toInt() ?? 0,
      );
    } catch (error) {
      debugPrint('[SupabaseManager] 가챠 천장 데이터 조회 실패: $error');
      return null;
    }
  }

  /// `profiles.character_pity_count`/`pet_pity_count`/`equipment_pity_count`
  /// 를 덮어쓴다 — [updatePrestigeData]와 같은 "로컬이 먼저 확정한 값을
  /// 그대로 push" 관례. [PityManager.rollAndConsumePity]가 호출될 때마다
  /// (=가챠를 뽑을 때마다) 호출한다.
  Future<void> updatePityData({required int character, required int pet, required int equipment}) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client
          .from(_profilesTable)
          .update({
            'character_pity_count': character,
            'pet_pity_count': pet,
            'equipment_pity_count': equipment,
          })
          .eq('id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] 가챠 천장 데이터 동기화 실패: $error');
    }
  }

  // ── 업적 (AchievementManager 전용) ─────────────────────────────────
  //
  // 누적 카운터(total_monster_kills/total_gacha_pulls)는 다른 매니저들의
  // 스칼라 카운터(prestige_core_points 등)와 같은 관례로 profiles의 평평한
  // 컬럼에 저장한다. 반면 "수령한 업적 목록"은 카테고리×단계 조합만큼
  // 계속 늘어나는 목록형 데이터라 profiles 컬럼 하나로 표현하기 부적절해
  // — 전용 테이블 `user_achievements`(user_id, achievement_key 유니크)에
  // 한 행씩 저장한다. 실제 컬럼/테이블 스키마는 요구사항에 정확한 이름이
  // 없어 이 장르에서 흔히 쓰는 최소 구성으로 가정했다 — 실제 이름이
  // 다르면 이 섹션과 [AchievementManager]만 고치면 된다.
  static const String _userAchievementsTable = 'user_achievements';

  /// 현재 유저의 누적 카운터(profiles)와 이미 수령한 업적 키 목록
  /// (user_achievements)을 함께 가져온다 — 못 불러오면 null(호출부가 로컬
  /// 캐시를 유지).
  Future<({int monsterKills, int gachaPulls, Set<String> claimedKeys})?> fetchAchievementData() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final Map<String, dynamic>? profileRow = await _client
          .from(_profilesTable)
          .select('total_monster_kills, total_gacha_pulls')
          .eq('id', userId)
          .maybeSingle();
      final List<dynamic> claimedRows = await _client
          .from(_userAchievementsTable)
          .select('achievement_key')
          .eq('user_id', userId);

      return (
        monsterKills: (profileRow?['total_monster_kills'] as num?)?.toInt() ?? 0,
        gachaPulls: (profileRow?['total_gacha_pulls'] as num?)?.toInt() ?? 0,
        claimedKeys: claimedRows
            .cast<Map<String, dynamic>>()
            .map((row) => row['achievement_key'] as String)
            .toSet(),
      );
    } catch (error) {
      debugPrint('[SupabaseManager] 업적 데이터 조회 실패: $error');
      return null;
    }
  }

  /// `profiles.total_monster_kills`/`total_gacha_pulls`를 덮어쓴다 —
  /// [updatePityData]와 같은 "로컬이 먼저 확정한 값을 그대로 push" 관례.
  /// [AchievementManager.claimTier]가 성공할 때마다 호출한다(누적
  /// 카운터는 매 처치/뽑기마다 서버에 쓰면 너무 잦아, 실제로 보상을 받는
  /// 시점에만 그때까지의 누적값을 함께 백업한다).
  Future<void> updateAchievementCounters({required int monsterKills, required int gachaPulls}) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client
          .from(_profilesTable)
          .update({'total_monster_kills': monsterKills, 'total_gacha_pulls': gachaPulls})
          .eq('id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] 업적 누적 카운터 동기화 실패: $error');
    }
  }

  /// [key](예: `'monsterKill:100'`)를 `user_achievements`에 1행 기록한다 —
  /// `(user_id, achievement_key)` 유니크 제약과 충돌해도(중복 수령 시도)
  /// 조용히 덮어쓰기만 하고 에러를 던지지 않도록 upsert를 쓴다.
  Future<void> claimAchievement(String key) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client
          .from(_userAchievementsTable)
          .upsert({'user_id': userId, 'achievement_key': key}, onConflict: 'user_id,achievement_key');
    } catch (error) {
      debugPrint('[SupabaseManager] 업적 수령 기록 실패: $error');
    }
  }

  // ── 펫 (EquipmentManager 전용) ──────────────────────────────────────
  //
  // 펫은 이 프로젝트에서 별도 모델이 아니라 `EquipType.pet`인 [Equipment]
  // 객체다(캐릭터/장비와 동일 구조). `Equipment` 모델은 앞으로도 필드가
  // 늘어날 수 있어, `user_pets.data`에 [Equipment.toJson] 결과 전체를
  // JSONB로 그대로 저장한다 — 필드가 추가될 때마다 SQL 컬럼을 새로 맞출
  // 필요가 없다. 실제 테이블/컬럼 스키마는 요구사항에 정확한 이름이 없어
  // 이 장르에서 흔히 쓰는 최소 구성으로 가정했다 — 실제 이름이 다르면 이
  // 섹션만 고치면 된다.
  static const String _userPetsTable = 'user_pets';

  /// 현재 유저가 보유한 펫 전체(`user_pets`, 각 행의 `data`가 [Equipment
  /// .toJson] 결과) — 실패하면(오프라인 등) 빈 리스트, 호출부
  /// ([EquipmentManager])가 로컬 상태를 그대로 유지한다.
  Future<List<Map<String, dynamic>>> fetchUserPets() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return const [];
      }
      final List<dynamic> rows =
          await _client.from(_userPetsTable).select('id, data').eq('user_id', userId);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 펫 목록 조회 실패: $error');
      return const [];
    }
  }

  /// 현재 유저의 `user_pets` 행을 [pets]로 통째로 맞춘다(기존 행 전부
  /// 삭제 후 재삽입) — 펫은 수십 마리 수준으로 적어 부분 갱신보다 훨씬
  /// 단순하고, 뽑기로 새로 생긴/분해로 사라진 펫이 서버에 밀린 채로 남는
  /// 일이 없다. [EquipmentManager.saveEquipment]가 호출될 때마다(=펫이든
  /// 아니든 장비 상태가 바뀔 때마다) 함께 호출된다.
  Future<void> syncUserPets(List<Map<String, dynamic>> pets) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client.from(_userPetsTable).delete().eq('user_id', userId);
      if (pets.isEmpty) {
        return;
      }
      await _client.from(_userPetsTable).insert([
        for (final Map<String, dynamic> pet in pets)
          {'id': pet['id'], 'user_id': userId, 'data': pet},
      ]);
    } catch (error) {
      debugPrint('[SupabaseManager] 펫 목록 동기화 실패: $error');
    }
  }

  /// 현재 유저의 `profiles.equipped_pet_id`(장착 중인 펫의 [Equipment.id],
  /// 없으면 null) — 못 불러오면 null(호출부가 미장착으로 안전하게 취급).
  Future<String?> fetchEquippedPetId() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final Map<String, dynamic>? row = await _client
          .from(_profilesTable)
          .select('equipped_pet_id')
          .eq('id', userId)
          .maybeSingle();
      return row?['equipped_pet_id'] as String?;
    } catch (error) {
      debugPrint('[SupabaseManager] 장착 펫 id 조회 실패: $error');
      return null;
    }
  }

  /// `profiles.equipped_pet_id`를 덮어쓴다 — [petId]가 null이면 미장착
  /// 상태로 저장한다.
  Future<void> updateEquippedPetId(String? petId) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client.from(_profilesTable).update({'equipped_pet_id': petId}).eq('id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] 장착 펫 id 동기화 실패: $error');
    }
  }

  static const String _towerFloorsTable = 'tower_floors';

  /// 무한의 탑 층별 몬스터 스탯/보상 테이블 전체를 내려받는다 — 로그인
  /// 여부와 무관한 공개 데이터라 `currentUserId` 체크 없이 그대로 조회한다
  /// ([fetchConsumableCatalog]와 같은 성격). 실패하면(오프라인 등) 빈
  /// 리스트 — 호출부([TowerFloorManager])가 이전에 캐시해 둔 테이블을
  /// 그대로 유지한다.
  Future<List<Map<String, dynamic>>> fetchTowerFloors() async {
    try {
      final List<dynamic> rows = await _client.from(_towerFloorsTable).select();
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 무한의 탑 층 테이블 조회 실패: $error');
      return const [];
    }
  }

  static const String _petStatMetadataTable = 'pet_stat_metadata';

  /// (스탯 키, 등급)별 펫 특수 스탯 값 범위 테이블 전체를 내려받는다 —
  /// 로그인 여부와 무관한 공개 데이터([fetchTowerFloors]와 같은 성격).
  /// 실패하면(오프라인 등) 빈 리스트 — 호출부([PetStatMetadataManager])가
  /// 이전에 캐시해 둔 값을 그대로 유지한다.
  Future<List<Map<String, dynamic>>> fetchPetStatMetadata() async {
    try {
      final List<dynamic> rows = await _client.from(_petStatMetadataTable).select();
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 펫 스탯 메타데이터 조회 실패: $error');
      return const [];
    }
  }

  // ── 유물 (ArtifactManager 전용) ─────────────────────────────────────
  //
  // `artifacts`(카탈로그: id/name/stat_key/value_per_level/max_level)와
  // `user_artifacts`(유저 진행도: user_id/artifact_id/level/fragment_count,
  // PK(user_id, artifact_id))로 나눈다 — [PetStatMetadataManager]와 같은
  // 이유(카탈로그는 로그인 여부와 무관한 공개 참조 데이터, 진행도는 유저별
  // 비공개 데이터)로 테이블을 분리했다.
  static const String _artifactsTable = 'artifacts';
  static const String _userArtifactsTable = 'user_artifacts';

  /// 유물 카탈로그 전체를 내려받는다 — 로그인 여부와 무관한 공개 데이터
  /// ([fetchPetStatMetadata]와 같은 성격). 실패하면(오프라인 등) 빈 리스트
  /// — 호출부([ArtifactManager])가 이전에 캐시해 둔 카탈로그를 유지한다.
  Future<List<Map<String, dynamic>>> fetchArtifactCatalog() async {
    try {
      final List<dynamic> rows = await _client.from(_artifactsTable).select();
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 유물 카탈로그 조회 실패: $error');
      return const [];
    }
  }

  /// 현재 유저가 보유한 유물 진행도(레벨/조각 수) 전체를 내려받는다.
  Future<List<Map<String, dynamic>>> fetchUserArtifacts() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return const [];
      }
      final List<dynamic> rows =
          await _client.from(_userArtifactsTable).select().eq('user_id', userId);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 유물 진행도 조회 실패: $error');
      return const [];
    }
  }

  /// 유물 하나([artifactId])의 레벨/조각 수를 덮어쓴다 — 가챠로 조각을
  /// 얻거나 레벨업할 때마다 호출한다. `(user_id, artifact_id)` 유니크
  /// 제약과 충돌해도(이미 있는 행) 조용히 덮어쓰도록 upsert를 쓴다
  /// ([SupabaseManager.claimAchievement]와 같은 관례).
  Future<void> syncUserArtifact({
    required String artifactId,
    required int level,
    required int fragmentCount,
  }) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client.from(_userArtifactsTable).upsert({
        'user_id': userId,
        'artifact_id': artifactId,
        'level': level,
        'fragment_count': fragmentCount,
      }, onConflict: 'user_id,artifact_id');
    } catch (error) {
      debugPrint('[SupabaseManager] 유물 진행도 동기화 실패: $error');
    }
  }

  // ── 룬 (RuneManager 전용) ───────────────────────────────────────────
  //
  // `user_runes`(id uuid PK, user_id, type, stat_key, base_value,
  // value_per_level, level, equipped_slot nullable) — 룬 한 개가 한 행.
  // `profiles.rune_fragments`(정수, 기본 0)로 재화(룬 조각)를 관리한다
  // ([highest_reached_chapter]와 같은 단일 컬럼 관례).
  static const String _userRunesTable = 'user_runes';

  Future<List<Map<String, dynamic>>> fetchUserRunes() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return const [];
      }
      final List<dynamic> rows =
          await _client.from(_userRunesTable).select().eq('user_id', userId);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 룬 목록 조회 실패: $error');
      return const [];
    }
  }

  /// [runeJson](`Rune.toJson()`)을 그대로 upsert한다 — 새 룬 생성/레벨업/
  /// 장착·해제 전부 이 메서드 하나로 동기화한다.
  Future<void> upsertUserRune(Map<String, dynamic> runeJson) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client.from(_userRunesTable).upsert({
        'user_id': userId,
        ...runeJson,
      });
    } catch (error) {
      debugPrint('[SupabaseManager] 룬 동기화 실패: $error');
    }
  }

  /// 합성으로 소모된 재료 룬들을 서버에서도 지운다.
  Future<void> deleteUserRunes(List<String> runeIds) async {
    if (runeIds.isEmpty) {
      return;
    }
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client
          .from(_userRunesTable)
          .delete()
          .eq('user_id', userId)
          .inFilter('id', runeIds);
    } catch (error) {
      debugPrint('[SupabaseManager] 룬 삭제 동기화 실패: $error');
    }
  }

  /// 현재 유저의 `profiles.rune_fragments` — 못 불러오면 null(호출부가
  /// 로컬 캐시를 유지).
  Future<int?> fetchRuneFragments() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final Map<String, dynamic>? row = await _client
          .from(_profilesTable)
          .select('rune_fragments')
          .eq('id', userId)
          .maybeSingle();
      return (row?['rune_fragments'] as num?)?.toInt();
    } catch (error) {
      debugPrint('[SupabaseManager] 룬 조각 조회 실패: $error');
      return null;
    }
  }

  Future<void> updateRuneFragments(int amount) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client.from(_profilesTable).update({'rune_fragments': amount}).eq('id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] 룬 조각 동기화 실패: $error');
    }
  }

  // ── 신규 모험가 7일 출석 (RookieAttendanceManager 전용) ────────────────
  //
  // `rookie_attendance`(user_id PK, start_date date, claimed_days int[]) —
  // 유저당 한 행. 재설치만으로 7일 트랙이 다시 시작되지 않도록, 이미
  // 서버에 시작일이 있으면 그 값을 로컬보다 신뢰한다.
  static const String _rookieAttendanceTable = 'rookie_attendance';

  Future<Map<String, dynamic>?> fetchRookieAttendance() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      return await _client
          .from(_rookieAttendanceTable)
          .select()
          .eq('user_id', userId)
          .maybeSingle();
    } catch (error) {
      debugPrint('[SupabaseManager] 신규 모험가 출석 조회 실패: $error');
      return null;
    }
  }

  Future<void> upsertRookieAttendance({
    required String startDate,
    required List<int> claimedDays,
  }) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client.from(_rookieAttendanceTable).upsert({
        'user_id': userId,
        'start_date': startDate,
        'claimed_days': claimedDays,
      });
    } catch (error) {
      debugPrint('[SupabaseManager] 신규 모험가 출석 동기화 실패: $error');
    }
  }

  // ── 요일 던전 일일 입장 (WeekdayDungeonManager 전용) ──────────────────
  //
  // `daily_dungeon_entry`(user_id, entry_date date, remaining_free_entries,
  // extra_entries_purchased, PK(user_id, entry_date)) — 하루에 한 행,
  // 자정(NTP 기준)이 지나면 새 날짜로 새 행이 생긴다.
  static const String _dailyDungeonEntryTable = 'daily_dungeon_entry';

  /// 오늘 날짜 행 하나만 가져온다(entry_date 내림차순 최신 1건) — 날짜
  /// 비교는 호출부([WeekdayDungeonManager])가 한다.
  Future<Map<String, dynamic>?> fetchDailyDungeonEntry() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final List<dynamic> rows = await _client
          .from(_dailyDungeonEntryTable)
          .select()
          .eq('user_id', userId)
          .order('entry_date', ascending: false)
          .limit(1);
      if (rows.isEmpty) {
        return null;
      }
      return rows.first as Map<String, dynamic>;
    } catch (error) {
      debugPrint('[SupabaseManager] 요일 던전 입장 횟수 조회 실패: $error');
      return null;
    }
  }

  Future<void> upsertDailyDungeonEntry({
    required String date,
    required int remainingFreeEntries,
    required int extraEntriesPurchased,
  }) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client.from(_dailyDungeonEntryTable).upsert({
        'user_id': userId,
        'entry_date': date,
        'remaining_free_entries': remainingFreeEntries,
        'extra_entries_purchased': extraEntriesPurchased,
      }, onConflict: 'user_id,entry_date');
    } catch (error) {
      debugPrint('[SupabaseManager] 요일 던전 입장 횟수 동기화 실패: $error');
    }
  }

  // ── 장비 세트 효과 (EquipmentSetManager 전용) ────────────────────────
  //
  // `equipment_sets`(set_id, name, two_piece_stat, two_piece_value,
  // four_piece_stat, four_piece_value) — 로그인 여부와 무관한 공개
  // 참조 데이터. 실제 컬럼명이 다르면 이 메서드와
  // [EquipmentSetBonus.fromJson]만 고치면 된다([fetchCharacterMeta]와
  // 같은 성격의 가정).
  static const String _equipmentSetsTable = 'equipment_sets';

  Future<List<Map<String, dynamic>>> fetchEquipmentSets() async {
    try {
      final List<dynamic> rows = await _client.from(_equipmentSetsTable).select();
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 장비 세트 카탈로그 조회 실패: $error');
      return const [];
    }
  }

  // ── 액티브 스킬 (SkillManager 전용) ─────────────────────────────────
  //
  // `skill_metadata`(카탈로그: id/name/description/skill_type('active_aoe'|
  // 'active_buff')/base_power/power_per_level/base_cooldown/max_level/
  // level_up_gold_cost/buff_duration_seconds/buff_attack_power_bonus/
  // buff_attack_speed_bonus)와 `user_skills`(유저 진행도: user_id/skill_id/
  // level/is_equipped, PK(user_id, skill_id))로 나눈다 — [ArtifactManager]/
  // [PetStatMetadataManager]와 같은 이유(카탈로그는 로그인 여부와 무관한
  // 공개 참조 데이터, 진행도는 유저별 비공개 데이터)로 테이블을 분리했다.
  // 실제 컬럼명이 다르면 이 섹션과 [ActiveSkill.fromCatalogJson]만 고치면
  // 된다([fetchCharacterMeta]와 같은 성격의 가정).
  static const String _skillMetadataTable = 'skill_metadata';
  static const String _userSkillsTable = 'user_skills';

  /// 액티브 스킬 카탈로그 전체를 내려받는다 — 로그인 여부와 무관한 공개
  /// 데이터. 실패하면(오프라인 등) 빈 리스트 — 호출부([SkillManager])가
  /// 이전에 캐시해 둔 카탈로그를 유지한다.
  Future<List<Map<String, dynamic>>> fetchSkillMetadata() async {
    try {
      final List<dynamic> rows = await _client.from(_skillMetadataTable).select();
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 액티브 스킬 카탈로그 조회 실패: $error');
      return const [];
    }
  }

  /// 현재 유저가 보유한 액티브 스킬 진행도(레벨/장착 여부) 전체를 내려받는다.
  Future<List<Map<String, dynamic>>> fetchUserSkills() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return const [];
      }
      final List<dynamic> rows =
          await _client.from(_userSkillsTable).select().eq('user_id', userId);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 액티브 스킬 진행도 조회 실패: $error');
      return const [];
    }
  }

  /// 스킬 하나([skillId])의 레벨/장착 여부를 덮어쓴다 — 레벨업하거나
  /// 장착/해제할 때마다 호출한다. `(user_id, skill_id)` 유니크 제약과
  /// 충돌해도(이미 있는 행) 조용히 덮어쓰도록 upsert를 쓴다.
  Future<void> syncUserSkill({
    required String skillId,
    required int level,
    required bool isEquipped,
  }) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client.from(_userSkillsTable).upsert({
        'user_id': userId,
        'skill_id': skillId,
        'level': level,
        'is_equipped': isEquipped,
      }, onConflict: 'user_id,skill_id');
    } catch (error) {
      debugPrint('[SupabaseManager] 액티브 스킬 진행도 동기화 실패: $error');
    }
  }

  // ── 캐릭터 메타데이터 (CharacterMetaManager 전용) ─────────────────
  //
  // `characters` 컬럼은 이 프로젝트에 아직 실제 테이블이 없어(요구사항에
  // 정확한 컬럼명이 없어) 이 장르에서 흔히 쓰는 최소 구성으로 가정했다:
  // character_id(text, PK — Equipment.gradeBadgeLabel과 동일한 형식, 예:
  // 'N1'), attack_type(text, 'melee'|'ranged'). 실제 테이블/컬럼명이
  // 다르면 이 섹션과 [CharacterMeta].fromJson만 고치면 된다.
  static const String _charactersTable = 'characters';

  /// 캐릭터 메타데이터 테이블 전체를 내려받는다 — 로그인 여부와 무관한
  /// 공개 데이터라 `currentUserId` 체크 없이 그대로 조회한다
  /// ([fetchTowerFloors]와 같은 성격). 실패하면(오프라인 등) 빈 리스트 —
  /// 호출부([CharacterMetaManager])가 이전에 캐시해 둔 값을 그대로 유지한다.
  Future<List<Map<String, dynamic>>> fetchCharacterMeta() async {
    try {
      final List<dynamic> rows = await _client.from(_charactersTable).select();
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 캐릭터 메타데이터 조회 실패: $error');
      return const [];
    }
  }

  // ── 물약/호감도 상점 (PotionManager 전용) ─────────────────────────
  //
  // consumable_items/user_consumables/user_daily_shop_limits 컬럼은 전부
  // 유저가 직접 확인해 준 실제 스키마([ShopConsumableEntry] 문서 참고)를
  // 그대로 쓴다. user_daily_shop_limits는 `user_id, item_id,
  // last_purchase_date, purchased_count`.

  static const String _consumableItemsTable = 'consumable_items';
  static const String _userConsumablesTable = 'user_consumables';
  static const String _dailyShopLimitsTable = 'user_daily_shop_limits';

  // ── 월드보스 (WorldBossManager 전용) ───────────────────────────────
  //
  // world_boss_config/user_world_boss 컬럼은 전부 유저가 직접 확인해 준
  // 실제 스키마를 쓴다: world_boss_config(schedule_hours,
  // duration_minutes, max_hp), user_world_boss(tickets_used,
  // extra_tickets, last_played_date, total_damage_dealt,
  // last_boss_session), world_boss_ranking_rewards(rank_min, rank_max,
  // reward_type, reward_amount). [fetchWorldBossRanking]의 `profiles(nickname)`
  // 임베드는 user_world_boss.user_id → profiles.id 외래키가 잡혀 있다는
  // 전제다 — PostgREST가 그 관계를 못 찾으면 이 쿼리만 별도로 손보면 된다.
  static const String _worldBossConfigTable = 'world_boss_config';
  static const String _userWorldBossTable = 'user_world_boss';
  static const String _worldBossRankingRewardsTable = 'world_boss_ranking_rewards';

  static const String _monsterDropTableTable = 'monster_drop_table';

  /// 몬스터 처치 드랍 테이블 전체를 내려받는다 — 로그인 여부와 무관한
  /// 공개 데이터라 `currentUserId` 체크 없이 그대로 조회한다
  /// ([fetchConsumableCatalog]와 같은 성격). 실패하면(오프라인 등) 빈
  /// 리스트 — 호출부([MonsterDropTableManager])가 이전에 캐시해 둔
  /// 테이블을 그대로 유지한다.
  Future<List<Map<String, dynamic>>> fetchMonsterDropTable() async {
    try {
      final List<dynamic> rows = await _client.from(_monsterDropTableTable).select();
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 몬스터 드랍 테이블 조회 실패: $error');
      return const [];
    }
  }

  /// 물약/호감도 아이템 카탈로그 전체를 내려받는다 — 로그인 여부와
  /// 무관한 공개 데이터라 `currentUserId` 체크 없이 그대로 조회한다.
  /// 실패하면(오프라인 등) 빈 리스트 — 호출부([PotionManager])가 이전에
  /// 캐시해 둔 카탈로그를 그대로 유지한다.
  Future<List<Map<String, dynamic>>> fetchConsumableCatalog() async {
    try {
      final List<dynamic> rows = await _client.from(_consumableItemsTable).select();
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 소모품 카탈로그 조회 실패: $error');
      return const [];
    }
  }

  /// 현재 유저가 보유한 모든 소모품의 (item_id -> count) 맵을 내려받는다.
  ///
  /// [주의] 아래 6개 메서드는 전부 `currentUserId` 접근 자체까지 포함해서
  /// try/catch로 감싼다 — `Supabase.initialize()`가 끝나기 전에 이 메서드가
  /// 불리면(정상 앱 흐름에서는 안 나지만, 단위 테스트처럼 Supabase 초기화를
  /// 건너뛴 환경에서는 날 수 있다) `Supabase.instance` 접근 자체가 예외를
  /// 던지는데, 이걸 try 블록 밖에 두면 예외가 그대로 새어 나가
  /// [PotionManager]의 `unawaited` 백그라운드 동기화 호출에서 처리되지 않은
  /// Future 에러가 된다.
  Future<Map<String, int>> fetchUserConsumables() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return const {};
      }
      // 실제 컬럼명은 "count"가 아니라 "quantity"다 — 예전엔 "count"로
      // 쿼리를 날려서 PGRST204("Could not find the 'count' column")
      // 에러가 났었다(그 전엔 아예 다른 문제로 GROUP BY 에러가 났었고,
      // 그건 quantity로 바꾸면서 "count"라는 예약어 취급 문제 자체가
      // 사라져 따옴표도 더 필요 없다).
      final List<dynamic> rows = await _client
          .from(_userConsumablesTable)
          .select('item_id, quantity')
          .eq('user_id', userId);
      // item_id가 실제로는 정수 PK/FK 컬럼이라 `as String`으로 캐스팅하면
      // "type 'int' is not a subtype of type 'String'"이 난다([ShopConsumableEntry
      // .fromJson]의 `json['id'].toString()`과 같은 이유) — 앱 전체가 소모품
      // id를 String으로 다루므로(PotionManager/ConsumableManager 등) 타입
      // 자체를 int로 바꾸는 대신 안전하게 문자열로 변환만 해 준다.
      return {
        for (final dynamic row in rows)
          row['item_id'].toString(): (row['quantity'] as num).toInt(),
      };
    } catch (error) {
      debugPrint('[SupabaseManager] 소모품 보유 목록 조회 실패: $error');
      return const {};
    }
  }

  /// [itemId]의 보유 개수를 [count]로(증감이 아니라 절대값) 갱신한다 —
  /// [GameManager.gold]를 그대로 넘기는 [updateGold]와 같은 관례.
  Future<void> upsertUserConsumable(String itemId, int count) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client.from(_userConsumablesTable).upsert({
        'user_id': userId,
        'item_id': itemId,
        'quantity': count,
      });
    } catch (error) {
      debugPrint('[SupabaseManager] 소모품 보유 개수 동기화 실패($itemId): $error');
    }
  }

  /// 장착된 물약 id — 해제 시에는 [potionId]에 null을 그대로 넘기면
  /// 컬럼도 NULL로 갱신된다.
  Future<void> updateEquippedPotion(String? potionId) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client.from(_profilesTable).update({'equipped_potion_id': potionId}).eq('id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] 장착 물약 동기화 실패: $error');
    }
  }

  /// 자동 물약 사용 HP% 임계값(0.0~1.0) 동기화.
  Future<void> updateAutoPotionThreshold(double threshold) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client
          .from(_profilesTable)
          .update({'auto_potion_hp_threshold': threshold})
          .eq('id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] 자동 물약 임계값 동기화 실패: $error');
    }
  }

  /// [date](`yyyy-MM-dd`)에 해당하는, 이 유저의 아이템별 "제한된 코인 구매"
  /// 횟수를 전부 내려받는다(item_id -> count) — [daily_coin_limit]이 걸린
  /// 아이템은 각자 독립적으로 하루 횟수를 추적하므로(예: SSR 물약 A는
  /// 오늘 3번, SSSR 물약 B는 오늘 1번, 서로 무관) 단일 카운터가 아니라
  /// 아이템별 맵으로 관리한다. 그날 기록이 없는 아이템은 이 맵에 아예
  /// 나타나지 않는다(호출부가 `?? 0`으로 처리).
  Future<Map<String, int>> fetchDailyCoinPurchaseCounts(String date) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return const {};
      }
      final List<dynamic> rows = await _client
          .from(_dailyShopLimitsTable)
          .select('item_id, purchased_count')
          .eq('user_id', userId)
          .eq('last_purchase_date', date);
      // fetchUserConsumables()와 같은 이유로 `as String` 대신 `.toString()`.
      return {
        for (final dynamic row in rows)
          row['item_id'].toString(): (row['purchased_count'] as num).toInt(),
      };
    } catch (error) {
      debugPrint('[SupabaseManager] 일일 코인 구매 횟수 조회 실패: $error');
      return const {};
    }
  }

  /// [date]에 [itemId]를 "제한된 코인 구매" 경로로 산 횟수를 [count]
  /// (절대값)로 갱신한다.
  Future<void> upsertDailyCoinPurchaseCount(String itemId, String date, int count) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client.from(_dailyShopLimitsTable).upsert({
        'user_id': userId,
        'item_id': itemId,
        'last_purchase_date': date,
        'purchased_count': count,
      });
    } catch (error) {
      debugPrint('[SupabaseManager] 일일 코인 구매 횟수 동기화 실패($itemId): $error');
    }
  }

  /// 월드보스 스케줄/체력 설정(단일 행) — 로그인 여부와 무관한 공개
  /// 데이터라 `currentUserId` 체크 없이 조회한다. 실패하거나 행이 없으면
  /// null — 호출부([WorldBossManager])가 기본값을 그대로 유지한다.
  Future<Map<String, dynamic>?> fetchWorldBossConfig() async {
    try {
      final List<dynamic> rows = await _client.from(_worldBossConfigTable).select().limit(1);
      if (rows.isEmpty) {
        return null;
      }
      return rows.first as Map<String, dynamic>;
    } catch (error) {
      debugPrint('[SupabaseManager] 월드보스 설정 조회 실패: $error');
      return null;
    }
  }

  /// 현재 유저의 월드보스 티켓 사용 현황(tickets_used/extra_tickets) 한
  /// 행을 내려받는다. 아직 행이 없는(한 번도 도전 안 한) 유저는 null —
  /// 호출부가 기본값(0/0)을 그대로 쓴다.
  Future<Map<String, dynamic>?> fetchUserWorldBoss() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final List<dynamic> rows =
          await _client.from(_userWorldBossTable).select().eq('user_id', userId).limit(1);
      if (rows.isEmpty) {
        return null;
      }
      return rows.first as Map<String, dynamic>;
    } catch (error) {
      debugPrint('[SupabaseManager] 월드보스 유저 데이터 조회 실패: $error');
      return null;
    }
  }

  /// [ticketsUsed]/[extraTickets]/[playedDate]/[totalDamageDealt]/
  /// [bossSession](전부 절대값)으로 갱신한다 — 티켓 소비, 충전권 사용,
  /// 전투 종료 후 데미지 기록 세 경로 모두 이 메서드 하나로 동기화한다.
  Future<void> upsertUserWorldBoss({
    required int ticketsUsed,
    required int extraTickets,
    required String playedDate,
    required int totalDamageDealt,
    required String bossSession,
  }) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client.from(_userWorldBossTable).upsert({
        'user_id': userId,
        'tickets_used': ticketsUsed,
        'extra_tickets': extraTickets,
        'last_played_date': playedDate,
        'total_damage_dealt': totalDamageDealt,
        'last_boss_session': bossSession,
      });
    } catch (error) {
      debugPrint('[SupabaseManager] 월드보스 티켓 동기화 실패: $error');
    }
  }

  /// [sessionId]와 같은 보스 리젠 회차(`last_boss_session`)에 참여한
  /// 유저들을 [total_damage_dealt] 내림차순으로 최대 100명까지 내려받는다
  /// — `profiles(nickname)` 임베드로 닉네임까지 한 번에 가져온다. 로그인
  /// 여부와 무관하게(다른 유저 기록 열람) `currentUserId` 체크 없이
  /// 조회한다. 실패하면 빈 리스트 — 호출부([WorldBossRankingDialog])가
  /// "랭킹을 불러오지 못했습니다" 상태를 보여준다.
  Future<List<Map<String, dynamic>>> fetchWorldBossRanking(String sessionId) async {
    try {
      final List<dynamic> rows = await _client
          .from(_userWorldBossTable)
          .select('user_id, total_damage_dealt, profiles(nickname)')
          .eq('last_boss_session', sessionId)
          .order('total_damage_dealt', ascending: false)
          .limit(100);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 월드보스 랭킹 조회 실패: $error');
      return const [];
    }
  }

  /// 순위 구간별 차등 보상 테이블 전체(랭킹이 낮을수록 뒤에 오도록
  /// rank_min 오름차순) — 로그인 여부와 무관한 공개 데이터.
  Future<List<Map<String, dynamic>>> fetchWorldBossRankingRewards() async {
    try {
      final List<dynamic> rows = await _client
          .from(_worldBossRankingRewardsTable)
          .select()
          .order('rank_min', ascending: true);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 월드보스 랭킹 보상 조회 실패: $error');
      return const [];
    }
  }

  /// 방금 마감된 보스 리젠 회차([sessionId])의 랭킹 보상을 서버 RPC
  /// (`distribute_world_boss_rewards`)로 정산한다 — 우편함(mailbox)에
  /// 1~100위 우편을 발송하는 실제 로직은 DB 함수 안에 있고, 그 함수가
  /// 이미 지급된 세션을 다시 지급하지 않도록 중복 처리를 막아준다. 그래서
  /// 호출부([WorldBossManager])는 세션이 끝난 걸 감지할 때마다 실패
  /// 걱정 없이 그냥 한 번 찔러주기만 하면 된다 — 이 메서드도 그 관례대로
  /// 예외를 삼키고 조용히 로그만 남긴다.
  Future<void> distributeWorldBossRewards(String sessionId) async {
    try {
      await _client.rpc('distribute_world_boss_rewards', params: {'p_session_id': sessionId});
    } catch (error) {
      debugPrint('[SupabaseManager] 월드보스 보상 정산 RPC 실패: $error');
    }
  }

  // ── 우편함 (MailboxManager 전용) ─────────────────────────────────
  //
  // `mailbox` 컬럼은 유저가 직접 확인해 준 실제 스키마를 쓴다: `id`,
  // `user_id`, `title`, `content`, `reward_type`, `reward_amount`,
  // `is_claimed`, `created_at`, `expires_at`([MailboxItem] 문서 참고).
  static const String _mailboxTable = 'mailbox';

  /// 현재 유저의 우편함 전체(수령 여부 무관, 최신순)를 내려받는다.
  Future<List<Map<String, dynamic>>> fetchMailbox() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return const [];
      }
      final List<dynamic> rows = await _client
          .from(_mailboxTable)
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 우편함 조회 실패: $error');
      return const [];
    }
  }

  /// 우편 1통을 수령 처리한다(`is_claimed = true`). `user_id`까지 함께
  /// 조건에 걸어 다른 유저의 우편을 실수로/악의적으로 건드릴 수 없게
  /// 한다(RLS가 이미 막아주더라도 방어적으로 한 번 더).
  Future<void> claimMail(String mailId) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client
          .from(_mailboxTable)
          .update({'is_claimed': true})
          .eq('id', mailId)
          .eq('user_id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] 우편 수령 동기화 실패($mailId): $error');
    }
  }

  /// [mailIds] 여러 통을 한 번에 수령 처리한다 — "모두 수령" 버튼 전용.
  Future<void> claimMailBulk(List<String> mailIds) async {
    if (mailIds.isEmpty) {
      return;
    }
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client
          .from(_mailboxTable)
          .update({'is_claimed': true})
          .inFilter('id', mailIds)
          .eq('user_id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] 우편 일괄 수령 동기화 실패: $error');
    }
  }

  // ── 길드 (GuildManager 전용) ─────────────────────────────────────
  //
  // `guilds`/`guild_members` 컬럼은 요구사항에 명시되지 않아, 이 장르에서
  // 흔히 쓰는 최소 구성으로 가정했다: guilds(`id`, `name`, `emblem`,
  // `level`, `exp`, `notice`, `master_id`), guild_members(`user_id`,
  // `guild_id`, `role`, `contribution`, `last_check_in`) — 실제 컬럼명이
  // 다르면 이 섹션의 메서드들과 [GuildInfo]/[GuildMember].fromJson만
  // 고치면 된다. `profiles.guild_coin`(단수형)은 유저가 직접 확인해 준
  // 실제 컬럼.
  static const String _guildsTable = 'guilds';
  static const String _guildMembersTable = 'guild_members';

  /// 현재 유저의 소속 길드 행(`guild_members`) — 없으면(미가입) null.
  Future<Map<String, dynamic>?> fetchMyGuildMembership() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final List<dynamic> rows = await _client
          .from(_guildMembersTable)
          .select()
          .eq('user_id', userId)
          .limit(1);
      if (rows.isEmpty) {
        return null;
      }
      return rows.first as Map<String, dynamic>;
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 가입 여부 조회 실패: $error');
      return null;
    }
  }

  /// [guildId] 길드의 상세 정보(`guilds` 한 행) — 로그인 여부와 무관한
  /// 공개 데이터.
  Future<Map<String, dynamic>?> fetchGuild(String guildId) async {
    try {
      final List<dynamic> rows =
          await _client.from(_guildsTable).select().eq('id', guildId).limit(1);
      if (rows.isEmpty) {
        return null;
      }
      return rows.first as Map<String, dynamic>;
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 정보 조회 실패: $error');
      return null;
    }
  }

  /// 길드 리스트([GuildLobbyScreen]) — 레벨 내림차순, 최대 100개.
  /// `guild_members(count)` 임베드로 인원수까지 한 번에 가져온다.
  Future<List<Map<String, dynamic>>> fetchGuildList() async {
    try {
      final List<dynamic> rows = await _client
          .from(_guildsTable)
          .select('id, name, emblem, level, guild_members(count)')
          .order('level', ascending: false)
          .limit(100);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 리스트 조회 실패: $error');
      return const [];
    }
  }

  /// [name]을 이미 다른 길드가 쓰고 있는지 — 조회 자체가 실패하면
  /// 보수적으로 "이미 사용 중"(true)으로 처리해, 중복 이름으로 길드가
  /// 생성될 위험을 피한다([_isNicknameTaken]과 반대로 실패 시 안전한
  /// 쪽이 여기서는 true라는 점에 주의).
  Future<bool> isGuildNameTaken(String name) async {
    try {
      final List<dynamic> rows =
          await _client.from(_guildsTable).select('id').eq('name', name).limit(1);
      return rows.isNotEmpty;
    } catch (error) {
      debugPrint('[SupabaseManager] 길드명 중복 확인 실패: $error');
      return true;
    }
  }

  /// 길드를 창설하고(guilds 1행) 창설자를 즉시 master로 가입시킨다
  /// (guild_members 1행) — 성공하면 새 길드 id, 둘 중 하나라도 실패하면
  /// null(재화는 이미 [GuildManager]가 먼저 차감해 뒀으므로, 여기서
  /// 실패해도 되돌려주는 처리는 호출부 책임이 아니라 그대로 손실로
  /// 남는다 — 서버 함수 없이 클라이언트 2단계 insert라 어쩔 수 없는
  /// 한계다).
  Future<String?> createGuild({required String name, required String emblem}) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final Map<String, dynamic> row = await _client
          .from(_guildsTable)
          .insert({
            'name': name,
            'emblem': emblem,
            'level': 1,
            'exp': 0,
            'notice': '',
            'master_id': userId,
          })
          .select()
          .single();
      final String guildId = row['id'].toString();
      await _client.from(_guildMembersTable).insert({
        'user_id': userId,
        'guild_id': guildId,
        'role': 'master',
        'contribution': 0,
      });
      return guildId;
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 창설 실패: $error');
      return null;
    }
  }

  /// [guildId]에 일반 길드원(`role: 'member'`)으로 즉시 가입한다.
  Future<bool> joinGuild(String guildId) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return false;
      }
      await _client.from(_guildMembersTable).insert({
        'user_id': userId,
        'guild_id': guildId,
        'role': 'member',
        'contribution': 0,
      });
      return true;
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 가입 실패: $error');
      return false;
    }
  }

  /// 길드 출석체크를 서버 RPC(`guild_check_in`)로 원자적으로 처리한다 —
  /// exp/guild_coin 증가와 "오늘 이미 체크인했는지" 판정까지 전부 DB
  /// 함수 안에서 이뤄진다. 예전엔 클라이언트가 로컬 exp를 읽어 더한 뒤
  /// 통째로 덮어쓰는 방식이라, 여러 멤버가 거의 동시에 체크인하면 한쪽
  /// 증가분이 유실될 수 있는 경쟁 조건이 있었다 — 그 계산/갱신을 서버
  /// RPC 하나로 옮겨 원자성을 보장한다.
  ///
  /// [주의] 다른 길드 메서드들과 마찬가지로 `currentUserId` 접근 자체까지
  /// 포함해서 try/catch로 감싼다 — `Supabase.initialize()`가 끝나기 전에
  /// (단위 테스트 등) 이 메서드가 불리면 `Supabase.instance` 접근 자체가
  /// 예외를 던지는데, 그 접근을 try 블록 밖(예: 호출부가 넘겨준 매개변수로
  /// 받는 방식)에 두면 [GuildManager.checkIn]이 await하는 이 Future
  /// 자체가 예외로 실패해 버린다.
  Future<bool> guildCheckIn({
    required String guildId,
    required int expAmount,
    required int coinAmount,
  }) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return false;
      }
      await _client.rpc(
        'guild_check_in',
        params: {
          'p_user_id': userId,
          'p_guild_id': guildId,
          'p_exp_amount': expAmount,
          'p_coin_amount': coinAmount,
        },
      );
      return true;
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 출석체크 RPC 실패: $error');
      return false;
    }
  }

  /// 길드 레벨(절대값)만 갱신한다 — exp 자체는 [guildCheckIn] RPC가 이미
  /// 원자적으로 반영했으므로, [GuildManager]가 로컬에서 계산한 레벨업
  /// 결과만 별도로 밀어 넣을 때 쓴다.
  Future<void> updateGuildLevel(String guildId, int level) async {
    try {
      await _client.from(_guildsTable).update({'level': level}).eq('id', guildId);
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 레벨 동기화 실패: $error');
    }
  }

  /// 길드 공지사항 갱신 — 길드장 전용(권한 체크는 [GuildManager]에서).
  Future<void> updateGuildNotice(String guildId, String notice) async {
    try {
      await _client.from(_guildsTable).update({'notice': notice}).eq('id', guildId);
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 공지 동기화 실패: $error');
    }
  }

  /// 길드 엠블럼 갱신 — 길드장 전용(권한 체크는 [GuildManager]에서).
  Future<void> updateGuildEmblem(String guildId, String emblem) async {
    try {
      await _client.from(_guildsTable).update({'emblem': emblem}).eq('id', guildId);
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 엠블럼 동기화 실패: $error');
    }
  }

  /// [guildId] 소속 멤버 전원을 기여도 내림차순으로 —
  /// `profiles(nickname, last_seen)` 임베드로 닉네임/최종 접속 시각까지
  /// 한 번에 가져온다.
  Future<List<Map<String, dynamic>>> fetchGuildMembers(String guildId) async {
    try {
      final List<dynamic> rows = await _client
          .from(_guildMembersTable)
          .select('user_id, role, contribution, profiles(nickname, last_seen)')
          .eq('guild_id', guildId)
          .order('contribution', ascending: false);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 길드원 목록 조회 실패: $error');
      return const [];
    }
  }

  // ── 길드 채팅 (GuildChatManager 전용) ────────────────────────────
  //
  // `guild_messages` 컬럼도 위 guilds/guild_members와 같은 관례로 가정한다:
  // id(uuid), guild_id(uuid, guilds.id 참조), user_id(uuid, auth.users.id
  // 참조), message(text), created_at(timestamptz). RLS로 "해당 길드
  // 멤버만 읽고/쓸 수 있음"을 강제한다는 전제라, 여기 클라이언트 코드는
  // guild_id로만 필터링하고 별도의 멤버십 검증을 다시 하지 않는다(서버
  // RLS가 이미 보장).
  static const String _guildMessagesTable = 'guild_messages';

  /// 채팅 탭 진입 시 최근 [limit]개 메시지를 오래된 순으로 가져온다 —
  /// `profiles(nickname)` 임베드로 발신자 닉네임까지 한 번에 가져온다.
  Future<List<Map<String, dynamic>>> fetchGuildMessages(String guildId, {int limit = 100}) async {
    try {
      final List<dynamic> rows = await _client
          .from(_guildMessagesTable)
          .select('id, guild_id, user_id, message, created_at, profiles(nickname)')
          .eq('guild_id', guildId)
          .order('created_at', ascending: false)
          .limit(limit);
      // 최신순으로 [limit]개를 자른 뒤(=최근 대화), 화면에는 오래된 순으로
      // 보여줘야 하므로 뒤집는다.
      return rows.cast<Map<String, dynamic>>().toList().reversed.toList();
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 채팅 내역 조회 실패: $error');
      return const [];
    }
  }

  /// [guildId]에 채팅 메시지 한 건을 보낸다 — 실제 화면 반영은 이 insert가
  /// 트리거하는 Realtime `postgres_changes` 이벤트([subscribeToGuildMessages])
  /// 가 처리하므로, 여기서는 성공 여부만 돌려주고 로컬 리스트에 낙관적으로
  /// 추가하지 않는다(같은 메시지가 두 번 보이는 것을 방지).
  Future<bool> sendGuildMessage({required String guildId, required String message}) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return false;
      }
      await _client.from(_guildMessagesTable).insert({
        'guild_id': guildId,
        'user_id': userId,
        'message': message,
      });
      return true;
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 채팅 전송 실패: $error');
      return false;
    }
  }

  /// [guildId]의 새 채팅 메시지(INSERT)를 실시간으로 구독한다 — 새 행이
  /// 생길 때마다 [onInsert]에 원본 row(Map)를 그대로 넘긴다(Realtime
  /// 페이로드는 `profiles` 임베드를 지원하지 않으므로, 닉네임 해석은
  /// 호출부([GuildMessage.fromJson]의 `resolveNickname`)가 담당한다).
  /// 반환된 채널은 화면을 떠날 때 반드시 [unsubscribeChannel]로 정리해야
  /// 한다 — 그러지 않으면 소켓 연결과 리스너가 계속 남아 있는다.
  /// 구독 생성 자체가 실패하면(예: 아직 `Supabase.initialize()`가 끝나기
  /// 전, 또는 Realtime 연결이 닫힌 상태) null — 이 파일의 다른 모든
  /// 공개 메서드와 같은 방어 관례([currentUserId] 접근까지 try 블록
  /// 안에서 감싸는 이유는 [guildCheckIn] 문서 참고). 호출부
  /// ([GuildChatManager.openChat])는 이미 `_channel` 필드가 nullable이라
  /// 별도 처리 없이 안전하게 null을 받아들인다.
  RealtimeChannel? subscribeToGuildMessages(
    String guildId,
    void Function(Map<String, dynamic> row) onInsert,
  ) {
    try {
      return _client
          .channel('guild_messages_$guildId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: _guildMessagesTable,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'guild_id',
              value: guildId,
            ),
            callback: (payload) => onInsert(payload.newRecord),
          )
          .subscribe();
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 채팅 구독 실패: $error');
      return null;
    }
  }

  /// [subscribeToGuildMessages]가 돌려준 채널 구독을 해제한다 —
  /// [GuildChatManager]가 채팅 탭을 떠날 때 호출한다.
  Future<void> unsubscribeChannel(RealtimeChannel channel) async {
    try {
      await _client.removeChannel(channel);
    } catch (error) {
      debugPrint('[SupabaseManager] 채널 구독 해제 실패: $error');
    }
  }

  /// [targetUserId]의 직책을 [role]('elder'|'member')로 바꾼다 — 길드장
  /// 전용(권한 체크는 [GuildManager]에서).
  Future<void> updateGuildMemberRole(String guildId, String targetUserId, String role) async {
    try {
      await _client
          .from(_guildMembersTable)
          .update({'role': role})
          .eq('guild_id', guildId)
          .eq('user_id', targetUserId);
    } catch (error) {
      debugPrint('[SupabaseManager] 길드원 직책 변경 실패: $error');
    }
  }

  /// [targetUserId]를 길드에서 추방(guild_members 행 삭제)한다 — 길드장
  /// 전용(권한 체크는 [GuildManager]에서).
  Future<void> kickGuildMember(String guildId, String targetUserId) async {
    try {
      await _client
          .from(_guildMembersTable)
          .delete()
          .eq('guild_id', guildId)
          .eq('user_id', targetUserId);
    } catch (error) {
      debugPrint('[SupabaseManager] 길드원 추방 실패: $error');
    }
  }

  /// 현재 유저가 [guildId] 길드를 자진 탈퇴한다 — `profiles.guild_coin`을
  /// 0으로 초기화하고 `guild_members` 행을 삭제한다(기여도는 그 행 자체가
  /// 지워지므로 함께 사라진다). 요구사항이 "순차적으로(또는 RPC를 통해)"라
  /// 두 쿼리를 순서대로 실행하는 방식을 택했다 — 둘 다 성공해야 true이고,
  /// 하나라도 실패하면(이미 실행된 나머지 하나를 되돌리지는 않는다. 두
  /// 쿼리를 하나의 트랜잭션으로 묶고 싶다면 `guild_check_in`처럼 RPC로
  /// 옮기는 게 정석이다) false — 호출부([GuildManager.leaveGuild])가 false를
  /// 받으면 로컬 상태를 건드리지 않는다.
  Future<bool> leaveGuild(String guildId) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return false;
      }
      await _client.from(_profilesTable).update({'guild_coin': 0}).eq('id', userId);
      await _client
          .from(_guildMembersTable)
          .delete()
          .eq('guild_id', guildId)
          .eq('user_id', userId);
      return true;
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 탈퇴 실패: $error');
      return false;
    }
  }

  /// 현재 유저의 `profiles.guild_coin`(단수형 — 유저가 직접 확인해 준 실제
  /// 컬럼명) — 못 불러오면 null(호출부가 로컬 캐시를 유지).
  Future<int?> fetchGuildCoins() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final Map<String, dynamic>? row = await _client
          .from(_profilesTable)
          .select('guild_coin')
          .eq('id', userId)
          .maybeSingle();
      return (row?['guild_coin'] as num?)?.toInt();
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 코인 조회 실패: $error');
      return null;
    }
  }

  /// `profiles.guild_coin`을 [amount](절대값)로 덮어쓴다 — [updateGold]와
  /// 같은 "낙관적 로컬 우선" 관례: [GuildManager]가 로컬에서 먼저 증감을
  /// 반영한 뒤 이 메서드로 그 최종값을 서버에 fire-and-forget으로 밀어
  /// 넣는다(길드 출석체크 자체는 여러 멤버의 공유 상태(exp)까지 얽혀 있어
  /// 여전히 `guild_check_in` RPC로 원자적으로 처리하지만, 길드 상점 구매/
  /// 길드 던전 보상처럼 이 유저 개인의 주화만 바뀌는 경로는 굳이 RPC를
  /// 거칠 필요가 없다).
  Future<void> updateGuildCoins(int amount) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client.from(_profilesTable).update({'guild_coin': amount}).eq('id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 코인 동기화 실패: $error');
    }
  }

  static const String _systemSettingsTable = 'system_settings';

  /// `system_settings(key, value)` 테이블에서 정수형 설정값 하나를 가져온다
  /// — 행이 없거나(아직 값을 안 넣음) 조회 자체가 실패하면(오프라인 등)
  /// [fallback]을 그대로 돌려준다. 특정 기능 하나에 종속되지 않은 범용
  /// 헬퍼라, 앞으로 다른 서버 설정값(예: 이벤트 배율)도 같은 테이블에
  /// 추가되면 이 메서드를 그대로 재사용하면 된다.
  Future<int> fetchSystemSettingInt(String key, {required int fallback}) async {
    try {
      final List<dynamic> rows = await _client
          .from(_systemSettingsTable)
          .select('value')
          .eq('key', key)
          .limit(1);
      if (rows.isEmpty) {
        return fallback;
      }
      final dynamic value = (rows.first as Map<String, dynamic>)['value'];
      if (value is num) {
        return value.toInt();
      }
      if (value is String) {
        return int.tryParse(value) ?? fallback;
      }
      return fallback;
    } catch (error) {
      debugPrint('[SupabaseManager] system_settings["$key"] 조회 실패: $error');
      return fallback;
    }
  }

  static const String _guildShopItemsTable = 'guild_shop_items';

  /// 길드 상점 카탈로그 전체를 내려받는다 — 로그인 여부와 무관한 공개
  /// 데이터라 `currentUserId` 체크 없이 그대로 조회한다([fetchConsumableCatalog]
  /// 와 같은 성격). 실패하면(오프라인 등) 빈 리스트 — 호출부([GuildShopManager])
  /// 가 이전에 캐시해 둔 카탈로그를 그대로 유지한다.
  Future<List<Map<String, dynamic>>> fetchGuildShopItems() async {
    try {
      final List<dynamic> rows = await _client.from(_guildShopItemsTable).select();
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 상점 카탈로그 조회 실패: $error');
      return const [];
    }
  }

  // ── 결투장/Arena (ArenaManager 전용) ─────────────────────────────
  //
  // `user_arena`/`arena_ranking_rewards` 컬럼은 요구사항에 명시되지 않은
  // 부분(예: 상대 매칭에 필요한 `combat_power`)이 있어 이 장르에서 흔히
  // 쓰는 최소 구성으로 가정했다: user_arena(`user_id`, `score`, `wins`,
  // `losses`, `combat_power`), arena_ranking_rewards(`rank_min`,
  // `rank_max`, `reward_type`, `reward_amount`) — 실제 컬럼명이 다르면
  // 이 섹션의 메서드들과 [ArenaOpponent]/[ArenaRankingEntry]/
  // [ArenaRankingReward].fromJson만 고치면 된다. `arena_reward_logs`는
  // `distribute_arena_rewards` RPC 내부에서만 쓰이는 서버 감사 로그라
  // 클라이언트가 직접 읽지 않는다.
  static const String _userArenaTable = 'user_arena';
  static const String _arenaRankingRewardsTable = 'arena_ranking_rewards';

  /// 현재 유저의 결투장 기록(점수/승패/전투력) 한 행 — 아직 한 번도
  /// 동기화된 적 없는(신규) 유저는 null, 호출부([ArenaManager])가
  /// 기본값(1000점/0승/0패)을 그대로 쓴다.
  Future<Map<String, dynamic>?> fetchMyArenaStats() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final List<dynamic> rows =
          await _client.from(_userArenaTable).select().eq('user_id', userId).limit(1);
      if (rows.isEmpty) {
        return null;
      }
      return rows.first as Map<String, dynamic>;
    } catch (error) {
      debugPrint('[SupabaseManager] 결투장 기록 조회 실패: $error');
      return null;
    }
  }

  /// 점수/승패/전투력(전부 절대값)을 갱신한다 — 전투 결과 반영, 전투력
  /// 재동기화, 주간 정산 후 점수 리셋 세 경로 모두 이 메서드 하나로
  /// 동기화한다.
  Future<void> upsertMyArenaStats({
    required int score,
    required int wins,
    required int losses,
    required int combatPower,
  }) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client.from(_userArenaTable).upsert({
        'user_id': userId,
        'score': score,
        'wins': wins,
        'losses': losses,
        'combat_power': combatPower,
      });
    } catch (error) {
      debugPrint('[SupabaseManager] 결투장 기록 동기화 실패: $error');
    }
  }

  /// [myScore] 근처(±200) 상대 후보를 넉넉히(최대 20명) 가져온다 — 표준
  /// PostgREST 필터로는 `ORDER BY random()`을 직접 쓸 수 없어서, 여기서
  /// 넓게 가져온 뒤 [ArenaManager.fetchOpponents]가 그중 3명을
  /// 클라이언트에서 셔플해 고른다. `profiles(nickname)` 임베드로 닉네임도
  /// 한 번에 가져온다.
  Future<List<Map<String, dynamic>>> fetchArenaOpponentCandidates(int myScore) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return const [];
      }
      final List<dynamic> rows = await _client
          .from(_userArenaTable)
          .select('user_id, combat_power, score, profiles(nickname)')
          .gte('score', myScore - 200)
          .lte('score', myScore + 200)
          .neq('user_id', userId)
          .limit(20);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 결투장 상대 후보 조회 실패: $error');
      return const [];
    }
  }

  /// 결투장 랭킹 — 점수 내림차순, 최대 100명. `profiles(nickname)` 임베드는
  /// `user_arena.user_id` → `profiles.id` 외래키가 잡혀 있다는 전제다.
  Future<List<Map<String, dynamic>>> fetchArenaRanking() async {
    try {
      final List<dynamic> rows = await _client
          .from(_userArenaTable)
          .select('user_id, score, profiles(nickname)')
          .order('score', ascending: false)
          .limit(100);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 결투장 랭킹 조회 실패: $error');
      return const [];
    }
  }

  /// 순위 구간별 차등 보상 테이블 전체 — 로그인 여부와 무관한 공개 데이터.
  Future<List<Map<String, dynamic>>> fetchArenaRankingRewards() async {
    try {
      final List<dynamic> rows = await _client
          .from(_arenaRankingRewardsTable)
          .select()
          .order('rank_min', ascending: true);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 결투장 랭킹 보상 조회 실패: $error');
      return const [];
    }
  }

  /// 방금 마감된 결투장 시즌([seasonId], `yyyy-Www`)의 랭킹 보상을 서버
  /// RPC(`distribute_arena_rewards`)로 정산한다 — 우편함 발송/점수 1000점
  /// 초기화/중복 방지까지 전부 DB 함수 안에서 처리되므로, 호출부
  /// ([ArenaManager])는 실패 걱정 없이 그냥 한 번 찔러주기만 하면 된다
  /// (월드보스 [distributeWorldBossRewards]와 같은 관례).
  Future<void> distributeArenaRewards(String seasonId) async {
    try {
      await _client.rpc('distribute_arena_rewards', params: {'p_season_id': seasonId});
    } catch (error) {
      debugPrint('[SupabaseManager] 결투장 보상 정산 RPC 실패: $error');
    }
  }

  // ── 일일 퀘스트 (QuestManager 전용) ────────────────────────────────
  //
  // `quests`/`user_quests` 컬럼은 요구사항에 명시되지 않은 부분(일일
  // 리셋 커서 등)이 있어 이 장르에서 흔히 쓰는 최소 구성으로 가정했다:
  // quests(`id`, `action_type`, `title`, `target_count`, `reward_bp`),
  // user_quests(`user_id`, `quest_id`, `current_count`, `is_claimed`) —
  // 실제 컬럼명이 다르면 이 섹션과 [Quest]/[QuestProgress].fromJson만
  // 고치면 된다. `action_type` 값은 [QuestActionType] 상수와 서버 시드
  // 데이터가 반드시 합의해야 한다.
  static const String _questsTable = 'quests';
  static const String _userQuestsTable = 'user_quests';

  /// 오늘의 퀘스트 카탈로그 — 로그인 여부와 무관한 공개 데이터.
  Future<List<Map<String, dynamic>>> fetchQuestCatalog() async {
    try {
      final List<dynamic> rows = await _client.from(_questsTable).select();
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 퀘스트 카탈로그 조회 실패: $error');
      return const [];
    }
  }

  /// 현재 유저의 오늘 진행도 전체(`quest_id` -> 행).
  Future<List<Map<String, dynamic>>> fetchUserQuests() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return const [];
      }
      final List<dynamic> rows =
          await _client.from(_userQuestsTable).select().eq('user_id', userId);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 퀘스트 진행도 조회 실패: $error');
      return const [];
    }
  }

  /// 여러 퀘스트의 진행도를 한 번의 요청으로 갱신한다 — [QuestManager]가
  /// 짧은 시간에 몰리는 진행도 갱신(예: 몬스터 연속 처치)을 모아서 이
  /// 메서드 한 번으로 흘려보낸다(매 처치마다 네트워크 요청을 쏘지
  /// 않기 위함). [rows]의 각 항목은 `{quest_id, current_count, is_claimed}`
  /// 형태다.
  Future<void> upsertUserQuestProgressBatch(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) {
      return;
    }
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client
          .from(_userQuestsTable)
          .upsert([for (final Map<String, dynamic> row in rows) {...row, 'user_id': userId}]);
    } catch (error) {
      debugPrint('[SupabaseManager] 퀘스트 진행도 일괄 동기화 실패: $error');
    }
  }

  // ── 배틀패스 (BattlePassManager 전용) ─────────────────────────────
  //
  // `battle_pass_seasons`(`id`, `start_date`, `end_date`)로 시즌 기간을
  // 관리하고, `battle_pass_rewards`(`level`, `free_reward_type`,
  // `free_reward_amount`, `premium_reward_type`, `premium_reward_amount`,
  // 시즌 무관 공용 트랙)와 `user_battle_pass`(`user_id`, `season_id`,
  // `bp_exp`, `is_premium`, `claimed_free_levels` int[],
  // `claimed_premium_levels` int[], PK(user_id, season_id))로 나눴다 —
  // 무료/프리미엄 수령 여부를 별도 테이블 없이 배열 컬럼 두 개로 표현하고,
  // 진행도를 시즌별로 분리해 시즌이 바뀌면 자연히 새 행에서 0부터
  // 시작한다.
  static const String _battlePassSeasonsTable = 'battle_pass_seasons';
  static const String _battlePassRewardsTable = 'battle_pass_rewards';
  static const String _userBattlePassTable = 'user_battle_pass';

  /// 최근 시즌 몇 개(시작일 내림차순)를 가져온다 — [BattlePassManager]가
  /// 그중 지금 기간에 걸쳐 있는(`start_date` ≤ 오늘 < `end_date`) 시즌
  /// 하나를 "현재 시즌"으로 고른다. 로그인 여부와 무관한 공개 데이터.
  Future<List<Map<String, dynamic>>> fetchBattlePassSeasons() async {
    try {
      final List<dynamic> rows = await _client
          .from(_battlePassSeasonsTable)
          .select()
          .order('start_date', ascending: false)
          .limit(5);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 배틀패스 시즌 조회 실패: $error');
      return const [];
    }
  }

  /// 레벨별 보상 트랙 전체(레벨 오름차순) — 시즌과 무관한 공용 트랙이라
  /// 로그인 여부와도 무관한 공개 데이터.
  Future<List<Map<String, dynamic>>> fetchBattlePassRewards() async {
    try {
      final List<dynamic> rows = await _client
          .from(_battlePassRewardsTable)
          .select()
          .order('level', ascending: true);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 배틀패스 보상 트랙 조회 실패: $error');
      return const [];
    }
  }

  /// 현재 유저의 [seasonId] 시즌 배틀패스 상태(exp/프리미엄 여부/수령
  /// 이력) — 아직 한 번도 동기화된 적 없으면 null, 호출부
  /// ([BattlePassManager])가 기본값(0 exp/무료 패스)을 그대로 쓴다.
  Future<Map<String, dynamic>?> fetchUserBattlePass({required String seasonId}) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final List<dynamic> rows = await _client
          .from(_userBattlePassTable)
          .select()
          .eq('user_id', userId)
          .eq('season_id', seasonId)
          .limit(1);
      if (rows.isEmpty) {
        return null;
      }
      return rows.first as Map<String, dynamic>;
    } catch (error) {
      debugPrint('[SupabaseManager] 배틀패스 상태 조회 실패: $error');
      return null;
    }
  }

  /// [seasonId] 시즌의 배틀패스 상태(전부 절대값)를 갱신한다 — 몬스터
  /// 처치/오프라인 보상/퀘스트 보상으로 exp가 오를 때, 보상을 수령할 때,
  /// 프리미엄 패스를 해금할 때 전부 이 메서드 하나로 동기화한다.
  Future<void> upsertUserBattlePass({
    required String seasonId,
    required int bpExp,
    required bool isPremium,
    required List<int> claimedFreeLevels,
    required List<int> claimedPremiumLevels,
  }) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client.from(_userBattlePassTable).upsert({
        'user_id': userId,
        'season_id': seasonId,
        'bp_exp': bpExp,
        'is_premium': isPremium,
        'claimed_free_levels': claimedFreeLevels,
        'claimed_premium_levels': claimedPremiumLevels,
      }, onConflict: 'user_id,season_id');
    } catch (error) {
      debugPrint('[SupabaseManager] 배틀패스 상태 동기화 실패: $error');
    }
  }

  // ── 보상형 광고 (AdManager 전용) ────────────────────────────────────
  //
  // `ad_unit_config`(`platform` text 'android'|'ios', `rewarded_ad_id`
  // text)로 광고 단위 ID를 앱 업데이트 없이 교체할 수 있게 하고,
  // `profiles.daily_ad_views`(int, 자정 리셋)/`profiles.last_ad_viewed_at`
  // (timestamptz, 1시간 쿨타임 기준)로 시청 제한을 서버에도 남긴다 — 실제
  // 컬럼 스키마는 요구사항에 명시된 이름 그대로 가정했다.
  static const String _adUnitConfigTable = 'ad_unit_config';

  /// [platform]('android' 또는 'ios')에 등록된 보상형 광고 단위 ID — 행이
  /// 없거나 조회 실패 시 null(호출부([AdManager])가 테스트용 ID로 폴백).
  Future<String?> fetchRewardedAdUnitId(String platform) async {
    try {
      final Map<String, dynamic>? row = await _client
          .from(_adUnitConfigTable)
          .select('rewarded_ad_id')
          .eq('platform', platform)
          .maybeSingle();
      return row?['rewarded_ad_id'] as String?;
    } catch (error) {
      debugPrint('[SupabaseManager] 보상형 광고 ID 조회 실패: $error');
      return null;
    }
  }

  /// 현재 유저의 `profiles.daily_ad_views`/`last_ad_viewed_at`을 함께
  /// 조회한다 — 못 불러오면 null(호출부가 로컬 캐시를 유지).
  Future<({int dailyAdViews, DateTime? lastAdViewedAt})?> fetchAdViewState() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final Map<String, dynamic>? row = await _client
          .from(_profilesTable)
          .select('daily_ad_views, last_ad_viewed_at')
          .eq('id', userId)
          .maybeSingle();
      if (row == null) {
        return null;
      }
      final String? lastViewedRaw = row['last_ad_viewed_at'] as String?;
      return (
        dailyAdViews: (row['daily_ad_views'] as num?)?.toInt() ?? 0,
        lastAdViewedAt: lastViewedRaw == null ? null : DateTime.tryParse(lastViewedRaw),
      );
    } catch (error) {
      debugPrint('[SupabaseManager] 광고 시청 상태 조회 실패: $error');
      return null;
    }
  }

  /// `profiles.daily_ad_views`/`last_ad_viewed_at`을 절대값으로 덮어쓴다 —
  /// [updateGold]와 같은 "로컬이 먼저 확정한 값을 그대로 push" 관례.
  Future<void> upsertAdViewState({
    required int dailyAdViews,
    required String lastAdViewedAtIso,
  }) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client.from(_profilesTable).update({
        'daily_ad_views': dailyAdViews,
        'last_ad_viewed_at': lastAdViewedAtIso,
      }).eq('id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] 광고 시청 상태 동기화 실패: $error');
    }
  }

  // ── 길드 레이드 (GuildRaidManager 전용) ─────────────────────────────
  //
  // `guild_bosses`(`guild_id` uuid PK/guilds.id 참조, `level` int,
  // `max_hp` bigint, `current_hp` bigint)에 길드당 정확히 한 행만 두고,
  // 공격은 반드시 `guild_boss_attack` RPC를 거친다 — 여러 길드원이 거의
  // 동시에 공격해도 데미지가 유실되지 않게(길드 출석체크의
  // `guild_check_in` RPC와 같은 이유) 서버에서 원자적으로 처리하고, 보스가
  // 죽는 순간의 다음 레벨 스폰과 참여자 전원에 대한 길드 주화 지급까지
  // 전부 그 함수 하나 안에서 끝낸다(참여자 명단은 `guild_boss_participants`
  // 테이블에 그 함수가 직접 누적 기록한다). 정확한 SQL은 완료 보고에 함께
  // 첨부한다.
  static const String _guildBossesTable = 'guild_bosses';

  /// [guildId] 길드의 현재 레이드 보스 상태 — 아직 한 번도 스폰된 적
  /// 없으면(행 없음) null, 호출부([GuildRaidManager])가 1레벨 기본값으로
  /// 취급한다.
  Future<Map<String, dynamic>?> fetchGuildBoss(String guildId) async {
    try {
      return await _client
          .from(_guildBossesTable)
          .select()
          .eq('guild_id', guildId)
          .maybeSingle();
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 레이드 보스 조회 실패: $error');
      return null;
    }
  }

  /// [guildId] 보스에게 [damage]만큼 공격한다 — `guild_boss_attack` RPC가
  /// 보스 체력 차감/사망 시 다음 레벨 스폰/참여자 길드 주화 지급까지
  /// 원자적으로 처리한 뒤 그 결과 행을 돌려준다. 실패(오프라인 등)하면
  /// null — 호출부는 이번 공격이 서버에 반영되지 않은 것으로 취급한다.
  Future<GuildBossAttackResult?> attackGuildBoss({
    required String guildId,
    required int damage,
  }) async {
    if (damage <= 0) {
      return null;
    }
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final dynamic response = await _client.rpc(
        'guild_boss_attack',
        params: {'p_guild_id': guildId, 'p_user_id': userId, 'p_damage': damage},
      );
      final List<dynamic> rows = response as List<dynamic>;
      if (rows.isEmpty) {
        return null;
      }
      return GuildBossAttackResult.fromJson(rows.first as Map<String, dynamic>);
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 레이드 공격 RPC 실패: $error');
      return null;
    }
  }
}
