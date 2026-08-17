/// `characters` 테이블(캐릭터 메타데이터)의 `attack_type` 컬럼 — 근접/
/// 원거리 공격 방식을 더 이상 [CharacterClass](직업, 사거리/투사체 비주얼
/// 담당)에서 암묵적으로 추론하지 않고, DB에서 명시적으로 관리한다
/// ([IdleGame._fireProjectile] 참고).
enum AttackType { melee, ranged }

/// DB 값이 없거나(컬럼이 비어있거나, 아직 이 캐릭터의 메타데이터 행 자체가
/// 없거나) 알 수 없는 문자열이면 안전하게 melee로 취급한다 — [GuildRole]
/// 파싱([guildRoleFromString])과 같은 관례.
AttackType attackTypeFromString(String? value) => switch (value) {
  'ranged' => AttackType.ranged,
  _ => AttackType.melee,
};

String attackTypeColumnValue(AttackType type) => switch (type) {
  AttackType.melee => 'melee',
  AttackType.ranged => 'ranged',
};

/// `characters` 테이블 한 행 — 지금은 [attackType] 하나만 담지만, 앞으로
/// 캐릭터 기본 스탯 등 다른 메타데이터가 늘어나면 이 모델에 필드만 추가하면
/// 된다([CharacterMetaManager] 참고).
class CharacterMeta {
  const CharacterMeta({required this.characterId, required this.attackType});

  /// [Equipment.gradeBadgeLabel]과 동일한 형식(예: 'N1').
  final String characterId;
  final AttackType attackType;

  factory CharacterMeta.fromJson(Map<String, dynamic> json) => CharacterMeta(
    characterId: json['character_id'] as String,
    attackType: attackTypeFromString(json['attack_type'] as String?),
  );

  Map<String, dynamic> toCacheJson() => {
    'character_id': characterId,
    'attack_type': attackTypeColumnValue(attackType),
  };
}
