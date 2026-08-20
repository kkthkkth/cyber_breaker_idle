/// 차원의 균열(로그라이크 모드) 갈림길 카드 종류 — [RiftManager.currentCards]
/// 가 층마다 3장을 무작위로 뽑아 보여준다. [boss]는 10층/20층에서만
/// 강제로 뜨는 특수 카드([RiftManager]의 "확정 보스 조우" 참고).
enum RiftCardType { normalBattle, eliteBattle, rest, boss }

/// 갈림길 카드 한 장 — [RiftScreen]이 그대로 그린다.
class RiftCard {
  const RiftCard({required this.type, required this.title, required this.description});

  final RiftCardType type;
  final String title;
  final String description;
}

/// [RiftScreen]/[RiftManager]가 공유하는 카드 표시 텍스트 — 카드 자체는
/// 매번 새로 만들 필요가 없는 고정 문구라 여기 하나씩만 둔다.
class RiftCardPool {
  const RiftCardPool._();

  static const RiftCard normalBattle = RiftCard(
    type: RiftCardType.normalBattle,
    title: '일반 전투',
    description: '무난한 세기의 몬스터와 싸운다.',
  );

  static const RiftCard eliteBattle = RiftCard(
    type: RiftCardType.eliteBattle,
    title: '엘리트 전투',
    description: '훨씬 강하지만 그만큼 더 좋은 유물을 준다.',
  );

  static const RiftCard rest = RiftCard(
    type: RiftCardType.rest,
    title: '휴식처',
    description: '전투 없이 체력을 회복하고 다음 층으로 이동한다.',
  );

  /// 10층/20층 "확정 보스 조우" 전용 카드 — [RiftManager._rollCards]가 이
  /// 층에서는 무작위 뽑기 대신 이 카드 3장을 그대로 채운다.
  static const RiftCard boss = RiftCard(
    type: RiftCardType.boss,
    title: '보스 조우',
    description: '이 층의 수호자 — 일반/엘리트보다 훨씬 강력한 진짜 벽.',
  );
}

/// [RiftRelic.effect] 값 — [RiftManager]가 [RiftManager.equippedRelics]에
/// 같은 효과를 가진 유물이 여러 개 쌓이면 값을 전부 더해(가산) 적용한다.
enum RiftRelicEffect { attackPercent, defensePercent, critRatePercent, lifeStealPercent, hpRegenPerFloor }

/// 임시 유물(Rift Relic) 하나 — 전투 승리 시 [RiftManager.offerRelics]가
/// 뽑은 후보 3개 중 하나를 고르면 [RiftManager.equippedRelics]에 영구히
/// (이번 균열 탐험 동안만) 쌓인다. 같은 유물을 여러 번 고르면 효과가
/// 중첩된다.
class RiftRelic {
  const RiftRelic({
    required this.id,
    required this.name,
    required this.description,
    required this.effect,
    required this.value,
    required this.icon,
  });

  final String id;
  final String name;
  final String description;
  final RiftRelicEffect effect;

  /// [RiftRelicEffect]에 따른 가산 배율/수치 — attackPercent/defensePercent/
  /// lifeStealPercent/hpRegenPerFloor는 0.2 == 20%p, critRatePercent도 같은
  /// 단위(0.1 == 10%p)로 취급한다.
  final double value;

  /// [RiftRelicBar]가 그대로 그리는 이모지 — 같은 [effect]라도 유물마다
  /// 다른 아이콘을 쓸 수 있게 개별 필드로 둔다(예: 공격력 유물 두 종이
  /// 🗡️/⚔️로 구분됨).
  final String icon;
}

/// 균열 전용 임시 유물 풀 — 요구사항 예시("공격력 +20%", "매 층마다 체력
/// +5% 회복", "흡혈 +10%")를 그대로 포함해 6종으로 확장했다. 밸런스는
/// 전부 1차 값이라 추후 실측 후 조정 대상.
class RiftRelicPool {
  const RiftRelicPool._();

  static const List<RiftRelic> all = [
    RiftRelic(
      id: 'rift_relic_attack',
      name: '균열의 분노',
      description: '공격력 +20%',
      effect: RiftRelicEffect.attackPercent,
      value: 0.2,
      icon: '🗡️',
    ),
    RiftRelic(
      id: 'rift_relic_defense',
      name: '균열의 갑주',
      description: '방어력 +20%',
      effect: RiftRelicEffect.defensePercent,
      value: 0.2,
      icon: '🛡️',
    ),
    RiftRelic(
      id: 'rift_relic_crit',
      name: '균열의 예기',
      description: '치명타 확률 +10%p',
      effect: RiftRelicEffect.critRatePercent,
      value: 0.1,
      icon: '🎯',
    ),
    RiftRelic(
      id: 'rift_relic_lifesteal',
      name: '균열의 갈증',
      description: '흡혈 +10%',
      effect: RiftRelicEffect.lifeStealPercent,
      value: 0.1,
      icon: '🩸',
    ),
    RiftRelic(
      id: 'rift_relic_regen',
      name: '균열의 맥동',
      description: '매 층마다 체력 +5% 회복',
      effect: RiftRelicEffect.hpRegenPerFloor,
      value: 0.05,
      icon: '💚',
    ),
    RiftRelic(
      id: 'rift_relic_attack_major',
      name: '균열의 폭주',
      description: '공격력 +35%',
      effect: RiftRelicEffect.attackPercent,
      value: 0.35,
      icon: '⚔️',
    ),
  ];
}
