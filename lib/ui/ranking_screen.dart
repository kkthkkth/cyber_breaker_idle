import 'package:flutter/material.dart';

import '../managers/dungeon_manager.dart';
import '../managers/game_manager.dart';
import '../managers/guild_manager.dart';
import '../managers/prestige_manager.dart';
import '../managers/ranking_manager.dart';
import '../managers/supabase_manager.dart';
import '../models/ranking_model.dart';

/// 홈 화면의 트로피 버튼 등 여러 진입점에서 공통으로 부르는 진입 함수 —
/// 랭킹은 항목이 많고(최대 100명 + 내 순위 바) 필터/새로고침 상호작용이
/// 있어 [WorldBossRankingDialog]와 달리 모달이 아니라 전체 화면으로 연다.
Future<void> showRankingScreen(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (context) => const RankingScreen()),
  );
}

/// 명예의 전당 — [RankingManager]가 카테고리별로 메모리에 캐싱한 상위
/// 100명을 탭 2개(챕터·환생 / 무한의 탑)로 보여준다. 각 탭은
/// [_RankingCategoryView]가 독립적으로 로드/새로고침한다.
class RankingScreen extends StatelessWidget {
  const RankingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF14141C),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1B1B26),
          elevation: 0,
          foregroundColor: Colors.white,
          centerTitle: true,
          title: const Text(
            '🏆 명예의 전당',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          bottom: TabBar(
            indicatorColor: const Color(0xFF6C4FCE),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: [
              for (final RankingCategory category in RankingCategory.values)
                Tab(text: category.displayName),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final RankingCategory category in RankingCategory.values)
              _RankingCategoryView(category: category),
          ],
        ),
      ),
    );
  }
}

class _RankingCategoryView extends StatefulWidget {
  const _RankingCategoryView({required this.category});

  final RankingCategory category;

  @override
  State<_RankingCategoryView> createState() => _RankingCategoryViewState();
}

class _RankingCategoryViewState extends State<_RankingCategoryView> {
  late Future<List<RankingEntry>> _loadFuture =
      RankingManager.instance.loadTopRankings(category: widget.category);

  Future<void> _refresh() async {
    final Future<List<RankingEntry>> future = RankingManager.instance.loadTopRankings(
      category: widget.category,
      forceRefresh: true,
    );
    setState(() => _loadFuture = future);
    await future;
  }

  /// 상위 100명 안에 내가 없을 때(=100위 밖) 보여줄 대체 항목 — 서버에
  /// 다시 물을 필요 없이, 이미 로컬에 있는 내 최신 값(GameManager/
  /// PrestigeManager/DungeonManager/GuildManager)을 그대로 쓴다
  /// ([WorldBossRankingDialog]의 `myEntry ??= ...` 폴백과 같은 관례).
  RankingEntry _myFallbackEntry(String userId) {
    final String guildName = GuildManager.instance.guildName;
    final String? resolvedGuildName = guildName.isEmpty ? null : guildName;
    return switch (widget.category) {
      RankingCategory.towerFloor => RankingEntry(
        userId: userId,
        nickname: '나',
        highestTowerFloor: DungeonManager.instance.highestClearedFloor,
        guildName: resolvedGuildName,
      ),
      RankingCategory.chapterPrestige => RankingEntry(
        userId: userId,
        nickname: '나',
        highestReachedChapter: GameManager.instance.highestReachedChapter,
        prestigeCount: PrestigeManager.instance.prestigeCount,
        guildName: resolvedGuildName,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RankingEntry>>(
      future: _loadFuture,
      builder: (context, snapshot) {
        final bool isLoading = snapshot.connectionState != ConnectionState.done;
        final List<RankingEntry> entries = snapshot.data ?? const [];
        final String? myUserId = SupabaseManager.instance.currentUserId;

        int? myRank;
        RankingEntry? myEntry;
        for (int i = 0; i < entries.length; i++) {
          if (entries[i].userId == myUserId) {
            myRank = i + 1;
            myEntry = entries[i];
            break;
          }
        }
        myEntry ??= myUserId == null ? null : _myFallbackEntry(myUserId);

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.white54))
              : RefreshIndicator(
                  onRefresh: _refresh,
                  color: Colors.white,
                  backgroundColor: const Color(0xFF20202C),
                  child: entries.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 140),
                            Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  '아직 랭킹에 등록된 모험가가 없어요.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white54),
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final int rank = index + 1;
                            final RankingEntry entry = entries[index];
                            final bool isMe = entry.userId == myUserId;
                            return rank <= 3
                                ? _TopRankTile(
                                    rank: rank,
                                    entry: entry,
                                    isMe: isMe,
                                    category: widget.category,
                                  )
                                : _RankTile(
                                    rank: rank,
                                    entry: entry,
                                    isMe: isMe,
                                    category: widget.category,
                                  );
                          },
                        ),
                ),
          bottomNavigationBar: myEntry == null
              ? null
              : SafeArea(
                  top: false,
                  child: _MyRankBar(rank: myRank, entry: myEntry, category: widget.category),
                ),
        );
      },
    );
  }
}

