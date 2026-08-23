import 'dart:math';

import 'package:flutter/material.dart';

enum EquipType {
  weapon,
  helmet,
  armor,
  shield,
  boots,
  ring,
  glove,
  belt,
  pet,
  character,
  relic,

  /// 길드 전쟁 승리 시에만 지급되는 기간제 "휘장" — 강화/분해/합성이
  /// 불가능하고([EquipmentManager]의 각 메서드가 이 타입을 명시적으로
  /// 제외한다), [Equipment.expiresAt]이 지나면 [GuildWarManager]가 자동
  /// 회수한다. 일반 가챠/필드 드랍으로는 절대 생성되지 않는다.
  badge,
}

extension EquipTypeX on EquipType {
  String get displayName {
    switch (this) {
      case EquipType.weapon:
        return '무기';
      case EquipType.helmet:
        return '투구';
      case EquipType.armor:
        return '갑옷';
      case EquipType.shield:
        return '방패';
      case EquipType.boots:
        return '신발';
      case EquipType.ring:
        return '반지';
      case EquipType.glove:
        return '장갑';
      case EquipType.belt:
        return '벨트';
      case EquipType.pet:
        return '펫';
      case EquipType.character:
        return '캐릭터';
      case EquipType.relic:
        return '유물';
      case EquipType.badge:
        return '휘장';
    }
  }
}

/// 캐릭터(EquipType.character)의 직업 — 근접/원거리 이동 정지 거리와 공격
/// 방식(즉발 근접 vs 투사체 발사)이 전부 이 값 하나로 결정된다
/// ([IdleGame._battleStopX]/[IdleGame._fireProjectile] 참고). 그 외 부위
/// (무기/방어구 등)에는 의미가 없다 — [Equipment.classType]은 캐릭터가
/// 아니면 항상 null이다.
enum CharacterClass { warrior, archer, mage }

extension CharacterClassX on CharacterClass {
  String get displayName {
    switch (this) {
      case CharacterClass.warrior:
        return '전사';
      case CharacterClass.archer:
        return '궁수';
      case CharacterClass.mage:
        return '마법사';
    }
  }

  /// 전사만 근접이고 궁수/마법사는 전부 원거리 — [_fireProjectile]의
  /// switch가 warrior 한 케이스와 archer/mage 두 케이스로 나뉘는 이유가
  /// 이 한 비트다.
  bool get isRanged => this != CharacterClass.warrior;

  /// 사거리(픽셀) — 몬스터가 이 거리까지만 다가오면 멈추고 전투를
  /// 시작한다([IdleGame._battleStopX]). 전사는 코앞까지, 궁수/마법사는
  /// 훨씬 멀리서 멈춰 선다. 값을 조절하고 싶으면 여기 한 곳만 고치면
  /// 된다(요구사항 예시 범위: 전사 50~80, 궁수/마법사 200~300).
  ///
  /// [주의] 전사는 원래 60 → 90으로 한 차례 늘렸었지만, 여전히 캐릭터와
  /// 몬스터 박스가 겹쳐 보인다는 피드백을 받고서야 계산이 잘못됐다는 걸
  /// 알았다 — [attackRange]는 두 컴포넌트의 "중심(anchor) 사이" 거리인데,
  /// [Anchor.bottomCenter]인 두 박스는 각자 폭의 절반만큼 자기 중심
  /// 좌우로 걸쳐 그려진다. 즉 실제로 안 겹치려면 최소
  /// `playerHalfWidth + monsterHalfWidth`(지금 값: [PlayerAnimationComponent
  /// .boxSize]/2 = 42 + [IdleGame.monsterSize]/2 = 60 = 102)보다는 커야
  /// 하는데, 90은 그보다도 작아서 애초에 겹칠 수밖에 없는 값이었다. 두
  /// 박스 절반 합(102) 위에 눈에 보이는 여백이 남도록 140으로 늘렸다
  /// (겹침 없이 약 38px 간격). boxSize/monsterSize를 나중에 또 바꾸면
  /// 이 값도 그 절반 합보다는 커야 한다는 걸 함께 확인해야 한다. 궁수/
  /// 마법사는 이미 훨씬 멀리서 멈추므로(240/260, 102보다 넉넉히 커서
  /// 문제없다) 그대로 뒀다.
  double get attackRange {
    switch (this) {
      case CharacterClass.warrior:
        return 140;
      case CharacterClass.archer:
        return 240;
      case CharacterClass.mage:
        return 260;
    }
  }
}

