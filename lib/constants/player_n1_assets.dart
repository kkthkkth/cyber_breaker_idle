import 'app_images.dart';
import 'asset_paths.dart';

/// 'N1' 캐릭터의 리소스 경로를 한곳에 모아 상수로 참조하는 클래스 —
/// 뼈대 애니메이션(Skeletal Animation)/스킨 교체 시스템 도입을 앞두고,
/// 부위별로 쪼갠 파츠 이미지들을 체계적으로 관리하기 위해 만들었다.
///
/// [주의] 이 프로젝트의 게임 아트는 로컬 `pubspec.yaml` assets가 아니라
/// 전부 원격 Supabase Storage 버킷([AssetPaths.bucketName])에서
/// [RemoteSpriteLoader]가 런타임에 직접 내려받는다([AppImages] 상단 문서
/// 참고). 여기 상수들도 실제 파일이 아니라 그 원격 URL 문자열이다 —
/// `pubspec.yaml`에 등록하거나 로컬 `assets/` 폴더에 파일을 복사해 둘
/// 필요가 전혀 없고, 이미 그 버킷에 올려둔 것으로 충분하다.
class PlayerN1Assets {
  const PlayerN1Assets._();

  static const String characterId = 'N1';

  // ── 기본 포즈 / 프레임 애니메이션 (SIDE BAR) ──────────────────────
  // 이미 AppImages의 범용 메서드가 처리하는 파일들이라 URL을 새로 만들지
  // 않고 그대로 위임한다 — 원본 파일 경로 규칙이 바뀌면 AppImages 한
  // 곳만 고치면 여기도 자동으로 맞는다.
  static String get front => AppImages.playerFront(characterId);
  static String get hit => AppImages.playerHit(characterId);

  /// N1의 run 프레임은 3장뿐이다(다른 캐릭터/공격 모션의 5장 기준과
  /// 다르다) — [PlayerAnimationComponent]의 5장 고정 로직과는 별개로,
  /// 이 상수를 직접 쓸 땐 이 개수(3)를 그대로 frameCount로 넘겨야 한다.
  static const int runFrameCount = 3;
  static List<String> get runFrames => List.generate(
    runFrameCount,
    (i) => AppImages.playerActionFrame(characterId, 'run', i + 1),
  );

  static const int attackFrameCount = 5;
  static List<String> get attackFrames => List.generate(
    attackFrameCount,
    (i) => AppImages.playerActionFrame(characterId, 'attack', i + 1),
  );

  // ── 스킨 파츠 (MAIN VIEW, Skeletal Animation/Skinning용) ──────────
  // `assets/images/player/N/N1/part/` 아래. 파일명 자체가 나중에 Spine
  // 등에서 쓸 스킨 슬롯 이름과 대응하므로, 상수 이름도 파일명을 그대로
  // 따라간다(무엇을 조립하는지 한눈에 알아보기 위함).
  static const String _partDir = '${AssetPaths.baseUrl}assets/images/player/N/N1/part/';

  static const String armLFore = '${_partDir}armored_arm_l_fore.png';
  static const String armLUpper = '${_partDir}armored_arm_l_upper.png';
  static const String armRFore = '${_partDir}armored_arm_r_fore.png';
  static const String armRUpper = '${_partDir}armored_arm_r_upper.png';
  static const String calfL = '${_partDir}armored_calf_l.png';
  static const String calfR = '${_partDir}armored_calf_r.png';
  static const String footL = '${_partDir}armored_foot_l.png';
  static const String footR = '${_partDir}armored_foot_r.png';
  static const String handL = '${_partDir}armored_hand_l.png';
  static const String handR = '${_partDir}armored_hand_r.png';
  static const String thighL = '${_partDir}armored_thigh_l.png';
  static const String thighR = '${_partDir}armored_thigh_r.png';

  /// 스킨 슬롯 이름 → URL 매핑 — Spine 같은 뼈대 라이브러리를 붙일 때
  /// "이 슬롯엔 이 이미지를 입힌다"는 스킨 정의를 그대로 이 맵에서
  /// 가져다 쓸 수 있도록 미리 구조화해 뒀다. 키는 파일명에서 확장자를
  /// 뗀 값 — Spine 에디터에서 attachment 이름을 지을 때도 보통 이
  /// 컨벤션을 따른다. [player_skin_loader.dart]의 `loadN1SkinParts()`가
  /// 이 맵을 그대로 순회해 전 파츠를 한 번에 내려받는다.
  static const Map<String, String> partsBySlot = {
    'armored_arm_l_fore': armLFore,
    'armored_arm_l_upper': armLUpper,
    'armored_arm_r_fore': armRFore,
    'armored_arm_r_upper': armRUpper,
    'armored_calf_l': calfL,
    'armored_calf_r': calfR,
    'armored_foot_l': footL,
    'armored_foot_r': footR,
    'armored_hand_l': handL,
    'armored_hand_r': handR,
    'armored_thigh_l': thighL,
    'armored_thigh_r': thighR,
  };
}
