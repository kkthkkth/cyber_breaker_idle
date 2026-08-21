import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/guild_boss_model.dart';
import '../models/guild_war_model.dart';

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
  static String get _googleRedirectTo =>
      kIsWeb ? Uri.base.toString() : _mobileRedirectTo;

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
  Future<void> upsertGoogleProfile(User user) =>
      _upsertProfile(userId: user.id, loginType: 'google');

  /// [userId]로 `profiles` 행을 만든다(이미 있으면 존재만 확인).
  ///
  /// [주의] upsert 페이로드에는 일부러 `id`/`login_type`만 담는다 —
  /// `nickname`/`level`/`gold` 같은 진행 데이터를 매번 같이 올리면, 이미
  /// 진행 중인 유저가 로그인할 때마다(=이 함수가 다시 불릴 때마다) 서버에
  /// 저장된 실제 값이 기본값/null로 덮어써지는 심각한 사고가 난다. 닉네임은
  /// [setNickname]처럼 해당 컬럼 하나만 건드리는 전용 함수로만 갱신한다.
  Future<void> _upsertProfile({
    required String userId,
    required String loginType,
  }) {
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

  /// `profiles.is_ad_free` — [IAPManager]가 광고 제거 영구 패스
  /// (`remove_ads_permanent`) 구매를 확인하면 [upsertIsAdFree]로 반영해
  /// 둔 값을, [ProfileManager.loadData]가 로그인 시 다시 읽어 다른
  /// 기기/재설치에서도 구매 상태를 복원한다. 아직 로그인 전이거나 조회
  /// 실패 시 null(호출부가 로컬 캐시를 그대로 유지).
  Future<bool?> fetchIsAdFree() async {
    final String? userId = currentUserId;
    if (userId == null) {
      return null;
    }
    try {
      final Map<String, dynamic>? row = await _client
          .from(_profilesTable)
          .select('is_ad_free')
          .eq('id', userId)
          .maybeSingle();
      return row?['is_ad_free'] as bool?;
    } catch (error) {
      debugPrint('[SupabaseManager] 광고 제거 상태 조회 실패: $error');
      return null;
    }
  }

  /// `profiles.is_ad_free`를 절대값으로 덮어쓴다 — [GameManager.updateGold]
  /// 와 같은 "로컬이 먼저 확정한 값을 그대로 push" 관례.
  Future<void> upsertIsAdFree(bool value) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client
          .from(_profilesTable)
          .update({'is_ad_free': value})
          .eq('id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] 광고 제거 상태 동기화 실패: $error');
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

  // ── 친구 시스템 (FriendManager 전용) ──────────────────────────────
  //
  // `friendships`(`user_id` 요청자, `friend_id` 대상, `status` 'pending'|
  // 'accepted') 하나로 요청/수락/친구 목록을 전부 표현한다 — 거절은 행
  // 삭제로 처리한다(거절 기록을 남길 필요가 없다는 판단). 온라인 상태/
  // 닉네임/전투력은 전부 이미 있는 `profiles` 테이블(닉네임/combat_power/
  // last_seen 이미 관리 중)을 그대로 재사용한다 — 별도 유저 테이블을
  // 새로 두지 않았다.
  static const String _friendshipsTable = 'friendships';

  /// 닉네임에 [query]가 포함된 유저를 검색한다(대소문자 무시), 최대 20명,
  /// 본인은 제외. [query]가 정확한 유저 id와도 일치하면 그 결과도 함께
  /// 포함한다(요구사항: "닉네임이나 유저 ID를 검색").
  Future<List<Map<String, dynamic>>> searchProfilesForFriend(
    String query,
  ) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const [];
    }
    final String? userId = currentUserId;
    try {
      final Map<String, Map<String, dynamic>> byId = {};

      final List<dynamic> byNickname = await _client
          .from(_profilesTable)
          .select('id, nickname, combat_power, equipped_character')
          .ilike('nickname', '%$trimmed%')
          .limit(20);
      for (final dynamic row in byNickname.cast<Map<String, dynamic>>()) {
        byId[row['id'] as String] = row;
      }

      // id.eq 필터는 값이 uuid 형식이 아니면 그 자체로 쿼리가 실패하므로,
      // 닉네임 검색과 하나의 or() 절로 묶지 않고 완전히 독립된 별도
      // 조회로 분리한다(형식이 안 맞으면 이 조회만 조용히 건너뛴다).
      const String uuidPattern =
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
      if (RegExp(uuidPattern).hasMatch(trimmed)) {
        final Map<String, dynamic>? byExactId = await _client
            .from(_profilesTable)
            .select('id, nickname, combat_power, equipped_character')
            .eq('id', trimmed)
            .maybeSingle();
        if (byExactId != null) {
          byId[byExactId['id'] as String] = byExactId;
        }
      }

      byId.remove(userId);
      return byId.values.toList();
    } catch (error) {
      debugPrint('[SupabaseManager] 유저 검색 실패: $error');
      return const [];
    }
  }

  /// 현재 유저가 요청자(user_id)이거나 대상(friend_id)인 모든 friendships
  /// 행 — pending/accepted 구분 없이 전부 가져온 뒤 [FriendManager]가
  /// 클라이언트에서 내 친구 목록/받은 요청으로 나눈다. 결합 OR 필터
  /// 대신 두 번의 단순 eq 조회로 나눈 이유는 [searchProfilesForFriend]와
  /// 같다 — 이 프로젝트에서 검증된 필터 방식만 쓴다.
  Future<List<Map<String, dynamic>>> fetchMyFriendshipRows() async {
    final String? userId = currentUserId;
    if (userId == null) {
      return const [];
    }
    try {
      final List<dynamic> asRequester = await _client
          .from(_friendshipsTable)
          .select()
          .eq('user_id', userId);
      final List<dynamic> asTarget = await _client
          .from(_friendshipsTable)
          .select()
          .eq('friend_id', userId);
      return [
        ...asRequester.cast<Map<String, dynamic>>(),
        ...asTarget.cast<Map<String, dynamic>>(),
      ];
    } catch (error) {
      debugPrint('[SupabaseManager] 친구 관계 조회 실패: $error');
      return const [];
    }
  }

  /// [targetUserId]에게 친구 요청을 보낸다(status='pending') — 중복 요청
  /// 방지는 [FriendManager.sendFriendRequest]가 [fetchMyFriendshipRows]로
  /// 이미 확인한 뒤에만 이 메서드를 부르므로 여기서는 다시 확인하지
  /// 않는다.
  Future<bool> sendFriendRequest(String targetUserId) async {
    final String? userId = currentUserId;
    if (userId == null) {
      return false;
    }
    try {
      await _client.from(_friendshipsTable).insert({
        'user_id': userId,
        'friend_id': targetUserId,
        'status': 'pending',
      });
      return true;
    } catch (error) {
      debugPrint('[SupabaseManager] 친구 요청 전송 실패: $error');
      return false;
    }
  }

  /// [requesterId]가 나(friend_id)에게 보낸 pending 요청을 accepted로
  /// 바꾼다 — 이 한 행이 양쪽 [fetchMyFriendshipRows] 조회에 모두
  /// 잡히므로, 별도로 반대 방향 행을 추가로 만들 필요가 없다.
  Future<bool> acceptFriendRequest(String requesterId) async {
    final String? userId = currentUserId;
    if (userId == null) {
      return false;
    }
    try {
      await _client
          .from(_friendshipsTable)
          .update({'status': 'accepted'})
          .eq('user_id', requesterId)
          .eq('friend_id', userId)
          .eq('status', 'pending');
      return true;
    } catch (error) {
      debugPrint('[SupabaseManager] 친구 요청 수락 실패: $error');
      return false;
    }
  }

  /// [requesterId]가 나에게 보낸 pending 요청을 거절(=행 삭제)한다.
  Future<bool> declineFriendRequest(String requesterId) async {
    final String? userId = currentUserId;
    if (userId == null) {
      return false;
    }
    try {
      await _client
          .from(_friendshipsTable)
          .delete()
          .eq('user_id', requesterId)
          .eq('friend_id', userId)
          .eq('status', 'pending');
      return true;
    } catch (error) {
      debugPrint('[SupabaseManager] 친구 요청 거절 실패: $error');
      return false;
    }
  }

  /// [ids]에 해당하는 프로필들의 닉네임/전투력/최종 접속 시각 — 친구
  /// 목록/받은 요청 탭이 [fetchMyFriendshipRows]로 얻은 유저 id들을
  /// 한 번에 조회할 때 쓴다.
  Future<List<Map<String, dynamic>>> fetchProfilesByIds(
    List<String> ids,
  ) async {
    if (ids.isEmpty) {
      return const [];
    }
    try {
      final List<dynamic> rows = await _client
          .from(_profilesTable)
          .select('id, nickname, combat_power, last_seen, equipped_character')
          .inFilter('id', ids);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 프로필 일괄 조회 실패: $error');
      return const [];
    }
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

      await _client
          .from(_profilesTable)
          .update({'nickname': nickname})
          .eq('id', userId);
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
      await _client
          .from(_profilesTable)
          .update({'gold': amount})
          .eq('id', userId);
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

  // ── 하드 모드 (GameManager 전용) ───────────────────────────────────
  //
  // `updateAllowTrade`/`fetchAllowTrade`와 같은 모양 — 로컬이 먼저 확정한
  // 값을 그대로 push하고, 실패해도 조용히 로컬 캐시를 유지한다.

  /// `profiles.is_hard_mode` — 못 불러오면 null(호출부가 로컬 캐시를
  /// 유지) — [fetchHighestReachedChapter]와 같은 관례. 여기서 false를
  /// 디폴트로 돌려주면, 조회 자체가 실패했을 때도 "정상 모드"로 단정해
  /// 로컬에 이미 반영된 하드 모드 상태를 조용히 되돌려버리게 된다.
  Future<bool?> fetchIsHardMode() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final Map<String, dynamic>? row = await _client
          .from(_profilesTable)
          .select('is_hard_mode')
          .eq('id', userId)
          .maybeSingle();
      return row?['is_hard_mode'] as bool?;
    } catch (error) {
      debugPrint('[SupabaseManager] 하드 모드 상태 조회 실패: $error');
      return null;
    }
  }

  Future<void> updateHardMode(bool value) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client
          .from(_profilesTable)
          .update({'is_hard_mode': value})
          .eq('id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] 하드 모드 상태 동기화 실패: $error');
    }
  }

  /// `profiles.hard_max_stage`(하드 모드 최고 도달 절대 스테이지) — 못
  /// 불러오면 null(호출부가 로컬 캐시를 유지).
  Future<int?> fetchHardMaxStage() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final Map<String, dynamic>? row = await _client
          .from(_profilesTable)
          .select('hard_max_stage')
          .eq('id', userId)
          .maybeSingle();
      return (row?['hard_max_stage'] as num?)?.toInt();
    } catch (error) {
      debugPrint('[SupabaseManager] 하드 모드 최고 스테이지 조회 실패: $error');
      return null;
    }
  }

  Future<void> updateHardMaxStage(int stage) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client
          .from(_profilesTable)
          .update({'hard_max_stage': stage})
          .eq('id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] 하드 모드 최고 스테이지 동기화 실패: $error');
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
          .select(
            'id, nickname, highest_reached_chapter, prestige_count, equipped_character',
          )
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
          .select('id, nickname, highest_tower_floor, equipped_character')
          .order('highest_tower_floor', ascending: false)
          .limit(100);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 무한의 탑 랭킹 조회 실패: $error');
      return const [];
    }
  }

  /// 전투력 랭킹([RankingCategory.combatPower]) — `profiles.combat_power`
  /// 내림차순 상위 [limit]명. [fetchTopRankingProfiles]/
  /// [fetchTopTowerRankingProfiles]처럼 `.select().order().limit()`을
  /// 직접 쓰지 않고, Postgres RPC `get_combat_power_ranking`(SECURITY
  /// DEFINER)을 호출한다 — [주의] `ranking_blacklist`에 등록된 user_id를
  /// 결과에서 완전히 제외해야 하는데, 그 제외를 클라이언트가 블랙리스트
  /// 목록을 통째로 받아와서(`.not('id','in', [...])`) 처리하면 (1) 블랙리스트
  /// 자체가 클라이언트에 노출되고 (2) 목록이 커질수록 쿼리도 느려진다.
  /// RPC 안에서 `NOT EXISTS` 서브쿼리로 서버 쪽에서 걸러서, 클라이언트는
  /// 이미 필터링된 결과만 받는다(SQL은 `supabase/combat_power_ranking.sql`
  /// 참고). 실패하면(RPC 미배포/오프라인 등) 빈 리스트 — 호출부
  /// ([RankingManager])가 이전에 캐시해 둔 값을 그대로 유지한다.
  Future<List<Map<String, dynamic>>> fetchCombatPowerRanking({
    int limit = 100,
  }) async {
    try {
      final dynamic result = await _client.rpc(
        'get_combat_power_ranking',
        params: {'result_limit': limit},
      );
      return (result as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 전투력 랭킹 조회 실패: $error');
      return const [];
    }
  }

  /// [userIds]에 속한 유저들의 소속 길드명 — `guild_members`를
  /// `guilds(name)` 임베드로 조회한다(한 유저는 최대 한 길드에만 속하므로
  /// 1:1 매핑). 길드가 없는 유저는 결과에 아예 나타나지 않는다.
  Future<List<Map<String, dynamic>>> fetchGuildNamesForUsers(
    List<String> userIds,
  ) async {
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

  /// 현재 유저의 `profiles.prestige_count`/`prestige_core_points`(환생
  /// 실행 횟수/누적 환생석 — 컬럼명은 하위 호환을 위해 그대로 유지, 둘 다
  /// 기본 0) — 못 불러오면 null(호출부가 로컬 캐시를 유지).
  Future<({int count, int stones})?> fetchPrestigeData() async {
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
        stones: (row['prestige_core_points'] as num?)?.toInt() ?? 0,
      );
    } catch (error) {
      debugPrint('[SupabaseManager] 환생 데이터 조회 실패: $error');
      return null;
    }
  }

  /// `profiles.prestige_count`/`prestige_core_points`를 덮어쓴다 —
  /// [updateHighestTowerFloor]와 같은 "로컬이 먼저 확정한 값을 그대로
  /// push" 관례. [PrestigeManager.prestige]가 성공할 때마다 호출한다.
  Future<void> updatePrestigeData({
    required int count,
    required int stones,
  }) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client
          .from(_profilesTable)
          .update({'prestige_count': count, 'prestige_core_points': stones})
          .eq('id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] 환생 데이터 동기화 실패: $error');
    }
  }

  static const String _userTalentsTable = 'user_talents';

  /// 현재 유저의 `profiles.talent_points`(환생으로 지급되는 특성 포인트,
  /// 기본 0) — 못 불러오면 null(호출부가 로컬 캐시를 유지).
  Future<int?> fetchTalentPoints() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final Map<String, dynamic>? row = await _client
          .from(_profilesTable)
          .select('talent_points')
          .eq('id', userId)
          .maybeSingle();
      if (row == null) {
        return null;
      }
      return (row['talent_points'] as num?)?.toInt() ?? 0;
    } catch (error) {
      debugPrint('[SupabaseManager] 특성 포인트 조회 실패: $error');
      return null;
    }
  }

  /// `profiles.talent_points`를 덮어쓴다 — [updatePrestigeData]와 같은
  /// "로컬이 먼저 확정한 값을 그대로 push" 관례. [TalentManager]가 포인트를
  /// 지급하거나(환생) 소모할 때마다(레벨업) 호출한다.
  Future<void> updateTalentPoints(int points) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client
          .from(_profilesTable)
          .update({'talent_points': points})
          .eq('id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] 특성 포인트 동기화 실패: $error');
    }
  }

  /// 현재 유저가 투자한 특성 노드별 레벨(`user_talents`, 각 행이 (node_id,
  /// level) 하나) — 실패하면 빈 리스트(호출부가 로컬 캐시를 유지).
  Future<List<Map<String, dynamic>>> fetchUserTalents() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return const [];
      }
      final List<dynamic> rows = await _client
          .from(_userTalentsTable)
          .select('node_id, level')
          .eq('user_id', userId);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 특성 노드 목록 조회 실패: $error');
      return const [];
    }
  }

  /// [TalentManager.levelUp]이 성공할 때마다 `user_talents`의 해당 노드
  /// 행을 [level]로 맞춘다(upsert) — [syncUserSkill]과 같은 관례.
  Future<void> syncUserTalent({
    required String nodeId,
    required int level,
  }) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client.from(_userTalentsTable).upsert({
        'user_id': userId,
        'node_id': nodeId,
        'level': level,
      }, onConflict: 'user_id, node_id');
    } catch (error) {
      debugPrint('[SupabaseManager] 특성 노드 동기화 실패: $error');
    }
  }

  static const String _userExpeditionsTable = 'user_expeditions';

  /// 현재 유저의 진행 중(또는 완료했지만 아직 수령 전인) 탐험 임무 전체 —
  /// 지역당 최대 1행([ExpeditionManager]가 region_id를 upsert 충돌 키로
  /// 쓴다). 실패하면 빈 리스트(호출부가 로컬 캐시를 유지).
  Future<List<Map<String, dynamic>>> fetchUserExpeditions() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return const [];
      }
      final List<dynamic> rows = await _client
          .from(_userExpeditionsTable)
          .select('region_id, unit_ids, start_time, is_collected')
          .eq('user_id', userId);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 탐험 목록 조회 실패: $error');
      return const [];
    }
  }

  /// [ExpeditionManager.startExpedition]이 성공할 때마다 호출 — 새 임무
  /// 행을 insert(upsert)한다.
  Future<void> syncExpeditionStart({
    required String regionId,
    required List<String> unitIds,
    required DateTime startTime,
  }) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client.from(_userExpeditionsTable).upsert({
        'user_id': userId,
        'region_id': regionId,
        'unit_ids': unitIds,
        'start_time': startTime.toIso8601String(),
        'is_collected': false,
      }, onConflict: 'user_id, region_id');
    } catch (error) {
      debugPrint('[SupabaseManager] 탐험 시작 동기화 실패: $error');
    }
  }

  /// [ExpeditionManager.claimReward]가 성공할 때마다 호출 — 해당 지역
  /// 행을 `is_collected = true`로 갱신한다(요구사항: "DB is_collected =
  /// true 처리"). 그 다음 탐험이 다시 시작되면 [syncExpeditionStart]가
  /// 같은 행을 새 값으로 다시 upsert하므로 별도 delete는 필요 없다.
  Future<void> syncExpeditionCollected(String regionId) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client
          .from(_userExpeditionsTable)
          .update({'is_collected': true})
          .eq('user_id', userId)
          .eq('region_id', regionId);
    } catch (error) {
      debugPrint('[SupabaseManager] 탐험 수령 동기화 실패: $error');
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
  Future<void> updatePityData({
    required int character,
    required int pet,
    required int equipment,
  }) async {
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
  Future<({int monsterKills, int gachaPulls, Set<String> claimedKeys})?>
  fetchAchievementData() async {
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
        monsterKills:
            (profileRow?['total_monster_kills'] as num?)?.toInt() ?? 0,
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
  Future<void> updateAchievementCounters({
    required int monsterKills,
    required int gachaPulls,
  }) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client
          .from(_profilesTable)
          .update({
            'total_monster_kills': monsterKills,
            'total_gacha_pulls': gachaPulls,
          })
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
      await _client.from(_userAchievementsTable).upsert({
        'user_id': userId,
        'achievement_key': key,
      }, onConflict: 'user_id,achievement_key');
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
      final List<dynamic> rows = await _client
          .from(_userPetsTable)
          .select('id, data')
          .eq('user_id', userId);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 펫 목록 조회 실패: $error');
      return const [];
    }
  }

  /// 현재 유저의 `user_pets` 행을 [pets]로 맞춘다 — 더 이상 보유하지 않은
  /// 펫(뽑기 분해 등으로 사라짐)만 정확히 골라 지우고, 나머지는
  /// upsert(있으면 갱신, 없으면 삽입)한다. [EquipmentManager.saveEquipment]
  /// 가 호출될 때마다(=펫이든 아니든 장비 상태가 바뀔 때마다) 함께
  /// 호출된다.
  ///
  /// [주의] 예전엔 "기존 행 전부 삭제 후 재삽입"이었다 — 의도(사라진
  /// 펫이 서버에 밀린 채로 남지 않게 함) 자체는 맞지만, `saveEquipment`가
  /// 여러 번 겹쳐(`unawaited`) 짧은 간격으로 불리면 두 호출의 delete/insert
  /// 순서가 뒤섞일 수 있었다 — A가 지운 뒤 아직 넣기 전에 B도 지우고
  /// 넣고, 그 다음 A도 같은 id로 또 넣으면서
  /// `duplicate key value violates unique constraint "user_pets_pkey"`가
  /// 났다(실측 확인됨). 삭제 범위를 "이제 없는 것"으로만 좁히고 나머지를
  /// upsert로 바꾸면, 같은 두 호출이 겹쳐도 upsert는 이미 있는 행을 그냥
  /// 덮어쓸 뿐 절대 실패하지 않는다 — 같은 id를 두 번 insert하는 경로
  /// 자체가 사라진다.
  Future<void> syncUserPets(List<Map<String, dynamic>> pets) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      if (pets.isEmpty) {
        await _client.from(_userPetsTable).delete().eq('user_id', userId);
        return;
      }

      final List<Object> currentPetIds = [
        for (final Map<String, dynamic> pet in pets) pet['id'] as Object,
      ];
      await _client
          .from(_userPetsTable)
          .delete()
          .eq('user_id', userId)
          .not('id', 'in', currentPetIds);

      await _client.from(_userPetsTable).upsert([
        for (final Map<String, dynamic> pet in pets)
          {'id': pet['id'], 'user_id': userId, 'data': pet},
      ], onConflict: 'id');
    } catch (error) {
      debugPrint('[SupabaseManager] 펫 목록 동기화 실패: $error');
    }
  }

  // ── 일반 장비 서버 동기화 (거래 시스템 전제 조건) ────────────────────
  //
  // [syncUserPets]/[fetchUserPets]와 완전히 같은 shape/로직을 펫이 아닌
  // 나머지 장비 전체에 그대로 적용한다 — 이미 검증된 diff-upsert 동시성
  // 패턴을 재사용할 뿐, 새로 설계하지 않는다(주석도 동일하게 적용된다:
  // "전부 삭제 후 재삽입"이 아니라 "사라진 것만 삭제 + 나머지 upsert"라
  // saveEquipment()가 겹쳐 불려도 안전하다). 이 테이블은 [TradeManager]가
  // "이 아이템은 지금 누구 소유"를 서버에서 판단하기 위한 미러일 뿐 —
  // 게임 로직 자체는 여전히 로컬(SharedPreferences)을 1차 신뢰 소스로
  // 쓴다([EquipmentManager] 문서 참고, 이 동기화는 fire-and-forget이라
  // 실패해도 로컬 플레이에 영향이 없다).
  static const String _userEquipmentTable = 'user_equipment';

  /// 현재 유저가 보유한 펫 이외 장비 전체(`user_equipment`, 각 행의
  /// `data`가 [Equipment.toJson] 결과) — 실패하면 빈 리스트.
  Future<List<Map<String, dynamic>>> fetchUserEquipment() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return const [];
      }
      final List<dynamic> rows = await _client
          .from(_userEquipmentTable)
          .select('id, data')
          .eq('user_id', userId);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 장비 목록 조회 실패: $error');
      return const [];
    }
  }

  /// 현재 유저의 `user_equipment` 행을 [items]로 맞춘다 — [syncUserPets]
  /// 문서의 동시성 주의사항이 그대로 적용된다.
  Future<void> syncUserEquipment(List<Map<String, dynamic>> items) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      if (items.isEmpty) {
        await _client.from(_userEquipmentTable).delete().eq('user_id', userId);
        return;
      }

      final List<Object> currentIds = [
        for (final Map<String, dynamic> item in items) item['id'] as Object,
      ];
      await _client
          .from(_userEquipmentTable)
          .delete()
          .eq('user_id', userId)
          .not('id', 'in', currentIds);

      await _client.from(_userEquipmentTable).upsert([
        for (final Map<String, dynamic> item in items)
          {'id': item['id'], 'user_id': userId, 'data': item},
      ], onConflict: 'id');
    } catch (error) {
      debugPrint('[SupabaseManager] 장비 목록 동기화 실패: $error');
    }
  }

  // ── 1:1 아이템 거래 (TradeManager 전용) ────────────────────────────
  //
  // profiles.allow_trade(boolean, 기본 false), trade_daily_count(user_id,
  // trade_date, count — 요일 던전과 같은 날짜 키 패턴), trades(id, user_a
  // 요청자, user_b 대상, status, locked_a, locked_b), trade_items(id,
  // trade_id, owner_user_id, equipment_id → user_equipment(id)) — 실제
  // 컬럼/제약은 supabase/trade_reference.sql 참고. 실제 아이템 이전은
  // execute_trade RPC(SECURITY DEFINER, 트랜잭션+행 잠금) 안에서만
  // 일어난다 — 이 클래스의 다른 메서드들은 요청/세션 상태만 다루고
  // 소유권을 직접 바꾸지 않는다.
  static const String _tradesTable = 'trades';
  static const String _tradeItemsTable = 'trade_items';
  static const String _tradeDailyCountTable = 'trade_daily_count';

  Future<bool> fetchAllowTrade(String userId) async {
    try {
      final Map<String, dynamic>? row = await _client
          .from(_profilesTable)
          .select('allow_trade')
          .eq('id', userId)
          .maybeSingle();
      return row?['allow_trade'] as bool? ?? false;
    } catch (error) {
      debugPrint('[SupabaseManager] 거래 허용 여부 조회 실패: $error');
      return false;
    }
  }

  Future<void> updateAllowTrade(bool value) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client
          .from(_profilesTable)
          .update({'allow_trade': value})
          .eq('id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] 거래 허용 여부 갱신 실패: $error');
    }
  }

  /// 오늘(UTC 기준 `current_date`) 내가 완료한 거래 횟수 — 하루 3회 제한
  /// 표시/사전 확인용(최종 판정은 RPC가 다시 한다).
  Future<int> fetchTradeCountToday() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return 0;
      }
      final String today = DateTime.now()
          .toUtc()
          .toIso8601String()
          .split('T')
          .first;
      final Map<String, dynamic>? row = await _client
          .from(_tradeDailyCountTable)
          .select('count')
          .eq('user_id', userId)
          .eq('trade_date', today)
          .maybeSingle();
      return (row?['count'] as num?)?.toInt() ?? 0;
    } catch (error) {
      debugPrint('[SupabaseManager] 오늘 거래 횟수 조회 실패: $error');
      return 0;
    }
  }

  /// [targetUserId]에게 거래 요청을 보낸다(`status='pending'`) — 성공하면
  /// 새로 생긴 [TradeSession] 행, 실패하면 null.
  Future<Map<String, dynamic>?> createTradeRequest(String targetUserId) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final Map<String, dynamic> row = await _client
          .from(_tradesTable)
          .insert({
            'user_a': userId,
            'user_b': targetUserId,
            'status': 'pending',
          })
          .select()
          .single();
      return row;
    } catch (error) {
      debugPrint('[SupabaseManager] 거래 요청 전송 실패: $error');
      return null;
    }
  }

  /// 내가 받은 pending 거래 요청 전체.
  Future<List<Map<String, dynamic>>> fetchIncomingTradeRequests() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return const [];
      }
      final List<dynamic> rows = await _client
          .from(_tradesTable)
          .select()
          .eq('user_b', userId)
          .eq('status', 'pending');
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 받은 거래 요청 조회 실패: $error');
      return const [];
    }
  }

  Future<Map<String, dynamic>?> fetchTradeSession(String tradeId) async {
    try {
      final Map<String, dynamic>? row = await _client
          .from(_tradesTable)
          .select()
          .eq('id', tradeId)
          .maybeSingle();
      return row;
    } catch (error) {
      debugPrint('[SupabaseManager] 거래 세션 조회 실패: $error');
      return null;
    }
  }

  /// 요청을 수락(`status='active'`)하거나 거절/취소(`status='cancelled'`)한다.
  Future<bool> updateTradeStatus(String tradeId, String status) async {
    try {
      await _client
          .from(_tradesTable)
          .update({'status': status})
          .eq('id', tradeId);
      return true;
    } catch (error) {
      debugPrint('[SupabaseManager] 거래 상태 변경 실패: $error');
      return false;
    }
  }

  /// [isUserA]에 따라 `locked_a`/`locked_b` 중 내 쪽만 갱신한다 — 아이템이
  /// 바뀌면(요구사항: "2단 잠금") 호출부가 false로 다시 부른다.
  Future<bool> updateTradeLock(
    String tradeId, {
    required bool isUserA,
    required bool locked,
  }) async {
    try {
      final String column = isUserA ? 'locked_a' : 'locked_b';
      await _client
          .from(_tradesTable)
          .update({column: locked})
          .eq('id', tradeId);
      return true;
    } catch (error) {
      debugPrint('[SupabaseManager] 거래 잠금 상태 변경 실패: $error');
      return false;
    }
  }

  /// [tradeId]에 올라간 아이템 전체 — `user_equipment(data)` 임베드로
  /// 표시용 스냅샷까지 한 번에 가져온다(FK: trade_items.equipment_id →
  /// user_equipment.id, guild_members→profiles 임베드와 같은 관례).
  Future<List<Map<String, dynamic>>> fetchTradeItems(String tradeId) async {
    try {
      final List<dynamic> rows = await _client
          .from(_tradeItemsTable)
          .select(
            'id, trade_id, owner_user_id, equipment_id, user_equipment(data)',
          )
          .eq('trade_id', tradeId);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 거래 아이템 조회 실패: $error');
      return const [];
    }
  }

  /// 내 아이템 [equipmentId]를 거래창에 올린다.
  Future<bool> addTradeItem({
    required String tradeId,
    required String equipmentId,
  }) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return false;
      }
      await _client.from(_tradeItemsTable).insert({
        'trade_id': tradeId,
        'owner_user_id': userId,
        'equipment_id': equipmentId,
      });
      return true;
    } catch (error) {
      debugPrint('[SupabaseManager] 거래 아이템 추가 실패: $error');
      return false;
    }
  }

  /// 거래창에서 [tradeItemId](trade_items 행 id, equipment_id 아님)를 뺀다.
  Future<bool> removeTradeItem(String tradeItemId) async {
    try {
      await _client.from(_tradeItemsTable).delete().eq('id', tradeItemId);
      return true;
    } catch (error) {
      debugPrint('[SupabaseManager] 거래 아이템 제거 실패: $error');
      return false;
    }
  }

  /// [tradeId] 세션(trades 행 + trade_items 행)이 바뀔 때마다 [onChange]를
  /// 부른다 — payload를 직접 다루지 않고 매번 전체 세션을 다시 불러오는
  /// 쪽([TradeManager]이 담당)이, trade_items의 Realtime payload에는
  /// user_equipment 임베드가 없어 어차피 다시 조회해야 하는 것보다
  /// 단순하고 안전하다.
  RealtimeChannel? subscribeToTradeSession(
    String tradeId,
    void Function() onChange,
  ) {
    try {
      return _client
          .channel('trade_session_$tradeId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: _tradesTable,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: tradeId,
            ),
            callback: (payload) => onChange(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: _tradeItemsTable,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'trade_id',
              value: tradeId,
            ),
            callback: (payload) => onChange(),
          )
          .subscribe();
    } catch (error) {
      debugPrint('[SupabaseManager] 거래 세션 구독 실패: $error');
      return null;
    }
  }

  /// 내가 대상(user_b)인 새 거래 요청이 들어올 때마다 [onInsert]를 부른다
  /// — 앱이 켜져 있는 동안 항상 살아있는 전역 구독([startLastSeenHeartbeat]
  /// 과 같은 "앱 생명주기 = 구독 생명주기" 관례).
  RealtimeChannel? subscribeToIncomingTradeRequests(
    String myUserId,
    void Function(Map<String, dynamic> row) onInsert,
  ) {
    try {
      return _client
          .channel('trade_requests_$myUserId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: _tradesTable,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_b',
              value: myUserId,
            ),
            callback: (payload) => onInsert(payload.newRecord),
          )
          .subscribe();
    } catch (error) {
      debugPrint('[SupabaseManager] 거래 요청 구독 실패: $error');
      return null;
    }
  }

  /// 거래를 원자적으로 확정한다 — 실제 아이템 이전/소유권 재검증/등급
  /// 재검증/일일 횟수 재검증까지 전부 execute_trade RPC(SECURITY DEFINER,
  /// 트랜잭션+행 잠금, supabase/trade_reference.sql 참고) 안에서 일어난다.
  /// 이 메서드는 그 RPC를 호출만 한다 — 실패(exception)하면 서버가 이미
  /// 전체 롤백한 상태이므로 호출부는 실패 토스트만 띄우면 된다.
  Future<bool> executeTrade(String tradeId) async {
    try {
      await _client.rpc('execute_trade', params: {'p_trade_id': tradeId});
      return true;
    } catch (error) {
      debugPrint('[SupabaseManager] 거래 확정 실패: $error');
      return false;
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
      await _client
          .from(_profilesTable)
          .update({'equipped_pet_id': petId})
          .eq('id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] 장착 펫 id 동기화 실패: $error');
    }
  }

  /// 장착 캐릭터가 바뀔 때마다([EquipmentManager.equipItem]) `profiles
  /// .equipped_character`를 함께 갱신한다 — [characterId]는
  /// [Equipment.gradeBadgeLabel](예: "N1", "SSR12")과 같은 형식.
  /// 친구/랭킹 화면이 다른 유저의 대표 캐릭터 썸네일([CharacterFacePortrait])
  /// 을 그릴 때 이 값을 읽는다.
  Future<void> updateEquippedCharacter(String characterId) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client
          .from(_profilesTable)
          .update({'equipped_character': characterId})
          .eq('id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] 장착 캐릭터 동기화 실패: $error');
    }
  }

  // ── 칭호 (TitleManager 전용) ────────────────────────────────────────
  //
  // title_catalog(`id`, `name`, `buff_type`, `buff_value`, `condition_type`,
  // `condition_goal`, `webp_path`) — 로그인 여부와 무관한 공개 카탈로그.
  // user_titles(`user_id`, `title_id`)로 보유 여부를, `profiles
  // .equipped_title`로 장착 중인 칭호 하나를 관리한다.
  static const String _titleCatalogTable = 'title_catalog';
  static const String _userTitlesTable = 'user_titles';

  /// 칭호 카탈로그 전체 — 로그인 여부와 무관한 공개 데이터.
  Future<List<Map<String, dynamic>>> fetchTitleCatalog() async {
    try {
      final List<dynamic> rows = await _client
          .from(_titleCatalogTable)
          .select();
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 칭호 카탈로그 조회 실패: $error');
      return const [];
    }
  }

  /// 현재 유저가 보유한 칭호 id 전체.
  Future<List<String>> fetchOwnedTitleIds() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return const [];
      }
      final List<dynamic> rows = await _client
          .from(_userTitlesTable)
          .select('title_id')
          .eq('user_id', userId);
      return [
        for (final dynamic row in rows)
          (row as Map<String, dynamic>)['title_id'] as String,
      ];
    } catch (error) {
      debugPrint('[SupabaseManager] 보유 칭호 조회 실패: $error');
      return const [];
    }
  }

  /// 현재 유저의 `profiles.equipped_title`.
  Future<String?> fetchEquippedTitle() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final Map<String, dynamic>? row = await _client
          .from(_profilesTable)
          .select('equipped_title')
          .eq('id', userId)
          .maybeSingle();
      return row?['equipped_title'] as String?;
    } catch (error) {
      debugPrint('[SupabaseManager] 장착 칭호 조회 실패: $error');
      return null;
    }
  }

  /// [titleId] 칭호를 획득 처리한다(`user_titles`에 행 삽입) —
  /// [TitleManager.checkAndGrantTitles]가 조건을 처음 만족한 순간 한 번만
  /// 호출한다. 이미 보유 중이면(중복 삽입 시도) 조용히 실패해도 무방하다
  /// (호출부가 로컬 보유 목록으로 이미 걸러낸 뒤에만 부른다).
  Future<bool> grantTitle(String titleId) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return false;
      }
      await _client.from(_userTitlesTable).insert({
        'user_id': userId,
        'title_id': titleId,
      });
      return true;
    } catch (error) {
      debugPrint('[SupabaseManager] 칭호 획득 기록 실패: $error');
      return false;
    }
  }

  /// [titleId]를 장착한다(null이면 해제) — `profiles.equipped_title` 갱신.
  Future<void> updateEquippedTitle(String? titleId) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client
          .from(_profilesTable)
          .update({'equipped_title': titleId})
          .eq('id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] 장착 칭호 동기화 실패: $error');
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
      final List<dynamic> rows = await _client
          .from(_petStatMetadataTable)
          .select();
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
      final List<dynamic> rows = await _client
          .from(_userArtifactsTable)
          .select()
          .eq('user_id', userId);
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
      final List<dynamic> rows = await _client
          .from(_userRunesTable)
          .select()
          .eq('user_id', userId);
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
      await _client
          .from(_profilesTable)
          .update({'rune_fragments': amount})
          .eq('id', userId);
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
      final List<dynamic> rows = await _client
          .from(_equipmentSetsTable)
          .select();
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
      final List<dynamic> rows = await _client
          .from(_skillMetadataTable)
          .select();
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
      final List<dynamic> rows = await _client
          .from(_userSkillsTable)
          .select()
          .eq('user_id', userId);
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

  // ── 캐릭터 기본 스탯/성장률 (CharacterMetadataManager 전용) ────────
  //
  // 위 `characters`(공격 타입 하나만 담던 기존 테이블)와는 별개의 새
  // 테이블이다 — 컬럼명은 유저가 알려준 계산식(최종 = 기본 * (1 +
  // (level-1)*level_growth_rate) * (1 + star*star_growth_rate), ASPD는
  // 예외로 base_aspd 그대로)에 나온 변수명을 그대로 컬럼명으로 가정했다:
  // character_id(text, PK — Equipment.gradeBadgeLabel과 동일한 형식, 예:
  // 'N1'), base_hp/base_atk/base_def/base_aspd(numeric), level_growth_rate/
  // star_growth_rate(numeric). 실제 컬럼명이 다르면 이 섹션과
  // [CharacterMetadata].fromJson만 고치면 된다.
  static const String _characterMetadataTable = 'character_metadata';

  /// 캐릭터 기본 스탯/성장률 테이블 전체를 내려받는다 — 로그인 여부와
  /// 무관한 공개 데이터라 `currentUserId` 체크 없이 그대로 조회한다
  /// ([fetchCharacterMeta]와 같은 성격). 실패하면(오프라인 등) 빈 리스트 —
  /// 호출부([CharacterMetadataManager])가 이전에 캐시해 둔 값을 그대로
  /// 유지한다.
  Future<List<Map<String, dynamic>>> fetchCharacterMetadata() async {
    try {
      final List<dynamic> rows = await _client
          .from(_characterMetadataTable)
          .select();
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 캐릭터 기본 스탯/성장률 조회 실패: $error');
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
  static const String _worldBossRankingRewardsTable =
      'world_boss_ranking_rewards';

  static const String _monsterDropTableTable = 'monster_drop_table';

  /// 몬스터 처치 드랍 테이블 전체를 내려받는다 — 로그인 여부와 무관한
  /// 공개 데이터라 `currentUserId` 체크 없이 그대로 조회한다
  /// ([fetchConsumableCatalog]와 같은 성격). 실패하면(오프라인 등) 빈
  /// 리스트 — 호출부([MonsterDropTableManager])가 이전에 캐시해 둔
  /// 테이블을 그대로 유지한다.
  Future<List<Map<String, dynamic>>> fetchMonsterDropTable() async {
    try {
      final List<dynamic> rows = await _client
          .from(_monsterDropTableTable)
          .select();
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 몬스터 드랍 테이블 조회 실패: $error');
      return const [];
    }
  }

  static const String _dungeonRewardsConfigTable = 'dungeon_rewards_config';

  /// 던전 클리어 보상 설정(던전 타입/아이템 타입/확률/최소·최대 수량)
  /// 전체를 내려받는다 — [fetchMonsterDropTable]과 같은 성격의 공개
  /// 데이터라 `currentUserId` 체크 없이 그대로 조회한다. 실패하면(오프라인
  /// 등) 빈 리스트 — 호출부([DungeonRewardManager])가 이전에 캐시해 둔
  /// 설정을 그대로 유지한다.
  Future<List<Map<String, dynamic>>> fetchDungeonRewardsConfig() async {
    try {
      final List<dynamic> rows = await _client
          .from(_dungeonRewardsConfigTable)
          .select();
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 던전 보상 설정 조회 실패: $error');
      return const [];
    }
  }

  /// 물약/호감도 아이템 카탈로그 전체를 내려받는다 — 로그인 여부와
  /// 무관한 공개 데이터라 `currentUserId` 체크 없이 그대로 조회한다.
  /// 실패하면(오프라인 등) 빈 리스트 — 호출부([PotionManager])가 이전에
  /// 캐시해 둔 카탈로그를 그대로 유지한다.
  Future<List<Map<String, dynamic>>> fetchConsumableCatalog() async {
    try {
      final List<dynamic> rows = await _client
          .from(_consumableItemsTable)
          .select();
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
      await _client
          .from(_profilesTable)
          .update({'equipped_potion_id': potionId})
          .eq('id', userId);
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
  Future<void> upsertDailyCoinPurchaseCount(
    String itemId,
    String date,
    int count,
  ) async {
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
      final List<dynamic> rows = await _client
          .from(_worldBossConfigTable)
          .select()
          .limit(1);
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
      final List<dynamic> rows = await _client
          .from(_userWorldBossTable)
          .select()
          .eq('user_id', userId)
          .limit(1);
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
  Future<List<Map<String, dynamic>>> fetchWorldBossRanking(
    String sessionId,
  ) async {
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
      await _client.rpc(
        'distribute_world_boss_rewards',
        params: {'p_session_id': sessionId},
      );
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
      final List<dynamic> rows = await _client
          .from(_guildsTable)
          .select()
          .eq('id', guildId)
          .limit(1);
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
      final List<dynamic> rows = await _client
          .from(_guildsTable)
          .select('id')
          .eq('name', name)
          .limit(1);
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
  Future<String?> createGuild({
    required String name,
    required String emblem,
  }) async {
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
      await _client
          .from(_guildsTable)
          .update({'level': level})
          .eq('id', guildId);
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 레벨 동기화 실패: $error');
    }
  }

  /// 길드 공지사항 갱신 — 길드장 전용(권한 체크는 [GuildManager]에서).
  Future<void> updateGuildNotice(String guildId, String notice) async {
    try {
      await _client
          .from(_guildsTable)
          .update({'notice': notice})
          .eq('id', guildId);
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 공지 동기화 실패: $error');
    }
  }

  /// 길드 엠블럼 갱신 — 길드장 전용(권한 체크는 [GuildManager]에서).
  Future<void> updateGuildEmblem(String guildId, String emblem) async {
    try {
      await _client
          .from(_guildsTable)
          .update({'emblem': emblem})
          .eq('id', guildId);
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

  /// [fetchGuildMembers]의 `profiles(...)` 임베드가 특정 행에서 비어
  /// 오는 경우(PostgREST가 `guild_members.user_id → profiles.id` 관계를
  /// 못 찾거나, 임베드 자체가 일시적으로 실패하는 등)를 위한 직접 재조회 —
  /// `profiles` 테이블을 `id`로 바로 필터링해 조인을 거치지 않는다. RLS가
  /// `profiles` 전체 읽기를 허용해 뒀다는 전제라 로그인 상태면 항상 값을
  /// 받아올 수 있어야 한다. [GuildManager.refreshMembers]가 1차 조인 결과
  /// 중 닉네임 해석에 실패한 행만 골라 이걸로 보충한다.
  Future<Map<String, String>> fetchNicknamesByUserIds(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) {
      return const {};
    }
    try {
      final List<dynamic> rows = await _client
          .from(_profilesTable)
          .select('id, nickname')
          .inFilter('id', userIds);
      final Map<String, String> result = {};
      for (final dynamic row in rows) {
        final Map<String, dynamic> map = row as Map<String, dynamic>;
        final String? nickname = map['nickname'] as String?;
        if (nickname != null && nickname.trim().isNotEmpty) {
          result[map['id'] as String] = nickname;
        }
      }
      return result;
    } catch (error) {
      debugPrint('[SupabaseManager] 닉네임 재조회 실패: $error');
      return const {};
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
  Future<List<Map<String, dynamic>>> fetchGuildMessages(
    String guildId, {
    int limit = 100,
  }) async {
    try {
      final List<dynamic> rows = await _client
          .from(_guildMessagesTable)
          .select(
            'id, guild_id, user_id, message, created_at, profiles(nickname)',
          )
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

  /// [guildId]에 채팅 메시지 한 건을 보내고, 서버가 채번한 실제 행(id/
  /// created_at 포함)을 그대로 돌려준다 — 실패하면 null.
  ///
  /// 예전엔 성공 여부(bool)만 돌려주고, 화면 반영은 오직 이 insert가
  /// 트리거하는 Realtime `postgres_changes` 에코([subscribeToGuildMessages])
  /// 에만 의존했다 — 그래서 전송 버튼을 누른 뒤 내 메시지가 화면에 뜨기까지
  /// 왕복 지연(서버 처리 + Realtime 브로드캐스트)만큼 체감 딜레이가 있었다.
  /// 이제 insert 자체가 실제 행을 즉시 돌려주므로, 호출부([GuildChatManager
  /// .sendMessage])가 그 값으로 곧바로(낙관적으로) 로컬 리스트를 갱신할 수
  /// 있다 — 나중에 같은 id로 Realtime 에코가 도착해도 기존 dedup 로직이
  /// 그대로 걸러준다.
  Future<Map<String, dynamic>?> sendGuildMessage({
    required String guildId,
    required String message,
  }) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final Map<String, dynamic> row = await _client
          .from(_guildMessagesTable)
          .insert({'guild_id': guildId, 'user_id': userId, 'message': message})
          .select('id, guild_id, user_id, message, created_at')
          .single();
      return row;
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 채팅 전송 실패: $error');
      return null;
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
  Future<void> updateGuildMemberRole(
    String guildId,
    String targetUserId,
    String role,
  ) async {
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
      await _client
          .from(_profilesTable)
          .update({'guild_coin': 0})
          .eq('id', userId);
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
      await _client
          .from(_profilesTable)
          .update({'guild_coin': amount})
          .eq('id', userId);
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
      final List<dynamic> rows = await _client
          .from(_guildShopItemsTable)
          .select();
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
      final List<dynamic> rows = await _client
          .from(_userArenaTable)
          .select()
          .eq('user_id', userId)
          .limit(1);
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
  Future<List<Map<String, dynamic>>> fetchArenaOpponentCandidates(
    int myScore,
  ) async {
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
      await _client.rpc(
        'distribute_arena_rewards',
        params: {'p_season_id': seasonId},
      );
    } catch (error) {
      debugPrint('[SupabaseManager] 결투장 보상 정산 RPC 실패: $error');
    }
  }

  // ── 퀘스트 (QuestManager 전용) ────────────────────────────────────
  //
  // quest_catalog(`id`, `period_type`, `action_type`, `target_count`,
  // `reward_type`, `reward_amount`, `description`) — 일일/주간/월간
  // 퀘스트 "풀"을 통째로 담은 공개 카탈로그. `user_quests`(`user_id`,
  // `quest_id`, `current_count`, `is_claimed`)는 그 풀에서 실제로 이
  // 유저에게 배정된 항목만 행으로 갖는다 — 배정 여부 자체를 별도 컬럼이
  // 아니라 "행이 존재하는지"로 표현한다([QuestManager] 참고). 실제
  // 컬럼명이 다르면 이 섹션과 [Quest]/[QuestProgress].fromJson만 고치면
  // 된다. `action_type`/`reward_type` 값은 [QuestActionType]/
  // [QuestRewardType] 상수와 서버 시드 데이터가 반드시 합의해야 한다.
  static const String _questCatalogTable = 'quest_catalog';
  static const String _userQuestsTable = 'user_quests';

  /// 일일/주간/월간 퀘스트 풀 전체 — 로그인 여부와 무관한 공개 데이터.
  Future<List<Map<String, dynamic>>> fetchQuestCatalog() async {
    try {
      final List<dynamic> rows = await _client
          .from(_questCatalogTable)
          .select();
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 퀘스트 카탈로그 조회 실패: $error');
      return const [];
    }
  }

  /// 현재 유저에게 배정된 퀘스트 전체와 그 진행도.
  Future<List<Map<String, dynamic>>> fetchUserQuests() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return const [];
      }
      final List<dynamic> rows = await _client
          .from(_userQuestsTable)
          .select()
          .eq('user_id', userId);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 퀘스트 진행도 조회 실패: $error');
      return const [];
    }
  }

  /// 여러 퀘스트의 진행도를 한 번의 요청으로 갱신(또는 새로 배정된
  /// 퀘스트를 진행도 0으로 최초 생성)한다 — [QuestManager]가 짧은 시간에
  /// 몰리는 진행도 갱신(예: 몬스터 연속 처치)을 모아서 이 메서드 한 번으로
  /// 흘려보낸다(매 처치마다 네트워크 요청을 쏘지 않기 위함). [rows]의 각
  /// 항목은 `{quest_id, current_count, is_claimed}` 형태다.
  Future<void> upsertUserQuestProgressBatch(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) {
      return;
    }
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client.from(_userQuestsTable).upsert([
        for (final Map<String, dynamic> row in rows)
          {...row, 'user_id': userId},
      ]);
    } catch (error) {
      debugPrint('[SupabaseManager] 퀘스트 진행도 일괄 동기화 실패: $error');
    }
  }

  /// 주기가 리셋되어 재배정될 때, 이전에 배정돼 있던 [questIds]의 행을
  /// 지운다 — [QuestManager]가 새 무작위 배정을 [upsertUserQuestProgressBatch]
  /// 로 다시 삽입하기 직전에 호출한다(배정 해제 = 행 삭제라는 [QuestManager]
  /// 관례를 서버에도 그대로 반영).
  Future<void> deleteUserQuestsByIds(List<String> questIds) async {
    if (questIds.isEmpty) {
      return;
    }
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client
          .from(_userQuestsTable)
          .delete()
          .eq('user_id', userId)
          .inFilter('quest_id', questIds);
    } catch (error) {
      debugPrint('[SupabaseManager] 이전 배정 퀘스트 삭제 실패: $error');
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
  Future<Map<String, dynamic>?> fetchUserBattlePass({
    required String seasonId,
  }) async {
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
  ///
  /// [seasonId]는 `battle_pass_seasons.id`를 그대로 문자열화한 값이라
  /// 길이가 고정돼 있지 않다 — `user_battle_pass.season_id` 컬럼은 반드시
  /// `text`(또는 충분히 넉넉한 varchar)여야 한다. `varchar(20)`처럼 좁게
  /// 잡혀 있으면 시즌 id가 길 때 "value too long for type character
  /// varying(20)"로 upsert가 통째로 실패한다 — season_id는 이 테이블의
  /// 복합 PK 절반을 이루는 식별자라 클라이언트에서 임의로 잘라내거나
  /// 해시로 바꿔 보내면 안 된다(다른 시즌과 충돌하거나
  /// `battle_pass_seasons.id`를 참조하는 FK가 깨진다) — 컬럼 타입을
  /// 넓히는 것이 유일하게 안전한 수정이다.
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

  // ── 마스터 캐릭터 (CharacterManifestManager 전용) ─────────────────────
  //
  // `master_characters`(`sub_id` text PK — "N1"/"SR2"처럼 등급 접두어+
  // 넘버링을 합친 문자열, `name`, `grade`, `job`, `is_active` bool,
  // `gacha_weight` int, `image_path` text)로 실제 존재하는 캐릭터 목록과
  // 가챠 당첨 가중치를 앱 재배포 없이 원격 제어한다. `is_active = false`인
  // 행은 서버 쿼리 단계에서부터 제외해, 클라이언트가 실수로라도 비활성
  // 캐릭터를 읽어들일 여지를 없앤다.
  static const String _masterCharactersTable = 'master_characters';

  /// 활성(`is_active = true`) 캐릭터 전체 — [CharacterManifestManager]가
  /// 도감/가챠 풀을 구성하는 유일한 원천. 실패해도(오프라인 등) 빈 리스트를
  /// 돌려주며, 호출부가 로컬 캐시로 폴백한다.
  Future<List<Map<String, dynamic>>> fetchMasterCharacters() async {
    try {
      final List<dynamic> rows = await _client
          .from(_masterCharactersTable)
          .select()
          .eq('is_active', true);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 마스터 캐릭터 목록 조회 실패: $error');
      return const [];
    }
  }

  // ── 마스터 컬렉션 (CollectionManager 전용) ────────────────────────────
  //
  // `master_collections`(`id` text PK, `category` text 'character'|
  // 'equipment'|'pet', `title` text, `required_items` jsonb —
  // [RequiredCollectionItem.toJson]과 동일한 키(type/grade/subId/
  // requiredLevel/count)를 쓰는 배열, `reward_stat` jsonb —
  // [CollectionRewardStat.toJson]과 동일한 키(type/value), `is_active`
  // bool, `sort_order` int)로 세트 수집 정의를 원격 제어한다. JSONB 컬럼이
  // 기존 모델의 `toJson`/`fromJson`과 키를 맞춰 쓰도록 설계해, 새로운
  // 파싱 로직 없이 [CollectionModel.fromJson]을 거의 그대로 재사용할 수
  // 있다.
  static const String _masterCollectionsTable = 'master_collections';

  /// 활성(`is_active = true`) 컬렉션 세트 정의 전체(`sort_order` 오름차순) —
  /// [CollectionManager]가 세트 목록을 구성하는 유일한 원천. 실패해도
  /// 빈 리스트를 돌려주며, 호출부가 로컬 캐시로 폴백한다.
  Future<List<Map<String, dynamic>>> fetchMasterCollections() async {
    try {
      final List<dynamic> rows = await _client
          .from(_masterCollectionsTable)
          .select()
          .eq('is_active', true)
          .order('sort_order', ascending: true);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 마스터 컬렉션 목록 조회 실패: $error');
      return const [];
    }
  }

  static const String _userCollectionsTable = 'user_collections';

  /// 현재 유저가 완료한 컬렉션 id 전체 — [CollectionManager.loadData]가
  /// 로컬 저장값과 합쳐서(둘 중 하나라도 완료면 완료로 취급) 다른 기기에서
  /// 이미 등록한 컬렉션도 놓치지 않게 한다. 실패하면 빈 리스트 — 로컬
  /// 저장값만으로 계속 진행한다.
  Future<List<String>> fetchUserCollections() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return const [];
      }
      final List<dynamic> rows = await _client
          .from(_userCollectionsTable)
          .select('collection_id')
          .eq('user_id', userId);
      return rows
          .cast<Map<String, dynamic>>()
          .map((row) => row['collection_id'] as String)
          .toList();
    } catch (error) {
      debugPrint('[SupabaseManager] 완료한 컬렉션 목록 조회 실패: $error');
      return const [];
    }
  }

  /// [CollectionManager.register]가 컬렉션을 완료 처리한 직후 호출 —
  /// `user_collections`에 완성 기록 1행을 남긴다. 같은 컬렉션을 두 번
  /// 등록할 일은 없지만(완료된 컬렉션은 [CollectionManager.canRegister]가
  /// 항상 false), 혹시 모를 중복 호출에도 안전하도록 upsert한다.
  Future<void> syncCollectionCompletion(String collectionId) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client.from(_userCollectionsTable).upsert({
        'user_id': userId,
        'collection_id': collectionId,
      }, onConflict: 'user_id, collection_id');
    } catch (error) {
      debugPrint('[SupabaseManager] 컬렉션 완성 기록 저장 실패: $error');
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
  Future<({int dailyAdViews, DateTime? lastAdViewedAt})?>
  fetchAdViewState() async {
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
        lastAdViewedAt: lastViewedRaw == null
            ? null
            : DateTime.tryParse(lastViewedRaw),
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
      await _client
          .from(_profilesTable)
          .update({
            'daily_ad_views': dailyAdViews,
            'last_ad_viewed_at': lastAdViewedAtIso,
          })
          .eq('id', userId);
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
        params: {
          'p_guild_id': guildId,
          'p_user_id': userId,
          'p_damage': damage,
        },
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

  static const String _guildBossParticipantsTable = 'guild_boss_participants';

  /// [guildId] 길드의 레이드 기여도 상위 5명(`total_damage_dealt` 내림차순)
  /// — `guild_boss_attack` RPC가 공격마다 이 테이블에 직접 누적 기록해
  /// 두므로, 여기서는 조회만 한다([fetchWorldBossRanking]과 같은
  /// `profiles(nickname)` 임베드 관례). 실패하면 빈 리스트(호출부가 이전
  /// 캐시를 유지).
  Future<List<Map<String, dynamic>>> fetchGuildBossLeaderboard(
    String guildId,
  ) async {
    try {
      final List<dynamic> rows = await _client
          .from(_guildBossParticipantsTable)
          .select('user_id, total_damage_dealt, profiles(nickname)')
          .eq('guild_id', guildId)
          .order('total_damage_dealt', ascending: false)
          .limit(5);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 레이드 기여도 랭킹 조회 실패: $error');
      return const [];
    }
  }

  /// [guildId] 보스 행의 변경(UPDATE — 다른 길드원의 공격으로 체력이
  /// 깎일 때마다)을 실시간으로 구독한다 — [onChanged]는 매번 원본 row를
  /// 그대로 넘긴다. 요구사항: "다른 길드원이 때린 데미지가 내 화면의
  /// 보스 HP 바에도... 주기적으로(또는 Realtime으로) 갱신" — 이미 같은
  /// 목적으로 쓰인 [subscribeToGuildMessages]와 같은 관례(체감 지연 없이
  /// 즉시 반영). 반환된 채널은 화면을 떠날 때 반드시 [unsubscribeChannel]
  /// 로 정리해야 한다. 구독 생성 자체가 실패하면 null.
  RealtimeChannel? subscribeToGuildBoss(
    String guildId,
    void Function(Map<String, dynamic> row) onChanged,
  ) {
    try {
      return _client
          .channel('guild_boss_$guildId')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: _guildBossesTable,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'guild_id',
              value: guildId,
            ),
            callback: (payload) => onChanged(payload.newRecord),
          )
          .subscribe();
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 레이드 보스 구독 실패: $error');
      return null;
    }
  }

  // ── 길드 전쟁(GvG) + 세금 (GuildWarManager 전용) ────────────────────
  //
  // `guild_war_config`/`global_tax_pool`은 싱글턴 1행 테이블, `guild_wars`는
  // (week_key, guild_id) 유니크한 길드별 전쟁 인스턴스, `guild_war_badges`는
  // 정산 RPC가 승리 길드원 전원에게 기록하는 휘장 지급 이력이다 — 정확한
  // SQL은 완료 보고에 함께 첨부한다.
  static const String _guildWarConfigTable = 'guild_war_config';
  static const String _globalTaxPoolTable = 'global_tax_pool';
  static const String _guildWarsTable = 'guild_wars';
  static const String _guildWarBadgesTable = 'guild_war_badges';

  /// 세금 비율/최소 보장 보상/휘장 버프 수치 — LiveOps 설정. 조회 실패 시
  /// null(호출부가 [GuildWarConfig.fallback]으로 대체).
  Future<Map<String, dynamic>?> fetchGuildWarConfig() async {
    try {
      return await _client
          .from(_guildWarConfigTable)
          .select()
          .eq('id', 1)
          .maybeSingle();
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 전쟁 설정 조회 실패: $error');
      return null;
    }
  }

  // ── 총 전투력 가중치 (ConfigManager 전용) ──────────────────────────
  //
  // `game_config` 테이블 한 행(id='cp_weights')에 담긴 서버 조정 가중치 —
  // 컬럼: id(text, PK), def_weight(numeric), offense_weight(numeric).
  // `id` 컬럼이 있는 이유는 이 테이블이 (guild_war_config처럼) 앞으로
  // 여러 설정 그룹을 같은 테이블의 다른 행으로 담을 수 있게 설계됐기
  // 때문이다 — 실제 컬럼명이 다르면 이 섹션과 [CombatPowerWeights]
  // .fromJson만 고치면 된다.
  static const String _gameConfigTable = 'game_config';

  /// [ConfigManager.loadConfig]가 앱 시작 시 한 번 호출 — 로그인 여부와
  /// 무관한 공개 데이터라 `currentUserId` 체크 없이 그대로 조회한다
  /// ([fetchGuildWarConfig]와 같은 성격). 실패하면(오프라인 등) null —
  /// 호출부가 [CombatPowerWeights]의 기본값(20.0/10.0)으로 안전하게
  /// 대체한다.
  Future<Map<String, dynamic>?> fetchCombatPowerWeights() async {
    try {
      return await _client
          .from(_gameConfigTable)
          .select()
          .eq('id', 'cp_weights')
          .maybeSingle();
    } catch (error) {
      debugPrint('[SupabaseManager] 전투력 가중치 설정 조회 실패: $error');
      return null;
    }
  }

  /// 서버 전체 누적 세금 풀 — 신청 화면 중앙에 실시간으로 보여준다.
  Future<Map<String, dynamic>?> fetchGlobalTaxPool() async {
    try {
      return await _client
          .from(_globalTaxPoolTable)
          .select()
          .eq('id', 1)
          .maybeSingle();
    } catch (error) {
      debugPrint('[SupabaseManager] 세금 풀 조회 실패: $error');
      return null;
    }
  }

  /// [coinSpent]/[gemSpent](가챠·요일 던전에서 실제로 소모한 재화)의
  /// `tax_rate`만큼을 `accrue_global_tax` RPC로 세금 풀에 원자적으로
  /// 더한다 — 여러 유저가 동시에 소비해도 반영분이 유실되지 않는다. 이미
  /// 로컬에서 재화 차감(예: [GameManager.spendGold])이 끝난 뒤에만
  /// 호출하는 fire-and-forget 부가 동작이라, 실패해도 게임 진행에는
  /// 영향이 없다.
  Future<void> accrueGlobalTax({int coinSpent = 0, int gemSpent = 0}) async {
    if (coinSpent <= 0 && gemSpent <= 0) {
      return;
    }
    try {
      await _client.rpc(
        'accrue_global_tax',
        params: {'p_coin_spent': coinSpent, 'p_gem_spent': gemSpent},
      );
    } catch (error) {
      debugPrint('[SupabaseManager] 세금 적립 RPC 실패: $error');
    }
  }

  /// [guildId]가 [weekKey] 전쟁에 신청한다 — 이미 신청한 행이 있으면
  /// 아무것도 덮어쓰지 않는다(`ignoreDuplicates`로 최초 신청만 반영, 이미
  /// 매칭된 이후 재신청 시도로 상태가 되돌아가는 사고를 막는다).
  Future<bool> applyForGuildWar({
    required String guildId,
    required String weekKey,
  }) async {
    try {
      await _client
          .from(_guildWarsTable)
          .upsert(
            {'guild_id': guildId, 'week_key': weekKey},
            onConflict: 'week_key,guild_id',
            ignoreDuplicates: true,
          );
      return true;
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 전쟁 신청 실패: $error');
      return false;
    }
  }

  /// [guildId]의 [weekKey] 전쟁 상태 한 행 — 아직 신청 전이면 null.
  Future<Map<String, dynamic>?> fetchMyGuildWar({
    required String guildId,
    required String weekKey,
  }) async {
    try {
      return await _client
          .from(_guildWarsTable)
          .select()
          .eq('guild_id', guildId)
          .eq('week_key', weekKey)
          .maybeSingle();
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 전쟁 상태 조회 실패: $error');
      return null;
    }
  }

  /// `match_guild_wars` RPC를 찔러본다 — 토요일 21:00 이전이면 RPC 내부
  /// 시간 가드가 아무 것도 하지 않으므로, 아무 때나 호출해도 안전하다
  /// (여러 클라이언트가 동시에 전쟁 탭을 열어 동시에 찔러도 멱등적).
  Future<void> triggerMatchGuildWars(String weekKey) async {
    try {
      await _client.rpc('match_guild_wars', params: {'p_week_key': weekKey});
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 전쟁 매칭 RPC 실패: $error');
    }
  }

  /// [warId] 거점에 [damage]만큼 공격한다 — `guild_war_attack` RPC가
  /// 방어력 감쇄/참여자 데미지 누적/거점 파괴 판정까지 원자적으로 처리한다.
  Future<GuildWarAttackResult?> attackGuildWarBase({
    required String warId,
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
        'guild_war_attack',
        params: {'p_war_id': warId, 'p_user_id': userId, 'p_damage': damage},
      );
      final List<dynamic> rows = response as List<dynamic>;
      if (rows.isEmpty) {
        return null;
      }
      return GuildWarAttackResult.fromJson(rows.first as Map<String, dynamic>);
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 전쟁 공격 RPC 실패: $error');
      return null;
    }
  }

  /// `settle_guild_wars` RPC를 찔러본다 — 그 주가 아직 안 끝났거나 이미
  /// 정산됐으면 RPC 내부에서 조용히 아무 것도 하지 않는다(멱등적).
  Future<void> triggerSettleGuildWars(String weekKey) async {
    try {
      await _client.rpc('settle_guild_wars', params: {'p_week_key': weekKey});
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 전쟁 정산 RPC 실패: $error');
    }
  }

  /// 현재 유저에게 아직 만료되지 않은 휘장 지급 기록이 있는지 — 있으면
  /// [GuildWarManager]가 로컬 인벤토리에 그대로 구현(materialize)한다.
  /// 만료 시각까지 조건에 넣어 이미 지난 지급 기록은 애초에 받아오지
  /// 않는다. [now]는 반드시 [getNetworkTime](NTP)으로 받아온 시간이어야
  /// 한다 — 기기 시계를 쓰면, 시계를 되돌려 이미(실제로는) 만료된 지급
  /// 기록을 다시 "유효한" 것으로 조회해 재장착할 수 있다.
  Future<Map<String, dynamic>?> fetchMyActiveWarBadge(DateTime now) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final List<dynamic> rows = await _client
          .from(_guildWarBadgesTable)
          .select()
          .eq('user_id', userId)
          .gt('expires_at', now.toUtc().toIso8601String())
          .order('granted_at', ascending: false)
          .limit(1);
      if (rows.isEmpty) {
        return null;
      }
      return rows.first as Map<String, dynamic>;
    } catch (error) {
      debugPrint('[SupabaseManager] 휘장 지급 기록 조회 실패: $error');
      return null;
    }
  }

  /// `profiles.combat_power`를 절대값으로 덮어쓴다 — [updateGold]와 같은
  /// "로컬이 먼저 확정한 값을 그대로 push" 관례. 길드 전쟁 매칭 공식이
  /// 이 컬럼(길드원 합산)을 직접 읽으므로, 신청 시점에 최신 전투력으로
  /// 갱신해 둬야 매칭이 정확하다.
  Future<void> updateCombatPower(int power) async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return;
      }
      await _client
          .from(_profilesTable)
          .update({'combat_power': power})
          .eq('id', userId);
    } catch (error) {
      debugPrint('[SupabaseManager] 전투력 동기화 실패: $error');
    }
  }

  /// 길드 금고 → [targetUserId] 개인 재화로 [coinAmount]/[gemAmount]를
  /// 옮긴다(전리품 분배) — `transfer_guild_treasury` RPC가 호출자가
  /// 길드장인지, 대상이 같은 길드원인지, 금고 잔액이 충분한지까지 전부
  /// 서버에서 검증한 뒤 원자적으로 처리한다. 성공하면 true.
  Future<bool> transferGuildTreasury({
    required String guildId,
    required String targetUserId,
    required int coinAmount,
    required int gemAmount,
  }) async {
    try {
      final dynamic result = await _client.rpc(
        'transfer_guild_treasury',
        params: {
          'p_guild_id': guildId,
          'p_target_user_id': targetUserId,
          'p_coin_amount': coinAmount,
          'p_gem_amount': gemAmount,
        },
      );
      return result == true;
    } catch (error) {
      debugPrint('[SupabaseManager] 길드 금고 분배 RPC 실패: $error');
      return false;
    }
  }
}
