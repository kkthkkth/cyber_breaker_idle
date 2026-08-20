import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/idle_game.dart';
import '../managers/rift_manager.dart';
import '../managers/skill_manager.dart';
import '../models/active_skill_model.dart';
import '../models/dungeon_reward_config_model.dart';
import '../models/rift_model.dart';
import '../widgets/center_toast.dart';
import 'home_screen.dart' show SkillEffectOverlay, SkillTreeQuickBar;
import 'top_bar.dart';

/// 던전 탭의 [입장하기]를 누르면 여기로 온다 — 하루 한 번의 무료 입장권을
/// 확인하고, 탐험이 진행 중이면([RiftManager.isActive]) 현재 층과 3장의
/// 갈림길 카드([RiftManager.currentCards])를, 아니면 시작 버튼을 보여준다.
/// 전투 카드를 고르면 [RiftBattleScreen](메인 방치형 전투 화면과 같은
/// [IdleGame] + [GameWidget] 구조)으로 넘어가고, 휴식처 카드는 이 화면
/// 안에서 곧장 처리한다(요구사항: "휴식처(체력 회복)").
class RiftScreen extends StatelessWidget {
  const RiftScreen({super.key});

  Future<void> _start(BuildContext context) async {
    final bool started = await RiftManager.instance.startRun();
    if (!context.mounted || started) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('오늘의 무료 입장을 모두 사용했습니다.')));
  }

  void _selectBattleCard(BuildContext context, RiftCard card) {
    RiftManager.instance.beginBattle(card.type);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RiftBattleScreen(cardType: card.type)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: RiftManager.instance,
      builder: (context, _) {
        final RiftManager rift = RiftManager.instance;
        return Scaffold(
          backgroundColor: const Color(0xFF14141C),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1B1B26),
            elevation: 0,
            foregroundColor: Colors.white,
            title: const Text(
              '차원의 균열',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
          ),
          body: rift.isActive ? _RunView(rift: rift, onSelectBattle: _selectBattleCard) : _EntryView(
            rift: rift,
            onStart: () => _start(context),
          ),
        );
      },
    );
  }
}

class _EntryView extends StatelessWidget {
  const _EntryView({required this.rift, required this.onStart});

  final RiftManager rift;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🌀', style: TextStyle(fontSize: 72)),
            const SizedBox(height: 16),
            const Text(
              '차원의 균열',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
            ),
            const SizedBox(height: 10),
            Text(
              '균열 전용 스탯으로 처음부터 다시 시작하는 로그라이크 도전!\n'
              '갈림길에서 전투/휴식을 고르며 최대 ${RiftManager.maxFloor}층까지 오르세요.\n'
              '체력이 0이 되면 그 자리에서 탐험이 끝납니다.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: rift.hasFreeEntryToday ? onStart : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C4FCE),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF3A3A4A),
                disabledForegroundColor: Colors.white38,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(rift.hasFreeEntryToday ? '탐험 시작 (오늘 1회)' : '오늘의 입장을 모두 사용했습니다'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RunView extends StatelessWidget {
  const _RunView({required this.rift, required this.onSelectBattle});

  final RiftManager rift;
  final void Function(BuildContext context, RiftCard card) onSelectBattle;

  Future<void> _selectRest(BuildContext context) async {
    await RiftManager.instance.rest();
  }

  @override
  Widget build(BuildContext context) {
    final double hpRatio = rift.riftMaxHp <= 0 ? 0 : (rift.riftHp / rift.riftMaxHp).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            '${rift.floor} / ${RiftManager.maxFloor}층',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: hpRatio,
              minHeight: 14,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(Colors.redAccent),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${rift.riftHp.toStringAsFixed(0)} / ${rift.riftMaxHp.toStringAsFixed(0)}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (rift.equippedRelics.isNotEmpty) ...[
            const SizedBox(height: 12),
            RiftRelicBar(relics: rift.equippedRelics),
          ],
          const SizedBox(height: 24),
          const Text(
            '갈림길 — 카드를 하나 선택하세요',
            style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: rift.currentCards.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final RiftCard card = rift.currentCards[index];
                return _RiftCardTile(
                  card: card,
                  onTap: card.type == RiftCardType.rest
                      ? () => _selectRest(context)
                      : () => onSelectBattle(context, card),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RiftCardTile extends StatelessWidget {
  const _RiftCardTile({required this.card, required this.onTap});

  final RiftCard card;
  final VoidCallback onTap;

  Color get _accent => switch (card.type) {
    RiftCardType.normalBattle => const Color(0xFF4F8FE0),
    RiftCardType.eliteBattle => const Color(0xFFE05A9E),
    RiftCardType.rest => const Color(0xFF4FE0A0),
    RiftCardType.boss => const Color(0xFFFF4D4D),
  };

  IconData get _icon => switch (card.type) {
    RiftCardType.normalBattle => Icons.sports_kabaddi,
    RiftCardType.eliteBattle => Icons.warning_amber,
    RiftCardType.rest => Icons.self_improvement,
    RiftCardType.boss => Icons.dangerous,
  };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF20202C),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _accent, width: 1.4),
        ),
        child: Row(
          children: [
            Icon(_icon, color: _accent, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    card.description,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: _accent),
          ],
        ),
      ),
    );
  }
}

/// [RiftScreen]에서 전투 카드를 고르면 진입하는 실제 전투 화면 — 일반
/// 스테이지/다른 던전 전투 화면과 완전히 같은 [IdleGame] + [GameWidget]
/// 구조를 그대로 재사용한다(guild_dungeon_screen.dart의
/// [GuildDungeonScreen]과 동일한 뼈대). 균열 내부라는 걸 시각적으로
/// 드러내기 위해 배경을 더 어둡게 깔고 은은한 보라색 톤을 오버레이한다.
/// 다른 던전과 달리 몬스터 HP 바 아래에 [RiftManager.riftHp] 바도 함께
/// 보여준다 — 이 모드만 플레이어가 실제로 피해를 입기 때문이다.
class RiftBattleScreen extends StatefulWidget {
  const RiftBattleScreen({super.key, required this.cardType});

