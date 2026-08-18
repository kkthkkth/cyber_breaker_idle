import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// [LoginScreen] 같은 화면은 `initState`에서 곧바로 `Supabase.instance`를
/// 읽는다(자동 로그인 확인, auth 상태 스트림 구독) — 실제 `main()`을 거치지
/// 않는 위젯 테스트에서 그런 화면을 `pumpWidget`하려면 이 헬퍼를 먼저
/// 호출해야 한다("You must initialize the supabase instance..." 어서션으로
/// 죽는 것을 막는다).
///
/// 실제 Supabase 프로젝트에는 전혀 연결하지 않는다 — 존재하지 않는 더미
/// URL/키로 클라이언트 껍데기만 만들고, [EmptyLocalStorage]로 세션 저장을
/// 끄고, `detectSessionInUri: false`로 딥링크 옵저버(app_links 플러그인,
/// 테스트 환경에 플랫폼 채널이 없다)도 띄우지 않는다. `autoRefreshToken:
/// false`도 필수다 — 기본값(true)이면 GoTrueClient가 주기적 세션 갱신용
/// Timer를 띄우는데, 이 Timer는 세션이 없어도 계속 살아 있어서 위젯 트리가
/// dispose된 뒤에도 남아 flutter_test의 "pending timer" 어서션을 건드린다.
/// 이 상태에서 `Supabase.instance.client.auth.currentUser`는 항상 null이라,
/// 로그인 화면의 "자동 로그인 확인" 로직이 실제 네트워크 요청 없이 안전하게
/// "로그인 안 됨"으로 끝난다 — 로그인 버튼을 실제로 눌러 게스트/구글
/// 로그인을 완주하는 흐름까지는 이 헬퍼로 테스트할 수 없다(그건 진짜
/// 네트워크가 필요한 통합 테스트의 영역이다).
///
/// `Supabase.initialize`는 패키지 내부적으로 이미 초기화된 상태에서 다시
/// 호출해도 예외 없이 조용히 건너뛰므로, 같은 테스트 파일 안의 여러
/// 테스트/그룹에서 각각 호출해도 안전하다.
Future<void> initializeTestSupabase() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // shared_preferences는 GoTrue의 PKCE 코드 검증기 저장소
  // (SharedPreferencesGotrueAsyncStorage)가 내부적으로 건드린다 — 플랫폼
  // 채널이 없는 테스트 환경에서도 정상 동작하도록 인메모리 목(mock)을
  // 깔아 둔다.
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'https://test.supabase.co',
    publishableKey: 'test-anon-key',
    debug: false,
    authOptions: const FlutterAuthClientOptions(
      localStorage: EmptyLocalStorage(),
      detectSessionInUri: false,
      autoRefreshToken: false,
    ),
  );
}
