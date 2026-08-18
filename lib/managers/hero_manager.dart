import 'package:flutter/material.dart';

/// `hero.png`(assets/raw/hero.png를 배경 제거해 assets/images/hero.png로
/// 저장한 결과물) 캐릭터 아트를 불러오는 전용 매니저 — 이 프로젝트의 다른
/// 매니저들과 같은 싱글턴 관례([instance] 정적 필드)를 따른다.
///
/// [주의] 이 프로젝트의 인게임 캐릭터 아트(챕터/스테이지에서 실제로
/// 그려지는 플레이어 스프라이트)는 로컬 pubspec.yaml assets가 아니라
/// 원격 Supabase Storage 버킷([AppImages]/`RemoteSpriteLoader` 참고)에서
/// 내려받는 별도 파이프라인이다. 이 매니저가 관리하는 `hero.png`는 그것과
/// 무관한, pubspec.yaml에 이미 등록되어 있는 `assets/images/` 디렉터리를
/// 통해 앱 번들에 직접 포함되는 순수 로컬 정적 에셋이다 — 원격 캐릭터 아트
/// 시스템에 편입하고 싶다면 그 Storage 버킷의 같은 경로에도 파일을 올려야
/// 한다(이 매니저만으로는 안 된다).
class HeroManager {
  HeroManager._internal();

  static final HeroManager instance = HeroManager._internal();

  /// 배경을 제거한 히어로 아트의 로컬 asset 경로 — pubspec.yaml의
  /// `assets/images/` 디렉터리가 이미 통째로 등록돼 있어 별도 설정 없이
  /// 앱 번들에 포함된다.
  static const String heroImagePath = 'assets/images/hero.png';

  /// 화면에 그대로 붙일 수 있는 위젯 — 파일이 없거나 손상됐을 때 앱이
  /// 죽지 않도록 [errorBuilder]로 조용히 placeholder 아이콘으로 대체한다
  /// (CustomSafeImage가 원격 이미지 404를 조용히 넘기는 것과 같은 이유).
  Widget buildHeroSprite({double? width, double? height, BoxFit fit = BoxFit.contain}) {
    return Image.asset(
      heroImagePath,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        debugPrint('[HeroManager] hero.png 로드 실패: $error');
        return const Icon(Icons.person, size: 48, color: Colors.white24);
      },
    );
  }

  /// 화면이 실제로 그리기 전에 이미지를 미리 디코딩해 이미지 캐시에
  /// 올려 둔다 — 처음 등장하는 프레임에서 로딩 지연/깜빡임 없이 바로
  /// 보이게 하고 싶을 때(예: 진입 애니메이션 직전) 호출한다.
  Future<void> preload(BuildContext context) {
    return precacheImage(const AssetImage(heroImagePath), context);
  }
}
