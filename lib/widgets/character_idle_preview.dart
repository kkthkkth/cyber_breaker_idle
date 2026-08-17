import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_images.dart';
import '../game/idle_game.dart';
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

  /// 512x512 캔버스 안에서 캐릭터가 차지하는 세로 비율(약 58.6%, 발밑은
  /// 캔버스 최하단에 붙어 있음 — [PlayerAnimationComponent.contentHeightRatio]
  /// 실측 참고)의 역수. 정사각형 이미지를 정사각형 상자에 [BoxFit.cover]로
  /// 맞추기만 하면 크롭이 전혀 일어나지 않아(둘 다 1:1 비율) 캔버스 전체,
  /// 즉 위쪽 여백까지 고스란히 다 보여서 캐릭터가 상자 안에서 작게
  /// 보인다. 이 배율만큼 이미지를 확대한 뒤 발밑(하단) 기준으로 잘라내면
  /// 위쪽 여백이 상자 밖으로 밀려나 잘리고, 캐릭터 알맹이가 상자를 꽉
  /// 채운다.
  static const double _zoom = 1 / PlayerAnimationComponent.contentHeightRatio;

  @override
  Widget build(BuildContext context) {
    final String path =
        AppImages.playerActionFrame(widget.characterId, 'wait', _frameIndex);

    // SizedBox.expand로 먼저 상자를 꽉 채운 뒤(Align은 자식에게 loose
    // constraints를 넘겨서 이미지가 상자보다 작게 레이아웃될 수 있으므로
    // 쓰지 않는다), Transform.scale(레이아웃 크기는 그대로 두고 그리기만
    // 확대)로 발밑(bottomCenter, 캔버스 최하단 = 여백 0%)을 축으로
    // 확대한다 — 발 위치는 그대로 고정된 채 위쪽 여백만 상자 밖으로
    // 밀려나 ClipRect에 잘려나간다.
    final Widget zoomed = ClipRect(
      child: Transform.scale(
        scale: _zoom,
        alignment: Alignment.bottomCenter,
        child: SizedBox.expand(
          child: CustomSafeImage(
            path: path,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.none,
          ),
        ),
      ),
    );

    final Widget clipped = ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: zoomed,
    );

    final double? boxSize = widget.size;
    if (boxSize == null) {
      return clipped;
    }
    return SizedBox(width: boxSize, height: boxSize, child: clipped);
  }
}
