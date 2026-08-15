import 'dart:async';

import 'package:flutter/material.dart';

import '../managers/arena_manager.dart';
import '../managers/game_manager.dart';
import '../models/arena_model.dart';
import '../utils/number_formatter.dart';

/// 1:1 비동기 PvP 전투 화면 — 상대는 실제로 접속해 있지 않고, 로비에서
/// 받아온 [ArenaOpponent]의 전투력 스냅샷만으로 재구성한 가상 스탯을
/// 상대한다. 전투 자체는 화면이 열리자마자 [ArenaManager.simulateBattle]
/// (결정론적 라운드 시뮬레이션)로 즉시 계산되고, 이 화면은 그 결과 이력을
/// 따라 체력 바를 애니메이션으로 재생하기만 한다.
class ArenaBattleScreen extends StatefulWidget {
  const ArenaBattleScreen({super.key, required this.opponent});

  final ArenaOpponent opponent;

  @override
  State<ArenaBattleScreen> createState() => _ArenaBattleScreenState();
}

class _ArenaBattleScreenState extends State<ArenaBattleScreen> {
  static const Duration _roundInterval = Duration(milliseconds: 400);

  late final double _myMaxHp = GameManager.instance.maxHp;
  late final double _myAttack = GameManager.instance.attackPower;
  late final ({double attack, double maxHp}) _opponentStats = ArenaManager.statsFromCombatPower(
    widget.opponent.combatPower,
  );
  late final ({List<double> myHpHistory, List<double> opponentHpHistory, bool won}) _result =
      ArenaManager.simulateBattle(
        myAttack: _myAttack,
        myMaxHp: _myMaxHp,
        opponentAttack: _opponentStats.attack,
        opponentMaxHp: _opponentStats.maxHp,
      );

  int _roundIndex = 0;
  Timer? _playbackTimer;
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    _playbackTimer = Timer.periodic(_roundInterval, _onTick);
  }

  void _onTick(Timer timer) {
    final int lastIndex = _result.myHpHistory.length - 1;
    if (_roundIndex >= lastIndex) {
      timer.cancel();
      _finishBattle();
      return;
    }
    setState(() => _roundIndex++);
  }

  void _finishBattle() {
    if (_isFinished) {
      return;
    }
    _isFinished = true;
    unawaited(ArenaManager.instance.reportBattleResult(won: _result.won));
    WidgetsBinding.instance.addPostFrameCallback((_) => _showResultDialog());
  }

  void _showResultDialog() {
    if (!mounted) {
      return;
    }
    final int scoreChange = _result.won ? ArenaManager.winScoreGain : -ArenaManager.lossScoreLoss;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1B1B26),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            _result.won ? '승리!' : '패배',
            style: TextStyle(
              color: _result.won ? Colors.greenAccent : Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _result.won
                    ? '${widget.opponent.nickname}님을 꺾었어요!'
                    : '${widget.opponent.nickname}님에게 패배했어요.',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Text(
                '점수 ${scoreChange > 0 ? '+' : ''}$scoreChange (현재 ${ArenaManager.instance.score}점)',
                style: TextStyle(
                  color: _result.won ? Colors.greenAccent : Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
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
        );
      },
    );
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double myHp = _result.myHpHistory[_roundIndex];
    final double opponentHp = _result.opponentHpHistory[_roundIndex];

    return PopScope(
      canPop: _isFinished,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F17),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1B1B26),
          elevation: 0,
          title: const Text(
            '결투장',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _Fighter(
                        name: '나',
                        icon: Icons.person,
                        accent: const Color(0xFF6C4FCE),
                        hp: myHp,
                        maxHp: _myMaxHp,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'VS',
                        style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ),
                    Expanded(
                      child: _Fighter(
                        name: widget.opponent.nickname,
                        icon: Icons.person_outline,
                        accent: Colors.redAccent,
                        hp: opponentHp,
                        maxHp: _opponentStats.maxHp,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  _isFinished ? '전투 종료' : '전투 중...',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Fighter extends StatelessWidget {
  const _Fighter({
    required this.name,
    required this.icon,
    required this.accent,
    required this.hp,
    required this.maxHp,
  });

  final String name;
  final IconData icon;
  final Color accent;
  final double hp;
  final double maxHp;

  @override
  Widget build(BuildContext context) {
    final double ratio = maxHp <= 0 ? 0 : (hp / maxHp).clamp(0.0, 1.0);

    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.2),
            shape: BoxShape.circle,
            border: Border.all(color: accent, width: 2),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: accent, size: 40),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 10,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation(accent),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${NumberFormatter.format(hp)} / ${NumberFormatter.format(maxHp)}',
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
      ],
    );
  }
}
