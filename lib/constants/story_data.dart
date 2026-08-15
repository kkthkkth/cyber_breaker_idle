import '../models/story_model.dart';
import 'app_images.dart';

/// [StoryLine] 하나를 짧게 만드는 헬퍼 — [thumbnailCharacterId]는 항상
/// 실제로 존재하는(에셋 레포에 등록된) 캐릭터 ID여야 한다("N1", "SR2" 등).
StoryLine _line(String speaker, String thumbnailCharacterId, String text) {
  return StoryLine(
    speaker: speaker,
    thumbnailUrl: AppImages.playerThumbnail(thumbnailCharacterId),
    text: text,
  );
}

/// "지휘관"(플레이어 자신 — 비전투원 전술가라 초상화가 없다)이나 "모든
/// 동료들" 같이 특정 1인을 가리키지 않는 그룹 대사에 쓴다. [thumbnailUrl]을
/// null로 두면 [StoryDialogWidget]이 기사단 엠블럼을 대신 그린다.
StoryLine _commanderLine(String speaker, String text) {
  return StoryLine(speaker: speaker, thumbnailUrl: null, text: text);
}

/// 챕터 하나가 가진 두 개의 대화 연출 — 챕터 첫 스테이지(subStage 1) 진입
/// 시 재생되는 [opening]과, 보스 스테이지(subStage 10) 진입 시 재생되는
/// 짧은 [bossIntro]. 둘 다 같은 챕터 회상 일러스트
/// ([AppImages.chapterMemoryIllustration])를 배경으로 공유한다 — 인게임
/// 전투 배경(IdleGame의 다중 레이어 패럴랙스, ParallaxBackLayer/
/// ParallaxGroundLayer)은 별도 관리되는 전용 에셋이다 — 먼 배경/바닥 둘 다
/// 같은 챕터 번호로 세트째 바뀌는 [AppImages.chapterBackgroundBack]/
/// [AppImages.groundTile]을 쓴다.
class ChapterStory {
  const ChapterStory({required this.chapter, required this.opening, required this.bossIntro});

  final int chapter;
  final StoryModel opening;
  final StoryModel bossIntro;
}

