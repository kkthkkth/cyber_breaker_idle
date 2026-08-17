import 'package:flutter/material.dart';

/// 요일 던전의 보상 종류 — [WeekdayDungeonSchedule]이 [DateTime.weekday]
/// 1(월)~7(일)에 하나씩 매핑한다.
enum WeekdayDungeonRewardType { gold, gem, enhanceStone, runeFragment, skillCurrency, combined }

extension WeekdayDungeonRewardTypeX on WeekdayDungeonRewardType {
  String get resourceLabel => switch (this) {
    WeekdayDungeonRewardType.gold => '골드',
    WeekdayDungeonRewardType.gem => '보석',
    WeekdayDungeonRewardType.enhanceStone => '강화석',
    WeekdayDungeonRewardType.runeFragment => '룬 조각',
    WeekdayDungeonRewardType.skillCurrency => '스킬 포인트',
    WeekdayDungeonRewardType.combined => '골드·보석·룬 조각 등',
  };

  IconData get icon => switch (this) {
    WeekdayDungeonRewardType.gold => Icons.monetization_on,
    WeekdayDungeonRewardType.gem => Icons.diamond,
    WeekdayDungeonRewardType.enhanceStone => Icons.construction,
    WeekdayDungeonRewardType.runeFragment => Icons.hexagon,
    WeekdayDungeonRewardType.skillCurrency => Icons.auto_awesome,
    WeekdayDungeonRewardType.combined => Icons.all_inclusive,
  };

  Color get color => switch (this) {
    WeekdayDungeonRewardType.gold => Colors.amberAccent,
    WeekdayDungeonRewardType.gem => Colors.cyanAccent,
    WeekdayDungeonRewardType.enhanceStone => Colors.orangeAccent,
    WeekdayDungeonRewardType.runeFragment => Colors.greenAccent,
    WeekdayDungeonRewardType.skillCurrency => Colors.purpleAccent,
    WeekdayDungeonRewardType.combined => Colors.pinkAccent,
  };
}

/// 요일 하루치 던전 정보 — [WeekdayDungeonSchedule.configFor]가 오늘의
/// 요일([DateTime.weekday])로 이 중 하나를 골라준다.
class WeekdayDungeonConfig {
  const WeekdayDungeonConfig({
    required this.weekday,
    required this.name,
    required this.rewardType,
  });

  /// [DateTime.weekday] 값(1=월요일 ~ 7=일요일).
  final int weekday;
  final String name;
  final WeekdayDungeonRewardType rewardType;
}

/// 요일별 던전 스케줄 — 순수 게임 기획 데이터(어느 요일에 어떤 보상
/// 던전이 열리는지)라 서버 왕복 없이 상수로 관리한다("dungeon_schedules
/// 또는 로컬/메타데이터 구조" 요구사항 중 로컬 메타데이터 방식을
/// 택했다 — [RuneCatalog]/`SkillManager._skillNamesFor`류의 다른 순수
/// 밸런스 상수들과 같은 관례). 요구사항 예시(월-골드, 화-보석, 수-강화석,
/// 목-룬 조각, 금-스킬 재화, 토/일-통합)를 그대로 반영했다.
class WeekdayDungeonSchedule {
  const WeekdayDungeonSchedule._();

  static const List<WeekdayDungeonConfig> all = [
    WeekdayDungeonConfig(
      weekday: DateTime.monday,
      name: '황금 던전',
      rewardType: WeekdayDungeonRewardType.gold,
    ),
    WeekdayDungeonConfig(
      weekday: DateTime.tuesday,
      name: '보석 광산',
      rewardType: WeekdayDungeonRewardType.gem,
    ),
    WeekdayDungeonConfig(
      weekday: DateTime.wednesday,
      name: '단조의 제단',
      rewardType: WeekdayDungeonRewardType.enhanceStone,
    ),
    WeekdayDungeonConfig(
      weekday: DateTime.thursday,
      name: '룬의 미궁',
      rewardType: WeekdayDungeonRewardType.runeFragment,
    ),
    WeekdayDungeonConfig(
      weekday: DateTime.friday,
      name: '오의의 전당',
      rewardType: WeekdayDungeonRewardType.skillCurrency,
    ),
    WeekdayDungeonConfig(
      weekday: DateTime.saturday,
      name: '혼돈의 관문',
      rewardType: WeekdayDungeonRewardType.combined,
    ),
    WeekdayDungeonConfig(
      weekday: DateTime.sunday,
      name: '혼돈의 관문',
      rewardType: WeekdayDungeonRewardType.combined,
    ),
  ];

  static WeekdayDungeonConfig configFor(int weekday) =>
      all.firstWhere((config) => config.weekday == weekday, orElse: () => all.first);
}