enum ItemGrade {
  n,
  r,
  sr,
  ssr,
  sssr,
  ur,
  lr,
}

extension ItemGradeX on ItemGrade {
  String get displayName {
    switch (this) {
      case ItemGrade.n:
        return 'N';
      case ItemGrade.r:
        return 'R';
      case ItemGrade.sr:
        return 'SR';
      case ItemGrade.ssr:
        return 'SSR';
      case ItemGrade.sssr:
        return 'SSSR';
      case ItemGrade.ur:
        return 'UR';
      case ItemGrade.lr:
        return 'LR';
    }
  }

}

/// 텍스트/아이콘 틴트처럼 단색 하나가 필요한 곳에서 쓰는 등급 대표색.
/// 테두리 렌더링(단색 vs 무지개 그라데이션)은 [getGradeBorderStyle] 참고.
Color getGradeColor(ItemGrade grade) {
  switch (grade) {
    case ItemGrade.n:
      return Colors.grey;
    case ItemGrade.r:
      return Colors.green;
    case ItemGrade.sr:
      return Colors.blue;
    case ItemGrade.ssr:
      return Colors.red;
    case ItemGrade.sssr:
      return Colors.orangeAccent;
    case ItemGrade.ur:
      return const Color(0xFFD5BAFF);
    case ItemGrade.lr:
      return const Color(0xFFEFE3FF);
  }
}

/// 등급 테두리 렌더링 방식 — N~SSSR은 [color](단색), UR/LR은 [gradient]
/// (파스텔 무지개)만 채워진다. 둘 다 non-null인 경우는 없다.
class GradeBorderStyle {
  const GradeBorderStyle.solid(Color this.color) : gradient = null;

  const GradeBorderStyle.gradient(Gradient this.gradient) : color = null;

  final Color? color;
  final Gradient? gradient;
}

/// UR: 옅은 빨강·노랑·초록·파랑·보라가 은은하게 도는 파스텔 무지개.
const LinearGradient _urGradient = LinearGradient(
  colors: [
    Color(0xFFFFB3BA),
    Color(0xFFFFDFBA),
    Color(0xFFBAFFC9),
    Color(0xFFBAE1FF),
    Color(0xFFD5BAFF),
  ],
);

/// LR: UR과 같은 색 구성이지만 알파를 낮춰 한층 더 투명하고 은은하게.
const LinearGradient _lrGradient = LinearGradient(
  colors: [
    Color(0x80FFB3BA),
    Color(0x80FFDFBA),
    Color(0x80BAFFC9),
    Color(0x80BAE1FF),
    Color(0x80D5BAFF),
  ],
);

GradeBorderStyle getGradeBorderStyle(ItemGrade grade) {
  switch (grade) {
    case ItemGrade.n:
      return const GradeBorderStyle.solid(Colors.grey);
    case ItemGrade.r:
      return const GradeBorderStyle.solid(Colors.green);
    case ItemGrade.sr:
      return const GradeBorderStyle.solid(Colors.blue);
    case ItemGrade.ssr:
      return const GradeBorderStyle.solid(Colors.red);
    case ItemGrade.sssr:
      return const GradeBorderStyle.solid(Colors.orangeAccent);
    case ItemGrade.ur:
      return const GradeBorderStyle.gradient(_urGradient);
    case ItemGrade.lr:
      return const GradeBorderStyle.gradient(_lrGradient);
  }
}

