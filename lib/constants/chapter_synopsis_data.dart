/// [주의: 독립 모듈] [StageCalculator]/[StoryTrigger]와 같은 이유로, 이
/// 파일도 아직 게임에 연결되지 않은 기획안이다 — 실제 대사 스크립트가
/// 아니라 "각 챕터가 어떤 테마이고 보스가 누구인지"를 요약한 뼈대다.
/// 여기 적힌 세계관은 기존 시즌1 스토리(`story_data.dart`의
/// `seasonOneMainStory`, "잿빛 숲"/"지휘관"/기사단 설정)를 그대로 잇는다 —
/// 다만 이번 10챕터·990스테이지 구조는 그 시즌1보다 훨씬 큰 스케일이라,
/// 같은 세계관 안에서 새로운 위협("차원의 침식")을 중심으로 다시 짰다.
///
/// [sampleOpeningLine]/[sampleBossLine]은 `{nickname}` 플레이스홀더를
/// 포함한 예시 대사 한 줄씩이다 — 실제 [StoryDialogWidget]의
/// `_resolveDialogueText`가 렌더링 직전에 이 자리를 유저가 설정한
/// 닉네임으로(없으면 "지휘관"으로) 치환한다. 전체 대사 스크립트가 아니라
/// "이런 톤으로 쓰면 된다"는 예시 한 줄임에 유의.
class ChapterSynopsis {
  const ChapterSynopsis({
    required this.chapter,
    required this.title,
    required this.theme,
    required this.bossName,
    required this.bossSummary,
    required this.sampleOpeningLine,
    required this.sampleBossLine,
  });

  final int chapter;

  /// 챕터 제목.
  final String title;

  /// 챕터 전체를 관통하는 테마/사건 한두 문장 요약.
  final String theme;

  final String bossName;

  /// 보스전의 내용과 처치 후 벌어지는 일(동료 합류 등) 요약.
  final String bossSummary;

  final String sampleOpeningLine;
  final String sampleBossLine;
}

