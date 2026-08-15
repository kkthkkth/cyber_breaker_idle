import 'package:flutter/material.dart';

import '../managers/arena_manager.dart';
import '../models/arena_model.dart';
import 'arena_battle_screen.dart';
import 'arena_ranking_dialog.dart';

/// 결투장(Arena) 로비 — 내 점수/승패 기록/랭킹 버튼을 상단에, 나와 점수가
/// 비슷한 도전 상대 3명을 중앙에 보여준다. 던전 탭 배너에서 진입한다.
/// 열릴 때마다 [ArenaManager.syncCombatPower]로 내 전투력을 최신화하고
/// (다른 유저가 나를 상대로 매칭할 때 참조하는 값이라 신선해야 한다)
/// 상대 후보를 새로 뽑는다.
class ArenaScreen extends StatefulWidget {
  const ArenaScreen({super.key});

  @override
  State<ArenaScreen> createState() => _ArenaScreenState();
}

class _ArenaScreenState extends State<ArenaScreen> {
  bool _isLoading = true;
  List<ArenaOpponent> _opponents = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    await ArenaManager.instance.syncCombatPower();
    final List<ArenaOpponent> opponents = await ArenaManager.instance.fetchOpponents();
    if (!mounted) {
      return;
    }
    setState(() {
      _opponents = opponents;
      _isLoading = false;
    });
  }

  Future<void> _challenge(ArenaOpponent opponent) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ArenaBattleScreen(opponent: opponent)),
    );
    // 전투 결과로 내 점수가 바뀌었을 수 있으니(매칭 범위가 점수 기준이라)
    // 돌아오면 상대 후보를 다시 뽑는다.
    if (mounted) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ArenaManager.instance,
      builder: (context, _) {
        final ArenaManager manager = ArenaManager.instance;

        return Scaffold(
          backgroundColor: const Color(0xFF14141C),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1B1B26),
            elevation: 0,
            // 뒤로 가기 버튼처럼 별도 색을 안 준 아이콘이 어두운 배경에
            // 묻히지 않도록 명시한다.
            foregroundColor: Colors.white,
            title: const Text(
              '결투장',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.emoji_events, color: Colors.amberAccent),
                onPressed: () => showArenaRankingDialog(context),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white70),
                onPressed: _isLoading ? null : _refresh,
              ),
            ],
          ),
          body: Column(
            children: [
              _ArenaStatsHeader(score: manager.score, wins: manager.wins, losses: manager.losses),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '도전 상대',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Colors.white54))
                    : _opponents.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            '점수가 비슷한 상대를 찾지 못했어요.\n잠시 후 다시 시도해 보세요.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white54),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: _opponents.length,
                        itemBuilder: (context, index) {
                          final ArenaOpponent opponent = _opponents[index];
                          return _OpponentTile(
                            opponent: opponent,
                            onChallenge: () => _challenge(opponent),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ArenaStatsHeader extends StatelessWidget {
  const _ArenaStatsHeader({required this.score, required this.wins, required this.losses});

  final int score;
  final int wins;
  final int losses;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF20202C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A4A)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF6C4FCE).withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF6C4FCE), width: 1.5),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.military_tech, color: Color(0xFF6C4FCE), size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$score점',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                ),
                const SizedBox(height: 4),
                Text(
                  '$wins승 $losses패',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OpponentTile extends StatelessWidget {
  const _OpponentTile({required this.opponent, required this.onChallenge});

  final ArenaOpponent opponent;
  final VoidCallback onChallenge;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF20202C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF3A3A4A), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.6)),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.person_outline, color: Colors.redAccent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  opponent.nickname,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  '전투력 ${opponent.combatPower} · ${opponent.score}점',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onChallenge,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('도전하기'),
          ),
        ],
      ),
    );
  }
}
