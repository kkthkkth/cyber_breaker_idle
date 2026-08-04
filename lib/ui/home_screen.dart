import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/idle_game.dart';
import '../managers/game_manager.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GameManager _manager = GameManager.instance;
  late final IdleGame _idleGame;

  @override
  void initState() {
    super.initState();
    _idleGame = IdleGame();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOfflineReward());
  }

  Future<void> _checkOfflineReward() async {
    final int reward = await _manager.calculateOfflineReward();
    if (reward <= 0 || !mounted) {
      return;
    }

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1B1B26),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            '오프라인 보상',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            '자리를 비운 동안 $reward G를 획득했습니다!',
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
    return Scaffold(
      backgroundColor: const Color(0xFF14141C),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 1,
              child: _BattleView(game: _idleGame, manager: _manager),
            ),
            Expanded(
              flex: 1,
              child: _UpgradeView(manager: _manager),
            ),
          ],
        ),
      ),
    );
  }
}

class _BattleView extends StatelessWidget {
  const _BattleView({required this.game, required this.manager});

  final IdleGame game;
  final GameManager manager;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F0F17),
      child: AnimatedBuilder(
        animation: manager,
        builder: (context, _) {
          final double hpRatio = manager.monsterMaxHp <= 0
              ? 0
              : (manager.monsterHp / manager.monsterMaxHp).clamp(0.0, 1.0);

          return Stack(
            children: [
              Positioned.fill(child: GameWidget(game: game)),
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      manager.isBossStage
                          ? '${manager.chapter}-${manager.stage} 보스!'
                          : '${manager.chapter}-${manager.stage}',
                      style: TextStyle(
                        color: manager.isBossStage ? Colors.redAccent : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
              if (manager.isBossStage)
                Positioned(
                  top: 52,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '남은 시간 ${manager.bossTimeRemaining.clamp(0, GameManager.bossTimeLimit).toStringAsFixed(1)}s',
                        style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
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
                        valueColor: const AlwaysStoppedAnimation(Colors.redAccent),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${manager.monsterHp.clamp(0, manager.monsterMaxHp).toStringAsFixed(0)} / ${manager.monsterMaxHp.toStringAsFixed(0)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _UpgradeView extends StatefulWidget {
  const _UpgradeView({required this.manager});

  final GameManager manager;

  @override
  State<_UpgradeView> createState() => _UpgradeViewState();
}

class _UpgradeViewState extends State<_UpgradeView> {
  late final Timer _cooldownTicker;

  @override
  void initState() {
    super.initState();
    _cooldownTicker = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _cooldownTicker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GameManager manager = widget.manager;

    return Container(
      color: const Color(0xFF1B1B26),
      padding: const EdgeInsets.all(16),
      child: AnimatedBuilder(
        animation: manager,
        builder: (context, _) {
          final List<Skill> learnedSkills =
              manager.skills.where((skill) => skill.isLearned).toList();

          return SingleChildScrollView(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.monetization_on, color: Colors.amber, size: 22),
                    const SizedBox(width: 6),
                    Text(
                      '${manager.gold} G',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (learnedSkills.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final Skill skill in learnedSkills)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: _SkillQuickSlot(
                            skill: skill,
                            onTap: () => manager.useActiveSkill(skill.id),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                _UpgradeButton(
                  title: '공격력',
                  level: manager.attackLevel,
                  valueLabel: manager.attackPower.toStringAsFixed(0),
                  cost: manager.attackUpgradeCost,
                  gold: manager.gold,
                  icon: Icons.local_fire_department,
                  onTap: manager.upgradeAttack,
                ),
                const SizedBox(height: 12),
                _UpgradeButton(
                  title: '공격속도',
                  level: manager.attackSpeedLevel,
                  valueLabel: '${manager.attackSpeed.toStringAsFixed(2)}/s',
                  cost: manager.speedUpgradeCost,
                  gold: manager.gold,
                  icon: Icons.bolt,
                  onTap: manager.upgradeAttackSpeed,
                ),
                const SizedBox(height: 12),
                _UpgradeButton(
                  title: '크리티컬 확률',
                  level: manager.criticalRateLevel,
                  valueLabel: '${(manager.criticalRate * 100).toStringAsFixed(0)}%',
                  cost: manager.criticalUpgradeCost,
                  gold: manager.gold,
                  icon: Icons.flash_on,
                  onTap: manager.upgradeCriticalRate,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _UpgradeButton extends StatelessWidget {
  const _UpgradeButton({
    required this.title,
    required this.level,
    required this.valueLabel,
    required this.cost,
    required this.gold,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final int level;
  final String valueLabel;
  final int cost;
  final int gold;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool affordable = gold >= cost;

    return InkWell(
      onTap: affordable ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF20202C),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: affordable ? const Color(0xFF6C4FCE) : const Color(0xFF3A3A4A),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: affordable ? Colors.amberAccent : Colors.white38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$title Lv.$level ($valueLabel)',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '비용: $cost G',
                    style: TextStyle(
                      color: affordable ? Colors.greenAccent : Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_upward, color: affordable ? Colors.white : Colors.white24),
          ],
        ),
      ),
    );
  }
}

class _SkillQuickSlot extends StatelessWidget {
  const _SkillQuickSlot({required this.skill, required this.onTap});

  final Skill skill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double remaining = skill.cooldownRemaining;
    final bool onCooldown = remaining > 0;

    return InkWell(
      onTap: onCooldown ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 52,
        height: 52,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF20202C),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF6C4FCE), width: 1.2),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(skill.icon, color: Colors.orangeAccent, size: 26),
            if (onCooldown)
              Container(
                color: Colors.black54,
                alignment: Alignment.center,
                child: Text(
                  remaining.toStringAsFixed(0),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