/// 장비가 가질 수 있는 스탯 종류 전부 — [Equipment.mainStat](부위 고정
/// 메인 스탯 1개)과 [Equipment.subStats](등급별로 개수가 늘어나는 추가
/// 옵션 목록) 양쪽에서 공용으로 쓰인다.
enum EquipmentStatType {
  attack,
  defense,
  attackSpeed,
  criticalRate,
  criticalDamage,
  evasionRate,
  defenseRate,
  critDefenseRate,
}

extension EquipmentStatTypeX on EquipmentStatType {
  String get displayName {
    switch (this) {
      case EquipmentStatType.attack:
        return '공격력';
      case EquipmentStatType.defense:
        return '방어력';
      case EquipmentStatType.attackSpeed:
        return '공격속도';
      case EquipmentStatType.criticalRate:
        return '크리티컬 확률';
      case EquipmentStatType.criticalDamage:
        return '크리티컬 데미지';
      case EquipmentStatType.evasionRate:
        return '회피율';
      case EquipmentStatType.defenseRate:
        return '방어율';
      case EquipmentStatType.critDefenseRate:
        return '크리티컬 방어율';
    }
  }

  /// true면 [EquipmentOption.value]가 비율(0.05 == +5%)로 해석되어 %로
  /// 표시된다. attack/defense 두 개만 절대 수치(+100 형태)로 표시된다.
  bool get isPercentage =>
      this != EquipmentStatType.attack && this != EquipmentStatType.defense;
}

/// 장비 한 개가 가질 수 있는 스탯 한 줄 — 메인 스탯과 서브 옵션 모두 이
/// 클래스 하나로 표현된다. [EquipmentStatTypeX.isPercentage] 여부에 따라
/// [displayText]가 "+100" 또는 "+5.0%" 형태로 자동 포매팅된다.
class EquipmentOption {
  const EquipmentOption({required this.type, required this.value});

  final EquipmentStatType type;
  final double value;

  String get displayText => type.isPercentage
      ? '${type.displayName} +${(value * 100).toStringAsFixed(1)}%'
      : '${type.displayName} +${value.toStringAsFixed(0)}';

  Map<String, dynamic> toJson() => {'type': type.name, 'value': value};

  factory EquipmentOption.fromJson(Map<String, dynamic> json) {
    return EquipmentOption(
      type: EquipmentStatType.values.byName(json['type'] as String),
      value: (json['value'] as num).toDouble(),
    );
  }
}

class Equipment {
  Equipment({
    required this.id,
    required this.name,
    required this.type,
    required this.grade,
    required this.statMultiplier,
    this.isEquipped = false,
    this.level = 0,
    this.subId = 1,
    this.star = 0,
    this.defenseOption = 0,
    this.defenseRateOption = 0,
    this.evasionRateOption = 0,
    this.critDefenseRateOption = 0,
    this.mainStat,
    this.subStats = const [],
    this.classType,
    this.specialStats = const {},
    this.setId,
    this.expiresAt,
  });

  final String id;
  final String name;
  final EquipType type;
  final ItemGrade grade;

  /// 직업(전사/궁수/마법사) — [EquipType.character]에만 의미가 있고, 그 외
  /// 부위는 항상 null이다. [IdleGame]이 이 값으로 사거리([CharacterClassX
  /// .attackRange])와 공격 방식(즉발 근접 vs [ProjectileComponent] 발사)을
  /// 결정한다. [EquipmentFactory.generate]가 캐릭터 생성 시 자동으로 채워
  /// 준다(명시적으로 넘기지 않는 한).
  final CharacterClass? classType;

  /// 방어 계열 서브 옵션 4종 — [statMultiplier]와 달리 레벨업으로 자라지
  /// 않고 생성 시점(가챠/합성)에 등급별 범위 안에서 한 번만 굴려진다.
  /// defense는 고정 수치, 나머지 셋은 비율(0.02 == +2%)로 해석된다.
  final double defenseOption;
  final double defenseRateOption;
  final double evasionRateOption;
  final double critDefenseRateOption;

