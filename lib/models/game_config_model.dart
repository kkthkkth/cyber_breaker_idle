/// Server-tunable game constants. Dummy defaults for now — once these move
/// to a DB/remote-config, replace the default construction with
/// `GameConfig.fromJson(response)` and nothing downstream needs to change.
class GameConfig {
  const GameConfig({
    this.offlineRewardEfficiency = 0.5,
    this.maxOfflineHours = 12,
  });

  /// Offline earnings run at this fraction of the online rate.
  /// 0.5 = offline income is 50% as fast as online income.
  final double offlineRewardEfficiency;

  /// Offline gap is clamped to at most this many hours before any reward
  /// (gold or item drops) is computed — without this cap, a very long gap
  /// (real absence, or a manipulated device clock) would otherwise produce
  /// an unbounded reward.
  final int maxOfflineHours;

  Map<String, dynamic> toJson() {
    return {
      'offlineRewardEfficiency': offlineRewardEfficiency,
      'maxOfflineHours': maxOfflineHours,
    };
  }

  factory GameConfig.fromJson(Map<String, dynamic> json) {
    return GameConfig(
      offlineRewardEfficiency:
          (json['offlineRewardEfficiency'] as num?)?.toDouble() ?? 0.5,
      maxOfflineHours: (json['maxOfflineHours'] as num?)?.toInt() ?? 12,
    );
  }
}
