import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  /// [guildId] 소속 멤버 전원을 기여도 내림차순으로 — `profiles(nickname)`
  /// 임베드로 닉네임까지 한 번에 가져온다.
  Future<List<Map<String, dynamic>>> fetchGuildMembers(String guildId) async {
    try {
      final List<dynamic> rows = await _client
          .from(_guildMembersTable)
          .select('user_id, role, contribution, profiles(nickname)')
          .eq('guild_id', guildId)
          .order('contribution', ascending: false);
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('[SupabaseManager] 길드원 목록 조회 실패: $error');
      return const [];
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
  // `battle_pass_rewards`/`user_battle_pass` 컬럼도 같은 이유로 가정:
  // battle_pass_rewards(`level`, `free_reward_type`, `free_reward_amount`,
  // `premium_reward_type`, `premium_reward_amount`), user_battle_pass
  // (`user_id`, `bp_exp`, `is_premium`, `claimed_free_levels` int[],
  // `claimed_premium_levels` int[]) — 무료/프리미엄 수령 여부를 별도
  // 테이블 없이 배열 컬럼 두 개로 표현했다.
  static const String _battlePassRewardsTable = 'battle_pass_rewards';
  static const String _userBattlePassTable = 'user_battle_pass';

  /// 레벨별 보상 트랙 전체(레벨 오름차순) — 로그인 여부와 무관한 공개
  /// 데이터.
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

  /// 현재 유저의 배틀패스 상태(exp/프리미엄 여부/수령 이력) — 아직 한
  /// 번도 동기화된 적 없으면 null, 호출부([BattlePassManager])가
  /// 기본값(0 exp/무료 패스)을 그대로 쓴다.
  Future<Map<String, dynamic>?> fetchUserBattlePass() async {
    try {
      final String? userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final List<dynamic> rows =
          await _client.from(_userBattlePassTable).select().eq('user_id', userId).limit(1);
      if (rows.isEmpty) {
        return null;
      }
      return rows.first as Map<String, dynamic>;
    } catch (error) {
      debugPrint('[SupabaseManager] 배틀패스 상태 조회 실패: $error');
      return null;
    }
  }

  /// 배틀패스 상태(전부 절대값)를 갱신한다 — 퀘스트 보상으로 exp가
  /// 오를 때, 보상을 수령할 때, 프리미엄 패스를 해금할 때 전부 이
  /// 메서드 하나로 동기화한다.
  Future<void> upsertUserBattlePass({
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
        'bp_exp': bpExp,
        'is_premium': isPremium,
        'claimed_free_levels': claimedFreeLevels,
        'claimed_premium_levels': claimedPremiumLevels,
      });
    } catch (error) {
      debugPrint('[SupabaseManager] 배틀패스 상태 동기화 실패: $error');
    }
  }
}
