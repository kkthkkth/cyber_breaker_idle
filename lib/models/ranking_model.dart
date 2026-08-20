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
    this.combatPower = 0,
    this.guildName,
    this.equippedCharacter,
  });

  final String userId;
  final String nickname;
  final int highestReachedChapter;
  final int prestigeCount;
  final int highestTowerFloor;

  /// [RankingCategory.combatPower] 전용 — [GameManager.totalCombatPower]가
  /// `profiles.combat_power`에 동기화해 둔 값(GameManager.syncCombatPower
  /// 문서 참고). 다른 카테고리로 조회했으면 항상 0.
  final int combatPower;

  /// 소속 길드가 없으면 null.
  final String? guildName;

  /// `profiles.equipped_character`([Equipment.gradeBadgeLabel] 형식) —
  /// [RankingCategory.combatPower]는 RPC(`get_combat_power_ranking`)가 이
  /// 컬럼을 아직 돌려주지 않으면(서버 함수 업데이트 전) 항상 null이라
  /// [_TopRankTile]/[_RankTile]이 기본 아바타 아이콘으로 대체한다.
  final String? equippedCharacter;

  factory RankingEntry.fromProfileJson(Map<String, dynamic> json, {String? guildName}) {
    final String? nickname = json['nickname'] as String?;
    return RankingEntry(
      userId: json['id'] as String,
      nickname: (nickname == null || nickname.trim().isEmpty) ? '익명의 모험가' : nickname,
      highestReachedChapter: (json['highest_reached_chapter'] as num?)?.toInt() ?? 1,
      prestigeCount: (json['prestige_count'] as num?)?.toInt() ?? 0,
      guildName: guildName,
      equippedCharacter: _parseEquippedCharacter(json['equipped_character']),
    );
  }

  factory RankingEntry.fromTowerProfileJson(Map<String, dynamic> json, {String? guildName}) {
    final String? nickname = json['nickname'] as String?;
    return RankingEntry(
      userId: json['id'] as String,
      nickname: (nickname == null || nickname.trim().isEmpty) ? '익명의 모험가' : nickname,
      highestTowerFloor: (json['highest_tower_floor'] as num?)?.toInt() ?? 0,
      guildName: guildName,
      equippedCharacter: _parseEquippedCharacter(json['equipped_character']),
    );
  }

  /// [SupabaseManager.fetchCombatPowerRanking]의 RPC 결과 행 — 컬럼은
  /// `id`/`nickname`/`combat_power` 셋뿐이다(블랙리스트 제외는 RPC 안에서
  /// 이미 끝난 상태로 내려온다). `equipped_character`는 RPC가 아직 안
  /// 돌려주므로(서버 함수 업데이트 전) 있으면 읽고 없으면 null.
  factory RankingEntry.fromCombatPowerProfileJson(Map<String, dynamic> json, {String? guildName}) {
    final String? nickname = json['nickname'] as String?;
    return RankingEntry(
      userId: json['id'] as String,
      nickname: (nickname == null || nickname.trim().isEmpty) ? '익명의 모험가' : nickname,
      combatPower: (json['combat_power'] as num?)?.toInt() ?? 0,
      guildName: guildName,
      equippedCharacter: _parseEquippedCharacter(json['equipped_character']),
    );
  }

  static String? _parseEquippedCharacter(dynamic raw) {
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }
    return raw;
  }
}

/// 명예의 전당이 지원하는 랭킹 종류 — [RankingManager]가 종류별로 독립된
/// 캐시를 둔다.
enum RankingCategory { chapterPrestige, towerFloor, combatPower }

extension RankingCategoryX on RankingCategory {
  String get displayName => switch (this) {
    RankingCategory.chapterPrestige => '챕터·환생',
    RankingCategory.towerFloor => '무한의 탑',
    RankingCategory.combatPower => '전투력',
  };
}
