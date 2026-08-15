import '../constants/app_images.dart';

/// 비주얼 노벨 대사 한 줄 — 화자 이름, 초상화(썸네일) URL, 대사 텍스트.
/// [thumbnailUrl]은 항상 [AppImages]를 거쳐 만들어야 한다(원시 문자열
/// 금지) — 실제 존재하지 않는 캐릭터 ID를 쓰면 CustomSafeImage가 조용히
/// placeholder로 대체해버려 오타를 알아채기 어렵다.
///
/// [thumbnailUrl]이 null이면(플레이어 자신인 "지휘관", 특정 1인을 가리키지
/// 않는 "모든 동료들" 같은 그룹 대사) [StoryDialogWidget]이 초상화 대신
/// 기사단 엠블럼을 그린다 — 존재하지 않는 캐릭터 이미지를 억지로 참조하지
/// 않기 위함이다.
class StoryLine {
  const StoryLine({
    required this.speaker,
    required this.thumbnailUrl,
    required this.text,
  });

  final String speaker;
  final String? thumbnailUrl;
  final String text;
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

/// 최초 실행 시 보여주는 프롤로그 — 몬스터의 침공을 막아내고 흩어진 동료를
/// 모으기 위해 모험을 떠나는 중세 판타지 기사단 이야기. 마지막에 합류하는
/// 동료 "에스텔"은 [StoryManager]가 프롤로그 클리어 시 실제로 지급하는
/// R등급 캐릭터와 짝을 맞춘 연출이다 — [EquipmentManager.grantStarterCharacters]
/// 참고. 시즌1 메인 스토리(챕터 1~10)는 [seasonOneMainStory](story_data.dart)
/// 에 따로 정의되어 있다.
final StoryModel prologueStory = StoryModel(
  id: 'prologue',
  backgroundUrl: AppImages.storyBackground('prologue'),
  lines: [
    StoryLine(
      speaker: '카일',
      thumbnailUrl: AppImages.playerThumbnail('N1'),
      text: '...결국 여기까지 왔군. 정체불명의 몬스터 무리가 왕국 전역을 휩쓸고 있어.',
    ),
    StoryLine(
      speaker: '카일',
      thumbnailUrl: AppImages.playerThumbnail('N1'),
      text: '함께 싸우던 기사단 동료들도 뿔뿔이 흩어져 버렸다. 이대로는 왕국을 지킬 수 없어.',
    ),
    StoryLine(
      speaker: '카일',
      thumbnailUrl: AppImages.playerThumbnail('N1'),
      text: '흩어진 동료들을 다시 모아야 한다. 일단 나 혼자라도... 움직여야겠지.',
    ),
    StoryLine(
      speaker: '에스텔',
      thumbnailUrl: AppImages.playerThumbnail('R1'),
      text: '잠깐! 혼자 가려는 거야? 나도 같이 갈게, 카일.',
    ),
    StoryLine(
      speaker: '카일',
      thumbnailUrl: AppImages.playerThumbnail('N1'),
      text: '에스텔? 무사했구나... 다행이야.',
    ),
    StoryLine(
      speaker: '에스텔',
      thumbnailUrl: AppImages.playerThumbnail('R1'),
      text: '지금부터는 함께야. 흩어진 동료들, 반드시 다 찾아내서 왕국을 되찾자.',
    ),
    StoryLine(
      speaker: '카일',
      thumbnailUrl: AppImages.playerThumbnail('N1'),
      text: '좋아. 우리의 모험은 지금부터 시작이다!',
    ),
  ],
);
