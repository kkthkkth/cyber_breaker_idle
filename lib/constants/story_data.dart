import '../models/story_model.dart';
import 'app_images.dart';

/// [StoryLine] 하나를 짧게 만드는 헬퍼 — [thumbnailCharacterId]는 항상
/// 실제로 존재하는(에셋 레포에 등록된) 캐릭터 ID여야 한다("N1", "SR2" 등).
StoryLine _line(String speaker, String thumbnailCharacterId, String text) {
  return StoryLine(
    speaker: speaker,
    thumbnailUrl: AppImages.playerThumbnail(thumbnailCharacterId),
    text: text,
    characterId: thumbnailCharacterId,
  );
}

/// "지휘관"(플레이어 자신 — 전투에 직접 나서지 않는 전술가라 초상화가
/// 없다)이나 "모든 동료들" 같이 특정 1인을 가리키지 않는 그룹 대사에 쓴다.
/// [thumbnailUrl]을 null로 두면 [StoryDialogWidget]이 기사단 엠블럼을
/// 대신 그린다.
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
/// 세계관: 수백 년 전 대재앙으로 대륙의 모든 남성이 소멸하고 오직 여성만
/// 남아 마물과 싸워온 정통 중세 판타지 대륙 '아르카디아'. 주인공(플레이어)은
/// 이 세계에 유일하게 존재하는 남성이자, 원래는 이 게임을 만들던 개발자
/// (프롤로그 참고 — [prologueBeforeName]/[prologueAfterName], story_model.dart).
/// 전투에 직접 나서지 않는 "지휘관"으로서, 몬스터의 스폰 위치·체력·약점이
/// 보이는 "디버그 시야"로 기사(전위)·마법사(마법 화력)·궁수(원거리 견제)
/// 동료들을 지휘한다.
///
/// 매 챕터 새 동료가 합류할 때는 관례적으로 두 반응을 함께 그린다:
/// 1) 대재앙 이후 처음 보는 '남성'이라는 사실에 대한 당황/호기심/호감,
/// 2) 상대 진영도 모르는 자신의 상성 정보(방패 내구도, 사거리 등)를 정확히
///    짚어내는 디버그 시야에 대한 경악.
///
/// 아군 캐스팅(실제 에셋이 있는 등급만 사용 — UR/LR은 아직 아트가 없어
/// [ItemPoolConfig.maxCharacterCount]에 0으로 잠겨 있다. 9장의 "UR 현자"는
/// 호칭만 UR을 쓸 뿐 실제 썸네일은 SSSR2를 재사용한다):
///   N1(수습 기사) · R1(방랑 기사) · SR1(마법사) · SR2(궁수) ·
///   SSR1(얼음 기사) · SSR2(대장장이) · SSR3(암살자) ·
///   SSSR1(8장 타락한 기사단장 / 10장 마왕 분신 — 같은 어둠에 물든 존재라는
///   연출로 재사용) · SSSR2(9장 현자).
/// 보스 전용 ID(아군과 겹치지 않는 나머지): N4/N7/N10/R4/R6/R9/SR4/SR7.
final Map<int, ChapterStory> seasonOneMainStory = {
  1: ChapterStory(
    chapter: 1,
    opening: StoryModel(
      id: 'chapter_1',
      backgroundUrl: AppImages.chapterMemoryIllustration(1),
      lines: [
        _line('N1', 'N1', '{nickname}님, 잿빛 숲 외곽에 마물 무리가 나타났어요! 저 혼자였다면 진작 도망쳤을 텐데...'),
        _commanderLine('지휘관', '도망칠 필요 없어. 저 늑대형 마물은 등 뒤 급소만 노출돼 있어. 정면 승부만 피하면 돼.'),
        _line('N1', 'N1', '그, 그걸 어떻게... 알겠습니다! {nickname}님만 믿고 움직일게요!'),
        _commanderLine('지휘관', '좋아, 내가 시야를 봐줄 테니 너는 검을 믿고 휘둘러. 우리 첫 합, 시작하자.'),
      ],
    ),
    bossIntro: StoryModel(
      id: 'chapter_1_boss',
      backgroundUrl: AppImages.chapterMemoryIllustration(1),
      lines: [
        _commanderLine('지휘관', '이 반응, 숲 전체를 오염시키는 마력의 근원이 바로 이 안쪽에 있어.'),
        _line('보스 (변종 마수)', 'N4', '크르릉... 침입자 냄새가 난다. 이 몸의 둥지를 넘본 죄, 뼈까지 씹어주마.'),
        _line('N1', 'N1', '{nickname}님, 놈이 생각보다 훨씬 커요! 저 혼자서는—'),
        _commanderLine('지휘관', '정면 갑각은 단단해도 뒷다리 관절은 약점이야. N1, 내가 타이밍 신호를 줄 테니 거기만 노려.'),
        _line('N1', 'N1', '네! {nickname}님의 눈을 믿고, 갑니다!'),
      ],
    ),
  ),
  2: ChapterStory(
    chapter: 2,
    opening: StoryModel(
      id: 'chapter_2',
      backgroundUrl: AppImages.chapterMemoryIllustration(2),
      lines: [
        _line('N1', 'N1', '몽환적인 버섯 숲이네요... 어라, 저기 검을 든 사람이 혼자서 마물 무리랑 싸우고 있어요!'),
        _line('R 방랑 기사', 'R1', '하아... 하아... 끝이 없군. 혼자서 여기까지 온 게 실수였나.'),
        _commanderLine('지휘관', '거기, 오른쪽! 포자 구름 속에 하나 더 숨어있다!'),
        _line('R 방랑 기사', 'R1', '뭐?! ...진짜네. 대체 어떻게 안 거지, 방금 그 목소리?'),
        _line('N1', 'N1', '저희 지휘관님이세요! 안 보이는 것도 다 보이는 분이시거든요!'),
        _line('R 방랑 기사', 'R1', '허, 재밌는 인간이네. 처음 보는 얼굴인데... 설마 진짜 소문의 그 남성? 그 눈, 잠깐 빌려볼까. 마침 이 독고다이 생활도 좀 지겨웠거든.'),
      ],
    ),
    bossIntro: StoryModel(
      id: 'chapter_2_boss',
      backgroundUrl: AppImages.chapterMemoryIllustration(2),
      lines: [
        _line('R 방랑 기사', 'R1', '숲의 마물들을 조종하던 게 바로 너였군, 독포자 퀸.'),
        _line('보스 (독포자 퀸)', 'N7', '키에에엑! 숲에 발을 들인 것을 후회하게 해주지!'),
        _commanderLine('지휘관', 'R1, 놈의 독주머니가 부풀 때마다 그 직후에 반드시 빈틈이 생겨. 타이밍만 놓치지 마.'),
        _line('R 방랑 기사', 'R1', '정말 손바닥 보듯 훤히 보이나 보네. 좋아, 믿고 베어주지!'),
      ],
    ),
  ),
  3: ChapterStory(
    chapter: 3,
    opening: StoryModel(
      id: 'chapter_3',
      backgroundUrl: AppImages.chapterMemoryIllustration(3),
      lines: [
        _line('N1', 'N1', '고대 신전이 마물들에게 점령당했어요... 저 안쪽에 갇힌 사람이 있는 것 같아요!'),
        _line('SR 마법사', 'SR1', '누구든 상관없어요, 이 결계만 좀... 마력이 바닥나서 더는 지팡이를 들 힘도...'),
        _commanderLine('지휘관', '결계 문양이 세 군데나 인위적으로 조작돼 있어. 이거 자연 발생한 균열이 아니라 누가 일부러 만든 거야.'),
        _line('SR 마법사', 'SR1', '네?! 그, 그걸 한눈에 알아보시다니... 저조차 여기 갇힌 지 사흘 만에 겨우 눈치챈 걸... 게다가 당신, 설마 고서에만 남아있다던 그 남성인가요?'),
        _line('N1', 'N1', '저희 지휘관님껜 안 보이는 게 없으시거든요!'),
        _line('SR 마법사', 'SR1', '구해주신다면... 저도 힘을 보태겠어요. 이 결계를 조작한 자, 저도 알아야겠으니까요.'),
      ],
    ),
    bossIntro: StoryModel(
      id: 'chapter_3_boss',
      backgroundUrl: AppImages.chapterMemoryIllustration(3),
      lines: [
        _line('SR 마법사', 'SR1', '제단에 마력을 계속 흘려보내던 그 석상이, 지금 움직이고 있어요!'),
        _line('보스 (고대 수호 석상)', 'N10', '신전을 침범하는 자··· 잿더미로 만들어주마.'),
        _commanderLine('지휘관', '가슴팍 문양이 마력의 핵이야. 저기가 뚫리는 순간 움직임이 반 박자 느려질 거야.'),
        _line('SR 마법사', 'SR1', '그 반 박자, 제가 놓치지 않을게요! 마법의 힘으로 문양을 꿰뚫겠어요!'),
      ],
    ),
  ),
  4: ChapterStory(
    chapter: 4,
    opening: StoryModel(
      id: 'chapter_4',
      backgroundUrl: AppImages.chapterMemoryIllustration(4),
      lines: [
        _line('N1', 'N1', '노을 빛 항구가 붉게 물들어 있어요... 저건 노을이 아니라, 화염 흔적 같아요.'),
        _line('SR 궁수', 'SR2', '이 거리에서 저 갑판 위 마물까진 내 활이 안 닿... 어?! 잠깐, 방금 그 말대로 쐈더니 정확히 맞았잖아?!'),
        _commanderLine('지휘관', '바람 방향 계산해서 반 걸음만 앞을 보고 쏘라고 했잖아. 네 활 사거리, 정확히 저기까지 닿아.'),
        _line('SR 궁수', 'SR2', '……처음 만난 사람이 내 활의 유효 사거리를 자보다 정확하게 알고 있다고? 게다가 남자? 당신 정체가 뭐야?'),
        _line('N1', 'N1', '저희 지휘관님이세요! 못 맞히는 게 없으시다니까요!'),
        _line('SR 궁수', 'SR2', '흥, 마음에 들어. 이 항구를 이 꼴로 만든 놈들, 그 계산으로 전부 쓸어주지.'),
      ],
    ),
    bossIntro: StoryModel(
      id: 'chapter_4_boss',
      backgroundUrl: AppImages.chapterMemoryIllustration(4),
      lines: [
        _line('SR 궁수', 'SR2', '타락한 상인 놈들이 뒤에서 마물이랑 결탁했더라고. 그리고 그 뒤에 또... 뭔가 있어.'),
        _line('보스 (타락한 심해의 검사)', 'R4', '크크... 애송이들이 항구의 차원 통로를 막을 수 있을 것 같으냐?'),
        _commanderLine('지휘관', '저 녀석 원거리 공격 쓰는 순간에만 왼쪽 아가미가 열려. SR2, 그 타이밍에 맞춰서 쏴.'),
        _line('SR 궁수', 'SR2', '0.1초도 안 되는 그 틈을 보고 있다고? ...좋아, 믿어보지. 화살 나간다!'),
      ],
    ),
  ),
  5: ChapterStory(
    chapter: 5,
    opening: StoryModel(
      id: 'chapter_5',
      backgroundUrl: AppImages.chapterMemoryIllustration(5),
      lines: [
        _line('N1', 'N1', '눈보라가 너무 거세요... 저기, 원형극장 한가운데 혼자 서 있는 사람이 있어요.'),
        _line('SSR 얼음 기사', 'SSR1', '...돌아가라. 이곳은 내가 혼자 지킨다. 더 이상 누구도 나 때문에 쓰러지게 둘 수 없어.'),
        _commanderLine('지휘관', '혼자 다 막겠다는 거, 그 방패 내구도로는 세 번째 파도에서 부서져. 정확히는 다음 공격까지.'),
        _line('SSR 얼음 기사', 'SSR1', '……뭐? 이 방패의 내구도를, 어떻게 정확히— 그리고 남자가... 이런 곳까지 어떻게.'),
        _commanderLine('지휘관', '동료를 지키려다 혼자 다 짊어지고 무너지는 거, 그거 희생이 아니라 그냥 도미노야. 뒤를 봐줄 사람이 있으면 안 무너져.'),
        _line('N1', 'N1', '지휘관님이라면 정말로, 당신을 혼자 쓰러지게 두지 않으실 거예요!'),
        _line('SSR 얼음 기사', 'SSR1', '……오랜만이군. 이런 말을 들은 게. 좋다, 그 눈을 한번 믿어보지.'),
      ],
    ),
    bossIntro: StoryModel(
      id: 'chapter_5_boss',
      backgroundUrl: AppImages.chapterMemoryIllustration(5),
      lines: [
        _line('보스 (설원의 마룡)', 'R6', '크아아앙! 얼어붙은 영혼들이여, 이 설원에 함께 묻혀라!'),
        _line('SSR 얼음 기사', 'SSR1', '{nickname}, 이번엔 혼자 안 막아. 뒤를 부탁한다.'),
        _commanderLine('지휘관', '그래, 정면은 네가, 빈틈은 내가 본다. 놈의 브레스 직후 3초가 유일한 급소 노출 구간이야.'),
        _line('SSR 얼음 기사', 'SSR1', '알았다. 내 대검, 이제야 제대로 쓸 곳을 찾았군.'),
      ],
    ),
  ),
  6: ChapterStory(
    chapter: 6,
    opening: StoryModel(
      id: 'chapter_6',
      backgroundUrl: AppImages.chapterMemoryIllustration(6),
      lines: [
        _line('N1', 'N1', '용암 광산 안쪽에서 망치질 소리가 들려요! 아직 누군가 버티고 있나 봐요.'),
        _line('SSR 대장장이', 'SSR2', '젠장, 마물 놈들이 대장간까지 밀고 들어와서— 아, 지원군?! ...어? 남자?'),
        _commanderLine('지휘관', '화로 뒤쪽 통로, 놈들 세 마리가 숨어서 대기 중이야. 정면 말고 화로를 방패 삼아 우회해.'),
        _line('SSR 대장장이', 'SSR2', '이 좁은 광산 지형을, 처음 온 사람이 나보다 더 잘 꿰고 있다고?! 어이가 없네, 진짜.'),
        _line('N1', 'N1', '저희 지휘관님껜 원래 안 보이는 게 없으세요! 이제 익숙해지실 거예요.'),
        _line('SSR 대장장이', 'SSR2', '……마음에 들어. 대장간만 지켜준다면, 너희들 장비는 내가 최고로 벼려주지.'),
      ],
    ),
    bossIntro: StoryModel(
      id: 'chapter_6_boss',
      backgroundUrl: AppImages.chapterMemoryIllustration(6),
      lines: [
        _line('보스 (용암 골렘)', 'R9', '쿠오오오! 뜨거운 용암 속에서 소멸하라!'),
        _line('SSR 대장장이', 'SSR2', '저 갑주, 표면은 단단해도 관절 이음새 쪽 온도가 유독 낮아. 그쪽이 약점이겠는데?'),
        _commanderLine('지휘관', '정확해. 왼쪽 어깨 이음새, 딱 한 방이면 갈라져.'),
        _line('SSR 대장장이', 'SSR2', '역시 보는 눈은 똑같네! 내 망치로 마무리 짓겠어!'),
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
        _line('SSR 암살자', 'SSR3', '……거기, 멈춰. 달빛 아래서 이 숲에 발을 들인 자, 목적이 뭐지.'),
        _commanderLine('지휘관', '적의는 없어. 그보다 너, 왼쪽 대나무 뒤에 숨은 마물부터 처리하는 게 좋을걸. 3초 뒤에 튀어나와.'),
        _line('SSR 암살자', 'SSR3', '……! 은신한 기척을 그렇게 쉽게 읽는다고? 인간치고는 제법이군. 아니, 잠깐— 너한테서 나는 이 냄새는……'),
        _line('N1', 'N1', '네? 냄새요?!'),
        _line('SSR 암살자', 'SSR3', '뭔가 이 세계 것이 아닌 낯선 냄새가 나. 흥미롭군. 게다가 이 대륙에 안 남았어야 할 남자라니. 좋아, 한동안 뒤를 따라붙어 주지.'),
        _commanderLine('지휘관', '(...냄새라니, 그건 또 무슨 소리야. 설마 진짜 개발자 냄새 같은 게 있는 건 아니겠지.)'),
      ],
    ),
    bossIntro: StoryModel(
      id: 'chapter_7_boss',
      backgroundUrl: AppImages.chapterMemoryIllustration(7),
      lines: [
        _line('SSR 암살자', 'SSR3', "그림자 속에 숨어 마물들을 조종하던 게 너였군. 그리고 그 손에 든 건— '차원 핵' 파편?"),
        _line('보스 (그림자 귀신)', 'SR4', '크크... 이걸 알아채다니, 살려둘 수 없겠군.'),
        _commanderLine('지휘관', '저 핵이 균열을 인위적으로 유지시키는 장치야. 놈이 핵을 방어하려고 팔을 든 순간이 유일한 빈틈.'),
        _line('SSR 암살자', 'SSR3', '속도로 승부를 보지. 쌍검, 간다.'),
      ],
    ),
  ),
  8: ChapterStory(
    chapter: 8,
    opening: StoryModel(
      id: 'chapter_8',
      backgroundUrl: AppImages.chapterMemoryIllustration(8),
      // 8장 전용 회상 일러스트(memory/chapter8/memory_8-1.png)가 아직
      // 원격 레포에 없다(에셋 스캔으로 확인됨) — 임시로 8장 인게임 스테이지
      // 배경을 대신 보여준다. 전용 일러스트가 올라오면 자동으로 그쪽이
      // 우선된다.
      fallbackBackgroundUrl: AppImages.chapterBackgroundBack(8),
      lines: [
        _line('N1', 'N1', '왕도가... 완전히 어둠에 물들었어요. 저기, 성전 위에 계신 분은... 스승님?!'),
        _commanderLine('지휘관', '네 스승이라고? 저 기운, 사람 것치곤 이미 반쯤 잠식돼 있어.'),
        _line('보스 (타락한 기사단장)', 'SSSR1', '약한 자는 살아남지 못한다... 이 어둠의 힘만이, 더 이상 아무도 잃지 않게 해줄 유일한 길이다.'),
        _line('N1', 'N1', '스승님, 그건 틀렸어요! 힘으로 전부 짓누른다고 아무도 잃지 않는 게 아니잖아요!'),
        _commanderLine('지휘관', 'N1, 이건 네가 매듭지어야 할 싸움이야. 뒤는 내가 완벽하게 봐줄 테니, 앞은 네가 가.'),
        _line('N1', 'N1', '……네. 이번엔, 제가 스승님을 지킬 차례예요.'),
      ],
    ),
    bossIntro: StoryModel(
      id: 'chapter_8_boss',
      backgroundUrl: AppImages.chapterMemoryIllustration(8),
      fallbackBackgroundUrl: AppImages.chapterBackgroundBack(8),
      lines: [
        _commanderLine('지휘관', '틀렸습니다, 단장님. 동료를 버려서 지키는 평화는, 그냥 폭력일 뿐이에요.'),
        _line('보스 (타락한 기사단장)', 'SSSR1', '……그 눈. 정말로 아무것도 놓치지 않는군. 좋다, 그 각오, 검으로 증명해 보아라.'),
        _line('N1', 'N1', '스승님... 이 눈물의 검으로, 당신을 편히 쉬게 해드리겠습니다.'),
      ],
    ),
  ),
  9: ChapterStory(
    chapter: 9,
    opening: StoryModel(
      id: 'chapter_9',
      backgroundUrl: AppImages.chapterMemoryIllustration(9),
      lines: [
        _line('N1', 'N1', '밤하늘 천문대의 별자리가... 이상하게 붉은빛을 띠고 있어요.'),
        _line('UR 현자', 'SSSR2', "왔군요. 계산은 이미 끝나 있었어요 — 이 세계에 어울리지 않는 '변수' 한 분이 나타날 거란 걸요."),
        _commanderLine('지휘관', '변수? ...혹시 내 얘기야?'),
        _line('UR 현자', 'SSSR2', '네. 수백 년 전 대재앙으로 대륙의 모든 남성이 사라진 그 밤에도, 이렇게 예정에 없던 빛이 하늘을 갈랐었죠.'),
        _line('N1', 'N1', '그, 그게 무슨 말씀이세요?! 대재앙이 예정된 일이었다는 건가요?!'),
        _line('UR 현자', 'SSSR2', '네 — 그건 재앙이 아니라, 이계의 마왕이 이 대륙을 약화시키려고 일으킨 주술이었어요. 이제야 확신이 서네요.'),
      ],
    ),
    bossIntro: StoryModel(
      id: 'chapter_9_boss',
      backgroundUrl: AppImages.chapterMemoryIllustration(9),
      lines: [
        _line('보스 (차원의 파수꾼)', 'SR7', '진실에 다다른 자··· 이 별자리 아래서 소멸시켜 주마.'),
        _line('UR 현자', 'SSSR2', '이 아이의 궤도, 정확히 11초 뒤에 붕괴해요. 그 순간이 유일한 빈틈이에요.'),
        _commanderLine('지휘관', '정확히 계산했네. 나랑 똑같은 걸 보고 있잖아, 당신.'),
        _line('UR 현자', 'SSSR2', '후훗, 그러게요. 처음 뵀는데 이상하게 낯설지 않네요. 갈까요, 마왕에게 가는 길로.'),
      ],
    ),
  ),
  10: ChapterStory(
    chapter: 10,
    opening: StoryModel(
      id: 'chapter_10',
      backgroundUrl: AppImages.chapterMemoryIllustration(10),
      lines: [
        _commanderLine('지휘관', '여기가 최심부인가. 다들, 준비는 됐지?'),
        _line('N1', 'N1', '{nickname}님과 함께라면, 어떤 마왕이라도 두렵지 않아요!'),
        _line('R 방랑 기사', 'R1', '이 순간을 위해 검을 갈고닦았지. 가보자고.'),
        _line('SSR 암살자', 'SSR3', '……그 낯선 냄새의 근원, 오늘 확실히 알게 되겠군.'),
        _line('UR 현자', 'SSSR2', '제 계산으론, 승률은 낮지 않아요. 당신이 있는 한은요.'),
        _commanderLine('지휘관', '좋아. 전원, 내 눈이 보는 대로 움직인다. 마지막까지 믿고 따라와줘.'),
        _commanderLine('모든 동료들', '네!!'),
      ],
    ),
    bossIntro: StoryModel(
      id: 'chapter_10_boss',
      backgroundUrl: AppImages.chapterMemoryIllustration(10),
      lines: [
        _line('보스 (이계의 마왕 분신)', 'SSSR1', "……흥미롭군. 내 주술을 뚫고 태어난 '변수'가 바로 너였나."),
        _commanderLine('지휘관', '네가 몇 백 년 전에 이 대륙에 뿌린 버그, 오늘 내가 직접 패치하러 왔다.'),
        _line('보스 (이계의 마왕 분신)', 'SSSR1', "패치? 우습군. 하나 경고해두지 — 이 몸은 겨우 '분신' 하나일 뿐이라는 걸."),
        _commanderLine('지휘관', '본체는 나중에 상대하지. 지금은 일단—'),
        _commanderLine('모든 동료들', '전원, 차원의 균열을 지금 이 자리에서 봉인한다!'),
        _commanderLine('지휘관', '(……저 말, 어딘가 불길하게 들리는 건 기분 탓이겠지. 일단 눈앞의 싸움부터.)'),
      ],
    ),
  ),
};
