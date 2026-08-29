import 'package:flame/components.dart' show Anchor;
import 'package:flame/sprite.dart' show SpriteAnimation, SpriteAnimationTicker;
import 'package:flame/widgets.dart' show SpriteAnimationWidget;
import 'package:flutter/material.dart';

import '../constants/app_images.dart';
import '../game/character_animation_spec.dart';
import '../game/remote_sprite_loader.dart';
import '../managers/character_animation_manager.dart';
import 'safe_image.dart';

/// 캐릭터 탭 중앙 카드에서 장착 캐릭터를 대기(wait) 모션으로 부드럽게
/// 반복 재생하는 위젯 — [CharacterFacePortrait]의 정적 정면 이미지 대신
/// 움직이는 모션을 보여준다.
///
/// [PlayerAnimationComponent]가 전투 화면에서 쓰는 것과 완전히 같은
/// 로딩 우선순위를 그대로 재사용한다 — DB 스프라이트 시트
/// ([CharacterAnimationManager.fetchSpec] → [RemoteSpriteLoader
/// .loadSpriteAnimation]) → 통짜 애니메이션 webp
/// ([RemoteSpriteLoader.loadAnimatedWebP]) → 단일 정지 이미지
/// ([AppImages.playerFront]). 어느 단계든 실패하면 조용히 다음 단계로
/// 넘어가고, 전부 실패해도(오프라인 등) 예외를 던지지 않고 정지
/// 이미지/placeholder로 대체된다.
///
/// [주의: Flame GameWidget 없이 순수 Flutter 위젯으로 재생한다] Flame이
/// 제공하는 [SpriteAnimationWidget](이미 로드된 [SpriteAnimation] 하나를
/// [GameWidget]/[FlameGame] 없이 그려 주는 헬퍼)을 쓴다 — 이 카드 하나
/// 때문에 별도 미니 게임 루프를 띄울 필요가 없다.
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
  SpriteAnimation? _animation;
  SpriteAnimationTicker? _ticker;

  /// [_animation]/[_ticker]가 실제로 어떤 characterId의 결과인지 —
  /// [_load]가 끝나기 전에 다른 캐릭터로 바뀌면([didUpdateWidget]) 그
  /// 낡은 응답을 무시하기 위한 가드로도, build()가 지금 [widget
  /// .characterId]와 다른 캐릭터의 애니메이션을 잘못 그리지 않게 하는
  /// 이중 방어로도 쓰인다.
  String? _loadedForCharacterId;

  @override
  void initState() {
    super.initState();
    _load(widget.characterId);
  }

  @override
  void didUpdateWidget(covariant CharacterIdlePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.characterId != widget.characterId) {
      setState(() {
        _animation = null;
        _ticker = null;
      });
      _load(widget.characterId);
    }
  }

  Future<void> _load(String characterId) async {
    SpriteAnimation? animation;
    try {
      final SpriteSheetSpec? sheetSpec =
          (await CharacterAnimationManager.instance.fetchSpec(characterId))['wait'];
      if (sheetSpec != null) {
        animation = await RemoteSpriteLoader.loadSpriteAnimation(
          sheetSpec.sheetPath,
          amount: sheetSpec.amount,
          textureSize: sheetSpec.textureSize,
          stepTime: sheetSpec.stepTime,
        );
      }
    } catch (error) {
      debugPrint('[CharacterIdlePreview] $characterId 시트 로드 실패: $error — webp 폴백으로 넘어갑니다.');
    }

    if (animation == null) {
      try {
        animation = await RemoteSpriteLoader.loadAnimatedWebP(
          AppImages.playerActionAnimation(characterId, 'wait'),
        );
      } catch (_) {
        // webp도 없다(404 등) — 아래에서 정지 이미지로 대체된다.
      }
    }

    if (!mounted || characterId != widget.characterId) {
      // 위젯이 이미 사라졌거나 그 사이 다른 캐릭터로 바뀌었으면([didUpdateWidget]
      // 이 다시 호출해 새 로드를 이미 시작한 뒤이므로) 이 낡은 응답은
      // 반영하지 않는다.
      return;
    }
    setState(() {
      _animation = animation;
      _ticker = animation?.createTicker();
      _loadedForCharacterId = characterId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final double? boxSize = widget.size;
    final SpriteAnimation? animation = _animation;
    final SpriteAnimationTicker? ticker = _ticker;

    final Widget content =
        (animation != null && ticker != null && _loadedForCharacterId == widget.characterId)
        ? SpriteAnimationWidget(
            animation: animation,
            animationTicker: ticker,
            // PlayerAnimationComponent와 동일하게 발밑(캔버스 하단 중앙)을
            // 기준으로 정렬한다 — SpritePainter가 상자 안에 원본 비율
            // 그대로(contain) 맞추고, 이 anchor로 "박스 하단 중앙 =
            // 스프라이트 하단 중앙"이 되도록 배치해 준다(Flame
            // Anchor.bottomCenter를 그대로 재사용).
            anchor: Anchor.bottomCenter,
            size: boxSize != null ? Size.square(boxSize) : null,
            paint: RemoteSpriteLoader.pixelArtPaint(),
          )
        : CustomSafeImage(
            path: AppImages.playerFront(widget.characterId),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.none,
          );

    final Widget clipped = ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: content,
    );

    if (boxSize == null) {
      return clipped;
    }
    return SizedBox(width: boxSize, height: boxSize, child: clipped);
  }
}
