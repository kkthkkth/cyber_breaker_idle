import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 최초 실행 온보딩 튜토리얼(3단계: 전투 화면 → 샵 탭 → 가챠 버튼)의
/// 진행 상태를 관장하는 싱글턴. [TutorialOverlay]가 이 매니저를 구독해
/// 지금 강조해야 할 위젯([currentTargetKey])과 안내 문구
/// ([currentMessage])를 그린다 — 실제로 그 위젯을 탭했을 때 다음 단계로
/// 넘기는 것은 각 화면(홈/메인 내비게이션/상점)의 책임이다
/// ([advance] 호출부 참고).
class TutorialManager extends ChangeNotifier {
  TutorialManager._internal();

  static final TutorialManager instance = TutorialManager._internal();

  static const int totalSteps = 3;
  static const String _completedKey = 'tutorial_completed';

  /// 강조할 위젯 3개 — 각 화면이 해당 위젯을 이 키로 감싸 둬야
  /// [TutorialOverlay]가 화면상 위치를 잴 수 있다.
  static final GlobalKey battleViewKey = GlobalKey(debugLabel: 'tutorial_battle_view');
  static final GlobalKey shopNavKey = GlobalKey(debugLabel: 'tutorial_shop_nav');
  static final GlobalKey freeGachaButtonKey = GlobalKey(debugLabel: 'tutorial_free_gacha_button');

  static const List<String> _messages = [
    '화면을 탭해서 몬스터를 공격하세요!',
    '하단 메뉴에서 상점으로 이동해 보세요.',
    '무료 가챠를 뽑아보세요!',
  ];

  static final List<GlobalKey> _targetKeys = [battleViewKey, shopNavKey, freeGachaButtonKey];

  bool isCompleted = true;
  int currentStep = 0;

  bool get isActive => !isCompleted && currentStep < totalSteps;

  GlobalKey? get currentTargetKey => isActive ? _targetKeys[currentStep] : null;

  String? get currentMessage => isActive ? _messages[currentStep] : null;

  /// main()이 앱 시작 시 한 번 호출 — 이전에 끝냈으면 다시 뜨지 않는다.
  /// 진행 중이던 단계는 따로 저장하지 않는다(완료 여부만 영속화) — 그래서
  /// 완료 전이면 항상 0단계부터 다시 보여준다.
  Future<void> loadData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    isCompleted = prefs.getBool(_completedKey) ?? false;
    currentStep = 0;
    notifyListeners();
  }

  /// 지금 강조 중인 위젯을 유저가 실제로 탭했을 때 각 화면이 호출한다.
  /// 마지막 단계였다면 [_complete]까지 이어서 처리한다.
  void advance() {
    if (!isActive) {
      return;
    }
    currentStep++;
    if (currentStep >= totalSteps) {
      _complete();
      return;
    }
    notifyListeners();
  }

  /// "건너뛰기" — 남은 단계를 전부 스킵하고 곧바로 완료 처리한다.
  void skip() => _complete();

  void _complete() {
    isCompleted = true;
    notifyListeners();
    _saveCompleted();
  }

  Future<void> _saveCompleted() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKey, true);
  }
}
