import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_images.dart';
import 'safe_image.dart';

/// 캐릭터 탭 중앙 카드에서 장착 캐릭터를 대기(wait) 모션으로 부드럽게
/// 반복 재생하는 위젯 — [CharacterFacePortrait]의 정적 정면 이미지 대신,
/// `player_{id}_wait1~5.png` 5프레임을 stepTime 0.15초 간격으로 순환한다
/// ([PlayerAnimationComponent]의 인게임 대기 모션과 동일한 프레임/속도).
/// 아직 대기 프레임이 없는(404) 캐릭터는 [CustomSafeImage]가 알아서
/// placeholder로 대체하므로 호출부에서 존재 여부를 따로 확인할 필요가 없다.
class CharacterIdlePreview extends StatefulWidget {
  const CharacterIdlePreview({
    super.key,
    required this.characterId,
    this.size,
    this.borderRadius = 0,
  });

  final String characterId;

  /// null이면 부모가 준 제약에 맞춰 채워지고, 값을 주면 그 크기의
  /// 정사각형으로 스스로를 감싼다([CharacterFacePortrait]과 동일한 관례).
  final double? size;
  final double borderRadius;

  @override
  State<CharacterIdlePreview> createState() => _CharacterIdlePreviewState();
}

class _CharacterIdlePreviewState extends State<CharacterIdlePreview> {
  static const int _frameCount = 5;
  static const Duration _stepTime = Duration(milliseconds: 150);

  int _frameIndex = 1;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_stepTime, (_) {
      setState(() => _frameIndex = _frameIndex % _frameCount + 1);
    });
  }

  @override
  void didUpdateWidget(covariant CharacterIdlePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.characterId != widget.characterId) {
      _frameIndex = 1;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String path =
        AppImages.playerActionFrame(widget.characterId, 'wait', _frameIndex);

    final Widget clipped = ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: CustomSafeImage(
        path: path,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.none,
      ),
    );

    final double? boxSize = widget.size;
    if (boxSize == null) {
      return clipped;
    }
    return SizedBox(width: boxSize, height: boxSize, child: clipped);
  }
}
