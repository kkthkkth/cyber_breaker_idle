import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_manager.dart';
import 'supabase_manager.dart';
import 'talent_manager.dart';
import 'title_manager.dart';

/// **환생(Rebirth)** — 이 게임의 프레스티지 시스템. 스테이지 진행도
/// (chapter/stage)와 골드, 그리고 그 골드로 산 캐릭터 기본 레벨을
/// 초기화하는 대신([GameManager.resetForPrestige] 참고), 이번 판에서
/// 도달한 만큼([GameManager.absoluteStage]) "환생석"을 얻어 누적한다.
/// 환생석은 [attackBonus]/[goldBonus]로 변환되어
/// [GameManager.attackPower]/[GameManager._onMonsterDefeated]에 길드
/// 버프와 똑같은 방식(곱산)으로 항상 적용된다 — 환생할 때마다 다음 판은
/// 예전 진행도를 더 빠르게 따라잡고 더 멀리 가는, 방치형 RPG 특유의
/// "무한 성장" 루프를 만든다.
///
/// [PotionManager]/[TowerFloorManager]와 같은 관례: 로컬(SharedPreferences)
/// 이 1차 신뢰 소스이고, Supabase `profiles` 테이블(`prestige_count`/
/// `prestige_core_points` 컬럼 — Dart 필드명은 [rebirthStones]로 바꿨지만
/// 기존 로컬 저장 키/서버 컬럼명은 하위 호환을 위해 그대로 유지한다)은
/// 기기 변경/재설치에도 진행도를 지키는 백업 계층이다.
class PrestigeManager extends ChangeNotifier {
  PrestigeManager._internal();

  static final PrestigeManager instance = PrestigeManager._internal();

  /// 이 챕터 이상 도달해야 환생을 실행할 수 있다 — 너무 이른 리셋으로
  /// 되레 좌절감만 주는 것을 막는 최소 문턱.
  static const int minChapterToPrestige = 10;

  static const double attackBonusPerRebirthStone = 0.01;
  static const double goldBonusPerRebirthStone = 0.01;

  /// 누적 환생석 — 환생할 때마다 [prestige]가 [rebirthStonesForRun]만큼
  /// **더한다**(예전 "코어 포인트"처럼 절대값을 다시 계산해 덮어쓰지
  /// 않는다). 환생을 아무리 반복해도 절대 줄어들지 않는다.
  int rebirthStones = 0;

  /// 지금까지 환생을 실행한 누적 횟수 — 절대 리셋되지 않는다.
  int prestigeCount = 0;

  double get attackBonus => rebirthStones * attackBonusPerRebirthStone;
  double get goldBonus => rebirthStones * goldBonusPerRebirthStone;

  bool get canPrestige => GameManager.instance.highestReachedChapter >= minChapterToPrestige;

  /// [absoluteStage](챕터+스테이지를 하나로 합친 절대 진행도,
  /// [GameManager.absoluteStage])까지 도달한 뒤 지금 환생하면 새로 얻는
  /// 환생석 — 도달한 스테이지가 높을수록 더 많이 받는다. absoluteStage
  /// 20당 환생석 1개, 최소 1개 — 간단하고 예측 가능한 1차 공식(수치
  /// 밸런스는 추후 실측 후 조정 대상). [canPrestige]가 이미 최소 챕터
  /// (10챕터 = absoluteStage 91 이상)로 걸러 두므로 실제로 0이 나올 일은
  /// 없지만, 방어적으로 최소 1을 보장한다. 순수 함수라 단위 테스트
  /// 가능(테스트를 위해 public).
  @visibleForTesting
  static int rebirthStonesForRun(int absoluteStage) {
    final int stones = absoluteStage ~/ 20;
    return stones < 1 ? 1 : stones;
  }

  /// 지금 환생을 실행하면 얻게 될 환생석 — 확인 다이얼로그
  /// ([RebirthConfirmDialog])가 요구사항 문구("환생석 N개를 얻습니다")에
  /// 그대로 쓴다. [GameManager.absoluteStage]는 리셋되기 전의 "이번 판"
  /// 진행도다.
  int get previewRebirthStones => rebirthStonesForRun(GameManager.instance.absoluteStage);

  /// 단위 테스트 전용 — 실제 환생석/횟수를 네트워크 없이 직접 주입한다
  /// ([TowerFloorManager.debugSeedForTest]와 같은 관례).
  @visibleForTesting
  void debugSeedForTest({required int rebirthStones, required int prestigeCount}) {
    this.rebirthStones = rebirthStones;
    this.prestigeCount = prestigeCount;
  }

  /// 환생을 실행한다 — [canPrestige]가 아니면 아무것도 하지 않고 null.
  /// 성공하면 [GameManager.resetForPrestige]로 진행도를 되돌리고, 새로
  /// 얻은 환생석을 기존 누적치에 더한 뒤 로컬/서버에 반영한다. 반환값은
  /// 이번 환생으로 "방금" 얻은 환생석 개수 — 호출부(UI)가 리셋 이후
  /// (absoluteStage가 1로 돌아간 뒤)에도 정확한 획득량을 토스트에 쓸 수
  /// 있도록, 리셋 전에 미리 계산해 돌려준다.
  Future<int?> prestige() async {
    if (!canPrestige) {
      return null;
    }
    final int gained = previewRebirthStones;

    rebirthStones += gained;
    prestigeCount += 1;
    GameManager.instance.resetForPrestige();

    notifyListeners();
    await _saveLocal();
    unawaited(
      SupabaseManager.instance.updatePrestigeData(count: prestigeCount, stones: rebirthStones),
    );
    // 칭호(Title) 자동 획득 판정 — prestige_count 조건 타입.
    TitleManager.instance.checkAndGrantTitles();
    // 특성(별자리) 트리 포인트 지급 — 요구사항: "환생 시에 talent_points가
    // 지급되는 훅을 추가".
    TalentManager.instance.grantTalentPoints();
    return gained;
  }

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 채운 뒤, 서버 값이
  /// 더 크면(기기 변경/재설치로 로컬이 비어 있는 경우 등) 그쪽으로
  /// 갱신한다.
  Future<void> loadData() async {
    await _loadLocal();

    final ({int count, int stones})? remote = await SupabaseManager.instance.fetchPrestigeData();
    if (remote != null && remote.stones > rebirthStones) {
      rebirthStones = remote.stones;
      prestigeCount = remote.count;
      await _saveLocal();
    }
    notifyListeners();
  }

  static const String _saveKey = 'prestige_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      // 'corePoints' 키는 기존 로컬 저장 데이터와의 하위 호환을 위해 그대로
      // 둔다(값만 이제 [rebirthStones]다) — 키를 바꾸면 이미 설치된
      // 기기에서 다음 로드 때 누적 환생석이 조용히 0으로 보인다.
      jsonEncode({'corePoints': rebirthStones, 'prestigeCount': prestigeCount}),
    );
  }

  Future<void> _loadLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      return;
    }
    try {
      final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
      rebirthStones = (data['corePoints'] as num?)?.toInt() ?? rebirthStones;
      prestigeCount = (data['prestigeCount'] as num?)?.toInt() ?? prestigeCount;
    } catch (error) {
      debugPrint('[PrestigeManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }
  }
}
