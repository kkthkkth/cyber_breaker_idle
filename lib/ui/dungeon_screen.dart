import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/idle_game.dart';
import '../managers/dungeon_manager.dart';
import '../models/equipment.dart';

class DungeonScreen extends StatelessWidget {
  const DungeonScreen({super.key});

  void _enterDungeon(BuildContext context, GameMode mode) {
    final DungeonManager dungeonManager = DungeonManager.instance;

    if (mode == GameMode.goldDungeon || mode == GameMode.equipDungeon) {
      final DungeonType type = mode == GameMode.goldDungeon
          ? DungeonType.goldDungeon
          : DungeonType.equipmentDungeon;
      if (!dungeonManager.consumeTicket(type)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('입장 티켓이 부족합니다')),
        );
        return;
      }
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _DungeonBattleScreen(mode: mode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DungeonManager dungeonManager = DungeonManager.instance;

    return AnimatedBuilder(
      animation: dungeonManager,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF14141C),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1B1B26),
            elevation: 0,
            title: const Text(
              '던전',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
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
                title: '무한의 탑',
                description: '현재 ${dungeonManager.currentFloor}층 도전 중! (클리어 보상: 골드)',
                icon: Icons.stairs,
                accentColor: Colors.cyanAccent,
                buttonLabel: '도전하기',
                enabled: true,
                onTap: () => _enterDungeon(context, GameMode.towerOfInfinity),
              ),
            ],
          ),
        );
      },
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
  const _DungeonBattleScreen({required this.mode});

  final GameMode mode;

  @override
  State<_DungeonBattleScreen> createState() => _DungeonBattleScreenState();
}

class _DungeonBattleScreenState extends State<_DungeonBattleScreen> {
  late final IdleGame _game;
  late final Timer _ticker;
  bool _resultShown = false;

  @override
  void initState() {
    super.initState();
    _game = IdleGame();
    _game.onDungeonComplete = _handleDungeonComplete;
    _game.startDungeon(widget.mode);
    _ticker = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  void _handleDungeonComplete({
    required bool success,
    required int goldReward,
    Equipment? itemReward,
  }) {
    if (_resultShown || !mounted) {
      return;
    }
    _resultShown = true;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1B1B26),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            success ? '클리어 성공!' : '클리어 실패',
            style: TextStyle(
              color: success ? Colors.greenAccent : Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              if (goldReward <= 0 && itemReward == null)
                const Text(
                  '보상이 없습니다. 다시 도전해보세요!',
                  style: TextStyle(color: Colors.white70),
                ),
            ],
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
      case GameMode.towerOfInfinity:
        return '무한의 탑 ${DungeonManager.instance.currentFloor}층';
      case GameMode.mainStage:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool timed =
        widget.mode == GameMode.goldDungeon || widget.mode == GameMode.equipDungeon;
    final double hpRatio = _game.dungeonMonsterMaxHp <= 0
        ? 0
        : (_game.dungeonMonsterHp / _game.dungeonMonsterMaxHp).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B1B26),
        elevation: 0,
        title: Text(
          _title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Positioned.fill(child: GameWidget(game: _game)),
          if (timed)
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
                  '${_game.dungeonMonsterHp.clamp(0, _game.dungeonMonsterMaxHp).toStringAsFixed(0)} / '
                  '${_game.dungeonMonsterMaxHp.toStringAsFixed(0)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
