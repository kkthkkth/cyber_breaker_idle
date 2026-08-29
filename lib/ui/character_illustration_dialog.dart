import 'package:flutter/material.dart';

import '../constants/app_images.dart';
import '../models/equipment.dart';
import '../widgets/character_illustration_video.dart';
import '../widgets/safe_image.dart';

/// 장착된 캐릭터의 성급(★0~5) 일러스트 뷰어 팝업 — 프로필 아이콘에서
/// 열든(main.dart) 상세 팝업의 갤러리 슬롯을 탭해서 열든([initialLevel]
/// 지정) 전부 이 위젯 하나를 공유한다. [initialLevel]을 안 주면(=프로필
/// 아이콘처럼 특정 슬롯에서 연 게 아니면) 해금된 성급 중 가장 높은 것부터
/// 보여준다. 해금된 성급들 사이는 [PageView]로 좌우 스와이프해서 넘겨볼 수
/// 있다 — 잠긴 성급은 애초에 페이지 목록에 넣지 않는다(스포일러 방지).
///
/// 각 페이지([_StarIllustrationPage])는 처음엔 항상 정지 이미지
/// (`heart{level}.png`, [AppImages.characterStarFallback])만 보여주고,
/// 좌측 상단의 반투명 재생 버튼을 눌러야만 6초짜리 연출 영상(mp4,
/// [AppImages.characterStarVideo])이 무음으로 한 번 재생된다 — 재생이
/// 끝나거나 같은 버튼을 다시 누르면 정지 이미지로 돌아온다. 정지 이미지든
/// 영상 재생 중이든, 더블 탭하면 [InteractiveViewer]로 자유롭게 확대/
/// 축소할 수 있는 전체화면으로 열린다([_FullScreenStarIllustration] 참고).
class CharacterIllustrationDialog extends StatefulWidget {
  const CharacterIllustrationDialog({super.key, required this.character, this.initialLevel});

  final Equipment character;

  /// 특정 성급부터 보여주고 싶을 때(예: 갤러리에서 ★2를 탭함) 지정한다.
  /// null이면 해금된 것 중 가장 높은 성급부터 시작한다.
  final int? initialLevel;

  /// 상세 팝업 하단의 작은 썸네일(item_detail_dialog.dart의
  /// `_StarIllustrationSlot`)이 여전히 이 문자열로 [Hero] 태그를 걸어
  /// 두지만, 이 카드 팝업 쪽에는 짝이 되는 Hero가 없어 실제로 전환
  /// 애니메이션이 이어지진 않는다 — 영상 컨트롤러를 Hero 전환 중에도
  /// 안전하게 들고 다니는 문제가 남아 있어 범위에서 제외했다. 나중에
  /// 다시 붙일 걸 대비해 태그 규칙만 유지한다.
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
              // 3:4 프레임 크기를 잡는다. 프레임 안의 이미지/영상은
              // BoxFit.cover로 카드를 여백 없이 꽉 채운다 — 원본 비율이
              // 3:4와 달라도 그 차이만큼 잘려 나갈 뿐, 카드 좌우(또는
              // 상하)에 검은 여백이 남지 않는다(예전엔 BoxFit.contain을
              // 써서 원본을 전부 보존했지만, 그 결과 원본 비율이 3:4와
              // 다른 일러스트마다 레터박스 여백이 생겨 재생 버튼 등
              // 오버레이가 사진 바깥 여백에 떠 보이는 문제가 있었다).
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
                          return _StarIllustrationPage(characterId: characterId, level: level);
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

/// 성급 감상창 페이지 하나 — 기본은 정지 이미지(`heart{level}.png`)만
/// 보여주고, 좌측 상단 재생 버튼을 눌러야 6초짜리 연출 영상을 재생한다.
/// 영상은 한 번만 재생하고([CharacterIllustrationVideo.loop] false) 끝나면
/// 자동으로 정지 이미지로 돌아오고, 재생 중에 같은 버튼을 다시 눌러도
/// 즉시 정지 이미지로 돌아온다. 사진/영상을 더블 탭하면 지금 보고 있는
/// 상태 그대로(정지 이미지든 재생 중이든) [_FullScreenStarIllustration]
/// 전체화면으로 열린다.
///
/// [주의: 사진/영상은 이 위젯(=카드 프레임) 전체를 여백 없이 꽉 채운다]
/// 예전엔 사진 쪽에 `Padding(all: 12)`를 둬서 살짝 안쪽으로 띄웠는데,
/// 카드를 최대한 꽉 채워 보여 달라는 요구로 그 패딩을 제거했다 — 사진/
/// 영상이 이 [Stack] 전체(`fit: StackFit.expand`)를 그대로 채운다. 재생
/// 버튼은 `Positioned(top: 12, left: 12)`로 사진 좌측 상단 안쪽에 직접
/// 얹힌다.
class _StarIllustrationPage extends StatefulWidget {
  const _StarIllustrationPage({required this.characterId, required this.level});

  final String characterId;
  final int level;

  @override
  State<_StarIllustrationPage> createState() => _StarIllustrationPageState();
}

class _StarIllustrationPageState extends State<_StarIllustrationPage> {
  bool _isPlaying = false;

  /// 더블 탭을 아주 빠르게 반복해도 전체화면 라우트가 여러 장 쌓이지
  /// 않도록 막는 잠금([IllustrationViewer._isOpeningFullScreen]과 동일한
  /// 관례).
  bool _isOpeningFullScreen = false;

