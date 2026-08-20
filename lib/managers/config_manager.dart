import 'package:flutter/foundation.dart';

import '../models/combat_power_weights_model.dart';
import 'supabase_manager.dart';

/// 앱 업데이트 없이 서버에서 즉시 조정 가능한 게임 밸런스 설정값을
/// 관장하는 싱글턴 — 지금은 총 전투력 가중치([combatPowerWeights]) 하나만
/// 담지만, 앞으로 다른 서버 조정 값이 늘어나면 이 매니저에 필드만 추가하면
/// 된다.
///
/// [ChangeNotifier]인 이유: 인게임 도중 [loadConfig]가 다시 호출돼 값이
/// 바뀌면([_notifyIfChanged]), 이 매니저를 구독 중인 UI(총 전투력 배너 —
/// comprehensive_stats_dialog.dart/item_detail_dialog.dart)가 닫았다 열
/// 필요 없이 즉시 새 가중치로 다시 그려진다(요구사항: "UI 실시간 반영").
class ConfigManager extends ChangeNotifier {
  ConfigManager._internal();

  static final ConfigManager instance = ConfigManager._internal();

  /// 네트워크 에러/파싱 실패 등 무엇이 잘못되든 항상 안전한 기본값
  /// (20.0/10.0)으로 시작한다 — [CombatPowerWeights]의 기본 생성자 자체가
  /// 이미 그 기본값이므로, [loadConfig]가 아직 끝나지 않았거나 완전히
  /// 실패해도 [GameManager.totalCombatPower]는 하드코딩 시절과 정확히
  /// 같은 값으로 동작한다.
  CombatPowerWeights combatPowerWeights = const CombatPowerWeights();

  /// main()이 앱 시작 시 한 번 호출 — 서버 행이 없거나(조회 실패) 파싱이
  /// 깨져도 절대 예외를 던지지 않고 기존 [combatPowerWeights](기본값 또는
  /// 이전에 성공적으로 불러온 값)를 그대로 유지한다.
  Future<void> loadConfig() async {
    final Map<String, dynamic>? row = await SupabaseManager.instance.fetchCombatPowerWeights();
    if (row == null) {
      debugPrint(
        '[ConfigManager] 전투력 가중치 설정을 가져오지 못해 기본값'
        '(defWeight=20.0, offenseWeight=10.0)을 유지합니다.',
      );
      return;
    }

    try {
      final CombatPowerWeights parsed = CombatPowerWeights.fromJson(row);
      combatPowerWeights = parsed;
      notifyListeners();
    } catch (error) {
      debugPrint('[ConfigManager] 전투력 가중치 설정 파싱 실패, 기존 값을 유지합니다: $error');
    }
  }
}
