import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/idle_game.dart';
import '../managers/dungeon_manager.dart';
import '../managers/skill_manager.dart';
import '../managers/sound_manager.dart';
import '../managers/tower_floor_manager.dart';
import '../managers/weekday_dungeon_manager.dart';
import '../managers/world_boss_manager.dart';
import '../models/active_skill_model.dart';
import '../models/consumable_item_model.dart';
import '../models/equipment.dart';
import '../models/tower_floor_model.dart';
import '../models/weekday_dungeon_model.dart';
import 'arena_screen.dart';
import 'home_screen.dart' show SkillEffectOverlay, SkillTreeQuickBar;
import 'top_bar.dart';
import 'world_boss_entry_dialog.dart';
import 'world_boss_ranking_dialog.dart';

class DungeonScreen extends StatefulWidget {
  const DungeonScreen({super.key});

  @override
  State<DungeonScreen> createState() => _DungeonScreenState();
}

class _DungeonScreenState extends State<DungeonScreen> {
  @override
  void initState() {
    super.initState();
    // 요구사항: "탑 메인 화면 진입 시 tower_floors 데이터를 불러와
    // 캐싱해줘" — main()이 앱 시작 시 이미 한 번 불러오지만, 이 화면(=탑
    // 입장 지점)에 들어올 때마다 다시 한번 최신화해서 운영자가 새로 층을
    // 추가해도 앱을 재시작하지 않아도 곧바로 반영되게 한다. 실패해도
    // 조용히 넘어간다(기존 캐시를 계속 쓰면 되므로) — TowerFloorManager
    // .loadData() 내부에서 이미 실패를 로그로 남기고 삼킨다.
    TowerFloorManager.instance.loadData();
  }

