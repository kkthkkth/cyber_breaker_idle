import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/painting.dart' show FilterQuality;
import 'package:http/http.dart' as http;

/// GitHub 등 원격 URL에서 Flame 컴포넌트가 쓸 [Sprite]/[SpriteAnimation]을
/// 내려받아 Flame의 이미지 캐시([Images])에 등록하는 로더 — Flutter UI 쪽의
/// [CustomSafeImage]/[CachedNetworkImage]와 짝을 이루는 Flame 전용 경로다
/// (Flame의 [Sprite]는 `dart:ui`의 [ui.Image]를 직접 들고 있어서
/// Flutter 위젯 트리의 이미지 캐시를 재사용할 수 없다).
///
/// 같은 URL을 여러 번 요청해도 [Images.containsKey]로 캐시 적중을 먼저
/// 확인하므로, 두 번째 호출부터는 네트워크 왕복 없이 즉시 반환된다.
///
/// 현재 이 프로젝트의 인게임 캐릭터(PlayerComponent)는 화면에 아무것도
/// 그리지 않는 좌표 기준점일 뿐이고 실제 스프라이트는 Flutter 오버레이
/// (CharacterFacePortrait 등)가 그린다 — 그래서 이 로더를 지금 당장 쓰는
/// 곳은 없지만, 앞으로 몬스터/이펙트 등 실제 Flame Sprite가 필요해지면
/// 바로 꺼내 쓸 수 있도록 미리 준비해 둔다.
class RemoteSpriteLoader {
  const RemoteSpriteLoader._();

  /// [url]의 이미지를 내려받아 Flame 이미지 캐시에 등록하고 [Sprite]로
  /// 반환한다. 픽셀 아트가 확대돼도 뭉개지지 않도록 paint의 필터링을 끈
  /// 상태로 돌려준다.
  static Future<Sprite> loadSprite(String url, {Images? imageCache}) async {
    final ui.Image image = await _loadImage(url, imageCache ?? Flame.images);
    final Sprite sprite = Sprite(image);
    _disableFiltering(sprite.paint);
    return sprite;
  }

  /// 가로로 [frameCount]장이 이어진 스프라이트 시트 한 장을 내려받아
  /// [SpriteAnimation]으로 잘라준다. 모든 프레임에 동일하게 필터링을 끈다.
  static Future<SpriteAnimation> loadSpriteAnimation(
    String url, {
    required int frameCount,
    required double stepTime,
    bool loop = true,
    Images? imageCache,
  }) async {
    final ui.Image image = await _loadImage(url, imageCache ?? Flame.images);
    final double frameWidth = image.width / frameCount;

    final SpriteAnimation animation = SpriteAnimation.fromFrameData(
      image,
      SpriteAnimationData.sequenced(
        amount: frameCount,
        stepTime: stepTime,
        textureSize: Vector2(frameWidth, image.height.toDouble()),
        loop: loop,
      ),
    );
    for (final SpriteAnimationFrame frame in animation.frames) {
      _disableFiltering(frame.sprite.paint);
    }
    return animation;
  }

  /// Flame [Images]에는 `fromBytes` 같은 헬퍼가 없어서, 다운로드한 바이트를
  /// `dart:ui`의 [ui.instantiateImageCodec]으로 직접 디코딩한 뒤
  /// [Images.add]로 캐시에 등록한다 — 키는 URL 자체를 쓰므로 같은 URL은
  /// 항상 같은 캐시 항목을 가리킨다.
  static Future<ui.Image> _loadImage(String url, Images imageCache) async {
    if (imageCache.containsKey(url)) {
      return imageCache.fromCache(url);
    }

    final http.Response response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw StateError('원격 이미지를 불러오지 못했습니다($url): HTTP ${response.statusCode}');
    }

    final ui.Codec codec = await ui.instantiateImageCodec(response.bodyBytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    imageCache.add(url, frame.image);
    return frame.image;
  }

  static void _disableFiltering(ui.Paint paint) {
    paint.isAntiAlias = false;
    paint.filterQuality = FilterQuality.none;
  }

  /// 픽셀 아트가 확대돼도 부드럽게 보간되지 않고 각지고 선명하게(Crisp)
  /// 남도록, 안티앨리어싱/필터링을 끈 새 [Paint]를 만들어 반환한다 —
  /// 이 프로젝트에서 "픽셀 아트를 어떻게 그릴지"를 정의하는 단 하나의
  /// 지점이다. 나중에 필터링 방식을 바꾸고 싶으면 여기 [_disableFiltering]
  /// 하나만 고치면 된다.
  ///
  /// [SpriteComponent]/[SpriteAnimationComponent]/
  /// [SpriteAnimationGroupComponent] 계열(Flame `HasPaint` 믹스인 사용)은
  /// 렌더링할 때 자기 자신의 `paint` 필드로 개별 [Sprite.paint]를
  /// **무조건 덮어써 버린다**(Flame 소스: `sprite.render(canvas, ...,
  /// overridePaint: paint)`) — 그래서 [loadSprite]/[loadSpriteAnimation]이
  /// 개별 스프라이트에 걸어 두는 필터링 해제만으로는 부족하고, 그 컴포넌트를
  /// 만들 때 이 메서드가 만든 Paint를 `paint:` 생성자 인자로 반드시
  /// 넘겨줘야 한다(예: [PlayerAnimationComponent]). 직접 `Sprite.render()`를
  /// 호출하는 커스텀 컴포넌트([ParallaxBackLayer]/[ParallaxGroundLayer]
  /// 같은 것)는 `overridePaint:`로 넘기면 된다.
  ///
  /// 호출할 때마다 새 [Paint] 인스턴스를 만들어 반환한다 — [Paint]는
  /// mutable이라, 여러 컴포넌트가 같은 인스턴스를 공유하면 한쪽의 투명도/틴트
  /// 조작(예: [HasPaint.setOpacity])이 다른 컴포넌트에도 새어 들어갈 수
  /// 있기 때문이다.
  static ui.Paint pixelArtPaint() {
    final ui.Paint paint = ui.Paint();
    _disableFiltering(paint);
    return paint;
  }
}
