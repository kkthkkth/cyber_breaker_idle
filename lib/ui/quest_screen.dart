import 'package:flutter/material.dart';

import '../managers/battle_pass_manager.dart';
import '../managers/quest_manager.dart';
import '../models/quest_model.dart';
import '../widgets/bouncy_button.dart';
import '../widgets/center_toast.dart';
import 'battle_pass_screen.dart';

/// 퀘스트 화면 — 일일/주간/월간 3개 탭으로 나뉘어, 각 주기마다 DB
/// 카탈로그([Quest])에서 무작위로 배정된 퀘스트([QuestManager
/// .dailyQuests]/[weeklyQuests]/[monthlyQuests])의 진행도 프로그레스 바를
/// 보여주고, 달성한 퀘스트는 [받기] 버튼으로 [Quest.rewardType]에 맞는
/// 보상(골드/보석/BP/룬 조각 등)을 수령한다. 우측 상단 버튼으로
/// [BattlePassScreen]에 바로 진입할 수 있다.
class QuestScreen extends StatelessWidget {
  const QuestScreen({super.key});

  Future<void> _claim(BuildContext context, QuestDisplayItem item) async {
    final Quest? claimed = await QuestManager.instance.claimQuest(item.quest.id);
    if (!context.mounted || claimed == null) {
      return;
    }
    showCenterToast(context, '${claimed.rewardLabel} 획득!');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([QuestManager.instance, BattlePassManager.instance]),
      builder: (context, _) {
        final List<QuestDisplayItem> dailyItems = QuestManager.instance.dailyQuests;
        final List<QuestDisplayItem> weeklyItems = QuestManager.instance.weeklyQuests;
        final List<QuestDisplayItem> monthlyItems = QuestManager.instance.monthlyQuests;
        final BattlePassManager battlePass = BattlePassManager.instance;

        return DefaultTabController(
          length: 3,
          child: Scaffold(
            backgroundColor: const Color(0xFF14141C),
            appBar: AppBar(
              backgroundColor: const Color(0xFF1B1B26),
              elevation: 0,
              // 뒤로 가기 버튼처럼 별도 색을 안 준 아이콘이 어두운 배경에
              // 묻히지 않도록 명시한다.
              foregroundColor: Colors.white,
              title: const Text(
                '퀘스트',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              centerTitle: true,
              bottom: const TabBar(
                indicatorColor: Color(0xFF6C4FCE),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                tabs: [
                  Tab(text: '일일'),
                  Tab(text: '주간'),
                  Tab(text: '월간'),
                ],
              ),
            ),
            body: Column(
              children: [
                InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const BattlePassScreen()),
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6C4FCE), Color(0xFF3A2A6E)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.military_tech, color: Colors.amberAccent, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '배틀패스 Lv.${battlePass.level}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: battlePass.levelProgressRatio,
                                  minHeight: 6,
                                  backgroundColor: Colors.white24,
                                  valueColor: const AlwaysStoppedAnimation(Colors.amberAccent),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right, color: Colors.white70),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _QuestListView(
                        items: dailyItems,
                        emptyMessage: '오늘의 퀘스트를 불러오는 중이에요.',
                        onClaim: (item) => _claim(context, item),
                      ),
                      _QuestListView(
                        items: weeklyItems,
                        emptyMessage: '이번 주 퀘스트를 불러오는 중이에요.',
                        onClaim: (item) => _claim(context, item),
                      ),
                      _QuestListView(
                        items: monthlyItems,
                        emptyMessage: '이번 달 퀘스트를 불러오는 중이에요.',
                        onClaim: (item) => _claim(context, item),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QuestListView extends StatelessWidget {
  const _QuestListView({
    required this.items,
    required this.emptyMessage,
    required this.onClaim,
  });

  final List<QuestDisplayItem> items;
  final String emptyMessage;
  final ValueChanged<QuestDisplayItem> onClaim;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(emptyMessage, style: const TextStyle(color: Colors.white54)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final QuestDisplayItem item = items[index];
        return _QuestTile(item: item, onClaim: () => onClaim(item));
      },
    );
  }
}

class _QuestTile extends StatelessWidget {
  const _QuestTile({required this.item, required this.onClaim});

  final QuestDisplayItem item;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final bool claimed = item.progress.isClaimed;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF20202C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: item.isClaimable ? Colors.amberAccent : const Color(0xFF3A3A4A),
          width: item.isClaimable ? 1.6 : 1.2,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.quest.description,
                  style: TextStyle(
                    color: claimed ? Colors.white38 : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: item.ratio,
                    minHeight: 8,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation(
                      claimed ? Colors.white24 : const Color(0xFF6C4FCE),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.progress.currentCount} / ${item.quest.targetCount} · 보상 ${item.quest.rewardLabel}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (claimed)
            const Icon(Icons.check_circle, color: Colors.greenAccent)
          else
            ElevatedButton(
              onPressed: withTapHaptic(item.isClaimable ? onClaim : null),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amberAccent,
                foregroundColor: Colors.black87,
                disabledBackgroundColor: const Color(0xFF3A3A4A),
                disabledForegroundColor: Colors.white38,
              ),
              child: const Text('받기'),
            ),
        ],
      ),
    );
  }
}