  Future<void> _enterDungeon(
    BuildContext context,
    GameMode mode, {
    bool isSweepMode = false,
  }) async {
    final DungeonManager dungeonManager = DungeonManager.instance;

    final DungeonType? ticketType = switch (mode) {
      GameMode.goldDungeon => DungeonType.goldDungeon,
      GameMode.equipDungeon => DungeonType.equipmentDungeon,
      GameMode.petDungeon => DungeonType.petDungeon,
      GameMode.towerOfInfinity ||
      GameMode.mainStage ||
      GameMode.worldBoss ||
      GameMode.guildDungeon ||
      GameMode.guildVictorySanctuary ||
      GameMode.weekdayDungeon ||
      GameMode.guildRaid ||
      GameMode.guildWar => null,
    };

    if (ticketType != null) {
      final bool hasTicket = await dungeonManager.consumeTicket(ticketType);
      if (!context.mounted) {
        return;
      }
      if (!hasTicket) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('입장 티켓이 부족합니다')));
        return;
      }
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            _DungeonBattleScreen(mode: mode, isSweepMode: isSweepMode),
      ),
    );
  }

  /// 요일 던전 전용 입장 진입점 — 무료 입장이 남아있으면 그것부터 쓰고,
  /// 다 썼으면 보석 [WeekdayDungeonManager.extraEntryCostGems]개를 소모할지
  /// 확인 팝업을 띄운다.
  Future<void> _enterWeekdayDungeon(BuildContext context) async {
    final WeekdayDungeonManager manager = WeekdayDungeonManager.instance;

    if (manager.canEnterFree) {
      final bool consumed = await manager.consumeFreeEntry();
      if (!context.mounted || !consumed) {
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => const _DungeonBattleScreen(mode: GameMode.weekdayDungeon),
        ),
      );
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('추가 입장', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          '오늘의 무료 입장을 모두 사용했습니다.\n'
          '보석 ${WeekdayDungeonManager.extraEntryCostGems}개를 소모해 추가로 입장할까요?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
              foregroundColor: Colors.black87,
            ),
            child: const Text('입장하기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    final bool consumed = await manager.consumeEntryWithGems();
    if (!context.mounted) {
      return;
    }
    if (!consumed) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('보석이 부족합니다')));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const _DungeonBattleScreen(mode: GameMode.weekdayDungeon),
      ),
    );
  }

  void _showTowerEntryDialog(BuildContext context) {
    final DungeonManager dungeonManager = DungeonManager.instance;
    final int currentFloor = dungeonManager.currentFloor;
    // 예전엔 여기서 sweepGoldRewardForFloor()/firstClearGemRewardForFloor()
    // 하드코딩 공식을 불렀다 — 이제 tower_floors 테이블 값을 그대로 읽는다.
    final TowerFloor? currentFloorData = TowerFloorManager.instance.floorData(currentFloor);

    // 요구사항: 도전할 층수의 데이터가 DB에 아직 없으면(예: 100층까지만
    // 등록됐는데 101층에 도전) 입장 팝업 자체를 열지 않고 안내만 띄운다 —
    // _activateDungeon의 hp=0 폴백까지 가지 않도록 진입 지점에서 막는다.
    if (currentFloorData == null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('더 높은 층이 곧 업데이트될 예정입니다!')));
      return;
    }

    final TowerFloor? sweepFloorData =
        currentFloor > 1 ? TowerFloorManager.instance.floorData(currentFloor - 1) : null;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (currentFloor > 1) ...[
                _TowerEntryBanner(
                  title:
                      '${currentFloor - 1}층 반복 도전 (남은 횟수: '
                      '${dungeonManager.dailyTowerSweepCount}/${DungeonManager.maxDailyTowerSweeps})',
                  floorData: sweepFloorData,
                  accentColor: Colors.amber,
                  enabled: dungeonManager.dailyTowerSweepCount > 0,
                  onTap: () async {
                    final bool consumed = await dungeonManager
                        .consumeTowerSweep();
                    if (!consumed || !dialogContext.mounted) {
                      return;
                    }
                    Navigator.of(dialogContext).pop();
                    _enterDungeon(
                      context,
                      GameMode.towerOfInfinity,
                      isSweepMode: true,
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
              _TowerEntryBanner(
                title: '$currentFloor층 최초 돌파',
                floorData: currentFloorData,
                accentColor: Colors.cyanAccent,
                enabled: true,
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  _enterDungeon(context, GameMode.towerOfInfinity);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final DungeonManager dungeonManager = DungeonManager.instance;
    final WeekdayDungeonManager weekdayDungeonManager = WeekdayDungeonManager.instance;

    return AnimatedBuilder(
      animation: Listenable.merge([dungeonManager, weekdayDungeonManager]),
      builder: (context, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF14141C),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1B1B26),
            elevation: 0,
            // 뒤로 가기 버튼처럼 별도 색을 안 준 아이콘이 어두운 배경에
            // 묻히지 않도록 명시한다.
            foregroundColor: Colors.white,
            title: const Text(
              '던전',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            centerTitle: true,
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _WorldBossBanner(),
              const SizedBox(height: 16),
              _DungeonCard(
                title: weekdayDungeonManager.todayConfig.name,
                description:
                    '오늘의 요일 던전 — 클리어 파도만큼 ${weekdayDungeonManager.todayConfig.rewardType.resourceLabel} 획득! '
                    '(60초 제한, 5파도마다 보스)',
                icon: weekdayDungeonManager.todayConfig.rewardType.icon,
                accentColor: weekdayDungeonManager.todayConfig.rewardType.color,
                buttonLabel: weekdayDungeonManager.canEnterFree
                    ? '입장 (${weekdayDungeonManager.remainingFreeEntries}/${WeekdayDungeonManager.maxDailyFreeEntries})'
                    : '보석으로 입장',
                enabled: true,
                onTap: () => _enterWeekdayDungeon(context),
              ),
              const SizedBox(height: 16),
              _DungeonCard(
                title: '결투장 (Arena)',
                description: '다른 유저와 비동기 1:1 대결! 승리하면 점수와 랭킹 보상.',
                icon: Icons.sports_martial_arts,
                accentColor: Colors.redAccent,
                buttonLabel: '입장하기',
                enabled: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ArenaScreen()),
                ),
              ),
              const SizedBox(height: 16),
              _DungeonCard(
                title: '골드 던전',
                description: '60초 동안 대량의 골드 획득!',
                icon: Icons.monetization_on,
                accentColor: Colors.amber,
                buttonLabel:
                    '입장 (${dungeonManager.goldDungeonTickets}/${DungeonManager.maxDailyTickets})',
                enabled: dungeonManager.goldDungeonTickets > 0,
                onTap: () => _enterDungeon(context, GameMode.goldDungeon),
              ),
              const SizedBox(height: 16),
              _DungeonCard(
                title: '장비 던전',
                description: '강력한 보스 처치 시 고등급 장비 확정 드롭!',
                icon: Icons.shield_moon,
                accentColor: Colors.purpleAccent,
                buttonLabel:
                    '입장 (${dungeonManager.equipmentDungeonTickets}/${DungeonManager.maxDailyTickets})',
                enabled: dungeonManager.equipmentDungeonTickets > 0,
                onTap: () => _enterDungeon(context, GameMode.equipDungeon),
              ),
              const SizedBox(height: 16),
              _DungeonCard(
                title: '펫 산책로',
                description: '클리어 시 펫 제작에 필요한 발바닥 획득!',
                icon: Icons.pets,
                accentColor: const Color(0xFFFF9F5A),
                buttonLabel:
                    '입장 (${dungeonManager.petDungeonTickets}/${DungeonManager.maxDailyTickets})',
                enabled: dungeonManager.petDungeonTickets > 0,
                onTap: () => _enterDungeon(context, GameMode.petDungeon),
              ),
              const SizedBox(height: 16),
              _DungeonCard(
                title: '무한의 탑',
                description:
                    '현재 ${dungeonManager.currentFloor}층 도전 중! (클리어 보상: 보석/골드/아이템)',
                icon: Icons.stairs,
                accentColor: Colors.cyanAccent,
                buttonLabel: '도전하기',
                enabled: true,
                onTap: () => _showTowerEntryDialog(context),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 예전엔 `icon`/`rewardText` 문자열 하나만 받아서 재화 하나(소탕=골드,
/// 최초 돌파=보석)만 보여줬다 — 이제 tower_floors 행([TowerFloor])을
/// 그대로 받아서 몬스터 HP/ATK 미리보기와 보상 전부(보석/골드/아이템)를
/// 보여준다(요구사항: "몬스터 HP, ATK를 그대로 렌더링"). 고정 height를
/// 없애고 패딩만으로 크기를 잡아서, 내용이 늘어나도(아이템 보상이 있는
/// 층 등) 오버플로우 없이 자연스럽게 늘어난다.
class _TowerEntryBanner extends StatelessWidget {
  const _TowerEntryBanner({
    required this.title,
    required this.floorData,
    required this.accentColor,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final TowerFloor? floorData;
  final Color accentColor;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TowerFloor? data = floorData;

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF20202C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: enabled ? accentColor : const Color(0xFF3A3A4A),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                color: enabled ? Colors.white : Colors.white38,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            if (data == null)
              const Text(
                '이 층 데이터를 아직 불러오지 못했습니다.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              )
            else ...[
              Text(
                '몬스터 HP ${data.monsterHp.toStringAsFixed(0)} · ATK ${data.monsterAttack.toStringAsFixed(0)}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  if (data.rewardGem > 0)
                    _RewardChip(
                      icon: Icons.diamond,
                      text: '${data.rewardGem}',
                      color: enabled ? Colors.cyanAccent : Colors.white24,
                    ),
                  if (data.rewardGold > 0)
                    _RewardChip(
                      icon: Icons.monetization_on,
                      text: '${data.rewardGold}',
                      color: enabled ? Colors.amber : Colors.white24,
                    ),
                  // ConsumableType으로 정확히 풀리면 그 아이콘/표시명을,
                  // 'equipment'면 장비 아이콘을, 그 어느 쪽도 아니면(예:
                  // "장비 강화 가루"처럼 enum과 안 맞는 자유 텍스트) 일반
                  // 선물 아이콘 + 원본 텍스트를 그대로 보여준다.
                  if (data.resolvedConsumableType != null)
                    _RewardChip(
                      icon: data.resolvedConsumableType!.icon,
                      text: data.resolvedConsumableType!.displayName,
                      color: enabled ? accentColor : Colors.white24,
                    )
                  else if (data.rewardItemKind == TowerRewardItemKind.equipment)
                    _RewardChip(
                      icon: Icons.shield,
                      text: data.rewardItemName ?? '장비',
                      color: enabled ? accentColor : Colors.white24,
                    )
                  else if (data.hasReward)
                    _RewardChip(
                      icon: Icons.card_giftcard,
                      text: data.rewardItemName!,
                      color: enabled ? accentColor : Colors.white24,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RewardChip extends StatelessWidget {
  const _RewardChip({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ],
    );
  }
}

/// 던전 리스트 최상단의 화려한 월드보스 배너 — 등장중/대기중 여부에 따라
/// 배경 그라데이션과 타이머 색이 바뀐다. [WorldBossManager]가 1초마다
/// 스스로 notifyListeners()를 부르므로 이 위젯은 [AnimatedBuilder]
/// 구독만으로 실시간 갱신된다(별도 폴링 타이머 불필요).
class _WorldBossBanner extends StatelessWidget {
  const _WorldBossBanner();

  String _formatCountdown(Duration duration) {
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);
    final String mm = minutes.toString().padLeft(2, '0');
    final String ss = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$mm:$ss';
    }
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: WorldBossManager.instance,
      builder: (context, _) {
        final WorldBossManager manager = WorldBossManager.instance;
        final List<Color> gradient = manager.isActive
            ? const [Color(0xFF7A0F0F), Color(0xFF2A0505)]
            : const [Color(0xFF2C2440), Color(0xFF1B1B26)];

        return Stack(
          children: [
            InkWell(
              onTap: () => showWorldBossEntryDialog(context),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                // 예전엔 height: 110 고정값을 줬는데, 폰트 렌더링/기기별
                // 미세한 줄 높이 차이로 안쪽 Column이 그 안에 딱 맞지 않고
                // 0.2px 단위로 넘쳐서 "RenderFlex overflowed" 경고가 났다.
                // 고정 높이를 없애고 패딩만으로 크기를 잡으면, 폰트 크기나
                // 텍스트 접근성 배율이 달라져도 항상 내용에 맞게 늘어나서
                // 구조적으로 오버플로우가 날 수 없다.
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: gradient),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: manager.isActive ? Colors.redAccent : const Color(0xFF6C4FCE),
                    width: 1.6,
                  ),
                ),
                child: Row(
                  children: [
                    const Text('🐉', style: TextStyle(fontSize: 48)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        // Container에 더 이상 고정 height가 없으니, Column도
                        // 남는 공간을 채우려 들지 않고(mainAxisSize.max로
                        // 두면 부모가 준 느슨한 제약 안에서 계속 늘어나려
                        // 하다가 다시 오버플로우 여지를 만든다) 딱 내용
                        // 높이만큼만 차지하게 한다.
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '월드보스: 용의 동굴',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            manager.isActive ? '보스 등장 중! 남은 시간' : '다음 등장까지',
                            style: TextStyle(
                              color: manager.isActive ? Colors.redAccent : Colors.white54,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _formatCountdown(manager.timeRemaining),
                            style: TextStyle(
                              color: manager.isActive ? Colors.redAccent : Colors.white70,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: manager.isActive ? Colors.redAccent : Colors.white38,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: _RankingTrophyButton(onTap: () => showWorldBossRankingDialog(context)),
            ),
          ],
        );
      },
    );
  }
}

/// 배너 우측 상단에 얹는 랭킹 진입 버튼 — 배너 전체를 덮는 InkWell(입장
/// 팝업)과 겹쳐도, Stack에서 더 위에 그려지는 이 InkWell이 그 지점의 탭을
/// 먼저 가로채므로 입장 팝업이 함께 뜨는 일은 없다.
class _RankingTrophyButton extends StatelessWidget {
  const _RankingTrophyButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.black45,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.amberAccent, width: 1.2),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.emoji_events, color: Colors.amberAccent, size: 18),
      ),
    );
  }
}

class _DungeonCard extends StatelessWidget {
  const _DungeonCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.accentColor,
    required this.buttonLabel,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color accentColor;
  final String buttonLabel;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF20202C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A4A), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accentColor, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: enabled ? onTap : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.black,
              disabledBackgroundColor: const Color(0xFF3A3A4A),
            ),
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}

class _DungeonBattleScreen extends StatefulWidget {
  const _DungeonBattleScreen({required this.mode, this.isSweepMode = false});

  final GameMode mode;
  final bool isSweepMode;

  @override
  State<_DungeonBattleScreen> createState() => _DungeonBattleScreenState();
}

class _DungeonBattleScreenState extends State<_DungeonBattleScreen> {
  late final IdleGame _game;
  late final Timer _ticker;
  bool _resultShown = false;

  // Whatever the skill damage target was before this screen (normally the
  // home screen's IdleGame) — restored on dispose so leaving the dungeon
  // doesn't leave skills pointed at a disposed dungeon monster.
  void Function(double damage)? _previousDamageHandler;

  // 광역기(active_aoe) 낙하 이펙트/데미지도 damageHandler와 같은 이유로
  // 저장해뒀다가 복원한다 — 안 그러면 던전을 나간 뒤 홈 화면에서 광역기를
  // 써도 이미 dispose된 던전 IdleGame의 콜백이 계속 남아 있어 아무 효과가
  // 없다.
  void Function(ActiveSkill skill, double damage)? _previousActiveSkillCast;

  @override
  void initState() {
    super.initState();
    _game = IdleGame();
    _game.onDungeonComplete = _handleDungeonComplete;
    _game.startDungeon(widget.mode, isSweepMode: widget.isSweepMode);
    _ticker = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => setState(() {}),
    );

    _previousDamageHandler = SkillManager.instance.damageHandler;
    SkillManager.instance.damageHandler = _game.applySkillDamage;
    _previousActiveSkillCast = SkillManager.instance.onActiveSkillCast;
    SkillManager.instance.onActiveSkillCast = _game.castActiveSkill;
    unawaited(SoundManager.instance.playDungeonBgm());
  }

  @override
  void dispose() {
    _ticker.cancel();
    if (identical(
      SkillManager.instance.damageHandler,
      _game.applySkillDamage,
    )) {
      SkillManager.instance.damageHandler = _previousDamageHandler;
    }
    if (identical(
      SkillManager.instance.onActiveSkillCast,
      _game.castActiveSkill,
    )) {
      SkillManager.instance.onActiveSkillCast = _previousActiveSkillCast;
    }
    // 이 화면 전용 IdleGame 인스턴스는 매번 새로 만들고 여기서 버린다 —
    // EquipmentManager 리스너를 해제하지 않으면 던전에 들어갔다 나올
    // 때마다 계속 쌓인다.
    _game.detachListeners();
    unawaited(SoundManager.instance.playLobbyBgm());
    super.dispose();
  }

  void _handleDungeonComplete({
    required bool success,
    required int goldReward,
    int gemReward = 0,
    Equipment? itemReward,
    int pawprintReward = 0,
    int guildCoinReward = 0,
    String? consumableItemReward,
  }) {
    if (_resultShown || !mounted) {
      return;
    }
    _resultShown = true;

    // advanceFloor()가 이미 실행된 뒤라, 방금 클리어한 층은 현재 층수 - 1.
    final int clearedFloor = DungeonManager.instance.currentFloor - 1;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1B1B26),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            success ? '클리어 성공!' : '클리어 실패',
            style: TextStyle(
              color: success ? Colors.greenAccent : Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: ConstrainedBox(
            // item_detail_dialog.dart와 같은 관례 — 보상 종류가 여러 개
            //동시에(예: 탑 층 클리어의 보석+골드+아이템) 뜨거나 접근성
            // 글자 크기가 커진 상태에서 이 Column이 다이얼로그 높이를
            // 넘어서도(RenderFlex overflow 대신) 안전하게 스크롤되게 한다.
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (gemReward > 0)
                Text(
                  '무한의 탑 $clearedFloor층 클리어! 보석 $gemReward개를 획득했습니다.',
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              if (goldReward > 0)
                Text(
                  '획득 골드: $goldReward G',
                  style: const TextStyle(color: Colors.white70),
                ),
              if (itemReward != null)
                Text(
                  '획득 장비: ${itemReward.name}',
                  style: TextStyle(
                    color: getGradeColor(itemReward.grade),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              if (pawprintReward > 0)
                Text(
                  '펫 산책로 클리어! 발바닥 $pawprintReward개를 획득했습니다.',
                  style: const TextStyle(
                    color: Color(0xFFFF9F5A),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              if (guildCoinReward > 0)
                Text(
                  '길드 던전 클리어! 길드 주화 $guildCoinReward개를 획득했습니다.',
                  style: const TextStyle(
                    color: Color(0xFF6C4FCE),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              if (consumableItemReward != null)
                Text(
                  '획득 아이템: $consumableItemReward',
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              if (goldReward <= 0 &&
                  gemReward <= 0 &&
                  itemReward == null &&
                  pawprintReward <= 0 &&
                  guildCoinReward <= 0 &&
                  consumableItemReward == null)
                const Text(
                  '보상이 없습니다. 다시 도전해보세요!',
                  style: TextStyle(color: Colors.white70),
                ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pop();
              },
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }

  String get _title {
    switch (widget.mode) {
      case GameMode.goldDungeon:
        return '골드 던전';
      case GameMode.equipDungeon:
        return '장비 던전';
      case GameMode.petDungeon:
        return '펫 산책로';
      case GameMode.towerOfInfinity:
        final int floor = widget.isSweepMode
            ? DungeonManager.instance.currentFloor - 1
            : DungeonManager.instance.currentFloor;
        return '무한의 탑 $floor층${widget.isSweepMode ? ' (반복)' : ''}';
      case GameMode.worldBoss:
        // 이 private 위젯은 실제로 worldBoss 모드로 인스턴스화되지 않는다
        // (전용 WorldBossBattleScreen이 따로 있다) — switch 소진성 때문에
        // 채워두는 값이다.
        return '월드보스: 용의 동굴';
      case GameMode.guildDungeon:
        // worldBoss와 같은 이유 — 전용 GuildDungeonScreen이 따로 있어
        // 실제로 이 값이 쓰이지 않는다.
        return '길드 던전';
      case GameMode.guildVictorySanctuary:
        // worldBoss와 같은 이유 — 전용 GuildDungeonScreen이 따로 있어
        // 실제로 이 값이 쓰이지 않는다.
        return '승리자의 성소';
      case GameMode.guildRaid:
        // worldBoss와 같은 이유 — 전용 GuildRaidScreen이 따로 있어
        // 실제로 이 값이 쓰이지 않는다.
        return '길드 레이드';
      case GameMode.guildWar:
        // worldBoss와 같은 이유 — 전용 GuildWarScreen이 따로 있어
        // 실제로 이 값이 쓰이지 않는다.
        return '길드 전쟁';
      case GameMode.weekdayDungeon:
        return WeekdayDungeonManager.instance.todayConfig.name;
      case GameMode.mainStage:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool timed =
        widget.mode == GameMode.goldDungeon ||
        widget.mode == GameMode.equipDungeon ||
        widget.mode == GameMode.petDungeon ||
        widget.mode == GameMode.weekdayDungeon ||
        // 무한의 탑도 이제 45초 타임어택이라(_towerDungeonDuration) 남은
        // 시간 HUD를 보여준다 — 예전엔 무제한(-1)이라 이 목록에 없었다.
        widget.mode == GameMode.towerOfInfinity;
    final double hpRatio = _game.dungeonMonsterMaxHp <= 0
        ? 0
        : (_game.dungeonMonsterHp / _game.dungeonMonsterMaxHp).clamp(0.0, 1.0);

    return PopScope(
      canPop: _resultShown,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F17),
        body: SafeArea(
          child: Column(
            children: [
              const TopBar(),
              SizedBox(
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: Text(
                        _title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                        ),
                      ),
                    ),
                    // 전투 결과가 나오기 전에는 뒤로가기로 이탈할 수 없도록 비활성화.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        icon: Icon(
                          Icons.arrow_back,
                          color: _resultShown ? Colors.white : Colors.white24,
                        ),
                        onPressed: _resultShown
                            ? () => Navigator.pop(context)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: GameWidget(game: _game)),
                    const Positioned.fill(child: SkillEffectOverlay()),
                    if (timed)
                      Positioned(
                        top: 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '남은 시간 ${_game.dungeonTimeRemaining.clamp(0, 999).toStringAsFixed(1)}s',
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    const Positioned(
                      bottom: 90,
                      left: 0,
                      right: 0,
                      child: SkillTreeQuickBar(),
                    ),
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: hpRatio,
                              minHeight: 14,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation(
                                Colors.redAccent,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_game.dungeonMonsterHp.clamp(0, _game.dungeonMonsterMaxHp).toStringAsFixed(0)} / '
                            '${_game.dungeonMonsterMaxHp.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
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
