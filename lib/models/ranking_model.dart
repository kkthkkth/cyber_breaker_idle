/// `profiles`(최고 도달 챕터/환생 횟수/무한의 탑 최고 층) +
/// `guild_members`→`guilds(name)` 임베드 조회 결과를 합친 명예의 전당
/// 랭킹 한 행 — [RankingManager]가 두 조회를 클라이언트에서 머지해 이
/// 하나로 만든다(profiles에는 길드 FK가 없어 PostgREST 임베드 한 번으로는
/// 랭킹+길드명을 동시에 가져올 수 없기 때문 — [RankingManager
/// .loadTopRankings] 문서 참고). 순위(rank)는 서버 컬럼이 아니라 정렬된
/// 리스트에서의 위치(index+1)로 매긴다.
///
/// [RankingCategory.chapterPrestige]/[RankingCategory.towerFloor] 두
/// 랭킹이 이 모델 하나를 공유한다 — 어느 카테고리로 조회했든 관련 없는
/// 필드는 그냥 0으로 남는다(예: 탑 랭킹 조회 결과는 [prestigeCount]가
/// 항상 0).
class RankingEntry {
  const RankingEntry({
    required this.userId,
    required this.nickname,
    this.highestReachedChapter = 0,
    this.prestigeCount = 0,
    this.highestTowerFloor = 0,
    this.guildName,
  });

  final String userId;
  final String nickname;
  final int highestReachedChapter;
  final int prestigeCount;
  final int highestTowerFloor;

  /// 소속 길드가 없으면 null.
  final String? guildName;

  factory RankingEntry.fromProfileJson(Map<String, dynamic> json, {String? guildName}) {
    final String? nickname = json['nickname'] as String?;
    return RankingEntry(
      userId: json['id'] as String,
      nickname: (nickname == null || nickname.trim().isEmpty) ? '익명의 모험가' : nickname,
      highestReachedChapter: (json['highest_reached_chapter'] as num?)?.toInt() ?? 1,
      prestigeCount: (json['prestige_count'] as num?)?.toInt() ?? 0,
      guildName: guildName,
    );
  }

  factory RankingEntry.fromTowerProfileJson(Map<String, dynamic> json, {String? guildName}) {
    final String? nickname = json['nickname'] as String?;
    return RankingEntry(
      userId: json['id'] as String,
      nickname: (nickname == null || nickname.trim().isEmpty) ? '익명의 모험가' : nickname,
      highestTowerFloor: (json['highest_tower_floor'] as num?)?.toInt() ?? 0,
      guildName: guildName,
    );
  }
}

/// 명예의 전당이 지원하는 랭킹 종류 — [RankingManager]가 종류별로 독립된
/// 캐시를 둔다.
enum RankingCategory { chapterPrestige, towerFloor }

extension RankingCategoryX on RankingCategory {
  String get displayName => switch (this) {
    RankingCategory.chapterPrestige => '챕터·환생',
    RankingCategory.towerFloor => '무한의 탑',
  };
}
