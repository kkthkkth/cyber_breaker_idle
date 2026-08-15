/// 스테이지/챕터 판별 순수 계산 유틸리티 — 확정된 신규 스테이지 구조를
/// 다룬다.
///
/// [주의: 독립 모듈] 이 파일은 지금 라이브로 동작 중인
/// `GameManager.chapter`/`.stage`(챕터 1~10을 별도 필드로 추적, 서브스테이지
/// 1~10, 챕터당 정확히 10개 = 총 100개)와는 **다른 번호 체계**이며, 기존
/// 코드 어디에서도 아직 참조하지 않는다. 실제 게임 진행/세이브 데이터에는
/// 아무 영향이 없다 — 나중에 이 체계로 전환하기로 결정하면 그때
/// `GameManager`를 여기에 연결하는 별도 작업이 필요하다.
///
/// 확정된 챕터 구조:
/// ```
/// 1챕터: 스테이지 1~9   (서브스테이지 1~10, 마지막 보스전 9-10)
/// 2챕터: 스테이지 10~19 (마지막 보스전 19-10)
/// 3챕터: 스테이지 20~29 (마지막 보스전 29-10)
/// 4챕터: 스테이지 30~39 (마지막 보스전 39-10)
/// 5챕터: 스테이지 40~49 (마지막 보스전 49-10)
/// 6챕터: 스테이지 50~59 (마지막 보스전 59-10)
/// 7챕터: 스테이지 60~69 (마지막 보스전 69-10)
/// 8챕터: 스테이지 70~79 (마지막 보스전 79-10)
/// 9챕터: 스테이지 80~89 (마지막 보스전 89-10)
/// 10챕터: 스테이지 90~99 (마지막 보스전 99-10)
/// ```
/// 챕터 1만 스테이지 번호가 9개(1~9)이고 나머지는 전부 10개씩이다 — 억지로
/// 맞춘 예외가 아니라 `stage ~/ 10`이 1~9에서 전부 0이 되는 것뿐인
/// 자연스러운 결과다([chapterOf] 참고). `stage`는 챕터 경계에서 리셋되지
/// 않고 1부터 99까지 계속 증가하며, `subStage`(1~10)만 챕터 안에서
/// 반복된다.
class StageCalculator {
  const StageCalculator._();

  /// 챕터 하나에 들어있는 서브스테이지 개수(1~10 고정).
  static const int maxSubStage = 10;

  /// 게임에 정의된 총 챕터 수.
  static const int maxChapter = 10;

  /// 전체 스테이지 번호의 최댓값(10챕터의 마지막 스테이지) — `maxChapter *
  /// maxSubStage - 1`과 같다.
  static const int maxStageNumber = 99;

  /// [stage](1~99)가 몇 챕터에 속하는지 — `stage ~/ 10 + 1`. 스테이지
  /// 1~9는 나눗셈 결과가 전부 0이라 챕터 1, 10~19는 1이라 챕터 2, ...
  /// 90~99는 9라 챕터 10이 된다.
  static int chapterOf(int stage) {
    assert(stage >= 1 && stage <= maxStageNumber, 'stage는 1~$maxStageNumber 이어야 합니다 (받은 값: $stage)');
    return (stage ~/ 10) + 1;
  }

  /// [chapter](1~10)의 첫 번째 스테이지 번호 — 챕터 1만 1, 나머지는
  /// `(chapter - 1) * 10`(예: 챕터 2 → 10, 챕터 10 → 90).
  static int firstStageOf(int chapter) {
    assert(
      chapter >= 1 && chapter <= maxChapter,
      'chapter는 1~$maxChapter 이어야 합니다 (받은 값: $chapter)',
    );
    return chapter == 1 ? 1 : (chapter - 1) * 10;
  }

  /// [chapter](1~10)의 마지막(보스) 스테이지 번호 — `chapter * 10 - 1`
  /// (예: 챕터 1 → 9, 챕터 2 → 19, 챕터 10 → 99).
  static int lastStageOf(int chapter) {
    assert(
      chapter >= 1 && chapter <= maxChapter,
      'chapter는 1~$maxChapter 이어야 합니다 (받은 값: $chapter)',
    );
    return chapter * 10 - 1;
  }

  /// 이 (stage, subStage) 조합이 챕터의 마지막 보스전(X9-10 형태)인지 —
  /// 스테이지 번호의 일의 자리가 9이면서 서브스테이지가 마지막(10)일 때만
  /// true.
  static bool isBossStage(int stage, int subStage) =>
      stage % 10 == 9 && subStage == maxSubStage;

  /// 이 (stage, subStage) 조합이 챕터에 막 처음 진입한 순간인지 —
  /// (1-1, 10-1, 20-1, ... 90-1) 형태일 때만 true. 스토리 "오프닝" 트리거
  /// 조건과 정확히 일치한다.
  static bool isChapterFirstEntry(int stage, int subStage) =>
      subStage == 1 && stage == firstStageOf(chapterOf(stage));
}
