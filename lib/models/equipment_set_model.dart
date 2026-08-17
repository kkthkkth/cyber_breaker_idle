/// [EquipmentSetBonus.twoPieceStat]/[fourPieceStat]에 쓰이는 세트 효과
/// 전용 패시브 스탯 키 — 매직 스트링을 이 상수들로 통일한다
/// ([ArtifactStat]/[PetSpecialStat]과 같은 관례).
class EquipmentSetStat {
  const EquipmentSetStat._();

  static const String attackPercent = 'attackPercent';
  static const String defensePercent = 'defensePercent';
  static const String criticalRatePercent = 'criticalRatePercent';
  static const String criticalDamagePercent = 'criticalDamagePercent';
  static const String maxHpPercent = 'maxHpPercent';

  static const List<String> values = [
    attackPercent,
    defensePercent,
    criticalRatePercent,
    criticalDamagePercent,
    maxHpPercent,
  ];

  static String displayName(String key) => switch (key) {
    attackPercent => '공격력 증가',
    defensePercent => '방어력 증가',
    criticalRatePercent => '크리티컬 확률 증가',
    criticalDamagePercent => '크리티컬 데미지 증가',
    maxHpPercent => '최대 체력 증가',
    _ => key,
  };
}

/// `equipment_sets` 테이블 한 행 — [Equipment.setId]가 이 [setId]와
/// 일치하는 장비를 2부위/4부위 동시 장착했을 때 발동하는 패시브 정의.
/// [fourPieceStat]이 null이면 그 세트는 2부위 효과만 있다(4부위 방어구
/// 세트가 없는 등).
class EquipmentSetBonus {
  const EquipmentSetBonus({
    required this.setId,
    required this.name,
    required this.twoPieceStat,
    required this.twoPieceValue,
    this.fourPieceStat,
    this.fourPieceValue = 0,
  });

  final String setId;
  final String name;

  final String twoPieceStat;
  final double twoPieceValue;

  final String? fourPieceStat;
  final double fourPieceValue;

  factory EquipmentSetBonus.fromJson(Map<String, dynamic> json) => EquipmentSetBonus(
    setId: json['set_id'] as String,
    name: json['name'] as String? ?? json['set_id'] as String,
    twoPieceStat: json['two_piece_stat'] as String,
    twoPieceValue: (json['two_piece_value'] as num?)?.toDouble() ?? 0,
    fourPieceStat: json['four_piece_stat'] as String?,
    fourPieceValue: (json['four_piece_value'] as num?)?.toDouble() ?? 0,
  );
}

/// [EquipmentSetManager.activeBonuses]가 돌려주는 "지금 발동 중인 세트
/// 효과 한 줄" — UI(아이템 상세/캐릭터 화면)가 그대로 나열해서 보여준다.
class ActiveSetBonus {
  const ActiveSetBonus({
    required this.setId,
    required this.setName,
    required this.equippedCount,
    required this.stat,
    required this.value,
    required this.isFourPiece,
  });

  final String setId;
  final String setName;
  final int equippedCount;
  final String stat;
  final double value;

  /// false면 2부위 효과, true면 4부위 효과.
  final bool isFourPiece;

  String get label =>
      '$setName (${isFourPiece ? '4' : '2'}세트) ${EquipmentSetStat.displayName(stat)} '
      '+${(value * 100).toStringAsFixed(0)}%';
}
