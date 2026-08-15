import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Common image renderer (this project's "CustomImageWidget"): draws from a
/// local `assets/` path or a GitHub-hosted network URL (see
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
/// re-downloading from GitHub every time.
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
class CustomSafeImage extends StatelessWidget {
  CustomSafeImage({
    Key? key,
    required this.path,
    this.fallbackPath,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.filterQuality = FilterQuality.medium,
  }) : super(key: key ?? ValueKey('$path|$fallbackPath'));

  final String path;

  /// [path] 로드가 실패하면(예: 아직 준비되지 않은 애니메이션 .webp)
  /// 대신 시도할 경로 — 그마저 실패하면 그때 최종적으로 회색 placeholder를
  /// 보여준다([_errorPlaceholder]). null이면 기존과 동일하게 [path] 실패
  /// 시 바로 placeholder로 간다. 예: 캐릭터 일러스트는 Live2D풍 .webp를
  /// 우선 시도하고, 아직 준비 안 된 캐릭터는 기존 정지 .png로 조용히
  /// 대체한다([AppImages.characterStar]/[AppImages.characterStarFallback]).
  final String? fallbackPath;

  final double? width;
  final double? height;
  final BoxFit fit;

  /// [FilterQuality.none]으로 넘기면 확대해도 흐려지지 않는다 — 픽셀 아트를
  /// Transform.scale 등으로 확대해서 보여줄 때 쓴다(기본값은 Image 위젯의
  /// 기본값과 동일한 medium이라 기존 호출부는 그대로 동작한다).
  final FilterQuality filterQuality;

  bool get _isNetwork => path.startsWith('http://') || path.startsWith('https://');

  bool get _isWebp => path.toLowerCase().endsWith('.webp');

  Widget _errorPlaceholder(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.image,
        color: Colors.grey,
        size: (width ?? height ?? 24) * 0.6,
      ),
    );
  }

  Widget _loadingPlaceholder(BuildContext context) {
    final double indicatorSize = (width ?? height ?? 24) * 0.4;
    return Container(
      width: width,
      height: height,
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

  /// [path]가 실패했을 때 보여줄 위젯 — [fallbackPath]가 있으면 그 경로로
  /// (더 이상 fallback 없이) 재귀적으로 다시 시도하고, 없으면 바로 회색
  /// placeholder. 재귀 호출 한 번으로 끝나므로("webp 실패 → png 시도, png도
  /// 실패하면 그때 placeholder") 무한 루프 걱정은 없다.
  Widget _buildFallbackOrPlaceholder(BuildContext context) {
    final String? fallback = fallbackPath;
    if (fallback == null) {
      return _errorPlaceholder(context);
    }
    return CustomSafeImage(
      path: fallback,
      width: width,
      height: height,
      fit: fit,
      filterQuality: filterQuality,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isNetwork) {
      if (_isWebp) {
        return Image.network(
          path,
          width: width,
          height: height,
          fit: fit,
          filterQuality: filterQuality,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : _loadingPlaceholder(context),
          errorBuilder: (context, error, stackTrace) => _buildFallbackOrPlaceholder(context),
        );
      }
      return CachedNetworkImage(
        imageUrl: path,
        width: width,
        height: height,
        fit: fit,
        filterQuality: filterQuality,
        placeholder: (context, url) => _loadingPlaceholder(context),
        errorWidget: (context, url, error) => _buildFallbackOrPlaceholder(context),
      );
    }

    return Image.asset(
      path,
      width: width,
      height: height,
      fit: fit,
      filterQuality: filterQuality,
      errorBuilder: (context, error, stackTrace) => _buildFallbackOrPlaceholder(context),
    );
  }
}
