/// `game_config` 테이블의 `id='cp_weights'` 행 — 총 전투력
/// ([GameManager.totalCombatPower]) 계산식에 들어가는 가중치 두 개를 앱
/// 업데이트 없이 서버에서 실시간으로 조정할 수 있게 한다
/// ([ConfigManager] 참고). 기본 생성자 자체가 이미 안전한 기본값이라,
/// 네트워크/파싱이 전부 실패해도 이 값 그대로 쓰면 기존 동작(하드코딩
/// 20.0/10.0이던 시절)과 100% 동일하다.
class CombatPowerWeights {
  const CombatPowerWeights({this.defWeight = 20.0, this.offenseWeight = 10.0});

  /// 방어 점수 계산의 방어력 가중치 — `방어 점수 = 체력 + (방어력 *
  /// defWeight) * (1 + 회피율 + 방어율)`. 기본 20.0.
  final double defWeight;

  /// 최종 전투력 계산의 공격 점수 가중치 — `최종 전투력 = (공격 점수 *
  /// offenseWeight) + 방어 점수`. 기본 10.0.
  final double offenseWeight;

  /// [json]의 `def_weight`/`offense_weight` 컬럼이 null이거나 통째로 없어도
  /// (컬럼명 오타, 행 자체가 비어 있음 등) 절대 예외를 던지지 않고 안전한
  /// 기본값으로 대체한다 — 이 매니저의 존재 이유가 "값을 못 가져와도 게임이
  /// 죽지 않는 것"이므로, 캐스팅 실패는 어떤 경우에도 허용하지 않는다.
  factory CombatPowerWeights.fromJson(Map<String, dynamic> json) => CombatPowerWeights(
    defWeight: (json['def_weight'] as num?)?.toDouble() ?? 20.0,
    offenseWeight: (json['offense_weight'] as num?)?.toDouble() ?? 10.0,
  );
}
