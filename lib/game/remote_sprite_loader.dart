import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Canvas, Color, FilterQuality, Paint, Rect;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../constants/asset_paths.dart';

/// [RemoteSpriteLoader]의 회로 차단기가 이미 실패로 확정한(영구 차단이든,
/// 429 쿨다운 중이든) URL에 대해 던지는 "조용한" 예외 — 호출부의 진단
/// 로그([IdleGame]의 `ProjectileComponent.onLoad`/`_loadSpriteOrPlaceholder`
/// 등)가 이미 알고 있는 실패를 매번 다시 로그로 찍지 않고 건너뛸 수 있게,
/// "방금 새로 알아낸 실패"([StateError])와 구분하기 위한 타입이다.
class RemoteAssetBlocked implements Exception {
  const RemoteAssetBlocked(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Supabase Storage 등 원격 URL에서 Flame 컴포넌트가 쓸 [Sprite]/[SpriteAnimation]을
/// 내려받아 Flame의 이미지 캐시([Images])에 등록하는 로더 — Flutter UI 쪽의
/// [CustomSafeImage]/[CachedNetworkImage]와 짝을 이루는 Flame 전용 경로다
/// (Flame의 [Sprite]는 `dart:ui`의 [ui.Image]를 직접 들고 있어서
/// Flutter 위젯 트리의 이미지 캐시를 재사용할 수 없다).
///
/// ## 메모리 캐시 — 같은 URL은 두 번 요청하지 않는다
/// 성공적으로 디코딩한 [ui.Image]는 [Images]([Flame.images], URL을 키로
/// 쓰는 맵)에 캐시되므로, 같은 URL을 다시 요청하면 네트워크/디코딩 없이
/// 즉시 반환된다([_loadImage]). 의도적으로 [Sprite] 객체 자체는 캐시해서
/// 재사용하지 않는다 — [Sprite.paint]는 mutable이고, 컴포넌트가
/// [HasPaint.setOpacity] 등으로 자기 paint를 조작할 수 있어서, 캐시된
/// [Sprite] 인스턴스를 여러 컴포넌트가 공유하면 한쪽의 조작이 다른 쪽에도
/// 새어 들어간다([pixelArtPaint] 문서 참고). 그래서 [ui.Image](불변)만
/// 캐시하고, [Sprite](그 이미지를 감싸는 얇은 래퍼 + 독립된 Paint)는 호출할
/// 때마다 새로 만든다 — 이미 캐시된 이미지를 감싸기만 하므로 비용은
/// 무시할 만하다.
///
/// ## 방어 계층 (Git LFS 포인터 / 레이트리밋 응답 / 손상된 바이트)
/// Git LFS 포인터 검사([isGitLfsPointer])는 GitHub raw 저장소를 직접 쓰던
/// 시절의 유물이다 — 지금은 Supabase Storage([AssetPaths.baseUrl])를 쓰므로
/// 실제로 걸릴 일은 없지만, 판별 자체가 저비용이고 무해해서 방어 계층을
/// 그대로 남겨 뒀다(나중에 다시 Git 기반 저장소를 쓰게 되더라도 코드 변경이
/// 필요 없다). 레이트리밋(429)에 걸리면 — HTTP 상태 코드는 200이 아니거나
/// (429 등) 200이어도 본문이 진짜 이미지 바이너리가 아닐 수 있다. 이런 응답을
/// 그대로
/// [ui.instantiateImageCodec]에 넘기면 "EncodingError: The source image
/// cannot be decoded." 예외가 터진다. [_fetchValidatedBytes]가 디코딩을
/// 시도하기 전에 매직 바이트로 "이게 진짜 이미지처럼 생겼는지"부터 저비용
/// 검사하고, 아니면 정확한 사유(LFS 포인터/비-이미지 응답)를 담아 즉시
/// 실패시킨다.
///
/// 429는 다른 실패와 다르게 취급한다 — 404나 LFS 포인터는 "이 URL은 절대
/// 성공할 수 없다"는 뜻이라 세션 내내 영구 차단([_brokenUrls])하지만, 429는
/// "지금은 막혔지만 나중엔 풀릴 수 있다"는 뜻이라 [_rateLimitCooldown] 뒤엔
/// 다시 시도할 기회를 준다([_rateLimitedUntil]). 429를 처음 확정한 요청만
/// 짧은 지연 후 1회 자동재시도([_rateLimitBackoffDelay])해서 "진짜
/// 레이트리밋인지" 재확인하고, 그 순간 [_globalRateLimitCooldownUntil]로
/// 전역 쿨다운을 세운다 — 그 이후 도착하는 다른 URL들은(예:
/// [PlayerAnimationComponent._loadAction]이 한 캐릭터당 최대 10장의 프레임
/// 후보를 동시에 요청하는 경우) 각자 또 재확인 재시도를 하지 않고 곧바로
/// 실패 처리된다. 그래서 레이트리밋이 걸려도 실제 재시도 요청은 세션
/// 전체를 통틀어 딱 한 번만 나간다 — 여러 URL이 동시에 각자 재시도하면서
/// 요청량을 오히려 배가시켜 레이트리밋을 더 악화시키는 일은 없다. 429
/// 발생 사실 자체도 세션당 한 번만 로그로 알린다([_hasAnnouncedRateLimit]).
///
/// ## 단방향 폴백 순서
/// [_fetchValidatedBytes] 하나가 이 전체 흐름을 담당하고, 어떤 단계에서도
/// 이전 단계로 되돌아가거나 반복하지 않는다:
/// 1. 회로 차단기 확인([_checkCircuitBreaker]) — 이미 실패가 확정된 URL이면
///    네트워크를 아예 건드리지 않고 조용히 실패([RemoteAssetBlocked]).
/// 2. 원격 시도([_fetchRemoteValidatedBytes]) — 429면 위에서 설명한 규칙대로
///    최대 1회만 재확인. 그 외 실패(404/LFS 포인터/디코딩 불가 바이트)는
///    즉시 영구 차단.
/// 3. 원격이 실패했을 때만 로컬 번들 에셋을 정확히 1회 시도
///    ([_tryLoadLocalAsset]) — 개발 중 CDN이 막혀 있어도, 문제의 파일을
///    로컬 프로젝트의 같은 상대 경로에 복사해 두면 그걸로 계속 작업을
///    이어갈 수 있다(pubspec.yaml에 이미 `assets/images/`가 전체 등록돼
///    있다 — 새 파일을 추가한 뒤에는 hot reload가 아니라 앱을 다시
///    시작해야 애셋 매니페스트에 반영된다). 로컬 시도의 실패가 원격을
///    다시 두드리게 만드는 경로는 없다 — 로컬도 실패하면 원격 실패를
///    그대로 다시 던지고 끝난다.
/// 4. 그래도 실패하면 호출부([ProjectileComponent]/[PlayerAnimationComponent]
///    등)가 각자의 fallback(도형 등)으로 대체한다 — 이 클래스는 관여하지
///    않는다.
class RemoteSpriteLoader {
  const RemoteSpriteLoader._();

  /// 영구 차단 목록 — 404/LFS 포인터/디코딩 실패처럼 다시 시도해도 결과가
  /// 바뀌지 않는 실패만 여기 들어간다. 세션 동안 다시 시도하지 않는다
  /// ([SoundManager]의 `_brokenFiles`/[CustomSafeImage]의 `_brokenUrls`와
  /// 같은 관례).
  static final Set<String> _brokenUrls = {};

  /// 429(레이트리밋)로 일시 차단된 URL과 그 해제 시각 — [_brokenUrls]와
  /// 달리 시간이 지나면 저절로 풀린다.
  static final Map<String, DateTime> _rateLimitedUntil = {};

  /// 429를 새로 만났을 때 짧게 기다렸다가 한 번만 자동 재시도하는 대기
  /// 시간 — 너무 짧으면 재시도도 그대로 429를 맞을 뿐이고, 너무 길면 로딩
  /// 자체가 눈에 띄게 느려진다.
  static const Duration _rateLimitBackoffDelay = Duration(milliseconds: 600);

  /// 자동 재시도까지 실패했을 때 이 URL을 얼마나 차단해 둘지 — 서버가
  /// `Retry-After` 헤더를 주지 않는 경우(GitHub raw 저장소를 쓰던 시절
  /// 실측 확인됨) 정확한 해제 시점을 알 방법이 없다. 그래서 "그 시간까지
  /// 기다리면 실제로 풀린다"는 보장이 아니라, "이 시간 동안은 어차피 또
  /// 막힐 게 뻔하니 서버를 더 두드리지 말자"는 클라이언트 쪽 자체
  /// 쿨다운이다 — 그 시간이 지나면 다시 한번 시도해 보고, 여전히 막혀
  /// 있으면 또 같은 시간만큼 쿨다운을 건다.
  static const Duration _rateLimitCooldown = Duration(minutes: 2);

  /// 이번 세션에서 429를 한 번이라도 안내했는지 — 그렇다면 이후 429는
  /// [_markRateLimited]가 조용히 처리한다(로그 생략).
  static bool _hasAnnouncedRateLimit = false;

  /// "원격 저장소가 지금 우리를 레이트리밋 중이다"라는 사실 자체를 URL과 무관하게
  /// 전역으로 기억해 두는 시각 — [PlayerAnimationComponent._loadAction]처럼
  /// 한 번의 캐릭터 로드가 서로 다른 URL(run1.png, run2.png, ...)을 최대
  /// 10장까지 동시에(Future.wait) 요청하는 경우, 그 10개 요청이 전부 첫
  /// 시도에서 429를 맞고 각자 독립적으로 "짧게 대기 후 1회 재시도"를 하면
  /// 순간적으로 요청량이 2배로 뛰어(10 → 20) 레이트리밋을 오히려 더
  /// 악화시킨다. 그래서 429를 처음 확정한 요청이 이 값을 세팅해 두면,
  /// 그 뒤로 도착하는(이미 진행 중이거나 새로 시작하는) 다른 모든 요청은
  /// [_fetchRemoteValidatedBytes]가 자기 몫의 백오프 재시도를 건너뛰고
  /// 곧바로 실패 처리한다 — 세션 전체를 통틀어 "재확인 재시도"는 사실상
  /// 한 번만 일어난다.
  static DateTime? _globalRateLimitCooldownUntil;

  static bool _isGloballyRateLimited() {
    final DateTime? until = _globalRateLimitCooldownUntil;
    if (until == null) {
      return false;
    }
    if (DateTime.now().isBefore(until)) {
      return true;
    }
    _globalRateLimitCooldownUntil = null;
    return false;
  }

  /// 단위 테스트 전용 — 회로 차단기/레이트리밋/안내 상태를 전부 초기화한다.
  @visibleForTesting
  static void debugResetBrokenUrls() {
    _brokenUrls.clear();
    _rateLimitedUntil.clear();
    _globalRateLimitCooldownUntil = null;
    _hasAnnouncedRateLimit = false;
  }

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

  /// 애니메이션 WebP(또는 GIF 등 dart:ui가 다중 프레임으로 디코딩할 수
  /// 있는 포맷) 파일 하나를 통째로 내려받아, 그 파일 자체에 담긴 프레임과
  /// 프레임별 타이밍 그대로 Flame [SpriteAnimation]으로 만든다.
  /// [loadSpriteAnimation]과 다른 점: [loadSpriteAnimation]은 "가로로 이어
  /// 붙인 정지 이미지 여러 장(스프라이트 시트)"을 프레임 개수/간격을 직접
  /// 지정해 균등하게 잘라내는 방식이고, 이 함수는 "원본 애니메이션 파일
  /// 하나"를 그 파일이 실제로 갖고 있는 프레임 수·프레임별 지속시간
  /// 그대로 디코딩한다 — 프레임 개수나 간격을 호출부가 알 필요가 없다.
  ///
  /// 정지 이미지(프레임 1장)를 넘겨도 안전하게 동작한다(1프레임짜리
  /// 애니메이션이 된다) — 그래서 "실제로 애니메이션 파일인지"를 호출부가
  /// 미리 확인할 필요가 없다.
  ///
  /// [SpriteAnimation] 자체(조립된 결과)는 URL로 캐시하지 않는다 —
  /// [PlayerAnimationComponent.updateAttackStepTime]처럼 프레임의
  /// `stepTime`을 나중에 직접 mutate하는 호출부가 있어서, 같은 인스턴스를
  /// 여러 컴포넌트(예: 별개의 IdleGame 인스턴스 두 개가 같은 캐릭터를
  /// 동시에 로드)가 공유하면 한쪽의 변경이 다른 쪽 재생 속도에 새어
  /// 들어간다. 다만 프레임별 [ui.Image]는 여전히 [Images]에 캐시되므로
  /// (아래 `frameCacheKey`), 같은 URL을 다시 호출해도 네트워크 재요청과
  /// 코덱 재디코딩은 [_fetchValidatedBytes]의 회로 차단기가 막아 준다.
  static Future<SpriteAnimation> loadAnimatedWebP(String url, {Images? imageCache}) async {
    final Images cache = imageCache ?? Flame.images;
    final Uint8List bytes = await _fetchValidatedBytes(url);

    final ui.Codec codec;
    try {
      codec = await ui.instantiateImageCodec(bytes);
    } catch (error) {
      _brokenUrls.add(url);
      throw StateError('원격 애니메이션 디코딩에 실패했습니다($url): $error');
    }

    final List<SpriteAnimationFrame> frames = [];
    for (int i = 0; i < codec.frameCount; i++) {
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      // 프레임마다 캐시 키를 따로 둬야 한다 — Images 캐시는 URL(문자열)
      // 하나당 이미지 하나만 담을 수 있어서, 같은 url로 여러 프레임을 그냥
      // add()하면 마지막 프레임이 앞선 프레임들을 덮어써 버린다.
      final String frameCacheKey = '$url#$i';
      if (!cache.containsKey(frameCacheKey)) {
        cache.add(frameCacheKey, frameInfo.image);
      }
      final Sprite sprite = Sprite(cache.fromCache(frameCacheKey));
      _disableFiltering(sprite.paint);
      // duration이 0이거나 음수면(코덱이 타이밍 정보를 못 준 정지 이미지 등)
      // SpriteAnimation 생성자의 "모든 프레임은 stepTime > 0" 단언에 걸리므로
      // 안전한 최소값으로 대체한다.
      final double stepTime =
          frameInfo.duration.inMilliseconds > 0 ? frameInfo.duration.inMilliseconds / 1000 : 0.1;
      frames.add(SpriteAnimationFrame(sprite, stepTime));
    }

    if (frames.isEmpty) {
      _brokenUrls.add(url);
      throw StateError('애니메이션 프레임을 하나도 디코딩하지 못했습니다($url)');
    }
    return SpriteAnimation(frames, loop: true);
  }

  /// Flame [Images]에는 `fromBytes` 같은 헬퍼가 없어서, 다운로드한 바이트를
  /// `dart:ui`의 [ui.instantiateImageCodec]으로 직접 디코딩한 뒤
  /// [Images.add]로 캐시에 등록한다 — 키는 URL 자체를 쓰므로 같은 URL은
  /// 항상 같은 캐시 항목을 가리킨다(= 메모리 캐시. 두 번째 호출부터는
  /// 네트워크/디코딩 없이 즉시 반환된다).
  static Future<ui.Image> _loadImage(String url, Images imageCache) async {
    if (imageCache.containsKey(url)) {
      return imageCache.fromCache(url);
    }

    final Uint8List bytes = await _fetchValidatedBytes(url);

    final ui.Codec codec;
    final ui.FrameInfo frame;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      frame = await codec.getNextFrame();
    } catch (error) {
      _brokenUrls.add(url);
      throw StateError('원격 이미지 디코딩에 실패했습니다($url): $error');
    }
    imageCache.add(url, frame.image);
    return frame.image;
  }

  /// [url]의 바이트를 확보한다 — 원격(회로 차단기 → 429 백오프 → 매직
  /// 바이트 검증)이 전부 실패하면 마지막으로 로컬 번들 에셋을 시도한다.
  /// 어느 쪽으로도 확보하지 못하면 원격 실패의 원래 예외를 그대로 던진다.
  static Future<Uint8List> _fetchValidatedBytes(String url) async {
    final RemoteAssetBlocked? blocked = _checkCircuitBreaker(url);
    if (blocked != null) {
      throw blocked;
    }

    try {
      return await _fetchRemoteValidatedBytes(url);
    } catch (remoteError) {
      final Uint8List? localBytes = await _tryLoadLocalAsset(url);
      if (localBytes != null) {
        debugPrint('[RemoteSpriteLoader] 원격 로드 실패, 로컬 에셋으로 대체합니다: $url');
        return localBytes;
      }
      rethrow;
    }
  }

  /// [url]이 이미 차단(영구 실패 또는 429 쿨다운 중)돼 있으면 조용한
  /// [RemoteAssetBlocked]를 반환한다(호출부가 던진다) — 쿨다운이 이미
  /// 지났으면 그 기록을 지우고 null을 반환해 다시 시도할 기회를 준다.
  static RemoteAssetBlocked? _checkCircuitBreaker(String url) {
    final DateTime? cooldownUntil = _rateLimitedUntil[url];
    if (cooldownUntil != null) {
      if (DateTime.now().isBefore(cooldownUntil)) {
        return RemoteAssetBlocked('레이트리밋 쿨다운 중이라 재시도를 건너뜁니다: $url');
      }
      _rateLimitedUntil.remove(url);
    }
    if (_brokenUrls.contains(url)) {
      return RemoteAssetBlocked('이미 실패가 확인된 URL이라 재시도를 건너뜁니다: $url');
    }
    return null;
  }

  /// 실제 네트워크 요청 + 429 백오프 재시도 + 매직 바이트 검증. 로컬 폴백을
  /// 모르는(=회로 차단기 검사가 이미 끝난) 순수 "원격 시도" 담당이라
  /// [_fetchValidatedBytes]에서만 호출한다.
  ///
  /// 429 처리는 딱 한 단계만 밟는다 — 이미 전역으로 레이트리밋이 확정된
  /// 상태([_isGloballyRateLimited])라면 네트워크 요청 자체를 보내지 않고
  /// 곧바로 실패시키고, 아직 확정되지 않았다면 [_rateLimitBackoffDelay]만큼
  /// 기다렸다가 딱 1회만 재확인한다. 어느 쪽이든 요청을 두 번 넘게 보내는
  /// 경로는 없다 — 캐릭터 하나를 로드할 때 프레임 후보 10장을 동시에
  /// 요청하는 [PlayerAnimationComponent._loadAction]처럼 여러 URL이 한꺼번에
  /// 429를 맞아도, 맨 처음 확정한 요청 하나만 재확인 재시도를 하고 나머지는
  /// 곧바로 포기해 요청량이 배가되지 않는다.
  static Future<Uint8List> _fetchRemoteValidatedBytes(String url) async {
    if (_isGloballyRateLimited()) {
      _rateLimitedUntil[url] = _globalRateLimitCooldownUntil!;
      throw StateError('원격 저장소 레이트리밋(429) 쿨다운 중이라 요청을 보내지 않습니다: $url');
    }

    http.Response response = await http.get(Uri.parse(url));
    if (response.statusCode == 429) {
      await Future<void>.delayed(_rateLimitBackoffDelay);
      response = await http.get(Uri.parse(url));
    }
    if (response.statusCode == 429) {
      _markRateLimited(url);
      throw StateError('원격 저장소 요청 레이트리밋(429)에 걸렸습니다: $url');
    }
    if (response.statusCode != 200) {
      _brokenUrls.add(url);
      throw StateError('원격 이미지를 불러오지 못했습니다($url): HTTP ${response.statusCode}');
    }

    final Uint8List bytes = response.bodyBytes;
    if (!looksLikeImageBytes(bytes)) {
      _brokenUrls.add(url);
      final String reason = isGitLfsPointer(bytes)
          ? 'Git LFS 포인터 텍스트가 대신 내려왔습니다(리포의 LFS 설정을 확인하세요)'
          : '이미지가 아닌 응답입니다(HTML 에러 페이지, 레이트리밋 안내 등)';
      throw StateError('원격 이미지가 유효한 바이너리가 아닙니다($url): $reason');
    }
    return bytes;
  }

  /// [url]을 [_rateLimitCooldown] 동안 일시 차단하고, 같은 시각을 전역
  /// 쿨다운([_globalRateLimitCooldownUntil])으로도 승격한다 — 이후 다른
  /// URL들은 [_fetchRemoteValidatedBytes]가 네트워크 요청조차 보내지 않고
  /// 곧바로 실패 처리한다. 이번 세션에서 처음 겪는 429라면 딱 한 번만
  /// 안내 로그를 남긴다 — 레이트리밋 중에는 서로 다른 수십 개 URL이
  /// 동시에 429를 맞을 수 있어서, 매번 찍으면 터미널이 도배된다.
  static void _markRateLimited(String url) {
    final DateTime cooldownUntil = DateTime.now().add(_rateLimitCooldown);
    _rateLimitedUntil[url] = cooldownUntil;
    _globalRateLimitCooldownUntil = cooldownUntil;
    if (_hasAnnouncedRateLimit) {
      return;
    }
    _hasAnnouncedRateLimit = true;
    debugPrint(
      '[RemoteSpriteLoader] 원격 저장소 요청 레이트리밋(429)에 걸렸습니다 — '
      '${_rateLimitCooldown.inMinutes}분간 모든 원격 이미지 요청을 보내지 않고 '
      '로컬 에셋/도형으로 조용히 대체합니다. 이 안내는 이번 세션에서 다시 출력되지 않습니다.',
    );
  }

  /// [url]이 [AssetPaths.baseUrl] 아래의 원격 경로라면, 같은 상대 경로의
  /// 로컬 번들 에셋(`assets/images/...`)을 시도한다 — 개발 중 CDN이
  /// 레이트리밋에 걸려도, 문제의 파일을 로컬 프로젝트의 같은 경로(예:
  /// `assets/images/player/N/N1/player_n1_run2.png`, pubspec.yaml에
  /// 등록된 것과 정확히 같은 상대 경로)로 복사해 두면 그 파일로 계속
  /// 작업을 이어갈 수 있다.
  ///
  /// [주의] `rootBundle.load(key)`에 넘기는 [relativePath]는 **`assets/`
  /// 접두어를 포함한 그대로**([AssetPaths.baseUrl]을 뗀 나머지, 즉
  /// pubspec.yaml에 적힌 경로 그 자체)여야 한다 — 여기서 `assets/`를 한 번
  /// 더 벗겨내면 안 된다. Flutter Web은 빌드 시 이 키를 `build/web/assets/`
  /// 아래에 **그대로**(키 자체의 `assets/`까지 포함해서) 복사해 두므로,
  /// 브라우저 콘솔에 보이는 실제 요청 경로가 `assets/assets/images/...`
  /// 처럼 "이중"으로 보이는 게 정상이다(이 프로젝트에 이미 번들된
  /// `assets/icons/app_icon.png` 등도 전부 `build/web/assets/assets/icons/
  /// app_icon.png`에 위치한다 — 실측 확인됨). 즉 이건 경로 조립 버그가
  /// 아니라 Flutter Web의 정상 동작이고, 진짜 원인은 그 경로에 파일이
  /// 아직 로컬에 없다는 것뿐이다 — `assets/`를 억지로 한 겹 벗겨내면
  /// 오히려 pubspec.yaml에 등록된 진짜 키와 어긋나 로컬에 파일을 넣어도
  /// 절대 못 찾게 된다.
  ///
  /// 로컬에도 없으면(가장 흔한 경우 — 이건 "선택적 개발 편의"이지 항상
  /// 있어야 하는 파일이 아니다) 조용히 null을 반환한다. 이 호출이
  /// 실패하면(브라우저 devtools 콘솔에 Flutter 프레임워크 자체가 "Flutter
  /// Web engine failed to fetch..." 경고를 한 줄 남기는데, 이건 프레임워크
  /// 내부에서 직접 찍는 것이라 이 함수의 try/catch로도 막을 수 없다 —
  /// 하지만 [_fetchValidatedBytes]의 회로 차단기 덕분에 같은 URL에 대해
  /// 두 번 다시 반복되지는 않는다) 앱 동작에는 영향이 없다.
  static Future<Uint8List?> _tryLoadLocalAsset(String url) async {
    if (!url.startsWith(AssetPaths.baseUrl)) {
      return null;
    }
    final String relativePath = url.substring(AssetPaths.baseUrl.length);
    try {
      final ByteData data = await rootBundle.load(relativePath);
      final Uint8List bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      return looksLikeImageBytes(bytes) ? bytes : null;
    } catch (_) {
      // 로컬 번들에 그 경로가 아예 없는 게 정상 케이스이므로 조용히 null.
      return null;
    }
  }

  /// PNG/JPEG/WebP/GIF의 파일 매직 바이트로 시작하는지만 확인하는 아주
  /// 가벼운 사전 검사 — 완전한 포맷 검증은 실제 디코더([ui
  /// .instantiateImageCodec])의 몫이고, 이건 "명백히 이미지가 아닌 응답"만
  /// 싸게 걸러내는 용도다. 순수 함수라 네트워크 없이 단위 테스트할 수 있다.
  @visibleForTesting
  static bool looksLikeImageBytes(Uint8List bytes) {
    if (bytes.length < 12) {
      return false;
    }
    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return true;
    }
    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return true;
    }
    // WebP: RIFF....WEBP 컨테이너
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    // GIF: "GIF87a"/"GIF89a"
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return true;
    }
    return false;
  }

  /// [bytes]가 Git LFS 텍스트 포인터 형식("version https://git-lfs...")으로
  /// 시작하는지 — [looksLikeImageBytes]가 false를 반환했을 때, 정확히 어떤
  /// 이유였는지(LFS 포인터 vs 그 외 비-이미지 응답) 로그 메시지를 더
  /// 정확하게 남기기 위한 것. 순수 함수라 네트워크 없이 단위 테스트할 수
  /// 있다.
  @visibleForTesting
  static bool isGitLfsPointer(Uint8List bytes) {
    if (bytes.length < 7) {
      return false;
    }
    final int previewLength = bytes.length < 64 ? bytes.length : 64;
    // 바이트 0~255는 항상 유효한 코드 포인트라 fromCharCodes가 임의
    // 바이너리에도 절대 예외를 던지지 않는다 — UTF 디코딩이 아니다.
    final String preview = String.fromCharCodes(bytes.sublist(0, previewLength));
    return preview.startsWith('version https://git-lfs');
  }

  /// 네트워크가 완전히 끊겼거나 캐릭터의 모든 아트(프레임 시퀀스 + 단일
  /// 이미지 폴백 + 로컬 에셋까지)가 전부 실패해도 100% 성공하는 최후의
  /// 보루 — 실제 파일을 전혀 내려받지 않고 dart:ui로 즉석에서 단색
  /// 정사각형 이미지를 그려 [Sprite]로 감싼다. [PlayerAnimationComponent
  /// .loadCharacter]가 이걸 최종 폴백으로 써서, "장착 캐릭터를 바꿨는데
  /// 화면이 이전 캐릭터에 멈춰 있다"처럼 보이는 대신 최소한 전환 자체는
  /// (단색 placeholder 모습이라도) 항상 즉시 반영되게 한다.
  static Future<Sprite> placeholderSprite({
    Color color = const Color(0xFF3A3A4A),
    int size = 64,
  }) async {
    final String cacheKey = 'placeholder_sprite_${color.toString()}_$size';
    if (Flame.images.containsKey(cacheKey)) {
      final Sprite sprite = Sprite(Flame.images.fromCache(cacheKey));
      _disableFiltering(sprite.paint);
      return sprite;
    }

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()), Paint()..color = color);
    final ui.Image image = await recorder.endRecording().toImage(size, size);
    Flame.images.add(cacheKey, image);

    final Sprite sprite = Sprite(image);
    _disableFiltering(sprite.paint);
    return sprite;
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
