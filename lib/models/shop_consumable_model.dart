import 'package:flutter/foundation.dart';

import '../constants/app_images.dart';
import '../models/equipment.dart';

/// 상점 소모품 카탈로그의 세 갈래 — 물약(등급별), 호감도 아이템, 입장
/// 충전권(월드보스 등). [item_type] 컬럼값과 1:1로 대응한다.
enum ShopConsumableCategory { potion, affectionGift, ticket }

/// 아이템을 살 때 쓰는 재화 — `base_currency` 컬럼값('coin'|'gem')과 대응.
enum ShopCurrency { coin, gem }

/// Supabase `consumable_items` 테이블의 행 하나 — 상점에 나열되는 물약/
/// 호감도 아이템의 정적 정의다. 실제 보유 개수는 여기 없다
/// ([PotionManager.countOf] 참고).
///
/// 실제 컬럼 스키마(유저 확인 완료):
/// ```
/// consumable_items
///   id                     text/uuid  PK
///   name                   text
///   item_type              text       'potion' | 'affection'
///   grade                  text       'n'|'r'|'sr'|'ssr'|'sssr'|'ur'|'lr' (물약만, 호감도 아이템은 null)
///   effect_value           numeric    물약=최대체력 대비 회복 %, 호감도 아이템=호감도 상승 %
///   base_currency          text       'coin' | 'gem' — 기본(무제한) 구매 시 사용하는 재화
///   base_price             integer    base_currency 기준 가격
///   daily_coin_limit       integer    0이면 "제한된 코인 구매" 경로 자체가 없음(=이미
///                                     base_currency가 coin이라 무제한 코인 구매가 가능하거나,
///                                     그 등급/아이템엔 코인 구매를 아예 안 열어줬다는 뜻).
///                                     0보다 크면 하루 이 횟수까지 [coinPriceForLimit]로
///                                     코인 구매를 추가로 허용한다(SSR 이상 물약의
///                                     "기본은 보석, 하루 N번은 코인" 규칙이 이 필드 하나로 표현됨).
///   coin_price_for_limit   integer    daily_coin_limit>0일 때, 그 한도 안에서 코인으로
///                                     살 때의 가격(보통 base_price(보석)보다 코인 단위로 저렴).
/// ```
/// `icon_path` 컬럼은 DB에 없다 — [iconPath]가 [item_type]/[grade] 조합으로
/// 경로를 자동 계산한다([AppImages.potionIcon]/[AppImages.affectionGiftIcon]).
class ShopConsumableEntry {
  const ShopConsumableEntry({
    required this.id,
    required this.name,
    required this.category,
    required this.effectValue,
    required this.baseCurrency,
    required this.basePrice,
    this.grade,
    this.dailyCoinLimit = 0,
    this.coinPriceForLimit = 0,
  });

  final String id;
  final String name;
  final ShopConsumableCategory category;

  /// 물약 전용 — 호감도 아이템은 항상 null.
  final ItemGrade? grade;

  /// 물약 = 최대 체력 대비 회복 비율(%), 호감도 아이템 = 호감도 상승치(%).
  final double effectValue;

  final ShopCurrency baseCurrency;
  final int basePrice;

  /// 0이면 "제한된 코인 구매" 옵션 자체가 없다.
  final int dailyCoinLimit;
  final int coinPriceForLimit;

  bool get isPotion => category == ShopConsumableCategory.potion;
  bool get isAffectionGift => category == ShopConsumableCategory.affectionGift;
  bool get isTicket => category == ShopConsumableCategory.ticket;

  /// [PotionManager.purchaseWithLimitedCoin]을 쓸 수 있는 아이템인지 —
  /// SSR 이상 물약처럼 "기본은 보석이지만 하루 N번은 코인으로도" 살 수 있는
  /// 특별 구매 경로가 있는지를 등급이 아니라 이 필드(서버 데이터) 하나로
  /// 판단한다. 등급으로 하드코딩하지 않으므로, 나중에 SR 물약에도 이런
  /// 규칙을 주고 싶으면 DB에서 `daily_coin_limit`만 채우면 된다.
  bool get hasLimitedCoinOption => dailyCoinLimit > 0;

  /// 아직 실제 아트가 준비되지 않아, item_type+grade(물약) /
  /// item_type+base_currency(호감도 아이템, coin/gem 티어 구분) /
  /// item_type(충전권, 종류가 하나뿐이라 티어 구분 없음)로 계산한 원격
  /// 경로를 돌려준다 — [CustomSafeImage]가 404를 조용히 placeholder로
  /// 대체하므로 실제 파일이 없어도 안전하다.
  String get iconPath {
    if (isPotion) {
      return AppImages.potionIcon(grade ?? ItemGrade.n);
    }
    if (isTicket) {
      return AppImages.ticketIcon();
    }
    return AppImages.affectionGiftIcon(isGemTier: baseCurrency == ShopCurrency.gem);
  }

  /// `grade` 컬럼 값을 [ItemGrade]로 변환한다 — `ItemGrade.values.byName`은
  /// 대소문자가 정확히 일치하지 않거나(`'SSR'` vs `ssr`) 값이 빈 문자열
  /// (NULL이 아니라 `''`인 컬럼도 흔하다)이거나 아예 알려지지 않은 값이면
  /// [ArgumentError]를 던져서, 이 한 필드 때문에 행 전체 파싱이(나아가
  /// `catalogRows.map(...).toList()`를 쓰는 호출부에서는 카탈로그 전체
  /// 로드가) 조용히 실패할 수 있었다. 대소문자를 정규화해서 매칭을
  /// 시도하고, 그래도 못 찾으면 예외 대신 로그를 남기고 null(호감도
  /// 아이템/충전권과 동일하게 처리)로 대체한다.
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
    debugPrint('[ShopConsumableEntry] 알 수 없는 grade 값 "$raw" — null로 처리합니다.');
    return null;
  }

  factory ShopConsumableEntry.fromJson(Map<String, dynamic> json) {
    final ShopConsumableCategory category = switch (json['item_type'] as String?) {
      'affection' => ShopConsumableCategory.affectionGift,
      'ticket' => ShopConsumableCategory.ticket,
      _ => ShopConsumableCategory.potion,
    };
    return ShopConsumableEntry(
      id: json['id'].toString(),
      name: json['name'] as String? ?? '이름 없는 아이템',
      category: category,
      grade: _parseGrade(json['grade'] as String?),
      effectValue: (json['effect_value'] as num?)?.toDouble() ?? 0,
      baseCurrency: (json['base_currency'] as String?) == 'gem' ? ShopCurrency.gem : ShopCurrency.coin,
      basePrice: (json['base_price'] as num?)?.toInt() ?? 0,
      dailyCoinLimit: (json['daily_coin_limit'] as num?)?.toInt() ?? 0,
      coinPriceForLimit: (json['coin_price_for_limit'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'name': name,
    'item_type': switch (category) {
      ShopConsumableCategory.affectionGift => 'affection',
      ShopConsumableCategory.ticket => 'ticket',
      ShopConsumableCategory.potion => 'potion',
    },
    'grade': grade?.name,
    'effect_value': effectValue,
    'base_currency': baseCurrency == ShopCurrency.gem ? 'gem' : 'coin',
    'base_price': basePrice,
    'daily_coin_limit': dailyCoinLimit,
    'coin_price_for_limit': coinPriceForLimit,
  };
}
