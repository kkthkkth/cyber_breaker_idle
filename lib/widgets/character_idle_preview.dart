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

  @override
  Widget build(BuildContext context) {
    // 우선 시도: 애니메이션 webp 한 장(자체 반복 재생, [_timer]가 필요
    // 없다). 실패하면(404 등) [CustomSafeImage.fallbackPath]가 예전 방식인
    // 번호 매김 PNG 프레임([_frameIndex], 이 위젯의 [_timer]가 150ms마다
    // 순환)으로 자동 전환한다.
    final String path = AppImages.playerActionAnimation(widget.characterId, 'wait');
    final String fallbackPath =
        AppImages.playerActionFrame(widget.characterId, 'wait', _frameIndex);

    // 예전엔 FittedBox(contain)로 전체를 담은 뒤 다시 Transform.scale로
    // 확대(발밑 기준)해 이펙트 여백을 잘라내는 2단계 방식을 썼는데, 그
    // 배율이 "콘텐츠가 캔버스의 정확히 50%를 차지한다"는 가정에 기반해서
    // 캐릭터마다 실제 여백 비율이 조금만 달라도 정수리가 다시 잘려 보이는
    // 문제가 있었다(요구사항: "무조건 박스 안에 다 들어가도록"). 지금은
    // FittedBox(BoxFit.contain, Alignment.bottomCenter) 한 단계만 쓴다 —
    // 원본 800x720 캔버스 전체를 잘라내지 않고 레터박스(여백)로만 맞추므로,
    // 어떤 크기의 상자에 넣어도 캐릭터 전체가 수학적으로 항상 다 보인다.
    // 대신 이펙트 여백만큼 캐릭터가 상자를 꽉 채우지 않고 살짝 작게 보일
    // 수 있다 — 잘림 없음을 더 우선한 트레이드오프다.
    final Widget contained = FittedBox(
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
    );

    final Widget clipped = ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: contained,
    );

    final double? boxSize = widget.size;
    if (boxSize == null) {
      return clipped;
    }
    return SizedBox(width: boxSize, height: boxSize, child: clipped);
  }
}
