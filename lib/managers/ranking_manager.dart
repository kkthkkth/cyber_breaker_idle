import '../models/ranking_model.dart';
import 'supabase_manager.dart';

/// 명예의 전당(글로벌 랭킹 Top 100) 조회 + 캐싱 전담 — 다른 매니저들과
/// 달리 "내 진행 데이터"가 아니라 전체 유저 스냅샷이라 로컬(SharedPreferences)
/// 저장은 하지 않고, 카테고리별 메모리 캐시(TTL [cacheTtl])만 둔다. DB
/// 부하를 막기 위해 이 TTL 안에는 화면을 몇 번을 들어와도 재조회하지
/// 않고, [loadTopRankings]에 `forceRefresh: true`를 주면(Pull-to-refresh)
/// 캐시를 무시하고 새로 받아온다(요구사항: "최소 5분~10분 주기로만 갱신").
///
/// [RankingCategory.chapterPrestige](최고 도달 챕터·환생 횟수)와
/// [RankingCategory.towerFloor](무한의 탑 최고 층수)를 완전히 독립된
/// 캐시로 관리한다 — 한쪽을 강제 새로고침해도 다른 쪽 캐시는 그대로
/// 유지된다.
class RankingManager {
  RankingManager._internal();

  static final RankingManager instance = RankingManager._internal();

  static const Duration cacheTtl = Duration(minutes: 5);

  final Map<RankingCategory, List<RankingEntry>> _entriesByCategory = {
    for (final RankingCategory category in RankingCategory.values) category: const [],
  };
  final Map<RankingCategory, DateTime?> _lastFetchedAtByCategory = {
    for (final RankingCategory category in RankingCategory.values) category: null,
  };

  List<RankingEntry> entriesFor(RankingCategory category) =>
      _entriesByCategory[category] ?? const [];

  bool _isCacheFresh(RankingCategory category) {
    final DateTime? fetchedAt = _lastFetchedAtByCategory[category];
    return fetchedAt != null && DateTime.now().difference(fetchedAt) < cacheTtl;
  }

  /// 단위 테스트 전용 — 실제 네트워크 없이 캐시 상태를 직접 주입한다.
  void debugSeedForTest({
    required RankingCategory category,
    required List<RankingEntry> entries,
    DateTime? fetchedAt,
  }) {
    _entriesByCategory[category] = entries;
    _lastFetchedAtByCategory[category] = fetchedAt;
  }

  /// [category]에 맞는 상위 100명을 가져온다:
  /// - [RankingCategory.chapterPrestige]: 최고 도달 챕터 내림차순(1순위) →
  ///   환생 횟수 내림차순(2순위).
  /// - [RankingCategory.towerFloor]: 무한의 탑 최고 클리어 층수 내림차순.
  ///
  /// `profiles`에는 길드 FK가 없어 길드명은
  /// [SupabaseManager.fetchGuildNamesForUsers]로 한 번 더 조회해 유저 id로
  /// 클라이언트에서 합친다(두 카테고리 공통).
  Future<List<RankingEntry>> loadTopRankings({
    RankingCategory category = RankingCategory.chapterPrestige,
    bool forceRefresh = false,
  }) async {
    final List<RankingEntry> cached = entriesFor(category);
    if (!forceRefresh && _isCacheFresh(category) && cached.isNotEmpty) {
      return cached;
    }

    final List<Map<String, dynamic>> profileRows = category == RankingCategory.towerFloor
        ? await SupabaseManager.instance.fetchTopTowerRankingProfiles()
        : await SupabaseManager.instance.fetchTopRankingProfiles();

    final List<String> userIds = [
      for (final Map<String, dynamic> row in profileRows) row['id'] as String,
    ];
    final List<Map<String, dynamic>> guildRows =
        await SupabaseManager.instance.fetchGuildNamesForUsers(userIds);

    final Map<String, String> guildNameByUserId = {};
    for (final Map<String, dynamic> row in guildRows) {
      final String? userId = row['user_id'] as String?;
      final Map<String, dynamic>? guild = row['guilds'] as Map<String, dynamic>?;
      final String? name = guild?['name'] as String?;
      if (userId != null && name != null && name.isNotEmpty) {
        guildNameByUserId[userId] = name;
      }
    }

    final List<RankingEntry> entries = [
      for (final Map<String, dynamic> row in profileRows)
        category == RankingCategory.towerFloor
            ? RankingEntry.fromTowerProfileJson(row, guildName: guildNameByUserId[row['id'] as String])
            : RankingEntry.fromProfileJson(row, guildName: guildNameByUserId[row['id'] as String]),
    ];
    _entriesByCategory[category] = entries;
    _lastFetchedAtByCategory[category] = DateTime.now();
    return entries;
  }

  /// 마지막으로 불러온 [category] 랭킹(상위 100명) 안에서 [userId]의 순위
  /// (1-base) — 없으면(=100위 밖) null.
  int? rankOf(String userId, {RankingCategory category = RankingCategory.chapterPrestige}) {
    final List<RankingEntry> entries = entriesFor(category);
    for (int i = 0; i < entries.length; i++) {
      if (entries[i].userId == userId) {
        return i + 1;
      }
    }
    return null;
  }
}
