import 'consumable_item_model.dart';

/// One independently-rolled entry in a [DropTable]: on a kill, [dropRate]
/// (0.0–1.0) is the chance to receive one [type].
class DropEntry {
  const DropEntry({required this.type, required this.dropRate});

  final ConsumableType type;
  final double dropRate;

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'dropRate': dropRate,
    };
  }

  factory DropEntry.fromJson(Map<String, dynamic> json) {
    return DropEntry(
      type: ConsumableType.values.byName(json['type'] as String),
      dropRate: (json['dropRate'] as num).toDouble(),
    );
  }
}

/// Monster kill drop table. Dummy rates for now; once drop rates move to a
/// DB/remote-config, decode a list of [DropEntry] into [entries] — the
/// roll logic in ConsumableManager.rollDrops only ever reads through it.
class DropTable {
  const DropTable(this.entries);

  final List<DropEntry> entries;

  static const DropTable defaultTable = DropTable([
    DropEntry(type: ConsumableType.premiumGachaTicket, dropRate: 0.05),
    DropEntry(type: ConsumableType.speed2x, dropRate: 0.02),
    DropEntry(type: ConsumableType.speed3x, dropRate: 0.01),
    DropEntry(type: ConsumableType.skillReset, dropRate: 0.01),
    DropEntry(type: ConsumableType.crossElementBook, dropRate: 0.01),
  ]);

  Map<String, dynamic> toJson() {
    return {
      'entries': entries.map((entry) => entry.toJson()).toList(),
    };
  }

  factory DropTable.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawEntries = json['entries'] as List<dynamic>;
    return DropTable(
      rawEntries
          .map((entry) => DropEntry.fromJson(entry as Map<String, dynamic>))
          .toList(),
    );
  }
}
