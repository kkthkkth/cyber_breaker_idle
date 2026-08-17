/// 업적 트랙 3종 — 방치형 RPG 핵심 지표를 그대로 진행도로 쓴다
/// ([AchievementManager] 참고).
enum AchievementCategory { monsterKill, highestChapter, gachaCount }

String achievementCategoryLabel(AchievementCategory category) => switch (category) {
  AchievementCategory.monsterKill => '몬스터 처치',
  AchievementCategory.highestChapter => '최고 도달 챕터',
  AchievementCategory.gachaCount => '누적 가챠 횟수',
};

/// 업적 한 단계 — 진행도가 [threshold]에 도달하면 보석 [gemReward]를 받을
/// 수 있다. 단계가 오를수록 [gemReward]도 커지도록
/// [AchievementManager.tiers]에서 구성한다.
class AchievementTier {
  const AchievementTier({required this.threshold, required this.gemReward});

  final int threshold;
  final int gemReward;
}

/// `profiles`/`user_achievements` 양쪽에서 이 업적 하나를 가리키는 고유
/// 문자열 키(예: `'monsterKill:100'`) — Supabase `user_achievements
/// .achievement_key` 컬럼 값과 형식이 같다.
String achievementKey(AchievementCategory category, int threshold) =>
    '${category.name}:$threshold';