  /// 부위(Type)에 따라 고정되는 메인 스탯 — 방어형 부위(투구/갑옷/신발/방패)는
  /// 항상 defense, 공격형 부위(무기/벨트/장갑/반지)는 항상 attack.
  /// [EquipmentFactory.generate]로 생성된 장비만 채워지며, 그 외 생성 경로로
  /// 만들어진 기존 장비는 null일 수 있다.
  final EquipmentOption? mainStat;

  /// 등급이 높을수록 개수가 늘어나는 추가 랜덤 옵션 — [EquipmentFactory]가
  /// 뽑을 때 [mainStat]과 같은 타입을 제외한 나머지 7종 풀에서 중복 없이
  /// 골라 채운다.
  final List<EquipmentOption> subStats;

  /// 펫([EquipType.pet]) 전용 특수 보너스 — [PetSpecialStat]의 6개 키(골드
  /// 획득량/드랍률/보스 데미지/최종 공격력 증폭/스킬 쿨감/크리티컬
  /// 데미지) 중 실제로 이 펫이 굴린 것만 담긴다. 값은 전부 비율(0.05 ==
  /// +5%)로 해석된다. 펫이 아닌 부위는 항상 빈 맵 — [attack]/[defense]류
  /// [EquipmentStatType]과 겹치지 않는 별도 네임스페이스라 [subStats]와
  /// 섞이지 않는다([PetStatMetadataManager]가 등급별 값 범위를 관리하고,
  /// [EquipmentManager.generateLootOfType]이 가챠 시점에 굴려 채운다).
  final Map<String, double> specialStats;

  /// 세트 장비 소속 id(예: 'set_fire_knight') — 이 값이 같은 장비를 여러
  /// 부위 동시 장착하면 [EquipmentSetManager]가 세트 효과를 발동시킨다.
  /// 세트에 속하지 않는(대부분의) 장비는 null. [EquipType.pet]/
  /// [EquipType.character]에도 이론적으로 붙을 수 있지만, 실제 세트
  /// 카탈로그는 장비 부위(무기/방어구류) 중심으로 구성하는 것을 권장한다.
  final String? setId;

  /// [EquipType.badge] 전용 만료 시각 — 그 외 타입은 항상 null(무기한).
  /// [GuildWarManager]가 이 시각을 지나면 인벤토리에서 회수한다.
  final DateTime? expiresAt;

  /// 지금 이 순간 만료됐는지 — badge가 아닌 타입은 항상 false(만료 개념이
  /// 없다). 전투 스탯 계산([GameManager.goldRewardForKill]/
  /// [effectiveCriticalMultiplier])처럼 매 프레임 동기적으로 읽어야 하는
  /// 자리 전용 — 기기 시계를 그대로 쓰므로, 회수(confiscate) 여부를
  /// 최종적으로 결정하는 자리에서는 대신 [isExpiredAt]으로 NTP 시간을
  /// 명시적으로 넘겨야 한다([EquipmentManager.removeExpiredBadge] 참고).
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// [now](반드시 NTP로 받아온 시간) 기준으로 만료됐는지 — 휘장 회수
  /// 스윕이 실제 판정에 쓴다. 기기 시계를 만료 시각 이전으로 되돌리면
  /// [isExpired]만으로는 휘장이 계속 "유효함"으로 남아, 자정 회수를
  /// 영구히 피하며 전투 버프를 계속 받을 수 있었다.
  bool isExpiredAt(DateTime now) => expiresAt != null && now.isAfter(expiresAt!);

  /// UI에서 옵션 텍스트를 렌더링할 때 쓰는 표시 순서 — 메인 스탯이 항상
  /// 최상단에 오고, 그 아래로 서브 옵션이 이어진다.
  List<EquipmentOption> get displayOptions => [?mainStat, ...subStats];

