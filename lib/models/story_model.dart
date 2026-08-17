import '../constants/app_images.dart';

/// 비주얼 노벨 대사 한 줄 — 화자 이름, 초상화(썸네일) URL, 대사 텍스트,
/// (있다면) 화면 좌/우에 크게 세워둘 전신 일러스트용 캐릭터 ID.
///
/// [thumbnailUrl]/[characterId]는 항상 [AppImages]/실제 존재하는(에셋
/// 레포에 등록된) 캐릭터 ID를 거쳐 만들어야 한다(원시 문자열 그대로
/// 흘려보내는 것 금지) — 오타가 나면 CustomSafeImage가 조용히 placeholder로
/// 대체해버려 알아채기 어렵다.
///
/// [thumbnailUrl]이 null이면(플레이어 자신인 "지휘관", 특정 1인을 가리키지
/// 않는 "모든 동료들" 같은 그룹 대사, 아직 정체가 드러나지 않은 "???")
/// [StoryDialogWidget]이 대화창 안 초상화 대신 기사단 엠블럼을 그리고,
/// [characterId]도 항상 null이라(전신 일러스트를 세울 특정 캐릭터가 없으므로)
/// 화면 좌/우의 큰 전신 일러스트 자체를 그리지 않는다 — 존재하지 않는
/// 캐릭터 이미지를 억지로 참조하지 않기 위함이다.
class StoryLine {
  const StoryLine({
    required this.speaker,
    required this.thumbnailUrl,
    required this.text,
    this.characterId,
  });

  final String speaker;
  final String? thumbnailUrl;
  final String text;
  final String? characterId;
}

/// 대사([lines]) 목록으로 이루어진 스토리 한 편(프롤로그, 시즌1 메인
/// 스토리 각 챕터 등). [backgroundUrl]은 대화창 뒤에 까는 배경 맵 이미지 —
/// 아직 그려지지 않은 챕터라도 [CustomSafeImage]가 알아서 placeholder로
/// 대체하므로 호출부에서 존재 여부를 따로 확인할 필요는 없다.
class StoryModel {
  const StoryModel({required this.id, required this.backgroundUrl, required this.lines});

  final String id;
  final String backgroundUrl;
  final List<StoryLine> lines;
}

/// 최초 실행 시 보여주는 프롤로그 — "게임 개발자가 자신이 만들던 게임
/// 세계 '아르카디아'에 빙의한다"는 설정의 두 파트로 나뉜다:
///
/// 1) [prologueBeforeName]: 새벽까지 '차원의 균열' 버그를 고치던 개발자가
///    빌드를 누르는 순간 빛에 휩싸여 아르카디아로 떨어지고, 수습 기사
///    N1에게 발견된다 — N1이 "고서에서만 전해지던 남성"을 실제로 마주치고
///    당황하는 장면으로 끝나며, 그 직후 [GameEntryScreen]이 [NicknameScreen]
///    을 띄운다("당신의 존함을...?"라는 N1의 질문에 실제로 답하는 연출).
/// 2) [prologueAfterName]: 닉네임 입력 직후 이어지는 대화 — N1의 반응,
///    자신이 "만들다 만" 세계에 떨어졌다는 자각, 그리고 몬스터 스탯/약점이
///    보이는 "디버그 시야" 능력을 처음 자각하는 장면까지 담는다.
///
/// 시즌1 메인 스토리(챕터 1~10)는 [seasonOneMainStory](story_data.dart)에
/// 따로 정의되어 있다.
final StoryModel prologueBeforeName = StoryModel(
  id: 'prologue_before_name',
  backgroundUrl: AppImages.storyBackground('prologue'),
  lines: [
    StoryLine(
      speaker: '???',
      thumbnailUrl: null,
      text: '으... 이 매크로 하나 넣었다고 왜 밸런스가 통째로 깨지는 거야. 새벽 3시에 대체 무슨 짓을 하고 있는 거지, 나는.',
    ),
    StoryLine(
      speaker: '???',
      thumbnailUrl: null,
      text: "'차원의 균열' 이벤트 트리거 버그... 이것만 잡으면 끝이다. 좋아, 마지막으로 딱 한 줄만 더 고치고—",
    ),
    StoryLine(
      speaker: '???',
      thumbnailUrl: null,
      text: '됐다. 이제 빌드만 돌리면... 어? 어어?! 모니터가 왜 이렇게 밝아지는—',
    ),
    StoryLine(
      speaker: '???',
      thumbnailUrl: null,
      text: '크윽...! 눈이, 눈이 안 떠져—',
    ),
    StoryLine(
      speaker: 'N1',
      thumbnailUrl: AppImages.playerThumbnail('N1'),
      characterId: 'N1',
      text: '저, 저기요! 정신 차려보세요! ...어라, 숨은 붙어있는데. 다행이다, 살아있...',
    ),
    StoryLine(
      speaker: 'N1',
      thumbnailUrl: AppImages.playerThumbnail('N1'),
      characterId: 'N1',
      text: '어? 어어?! 자, 잠깐만요— 이, 이런 얼굴은... 서, 설마—',
    ),
    StoryLine(
      speaker: 'N1',
      thumbnailUrl: AppImages.playerThumbnail('N1'),
      characterId: 'N1',
      text: "세, 세상에... 고서에서만 전해지던 진짜 '남성'?! 대재앙 이후로 대륙에 단 한 분도 안 남았다던 그 존재가, 어째서 잿빛 숲 한복판에...!",
    ),
    StoryLine(
      speaker: 'N1',
      thumbnailUrl: AppImages.playerThumbnail('N1'),
      characterId: 'N1',
      text: '저, 저기, 앗, 정신이 드시나요?! 괘, 괜찮으신가요? 저는 이 근방을 지키는 수습 기사예요. 이름은... 아, 아니 그보다!',
    ),
    StoryLine(
      speaker: 'N1',
      thumbnailUrl: AppImages.playerThumbnail('N1'),
      characterId: 'N1',
      text: '부디, 부디 당신의 존함을 여쭤도 될까요...? 이렇게 뵙게 된 것도 인연인데, 이름 없이 지나칠 순 없잖아요.',
    ),
  ],
);

