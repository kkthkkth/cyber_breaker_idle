import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_manager.dart';
import 'supabase_manager.dart';

/// "오버클럭"(Overclock) — 이 게임의 프레스티지(환생) 시스템. 스테이지
/// 진행도(chapter/stage)와 골드를 초기화하는 대신, 지금까지 도달한 최고
/// 챕터([GameManager.highestReachedChapter]) 기준으로 영구 "코어 포인트"를
/// 얻는다. 코어 포인트는 [attackBonus]/[goldBonus]로 변환되어
/// [GameManager.attackPower]/[GameManager._onMonsterDefeated]에 길드 버프와
/// 똑같은 방식(곱산)으로 항상 적용된다 — 리셋할 때마다 다음 판은 예전
/// 진행도를 더 빠르게 따라잡고 더 멀리 가는, 방치형 RPG 특유의 "무한 성장"
/// 루프를 만든다.
///
/// [PotionManager]/[TowerFloorManager]와 같은 관례: 로컬(SharedPreferences)
/// 이 1차 신뢰 소스이고, Supabase `profiles` 테이블(`prestige_count`/
/// `prestige_core_points` 컬럼)은 기기 변경/재설치에도 진행도를 지키는
/// 백업 계층이다.
class PrestigeManager extends ChangeNotifier {
  PrestigeManager._internal();

  static final PrestigeManager instance = PrestigeManager._internal();

  /// 이 챕터 이상 도달해야 오버클럭을 실행할 수 있다 — 너무 이른 리셋으로
  /// 되레 좌절감만 주는 것을 막는 최소 문턱.
  static const int minChapterToPrestige = 10;

  static const double attackBonusPerCorePoint = 0.01;
  static const double goldBonusPerCorePoint = 0.01;

  int corePoints = 0;
  int prestigeCount = 0;

  double get attackBonus => corePoints * attackBonusPerCorePoint;
  double get goldBonus => corePoints * goldBonusPerCorePoint;

  bool get canPrestige => GameManager.instance.highestReachedChapter >= minChapterToPrestige;

  /// [chapter]에 도달했을 때 얻는 "총" 코어 포인트 — 실제로 벌어들인
  /// 증분이 아니라 이 챕터 기준의 절대값이다([prestige]가 이 값을 그냥 새
  /// [corePoints]로 덮어쓰지, 더하지 않는다). 챕터 2마다 코어 포인트
  /// 1개 — 간단하고 예측 가능한 1차 공식(수치 밸런스는 추후 실측 후
  /// 조정 대상). 순수 함수라 단위 테스트 가능(테스트를 위해 public).
  @visibleForTesting
  static int corePointsForChapter(int chapter) => chapter ~/ 2;

  /// 지금 오버클럭을 실행하면 얻게 될 코어 포인트 — 확인 다이얼로그가
  /// [corePoints](현재)와 나란히 보여준다.
  int get previewCorePoints => corePointsForChapter(GameManager.instance.highestReachedChapter);

  /// 단위 테스트 전용 — 실제 코어 포인트를 네트워크 없이 직접 주입한다
  /// ([TowerFloorManager.debugSeedForTest]와 같은 관례).
  @visibleForTesting
  void debugSeedForTest({required int corePoints, required int prestigeCount}) {
    this.corePoints = corePoints;
    this.prestigeCount = prestigeCount;
  }

  /// 오버클럭을 실행한다 — [canPrestige]가 아니거나, 지금 실행해도 얻는
  /// 코어 포인트가 기존과 같거나 적으면(같은 챕터에서 다시 누르는 등,
  /// 이득이 없는 리셋) 아무것도 하지 않고 false. 성공하면
  /// [GameManager.resetForPrestige]로 진행도를 되돌리고, 새 코어 포인트를
  /// 로컬/서버에 반영한다.
  Future<bool> prestige() async {
    if (!canPrestige) {
      return false;
    }
    final int newCorePoints = previewCorePoints;
    if (newCorePoints <= corePoints) {
      return false;
    }

    corePoints = newCorePoints;
    prestigeCount += 1;
    GameManager.instance.resetForPrestige();

    notifyListeners();
    await _saveLocal();
    unawaited(
      SupabaseManager.instance.updatePrestigeData(count: prestigeCount, corePoints: corePoints),
    );
    return true;
  }

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 채운 뒤, 서버 값이
  /// 더 크면(기기 변경/재설치로 로컬이 비어 있는 경우 등) 그쪽으로
  /// 갱신한다.
  Future<void> loadData() async {
    await _loadLocal();

    final ({int count, int corePoints})? remote = await SupabaseManager.instance.fetchPrestigeData();
    if (remote != null && remote.corePoints > corePoints) {
      corePoints = remote.corePoints;
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
      jsonEncode({'corePoints': corePoints, 'prestigeCount': prestigeCount}),
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
      corePoints = (data['corePoints'] as num?)?.toInt() ?? corePoints;
      prestigeCount = (data['prestigeCount'] as num?)?.toInt() ?? prestigeCount;
    } catch (error) {
      debugPrint('[PrestigeManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }
  }
}
