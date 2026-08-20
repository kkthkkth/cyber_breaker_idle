import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Common image renderer (this project's "CustomImageWidget"): draws from a
/// local `assets/` path or a Supabase Storage-hosted network URL (see
/// lib/constants/asset_paths.dart / app_images.dart) — falling back to a
/// placeholder instead of crashing when the asset/URL is unreachable, and
/// showing a small loading indicator while a network image downloads.
///
/// Use this everywhere in the game UI instead of `Image.asset`/`Image.network`
/// directly: CustomSafeImage(path: AppImages.iconGold, width: 24, height: 24)
/// `path` may be a local asset path or an `http(s)://` URL — which renderer
/// is used is decided automatically. Network paths go through
/// [CachedNetworkImage] so repeat loads (re-opening the same dialog, scrolling
/// a grid back into view, ...) reuse the on-disk cache instead of
/// re-downloading from Supabase Storage every time.
///
/// Animated `.webp` is special-cased to bypass [CachedNetworkImage]
/// entirely: `cached_network_image` renders through the `octo_image`
/// package, which in practice has been observed to freeze animated WebP on
/// its first frame (the multi-frame codec is decoded fine, but the extra
/// placeholder/frame-builder plumbing `octo_image` wraps around the
/// underlying [Image] never drives it past frame 0). Plain [Image.network]/
/// [Image.asset] don't have that problem — Flutter's own [Image] widget
/// animates and loops multi-frame codecs natively with zero extra app code.
/// So `.webp` paths skip the cache-manager layer and go straight to
/// [Image.network]/[Image.asset] (no on-disk caching for those specifically,
/// but the framework's in-memory [ImageCache] still avoids re-decoding a
/// [key]-stable image across rebuilds — see below). Every other extension
/// keeps using [CachedNetworkImage] as before, for its disk caching.
///
/// [주의] 네트워크 경로는 성공도 실패도 아닌 채로 멈춰 있을 수 있다(DNS
/// 문제, 응답 없는 연결 등) — `Image.network`/`CachedNetworkImage` 둘 다
/// 기본적으로 타임아웃이 없어서, 이런 경우 로딩 스피너가 무한히 돈다(호감도
/// "영상"/성급 일러스트처럼 원격 레포에서 큰 .webp를 받아오는 화면에서
/// 특히 체감된다). 그래서 이 위젯은 [_networkTimeout] 안에 성공/실패 어느
/// 쪽으로도 결론이 안 나면 강제로 실패 처리해 [fallbackPath]/placeholder로
/// 넘어간다([_CustomSafeImageState] 참고).
///
/// 한 번 실패가 확인된 URL은 [_CustomSafeImageState._brokenUrls]에 세션
/// 동안 기록돼, 같은 URL을 쓰는 다른 인스턴스(다른 화면/그리드 셀 등)는
/// 재시도 없이 곧바로 대체 화면으로 넘어간다 — Git LFS 텍스트 포인터나
/// 레이트리밋 응답처럼 디코딩 자체가 애초에 불가능한 URL을 여러 위젯이
/// 각자 반복 요청+실패 로그를 쌓는 것을 막는다.
class CustomSafeImage extends StatefulWidget {
  CustomSafeImage({
    Key? key,
    required this.path,
    this.fallbackPath,
    this.fallbackBuilder,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.filterQuality = FilterQuality.medium,
  }) : super(key: key ?? ValueKey('$path|$fallbackPath'));

  final String path;

  /// [path](와 있다면 [fallbackPath]까지) 로드가 최종적으로 실패했을 때
  /// 기본 회색 placeholder([_CustomSafeImageState._errorPlaceholder]) 대신
  /// 보여줄 위젯 — 예: [TitleBadge]가 칭호 webp 로드 실패 시 이름 텍스트
  /// 배지로 대체하는 용도. null이면(기본값) 기존과 동일하게 회색
  /// placeholder를 그린다.
  final WidgetBuilder? fallbackBuilder;

  /// [path] 로드가 실패하면(예: 아직 준비되지 않은 애니메이션 .webp, 디코딩
  /// 실패, 또는 타임아웃) 대신 시도할 경로 — 그마저 실패하면 최종적으로
  /// 회색 placeholder를 보여준다([_CustomSafeImageState._errorPlaceholder]).
  /// null이면 기존과 동일하게 [path] 실패 시 바로 placeholder로 간다. 예:
  /// 캐릭터 일러스트는 Live2D풍 .webp를 우선 시도하고, 아직 준비 안 된
  /// 캐릭터는 기존 정지 .png로 조용히 대체한다([AppImages.characterStar]/
  /// [AppImages.characterStarFallback], 호감도 화면의 heart 일러스트도
  /// 같은 관례를 따른다).
  final String? fallbackPath;

  final double? width;
  final double? height;
  final BoxFit fit;

  /// [FilterQuality.none]으로 넘기면 확대해도 흐려지지 않는다 — 픽셀 아트를
  /// Transform.scale 등으로 확대해서 보여줄 때 쓴다(기본값은 Image 위젯의
  /// 기본값과 동일한 medium이라 기존 호출부는 그대로 동작한다).
  final FilterQuality filterQuality;

  bool get isNetwork => path.startsWith('http://') || path.startsWith('https://');

  bool get isWebp => path.toLowerCase().endsWith('.webp');

  @override
  State<CustomSafeImage> createState() => _CustomSafeImageState();
}

class _CustomSafeImageState extends State<CustomSafeImage> {
  /// 한 번이라도 로드에 실패한 것으로 확인된 네트워크 URL — 세션 동안 다시
  /// 시도하지 않는다([RemoteSpriteLoader]/[SoundManager]의 `_brokenFiles`와
  /// 같은 회로 차단기 관례). 같은 깨진 썸네일이 그리드/리스트 여러 곳에
  /// 동시에 쓰이면(예: 캐릭터 목록에 같은 캐릭터가 여러 번 등장) 각
  /// 인스턴스가 독립적으로 네트워크 요청 + 디코딩 실패 + 에러 로그를
  /// 반복했던 것을, 한 번 실패가 확인된 URL은 이후 어떤 인스턴스도 즉시
  /// 대체 화면으로 넘어가게 해서 막는다 — 그 자체로 로그도 URL당 한 번만
  /// 찍히게 된다(반복 인스턴스는 애초에 [errorBuilder]/[errorWidget]까지
  /// 도달하지 않으므로).
  static final Set<String> _brokenUrls = {};

  /// 네트워크 요청이 이 시간 안에 성공도 실패도 아닌 채로 멈춰 있으면
  /// 강제로 실패 처리한다 — 로컬 asset은 디스크에서 즉시 성공/실패가
  /// 갈리므로(무한정 멈출 이유가 없다) 네트워크 경로에만 적용한다. 위젯의
  /// [ValueKey]가 `path`/`fallbackPath` 조합마다 다르므로, 경로가 바뀌면
  /// 항상 새 State(= 새 타이머)로 시작한다.
  static const Duration _networkTimeout = Duration(seconds: 8);

  Timer? _timeoutTimer;

  /// 성공(이미지가 실제로 화면에 그려짐) 또는 실패(errorBuilder가 이미
  /// 한 번 불림)로 이미 결론이 난 뒤에는 타임아웃이 뒤늦게 발동해 멀쩡히
  /// 뜬 이미지를 다시 placeholder로 덮어쓰는 일이 없도록 막는 가드.
  bool _settled = false;

  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    if (widget.isNetwork) {
      _timeoutTimer = Timer(_networkTimeout, () {
        if (!_settled && mounted) {
          debugPrint(
            '[AssetLoadError] Timed out after ${_networkTimeout.inSeconds}s: ${widget.path}',
          );
          setState(() => _timedOut = true);
        }
      });
    }
  }

  void _markSettled() {
    if (_settled) {
      return;
    }
    _settled = true;
    _timeoutTimer?.cancel();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  Widget _errorPlaceholder(BuildContext context) {
    final WidgetBuilder? fallbackBuilder = widget.fallbackBuilder;
    if (fallbackBuilder != null) {
      return fallbackBuilder(context);
    }
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.image,
        color: Colors.grey,
        size: (widget.width ?? widget.height ?? 24) * 0.6,
      ),
    );
  }

  Widget _loadingPlaceholder(BuildContext context) {
    final double indicatorSize = (widget.width ?? widget.height ?? 24) * 0.4;
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: SizedBox(
        width: indicatorSize,
        height: indicatorSize,
        child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
      ),
    );
  }

  /// [widget.path](또는 타임아웃)가 실패했을 때 보여줄 위젯 —
  /// [widget.fallbackPath]가 있으면 그 경로로(더 이상 fallback 없이)
  /// 재귀적으로 다시 시도하고, 없으면 바로 회색 placeholder. 재귀 호출
  /// 한 번으로 끝나므로("webp 실패 → png 시도, png도 실패하면 그때
  /// placeholder") 무한 루프 걱정은 없다 — fallback 시도 자체도 새
  /// [CustomSafeImage](=새 State=새 타이머)라 자체적으로 타임아웃 보호를
  /// 받는다.
  Widget _buildFallbackOrPlaceholder(BuildContext context) {
    final String? fallback = widget.fallbackPath;
    if (fallback == null) {
      return _errorPlaceholder(context);
    }
    return CustomSafeImage(
      path: fallback,
      fallbackBuilder: widget.fallbackBuilder,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      filterQuality: widget.filterQuality,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_timedOut || (widget.isNetwork && _brokenUrls.contains(widget.path))) {
      return _buildFallbackOrPlaceholder(context);
    }

    if (widget.isNetwork) {
      if (widget.isWebp) {
        return Image.network(
          widget.path,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          filterQuality: widget.filterQuality,
          loadingBuilder: (context, child, progress) {
            if (progress != null) {
              return _loadingPlaceholder(context);
            }
            _markSettled();
            return child;
          },
          errorBuilder: (context, error, stackTrace) {
            _markSettled();
            _brokenUrls.add(widget.path);
            debugPrint(
              '[AssetLoadError] Failed to load: ${widget.path}, exception: $error, stack: $stackTrace',
            );
            return _buildFallbackOrPlaceholder(context);
          },
        );
      }
      return CachedNetworkImage(
        imageUrl: widget.path,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        filterQuality: widget.filterQuality,
        placeholder: (context, url) => _loadingPlaceholder(context),
        imageBuilder: (context, imageProvider) {
          _markSettled();
          return Image(
            image: imageProvider,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            filterQuality: widget.filterQuality,
          );
        },
        errorWidget: (context, url, error) {
          _markSettled();
          _brokenUrls.add(widget.path);
          debugPrint(
            '[AssetLoadError] Failed to load: $url, exception: $error, stack: null',
          );
          return _buildFallbackOrPlaceholder(context);
        },
      );
    }

    return Image.asset(
      widget.path,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      filterQuality: widget.filterQuality,
      errorBuilder: (context, error, stackTrace) {
        debugPrint(
          '[AssetLoadError] Failed to load: ${widget.path}, exception: $error, stack: $stackTrace',
        );
        return _buildFallbackOrPlaceholder(context);
      },
    );
  }
}