/// 닉네임 입력 직후 이어지는 후반부 — [GameEntryScreen]이
/// [NicknameScreen]에서 돌아오면 곧바로 재생한다.
final StoryModel prologueAfterName = StoryModel(
  id: 'prologue_after_name',
  backgroundUrl: AppImages.storyBackground('prologue'),
  lines: [
    StoryLine(
      speaker: 'N1',
      thumbnailUrl: AppImages.playerThumbnail('N1'),
      characterId: 'N1',
      text: '{nickname}... {nickname}님이시군요! 좋은 이름이에요. 저는 이 잿빛 숲 경계를 맡은 수습 기사, N1이라고 해요!',
    ),
    StoryLine(
      speaker: '지휘관',
      thumbnailUrl: null,
      text: '그래... 일단 상황부터 정리하자. 여기가 아르카디아? 내가 만들다 만 그 대륙에... 진짜로 떨어졌다고?',
    ),
    StoryLine(
      speaker: 'N1',
      thumbnailUrl: AppImages.playerThumbnail('N1'),
      characterId: 'N1',
      text: '네? 만들다 마셨다니... 무슨 말씀이신지? 혹시 머리를 심하게 부딪히신 건 아니시죠?!',
    ),
    StoryLine(
      speaker: '지휘관',
      thumbnailUrl: null,
      text: '아니, 아무것도 아니야. ...근데 저쪽 수풀 뒤에 있는 저 슬라임, 왜 체력바랑 약점 속성이 눈앞에 둥둥 떠다니는 것처럼 보이지?',
    ),
    StoryLine(
      speaker: 'N1',
      thumbnailUrl: AppImages.playerThumbnail('N1'),
      characterId: 'N1',
      text: '체, 체력바요?! {nickname}님, 지금 뭐가 보이신다는 거예요?!',
    ),
    StoryLine(
      speaker: '지휘관',
      thumbnailUrl: null,
      text: "'물리 방어 낮음, 화속성 약점'... 이거 완전 어제 내가 대충 하드코딩한 슬라임 스탯표잖아. 와, 이 능력 뭐야, 진짜 편하네.",
    ),
    StoryLine(
      speaker: 'N1',
      thumbnailUrl: AppImages.playerThumbnail('N1'),
      characterId: 'N1',
      text: "저, 전 아무것도 안 보이는데... 서, 설마 그게 바로 전설의 '신탁의 눈'인가요?! 신께서 내리신 전술안!",
    ),
    StoryLine(
      speaker: '지휘관',
      thumbnailUrl: null,
      text: '...신탁까진 아니고. 아무튼 눈에 보이는 대로만 말해줄 테니까, N1 너는 몸으로 움직여줘. 콤비로 가보자.',
    ),
    StoryLine(
      speaker: 'N1',
      thumbnailUrl: AppImages.playerThumbnail('N1'),
      characterId: 'N1',
      text: '네! {nickname}님과 함께라면 뭐든 할 수 있을 것 같아요! 잘 부탁드립니다, 지휘관님!',
    ),
    StoryLine(
      speaker: '지휘관',
      thumbnailUrl: null,
      text: '좋아. 흩어진 동료들을 모아서, 이 세계를 집어삼키려는 차원의 균열부터 막아야겠지. ...나 원, 내가 만든 버그를 내가 직접 잡으러 다니게 될 줄이야.',
    ),
  ],
);