  /// 같은 등급 내 종류(넘버링) — 1~[ItemPoolConfig.maxCount] 범위(부위+등급
  /// 조합별로 실제 존재하는 개수만큼만) 안에서 생성 시점에 무작위 배정된다.
  final int subId;

  /// 타일 좌측 상단 뱃지에 쓰는 "등급+넘버링" 표기 (예: N1, SSR12, LR5).
  String get gradeBadgeLabel => '${grade.displayName}$subId';

  /// 별(성급) 진화 단계 — 0~[maxStar]. 만렙(Lv.50) 동일 아이템끼리의 합성
  /// (EquipmentManager.synthesizeGroup)으로만 오르고, 결과물은 항상 레벨 0
  /// 으로 초기화된다.
  int star;

  static const int maxStar = 5;

  /// 성급(★) 1당 [mainStat] 표시 수치에 붙는 보너스 비율 — 합성으로 별이
  /// 오를 때마다 [ItemDetailDialog]가 보여주는 "기본 공격력"이 이 비율만큼
  /// 불어난다(예: ★1 = +20%). 표기 전용 상수라 [EquipmentManager]의 실제
  /// 전투 스탯 합산(getTotalEquipmentMultiplier 등)에는 관여하지 않는다.
  static const double starGrowthPerStar = 0.2;

  bool get isMaxStar => star >= maxStar;

  /// 성급 텍스트 표기 — 숫자 조합("★3")이 아니라 별을 [star]개만큼 그대로
  /// 나열한다("★★★"). 0성은 빈 문자열(표기 안 함). 프로젝트 전체(캐릭터 탭
  /// 프리뷰, 인벤토리/장착 슬롯 뱃지, 상세 팝업 일러스트 갤러리 등)가 이
  /// 헬퍼 하나로 통일해서 쓴다 — 표기 방식을 바꿀 일이 생기면 여기 한
  /// 곳만 고치면 된다.
  static String starText(int star) => '★' * star;

  /// 타일 하단에 쓰는 별 표기 — [starText]를 그대로 위임한다.
  String get starLabel => starText(star);

  /// 인벤토리 그리드/합성/분해/장착 선택 등 아이템 목록을 보여주는 화면
  /// 전부가 공유하는 정렬 규칙 — 1순위 성급(★) 내림차순, 2순위 레벨
  /// 내림차순, 3순위 기본 등급(rarity) 내림차순([ItemGrade]는 n~lr 순으로
  /// 선언돼 있어 `.index`가 그대로 rarityIndex 역할을 한다). `list.sort(...)`
  /// 에 그대로 넘겨 쓴다.
  static int compareForDisplay(Equipment a, Equipment b) {
    final int starCompare = b.star.compareTo(a.star);
    if (starCompare != 0) {
      return starCompare;
    }
    final int levelCompare = b.level.compareTo(a.level);
    if (levelCompare != 0) {
      return levelCompare;
    }
    return b.grade.index.compareTo(a.grade.index);
  }

  /// 레벨업으로 오르는 값이라 더 이상 final이 아니다 — [levelUp] 계열
  /// 로직만 이 필드를 직접 바꾼다.
  double statMultiplier;
  bool isEquipped;
  int level;

  static const int maxLevel = 50;

  /// 레벨업 1회당 [statMultiplier]가 오르는 고정치.
  static const double statGrowthPerLevel = 0.1;

  bool get isMaxLevel => level >= maxLevel;

  double get nextLevelStatMultiplier =>
      isMaxLevel ? statMultiplier : statMultiplier + statGrowthPerLevel;

