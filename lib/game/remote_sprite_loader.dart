import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Canvas, Color, FilterQuality, Paint, Rect;
import 'package:http/http.dart' as http;

import '../managers/storage_manager.dart';

/// [RemoteSpriteLoader]의 회로 차단기가 이미 실패로 확정한(영구 차단이든,
/// 429 쿨다운 중이든) objectKey에 대해 던지는 "조용한" 예외 — 호출부의 진단
/// 로그([IdleGame]의 `ProjectileComponent.onLoad`/`_loadSpriteOrPlaceholder`
/// 등)가 이미 알고 있는 실패를 매번 다시 로그로 찍지 않고 건너뛸 수 있게,
/// "방금 새로 알아낸 실패"([StateError])와 구분하기 위한 타입이다.
class RemoteAssetBlocked implements Exception {
  const RemoteAssetBlocked(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Cloudflare R2(비공개 버킷)에서 Flame 컴포넌트가 쓸 [Sprite]/
/// [SpriteAnimation]을 내려받아 Flame의 이미지 캐시([Images])에 등록하는
/// 로더 — Flutter UI 쪽의 [CustomSafeImage]/[CachedNetworkImage]와 짝을
/// 이루는 Flame 전용 경로다(Flame의 [Sprite]는 `dart:ui`의 [ui.Image]를
/// 직접 들고 있어서 Flutter 위젯 트리의 이미지 캐시를 재사용할 수 없다).
///
/// ## objectKey vs 실제 요청 URL — 반드시 구분해야 하는 이유
/// 이 클래스가 받는 문자열([objectKey], 예:
/// `assets/images/player/N/N1/player_n1_front.png`)은 더 이상 그 자체로
/// 요청 가능한 URL이 아니다 — R2가 비공개 버킷으로 바뀌면서, 실제로
/// 내려받으려면 매번 [StorageManager.imageUrl]로 Supabase Edge
/// Function(`get-r2-url`)에서 짧은 유효기간(1시간)의 서명 URL을 새로
/// 발급받아야 한다. 이 서명 URL은 같은 objectKey라도 발급될 때마다
/// 쿼리스트링 서명이 달라진다 — 그래서 **이 파일의 모든 캐시/회로
/// 차단기(Flame [Images] 캐시, [_brokenUrls], [_rateLimitedUntil])는
/// objectKey로만 키를 잡는다**. 예전처럼 요청 URL 자체를 캐시 키로 쓰면,
/// [StorageManager]의 캐시가 갱신될 때마다(약 55분마다) 서명이 달라진
/// "새 URL"을 완전히 새로운 자산으로 착각해 이미 캐시된 이미지를 다시
/// 내려받고, 오래된 [ui.Image]는 캐시에 고아로 계속 쌓이는(메모리 누수)
/// 사고가 난다.
///
/// ## 메모리 캐시 — 같은 objectKey는 두 번 요청하지 않는다
/// 성공적으로 디코딩한 [ui.Image]는 [Images]([Flame.images], objectKey를
/// 키로 쓰는 맵)에 캐시되므로, 같은 objectKey를 다시 요청하면 네트워크/
/// 디코딩 없이 즉시 반환된다([_loadImage]). 의도적으로 [Sprite] 객체
/// 자체는 캐시해서 재사용하지 않는다 — [Sprite.paint]는 mutable이고,
/// 컴포넌트가 [HasPaint.setOpacity] 등으로 자기 paint를 조작할 수 있어서,
/// 캐시된 [Sprite] 인스턴스를 여러 컴포넌트가 공유하면 한쪽의 조작이
/// 다른 쪽에도 새어 들어간다([pixelArtPaint] 문서 참고). 그래서
/// [ui.Image](불변)만 캐시하고, [Sprite](그 이미지를 감싸는 얇은 래퍼 +
/// 독립된 Paint)는 호출할 때마다 새로 만든다 — 이미 캐시된 이미지를
/// 감싸기만 하므로 비용은 무시할 만하다.
///
/// ## 방어 계층 (Git LFS 포인터 / 레이트리밋 응답 / 손상된 바이트)
/// Git LFS 포인터 검사([isGitLfsPointer])는 GitHub raw 저장소를 직접 쓰던
/// 시절의 유물이다 — 지금은 Cloudflare R2를 쓰므로 실제로 걸릴 일은
/// 없지만, 판별 자체가 저비용이고 무해해서 방어 계층을 그대로 남겨
/// 뒀다. 레이트리밋(429)에 걸리면 — HTTP 상태 코드는 200이 아니거나
/// (429 등) 200이어도 본문이 진짜 이미지 바이너리가 아닐 수 있다. 이런
/// 응답을 그대로 [ui.instantiateImageCodec]에 넘기면 "EncodingError: The
/// source image cannot be decoded." 예외가 터진다.
/// [_fetchRemoteValidatedBytes]가 디코딩을 시도하기 전에 매직 바이트로
/// "이게 진짜 이미지처럼 생겼는지"부터 저비용 검사하고, 아니면 정확한
/// 사유(LFS 포인터/비-이미지 응답)를 담아 즉시 실패시킨다.
///
/// 429는 다른 실패와 다르게 취급한다 — 404나 LFS 포인터는 "이 objectKey는
/// 절대 성공할 수 없다"는 뜻이라 세션 내내 영구 차단([_brokenUrls])하지만,
/// 429는 "지금은 막혔지만 나중엔 풀릴 수 있다"는 뜻이라
/// [_rateLimitCooldown] 뒤엔 다시 시도할 기회를 준다([_rateLimitedUntil]).
/// 429를 처음 확정한 요청만 짧은 지연 후 1회 자동재시도
/// ([_rateLimitBackoffDelay])해서 "진짜 레이트리밋인지" 재확인하고, 그
/// 순간 [_globalRateLimitCooldownUntil]로 전역 쿨다운을 세운다 — 그 이후
/// 도착하는 다른 objectKey들은(예: [PlayerAnimationComponent.loadCharacter]가
/// 한 캐릭터당 run/attack/wait/defeat 요청을 동시에 보내는 경우) 각자 또
/// 재확인 재시도를 하지 않고 곧바로 실패 처리된다. 그래서 레이트리밋이
/// 걸려도 실제 재시도 요청은 세션 전체를 통틀어 딱 한 번만 나간다 — 여러
/// objectKey가 동시에 각자 재시도하면서 요청량을 오히려 배가시켜
/// 레이트리밋을 더 악화시키는 일은 없다. 429 발생 사실 자체도 세션당 한
/// 번만 로그로 알린다([_hasAnnouncedRateLimit]).
///
/// [StorageManager]를 통한 URL 발급 실패(Edge Function 미배포/네트워크
/// 단절 등)는 "이 objectKey가 존재하지 않는다"는 확정이 아니라 "지금
/// 인프라에 접근할 수 없다"는 뜻이라, 404처럼 영구 차단하지 않는다 —
/// 다음 요청에서 다시 시도할 기회를 준다.
///
/// ## 단방향 폴백 순서
/// [_fetchValidatedBytes] 하나가 이 전체 흐름을 담당하고, 어떤 단계에서도
/// 이전 단계로 되돌아가거나 반복하지 않는다:
/// 1. 회로 차단기 확인([_checkCircuitBreaker]) — 이미 실패가 확정된
///    objectKey면 네트워크를 아예 건드리지 않고 조용히 실패
///    ([RemoteAssetBlocked]).
/// 2. [StorageManager.imageUrl]로 서명 URL 발급 — 실패(인프라 문제)하면
///    영구 차단 없이 즉시 그 라운드만 실패.
/// 3. 원격 시도([_fetchRemoteValidatedBytes]) — 429면 위에서 설명한
///    규칙대로 최대 1회만 재확인. 그 외 실패(404/LFS 포인터/디코딩 불가
///    바이트)는 즉시 영구 차단.
/// 4. 그래도 실패하면 호출부([ProjectileComponent]/
///    [PlayerAnimationComponent] 등)가 각자의 fallback(도형 등)으로
///    대체한다 — 이 클래스는 관여하지 않는다.
///
/// [주의: 로컬 번들 에셋 폴백은 없다] 예전엔 원격이 실패하면 마지막으로
/// `rootBundle.load(objectKey)`(로컬 프로젝트의 같은 상대 경로)를 한 번
/// 더 시도했다 — 지금은 제거했다. Flutter Web은 pubspec.yaml에 등록된
/// 에셋을 항상 "assets/" 네임스페이스 아래로 한 번 더 감싸 서빙한다
/// (`flutter build web` 결과물이 실제로 `build/web/assets/assets/images/...`
/// 로 중첩되는 것으로 직접 확인함) — 이 프로젝트의 에셋 폴더 이름이
/// 하필 "assets"라서, objectKey(`assets/images/...`)를 그대로
/// `rootBundle.load`에 넘기면 실제 요청 경로가 `.../assets/assets/images/...`
/// 처럼 두 번 겹쳐 보인다. 이건 문자열 조립 버그가 아니라 Flutter Web의
/// 정상 동작이라 코드로 "고칠" 방법이 없고(objectKey에서 "assets/"를
/// 떼어내면 반대로 에셋 매니페스트에서 그 키를 아예 못 찾아 더 일찍
/// 깨진다), 지금 이 프로젝트의 아트는 전부 R2에만 있고 로컬 프로젝트에는
/// 애초에 존재하지 않으므로(R2 마이그레이션 이후 로컬 사본을 유지하지
/// 않는다) 이 폴백은 사실상 항상 실패만 하면서 브라우저 콘솔에 진짜
/// 원인(R2에 그 objectKey가 없다)과 구분하기 어려운 "이중 경로" 404를
/// 하나 더 추가하는 노이즈였다. 그래서 완전히 제거했다 — 원격 실패가
/// 곧바로 최종 실패로 이어지므로, 콘솔에는 이제 R2 실패 로그 하나만
/// 남는다. 개발 중 R2에 아직 없는 아트를 로컬에서 미리 보고 싶다면
/// [AppImages] 대신 그 파일을 가리키는 임시 `http(s)://` 직접 URL을
/// 쓰거나, R2에 먼저 업로드하는 쪽을 권장한다.
class RemoteSpriteLoader {
  const RemoteSpriteLoader._();

  /// 영구 차단 목록(objectKey 기준) — 404/LFS 포인터/디코딩 실패처럼
  /// 다시 시도해도 결과가 바뀌지 않는 실패만 여기 들어간다. 세션 동안
  /// 다시 시도하지 않는다([SoundManager]의 `_brokenFiles`/
  /// [CustomSafeImage]의 `_brokenUrls`와 같은 관례).
  static final Set<String> _brokenUrls = {};

  /// 429(레이트리밋)로 일시 차단된 objectKey와 그 해제 시각 —
  /// [_brokenUrls]와 달리 시간이 지나면 저절로 풀린다.
  static final Map<String, DateTime> _rateLimitedUntil = {};

  /// 429를 새로 만났을 때 짧게 기다렸다가 한 번만 자동 재시도하는 대기
  /// 시간 — 너무 짧으면 재시도도 그대로 429를 맞을 뿐이고, 너무 길면 로딩
  /// 자체가 눈에 띄게 느려진다.
  static const Duration _rateLimitBackoffDelay = Duration(milliseconds: 600);

  /// 자동 재시도까지 실패했을 때 이 objectKey를 얼마나 차단해 둘지 —
  /// 서버가 `Retry-After` 헤더를 주지 않는 경우 정확한 해제 시점을 알
  /// 방법이 없다. 그래서 "그 시간까지 기다리면 실제로 풀린다"는 보장이
  /// 아니라, "이 시간 동안은 어차피 또 막힐 게 뻔하니 서버를 더 두드리지
  /// 말자"는 클라이언트 쪽 자체 쿨다운이다 — 그 시간이 지나면 다시 한번
  /// 시도해 보고, 여전히 막혀 있으면 또 같은 시간만큼 쿨다운을 건다.
  static const Duration _rateLimitCooldown = Duration(minutes: 2);

  /// 이번 세션에서 429를 한 번이라도 안내했는지 — 그렇다면 이후 429는
  /// [_markRateLimited]가 조용히 처리한다(로그 생략).
  static bool _hasAnnouncedRateLimit = false;

  /// "원격 저장소가 지금 우리를 레이트리밋 중이다"라는 사실 자체를
  /// objectKey와 무관하게 전역으로 기억해 두는 시각 —
  /// [PlayerAnimationComponent.loadCharacter]처럼 한 번의 캐릭터 로드가
  /// 서로 다른 objectKey(run 시트, attack 시트, wait 시트, hit 이미지)를
  /// 동시에(Future.wait) 요청하는 경우, 그 요청들이 전부 첫 시도에서
  /// 429를 맞고 각자 독립적으로 "짧게 대기 후 1회 재시도"를 하면 순간적으로
  /// 요청량이 2배로 뛰어 레이트리밋을 오히려 더 악화시킨다.
  /// 그래서 429를 처음 확정한 요청이 이 값을 세팅해 두면, 그 뒤로
  /// 도착하는(이미 진행 중이거나 새로 시작하는) 다른 모든 요청은
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

  /// [objectKey](R2 안의 상대 경로, 예:
  /// `assets/images/player/N/N1/player_n1_front.png`)의 이미지를 내려받아
  /// Flame 이미지 캐시에 등록하고 [Sprite]로 반환한다. 픽셀 아트가 확대돼도
  /// 뭉개지지 않도록 paint의 필터링을 끈 상태로 돌려준다.
  static Future<Sprite> loadSprite(String objectKey, {Images? imageCache}) async {
    final ui.Image image = await _loadImage(objectKey, imageCache ?? Flame.images);
    final Sprite sprite = Sprite(image);
    _disableFiltering(sprite.paint);
    return sprite;
  }

  /// 스프라이트 시트 한 장을 [amount]칸으로 잘라 [SpriteAnimation]을
  /// 만든다 — [amount]/[textureSize](칸 하나의 픽셀 크기)는 호출부가
  /// 명시적으로 넘긴다. [CharacterAnimationManager]에 캐릭터/모션별로
  /// 등록된 [SpriteSheetSpec](DB `character_animations` 행)이 이 값들의
  /// 실제 출처다 — 이 함수 자체는 어떤 캐릭터가 몇 프레임인지는 전혀
  /// 모른다.
  ///
  /// [amountPerRow](한 행에 들어가는 칸 수)는 DB 스키마에 그 컬럼이 없어
  /// 대부분 null로 들어온다 — 그럴 땐 [_resolveColumns]가 실제로 로드된
  /// 이미지의 가로 픽셀 수를 [textureSize.x]로 나눠 역산한다(예: 시트가
  /// 실제로는 3200px 폭에 800px짜리 칸이 4개씩 배치된 다중 행 격자라면
  /// `3200 ~/ 800 = 4`열). 이렇게 역산한 열 수를 검증([_validateSheetBounds])
  /// 과 실제 슬라이싱([SpriteAnimationData.sequenced]) 양쪽에 동일하게
  /// 써야 한다 — 검증만 고치고 슬라이싱은 예전처럼 "한 행에 전부"로
  /// 넘기면, 검증은 통과해도 실제로 잘라내는 격자는 여전히 틀린 채로
  /// 남는다. 실제로 잘라내기 전에 [_validateSheetBounds]로 그 격자가
  /// 이미지 크기 안에 들어오는지 먼저 확인한다. 모든 프레임에 동일하게
  /// 필터링을 끈다.
  static Future<SpriteAnimation> loadSpriteAnimation(
    String objectKey, {
    required int amount,
    required Vector2 textureSize,
    required double stepTime,
    int? amountPerRow,
    bool loop = true,
    Images? imageCache,
  }) async {
    final ui.Image image = await _loadImage(objectKey, imageCache ?? Flame.images);
    final int columns = _resolveColumns(
      image: image,
      amount: amount,
      textureSize: textureSize,
      amountPerRow: amountPerRow,
    );
    _validateSheetBounds(
      objectKey: objectKey,
      image: image,
      amount: amount,
      textureSize: textureSize,
      columns: columns,
    );

    final SpriteAnimation animation = SpriteAnimation.fromFrameData(
      image,
      SpriteAnimationData.sequenced(
        amount: amount,
        stepTime: stepTime,
        textureSize: textureSize,
        amountPerRow: columns,
        loop: loop,
      ),
    );
    for (final SpriteAnimationFrame frame in animation.frames) {
      _disableFiltering(frame.sprite.paint);
    }
    return animation;
  }

  /// 한 행에 실제로 몇 칸이 들어있는지 결정한다.
  ///
  /// [amountPerRow]를 호출부가 명시적으로 넘겼으면(지금 DB 스키마엔 그런
  /// 컬럼이 없어 항상 null이지만, 나중에 추가될 경우를 대비해 오버라이드
  /// 통로를 남겨 둔다) 그 값을 그대로 쓴다. 아니면 실제 로드된 이미지의
  /// 가로 픽셀 수를 프레임 한 칸의 가로 크기([textureSize.x])로 나눠 열
  /// 수를 역산한다 — 예: 3200px 폭 시트에 800px짜리 칸이면 `3200 ~/ 800
  /// = 4`열짜리 격자. **[amount](총 프레임 수)에서 역산하지 않는다** —
  /// 예전 기본값(`amountPerRow = amount`, "무조건 한 행에 전부")은 시트가
  /// 실제로는 여러 행으로 접혀 있을 때 완전히 틀린 열 수가 되어 프레임을
  /// 엉뚱한 경계로 잘라냈다(캐릭터가 깜빡이거나 조각나 보이는 원인). DB에
  /// "이 시트가 몇 행/열로 접혀 있는지"를 담을 컬럼이 없는 지금, 실제
  /// 이미지의 픽셀 크기가 유일하게 신뢰할 수 있는 소스다.
  static int _resolveColumns({
    required ui.Image image,
    required int amount,
    required Vector2 textureSize,
    int? amountPerRow,
  }) {
    if (amountPerRow != null && amountPerRow > 0) {
      return amountPerRow;
    }
    if (textureSize.x <= 0) {
      // 0 이하인 값은 이 함수가 판단할 수 없다 — _validateSheetBounds가
      // 곧 이 규격 자체를 명확한 에러로 실패시킨다.
      return amount;
    }
    final int columnsFromImage = image.width ~/ textureSize.x.round();
    if (columnsFromImage <= 0) {
      // 이미지가 프레임 한 칸보다도 좁다 — 1을 반환해 아래 검증 단계가
      // "그 자체로 실패"라는 명확한 진단을 내도록 한다.
      return 1;
    }
    // 역산한 열 수가 총 프레임 수보다 많으면(시트 여백 등으로 계산이 더
    // 크게 나온 경우) 의미가 없으므로 amount로 상한을 둔다 — 정확히 한
    // 행짜리 시트라면 어차피 columnsFromImage가 amount와 같거나 그 이하로
    // 나온다.
    return columnsFromImage > amount ? amount : columnsFromImage;
  }

  /// [textureSize](DB `frame_width`/`frame_height`)로 [amount]개 프레임을
  /// ([columns]장마다 다음 행으로 접어) 실제로 잘라낼 수 있는지 미리
  /// 검증한다. [columns]는 [_resolveColumns]가 결정한, 실제 슬라이싱에도
  /// 그대로 쓰이는 값이다 — 검증과 실제 슬라이싱이 서로 다른 열 수를 쓰는
  /// 일이 없도록 호출부([loadSpriteAnimation])가 하나의 값을 계산해 양쪽에
  /// 동일하게 넘긴다.
  ///
  /// [주의: textureSize는 반드시 "칸 하나(프레임 하나)"의 픽셀 크기다 —
  /// 시트 "전체" 크기가 아니다] `character_animations.frame_width`/
  /// `frame_height`를 시트 전체 해상도로 착각해 그대로 등록하면, 여기서
  /// 계산하는 필요 크기(`textureSize * 열/행 수`)가 실제 시트보다 훨씬
  /// 커져 항상 이 검증에서 걸린다 — 그게 정상이다(반대로 "칸 크기"를
  /// "전체 크기"인 것처럼 줄여서 넘기면 검증은 통과하지만 각 프레임이
  /// 시트 전체를 한 칸으로 착각해 늘어난 채로 그려진다).
  ///
  /// [왜 로드 시점에 미리 확인하는가] Flame의 `SpriteAnimationData
  /// .sequenced`/`Sprite`는 이 계산이 이미지 실제 크기를 벗어나도 생성
  /// 시점([SpriteAnimation.fromFrameData] 호출)엔 조용히 넘어가고, 나중에
  /// 그 프레임이 재생될 차례에만(렌더링 시점, [PlayerAnimationComponent
  /// .render]가 매 프레임 호출하는 시점) "Image ... is smaller than the
  /// requested size" 같은 오류를 내거나 아예 그리지 않는다 — 이 실패는
  /// [PlayerAnimationComponent.loadCharacter]의 `await` 바깥(렌더 루프
  /// 안)에서 일어나므로 그쪽 try/catch로 잡히지 않고, 재생 프레임이
  /// 순환하며 어떤 인덱스는 성공(그려짐)·어떤 인덱스는 실패(안 그려지거나
  /// 오류)를 반복해 캐릭터가 깜빡이는 것처럼 보인다. 그래서 로드 시점에
  /// 미리 전체 그리드가 이미지 안에 들어오는지 확인해, 안 맞으면 그
  /// 자리에서(아직 `await` 안, 호출부의 try/catch가 잡을 수 있는 시점에)
  /// 명확한 진단 메시지와 함께 실패시킨다 — 호출부
  /// ([PlayerAnimationComponent._loadActionAnimation])가 이 실패를 잡아
  /// webp/단일 이미지 폴백으로 안전하게 넘어간다.
  static void _validateSheetBounds({
    required String objectKey,
    required ui.Image image,
    required int amount,
    required Vector2 textureSize,
    required int columns,
  }) {
    if (amount <= 0 || textureSize.x <= 0 || textureSize.y <= 0) {
      throw StateError(
        '스프라이트 시트 규격이 올바르지 않습니다($objectKey): amount=$amount, '
        'textureSize=$textureSize — 전부 0보다 커야 합니다.',
      );
    }
    final int rows = (amount / columns).ceil();
    final double requiredWidth = textureSize.x * columns;
    final double requiredHeight = textureSize.y * rows;

    if (requiredWidth > image.width || requiredHeight > image.height) {
      final String message =
          '스프라이트 시트가 DB 규격보다 작습니다($objectKey): 실제 이미지 크기는 '
          '${image.width}x${image.height}인데, DB 규격(frame_width='
          '${textureSize.x.toInt()}, frame_height=${textureSize.y.toInt()} — 반드시 '
          '"1칸(1프레임)당" 픽셀 크기여야 합니다, 시트 "전체" 크기가 아닙니다) × '
          'amount=$amount(이미지 폭에서 역산한 한 행 $columns장, $rows행 가정)로는 '
          '최소 ${requiredWidth.toInt()}x${requiredHeight.toInt()}가 필요합니다. '
          'character_animations 테이블의 frame_width/frame_height/frame_count 값이 '
          '실제 업로드된 시트 이미지와 맞는지 확인하세요.';
      debugPrint('[RemoteSpriteLoader] $message');
      throw StateError(message);
    }
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
  /// [SpriteAnimation] 자체(조립된 결과)는 objectKey로 캐시하지 않는다 —
  /// [PlayerAnimationComponent.updateAttackStepTime]처럼 프레임의
  /// `stepTime`을 나중에 직접 mutate하는 호출부가 있어서, 같은 인스턴스를
  /// 여러 컴포넌트(예: 별개의 IdleGame 인스턴스 두 개가 같은 캐릭터를
  /// 동시에 로드)가 공유하면 한쪽의 변경이 다른 쪽 재생 속도에 새어
  /// 들어간다. 다만 프레임별 [ui.Image]는 여전히 [Images]에 캐시되므로
  /// (아래 `frameCacheKey`), 같은 objectKey를 다시 호출해도 네트워크
  /// 재요청과 코덱 재디코딩은 [_fetchValidatedBytes]의 회로 차단기가
  /// 막아 준다.
  static Future<SpriteAnimation> loadAnimatedWebP(String objectKey, {Images? imageCache}) async {
    final Images cache = imageCache ?? Flame.images;
    final Uint8List bytes = await _fetchValidatedBytes(objectKey);

    final ui.Codec codec;
    try {
      codec = await ui.instantiateImageCodec(bytes);
    } catch (error) {
      _brokenUrls.add(objectKey);
      throw StateError('원격 애니메이션 디코딩에 실패했습니다($objectKey): $error');
    }

    final List<SpriteAnimationFrame> frames = [];
    for (int i = 0; i < codec.frameCount; i++) {
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      // 프레임마다 캐시 키를 따로 둬야 한다 — Images 캐시는 키 하나당
      // 이미지 하나만 담을 수 있어서, 같은 objectKey로 여러 프레임을 그냥
      // add()하면 마지막 프레임이 앞선 프레임들을 덮어써 버린다.
      final String frameCacheKey = '$objectKey#$i';
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
      _brokenUrls.add(objectKey);
      throw StateError('애니메이션 프레임을 하나도 디코딩하지 못했습니다($objectKey)');
    }
    return SpriteAnimation(frames, loop: true);
  }

  /// Flame [Images]에는 `fromBytes` 같은 헬퍼가 없어서, 다운로드한 바이트를
  /// `dart:ui`의 [ui.instantiateImageCodec]으로 직접 디코딩한 뒤
  /// [Images.add]로 캐시에 등록한다 — 키는 [objectKey] 자체를 쓰므로(발급
  /// 받을 때마다 서명이 달라지는 실제 요청 URL이 아니라) 같은 objectKey는
  /// 항상 같은 캐시 항목을 가리킨다(= 메모리 캐시. 두 번째 호출부터는
  /// 네트워크/디코딩 없이 즉시 반환된다).
  static Future<ui.Image> _loadImage(String objectKey, Images imageCache) async {
    if (imageCache.containsKey(objectKey)) {
      return imageCache.fromCache(objectKey);
    }

    final Uint8List bytes = await _fetchValidatedBytes(objectKey);

    final ui.Codec codec;
    final ui.FrameInfo frame;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      frame = await codec.getNextFrame();
    } catch (error) {
      _brokenUrls.add(objectKey);
      throw StateError('원격 이미지 디코딩에 실패했습니다($objectKey): $error');
    }
    imageCache.add(objectKey, frame.image);
    return frame.image;
  }

  /// [objectKey]의 바이트를 확보한다 — 회로 차단기 확인 → R2 서명 URL
  /// 발급([StorageManager]) → 원격 요청(429 백오프 → 매직 바이트 검증).
  /// 로컬 번들 에셋 폴백은 없다(클래스 문서의 "로컬 번들 에셋 폴백은
  /// 없다" 참고) — 실패하면 원격 실패를 그대로 던진다.
  static Future<Uint8List> _fetchValidatedBytes(String objectKey) async {
    final RemoteAssetBlocked? blocked = _checkCircuitBreaker(objectKey);
    if (blocked != null) {
      throw blocked;
    }
    return _fetchRemoteValidatedBytes(objectKey);
  }

  /// [objectKey]가 이미 차단(영구 실패 또는 429 쿨다운 중)돼 있으면 조용한
  /// [RemoteAssetBlocked]를 반환한다(호출부가 던진다) — 쿨다운이 이미
  /// 지났으면 그 기록을 지우고 null을 반환해 다시 시도할 기회를 준다.
  static RemoteAssetBlocked? _checkCircuitBreaker(String objectKey) {
    final DateTime? cooldownUntil = _rateLimitedUntil[objectKey];
    if (cooldownUntil != null) {
      if (DateTime.now().isBefore(cooldownUntil)) {
        return RemoteAssetBlocked('레이트리밋 쿨다운 중이라 재시도를 건너뜁니다: $objectKey');
      }
      _rateLimitedUntil.remove(objectKey);
    }
    if (_brokenUrls.contains(objectKey)) {
      return RemoteAssetBlocked('이미 실패가 확인된 objectKey라 재시도를 건너뜁니다: $objectKey');
    }
    return null;
  }

  /// R2 서명 URL 발급 + 실제 네트워크 요청 + 429 백오프 재시도 + 매직
  /// 바이트 검증. 로컬 폴백을 모르는(=회로 차단기 검사가 이미 끝난) 순수
  /// "원격 시도" 담당이라 [_fetchValidatedBytes]에서만 호출한다.
  ///
  /// [StorageManager.imageUrl] 자체가 실패하면(Edge Function 미배포,
  /// 네트워크 단절 등 — "이 objectKey가 R2에 없다"는 뜻이 아니라 "지금
  /// 서명 URL을 발급받을 인프라에 닿지 못했다"는 뜻) 영구 차단하지 않고
  /// 그 라운드만 실패시킨다 — 인프라가 다시 살아나면 다음 요청이 정상
  /// 복구된다.
  ///
  /// 429 처리는 딱 한 단계만 밟는다 — 이미 전역으로 레이트리밋이 확정된
  /// 상태([_isGloballyRateLimited])라면 네트워크 요청 자체를 보내지 않고
  /// 곧바로 실패시키고, 아직 확정되지 않았다면 [_rateLimitBackoffDelay]만큼
  /// 기다렸다가 딱 1회만 재확인한다. 어느 쪽이든 요청을 두 번 넘게 보내는
  /// 경로는 없다 — 캐릭터 하나를 로드할 때 여러 objectKey를 동시에
  /// 요청하는 [PlayerAnimationComponent.loadCharacter]처럼 여러 objectKey가
  /// 한꺼번에 429를 맞아도, 맨 처음 확정한 요청 하나만 재확인 재시도를
  /// 하고 나머지는 곧바로 포기해 요청량이 배가되지 않는다.
  static Future<Uint8List> _fetchRemoteValidatedBytes(String objectKey) async {
    if (_isGloballyRateLimited()) {
      _rateLimitedUntil[objectKey] = _globalRateLimitCooldownUntil!;
      throw StateError('원격 저장소 레이트리밋(429) 쿨다운 중이라 요청을 보내지 않습니다: $objectKey');
    }

    final String? signedUrl = await StorageManager.instance.imageUrl(objectKey);
    if (signedUrl == null) {
      throw StateError('R2 서명 URL을 발급받지 못했습니다($objectKey) — 인프라 문제일 수 있습니다.');
    }

    http.Response response = await http.get(Uri.parse(signedUrl));
    if (response.statusCode == 429) {
      await Future<void>.delayed(_rateLimitBackoffDelay);
      response = await http.get(Uri.parse(signedUrl));
    }
    if (response.statusCode == 429) {
      _markRateLimited(objectKey);
      throw StateError('원격 저장소 요청 레이트리밋(429)에 걸렸습니다: $objectKey');
    }
    if (response.statusCode != 200) {
      _brokenUrls.add(objectKey);
      throw StateError('원격 이미지를 불러오지 못했습니다($objectKey): HTTP ${response.statusCode}');
    }

    final Uint8List bytes = response.bodyBytes;
    if (!looksLikeImageBytes(bytes)) {
      _brokenUrls.add(objectKey);
      final String reason = isGitLfsPointer(bytes)
          ? 'Git LFS 포인터 텍스트가 대신 내려왔습니다(리포의 LFS 설정을 확인하세요)'
          : '이미지가 아닌 응답입니다(HTML 에러 페이지, 레이트리밋 안내 등)';
      throw StateError('원격 이미지가 유효한 바이너리가 아닙니다($objectKey): $reason');
    }
    return bytes;
  }

  /// [objectKey]를 [_rateLimitCooldown] 동안 일시 차단하고, 같은 시각을
  /// 전역 쿨다운([_globalRateLimitCooldownUntil])으로도 승격한다 — 이후
  /// 다른 objectKey들은 [_fetchRemoteValidatedBytes]가 네트워크 요청조차
  /// 보내지 않고 곧바로 실패 처리한다. 이번 세션에서 처음 겪는 429라면
  /// 딱 한 번만 안내 로그를 남긴다 — 레이트리밋 중에는 서로 다른 수십 개
  /// objectKey가 동시에 429를 맞을 수 있어서, 매번 찍으면 터미널이
  /// 도배된다.
  static void _markRateLimited(String objectKey) {
    final DateTime cooldownUntil = DateTime.now().add(_rateLimitCooldown);
    _rateLimitedUntil[objectKey] = cooldownUntil;
    _globalRateLimitCooldownUntil = cooldownUntil;
    if (_hasAnnouncedRateLimit) {
      return;
    }
    _hasAnnouncedRateLimit = true;
    debugPrint(
      '[RemoteSpriteLoader] 원격 저장소 요청 레이트리밋(429)에 걸렸습니다 — '
      '${_rateLimitCooldown.inMinutes}분간 모든 원격 이미지 요청을 보내지 않고 '
      '도형으로 조용히 대체합니다. 이 안내는 이번 세션에서 다시 출력되지 않습니다.',
    );
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
