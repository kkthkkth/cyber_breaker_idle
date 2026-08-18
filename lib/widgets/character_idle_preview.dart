import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_images.dart';
import '../game/idle_game.dart';
import 'safe_image.dart';

/// 캐릭터 탭 중앙 카드에서 장착 캐릭터를 대기(wait) 모션으로 부드럽게
/// 반복 재생하는 위젯 — [CharacterFacePortrait]의 정적 정면 이미지 대신
/// 움직이는 모션을 보여준다.
///
/// [AppImages.playerActionAnimation](`player_{id}_wait.webp`, 예:
/// N1은 `player_n1_wait.webp`)을 최우선으로 시도한다 — 애니메이션 파일
/// 하나가 자체적으로 프레임/타이밍을 담고 있어([PlayerAnimationComponent]
/// 의 인게임 대기 모션이 쓰는 것과 같은 파일), [Image]가 별도 타이머 없이
/// 알아서 반복 재생한다. 아직 그 캐릭터의 webp가 없는(404) 경우에만 예전
/// 방식(`player_{id}_wait1~5.png` 5프레임을 [_timer]로 stepTime 0.15초
/// 간격 순환)으로 조용히 대체된다 — [CustomSafeImage.fallbackPath]가 이
/// 전환을 처리하므로 호출부는 어느 쪽이 성공했는지 신경 쓸 필요가 없다.
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

  /// 캔버스 안에서 캐릭터 콘텐츠가 차지하는 비율(표준 규격 기준 가로/세로
  /// 모두 50% — [PlayerAnimationComponent.contentRatio] 참고)의 역수.
  /// [build]가 원본 캔버스(800x720) 전체를 잘림 없이 상자 안에 발밑 기준
  /// (bottomCenter)으로 맞춰 넣어 둔 다음, 이 배율만큼 다시 발밑을 축으로
  /// 확대하면 위쪽/좌우 이펙트 여백이 상자 밖으로 밀려나 잘리고 캐릭터
  /// 콘텐츠만(가로/세로 각각 정확히 상자를 꽉 채우며) 남는다 — 가로/세로
  /// 콘텐츠 비율이 똑같이 50%라 이 배율 하나로 양쪽 축 모두 정확히
  /// 들어맞는다.
  static const double _zoom = 1 / PlayerAnimationComponent.contentRatio;

  @override
  Widget build(BuildContext context) {
    // 우선 시도: 애니메이션 webp 한 장(자체 반복 재생, [_timer]가 필요
    // 없다). 실패하면(404 등) [CustomSafeImage.fallbackPath]가 예전 방식인
    // 번호 매김 PNG 프레임([_frameIndex], 이 위젯의 [_timer]가 150ms마다
    // 순환)으로 자동 전환한다.
    final String path = AppImages.playerActionAnimation(widget.characterId, 'wait');
    final String fallbackPath =
        AppImages.playerActionFrame(widget.characterId, 'wait', _frameIndex);

    // 원본 캔버스(800x720)는 정사각형이 아니다 — 예전처럼 BoxFit.cover로
    // 정사각형 상자에 곧바로 맞추면 그 단계에서 이미 좌우가 잘려 나가고,
    // 그 위에 다시 [_zoom]만큼 확대하면 캐릭터 콘텐츠 가장자리(어깨 등)
    // 까지 이중으로 잘려 나간다 — 정수리가 위쪽 테두리에 잘려 보이던
    // 버그의 원인이었다(실측 확인됨). FittedBox(BoxFit.contain +
    // Alignment.bottomCenter)로 원본 비율을 유지한 채 "잘림 없이" 발밑
    // 기준으로 상자에 맞춰 넣은 뒤에만 [_zoom] 확대를 적용해야 한다 —
    // contain은 잘라내지 않고 레터박스(여백)로만 맞추므로, 이 단계에서는
    // 캐릭터가 항상 통째로 보인다.
    final Widget zoomed = ClipRect(
      child: Transform.scale(
        scale: _zoom,
        alignment: Alignment.bottomCenter,
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: PlayerAnimationComponent.referenceCanvasWidth,
              height: PlayerAnimationComponent.referenceCanvasHeight,
              child: CustomSafeImage(
                path: path,
                fallbackPath: fallbackPath,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.none,
              ),
            ),
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