  /// 다음 레벨업에 필요한 코인 — 등급이 높을수록, 레벨이 오를수록 비싸진다.
  int get levelUpCost =>
      (100 * (grade.index + 1) * pow(1.12, level - 1)).round();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'grade': grade.name,
      'statMultiplier': statMultiplier,
      'isEquipped': isEquipped,
      'level': level,
      'subId': subId,
      'star': star,
      'defenseOption': defenseOption,
      'defenseRateOption': defenseRateOption,
      'evasionRateOption': evasionRateOption,
      'critDefenseRateOption': critDefenseRateOption,
      'mainStat': mainStat?.toJson(),
      'subStats': subStats.map((option) => option.toJson()).toList(),
      'classType': classType?.name,
      'specialStats': specialStats,
      'setId': setId,
      'expiresAt': expiresAt?.toIso8601String(),
    };
  }

  factory Equipment.fromJson(Map<String, dynamic> json) {
    return Equipment(
      id: json['id'] as String,
      name: json['name'] as String,
      type: _parseType(json['type'] as String?),
      grade: _parseGrade(json['grade'] as String? ?? ''),
      statMultiplier: (json['statMultiplier'] as num).toDouble(),
      isEquipped: json['isEquipped'] as bool,
      level: json['level'] as int? ?? 0,
      subId: json['subId'] as int? ?? 1,
      star: json['star'] as int? ?? 0,
      defenseOption: (json['defenseOption'] as num?)?.toDouble() ?? 0,
      defenseRateOption: (json['defenseRateOption'] as num?)?.toDouble() ?? 0,
      evasionRateOption: (json['evasionRateOption'] as num?)?.toDouble() ?? 0,
      critDefenseRateOption: (json['critDefenseRateOption'] as num?)?.toDouble() ?? 0,
      mainStat: json['mainStat'] != null
          ? EquipmentOption.fromJson(json['mainStat'] as Map<String, dynamic>)
          : null,
      subStats: (json['subStats'] as List<dynamic>?)
              ?.map((entry) => EquipmentOption.fromJson(entry as Map<String, dynamic>))
              .toList() ??
          const [],
      classType: _parseClassType(json['classType'] as String?),
      // 이 필드가 생기기 전에 저장된 기존 데이터(펫 포함)는 이 키 자체가
      // 없다 — 그런 경우 빈 맵으로 안전하게 대체한다(신규 필드 추가 시
      // 항상 지키는 JSON 호환성 관례).
      specialStats: (json['specialStats'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(key, (value as num).toDouble()),
          ) ??
          const {},
      setId: json['setId'] as String?,
      expiresAt: json['expiresAt'] != null ? DateTime.tryParse(json['expiresAt'] as String) : null,
    );
  }

  /// 등급 체계 개편 전 저장 데이터(normal/rare/... 등)가 남아있어도 크래시
  /// 대신 최저 등급으로 안전하게 대체한다.
  static ItemGrade _parseGrade(String name) {
    for (final ItemGrade grade in ItemGrade.values) {
      if (grade.name == name) {
        return grade;
      }
    }
    return ItemGrade.n;
  }

  /// [보안 감사 2026-08-21] [_parseGrade]와 같은 이유로 추가 — 예전엔
  /// `EquipType.values.byName(json['type'] as String)`을 그대로 써서,
  /// 이 값이 null이거나(예: 다른 유저의 손상된/예전 스키마 행) enum
  /// 이름과 정확히 일치하지 않으면 `Equipment.fromJson` 전체가 예외를
  /// 던졌다. 이제는 `user_equipment`를 거쳐 다른 유저의 데이터를
  /// 그대로 읽는 거래 화면([TradeItemEntry.fromJson])처럼 이 프로젝트가
  /// 통제할 수 없는 외부 데이터를 파싱하는 경로가 생겨서, 그 값 하나
  /// 때문에 화면 전체가 죽는 일이 없도록 [ItemGrade]와 같은 관례로
  /// 통일한다.
  static EquipType _parseType(String? name) {
    if (name != null) {
      for (final EquipType type in EquipType.values) {
        if (type.name == name) {
          return type;
        }
      }
    }
    return EquipType.weapon;
  }

  /// [classType]은 원래도 nullable이라, 못 알아보는 값이면 그냥 null로
  /// 안전하게 대체한다(캐릭터가 아닌 부위는 애초에 항상 null이므로 이
  /// 폴백이 자연스럽다).
  static CharacterClass? _parseClassType(String? name) {
    if (name == null) {
      return null;
    }
    for (final CharacterClass classType in CharacterClass.values) {
      if (classType.name == name) {
        return classType;
      }
    }
    return null;
  }
}

