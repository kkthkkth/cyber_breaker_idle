import '../models/equipment.dart';

/// 등급별로 "실제로 존재하는(아트/썸네일이 준비된) 서로 다른 종류(subId)의
/// 최대 개수"를 부위 카테고리별로 직접 관리하는 설정 — 펫/장비의 생성(가챠,
/// 필드 드랍, 테스트 인벤토리, 합성)이 이 표를 거친다. 여기 적힌 개수를
/// 넘는 subId는 절대 생성되지 않으므로, 실제 아트가 없는 "SR25" 같은 유령
/// 아이템이 생기지 않는다.
///
/// 캐릭터(EquipType.character)는 더 이상 이 파일이 다루지 않는다 —
/// [CharacterManifestManager](Supabase `master_characters`)가 앱 재배포
/// 없이 실시간으로 캐릭터를 추가/숨김/가챠 가중치 조정을 할 수 있게 그
/// 역할을 전담한다([EquipmentManager]의 `_hasGachaContent`/`_rollSubId`
/// 참고).
///
/// 새 아트를 추가했으면 여기 숫자만 올리면 된다. 0이면 그 등급은 아직
/// 아무것도 없다는 뜻이라 생성 로직이 다른 등급으로 대체한다([EquipmentManager]
/// 의 `_pickAvailableGrade` 참고).
class ItemPoolConfig {
  const ItemPoolConfig._();

  /// 펫(EquipType.pet) — 아직 부위별 전용 이미지가 없어(아이콘/텍스트로만
  /// 표시) 캐릭터만큼 타이트하게 잠글 필요는 없지만, 등급당 소수로 제한해
  /// 불필요하게 많은 종류가 쏟아지지 않게 한다.
  static const Map<ItemGrade, int> maxPetCount = {
    ItemGrade.n: 3,
    ItemGrade.r: 3,
    ItemGrade.sr: 2,
    ItemGrade.ssr: 2,
    ItemGrade.sssr: 1,
    ItemGrade.ur: 1,
    ItemGrade.lr: 1,
  };

  /// 장비(무기/투구/갑옷/방패/신발/반지/장갑/벨트)와 유물 — 펫과 같은
  /// 이유로 소수만 허용한다.
  static const Map<ItemGrade, int> maxEquipmentCount = {
    ItemGrade.n: 3,
    ItemGrade.r: 3,
    ItemGrade.sr: 2,
    ItemGrade.ssr: 2,
    ItemGrade.sssr: 1,
    ItemGrade.ur: 1,
    ItemGrade.lr: 1,
  };

  /// [type] + [grade] 조합의 최대 subId 개수. 0이면 이 조합은 아직 실제
  /// 콘텐츠가 없다는 뜻.
  ///
  /// 캐릭터(EquipType.character)는 더 이상 이 표가 다루지 않는다 —
  /// [CharacterManifestManager](Supabase `master_characters`)가 유일한
  /// 출처이므로, 여기서는 항상 0을 반환해 혹시라도 남아있을 호출부가
  /// 조용히 잘못된 개수를 쓰는 대신 눈에 띄게 "콘텐츠 없음"으로 처리되게
  /// 한다.
  static int maxCount(EquipType type, ItemGrade grade) {
    if (type == EquipType.character) {
      return 0;
    }
    final Map<ItemGrade, int> table = switch (type) {
      EquipType.pet => maxPetCount,
      _ => maxEquipmentCount,
    };
    return table[grade] ?? 0;
  }
}
