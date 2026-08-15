import 'stage_calculator.dart';

/// [주의: 독립 모듈] [StageCalculator]와 같은 이유로, 이 파일도 아직
/// 어디에도 연결되지 않은 독립 데이터 구조다 — 실제로 게임에 붙이려면
/// (예: `GameManager`가 새 스테이지 체계로 전환된 뒤) 여기 정의된
/// [StoryTrigger] 목록을 순회하며 "현재 (stage, subStage)와 일치하는
/// 트리거가 있는지" 확인하는 연결 코드가 별도로 필요하다.
///
/// 스토리가 뜨는 시점은 두 가지뿐이다:
///   - [StoryTriggerMoment.chapterOpening]: 챕터에 막 진입한 순간
///     (X-1, 예: 1-1/10-1/20-1) — "챕터 첫 진입 시점".
///   - [StoryTriggerMoment.chapterBossIntro]: 챕터의 마지막 보스전에
///     들어선 순간(X9-10, 예: 9-10/19-10) — "보스전 직전". 보스를 처치한
///     "직후"는 별도의 트리거가 아니라, 자연스럽게 다음 챕터의
///     [chapterOpening]으로 이어진다(보스를 깨면 스테이지가 그다음
///     챕터의 1번째로 넘어가므로) — 기존 시즌1 스토리 시스템
///     ([MainStoryManager]/`ChapterStory.opening`+`.bossIntro`)과 동일한
///     설계다.
enum StoryTriggerMoment { chapterOpening, chapterBossIntro }

/// 스토리 한 편이 "언제" 뜨는지를 나타내는 트리거 — 실제 대사 내용은 담지
/// 않고 [storyId]로 참조만 한다(대사 데이터는 [chapterSynopses]/향후
/// StoryModel 쪽에 따로 둔다). [stage]/[subStage]는 손으로 나열하지 않고
/// 전부 [StageCalculator]로부터 계산되므로, 챕터 구조가 바뀌어도(챕터 수가
/// 늘어나는 등) 이 목록이 자동으로 맞춰진다.
class StoryTrigger {
  const StoryTrigger({
    required this.moment,
    required this.chapter,
    required this.stage,
    required this.subStage,
    required this.storyId,
  });

  final StoryTriggerMoment moment;
  final int chapter;
  final int stage;
  final int subStage;

  /// [chapterSynopses]의 [ChapterSynopsis.chapter]와 짝지어 실제 대사
  /// 내용을 찾아오는 키 — 예: `'chapter_3_opening'`, `'chapter_3_boss'`.
  final String storyId;

  /// UI/디버그 표기용 — "3-1" 같은 "스테이지-서브스테이지" 라벨.
  String get stageLabel => '$stage-$subStage';

  /// 지금 (stage, subStage) 위치가 정확히 이 트리거가 떠야 하는 지점인지.
  bool matches(int currentStage, int currentSubStage) =>
      stage == currentStage && subStage == currentSubStage;
}

/// 챕터 1~[chapterCount] 전부에 대해 "첫 진입"/"보스전" 두 트리거를
/// 자동으로 만든다 — 스테이지 번호를 손으로 하나씩 나열하지 않고
/// [StageCalculator.firstStageOf]/[StageCalculator.lastStageOf]로 계산해서
/// 만들기 때문에, 트리거 목록이 항상 챕터 구조와 어긋나지 않는다.
List<StoryTrigger> buildStoryTriggers({int chapterCount = StageCalculator.maxChapter}) {
  final List<StoryTrigger> triggers = [];
  for (int chapter = 1; chapter <= chapterCount; chapter++) {
    triggers.add(
      StoryTrigger(
        moment: StoryTriggerMoment.chapterOpening,
        chapter: chapter,
        stage: StageCalculator.firstStageOf(chapter),
        subStage: 1,
        storyId: 'chapter_${chapter}_opening',
      ),
    );
    triggers.add(
      StoryTrigger(
        moment: StoryTriggerMoment.chapterBossIntro,
        chapter: chapter,
        stage: StageCalculator.lastStageOf(chapter),
        subStage: StageCalculator.maxSubStage,
        storyId: 'chapter_${chapter}_boss',
      ),
    );
  }
  return triggers;
}