/// 부위별 고정 메인 스탯 + 등급별 랜덤 서브 옵션을 굴려 [Equipment]를 만드는
/// 생성 팩토리. 기존 EquipmentManager의 가챠/합성 로직과는 별개의 경로이며,
/// [Equipment.mainStat]/[Equipment.subStats]를 채우고 싶을 때 이 팩토리를
/// 통해서만 생성하면 된다.
class EquipmentFactory {
  EquipmentFactory._();

  static final Random _random = Random();

  /// 방어형 부위(투구/갑옷/신발/방패) — 메인 스탯이 defense로 고정된다.
  /// 그 외 전부(무기/벨트/장갑/반지 및 나머지 미분류 부위)는 attack.
  static const Set<EquipType> _defensiveTypes = {
    EquipType.helmet,
    EquipType.armor,
    EquipType.boots,
    EquipType.shield,
  };

  /// 등급별 추가 서브 옵션 개수.
  static const Map<ItemGrade, int> _subStatCountByGrade = {
    ItemGrade.n: 0,
    ItemGrade.r: 1,
    ItemGrade.sr: 2,
    ItemGrade.ssr: 2,
    ItemGrade.sssr: 3,
    ItemGrade.ur: 4,
    ItemGrade.lr: 5,
  };

  /// N등급(gradeIndex 0)에서 나올 수 있는 메인 스탯의 최저 수치.
  static const Map<EquipmentStatType, double> _mainStatBaseFloor = {
    EquipmentStatType.attack: 10,
    EquipmentStatType.defense: 8,
  };

  /// N등급(gradeIndex 0)에서 나올 수 있는 서브 옵션의 최저 수치.
  static const Map<EquipmentStatType, double> _subStatBaseFloor = {
    EquipmentStatType.attack: 3,
    EquipmentStatType.defense: 2,
    EquipmentStatType.attackSpeed: 0.02,
    EquipmentStatType.criticalRate: 0.02,
    EquipmentStatType.criticalDamage: 0.03,
    EquipmentStatType.evasionRate: 0.01,
    EquipmentStatType.defenseRate: 0.02,
    EquipmentStatType.critDefenseRate: 0.02,
  };

  /// 등급 1단계당 구간(min~max)이 통째로 얼마나 위로 올라가는지 — 등급의
  /// 최저치(floor)가 이전 등급의 최대치(max)보다 항상 크도록
  /// _gradeGrowth > 1 + _gradeWidthRatio 관계를 반드시 지켜야 한다
  /// (예: 1.5 > 1.25 ✓). 이 부등식이 곧 요구사항 3번 "무조건 높게"의 근거.
  static const double _gradeGrowth = 1.5;
  static const double _gradeWidthRatio = 0.25;

