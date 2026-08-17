import '../models/equipment.dart' show ItemGrade;
import 'asset_paths.dart';

/// Central registry of image paths — 전부 [AssetPaths.baseUrl] 아래의
/// GitHub 원격 URL을 가리킨다(더 이상 로컬 assets가 아니다). 참조는 항상
/// 이 클래스를 통해서 하고(원시 문자열 금지), 항상 [CustomSafeImage]로
/// 불러온다 — 네트워크 실패 시 자동으로 placeholder로 대체된다.
class AppImages {
  const AppImages._();

  // Equipment icons
  static const String swordLegendary =
      '${AssetPaths.baseUrl}assets/icons/sword_legendary.png';
  static const String shieldRare = '${AssetPaths.baseUrl}assets/icons/shield_rare.png';
  static const String armorEpic = '${AssetPaths.baseUrl}assets/icons/armor_epic.png';
  static const String ringMythic = '${AssetPaths.baseUrl}assets/icons/ring_mythic.png';

  // Skill icons
  static const String skillFire = '${AssetPaths.baseUrl}assets/icons/skill_fire.png';
  static const String skillWater = '${AssetPaths.baseUrl}assets/icons/skill_water.png';
  static const String skillLightning =
      '${AssetPaths.baseUrl}assets/icons/skill_lightning.png';

  // Currency icons
  static const String iconGold = '${AssetPaths.baseUrl}assets/icons/icon_gold.png';
  static const String iconGem = '${AssetPaths.baseUrl}assets/icons/icon_gem.png';

  // Backgrounds / large art
  static const String battleBackground =
      '${AssetPaths.baseUrl}assets/images/battle_background.png';

  // Player character art — assets/images/player/{GRADE}/{characterId}/ 아래
  // 정면/측면/피격/공격/썸네일/성급 일러스트가 전부 들어간다. [characterId]는
  // Equipment.gradeBadgeLabel(예: "N1")과 동일한 형식이고, {GRADE} 폴더(N, R,
  // SR...)는 characterId에서 끝의 숫자(subId)만 떼어내면 그대로 나온다
  // ("N1" → "N", "SSSR3" → "SSSR") — grade.displayName 자체가 항상 순수
  // 알파벳이라 안전하게 정규식으로 벗겨낼 수 있다. 아직 그려지지 않은 등급은
  // CustomSafeImage가 알아서 placeholder로 대체하므로 호출부에서 존재
  // 여부를 따로 확인할 필요는 없다.
  static final RegExp _trailingSubId = RegExp(r'[0-9]+$');

  static String _gradeFolder(String characterId) =>
      characterId.replaceAll(_trailingSubId, '');

  static String _playerDir(String characterId) =>
      'assets/images/player/${_gradeFolder(characterId)}/$characterId';

  static String playerFront(String characterId) => AssetPaths.resolve(
    '${_playerDir(characterId)}/player_${characterId.toLowerCase()}_front.png',
  );

  static String playerSide(String characterId) => AssetPaths.resolve(
    '${_playerDir(characterId)}/player_${characterId.toLowerCase()}_side.png',
  );

  static String playerHit(String characterId) => AssetPaths.resolve(
    '${_playerDir(characterId)}/player_${characterId.toLowerCase()}_hit.png',
  );

  static String playerAttack(String characterId) => AssetPaths.resolve(
    '${_playerDir(characterId)}/player_${characterId.toLowerCase()}_attack.png',
  );

  /// 달리기/공격 프레임 시퀀스 — `player_{id}_run1~5.png`,
  /// `player_{id}_attack1~5.png`. 아직 N1만 실제로 프레임이 준비돼 있고,
  /// 프레임이 없는(404) 캐릭터는 PlayerAnimationComponent가 기존 단일
  /// 이미지([playerSide]/[playerAttack])로 자동 대체한다 — 호출부에서
  /// 존재 여부를 따로 확인할 필요는 없다.
  static String playerActionFrame(String characterId, String action, int frameIndex) =>
      AssetPaths.resolve(
        '${_playerDir(characterId)}/player_${characterId.toLowerCase()}_$action$frameIndex.png',
      );

  /// 뼈대 애니메이션(Skeletal Animation)/스킨 교체용으로 부위별로 쪼갠
  /// 파츠 이미지 — `assets/images/player/{GRADE}/{characterId}/part/`
  /// 아래에 놓인다. [partFileName]은 확장자를 포함한 실제 파일명
  /// (예: `armored_foot_l.png`) 그대로 넘긴다 — 이 클래스는 어떤 파츠가
  /// 존재하는지 알지 못하고 그냥 경로만 조립한다. 캐릭터별로 어떤 파츠가
  /// 있는지(고정 상수 목록)는 [PlayerN1Assets]처럼 캐릭터 전용 클래스가
  /// 관리한다.
  static String playerPart(String characterId, String partFileName) =>
      AssetPaths.resolve('${_playerDir(characterId)}/part/$partFileName');