const List<ChapterSynopsis> chapterSynopses = [
  ChapterSynopsis(
    chapter: 1,
    title: '잿빛 숲의 신호탄',
    theme:
        '평화롭던 왕국 외곽에 정체불명의 마물 무리가 쏟아지기 시작한다. '
        '{nickname}은(는) 흩어진 기사단원들을 규합하며 첫걸음을 내딛는다.',
    bossName: '숲을 오염시킨 거대 마물',
    bossSummary: '잿빛 숲의 마력 원천을 집어삼킨 변종 마수. 처치하면 숲의 오염이 멎고 첫 동료 N1이 정식으로 합류한다.',
    sampleOpeningLine: '{nickname}님, 마물들의 세력이 전보다 훨씬 거세졌어요... 함께 맞서 주시겠어요?',
    sampleBossLine: '이 마력 반응, 심상치 않다. {nickname}, 놈의 핵을 노려라!',
  ),
  ChapterSynopsis(
    chapter: 2,
    title: '폐허가 된 왕도 외곽',
    theme:
        '수도로 향하는 길목의 마을들이 하나둘 폐허가 되어간다. '
        '{nickname}의 부대는 생존자를 구하며 마물 무리의 근원을 쫓는다.',
    bossName: '외곽 수비대장을 집어삼킨 강령 마수',
    bossSummary: '왕국 수비대의 유해를 흡수해 거대해진 마수. 처치 후 수도로 가는 길이 열린다.',
    sampleOpeningLine: '{nickname}, 이 앞부터는 지원군이 없다. 우리끼리 뚫어야 해.',
    sampleBossLine: '동료들의 원한이 이 검에 실려 있다! {nickname}, 마무리를 부탁한다!',
  ),
  ChapterSynopsis(
    chapter: 3,
    title: '방랑 검사의 협곡',
    theme:
        '협곡에서 홀로 마물떼와 맞서던 방랑 검사와 조우한다. '
        '{nickname}의 지휘 아래 힘을 합쳐 협곡을 돌파하며 신뢰를 쌓는다.',
    bossName: '협곡을 뒤흔드는 지룡형 마물',
    bossSummary: '협곡 깊은 곳에 잠들어 있던 지룡형 마물이 마력 폭주로 눈을 뜬다. 처치 후 방랑 검사가 정식으로 합류한다.',
    sampleOpeningLine: '이런 곳에서 지원군이라니. {nickname}이라고 했나 — 나쁘지 않군.',
    sampleBossLine: '{nickname}, 놈이 지반을 무너뜨리기 전에 승부를 봐야 한다!',
  ),
  ChapterSynopsis(
    chapter: 4,
    title: '성역을 지키는 성검사',
    theme:
        '왕국 최후의 성역에서, 오직 홀로 결계를 지켜온 성검사와 만난다. '
        '{nickname}은(는) 그녀의 신뢰를 얻어 성역의 힘을 빌리고자 한다.',
    bossName: '결계를 잠식한 타락한 수호수',
    bossSummary: '성역을 지키던 수호수가 마력 침식으로 타락해 폭주한다. 처치하면 성검사가 결계의 힘 일부를 나누어 준다.',
    sampleOpeningLine: '{nickname}, 이 성역이 무너지면 대륙 전체가 위험해집니다. 힘을 빌려주세요.',
    sampleBossLine: '성검사, 전열을 정비해라! {nickname}, 우리가 지휘를 지원하겠다!',
  ),
  ChapterSynopsis(
    chapter: 5,
    title: '설원의 얼음 기사',
    theme:
        '북쪽 설원에서 서리의 대검을 휘두르는 얼음 기사(SSR)의 소문을 쫓는다. '
        '{nickname}의 원정대는 혹한 속에서 그녀와 첫 접점을 만든다.',
    bossName: '설원의 마룡',
    bossSummary: '설원 깊은 곳에 봉인되어 있던 마룡이 깨어난다. 처치 후 얼음 기사가 원정대에 합류한다.',
    sampleOpeningLine: '{nickname}, 이 설원 아래 잠든 것이 눈을 뜨면... 돌이킬 수 없다.',
    sampleBossLine: '빙설의 마력을 대검에 집결시켜라! {nickname}, 놈을 완전히 얼려주마!',
  ),
  ChapterSynopsis(
    chapter: 6,
    title: '화산 지대의 화염 기사',
    theme:
        '용암이 흐르는 화산 지대에서, 불꽃의 대검을 직접 제련하는 화염 기사(SSR)와 마주친다. '
        '{nickname}의 원정대는 뜨거운 환대(?) 끝에 그녀의 실력을 증명해 보인다.',
    bossName: '용암 골렘',
    bossSummary: '화산 지대의 마물들을 통솔하던 거대 용암 골렘. 처치 후 화염 기사가 정식으로 합류한다.',
    sampleOpeningLine: '{nickname}, 내 불꽃을 견뎌낼 수 있다면... 이야기를 들어주지.',
    sampleBossLine: '망치질 몇 번에 박살 날 녀석이! {nickname}님, 신호를 주세요!',
  ),
  ChapterSynopsis(
    chapter: 7,
    title: '차원이 갈라지는 사막',
    theme:
        '사막 한복판에 정체불명의 균열이 발견된다. 마물들은 그 균열에서 쏟아지고 있었다 — '
        '{nickname}은(는) 처음으로 "차원의 침식"이라는 진짜 위협과 마주한다.',
    bossName: '균열을 지키는 차원 파수마',
    bossSummary: '균열 너머에서 건너온 이형의 마물. 처치해도 균열은 닫히지 않고, 오히려 더 큰 존재의 기척이 느껴진다.',
    sampleOpeningLine: '오해다! 우리는 이 차원의 균열을 막으러 온 것뿐이다, {nickname}!',
    sampleBossLine: '쌍검의 속도로 놈의 허점을 기습해라! {nickname}, 지금이다!',
  ),
  ChapterSynopsis(
    chapter: 8,
    title: '스승님과의 재회',
    theme:
        '균열을 쫓던 중, 오래전 소식이 끊겼던 스승이 차원의 힘에 잠식된 채 나타난다. '
        '{nickname}과 동료들은 그를 막아서야 하는 잔인한 선택 앞에 놓인다.',
    bossName: '차원에 잠식된 스승',
    bossSummary: '한때 기사단을 이끌던 스승이 차원의 유혹에 잠식되어 적으로 나타난다. 처치(정화) 후 진실의 실마리를 얻는다.',
    sampleOpeningLine: '스승님... 차원의 유혹에 빠지신 겁니까? {nickname}, 우리가 반드시 되돌리겠습니다.',
    sampleBossLine: '틀렸습니다, 스승님! {nickname}과 함께라면 동료를 버리지 않고도 이길 수 있습니다!',
  ),
  ChapterSynopsis(
    chapter: 9,
    title: '대재앙의 진실',
    theme:
        '정화된 스승으로부터 수백 년 전 대재앙 — 남성이 소멸했던 그날의 진실을 듣는다. '
        '{nickname}은(는) 마왕의 진짜 목적이 "이 차원 자체의 재구성"임을 알게 된다.',
    bossName: '진실을 감추는 기억의 파수병',
    bossSummary: '대재앙의 기억을 봉인해 온 존재. 처치하면 최종 결전의 무대(차원 균열 최심부)로 가는 길이 열린다.',
    sampleOpeningLine: '수백 년 전 그날의 진실... {nickname}, 당신은 들을 준비가 되었나요?',
    sampleBossLine: '마왕의 차원 연결 고리를 검기로 잘라내라! {nickname}, 이 앞이 마지막이다!',
  ),
  ChapterSynopsis(
    chapter: 10,
    title: '차원 균열, 최심부',
    theme:
        '모든 동료가 한자리에 모였다. {nickname}이(가) 이끄는 원정대는 차원 균열의 최심부에서 '
        '마왕의 분신과 마지막 결전을 치른다.',
    bossName: '이계의 마왕 분신',
    bossSummary:
        '마왕 본체가 이 차원에 남긴 강대한 분신. 총력전 끝에 쓰러뜨리면 차원의 균열이 완전히 봉인되며 '
        '시즌 1의 대장정이 마무리된다.',
    sampleOpeningLine: '모든 기사단원이여, 차원 균열 최심부에 도달했다! {nickname}의 이름으로 검을 집결시켜라!',
    sampleBossLine: '{nickname}과(와) 함께라면 어떤 마왕도 두렵지 않습니다! 원정대 전체, 총력전이다!',
  ),
];
