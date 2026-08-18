/// `character_metadata` 테이블(캐릭터별 기본 전투 스탯 + 성장률) 한 행 —
/// [CharacterMetadataManager]가 앱 시작 시 전체를 캐싱하고, 장착된
/// 캐릭터의 `Equipment.level`/`Equipment.star`와 조합해 [computeFinalStats]
/// 로 실제 전투 스탯을 계산한다.
///
/// [주의] `Equipment.level`은 이 프로젝트에서 0-indexed다("Lv.0" = 아직
/// 한 번도 레벨업하지 않은 상태 — item_detail_dialog.dart가 그대로
/// "Lv. 0/50"으로 표시한다) — 그래서 "몇 번 레벨업했는지"가 곧
/// `Equipment.level` 값 자체와 같다. 요청받은 계산식은
/// `기본 * (1 + (level-1)*level_growth_rate)`처럼 1-indexed 레벨을
/// 가정하지만, `Equipment.level`(0-indexed)을 그 식의 `level`에 그대로
/// 대입하면 `(level-1)`이 정확히 "레벨업 횟수"가 되므로 별도의 +1/-1
/// 변환이 필요 없다 — [computeFinalStats]의 `level` 인자에는 항상
/// `Equipment.level`을 그대로(변환 없이) 넘기면 된다.
class CharacterMetadata {
  const CharacterMetadata({
    required this.characterId,
    required this.baseHp,
    required this.baseAttack,
    required this.baseDefense,
    required this.baseAttackSpeed,
    required this.levelGrowthRate,
    required this.starGrowthRate,
  });

  /// `Equipment.gradeBadgeLabel`과 동일한 형식(예: 'N1').
  final String characterId;

  final double baseHp;
  final double baseAttack;
  final double baseDefense;

  /// 공격속도(ASPD) — [computeFinalStats]가 레벨/별 성장률을 전혀 적용하지
  /// 않고 이 값을 그대로 최종 ASPD로 쓴다(요청사항의 명시적 예외).
  final double baseAttackSpeed;

  final double levelGrowthRate;
  final double starGrowthRate;

  /// [json['character_id'] as String]처럼 곧바로 캐스팅하면, 실제 서버
  /// 컬럼명이 `id`이거나 그 행에 아직 값이 비어 있을 때(둘 다 실측된 실패
  /// 사례) `type 'Null' is not a subtype of type 'String'`으로 앱이
  /// 죽는다. `character_id`/`id` 두 컬럼명을 모두 받아들이고, 둘 다 없으면
  /// 빈 문자열로 안전하게 대체한다(빈 문자열은 어떤 실제 캐릭터 ID와도
  /// 매치되지 않으므로 [CharacterMetadataManager.byId]가 조용히 무시한다
  /// — 이 프로젝트의 다른 파싱 실패 폴백과 같은 관례).
  ///
  /// 숫자 필드도 전부 `as num?`로 느슨하게 받고, null이면(컬럼 누락/미입력)
  /// 에러 대신 무난한 기본값으로 대체한다 — 0을 기본값으로 쓰면 그
  /// 캐릭터가 조용히 아무 스탯도 없는 것처럼 보여서 "데이터가 비어서
  /// 그런 건지, 진짜로 0인 게 의도인지" 구분이 안 되므로, 육안으로 바로
  /// "기본값이 채워졌구나"라고 알아챌 수 있는 값을 쓴다.
  factory CharacterMetadata.fromJson(Map<String, dynamic> json) => CharacterMetadata(
    characterId: (json['character_id'] ?? json['id'] ?? '') as String,
    baseHp: (json['base_hp'] as num?)?.toDouble() ?? 1000,
    baseAttack: (json['base_atk'] as num?)?.toDouble() ?? 1000,
    baseDefense: (json['base_def'] as num?)?.toDouble() ?? 500,
    baseAttackSpeed: (json['base_aspd'] as num?)?.toDouble() ?? 1.0,
    levelGrowthRate: (json['level_growth_rate'] as num?)?.toDouble() ?? 0.05,
    starGrowthRate: (json['star_growth_rate'] as num?)?.toDouble() ?? 0.1,
  );

  Map<String, dynamic> toCacheJson() => {
    'character_id': characterId,
    'base_hp': baseHp,
    'base_atk': baseAttack,
    'base_def': baseDefense,
    'base_aspd': baseAttackSpeed,
    'level_growth_rate': levelGrowthRate,
    'star_growth_rate': starGrowthRate,
  };

  /// 요청받은 계산식: 최종 = 기본 스탯 * (1 + (level-1)*level_growth_rate)
  /// * (1 + star*star_growth_rate). [level]에는 `Equipment.level`을 그대로
  /// 넘긴다(클래스 상단 문서의 0-indexed 설명 참고). ASPD는 예외로 이
  /// 배율을 전혀 타지 않고 [baseAttackSpeed]를 그대로 쓴다.
  CharacterFinalStats computeFinalStats({required int level, required int star}) {
    final double growthFactor = (1 + level * levelGrowthRate) * (1 + star * starGrowthRate);
    return CharacterFinalStats(
      hp: baseHp * growthFactor,
      attack: baseAttack * growthFactor,
      defense: baseDefense * growthFactor,
      attackSpeed: baseAttackSpeed,
      baseHp: baseHp,
      baseAttack: baseAttack,
      baseDefense: baseDefense,
    );
  }
}

/// [CharacterMetadata.computeFinalStats]의 결과 — 최종 수치와 함께
/// "기본값"도 그대로 들고 있어서, UI가 "최종 (기본 + 추가 성장치)" 형태로
/// 분해해 보여줄 수 있다([hpGrowth]/[attackGrowth]/[defenseGrowth]).
class CharacterFinalStats {
  const CharacterFinalStats({
    required this.hp,
    required this.attack,
    required this.defense,
    required this.attackSpeed,
    required this.baseHp,
    required this.baseAttack,
    required this.baseDefense,
  });

  final double hp;
  final double attack;
  final double defense;

  /// 레벨/별 등급의 영향을 받지 않는 고정 공격속도.
  final double attackSpeed;

  final double baseHp;
  final double baseAttack;
  final double baseDefense;

  double get hpGrowth => hp - baseHp;
  double get attackGrowth => attack - baseAttack;
  double get defenseGrowth => defense - baseDefense;

  /// 메타데이터가 없는 캐릭터(장착 캐릭터 없음, 마이그레이션 전 등)를 위한
  /// 안전한 0값 — [GameManager]의 기존 계정 단위 스탯 체인에 어떤 영향도
  /// 주지 않는다.
  static const CharacterFinalStats zero = CharacterFinalStats(
    hp: 0,
    attack: 0,
    defense: 0,
    attackSpeed: 0,
    baseHp: 0,
    baseAttack: 0,
    baseDefense: 0,
  );
}