  /// 얼굴~어깨만 예쁘게 잘려있는 전용 썸네일 — 작은 슬롯/팝업 헤더에서
  /// [playerFront]를 억지로 확대/크롭하는 대신 이 파일을 그대로 쓴다.
  static String playerThumbnail(String characterId) => AssetPaths.resolve(
    '${_playerDir(characterId)}/player_${characterId.toLowerCase()}_thumbnail.png',
  );

  // Pet art — assets/images/pet/{GRADE}/{petId}/ 아래 정면 이미지가
  // 들어간다. [petId]는 [playerFront]의 characterId와 동일한 형식
  // (Equipment.gradeBadgeLabel, 예: "N1")이고, 등급 폴더도 같은 규칙
  // ([_gradeFolder])으로 뗀다 — 캐릭터/펫이 [Equipment] 하나를 공유하는
  // 구조라 id 형식도 동일하다.
  static String _petDir(String petId) => 'assets/images/pet/${_gradeFolder(petId)}/$petId';

  static String petFront(String petId) =>
      AssetPaths.resolve('${_petDir(petId)}/pet_${petId.toLowerCase()}_front.png');

  /// 성급(★0~5) 해금 일러스트 — Live2D풍으로 움직이는 애니메이션(.webp)이
  /// 우선 시도된다. 아직 애니메이션 작업이 안 된 캐릭터는 이 경로가 404로
  /// 실패하므로, 호출부는 반드시 [characterStarFallback](같은 파일명의
  /// 기존 정지 .png)을 [CustomSafeImage.fallbackPath]로 함께 넘겨서 자동
  /// 대체되게 해야 한다 — 이 함수 하나만으로는 아직 웹툰이 없는 캐릭터가
  /// 깨져 보인다.
  static String characterStar(String characterId, int level) =>
      AssetPaths.resolve('${_playerDir(characterId)}/illustration/star$level.webp');

  /// [characterStar](.webp)가 아직 없어서(404 등) 실패했을 때 자동으로
  /// 대신 불러오는 기존 정지 일러스트 — 파일명은 같고 확장자만 .png.
  static String characterStarFallback(String characterId, int level) =>
      AssetPaths.resolve('${_playerDir(characterId)}/illustration/star$level.png');

  /// 호감도 화면 전용 일러스트(레벨 1~10) — 파일명은 `heart1`~`heart10`.
  /// [characterStar]류(성급 ★0~5, `star$level`)와는 별개 자산이다. 정지
  /// 프레임은 이 함수(.png), Live2D풍 애니메이션은
  /// [affectionIllustrationAnimated](.webp)를 쓴다 — 어느 쪽을 부를지는
  /// 재생/일시정지 상태에 따라 호출부([AffectionScreen])가 고른다. 서약
  /// (Oath) 여부와 무관하게 항상 이 파일명 규칙 그대로다 — 원격 레포 실제
  /// 구조 확인 결과 `_oath` 접미사가 붙은 별도 파일은 존재하지 않는다(예전
  /// 코드가 `heart${level}_oath.png`를 만들어 404를 유발했었다).
  static String affectionIllustration(String characterId, int level) =>
      AssetPaths.resolve('${_playerDir(characterId)}/illustration/heart$level.png');

  /// [affectionIllustration]의 애니메이션(.webp) 버전 — 재생 상태일 때만
  /// 불러온다.
  static String affectionIllustrationAnimated(String characterId, int level) =>
      AssetPaths.resolve('${_playerDir(characterId)}/illustration/heart$level.webp');

  /// 스토리(프롤로그) 대화창 뒤에 까는 배경 맵 이미지 — [sceneId]는
  /// "prologue" 형식. 시즌1 메인 스토리(챕터 1~10)는 실제 원격 레포에
  /// 등록된 전용 일러스트가 따로 있어 [chapterMemoryIllustration]을 쓴다.
  static String storyBackground(String sceneId) =>
      AssetPaths.resolve('assets/images/story/$sceneId/background.png');

  /// 시즌1 메인 스토리 챕터별 회상(memory) 일러스트 — 오프닝/보스 대화
  /// 화면 배경으로 쓰인다. 예: 1장 -> `memory/chapter1/memory_1-1.png`,
  /// 10장 -> `memory/chapter10/memory_10-1.png`.
  static String chapterMemoryIllustration(int chapterNumber) =>
      AssetPaths.resolve('assets/images/memory/chapter$chapterNumber/memory_$chapterNumber-1.png');

  /// 실제로 그려진 배경 아트가 존재하는 챕터 수 — bg_chapter1_*.png ~
  /// bg_chapter10_*.png만 원격 레포에 등록되어 있다.
  static const int _battleBackgroundChapterCount = 10;

