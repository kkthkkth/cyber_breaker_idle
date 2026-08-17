import 'package:flutter/material.dart';

import 'consumable_item_model.dart';

/// 신규 모험가 7일 출석부 한 칸의 보상 종류.
enum RookieRewardKind { gold, gem, consumable }

/// [RookieAttendanceSchedule.rewardForDay]가 돌려주는 하루치 보상 —
/// 1일차 보석부터 7일차 최고 등급 상자까지 점점 커지는 확실한 보상
/// 루프(요구사항)를 표현한다.
class RookieAttendanceReward {
  const RookieAttendanceReward({
    required this.day,
    required this.kind,
    this.amount = 0,
    this.consumableType,
    this.consumableAmount = 1,
  });

  final int day;
  final RookieRewardKind kind;

  /// [kind]가 gold/gem일 때의 수량.
  final int amount;

  /// [kind]가 consumable일 때의 아이템 종류/수량.
  final ConsumableType? consumableType;
  final int consumableAmount;

  IconData get displayIcon {
    switch (kind) {
      case RookieRewardKind.gold:
        return Icons.monetization_on;
      case RookieRewardKind.gem:
        return Icons.diamond;
      case RookieRewardKind.consumable:
        return consumableType?.icon ?? Icons.card_giftcard;
    }
  }

  String get displayLabel {
    switch (kind) {
      case RookieRewardKind.gold:
        return '$amount G';
      case RookieRewardKind.gem:
        return '$amount 💎';
      case RookieRewardKind.consumable:
        return '${consumableType?.displayName ?? '아이템'} x$consumableAmount';
    }
  }
}

/// 신규 모험가 7일 출석 스케줄 — 순수 기획 데이터라 상수로 관리한다
/// ([WeekdayDungeonSchedule]과 같은 관례). 7일차는 이 게임에서 이미
/// 확립된 최고 등급 상자([ConsumableType.legendaryBox], 월간 출석
/// 30일차 마일스톤과 동일)로 강력하게 마무리한다.
class RookieAttendanceSchedule {
  const RookieAttendanceSchedule._();

  static const List<RookieAttendanceReward> all = [
    RookieAttendanceReward(day: 1, kind: RookieRewardKind.gem, amount: 50),
    RookieAttendanceReward(day: 2, kind: RookieRewardKind.gold, amount: 3000),
    RookieAttendanceReward(
      day: 3,
      kind: RookieRewardKind.consumable,
      consumableType: ConsumableType.advancedBox,
    ),
    RookieAttendanceReward(day: 4, kind: RookieRewardKind.gem, amount: 100),
    RookieAttendanceReward(
      day: 5,
      kind: RookieRewardKind.consumable,
      consumableType: ConsumableType.heroBox,
    ),
    RookieAttendanceReward(day: 6, kind: RookieRewardKind.gem, amount: 200),
    RookieAttendanceReward(
      day: 7,
      kind: RookieRewardKind.consumable,
      consumableType: ConsumableType.legendaryBox,
    ),
  ];

  static RookieAttendanceReward rewardForDay(int day) =>
      all.firstWhere((reward) => reward.day == day, orElse: () => all.first);
}