  @override
  void didUpdateWidget(covariant _StarIllustrationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 다른 성급 페이지로 바뀌면(좌우 스와이프 등) 재생 상태를 들고 가지
    // 않는다 — 항상 정지 이미지로 새로 시작해야 매번 다시 재생 버튼을
    // 눌러야 하는 의도(연출 영상을 유저가 직접 트리거)가 유지된다.
    if (oldWidget.level != widget.level && _isPlaying) {
      _isPlaying = false;
    }
  }

  void _togglePlay() => setState(() => _isPlaying = !_isPlaying);

  void _onVideoCompleted() {
    if (mounted) {
      setState(() => _isPlaying = false);
    }
  }

  void _openFullScreen() {
    if (_isOpeningFullScreen) {
      return;
    }
    _isOpeningFullScreen = true;

    Navigator.of(context)
        .push(
          PageRouteBuilder<void>(
            opaque: false,
            barrierColor: Colors.black,
            transitionDuration: const Duration(milliseconds: 280),
            reverseTransitionDuration: const Duration(milliseconds: 220),
            pageBuilder: (context, animation, secondaryAnimation) =>
                _FullScreenStarIllustration(
                  characterId: widget.characterId,
                  level: widget.level,
                  isPlaying: _isPlaying,
                ),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        )
        .then((_) {
          if (mounted) {
            _isOpeningFullScreen = false;
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    final String imagePath = AppImages.characterStarFallback(widget.characterId, widget.level);

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          // 배경(카드 바깥)을 탭하면 닫히는 다이얼로그 안에서 쓰이므로,
          // 사진/영상 위의 단순 탭이 배경 탭-닫기로 새지 않도록 여기서
          // 흡수한다. 확대는 더블 탭으로만 연다.
          onTap: () {},
          onDoubleTap: _openFullScreen,
          child: _isPlaying
              ? CharacterIllustrationVideo(
                  videoPath: AppImages.characterStarVideo(widget.characterId, widget.level),
                  thumbnailFallbackPath: imagePath,
                  fit: BoxFit.cover,
                  loop: false,
                  onCompleted: _onVideoCompleted,
                )
              : CustomSafeImage(
                  path: imagePath,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.none,
                ),
        ),
        Positioned(
          top: 12,
          left: 12,
          child: Opacity(
            opacity: 0.5,
            child: _PlayToggleButton(isPlaying: _isPlaying, onTap: _togglePlay),
          ),
        ),
      ],
    );
  }
}

/// 더블 탭으로 진입하는 진짜 전체화면 뷰어 — [InteractiveViewer]로 자유롭게
/// 확대/축소하고, 다시 더블 탭하면 [Navigator.pop]으로 돌아간다.
/// [isPlaying]이 true면(카드에서 영상 재생 중에 더블 탭한 경우) 영상을
/// 무한 반복으로 확대해서 계속 보여주고, false면 정지 이미지를 그대로
/// 확대해서 보여준다.
///
/// [주의: 카드의 재생 컨트롤러를 그대로 물려받지 않는다] 카드 쪽
/// [CharacterIllustrationVideo]와 이 라우트의 것은 서로 다른
/// [VideoPlayerController] 인스턴스다(전체화면 진입 시 영상이 처음부터
/// 다시 재생된다) — 살아있는 컨트롤러를 라우트 전환 중에 안전하게 넘기는
/// 것보다, 새로 하나 더 열어 독립적으로 재생하는 쪽이 훨씬 단순하고
/// 안전하다. 6초짜리 짧은 무음 영상이라 다시 처음부터 재생돼도 체감
/// 차이가 거의 없다.
class _FullScreenStarIllustration extends StatelessWidget {
  const _FullScreenStarIllustration({
    required this.characterId,
    required this.level,
    required this.isPlaying,
  });

  final String characterId;
  final int level;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final String imagePath = AppImages.characterStarFallback(characterId, level);

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: () => Navigator.of(context).pop(),
          child: Center(
            child: InteractiveViewer(
              // 카드와 통일해 기본은 BoxFit.cover로 꽉 채우지만, 그러면
              // 원본의 잘려나간 가장자리는 1.0 이상으로 확대(zoom in)해도
              // 영원히 볼 수 없다 — minScale을 1 미만으로 낮춰서 사용자가
              // 필요하면 직접 축소(pinch-out)해 원본 전체를 다시 볼 수
              // 있는 여지를 남겨 둔다.
              minScale: 0.5,
              maxScale: 5.0,
              child: isPlaying
                  ? CharacterIllustrationVideo(
                      videoPath: AppImages.characterStarVideo(characterId, level),
                      thumbnailFallbackPath: imagePath,
                      fit: BoxFit.cover,
                    )
                  : CustomSafeImage(
                      path: imagePath,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.none,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 좌측 상단의 재생/정지 토글 아이콘 버튼([IllustrationViewer]의
/// `_PlayPauseButton`과 같은 모양·크기를 재사용한다).
class _PlayToggleButton extends StatelessWidget {
  const _PlayToggleButton({required this.isPlaying, required this.onTap});

  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isPlaying ? '연출 영상 정지' : '연출 영상 재생',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
          child: Icon(
            isPlaying ? Icons.stop : Icons.play_arrow,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}
