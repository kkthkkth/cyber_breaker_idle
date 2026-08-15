import 'package:flutter/material.dart';

import 'consumable_item_model.dart';
import 'equipment.dart';

/// Supabase `guild_shop_items` 테이블의 행 하나 — 길드 주화로 구매하는
/// 길드 상점 상품. 별도의 아이템 종류 체계를 새로 만들지 않고 기존
/// [ConsumableType]/[ConsumableManager]를 그대로 재사용한다 — 구매 시
/// `ConsumableManager.instance.addItem(type, rewardAmount)` 한 줄로 지급이
/// 끝난다.
///
/// 실제 컬럼 스키마(사용자가 직접 확인해 준 실제 구성):
/// ```
/// guild_shop_items
///   id             text/uuid  PK
///   item_type      text       ConsumableType.name 값(예: 'goldDungeonTicket')
///   name           text
///   grade          text?      'n'|'r'|'sr'|'ssr'|'sssr'|'ur'|'lr' — 아이콘
///                             색상/등급 표시용. 등급 개념이 없는 상품은 null.
///   price          integer    길드 주화 가격
///   reward_amount  integer    구매 1회당 지급 수량
///   daily_limit    integer    일일 구매 제한 — 파싱만 해 두고 실제 제한
///                             로직은 아직 구현하지 않았다(추후 작업).
/// ```
/// `icon_path` 컬럼은 DB에 없다 — [icon]이 [type]([ConsumableTypeX.icon])
/// 기반 기본 Material 아이콘을 돌려주고, [grade]가 있으면 [getGradeColor]로
/// 등급 색을 함께 보여준다(둘 다 UI가 그 자리에서 계산한다).
class GuildShopItem {
  const GuildShopItem({
    required this.id,
    required this.name,
    required this.type,
    required this.price,
    this.grade,
    this.rewardAmount = 1,
    this.dailyLimit = 0,
  });

  final String id;
  final String name;
  final ConsumableType type;

  /// 등급 개념이 없는 상품(예: 재료/충전권)은 null.
  final ItemGrade? grade;

  /// 길드 주화 가격.
  final int price;

  /// 구매 1회당 지급되는 수량.
  final int rewardAmount;

  /// 일일 구매 제한 — 0이면 무제한으로 취급할 수 있으나, 지금은 어느
  /// 화면/로직도 이 값을 실제로 강제하지 않는다(요구사항: "지금은 파싱
  /// 모델에만 추가해 두고 로직에서는 무시").
  final int dailyLimit;

  IconData get icon => type.icon;

  factory GuildShopItem.fromJson(Map<String, dynamic> json) {
    return GuildShopItem(
      id: json['id'].toString(),
      name: json['name'] as String? ?? '이름 없는 상품',
      // ConsumableType.values.byName은 값이 없거나 알 수 없는 문자열이면
      // ArgumentError를 던진다 — 이 행 하나만 건너뛰도록 호출부
      // (GuildShopManager.loadData)가 try/catch로 감싼다([PotionManager
      // .loadData]의 카탈로그 행 파싱과 같은 관례).
      type: ConsumableType.values.byName(json['item_type'] as String),
      grade: _parseGrade(json['grade'] as String?),
      price: (json['price'] as num?)?.toInt() ?? 0,
      rewardAmount: (json['reward_amount'] as num?)?.toInt() ?? 1,
      dailyLimit: (json['daily_limit'] as num?)?.toInt() ?? 0,
    );
  }

  /// [ShopConsumableEntry._parseGrade]와 같은 관례 — 대소문자를 정규화해서
  /// 매칭을 시도하고, 못 찾으면 예외 대신 로그를 남기고 null(등급 없는
  /// 상품과 동일하게 처리)로 대체한다.
  static ItemGrade? _parseGrade(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final String normalized = raw.trim().toLowerCase();
    for (final ItemGrade grade in ItemGrade.values) {
      if (grade.name == normalized) {
        return grade;
      }
    }
    debugPrint('[GuildShopItem] 알 수 없는 grade 값 "$raw" — null로 처리합니다.');
    return null;
  }

  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'name': name,
    'item_type': type.name,
    'grade': grade?.name,
    'price': price,
    'reward_amount': rewardAmount,
    'daily_limit': dailyLimit,
  };
}
