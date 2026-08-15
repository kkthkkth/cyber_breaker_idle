import 'package:flutter/material.dart';

import '../constants/app_images.dart';
import '../models/equipment.dart';
import '../widgets/illustration_viewer.dart';

/// 장착된 캐릭터의 성급(★0~5) 일러스트 뷰어 팝업 — 프로필 아이콘에서
/// 열든(main.dart) 상세 팝업의 갤러리 슬롯을 탭해서 열든([initialLevel]
/// 지정) 전부 이 위젯 하나를 공유한다. [initialLevel]을 안 주면(=프로필
/// 아이콘처럼 특정 슬롯에서 연 게 아니면) 해금된 성급 중 가장 높은 것부터
/// 보여준다. 해금된 성급들 사이는 [PageView]로 좌우 스와이프해서 넘겨볼 수
/// 있다 — 잠긴 성급은 애초에 페이지 목록에 넣지 않는다(스포일러 방지).
///
/// 각 페이지는 공용 [IllustrationViewer]를 그대로 쓴다 — 처음엔 정지
/// .png만 보여주고, 좌측 상단 반투명 재생 버튼을 눌러야만 애니메이션
/// .webp로 바뀐다(메모리 최적화). 일러스트를 더블 탭하면 [Hero] 전환으로
/// [FullScreenIllustrationViewer]가 열리고, 그 안에서만 [InteractiveViewer]
/// 로 마음껏 확대/축소·패닝할 수 있다 — "팝업 프레임 안에서만 확대돼
/// 잘려 보이는" 문제 자체를 아예 구조적으로 없앤 것이다(카드 프레임 크기와
/// 무관하게 진짜 전체화면 새 라우트로 이동하므로).
class CharacterIllustrationDialog extends StatefulWidget {
  const CharacterIllustrationDialog({super.key, required this.character, this.initialLevel});

  final Equipment character;

  /// 특정 성급부터 보여주고 싶을 때(예: 갤러리에서 ★2를 탭함) 지정한다.
  /// null이면 해금된 것 중 가장 높은 성급부터 시작한다.
  final int? initialLevel;

  /// 이 캐릭터+성급 조합에서만 유일한 [Hero] 태그 — 이 팝업(카드 프레임)의
  /// 페이지, [_FullScreenIllustrationPage](진짜 전체화면), 그리고 상세
  /// 팝업 하단의 작은 썸네일(item_detail_dialog.dart의
  /// `_StarIllustrationSlot`) 셋 다 정확히 같은 문자열을 써야 Hero
  /// 전환이(썸네일→카드 팝업, 카드 팝업→전체화면 모두) 끊기지 않고
  /// 이어진다. 확장자(썸네일 .png ↔ 카드/전체화면 .webp)가 달라도 태그
  /// 자체는 characterId+level로만 결정되므로 무관하다.
  static String heroTag(String characterId, int level) =>
      'character-illustration-$characterId-$level';

  @override
  State<CharacterIllustrationDialog> createState() => _CharacterIllustrationDialogState();
}

class _CharacterIllustrationDialogState extends State<CharacterIllustrationDialog> {
  static const int maxStarLevel = 5;

  late final List<int> _unlockedLevels;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();

    // ★0(기본 일러스트)은 캐릭터를 보유하기만 해도 항상 해금 상태다 —
    // star 필드는 0 미만으로 내려가지 않으므로 "0 <= currentStarLevel"은
    // 항상 참이라 별도 예외 처리 없이 같은 식으로 자연스럽게 걸러진다.
    final int currentStarLevel = widget.character.star;
    _unlockedLevels = [
      for (int level = 0; level <= maxStarLevel; level++)
        if (level <= currentStarLevel) level,
    ];

    final int requestedLevel = widget.initialLevel ?? _unlockedLevels.last;
    final int startIndex = _unlockedLevels.indexOf(requestedLevel);
    _pageController = PageController(initialPage: startIndex >= 0 ? startIndex : 0);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _heroTag(int level) =>
      CharacterIllustrationDialog.heroTag(widget.character.gradeBadgeLabel, level);

  @override
  Widget build(BuildContext context) {
    final Color gradeColor = getGradeColor(widget.character.grade);
    final String characterId = widget.character.gradeBadgeLabel;
    final Size screenSize = MediaQuery.of(context).size;

    return Dialog.fullscreen(
      backgroundColor: Colors.black87,
      child: SafeArea(
        child: Stack(
          children: [
            // 닫기 버튼 대신, 일러스트 바깥의 빈 배경을 탭하면 닫힌다 —
            // Stack의 가장 아래(뒤) 레이어라 위에 그려진 콘텐츠(카드 프레임
            // 안의 GestureDetector가 흡수)에 가려진 영역까지는 히트테스트가
            // 도달하지 않는다.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            Center(
              // 화면을 넘지 않는 한도(maxWidth/maxHeight) 안에서 세로형
              // 3:4 프레임 크기를 잡는다. 프레임 안의 이미지는 BoxFit.contain
              // 으로 원본 비율을 그대로 유지한 채 프레임 안에 전부 들어오도록
              // 맞춘다 — BoxFit.cover였다면 프레임 비율(3:4)과 실제 일러스트
              // 비율이 다를 때 그 차이만큼 잘려 나간다.
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: screenSize.width * 0.92,
                  maxHeight: screenSize.height * 0.8,
                ),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1B26),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: gradeColor, width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: _unlockedLevels.length,
                        itemBuilder: (context, index) {
                          final int level = _unlockedLevels[index];
                          return Padding(
                            padding: const EdgeInsets.all(12),
                            child: IllustrationViewer(
                              heroTag: _heroTag(level),
                              staticImagePath: AppImages.characterStarFallback(
                                characterId,
                                level,
                              ),
                              animatedImagePath: AppImages.characterStar(characterId, level),
                              fit: BoxFit.contain,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 해금된 성급이 2개 이상일 때만 "지금 몇 성을 보고 있는지" +
            // 스와이프 가능함을 알려주는 배지를 하단에 띄운다.
            if (_unlockedLevels.length > 1)
              Positioned(
                bottom: 28,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    // 배지도 콘텐츠로 취급해 탭해도 닫히지 않게 한다.
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: AnimatedBuilder(
                      animation: _pageController,
                      builder: (context, _) {
                        final double page =
                            _pageController.hasClients && _pageController.page != null
                                ? _pageController.page!
                                : _pageController.initialPage.toDouble();
                        final int index = page.round().clamp(0, _unlockedLevels.length - 1);
                        final int level = _unlockedLevels[index];
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '★$level',
                            style: const TextStyle(
                              color: Colors.amberAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

