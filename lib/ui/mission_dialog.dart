import 'package:flutter/material.dart';

import '../managers/achievement_manager.dart';
import '../managers/attendance_manager.dart';
import '../managers/mission_manager.dart';
import '../managers/rookie_attendance_manager.dart';
import '../models/achievement_model.dart';
import '../models/mission_model.dart';
import '../models/rookie_attendance_model.dart';
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
          length: 6,
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
                        Tab(text: '신규출석'),
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
                    _RookieAttendanceTab(),
                    _AttendanceTab(),
                    MonthlyAttendanceView(),
                    _MissionListTab(missionType: MissionType.daily),
                    _MissionListTab(missionType: MissionType.weekly),
                    _AchievementTab(),
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

/// 신규 모험가 7일 출석부 — [_AttendanceTile]과 같은 리스트형 레이아웃을
/// 쓰되, 7일차(최고 등급 보상)만 화려한 글로우 테두리로 강조한다
/// (요구사항: "7일차 보상이 화려한 글로우 효과와 함께 강조").
class _RookieAttendanceTab extends StatelessWidget {
  const _RookieAttendanceTab();

  @override
  Widget build(BuildContext context) {
    final RookieAttendanceManager manager = RookieAttendanceManager.instance;

    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: RookieAttendanceManager.totalDays,
          separatorBuilder: (context, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final int day = index + 1;
            return _RookieAttendanceTile(
              day: day,
              reward: manager.rewardForDay(day),
              claimed: manager.isClaimed(day),
              claimable: manager.canClaim(day),
              locked: manager.isLocked(day),
              onClaim: () => manager.claimReward(day),
            );
          },
        );
      },
    );
  }
}

class _RookieAttendanceTile extends StatelessWidget {
  const _RookieAttendanceTile({
    required this.day,
    required this.reward,
    required this.claimed,
    required this.claimable,
    required this.locked,
    required this.onClaim,
  });

  final int day;
  final RookieAttendanceReward reward;
  final bool claimed;
  final bool claimable;
  final bool locked;
  final VoidCallback onClaim;

  bool get _isFinalDay => day == RookieAttendanceManager.totalDays;

  @override
  Widget build(BuildContext context) {
    final Color accent = _isFinalDay ? Colors.amberAccent : const Color(0xFF6C4FCE);

    return Container(
      decoration: _isFinalDay
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.amberAccent.withValues(alpha: 0.55),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            )
          : null,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: _isFinalDay
              ? LinearGradient(
                  colors: [accent.withValues(alpha: 0.28), const Color(0xFF20202C)],
                )
              : null,
          color: _isFinalDay ? null : const Color(0xFF20202C),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: claimable ? accent : const Color(0xFF3A3A4A),
            width: claimable ? (_isFinalDay ? 2 : 1.5) : 1,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                _isFinalDay ? '최종일' : '$day일차',
                style: TextStyle(
                  color: locked ? Colors.white38 : (_isFinalDay ? Colors.amberAccent : Colors.white),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            Icon(
              reward.displayIcon,
              color: locked ? Colors.white24 : accent,
              size: _isFinalDay ? 28 : 22,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                reward.displayLabel,
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
                          isGold: reward.kind == RookieRewardKind.gold,
                        );
                        onClaim();
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isFinalDay ? Colors.amberAccent : Colors.green,
                  foregroundColor: _isFinalDay ? Colors.black87 : Colors.white,
                  disabledBackgroundColor: const Color(0xFF3A3A4A),
                ),
                child: const Text('획득'),
              ),
          ],
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

/// 방치형 RPG 핵심 지표 3종(몬스터 누적 처치/최고 도달 챕터/누적 가챠
/// 횟수) 단계형 업적 탭 — [AchievementManager.tiers]의 모든 (카테고리,
/// 단계) 조합을 한 리스트로 펼쳐서 보여준다. 정렬 우선순위: 지금 바로
/// "보상 받기"가 가능한 업적(0) → 아직 진행 중인 업적(1) → 이미 수령
/// 완료한 업적(2) — 요구사항대로 수령 가능한 업적이 항상 최상단에 온다.
class _AchievementTab extends StatelessWidget {
  const _AchievementTab();

