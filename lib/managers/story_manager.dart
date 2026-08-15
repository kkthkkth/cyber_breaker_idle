import 'package:shared_preferences/shared_preferences.dart';

/// 스토리(프롤로그 등) 클리어 여부만 담당하는 가벼운 매니저 — 대사 데이터는
/// story_model.dart, 재생 UI는 StoryDialogWidget이 맡는다. 상태가 화면
/// 전환(전체 앱 재빌드) 한 번에만 영향을 주고 이후 구독자가 없어
/// ChangeNotifier로 만들 필요는 없다([MyApp]이 직접 setState로 전환한다).
class StoryManager {
  StoryManager._internal();

  static final StoryManager instance = StoryManager._internal();

  static const String _prologueKey = 'story_prologue_cleared';

  bool isPrologueCleared = false;

  Future<void> loadData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    isPrologueCleared = prefs.getBool(_prologueKey) ?? false;
  }

  /// 스토리를 끝까지 봤든 스킵했든 결과는 동일하게 "클리어"로 취급한다 —
  /// 다음 실행부터는 [MyApp]이 이 값을 보고 프롤로그를 건너뛴다.
  Future<void> markPrologueCleared() async {
    if (isPrologueCleared) {
      return;
    }
    isPrologueCleared = true;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prologueKey, true);
  }
}
