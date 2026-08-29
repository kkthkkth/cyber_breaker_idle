import 'package:flutter/material.dart';

import 'character_illustration_video.dart';
import 'safe_image.dart';

/// 재생/정지 토글 + 더블 탭 전체화면([Hero] + [InteractiveViewer])이
/// 포함된 공용 캐릭터 일러스트 뷰어 — 호감도 화면과 캐릭터 일러스트 팝업
/// (CharacterIllustrationDialog)이 함께 쓴다.
///
/// 항상 정지 이미지([staticImagePath], .png)로 시작한다. 좌측 상단의
/// 반투명(Opacity 0.5) 버튼을 누르면 [videoPath](.mp4)가 무음으로 한 번
/// 재생되고, 끝나거나 같은 버튼을 다시 누르면 정지 이미지로 돌아간다
/// ([CharacterIllustrationDialog]의 `_StarIllustrationPage`와 동일한
/// 관례 — 예전엔 여기서 .webp 애니메이션으로 토글했지만, 실제 R2에는
/// .webp가 아니라 .mp4만 올라가 있어 영상 재생으로 대체했다). 이 재생
/// 상태는 이 위젯 안에서만 관리되고 부모에게 노출되지 않는다 — 호출부의
/// 다른 상태(예: 오늘 남은 대화 횟수)와 절대 섞일 수 없는 구조다.
///
/// 이미지를 더블 탭하면 [FullScreenIllustrationViewer]로 순수 정지
/// 이미지만 꽉 채운 진짜 전체화면 라우트가 열린다 — 재생 버튼이나
/// [overlay]로 얹은 다른 버튼은 그 라우트에는 전혀 그려지지 않는다(완전히
/// 분리된 별도 위젯이라 실수로 섞일 수 없다). [주의] 영상 재생 중에
/// 더블 탭해도 전체화면은 항상 정지 이미지를 보여준다 — 재생 중인
/// [VideoPlayerController]를 라우트 전환 중에도 안전하게 들고 다니는
/// 문제가 있어, 전체화면은 정지 이미지 전용으로 단순하게 유지했다.
class IllustrationViewer extends StatefulWidget {
  const IllustrationViewer({
    super.key,
    required this.heroTag,
    required this.staticImagePath,
    required this.videoPath,
    this.staticFallbackImagePath,
    this.fit = BoxFit.cover,
    this.overlays = const [],
  });

  /// 이 뷰어의 페이지(카드)와, 더블 탭으로 열리는 전체화면이 공유하는
  /// [Hero] 태그.
  final Object heroTag;

  final String staticImagePath;

  /// 재생 버튼을 눌렀을 때 재생할 6초짜리 연출 영상(.mp4) R2 objectKey —
  /// [CharacterIllustrationVideo]가 [StorageManager]로 프리사인드 URL을
  /// 발급받아 재생한다.
  final String videoPath;

  /// [staticImagePath] 로드가 실패했을 때 대신 시도할 경로 — 기본(null)은
  /// "정지 이미지는 이미 원본이라 fallback이 필요 없다"는 대부분의 경우에
  /// 맞다. 아직 준비 안 된 특수 스킨처럼 별도 아트를 우선 시도하고, 없으면
  /// 평소 그림으로 조용히 되돌아가야 하는 경우에 쓴다.
  final String? staticFallbackImagePath;

  final BoxFit fit;

  /// 재생 버튼 외에 추가로 얹고 싶은 버튼들(예: 호감도 화면의 '대화'
  /// 버튼과 '서약하기' 버튼) — 각각 보통 [Positioned]로 감싸서 넘긴다.
  /// 이미지의 더블 탭 감지 영역 위에 나중에(=위에) 그려지므로 이
  /// 오버레이들의 탭은 항상 우선 히트테스트된다.
  final List<Widget> overlays;

  @override
  State<IllustrationViewer> createState() => _IllustrationViewerState();
}

class _IllustrationViewerState extends State<IllustrationViewer> {
  /// 이 위젯 밖에서는 절대 읽거나 바꿀 수 없다 — 재생 버튼의 onPressed는
  /// 오직 이 필드 하나만 뒤집는다.
  bool _isPlaying = false;

  /// 전체화면 진입 처리 중 잠금 — 더블 탭을 다시 아주 빠르게 반복하면
  /// [Navigator.push]가 여러 번 겹쳐 호출돼 같은 전체화면 라우트가 여러
  /// 장 쌓일 수 있다. 라우트가 pop되어 돌아올 때까지 추가 진입을 막는다.
  bool _isOpeningFullScreen = false;