  /// [type] 부위 + [grade] 등급에 맞는 장비 하나를 생성한다. [statMultiplier]는
  /// EquipmentManager의 레벨업/자동장착 비교 로직이 여전히 이 필드를 쓰므로
  /// 호출부(가챠 등급 굴림)에서 넘겨줄 수 있게 열어두고, 안 넘기면 1.0.
  /// [star]도 마찬가지로 합성(별 진화) 결과물에 곧바로 반영할 수 있게 노출.
  /// [specialStats]는 펫([EquipType.pet]) 전용 — DB(`pet_stat_metadata`)
  /// 기반 값 범위에서 굴리는 로직이라 이 순수 팩토리 밖(호출부인
  /// [EquipmentManager.generateLootOfType])에서 미리 계산해 넘긴다. 다른
  /// 타입은 항상 기본값(빈 맵)을 그대로 쓴다.
  static Equipment generate({
    required EquipType type,
    required ItemGrade grade,
    required String id,
    required String name,
    int subId = 1,
    double statMultiplier = 1.0,
    int star = 0,
    CharacterClass? classType,
    Map<String, double> specialStats = const {},
    String? setId,
  }) {
    final EquipmentStatType mainStatType = _defensiveTypes.contains(type)
        ? EquipmentStatType.defense
        : EquipmentStatType.attack;

    final EquipmentOption mainStat = EquipmentOption(
      type: mainStatType,
      value: _rollValue(_mainStatBaseFloor[mainStatType]!, grade),
    );

    final int subStatCount = _subStatCountByGrade[grade] ?? 0;
    final List<EquipmentOption> subStats = _rollUniqueSubStats(
      excluding: mainStatType,
      count: subStatCount,
      grade: grade,
    );

    return Equipment(
      id: id,
      name: name,
      type: type,
      grade: grade,
      statMultiplier: statMultiplier,
      subId: subId,
      star: star,
      mainStat: mainStat,
      subStats: subStats,
      classType: type == EquipType.character
          ? (classType ?? _deriveClassType(subId))
          : null,
      specialStats: specialStats,
      setId: setId,
    );
  }

  /// 캐릭터 생성 시 [classType]을 명시적으로 넘기지 않으면 이 규칙으로
  /// 자동 배정한다 — 등급별 [subId](1부터 시작하는 넘버링)를 3개 직업에
  /// 균등하게 순환 배정(round-robin)해서, 이미 존재하는 더미 캐릭터
  /// 35종(ItemPoolConfig.maxCharacterCount) 전부에 빠짐없이 직업이
  /// 붙도록 한다. subId=1이 항상 전사가 되는 건 의도된 것 — 각 등급의
  /// "메인" 캐릭터(예: grantStarterCharacters의 starter)가 항상 근접
  /// 전사로 시작하게 해서 기존 밸런스/애니메이션 기대치를 깨지 않는다.
  static CharacterClass _deriveClassType(int subId) =>
      CharacterClass.values[(subId - 1) % CharacterClass.values.length];

  /// [excluding](메인 스탯 타입)을 뺀 나머지 풀에서 [count]개를 중복 없이
  /// 뽑는다. Set으로 뽑힌 타입을 추적하면서 while로 채우되, 풀 자체가
  /// [count]보다 작으면(요청받은 개수를 절대 채울 수 없으면) 무한루프 대신
  /// assert로 즉시 드러나게 한다 — LR(5개)처럼 요구 개수가 큰 등급에서
  /// "옵션 풀이 부족해 조용히 개수가 모자란 채 반환되는" 사고를 막기 위함.
  static List<EquipmentOption> _rollUniqueSubStats({
    required EquipmentStatType excluding,
    required int count,
    required ItemGrade grade,
  }) {
    final List<EquipmentStatType> pool =
        EquipmentStatType.values.where((statType) => statType != excluding).toList();
    assert(
      count <= pool.length,
      '서브 옵션 풀(${pool.length}개)보다 많은 $count개를 요청했습니다.',
    );

    final Set<EquipmentStatType> chosen = {};
    while (chosen.length < count && chosen.length < pool.length) {
      chosen.add(pool[_random.nextInt(pool.length)]);
    }

    return chosen
        .map(
          (statType) => EquipmentOption(
            type: statType,
            value: _rollValue(_subStatBaseFloor[statType]!, grade),
          ),
        )
        .toList();
  }

  /// baseFloor를 등급만큼 지수적으로 끌어올린 구간(floor~floor*1.25) 안에서
  /// 값을 하나 굴린다. 소수 3자리까지 반올림.
  static double _rollValue(double baseFloor, ItemGrade grade) {
    final double floor = baseFloor * pow(_gradeGrowth, grade.index);
    final double max = floor * (1 + _gradeWidthRatio);
    final double value = floor + _random.nextDouble() * (max - floor);
    return double.parse(value.toStringAsFixed(3));
  }
}