  final RiftCardType cardType;

  bool get isElite => cardType == RiftCardType.eliteBattle;
  bool get isBoss => cardType == RiftCardType.boss;

  @override
  State<RiftBattleScreen> createState() => _RiftBattleScreenState();
}

class _RiftBattleScreenState extends State<RiftBattleScreen> {
  late final IdleGame _game;
  late final Timer _ticker;
  bool _resultShown = false;

  void Function(double damage)? _previousDamageHandler;
  void Function(ActiveSkill skill, double damage)? _previousActiveSkillCast;

  @override
  void initState() {
    super.initState();
    _game = IdleGame();
    _game.onDungeonComplete = _handleBattleComplete;
    _game.startDungeon(GameMode.dimensionalRift);
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => setState(() {}));

    _previousDamageHandler = SkillManager.instance.damageHandler;
    SkillManager.instance.damageHandler = _game.applySkillDamage;
    _previousActiveSkillCast = SkillManager.instance.onActiveSkillCast;
    SkillManager.instance.onActiveSkillCast = _game.castActiveSkill;
  }

  @override
  void dispose() {
    _ticker.cancel();
    if (identical(SkillManager.instance.damageHandler, _game.applySkillDamage)) {
      SkillManager.instance.damageHandler = _previousDamageHandler;
    }
    if (identical(SkillManager.instance.onActiveSkillCast, _game.castActiveSkill)) {
      SkillManager.instance.onActiveSkillCast = _previousActiveSkillCast;
    }
    _game.detachListeners();
    super.dispose();
  }

