import 'package:flutter/material.dart';

import '../managers/battle_pass_manager.dart';
import '../managers/quest_manager.dart';
import '../models/quest_model.dart';
import '../widgets/center_toast.dart';
import 'battle_pass_screen.dart';

/// 앱 전역 상단 AppBar([main.dart]의 actions)에서 쓰는 퀘스트 진입
/// 버튼 — 수령 가능한 퀘스트가 있으면 빨간 뱃지를 띄운다.
/// [MailboxHudButton]과 같은 관례. 기존 [_QuestHudButton](home_screen.dart,
/// 미션 다이얼로그를 여는 클립보드 아이콘)과는 별개의 새 배틀패스 일일
/// 퀘스트 진입점이다 — 이름 충돌을 피하려고 "Daily"를 붙였다.
class DailyQuestHudButton extends StatelessWidget {
  const DailyQuestHudButton({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: QuestManager.instance,
      builder: (context, _) {
        return IconButton(
          icon: Badge(
            isLabelVisible: QuestManager.instance.hasClaimableQuest,
            backgroundColor: Colors.redAccent,
            smallSize: 10,
            child: const Text('📜', style: TextStyle(fontSize: 18)),
          ),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const QuestScreen()),
          ),
        );
      },
    );
  }
}

/// 일일 퀘스트 화면 — 목표 진행도 프로그레스 바를 보여주고, 달성한
/// 퀘스트는 [받기] 버튼으로 배틀패스 BP 경험치를 수령한다. 우측 상단
/// 버튼으로 [BattlePassScreen]에 바로 진입할 수 있다.
class QuestScreen extends StatelessWidget {
  const QuestScreen({super.key});

  Future<void> _claim(BuildContext context, QuestDisplayItem item) async {
    final bool success = await QuestManager.instance.claimQuest(item.quest.id);
    if (!context.mounted || !success) {
      return;
    }
    showCenterToast(context, '배틀패스 경험치 +${item.quest.rewardBp} BP 획득!');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([QuestManager.instance, BattlePassManager.instance]),
      builder: (context, _) {
        final List<QuestDisplayItem> items = QuestManager.instance.questsWithProgress;
        final BattlePassManager battlePass = BattlePassManager.instance;

        return Scaffold(
          backgroundColor: const Color(0xFF14141C),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1B1B26),
            elevation: 0,
            // 뒤로 가기 버튼처럼 별도 색을 안 준 아이콘이 어두운 배경에
            // 묻히지 않도록 명시한다.
            foregroundColor: Colors.white,
            title: const Text(
              '일일 퀘스트',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
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
                child: items.isEmpty
                    ? const Center(
                        child: Text(
                          '오늘의 퀘스트를 불러오는 중이에요.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final QuestDisplayItem item = items[index];
                          return _QuestTile(item: item, onClaim: () => _claim(context, item));
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
                  item.quest.title,
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
                  '${item.progress.currentCount} / ${item.quest.targetCount} · 보상 ${item.quest.rewardBp} BP',
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
              onPressed: item.isClaimable ? onClaim : null,
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
