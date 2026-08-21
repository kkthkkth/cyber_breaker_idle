import 'package:flutter/material.dart';

import '../managers/weekday_dungeon_manager.dart';
import '../models/weekday_dungeon_model.dart';
import 'dungeon_screen.dart' show enterWeekdayDungeon;

/// [DateTime.weekday](1=월 ~ 7=일) 순서 그대로의 한글 요일 이름 —
/// [_DailyDungeonTile]이 각 던전 카드에 "월요일" 같은 라벨을 붙일 때 쓴다.
const List<String> _weekdayNames = [
  '월요일',
  '화요일',
  '수요일',
  '목요일',
  '금요일',
  '토요일',
  '일요일',
];

/// "요일 던전" 진입 카드(dungeon_screen.dart)를 누르면 여기로 온다 — 월~일
/// 7개 던전을 전부 리스트로 보여주되, 오늘 요일에 해당하는 던전만 색이
/// 입혀진 채 입장 가능하고 나머지는 자물쇠 아이콘과 함께 흑백으로 잠겨
/// 있다(요구사항: "오늘 요일에 해당하는 던전만 활성화... 나머지는 자물쇠
/// 아이콘과 함께 흑백 처리"). 실제 던전 종류/보상/입장 횟수 관리는 전부
/// 기존 [WeekdayDungeonManager]를 그대로 재사용한다 — 이 화면은 오직
/// "7개를 한눈에 보여주는" 새 UI 레이어일 뿐, 새 매니저나 새 DB 테이블을
/// 두지 않는다.
class DailyDungeonScreen extends StatelessWidget {
  const DailyDungeonScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: WeekdayDungeonManager.instance,
      builder: (context, _) {
        final WeekdayDungeonManager manager = WeekdayDungeonManager.instance;
        final int todayWeekday = manager.todayConfig.weekday;

        return Scaffold(
          backgroundColor: const Color(0xFF14141C),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1B1B26),
            elevation: 0,
            foregroundColor: Colors.white,
            title: const Text(
              '요일 던전',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            centerTitle: true,
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF20202C),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFF3A3A4A),
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '오늘 남은 입장 횟수: ${manager.remainingFreeEntries} / ${WeekdayDungeonManager.maxDailyFreeEntries}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (!manager.canEnterFree) ...[
                        const SizedBox(height: 4),
                        Text(
                          '무료 입장을 모두 사용했어요. 보석 ${WeekdayDungeonManager.extraEntryCostGems}개로 추가 입장할 수 있어요.',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: WeekdayDungeonSchedule.all.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final WeekdayDungeonConfig config =
                        WeekdayDungeonSchedule.all[index];
                    final bool isToday = config.weekday == todayWeekday;
                    return _DailyDungeonTile(
                      config: config,
                      isToday: isToday,
                      remainingFreeEntries: manager.remainingFreeEntries,
                      onTap: isToday
                          ? () => enterWeekdayDungeon(context)
                          : null,
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

class _DailyDungeonTile extends StatelessWidget {
  const _DailyDungeonTile({
    required this.config,
    required this.isToday,
    required this.remainingFreeEntries,
    required this.onTap,
  });

  final WeekdayDungeonConfig config;
  final bool isToday;
  final int remainingFreeEntries;

  /// 오늘 요일이 아니면 null — [InkWell]이 자동으로 탭을 비활성화한다.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // [DateTime.weekday]는 1(월)부터 시작하므로 배열 인덱스는 -1.
    final String weekdayLabel = _weekdayNames[config.weekday - 1];
    final Color accent = isToday
        ? config.rewardType.color
        : const Color(0xFF4A4A5A);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF20202C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isToday ? accent : const Color(0xFF3A3A4A),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isToday ? 0.15 : 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                config.rewardType.icon,
                color: isToday ? accent : Colors.white24,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    weekdayLabel,
                    style: TextStyle(
                      color: isToday ? accent : Colors.white38,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    config.name,
                    style: TextStyle(
                      color: isToday ? Colors.white : Colors.white38,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '보상: ${config.rewardType.resourceLabel}',
                    style: TextStyle(
                      color: isToday ? Colors.white54 : Colors.white24,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (isToday)
              ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.black,
                ),
                child: Text(
                  '입장 ($remainingFreeEntries/${WeekdayDungeonManager.maxDailyFreeEntries})',
                ),
              )
            else
              const Icon(Icons.lock, color: Colors.white24, size: 22),
          ],
        ),
      ),
    );
  }
}
