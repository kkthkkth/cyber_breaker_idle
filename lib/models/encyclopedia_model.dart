import 'collection_model.dart';
import 'equipment.dart';

/// 도감(Encyclopedia) 한 칸 — "이 조합(부위+등급+넘버링)을 한 번이라도
/// 보유한 적 있는지"를 개별로 추적한다. CollectionManager의 세트 수집
/// (컬렉션)과는 별개 시스템으로, 항목 하나하나가 보유 시 1회성 보석
/// 보상을 준다. 보유 여부 자체는 저장하지 않는다(EncyclopediaManager가
/// 인벤토리를 보고 실시간으로 판정) — 여기 저장되는 건 보상을 이미
/// 받았는지([isRewarded])뿐이다.
class EncyclopediaEntry {
  EncyclopediaEntry({
    required this.category,
    required this.type,
    required this.grade,
    required this.subId,
    this.isRewarded = false,
  });

  final CollectionCategory category;
  final EquipType type;
  final ItemGrade grade;
  final int subId;

  /// 보상을 이미 수령했는지 — 한 번 true가 되면, 이후 인벤토리에서 아이템이
  /// 사라져도(분해 등) 계속 "보유함(회색조 아님)"으로 취급된다.
  bool isRewarded;

  String get id => '${type.name}_${grade.name}_$subId';

  /// 캐릭터 썸네일/정면 이미지 경로에 쓰는 ID 형식(예: "N1", "SSSR3").
  String get gradeBadgeLabel => '${grade.displayName}$subId';

  /// 등급이 높을수록 커지는 1회성 보석 보상.
  int get gemReward => (grade.index + 1) * 20;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'grade': grade.name,
    'subId': subId,
    'isRewarded': isRewarded,
  };
}
