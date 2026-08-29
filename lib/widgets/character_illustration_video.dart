import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../managers/storage_manager.dart';
import 'safe_image.dart';

/// R2에 올라간 mp4 한 편([videoPath], 예: 성급/호감도별 6초짜리 연출
/// 영상 — [AppImages.characterStarVideo])을 [StorageManager]가 발급한
/// 프리사인드 URL로 스트리밍 재생하는 위젯 — 무음(muted) + 로드 완료
/// 즉시 자동 재생(autoplay)으로 고정돼 있다. [loop]가 true(기본값)면
/// 배경 연출용으로 무한 반복하고, false면 한 번만 재생한 뒤
/// [onCompleted]를 호출한다 — 호출부(예: 캐릭터 일러스트 감상창)가 그
/// 신호를 받아 정지 이미지로 되돌리는 등 재생 종료 후 동작을 정할 수
/// 있다. 재생/정지 버튼 같은 컨트롤 자체는 이 위젯에 없다 — "재생 중이냐
/// 아니냐"는 호출부가 이 위젯을 화면에 넣고 빼는 것으로 결정한다.
///
/// [주의: 로딩/실패 시 항상 정지 이미지를 보여준다] URL 발급이 끝나기
/// 전(로딩 중)이거나, 발급/디코딩/재생 중 어느 단계에서든 실패하면
/// (네트워크 오류, 아직 그 영상이 R2에 없음 등) [thumbnailFallbackPath]
/// 정지 이미지로 조용히 대체된다 — 화면이 비어 있거나 찌그러진 채로
/// 남지 않는다. 이 위젯은 절대 예외를 밖으로 던지지 않는다.
class CharacterIllustrationVideo extends StatefulWidget {
  const CharacterIllustrationVideo({
    super.key,
    required this.videoPath,
    required this.thumbnailFallbackPath,
    this.fit = BoxFit.cover,
    this.loop = true,
    this.onCompleted,
  });

  /// R2 objectKey(mp4) — [StorageManager.imageUrl]로 프리사인드 URL을
  /// 발급받는다("image"라는 이름과 달리 임의의 objectKey에 다 쓸 수 있는
  /// 범용 발급 함수다).
  final String videoPath;

  /// 로딩 중이거나 실패했을 때 대신 보여줄 정지 이미지의 objectKey
  /// ([CustomSafeImage]로 렌더링).
  final String thumbnailFallbackPath;

  final BoxFit fit;

  /// true(기본값)면 무한 반복 재생한다. false면 한 번만 재생하고 끝나는
  /// 순간 [onCompleted]가 정확히 한 번 호출된다 — [loop]가 true일 때는
  /// "끝"이라는 개념이 없으므로 [onCompleted]가 절대 호출되지 않는다.
  final bool loop;

  /// [loop]가 false일 때만 의미가 있다 — 재생이 끝(영상 길이까지 도달)에
  /// 도달한 순간 호출된다.
  final VoidCallback? onCompleted;

  @override
  State<CharacterIllustrationVideo> createState() => _CharacterIllustrationVideoState();
}

class _CharacterIllustrationVideoState extends State<CharacterIllustrationVideo> {
  VideoPlayerController? _controller;
  bool _isReady = false;

  /// [_onPositionChanged]가 같은 재생 1회당 [widget.onCompleted]를 정확히
  /// 한 번만 부르도록 막는 가드 — [VideoPlayerController]의 리스너는 영상
  /// 길이 부근 여러 프레임에 걸쳐 계속 불릴 수 있어서, 가드 없이는 완료
  /// 콜백이 여러 번 호출될 수 있다.
  bool _hasNotifiedCompletion = false;

  @override
  void initState() {
    super.initState();
    _load(widget.videoPath);
  }

  @override
  void didUpdateWidget(covariant CharacterIllustrationVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 다른 영상(다른 성급 페이지로 스와이프 등)으로 바뀌면 기존 컨트롤러를
    // 즉시 버리고 새로 로드한다 — 그대로 두면 화면에 안 보이는 이전 영상이
    // 계속 재생/버퍼링되며 리소스를 낭비한다.
    if (oldWidget.videoPath != widget.videoPath) {
      _disposeController();
      _hasNotifiedCompletion = false;
      setState(() => _isReady = false);
      _load(widget.videoPath);
    }
  }

  Future<void> _load(String videoPath) async {
    final String? url = await StorageManager.instance.imageUrl(videoPath);
    if (!mounted || videoPath != widget.videoPath) {
      // 위젯이 이미 사라졌거나(dispose) 그 사이 다른 영상으로 또 바뀌었으면
      // ([didUpdateWidget]이 다시 호출해 새 로드를 이미 시작한 뒤이므로)
      // 이 낡은 응답은 반영하지 않는다.
      return;
    }
    if (url == null) {
      debugPrint('[CharacterIllustrationVideo] URL 발급 실패($videoPath) — 썸네일로 대체합니다.');
      return;
    }

    final VideoPlayerController controller = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await controller.initialize();
      if (!mounted || videoPath != widget.videoPath) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(widget.loop);
      await controller.setVolume(0.0);
      await controller.play();
      if (!widget.loop) {
        controller.addListener(_onPositionChanged);
      }
      _controller = controller;
      setState(() => _isReady = true);
    } catch (error) {
      debugPrint('[CharacterIllustrationVideo] 영상 로드 실패($videoPath): $error — 썸네일로 대체합니다.');
      await controller.dispose();
    }
  }

  /// [widget.loop]가 false일 때만 등록되는 리스너 — 재생 위치가 영상
  /// 길이에 도달하면(재생 종료) [widget.onCompleted]를 한 번 호출한다.
  void _onPositionChanged() {
    if (_hasNotifiedCompletion) {
      return;
    }
    final VideoPlayerController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final Duration duration = controller.value.duration;
    if (duration <= Duration.zero) {
      return;
    }
    if (controller.value.position >= duration) {
      _hasNotifiedCompletion = true;
      widget.onCompleted?.call();
    }
  }

  void _disposeController() {
    final VideoPlayerController? controller = _controller;
    _controller = null;
    controller?.removeListener(_onPositionChanged);
    controller?.dispose();
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? controller = _controller;
    if (_isReady && controller != null && controller.value.isInitialized) {
      return ClipRect(
        child: FittedBox(
          fit: widget.fit,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
      );
    }
    return CustomSafeImage(
      path: widget.thumbnailFallbackPath,
      fit: widget.fit,
      filterQuality: FilterQuality.none,
    );
  }
}
