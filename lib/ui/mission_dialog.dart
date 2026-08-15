import 'package:flutter/material.dart';

import '../managers/attendance_manager.dart';
import '../managers/mission_manager.dart';
import '../models/mission_model.dart';
import '../widgets/coin_fly_animation.dart';
import 'monthly_attendance_dialog.dart';

/// Tabbed quest popup — opened from the HUD icon on the home battle view.
/// Replaces the old bottom-tab MissionScreen.
class MissionDialog extends StatelessWidget {
  const MissionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF14141C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: SizedBox(
        width: double.maxFinite,
        height: 520,
        child: DefaultTabController(
          length: 5,
          child: Column(
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF1B1B26),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '퀘스트',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    const TabBar(
                      isScrollable: true,
                      indicatorColor: Color(0xFF6C4FCE),
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white54,
                      tabs: [
                        Tab(text: '로그인 보상'),
                        Tab(text: '월간 출석'),
                        Tab(text: '일일 퀘스트'),
                        Tab(text: '주간 퀘스트'),
                        Tab(text: '업적'),
                      ],
                    ),
                  ],
                ),
              ),
              const Expanded(
                child: TabBarView(
                  children: [
                    _AttendanceTab(),
                    MonthlyAttendanceView(),
                    _MissionListTab(missionType: MissionType.daily),
                    _MissionListTab(missionType: MissionType.weekly),
                    // No dedicated achievement model yet — the monthly
                    // mission pool doubles as the "업적" tab for now.
                    _MissionListTab(missionType: MissionType.monthly),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttendanceTab extends StatelessWidget {
  const _AttendanceTab();

  @override
  Widget build(BuildContext context) {
    final AttendanceManager manager = AttendanceManager.instance;

    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: AttendanceManager.totalDays,
          separatorBuilder: (context, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final int day = index + 1;
            return _AttendanceTile(
              day: day,
              reward: manager.rewardForDay(day),
              claimed: manager.isClaimed(day),
              claimable: manager.canClaim(day),
              locked: manager.isLocked(day),
              onClaim: () {
                manager.claimReward(day);
              },
            );
          },
        );
      },
    );
  }
}

class _AttendanceTile extends StatelessWidget {
  const _AttendanceTile({
    required this.day,
    required this.reward,
    required this.claimed,
    required this.claimable,
    required this.locked,
    required this.onClaim,
  });

  final int day;
  final ({RewardType type, int amount}) reward;
  final bool claimed;
  final bool claimable;
  final bool locked;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final Color rewardColor = reward.type == RewardType.gold ? Colors.amber : Colors.cyanAccent;
    final IconData rewardIcon = reward.type == RewardType.gold ? Icons.monetization_on : Icons.diamond;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF20202C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: claimable ? const Color(0xFF6C4FCE) : const Color(0xFF3A3A4A),
          width: claimable ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              '$day일차',
              style: TextStyle(
                color: locked ? Colors.white38 : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          Icon(rewardIcon, color: locked ? Colors.white24 : rewardColor, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${reward.amount}',
              style: TextStyle(
                color: locked ? Colors.white38 : Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (claimed)
            const Icon(Icons.check_circle, color: Colors.greenAccent, size: 26)
          else if (locked)
            const Icon(Icons.lock, color: Colors.white24, size: 22)
          else
            ElevatedButton(
              onPressed: claimable
                  ? () {
                      showCoinFlyAnimation(
                        context,
                        startPosition: widgetGlobalCenter(context),
                        isGold: reward.type == RewardType.gold,
                      );
                      onClaim();
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF3A3A4A),
              ),
              child: const Text('획득'),
            ),
        ],
      ),
    );
  }
}

class _MissionListTab extends StatelessWidget {
  const _MissionListTab({required this.missionType});

  final MissionType missionType;

  @override
  Widget build(BuildContext context) {
    final MissionManager manager = MissionManager.instance;

    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        final List<Mission> missions = manager.missionsOfType(missionType);
        if (missions.isEmpty) {
          return const Center(
            child: Text('불러온 미션이 없습니다', style: TextStyle(color: Colors.white54)),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: missions.length,
          separatorBuilder: (context, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            return _MissionCard(mission: missions[index], onClaim: manager.claimReward);
          },
        );
      },
    );
  }
}

class _MissionCard extends StatelessWidget {
  const _MissionCard({required this.mission, required this.onClaim});

  final Mission mission;
  final bool Function(String id) onClaim;

  @override
  Widget build(BuildContext context) {
    final double progress = mission.targetValue <= 0
        ? 0
        : (mission.currentValue / mission.targetValue).clamp(0.0, 1.0);

    return Card(
      color: const Color(0xFF20202C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFF3A3A4A)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mission.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mission.description,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation(
                        mission.isCleared ? Colors.greenAccent : const Color(0xFF6C4FCE),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${mission.currentValue}/${mission.targetValue}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  mission.rewardType == RewardType.gold ? Icons.monetization_on : Icons.diamond,
                  color: mission.rewardType == RewardType.gold ? Colors.amber : Colors.cyanAccent,
                  size: 20,
                ),
                const SizedBox(height: 2),
                Text(
                  '${mission.rewardAmount}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: mission.isCleared && !mission.isRewardClaimed
                      ? () {
                          showCoinFlyAnimation(
                            context,
                            startPosition: widgetGlobalCenter(context),
                            isGold: mission.rewardType == RewardType.gold,
                          );
                          onClaim(mission.id);
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C4FCE),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF3A3A4A),
                    disabledForegroundColor: Colors.white54,
                  ),
                  child: Text(mission.isRewardClaimed ? '수령 완료' : '보상 받기'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