/// [entry]/[category] 조합에서 강조용 1줄 + 보조용 1줄 텍스트를 뽑는다 —
/// 세 타일 위젯([_TopRankTile]/[_RankTile]/[_MyRankBar])이 전부 공유한다.
({String primary, String secondary}) _statLinesFor(RankingEntry entry, RankingCategory category) {
  return switch (category) {
    RankingCategory.towerFloor => (primary: '${entry.highestTowerFloor}층', secondary: '최고 클리어'),
    RankingCategory.chapterPrestige => (
      primary: '${entry.highestReachedChapter}챕터',
      secondary: '환생 ${entry.prestigeCount}회',
    ),
  };
}

/// 1~3위 전용 — 왕관/메달 이모지와 금/은/동 강조 색으로 화려하게
/// ([WorldBossRankingDialog]의 `_TopRankTile`과 같은 시각 언어).
class _TopRankTile extends StatelessWidget {
  const _TopRankTile({
    required this.rank,
    required this.entry,
    required this.isMe,
    required this.category,
  });

  final int rank;
  final RankingEntry entry;
  final bool isMe;
  final RankingCategory category;

  Color get _accent => switch (rank) {
    1 => const Color(0xFFFFD700),
    2 => const Color(0xFFC0C0C0),
    _ => const Color(0xFFCD7F32),
  };

  String get _medal => switch (rank) {
    1 => '👑',
    2 => '🥈',
    _ => '🥉',
  };

  @override
  Widget build(BuildContext context) {
    final ({String primary, String secondary}) stats = _statLinesFor(entry, category);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [_accent.withValues(alpha: 0.35), Colors.transparent]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isMe ? Colors.cyanAccent : _accent, width: isMe ? 2 : 1.4),
      ),
      child: Row(
        children: [
          Text(_medal, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.nickname,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _accent, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.guildName ?? '무소속',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                stats.primary,
                style: TextStyle(color: _accent, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                stats.secondary,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 4~100위 — 깔끔한 리스트 타일.
class _RankTile extends StatelessWidget {
  const _RankTile({
    required this.rank,
    required this.entry,
    required this.isMe,
    required this.category,
  });

  final int rank;
  final RankingEntry entry;
  final bool isMe;
  final RankingCategory category;

  @override
  Widget build(BuildContext context) {
    final ({String primary, String secondary}) stats = _statLinesFor(entry, category);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFF6C4FCE).withValues(alpha: 0.2) : const Color(0xFF20202C),
        borderRadius: BorderRadius.circular(10),
        border: isMe ? Border.all(color: Colors.cyanAccent) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '$rank',
              style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.nickname,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  entry.guildName ?? '무소속',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                stats.primary,
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12),
              ),
              Text(
                stats.secondary,
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 화면 최하단에 내비게이션 바처럼 항상 고정으로 붙는 "내 순위" 바 —
/// 100위 밖이면 순위 대신 "100위 밖"으로 표기한다(요구사항).
class _MyRankBar extends StatelessWidget {
  const _MyRankBar({required this.rank, required this.entry, required this.category});

  final int? rank;
  final RankingEntry entry;
  final RankingCategory category;

  @override
  Widget build(BuildContext context) {
    final ({String primary, String secondary}) stats = _statLinesFor(entry, category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1B1B26),
        border: Border(top: BorderSide(color: Color(0xFF6C4FCE), width: 1.4)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              rank != null ? '$rank위' : '100위 밖',
              style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.nickname,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  entry.guildName ?? '무소속',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                stats.primary,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Text(
                stats.secondary,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
