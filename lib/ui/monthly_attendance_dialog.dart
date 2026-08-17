import 'package:flutter/material.dart';

import '../managers/monthly_attendance_manager.dart';
import '../models/consumable_item_model.dart';
import '../widgets/coin_fly_animation.dart';

/// Manual-claim monthly attendance calendar body — embedded as a tab inside
/// MissionDialog. No auto-popup reward — every day cell and every milestone
/// chest must be tapped explicitly.
class MonthlyAttendanceView extends StatefulWidget {
  const MonthlyAttendanceView({super.key});

  @override
  State<MonthlyAttendanceView> createState() => _MonthlyAttendanceViewState();
}

class _MonthlyAttendanceViewState extends State<MonthlyAttendanceView> {
  final MonthlyAttendanceManager _manager = MonthlyAttendanceManager.instance;

  @override
  void initState() {
    super.initState();
    _manager.refreshToday();
  }

  Future<void> _claimDay(int day) async {
    await _manager.claimDay(day);
  }

  Future<void> _claimBox(int milestone) async {
    final bool success = await _manager.claimBox(milestone);
    if (!success || !mounted) {
      return;
    }

    final ConsumableType boxType = _manager.boxTypeForMilestone(milestone);
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1B1B26),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: boxType.boxColor),
          ),
          title: Text(
            '🎁 ${boxType.displayName}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            '${boxType.displayName} 지급 완료되었습니다',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _manager,
      builder: (context, _) {
        final int totalDays = _manager.daysInCurrentMonth;
        final double progress = (_manager.attendanceCount /
                MonthlyAttendanceManager.boxMilestones.last)
            .clamp(0.0, 1.0);

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                '누적 출석 ${_manager.attendanceCount}일',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 10,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF6C4FCE)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: MonthlyAttendanceManager.boxMilestones
                    .map(
                      (m) => _BoxSlot(
                        milestone: m,
                        manager: _manager,
                        onTap: () => _claimBox(m),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.builder(
                  itemCount: totalDays,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                    childAspectRatio: 0.8,
                  ),
                  itemBuilder: (context, index) {
                    final int day = index + 1;
                    return _DayCell(
                      day: day,
                      manager: _manager,
                      onTap: () => _claimDay(day),
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

class _BoxSlot extends StatelessWidget {
  const _BoxSlot({
    required this.milestone,
    required this.manager,
    required this.onTap,
  });

  final int milestone;
  final MonthlyAttendanceManager manager;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ConsumableType boxType = manager.boxTypeForMilestone(milestone);
    final bool claimed = manager.isBoxClaimed(milestone);
    final bool claimable = manager.canClaimBox(milestone);
    final Color color = boxType.boxColor;

    return InkWell(
      onTap: claimable ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: claimed
                  ? const Color(0xFF20202C)
                  : color.withValues(alpha: claimable ? 0.25 : 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: claimed ? const Color(0xFF3A3A4A) : color,
                width: claimable ? 2 : 1,
              ),
            ),
            child: Icon(
              claimed ? Icons.check : Icons.card_giftcard,
              color: claimed ? Colors.white38 : color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$milestone일',
            style: TextStyle(
              color: claimable ? Colors.white : Colors.white38,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.manager,
    required this.onTap,
  });

  final int day;
  final MonthlyAttendanceManager manager;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final DateTime target = DateTime(now.year, now.month, day);
    final DailyRewardType type = manager.rewardTypeForWeekday(target.weekday);
    final bool claimed = manager.isDayClaimed(day);
    final bool isToday = day == now.day;
    final bool isPast = day < now.day;
    final bool claimable = manager.isDayClaimable(day);

    late final IconData rewardIcon;
    late final Color rewardColor;
    switch (type) {
      case DailyRewardType.coin:
        rewardIcon = Icons.monetization_on;
        rewardColor = Colors.amber;
      case DailyRewardType.dust:
        rewardIcon = Icons.grain;
        rewardColor = const Color(0xFFC9A24B);
      case DailyRewardType.gem:
        rewardIcon = Icons.diamond;
        rewardColor = Colors.cyanAccent;
    }

    // 4가지 상태: 출석 완료(녹색 체크) / 미출석 과거(회색 X) / 오늘(보상 아이콘 강조) / 미래(보상 아이콘).
    final Widget statusIcon;
    if (claimed) {
      statusIcon = const Icon(Icons.check_circle, color: Colors.greenAccent, size: 18);
    } else if (isPast) {
      statusIcon = const Icon(Icons.cancel, color: Colors.white38, size: 18);
    } else if (isToday) {
      statusIcon = _PulsingIcon(icon: rewardIcon, color: rewardColor);
    } else {
      statusIcon = Icon(rewardIcon, color: rewardColor, size: 16);
    }

    return InkWell(
      onTap: claimable
          ? () {
              if (type != DailyRewardType.dust) {
                showCoinFlyAnimation(
                  context,
                  startPosition: widgetGlobalCenter(context),
                  isGold: type == DailyRewardType.coin,
                );
              }
              onTap();
            }
          : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: claimed ? const Color(0xFF1B1B26) : const Color(0xFF20202C),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isToday && !claimed ? rewardColor : const Color(0xFF3A3A4A),
            width: isToday && !claimed ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            statusIcon,
            Text(
              '$day',
              style: TextStyle(
                color: isPast && !claimed ? Colors.white24 : Colors.white,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gentle pulse to draw the eye to today's claimable reward.
class _PulsingIcon extends StatefulWidget {
  const _PulsingIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.5, end: 1.0).animate(_controller),
      child: ScaleTransition(
        scale: Tween(begin: 0.9, end: 1.15).animate(_controller),
        child: Icon(widget.icon, color: widget.color, size: 18),
      ),
    );
  }
}
