import 'package:flutter_test/flutter_test.dart';

import 'package:idle_rpg/main.dart';

import 'test_utils/supabase_test_helper.dart';

void main() {
  testWidgets('App boots into LoginScreen without crashing', (WidgetTester tester) async {
    // main()이 runApp() 전에 거치는 수십 개의 매니저 초기화(Supabase 조회 등)는
    // 여기서 실행하지 않는다 — MyApp.build()의 home은 항상 LoginScreen이고,
    // LoginScreen이 initState에서 곧바로 읽는 건 Supabase 하나뿐이라(다른
    // 매니저는 로그인 이후 GameEntryScreen부터 관여한다), 이 화면 하나를
    // 부팅하는 데는 Supabase 초기화만 있으면 충분하다.
    await initializeTestSupabase();

    await tester.pumpWidget(const MyApp());
    // LoginScreen.initState가 addPostFrameCallback으로 예약한 자동 로그인
    // 확인(_checkAutoLogin)이 마저 돌 시간을 준다 — 세션이 없으니(더미
    // Supabase 인스턴스) 아무 데도 네비게이션하지 않고 조용히 끝난다.
    await tester.pump();

    expect(find.text('Cyber Breaker Idle'), findsOneWidget);
    expect(find.text('게스트로 시작하기'), findsOneWidget);
    expect(find.text('구글 로그인'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
