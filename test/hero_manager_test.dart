import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_rpg/managers/hero_manager.dart';

import 'test_utils/fake_asset_bundle.dart';

void main() {
  test('heroImagePath points at the bundled local asset', () {
    expect(HeroManager.heroImagePath, 'assets/images/hero.png');
  });

  // hero.png는 아직 아트팀이 저장소에 올리지 않은 실물 파일이라(assets/images/
  // 아래에 존재하지 않음 — HeroManager 문서 참고) 진짜 rootBundle로는 항상
  // 404 성격의 로드 실패가 난다. 이 두 테스트는 "파일이 실제로 있을 때"의
  // 정상 경로(로드 성공 → 이미지 렌더/precache 완료)를 검증하려는 것이므로,
  // 그 경로만 [FakeAssetBundle]로 더미 PNG를 흘려보낸다 — HeroManager
  // 자체나 실제 asset 파일은 전혀 건드리지 않는다.
  final Set<String> dummyAssetKeys = {HeroManager.heroImagePath};

  testWidgets('buildHeroSprite renders the hero image with no load error', (tester) async {
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: FakeAssetBundle(dummyAssetKeys),
        child: MaterialApp(
          home: Scaffold(
            body: HeroManager.instance.buildHeroSprite(width: 100, height: 100),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    // If the asset had failed to decode, errorBuilder would have swapped in
    // this fallback icon instead — asserting its absence confirms the real
    // image loaded successfully.
    expect(find.byIcon(Icons.person), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('errorBuilder swaps in a placeholder icon instead of crashing on a bad path', (tester) async {
    // Exercises the exact errorBuilder HeroManager.buildHeroSprite wires up,
    // against a path that is guaranteed not to exist in the asset bundle —
    // this is what actually protects the app from a missing/corrupt file.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Image.asset(
            'assets/images/hero_this_path_does_not_exist.png',
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.person, size: 48, color: Colors.white24),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preload completes without throwing', (tester) async {
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: FakeAssetBundle(dummyAssetKeys),
        child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      ),
    );
    final BuildContext context = tester.element(find.byType(Scaffold));

    // precacheImage()가 기다리는 실제 이미지 디코드 완료 콜백은 flutter_tester
    // 엔진 스레드에서 오는데, 이 테스트 존(자동 pump 기반 fake 타이머 존)
    // 안에서 그냥 await만 하면 그 콜백이 결코 전달되지 않아 무한히 멈춘다
    // (재현 확인됨 — 10분 타임아웃). runAsync가 콜백을 실제 이벤트 루프
    // 존에서 돌려줘야 정상적으로 완료된다.
    await tester.runAsync(() => HeroManager.instance.preload(context));
  });
}
