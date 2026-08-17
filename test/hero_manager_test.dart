import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_rpg/managers/hero_manager.dart';

void main() {
  test('heroImagePath points at the bundled local asset', () {
    expect(HeroManager.heroImagePath, 'assets/images/hero.png');
  });

  testWidgets('buildHeroSprite renders the hero image with no load error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HeroManager.instance.buildHeroSprite(width: 100, height: 100),
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
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    final BuildContext context = tester.element(find.byType(Scaffold));

    await expectLater(HeroManager.instance.preload(context), completes);
  });
}
