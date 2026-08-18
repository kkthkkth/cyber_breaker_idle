import 'supabase_config.dart';

/// Supabase Storage 원격 이미지 버킷의 Base URL과, 로컬 상대 경로
/// ("assets/images/...")를 그 아래의 전체 네트워크 URL로 바꿔주는
/// 유틸리티. 프로젝트 전체의 이미지 경로가 로컬 assets에서 원격 URL로
/// 넘어가는 지점이 이 클래스 하나뿐이라, 나중에 버킷을 옮기거나 CDN을
/// 앞단에 두게 되면 [baseUrl] 하나만 바꾸면 된다.
///
/// [이력] 원래는 GitHub 저장소(raw.githubusercontent.com)를 직접 썼는데,
/// GitHub의 익명 요청 레이트리밋(429)이 상용 트래픽에서 실제로 걸려서
/// (`RemoteSpriteLoader`의 429 회로 차단기가 그 대응으로 추가된 것) 자체
/// Supabase 프로젝트의 Storage 버킷([bucketName])으로 옮겼다. 프로젝트
/// REF를 이 파일에 별도로 하드코딩하지 않고 [SupabaseConfig.url]에서 그대로
/// 파생시킨다 — 프로젝트 URL이 바뀌어도 이 파일을 따로 고칠 필요가 없고,
/// "Supabase 프로젝트 접속 정보는 SupabaseConfig 하나가 유일한 소스"라는
/// 기존 관례([SupabaseConfig] 문서 참고)가 이미지 경로에도 그대로 이어진다.
///
/// player 폴더뿐 아니라 앞으로 monster/equipment/pet 등 어떤 하위 폴더가
/// 추가되더라도, 그 폴더 밑의 상대 경로 문자열만 조합해서 [resolve]에
/// 넘기면 그대로 전체 URL이 된다 — 폴더별로 별도 메서드를 새로 만들
/// 필요가 없다.
class AssetPaths {
  const AssetPaths._();

  /// 게임 이미지를 담는 Supabase Storage 버킷 이름 — 이 버킷은 반드시
  /// "Public" 버킷이어야 하고(아니면 아래 `/object/public/` 경로 자체가
  /// 404/400을 반환한다), `storage.objects`에 누구나 읽을 수 있는 RLS
  /// SELECT 정책도 있어야 한다(둘 다 이 프로젝트 루트의
  /// `supabase/storage_game_assets_policy.sql` 참고).
  static const String bucketName = 'game-assets';

  /// Supabase Storage Public URL 구조:
  /// `https://<project-ref>.supabase.co/storage/v1/object/public/<bucket>/`.
  /// [SupabaseConfig.url]이 이미 `https://<project-ref>.supabase.co`
  /// 형태라 뒤에 경로만 이어 붙이면 된다.
  static const String baseUrl = '${SupabaseConfig.url}/storage/v1/object/public/$bucketName/';

  /// "assets/images/player/N/N1/player_n1_front.png" 같은 상대 경로를
  /// [baseUrl] 아래의 전체 https URL로 변환한다. 맨 앞에 슬래시가 붙어
  /// 있어도(`/assets/...`) 없어도(`assets/...`) 결과가 같도록 정규화한다.
  static String resolve(String relativePath) {
    final String normalized =
        relativePath.startsWith('/') ? relativePath.substring(1) : relativePath;
    return '$baseUrl$normalized';
  }
}