  /// 챕터 진행에는 끝이 없지만(엔드리스) 배경 아트는 1~10장뿐이라, 10장을
  /// 넘어가면 다시 1장부터 순환 재사용한다(Dart의 `%`는 항상 0 이상을
  /// 반환하므로 [chapterNumber]가 0 이하로 들어와도 안전하다).
  static int _cyclicBattleChapter(int chapterNumber) =>
      ((chapterNumber - 1) % _battleBackgroundChapterCount) + 1;

  /// 인게임 전투 화면의 다중 레이어 패럴랙스 중 "먼 배경" 레이어 —
  /// 완전히 정지된(baseVelocity 0) 원경. 스토리 컷씬 배경([storyBackground])
  /// 과는 별개의 전용 에셋. [chapterNumber]는 GameManager.chapterOf(절대
  /// 스테이지) 값을 그대로 넘기면 된다.
  static String chapterBackgroundBack(int chapterNumber) => AssetPaths.resolve(
      'assets/images/background/bg_chapter${_cyclicBattleChapter(chapterNumber)}_back.png');

  /// 다중 레이어 패럴랙스의 "바닥/땅" 레이어 이미지 경로 — 캐릭터의
  /// 발걸음 속도에 맞춰 좌→우로 빠르게 무한 스크롤된다(IdleGame의 groundY
  /// 라인 아래에만 그려진다, [ParallaxGroundLayer] 참고). [chapterBackgroundBack]
  /// (먼 배경)과 세트로, 같은 챕터 번호로 순환(cyclic)되는 전용 바닥
  /// 아트를 쓴다 — 1챕터 숲 바닥, 2챕터 버섯 바닥처럼 배경 테마와 함께
  /// 바뀌어야 자연스럽다(예전엔 챕터와 무관하게 `bg_chapter1_ground.png`
  /// 하나로 고정돼 있었지만, 배경만 바뀌고 바닥은 그대로라 테마가 어긋나
  /// 보이는 문제가 있어 챕터별 세트로 바꿨다). `assets/images/background/`
  /// 폴더 밑에 `bg_chapter{N}_ground.png` 이름으로 올려야 한다.
  ///
  /// [주의] 이 프로젝트의 인게임 이미지는 로컬 pubspec.yaml assets가 아니라
  /// **원격 GitHub 레포**(https://github.com/kkthkkth/cyber_breaker_idle_images)
  /// 에서 [RemoteSpriteLoader]가 직접 내려받는다 — 로컬 프로젝트의
  /// `assets/images/` 폴더에 파일을 넣는 것만으로는 아무 효과가 없고,
  /// 반드시 그 원격 레포의 같은 경로에 파일을 올려야 한다. 아직 해당
  /// 챕터의 전용 바닥 아트가 준비되지 않았다면(404) [RemoteSpriteLoader]가
  /// 조용히 이전 타일을 유지하므로([IdleGame._loadGroundTile] 참고) 갑자기
  /// 화면이 깨지지는 않는다 — 다만 시각적으로는 이전 챕터 바닥이 그대로
  /// 남으므로, 실제로 세트를 갖추려면 각 챕터 폴더에 파일을 올려야 한다.
  static String groundTile(int chapterNumber) => AssetPaths.resolve(
      'assets/images/background/bg_chapter${_cyclicBattleChapter(chapterNumber)}_ground.png');

  /// 상점 물약 아이콘 — `consumable_items` 테이블에 `icon_path` 컬럼이
  /// 없어서, [grade]만으로 경로를 계산한다(등급별 물약 아이콘 하나씩만
  /// 있으면 충분하다는 전제 — 같은 등급 물약이 여러 종류로 늘어나면 이
  /// 함수에 이름/ID 기반 구분을 추가해야 한다). `assets/images/items/potion/`
  /// 폴더 밑에 `{grade}.png`(예: `n.png`, `ssr.png`) 이름으로 올리면 된다.
  static String potionIcon(ItemGrade grade) =>
      AssetPaths.resolve('assets/images/items/potion/${grade.name}.png');

  /// 상점 호감도 아이템 아이콘 — 물약과 달리 등급 컬럼이 없어서, 대신
  /// 구매 재화 티어(코인/보석)로 구분한다. `assets/images/items/affection/`
  /// 폴더 밑에 `coin.png`/`gem.png` 두 장만 올리면 된다.
  static String affectionGiftIcon({required bool isGemTier}) => AssetPaths.resolve(
      'assets/images/items/affection/${isGemTier ? 'gem' : 'coin'}.png');

  /// 월드보스 입장 충전권 아이콘 — 종류가 하나뿐이라(등급/티어 구분 없음)
  /// 고정 경로 하나로 충분하다. `assets/images/items/ticket/world_boss.png`
  /// 로 올리면 된다.
  static String ticketIcon() =>
      AssetPaths.resolve('assets/images/items/ticket/world_boss.png');
}