  @override
  void didUpdateWidget(covariant IllustrationViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 다른 그림(다른 heroTag)으로 바뀌면 재생 상태를 들고 가지 않는다 —
    // 매번 새로 재생 버튼을 눌러야 그 그림의 영상을 재생한다. 같은 그림이
    // 리빌드된 것뿐이면 재생 상태를 그대로 둔다.
    if (oldWidget.heroTag != widget.heroTag && _isPlaying) {
      _isPlaying = false;
    }
  }

  void _togglePlay() {
    // 오직 재생 상태만 바꾼다 — 그 외 어떤 상태(대화 횟수 등)도 여기서
    // 건드리지 않는다.
    setState(() => _isPlaying = !_isPlaying);
  }

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
                FullScreenIllustrationViewer(
                  imagePath: widget.staticImagePath,
                  fallbackImagePath: widget.staticFallbackImagePath,
                  heroTag: widget.heroTag,
                ),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        )
        .then((_) {
          // 전체화면에서 다시 pop으로 돌아왔을 때만 잠금을 푼다 — 그 전까지
          // 더블 탭을 반복해도 두 번째 이후 호출은 위에서 즉시 무시된다.
          if (mounted) {
            _isOpeningFullScreen = false;
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          // 배경을 탭하면 닫히는 화면(예: CharacterIllustrationDialog)
          // 안에서 쓰일 때, 일러스트 위의 단순 탭이 배경 탭-닫기로 새지
          // 않도록 여기서 흡수한다. 진짜 확대는 더블 탭으로만 연다.
          onTap: () {},
          onDoubleTap: _openFullScreen,
          child: _isPlaying
              ? CharacterIllustrationVideo(
                  videoPath: widget.videoPath,
                  thumbnailFallbackPath: widget.staticImagePath,
                  fit: widget.fit,
                  loop: false,
                  onCompleted: _onVideoCompleted,
                )
              : Hero(
                  tag: widget.heroTag,
                  child: CustomSafeImage(
                    path: widget.staticImagePath,
                    fallbackPath: widget.staticFallbackImagePath,
                    fit: widget.fit,
                    filterQuality: FilterQuality.none,
                  ),
                ),
        ),
        Positioned(
          left: 10,
          top: 10,
          child: Opacity(
            opacity: 0.5,
            child: _PlayPauseButton(isPlaying: _isPlaying, onTap: _togglePlay),
          ),
        ),
        ...widget.overlays,
      ],
    );
  }
}

/// 좌측 상단의 재생/일시정지 토글 아이콘 버튼.
class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.isPlaying, required this.onTap});

  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isPlaying ? '애니메이션 일시정지' : '애니메이션 재생',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
          child: Icon(
            isPlaying ? Icons.pause : Icons.play_arrow,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}

/// 더블 탭으로 진입하는 진짜 전체화면 뷰어 — [InteractiveViewer]로 자유롭게
/// 확대/축소하고, 다시 더블 탭하면 [Navigator.pop]으로 돌아간다. **오직
/// 이미지 하나만** 그린다 — 재생 버튼이나 그 외 오버레이는 절대 그리지
/// 않는다(호출부인 [IllustrationViewer]와 완전히 분리된 별도 위젯).
class FullScreenIllustrationViewer extends StatelessWidget {
  const FullScreenIllustrationViewer({
    super.key,
    required this.imagePath,
    required this.fallbackImagePath,
    required this.heroTag,
  });

  final String imagePath;
  final String? fallbackImagePath;
  final Object heroTag;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: () => Navigator.of(context).pop(),
          child: Center(
            child: InteractiveViewer(
              // 카드와 통일해 기본은 BoxFit.cover로 꽉 채우지만, 그러면
              // 원본의 잘려나간 가장자리는 1.0 이상으로 확대해도 영원히
              // 볼 수 없다 — minScale을 1 미만으로 낮춰서 필요하면 직접
              // 축소(pinch-out)해 원본 전체를 다시 볼 수 있게 한다.
              minScale: 0.5,
              maxScale: 5.0,
              child: Hero(
                tag: heroTag,
                child: CustomSafeImage(
                  path: imagePath,
                  fallbackPath: fallbackImagePath,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.none,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
