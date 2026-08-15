/// GitHub 원격 이미지 저장소의 Base URL과, 로컬 상대 경로("assets/images/...")
/// 를 그 아래의 전체 네트워크 URL로 바꿔주는 유틸리티. 프로젝트 전체의
/// 이미지 경로가 로컬 assets에서 원격 URL로 넘어가는 지점이 이 클래스
/// 하나뿐이라, 나중에 저장소를 옮기거나 CDN을 앞단에 두게 되면 [baseUrl]
/// 하나만 바꾸면 된다.
///
/// player 폴더뿐 아니라 앞으로 monster/equipment/pet 등 어떤 하위 폴더가
/// 추가되더라도, 그 폴더 밑의 상대 경로 문자열만 조합해서 [resolve]에
/// 넘기면 그대로 전체 URL이 된다 — 폴더별로 별도 메서드를 새로 만들
/// 필요가 없다.
class AssetPaths {
  const AssetPaths._();

  static const String baseUrl =
      'https://raw.githubusercontent.com/kkthkkth/cyber_breaker_idle_images/main/';

  /// "assets/images/player/N/N1/player_n1_front.png" 같은 상대 경로를
  /// [baseUrl] 아래의 전체 https URL로 변환한다. 맨 앞에 슬래시가 붙어
  /// 있어도(`/assets/...`) 없어도(`assets/...`) 결과가 같도록 정규화한다.
  static String resolve(String relativePath) {
    final String normalized =
        relativePath.startsWith('/') ? relativePath.substring(1) : relativePath;
    return '$baseUrl$normalized';
  }
}