/// 시즌1 메인 스토리 — 총 10개 챕터, 챕터 번호를 키로 한다. 트리거 시점은
/// [MainStoryManager]/main.dart의 [_MainNavigationScreenState] 참고.
///
/// 세계관: 대륙의 모든 여성 영웅은 각자 다른 검과 검기를 다루는 검사들이다
/// (마법사/궁수 대신 룬 성검사, 검기를 날리는 환검사, 별빛 마검사 등으로
/// 표현). "지휘관"은 전투에 나서지 않는 플레이어 자신 — 비전투원 전술가라
/// 초상화 없이 엠블럼으로 표시된다([_commanderLine]).
///
/// 아군 캐스팅(실제 에셋이 있는 등급만 사용 — UR/LR은 아직 아트가 없어
/// [ItemPoolConfig.maxCharacterCount]에 0으로 잠겨 있다. 9장 "UR
/// 별빛마검사"는 호칭만 UR을 쓸 뿐 실제 썸네일은 SSSR2를 재사용한다):
///   N1(수습 기사) · R1(쾌검사) · SR1(룬 성검사) · SR2(환검사) ·
///   SSR1(얼음 대검 기사) · SSR2(화염 대장장이 대검사) · SSR3(암살 쌍검사) ·
///   SSSR1(8장 타락한 스승 / 10장 마왕 분신 — 같은 어둠에 물든 존재라는
///   연출로 재사용) · SSSR2(9장 별빛마검사).
/// 보스 전용 ID(아군과 겹치지 않는 나머지): N4/N7/N10/R4/R6/R9/SR4/SR7.
final Map<int, ChapterStory> seasonOneMainStory = {
  1: ChapterStory(
    chapter: 1,
    opening: StoryModel(
      id: 'chapter_1',
      backgroundUrl: AppImages.chapterMemoryIllustration(1),
      lines: [
        _line('N1', 'N1', '{nickname}님! 마물들의 세력이 전보다 훨씬 거세졌어요... 외곽 방어선이 무너지고 있습니다!'),
        _commanderLine('지휘관', '당황하지 마라. 인근 주민들을 먼저 구출하고, 놈들의 측면을 노린다!'),
        _line('N1', 'N1', '네! 비록 나무 검이지만, {nickname}님의 전술에 따라 검을 휘두르겠습니다!'),
      ],
    ),
    bossIntro: StoryModel(
      id: 'chapter_1_boss',
      backgroundUrl: AppImages.chapterMemoryIllustration(1),
      lines: [
        _commanderLine('지휘관', '이 무시무시한 마력 반응은... 숲을 오염시킨 거대 마물인가!'),
        _line('보스 (변종 마수)', 'N4', '크아아아-! 어리석은 기사 따위가 감히 본거지를 넘보느냐!'),
        _line('N1', 'N1', '{nickname}님, 놈이 잿빛 숲의 원천을 오염시키고 있었어요! 놈을 제압해야 합니다!'),
      ],
    ),
  ),
  2: ChapterStory(
    chapter: 2,
    opening: StoryModel(
      id: 'chapter_2',
      backgroundUrl: AppImages.chapterMemoryIllustration(2),
      lines: [
        _line('N1', 'N1', '몽환적인 버섯 숲이네요... 하지만 독 포자와 마물의 기운이 느껴집니다.'),
        _commanderLine('지휘관', '저 앞쪽에서 바람을 가르는 검격 소리가 난다. 누군가 싸우고 있어!'),
        _line('R 쾌검사', 'R1', '하아... 끝도 없이 몰려오는군. 내 카타나가 부러지기 전에 끝내주지!'),
      ],
    ),
    bossIntro: StoryModel(
      id: 'chapter_2_boss',
      backgroundUrl: AppImages.chapterMemoryIllustration(2),
      lines: [
        _line('R 쾌검사', 'R1', '독포자 퀸... 숲의 마물들을 통제하던 녀석이 바로 너였군.'),
        _line('보스 (독포자 퀸)', 'N7', '키에에엑-! 숲의 맹독 맛을 보아라!'),
        _commanderLine('지휘관', '방랑 검사, 합공한다! 측면을 부탁한다!'),
        _line('R 쾌검사', 'R1', '후, 내 검술 속도를 따라올 수 있다면 어디 맞춰봐!'),
      ],
    ),
  ),
  3: ChapterStory(
    chapter: 3,
    opening: StoryModel(
      id: 'chapter_3',
      backgroundUrl: AppImages.chapterMemoryIllustration(3),
      lines: [
        _line('N1', 'N1', '이곳이 고대 신전이군요... 마물들에 점령당한 상태예요.'),
        _line('SR 성검사', 'SR1', '검에 두른 신성한 룬 마력이 흐려지고 있어... 하지만 신전을 빼앗기게 둘 순 없다!'),
        _commanderLine('지휘관', '성검사, 전열을 정비해라! 우리가 지휘를 지원하겠다!'),
      ],
    ),
    bossIntro: StoryModel(
      id: 'chapter_3_boss',
      backgroundUrl: AppImages.chapterMemoryIllustration(3),
      lines: [
        _line('SR 성검사', 'SR1', '차원의 균열에 마력을 공급하던 제단의 석상이 움직인다!'),
        _line('보스 (고대 수호 석상)', 'N10', '신전을 침범하는 자... 잿더미로 만들어주마.'),
        _commanderLine('지휘관', '놈의 핵을 노려라! 룬 마력을 검 끝에 집중시켜라!'),
        _line('SR 성검사', 'SR1', '빛의 룬 검기여, 차원의 악마를 꿰뚫어라!'),
      ],
    ),
  ),
  4: ChapterStory(
    chapter: 4,
    opening: StoryModel(
      id: 'chapter_4',
      backgroundUrl: AppImages.chapterMemoryIllustration(4),
      lines: [
        _line('SR 환검사', 'SR2', '항구를 점령한 타락한 상인들이 붉은 검기를 날리는 마물들과 결탁했어.'),
        _commanderLine('지휘관', '원거리에서 날아오는 검기를 조심해라. 방어선을 구축한다!'),
        _line('SR 환검사', 'SR2', '훗, 검기를 날리는 건 놈들뿐만이 아니야. 내 환검술을 보여주지!'),
      ],
    ),
    bossIntro: StoryModel(
      id: 'chapter_4_boss',
      backgroundUrl: AppImages.chapterMemoryIllustration(4),
      lines: [
        _line('보스 (타락한 심해의 검사)', 'R4', '크크... 원정대 따위가 항구의 차원 통로를 막을 수 있을 것 같으냐!'),
        _line('SR 환검사', 'SR2', '바다를 더럽힌 죄, 내 바람의 검기로 단죄해주마!'),
        _commanderLine('지휘관', '전 기사단, 사격 검기를 뚫고 돌격하라!'),
      ],
    ),
  ),
  5: ChapterStory(
    chapter: 5,
    opening: StoryModel(
      id: 'chapter_5',
      backgroundUrl: AppImages.chapterMemoryIllustration(5),
      lines: [
        _line('N1', 'N1', '눈보라가 너무 거세요... 얼음 결정이 검에 맺히고 있어요.'),
        _line('SSR 얼음기사', 'SSR1', '슬픔과 서리가 감도는 이 설원에... 어째서 다시 검을 들라 하는가.'),
        _commanderLine('지휘관', '과거에 사로잡히지 마라! 그 거대한 대검은 동료들을 지키기 위해 존재하는 것이다!'),
      ],
    ),
    bossIntro: StoryModel(
      id: 'chapter_5_boss',
      backgroundUrl: AppImages.chapterMemoryIllustration(5),
      lines: [
        _line('보스 (설원의 마룡)', 'R6', '크아아아! 얼어붙은 영혼들이여, 이 설원에 묻혀라!'),
        _line('SSR 얼음기사', 'SSR1', '{nickname}의 말이 맞았다... 내 서리의 대검은 꺾이지 않는다!'),
        _commanderLine('지휘관', '빙설의 마력을 대검에 집결시켜 놈을 베어라!'),
      ],
    ),
  ),
  6: ChapterStory(
    chapter: 6,
    opening: StoryModel(
      id: 'chapter_6',
      backgroundUrl: AppImages.chapterMemoryIllustration(6),
      lines: [
        _line('SSR 화염기사', 'SSR2', '열기가 느껴지나? 내가 직접 제련한 불꽃의 대검이다!'),
        _commanderLine('지휘관', '화산 지대의 용암 마물들이 기사단의 무기를 위협하고 있다.'),
        _line('SSR 화염기사', 'SSR2', '마물 따위가 감히 기사단의 검을 논하느냐! 싹 다 융해시켜 주마!'),
      ],
    ),
    bossIntro: StoryModel(
      id: 'chapter_6_boss',
      backgroundUrl: AppImages.chapterMemoryIllustration(6),
      lines: [
        _line('보스 (용암 골렘)', 'R9', '쿠오오오! 뜨거운 용암 속에서 소멸하라!'),
        _line('SSR 화염기사', 'SSR2', '망치질 몇 번에 박살 날 녀석이! {nickname}님, 신호를 주세요!'),
        _commanderLine('지휘관', '화염 대검의 일격으로 놈의 갑주를 부숴라!'),
      ],
    ),
  ),
  7: ChapterStory(
    chapter: 7,
    opening: StoryModel(
      id: 'chapter_7',
      backgroundUrl: AppImages.chapterMemoryIllustration(7),
      lines: [
        _line('N1', 'N1', '대나무 숲의 그림자 속에서 살기가 느껴져요!'),
        _line('SSR 암살자', 'SSR3', '달빛 아래서 날 침범한 자가 누구지? 단검을 받기 전에 답해라.'),
        _commanderLine('지휘관', '오해다! 우리는 차원의 균열을 막으러 온 기사단이다!'),
      ],
    ),
    bossIntro: StoryModel(
      id: 'chapter_7_boss',
      backgroundUrl: AppImages.chapterMemoryIllustration(7),
      lines: [
        _line('보스 (그림자 귀신)', 'SR4', '크크... 대나무 숲의 암살자도 이제 끝이다...'),
        _line('SSR 암살자', 'SSR3', '그림자 속에 숨어있던 쥐새끼는 너였구나.'),
        _commanderLine('지휘관', '쌍검의 속도로 놈의 허점을 기습해라!'),
      ],
    ),
  ),
  8: ChapterStory(
    chapter: 8,
    opening: StoryModel(
      id: 'chapter_8',
      backgroundUrl: AppImages.chapterMemoryIllustration(8),
      lines: [
        _line('N1', 'N1', '왕도가 어둠 마기에 물들었어요... 스승님이 계신 성전이...'),
        _commanderLine('지휘관', '스승님... 차원의 유혹에 빠지신 겁니까!'),
        _line('보스 (타락한 스승)', 'SSSR1', '약한 자는 생존할 수 없다... 이 핏빛 검의 힘만이 대륙을 구한다...'),
      ],
    ),
    bossIntro: StoryModel(
      id: 'chapter_8_boss',
      backgroundUrl: AppImages.chapterMemoryIllustration(8),
      lines: [
        _commanderLine('지휘관', '틀렸습니다 스승님! 동료를 버린 검은 그저 폭력일 뿐입니다!'),
        _line('보스 (타락한 스승)', 'SSSR1', '너희의 검술로 날 증명해 보아라!'),
        _line('N1', 'N1', '스승님... 눈물의 검으로 당신을 안식에 들게 하겠습니다!'),
      ],
    ),
  ),
  9: ChapterStory(
    chapter: 9,
    opening: StoryModel(
      id: 'chapter_9',
      backgroundUrl: AppImages.chapterMemoryIllustration(9),
      lines: [
        _line('UR 별빛마검사', 'SSSR2', '밤하늘 천문대의 별자리가 붉게 타오르고 있어요... 차원 대재앙의 진실이 보입니다.'),
        _commanderLine('지휘관', '수백 년 전 남성이 소멸했던 대재앙의 진실이 무엇입니까?'),
        _line('UR 별빛마검사', 'SSSR2', '이계의 마왕이 우리를 약화시키기 위해 번개 검으로 일으킨 주술이었어요.'),
      ],
    ),
    bossIntro: StoryModel(
      id: 'chapter_9_boss',
      backgroundUrl: AppImages.chapterMemoryIllustration(9),
      lines: [
        _line('보스 (차원의 파수꾼)', 'SR7', '진실을 알게 된 자, 이 별자리 밑에서 소멸하라!'),
        _line('UR 별빛마검사', 'SSSR2', '내 별빛 얇은 검으로 별자리의 운명을 바꾸겠어요!'),
        _commanderLine('지휘관', '마왕의 차원 연결 고리를 검기로 잘라내라!'),
      ],
    ),
  ),
  10: ChapterStory(
    chapter: 10,
    opening: StoryModel(
      id: 'chapter_10',
      backgroundUrl: AppImages.chapterMemoryIllustration(10),
      lines: [
        _commanderLine('지휘관', '모든 기사단원이여, 차원 균열 최심부에 도달했다! 각자의 검을 집결시켜라!'),
        _line('N1', 'N1', '{nickname}님과 함께라면 어떤 마왕도 두렵지 않습니다!'),
        _commanderLine('모든 동료들', '우리의 검을 {nickname}의 전술에 바칩니다!'),
      ],
    ),
    bossIntro: StoryModel(
      id: 'chapter_10_boss',
      backgroundUrl: AppImages.chapterMemoryIllustration(10),
      lines: [
        _line('보스 (이계의 마왕 분신)', 'SSSR1', '어리석은 여검사들... 차원의 구렁텅이로 떨어져라!'),
        _commanderLine('지휘관', '원정대 전체, 총력전이다! 검의 빛으로 차원의 균열을 완전 봉인한다!'),
        _commanderLine('모든 동료들', '하앗-! 차원을 가르는 일편제월!'),
      ],
    ),
  ),
};
