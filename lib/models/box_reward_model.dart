import 'consumable_item_model.dart';

enum BoxRewardKind { gold, gem, dust, item }

/// One possible payout inside a reward box. [weight] is relative (not
/// required to sum to 1) — see [BoxRewardManager]'s weighted pick.
class BoxRewardEntry {
  const BoxRewardEntry({
    required this.kind,
    required this.amount,
    required this.weight,
    this.itemType,
    this.iconPath,
  });

  final BoxRewardKind kind;
  final int amount;
  final double weight;

  /// Only set when [kind] is [BoxRewardKind.item].
  final ConsumableType? itemType;

  /// Local `assets/...` path or a network `http(s)://...` URL for the result
  /// popup; null falls back to a kind/itemType-derived built-in icon.
  final String? iconPath;

  String get label {
    switch (kind) {
      case BoxRewardKind.gold:
        return '골드 $amount';
      case BoxRewardKind.gem:
        return '보석 $amount';
      case BoxRewardKind.dust:
        return '가루 $amount';
      case BoxRewardKind.item:
        return '${itemType?.displayName ?? '아이템'} x$amount';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'kind': kind.name,
      'amount': amount,
      'weight': weight,
      'itemType': itemType?.name,
      'iconPath': iconPath,
    };
  }

  factory BoxRewardEntry.fromJson(Map<String, dynamic> json) {
    return BoxRewardEntry(
      kind: BoxRewardKind.values.byName(json['kind'] as String),
      amount: json['amount'] as int,
      weight: (json['weight'] as num).toDouble(),
      itemType: json['itemType'] != null
          ? ConsumableType.values.byName(json['itemType'] as String)
          : null,
      iconPath: json['iconPath'] as String?,
    );
  }
}
