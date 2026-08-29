/// 로컬 상대 경로("assets/images/player/N/N1/player_n1_front.png" 형태)를
/// 정규화하는 유틸리티 — 맨 앞에 슬래시가 붙어 있어도(`/assets/...`)
/// 없어도(`assets/...`) 결과가 같도록 통일한다.
///
/// [이력] 원래는 Supabase Storage 공개 버킷의 전체 URL로 바꿔주는 역할까지
/// 했다(`baseUrl` 상수 + `resolve()`가 그 접두어를 붙였고, 그 전에는
/// GitHub raw 저장소를 직접 썼다). 지금은 R2가 **비공개** 버킷으로
/// 바뀌면서 클라이언트가 "공개 URL"이라는 개념 자체를 몰라도 된다 — 대신
/// 이 상대 경로 자체가 Cloudflare R2의 objectKey가 되고, [StorageManager]
/// (`lib/managers/storage_manager.dart`)가 Supabase Edge Function
/// (`get-r2-url`)에 그 키를 넘겨 요청할 때마다 짧은 유효기간(1시간)의
/// 서명 URL을 발급받는다 — R2 접근 키가 클라이언트 번들에 전혀 노출되지
/// 않는다는 게 이 전환의 핵심이다. [AppImages]/[PlayerN1Assets]가 계속
/// 이 함수를 거쳐 최종 경로 문자열을 만들므로, 원격 저장 방식이 나중에
/// 또 바뀌어도 고칠 곳은 여전히 이 파일 하나뿐이다.
class AssetPaths {
  const AssetPaths._();

  static String resolve(String relativePath) =>
      relativePath.startsWith('/') ? relativePath.substring(1) : relativePath;
}