  static int _sortRank(AchievementManager manager, AchievementCategory category, int threshold) {
    if (manager.canClaimTier(category, threshold)) {
      return 0;
    }
    if (manager.isTierClaimed(category, threshold)) {
      return 2;
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AchievementManager.instance,
      builder: (context, _) {
        final AchievementManager manager = AchievementManager.instance;

        final List<({AchievementCategory category, AchievementTier tier})> entries = [
          for (final AchievementCategory category in AchievementCategory.values)
            for (final AchievementTier tier in AchievementManager.tiers[category] ?? const [])
              (category: category, tier: tier),
        ];
        entries.sort((a, b) {
          final int rankA = _sortRank(manager, a.category, a.tier.threshold);
          final int rankB = _sortRank(manager, b.category, b.tier.threshold);
          if (rankA != rankB) {
            return rankA.compareTo(rankB);
          }
          final int categoryCompare = a.category.index.compareTo(b.category.index);
          if (categoryCompare != 0) {
            return categoryCompare;
          }
          return a.tier.threshold.compareTo(b.tier.threshold);
        });

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: entries.length,
          separatorBuilder: (context, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final ({AchievementCategory category, AchievementTier tier}) entry = entries[index];
            return _AchievementCard(
              category: entry.category,
              tier: entry.tier,
              progress: manager.progressFor(entry.category),
              claimed: manager.isTierClaimed(entry.category, entry.tier.threshold),
              claimable: manager.canClaimTier(entry.category, entry.tier.threshold),
              onClaim: () => manager.claimTier(entry.category, entry.tier.threshold),
            );
          },
        );
      },
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

/// 업적 카드 — [_MissionCard]와 같은 레이아웃(진행도 바 + 보상 + 버튼)을
/// 쓰되, [claimable](지금 바로 수령 가능)일 때는 카드 테두리/버튼을
/// 골드색 글로우로 강조해서 유저가 놓치지 않고 계속 누르고 싶어지게
/// 만든다([gacha_reveal_screen.dart]의 최고 등급 카드 글로우와 같은 시각
/// 언어).
class _AchievementCard extends StatelessWidget {
  const _AchievementCard({
    required this.category,
    required this.tier,
    required this.progress,
    required this.claimed,
    required this.claimable,
    required this.onClaim,
  });

  final AchievementCategory category;
  final AchievementTier tier;
  final int progress;
  final bool claimed;
  final bool claimable;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final double ratio =
        tier.threshold <= 0 ? 0 : (progress / tier.threshold).clamp(0.0, 1.0);

    return Container(
      decoration: claimable
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.amberAccent.withValues(alpha: 0.4),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            )
          : null,
      child: Card(
        color: const Color(0xFF20202C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: claimable ? Colors.amberAccent : const Color(0xFF3A3A4A),
            width: claimable ? 1.5 : 1,
          ),
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
                      '${achievementCategoryLabel(category)} ${tier.threshold}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '누적 ${tier.threshold} 달성 시 보석을 받을 수 있어요.',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 8,
                        backgroundColor: Colors.white24,
                        valueColor: AlwaysStoppedAnimation(
                          claimed || claimable ? Colors.greenAccent : const Color(0xFF6C4FCE),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${progress.clamp(0, tier.threshold)}/${tier.threshold}',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.diamond, color: Colors.cyanAccent, size: 20),
                  const SizedBox(height: 2),
                  Text(
                    '${tier.gemReward}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: claimable
                        ? () {
                            showCoinFlyAnimation(
                              context,
                              startPosition: widgetGlobalCenter(context),
                              isGold: false,
                            );
                            onClaim();
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: claimable ? Colors.amberAccent : const Color(0xFF6C4FCE),
                      foregroundColor: claimable ? Colors.black : Colors.white,
                      disabledBackgroundColor: const Color(0xFF3A3A4A),
                      disabledForegroundColor: Colors.white54,
                      elevation: claimable ? 6 : 0,
                    ),
                    child: Text(claimed ? '수령 완료' : '보상 받기'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