  void _handleBattleComplete({
    required bool success,
    required int goldReward,
    int gemReward = 0,
    dynamic itemReward,
    int pawprintReward = 0,
    int guildCoinReward = 0,
    dynamic consumableItemReward,
  }) {
    if (_resultShown || !mounted) {
      return;
    }
    _resultShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveOutcome(success: success));
  }

  Future<void> _resolveOutcome({required bool success}) async {
    if (!mounted) {
      return;
    }
    if (!success) {
      await _showRunEndDialog(success: false);
      return;
    }
    if (RiftManager.instance.floor >= RiftManager.maxFloor) {
      // 마지막 층을 클리어했다 — 다음 층이 없으므로 유물 선택 없이 곧장
      // 탐험을 종료한다.
      await _showRunEndDialog(success: true);
      return;
    }
    await _showRelicDialog();
  }

  Future<void> _showRelicDialog() async {
    final List<RiftRelic> options = RiftManager.instance.offerRelics();
    if (!mounted) {
      return;
    }
    final RiftRelic? chosen = await showDialog<RiftRelic>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _RelicChoiceDialog(options: options),
    );
    if (chosen != null) {
      await RiftManager.instance.applyRelicChoice(chosen);
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _showRunEndDialog({required bool success}) async {
    final List<DungeonRewardGrant> grants = await RiftManager.instance.endRun();
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          success ? '균열 정복!' : '탐험 종료',
          style: TextStyle(
            color: success ? Colors.greenAccent : Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              success ? '${RiftManager.maxFloor}층까지 모두 돌파했습니다!' : '체력이 다해 탐험이 끝났습니다.',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 10),
            if (grants.isEmpty)
              const Text('획득한 보상이 없습니다.', style: TextStyle(color: Colors.white38))
            else
              Text(
                '획득: ${grants.map((grant) => grant.label).join(', ')}',
                style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double monsterHpRatio = _game.dungeonMonsterMaxHp <= 0
        ? 0
        : (_game.dungeonMonsterHp / _game.dungeonMonsterMaxHp).clamp(0.0, 1.0);
    final double riftHpRatio = RiftManager.instance.riftMaxHp <= 0
        ? 0
        : (RiftManager.instance.riftHp / RiftManager.instance.riftMaxHp).clamp(0.0, 1.0);

    return PopScope(
      canPop: _resultShown,
      child: Scaffold(
        // 다른 던전(0xFF0F0F17)보다 한 단계 더 어둡게 — 균열 내부라는
        // 느낌을 준다(요구사항: "배경색이나 상단 UI를 살짝 어둡게").
        backgroundColor: const Color(0xFF08080D),
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
                        widget.isBoss
                            ? '차원의 균열 — 보스'
                            : (widget.isElite ? '차원의 균열 — 엘리트' : '차원의 균열'),
                        style: TextStyle(
                          color: widget.isBoss
                              ? const Color(0xFFFF4D4D)
                              : (widget.isElite ? const Color(0xFFE05A9E) : Colors.white),
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        icon: Icon(
                          Icons.arrow_back,
                          color: _resultShown ? Colors.white : Colors.white24,
                        ),
                        onPressed: _resultShown ? () => Navigator.pop(context) : null,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: GameWidget(game: _game)),
                    // 균열 전용 은은한 보라색 오버레이 — Flame 캔버스 자체를
                    // 건드리지 않고 화면 톤만 살짝 어둡게 바꾼다.
                    const Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: Color(0x22240B3E)),
                        ),
                      ),
                    ),
                    const Positioned.fill(child: SkillEffectOverlay()),
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
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '몬스터',
                            style: TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: monsterHpRatio,
                              minHeight: 12,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation(Colors.redAccent),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            '내 체력 (riftHp)',
                            style: TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: riftHpRatio,
                              minHeight: 12,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation(Colors.greenAccent),
                            ),
                          ),
                          if (RiftManager.instance.equippedRelics.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            RiftRelicBar(relics: RiftManager.instance.equippedRelics),
                          ],
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

/// 지금까지 모은 임시 유물([RiftManager.equippedRelics])을 작은 이모지
/// 아이콘으로 가로 나열한다 — [RiftScreen]의 갈림길 화면과
/// [RiftBattleScreen] 양쪽에서 공유한다. 아이콘을 길게 누르면(모바일
/// 기본 [Tooltip] 동작) 이름/효과가 말풍선으로, 짧게 탭하면 같은 내용이
/// 중앙 토스트로 뜬다 — 두 상호작용 모두 지원해 달라는 요구사항 그대로.
class RiftRelicBar extends StatelessWidget {
  const RiftRelicBar({super.key, required this.relics});

  final List<RiftRelic> relics;

  @override
  Widget build(BuildContext context) {
    if (relics.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 36,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final RiftRelic relic in relics)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Tooltip(
                  message: '${relic.name}: ${relic.description}',
                  child: GestureDetector(
                    onTap: () =>
                        showCenterToast(context, '${relic.name}: ${relic.description}'),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: const Color(0xFF20202C),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF6C4FCE), width: 1.2),
                      ),
                      alignment: Alignment.center,
                      child: Text(relic.icon, style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 전투 승리 직후 뜨는 유물 선택 팝업 — 3개 중 하나를 고르면(뒤로가기로
/// 닫을 수 없다, `barrierDismissible: false`) 그 값을 그대로 pop한다.
class _RelicChoiceDialog extends StatelessWidget {
  const _RelicChoiceDialog({required this.options});

  final List<RiftRelic> options;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1B1B26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        '승리! 임시 유물을 선택하세요',
        style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final RiftRelic relic in options) ...[
            InkWell(
              onTap: () => Navigator.of(context).pop(relic),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.maxFinite,
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF20202C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF6C4FCE), width: 1.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      relic.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      relic.description,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
