import 'package:flutter/material.dart';

import '../managers/supabase_manager.dart';
import '../models/arena_model.dart';
import '../utils/number_formatter.dart';

/// 로비 상단의 🏆 버튼 등 여러 진입점에서 공통으로 부르는 진입 함수.
Future<void> showArenaRankingDialog(BuildContext context) {
  return showDialog<void>(context: context, builder: (context) => const ArenaRankingDialog());
}

typedef _RankingLoadResult = ({List<ArenaRankingEntry> entries, List<ArenaRankingReward> rewards});

/// 결투장 실시간 점수 랭킹(최대 100명) + 순위 구간별 보상 안내 팝업 —
/// [WorldBossRankingDialog]와 같은 구조. 열릴 때 딱 한 번 서버에서
/// 스냅샷을 받아온다(라이브 구독은 아니다).
class ArenaRankingDialog extends StatefulWidget {
  const ArenaRankingDialog({super.key});

  @override
  State<ArenaRankingDialog> createState() => _ArenaRankingDialogState();
}

class _ArenaRankingDialogState extends State<ArenaRankingDialog> {
  late final Future<_RankingLoadResult> _loadFuture = _load();

  Future<_RankingLoadResult> _load() async {
    final List<List<Map<String, dynamic>>> results = await Future.wait([
      SupabaseManager.instance.fetchArenaRanking(),
      SupabaseManager.instance.fetchArenaRankingRewards(),
    ]);
    final List<ArenaRankingEntry> entries = results[0].map(ArenaRankingEntry.fromJson).toList();
    final List<ArenaRankingReward> rewards = results[1].map(ArenaRankingReward.fromJson).toList();
    return (entries: entries, rewards: rewards);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1B1B26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: SizedBox(
        width: double.maxFinite,
        height: 560,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 4, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '⚔️ 결투장 랭킹',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<_RankingLoadResult>(
                future: _loadFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator(color: Colors.white54));
                  }
                  final _RankingLoadResult? data = snapshot.data;
                  if (data == null || data.entries.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          '아직 결투장에 기록이 없어요.\n첫 번째로 도전해 보세요!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    );
                  }
                  return _RankingBody(entries: data.entries, rewards: data.rewards);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankingBody extends StatelessWidget {
  const _RankingBody({required this.entries, required this.rewards});

  final List<ArenaRankingEntry> entries;
  final List<ArenaRankingReward> rewards;

  ArenaRankingReward? _rewardForRank(int rank) {
    for (final ArenaRankingReward reward in rewards) {
      if (reward.coversRank(rank)) {
        return reward;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final String? myUserId = SupabaseManager.instance.currentUserId;
    int? myRank;
    for (int i = 0; i < entries.length; i++) {
      if (entries[i].userId == myUserId) {
        myRank = i + 1;
        break;
      }
    }

    return Column(
      children: [
        if (rewards.isNotEmpty) _RewardLegend(rewards: rewards),
        if (myRank != null)
          _MyRankBar(rank: myRank, score: entries[myRank - 1].score)
        else if (myUserId != null)
          const _MyRankBar(rank: null, score: null),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final int rank = index + 1;
              final ArenaRankingEntry entry = entries[index];
              final bool isMe = entry.userId == myUserId;
              return rank <= 3
                  ? _TopRankTile(rank: rank, entry: entry, reward: _rewardForRank(rank), isMe: isMe)
                  : _RankTile(rank: rank, entry: entry, isMe: isMe);
            },
          ),
        ),
      ],
    );
  }
}

class _RewardLegend extends StatelessWidget {
  const _RewardLegend({required this.rewards});

  final List<ArenaRankingReward> rewards;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: rewards.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final ArenaRankingReward reward = rewards[index];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24),
            ),
            alignment: Alignment.center,
            child: Text(
              '${reward.rankRangeLabel} ${reward.rewardLabel}',
              style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          );
        },
      ),
    );
  }
}

/// 리스트 최상단에 고정으로 붙는 "내 순위" 바 — 100위 밖(혹은 아직 전투
/// 기록 없음)이면 [rank]가 null로 넘어와 "100위 밖"으로 표기한다.
class _MyRankBar extends StatelessWidget {
  const _MyRankBar({required this.rank, required this.score});

  final int? rank;
  final int? score;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF6C4FCE).withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6C4FCE), width: 1.4),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              rank != null ? '$rank위' : '100위 밖',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          const Expanded(
            child: Text('나', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          Text(
            score != null ? '$score점' : '-',
            style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _TopRankTile extends StatelessWidget {
  const _TopRankTile({
    required this.rank,
    required this.entry,
    required this.reward,
    required this.isMe,
  });

  final int rank;
  final ArenaRankingEntry entry;
  final ArenaRankingReward? reward;
  final bool isMe;

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
                if (reward != null)
                  Text(
                    '보상: ${reward!.rewardLabel}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
              ],
            ),
          ),
          Text(
            '${entry.score}점',
            style: TextStyle(color: _accent, fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _RankTile extends StatelessWidget {
  const _RankTile({required this.rank, required this.entry, required this.isMe});

  final int rank;
  final ArenaRankingEntry entry;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
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
            width: 36,
            child: Text(
              '$rank',
              style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              entry.nickname,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white),
            ),
          ),
          Text(
            NumberFormatter.format(entry.score.toDouble()),
            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
