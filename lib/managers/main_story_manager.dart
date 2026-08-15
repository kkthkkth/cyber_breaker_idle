import 'package:shared_preferences/shared_preferences.dart';

import '../constants/story_data.dart';
import '../models/story_model.dart';
import 'game_manager.dart';

/// 시즌1 메인 스토리(챕터 1~10)의 진행 상태를 담당하는 가벼운 매니저 —
/// 실제 대사 데이터는 story_data.dart의 [seasonOneMainStory], 재생 UI는
/// [StoryDialogWidget]이 맡는다. [StoryManager](프롤로그 전용)와 같은
/// 이유로 ChangeNotifier로 만들지 않았다.
///
/// 챕터당 두 번의 1회성 연출을 각각 독립적으로 추적한다:
///   - [_openingShown]: 챕터 첫 스테이지(subStage 1) 진입 시의 오프닝.
///   - [_bossIntroShown]: 보스 스테이지(subStage 10) 진입 시의 보스 대화.
/// "챕터가 클리어됐는지"([isChapterCleared])는 [maxClearedChapter](단조
/// 증가, 직접 저장)로 판정한다 — [GameManager.chapter]는 "현재 위치"라
/// 패배 시 다시 내려갈 수 있으므로, 그 값을 그대로 비교(`chapter > n`)하면
/// 이미 클리어한 챕터가 패배 한 번에 다시 "미해금"으로 보이는 버그가
/// 생긴다. [maxClearedChapter]는 클리어 기록이라 절대 줄어들지 않는다.
class MainStoryManager {
  MainStoryManager._internal();

  static final MainStoryManager instance = MainStoryManager._internal();

  static const String _openingSaveKey = 'main_story_opening_shown';
  static const String _bossIntroSaveKey = 'main_story_boss_intro_shown';
  static const String _maxClearedChapterSaveKey = 'main_story_max_cleared_chapter';

  final Set<int> _openingShown = {};
  final Set<int> _bossIntroShown = {};

  /// 유저가 실제로 클리어한(보스를 처치한) 가장 높은 챕터 번호.
  int maxClearedChapter = 0;

  bool isOpeningShown(int chapter) => _openingShown.contains(chapter);

  bool isBossIntroShown(int chapter) => _bossIntroShown.contains(chapter);

  /// 챕터 n을 실제로 클리어했는지 — [maxClearedChapter] 기준(위 클래스
  /// doc 참고). 아직 도달하지 못한 챕터는 항상 false(잠금).
  bool isChapterCleared(int chapter) => chapter <= maxClearedChapter;

  Future<void> loadData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final List<String>? savedOpening = prefs.getStringList(_openingSaveKey);
    if (savedOpening != null) {
      _openingShown
        ..clear()
        ..addAll(savedOpening.map(int.parse));
    }

    final List<String>? savedBossIntro = prefs.getStringList(_bossIntroSaveKey);
    if (savedBossIntro != null) {
      _bossIntroShown
        ..clear()
        ..addAll(savedBossIntro.map(int.parse));
    }

    // 이 필드가 생기기 전 세이브이거나(값이 없음) 어떤 이유로든 실제
    // 진행보다 뒤처져 있을 가능성에 대비해, 저장된 값과 "현재 챕터 - 1"
    // (=최소한 여기까지는 클리어했다는 확실한 사실) 중 더 큰 쪽을 취한다 —
    // 절대 줄어들지 않는다.
    final int savedMaxCleared = prefs.getInt(_maxClearedChapterSaveKey) ?? 0;
    final int inferredFromCurrentChapter =
        (GameManager.instance.chapter - 1).clamp(0, seasonOneMainStory.length);
    maxClearedChapter = savedMaxCleared > inferredFromCurrentChapter
        ? savedMaxCleared
        : inferredFromCurrentChapter;
  }

  /// [chapter]의 오프닝이 [seasonOneMainStory]에 정의되어 있고 아직 안
  /// 봤다면 그 [StoryModel]을 반환한다.
  StoryModel? pendingOpeningFor(int chapter) {
    if (isOpeningShown(chapter)) {
      return null;
    }
    return seasonOneMainStory[chapter]?.opening;
  }

  /// [chapter]의 보스 대화가 정의되어 있고 아직 안 봤다면 그 [StoryModel]을
  /// 반환한다.
  StoryModel? pendingBossIntroFor(int chapter) {
    if (isBossIntroShown(chapter)) {
      return null;
    }
    return seasonOneMainStory[chapter]?.bossIntro;
  }

  /// 스토리를 끝까지 보든 스킵하든 결과는 동일하게 "봤음"으로 저장한다.
  Future<void> markOpeningShown(int chapter) async {
    if (!_openingShown.add(chapter)) {
      return;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _openingSaveKey,
      _openingShown.map((c) => c.toString()).toList(),
    );
  }

  Future<void> markBossIntroShown(int chapter) async {
    if (!_bossIntroShown.add(chapter)) {
      return;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _bossIntroSaveKey,
      _bossIntroShown.map((c) => c.toString()).toList(),
    );
  }

  /// [chapter]를 클리어했다고(보스를 처치했다고) 기록한다 — 단조 증가라
  /// 이미 더 높은(또는 같은) 값이 있으면 아무 것도 하지 않는다.
  /// main.dart의 GameManager.onChapterAdvanced 콜백이 "챕터 (newChapter-1)을
  /// 방금 클리어했다"는 뜻으로 호출한다.
  Future<void> recordChapterCleared(int chapter) async {
    if (chapter <= maxClearedChapter) {
      return;
    }
    maxClearedChapter = chapter;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_maxClearedChapterSaveKey, maxClearedChapter);
  }
}
