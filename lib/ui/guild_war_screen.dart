import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/idle_game.dart';
import '../managers/guild_war_manager.dart';
import '../managers/skill_manager.dart';
import '../models/active_skill_model.dart';
import '../models/guild_war_model.dart';
import '../utils/number_formatter.dart';
import '../widgets/bouncy_button.dart';
import 'home_screen.dart' show SkillEffectOverlay, SkillTreeQuickBar;
import 'top_bar.dart';

/// 길드 전쟁 거점 공격 화면 — [GuildRaidScreen]과 완전히 같은
/// [IdleGame] + [GameWidget] 뼈대를 재사용하되, 상대가 공유 보스가 아니라
/// 매칭된 상대 길드의 거점(성)이라는 점이 다르다. 30초가 끝나면 누적
/// 데미지를 [GuildWarManager.submitDamage]로 한 번에 제출한다.
class GuildWarScreen extends StatefulWidget {
  const GuildWarScreen({super.key});

  @override
  State<GuildWarScreen> createState() => _GuildWarScreenState();
}

class _GuildWarScreenState extends State<GuildWarScreen> {
  late final IdleGame _game;
  bool _resultShown = false;
  bool _isSubmitting = false;

  void Function(double damage)? _previousDamageHandler;
  void Function(ActiveSkill skill, double damage)? _previousActiveSkillCast;

  @override
  void initState() {
    super.initState();
    _game = IdleGame();
    _game.guildWarBaseHp = (GuildWarManager.instance.myWar?.baseCurrentHp ?? 0)
        .toDouble();
    _game.onDungeonComplete = _handleDungeonComplete;
    _game.startDungeon(GameMode.guildWar);
    // [퍼포먼스 감사 2026-08-21] 화면 전체를 다시 그리던 폴링 타이머 제거
    // — [_GuildWarTimerBadge]/[_GuildWarBaseHpBar]가 각자 스스로 틱한다
    // ([_DungeonBattleScreen]과 같은 수정).

    _previousDamageHandler = SkillManager.instance.damageHandler;
    SkillManager.instance.damageHandler = _game.applySkillDamage;
    _previousActiveSkillCast = SkillManager.instance.onActiveSkillCast;
    SkillManager.instance.onActiveSkillCast = _game.castActiveSkill;
  }

  @override
  void dispose() {
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
    _game.detachListeners();
    super.dispose();
  }

  void _handleDungeonComplete({
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
    // [퍼포먼스 감사 2026-08-21] 폴링 타이머를 없앴으므로 뒤로가기 버튼
    // 활성화를 반영하려면 명시적으로 setState해야 한다.
    setState(() => _resultShown = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _submitAndShowResult());
  }

  Future<void> _submitAndShowResult() async {
    if (!mounted) {
      return;
    }
    setState(() => _isSubmitting = true);
    final int totalDamage = _game.guildWarDamageDealt.round();
    final GuildWarAttackResult? result = await GuildWarManager.instance
        .submitDamage(totalDamage);
    if (!mounted) {
      return;
    }
    setState(() => _isSubmitting = false);
    _showResultDialog(totalDamage: totalDamage, result: result);
  }

  void _showResultDialog({
    required int totalDamage,
    required GuildWarAttackResult? result,
  }) {
    if (!mounted) {
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1B1B26),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            '거점 공격 결과',
            style: TextStyle(
              color: Color(0xFFB8860B),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '누적 피해량: ${NumberFormatter.format(totalDamage.toDouble())}',
                style: const TextStyle(color: Colors.white70),
              ),
              if (result == null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    '서버에 결과를 반영하지 못했어요. 네트워크를 확인해주세요.',
                    style: TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                )
              else if (result.baseDestroyed)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    '상대 거점을 파괴했습니다!',
                    style: TextStyle(
                      color: Colors.amberAccent,
                      fontWeight: FontWeight.bold,
                    ),
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
  Widget build(BuildContext context) {
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
                    const Align(
                      alignment: Alignment.center,
                      child: Text(
                        '길드 전쟁',
                        style: TextStyle(
                          color: Colors.white,
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
                          color: (_resultShown && !_isSubmitting)
                              ? Colors.white
                              : Colors.white24,
                        ),
                        onPressed: (_resultShown && !_isSubmitting)
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
                    Positioned(
                      top: 12,
                      left: 0,
                      right: 0,
                      child: Center(child: _GuildWarTimerBadge(game: _game)),
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
                      child: _GuildWarBaseHpBar(game: _game),
                    ),
                    if (_isSubmitting)
                      Container(
                        color: Colors.black54,
                        alignment: Alignment.center,
                        child: const CircularProgressIndicator(
                          color: Color(0xFFB8860B),
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

/// "남은 시간" 배지 — [_DungeonTimerBadge]와 같은 이유로 분리, 스스로만
/// 100ms마다 다시 그린다.
class _GuildWarTimerBadge extends StatefulWidget {
  const _GuildWarTimerBadge({required this.game});

  final IdleGame game;

  @override
  State<_GuildWarTimerBadge> createState() => _GuildWarTimerBadgeState();
}

class _GuildWarTimerBadgeState extends State<_GuildWarTimerBadge> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '남은 시간 ${widget.game.dungeonTimeRemaining.clamp(0, 999).toStringAsFixed(1)}s',
        style: const TextStyle(
          color: Colors.orangeAccent,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }
}

/// 상대 거점 HP 바 — [_GuildWarTimerBadge]와 같은 이유로 분리.
class _GuildWarBaseHpBar extends StatefulWidget {
  const _GuildWarBaseHpBar({required this.game});

  final IdleGame game;

  @override
  State<_GuildWarBaseHpBar> createState() => _GuildWarBaseHpBarState();
}

class _GuildWarBaseHpBarState extends State<_GuildWarBaseHpBar> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    final double hpRatio = widget.game.dungeonMonsterMaxHp <= 0
        ? 0
        : (widget.game.dungeonMonsterHp / widget.game.dungeonMonsterMaxHp)
              .clamp(0.0, 1.0);
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: hpRatio,
            minHeight: 14,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation(Color(0xFFB8860B)),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${widget.game.dungeonMonsterHp.clamp(0, widget.game.dungeonMonsterMaxHp).toStringAsFixed(0)} / '
          '${widget.game.dungeonMonsterMaxHp.toStringAsFixed(0)}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}

/// 길드 전쟁 탭 — [GuildMainScreen] 하단 탭 중 하나. 화면 중앙에 서버
/// 누적 세금(요구사항: "화려하게")을 보여주고, 신청/매칭/전투 상태를
/// 단계별로 안내한다.
class GuildWarTab extends StatefulWidget {
  const GuildWarTab({super.key});

  @override
  State<GuildWarTab> createState() => _GuildWarTabState();
}

class _GuildWarTabState extends State<GuildWarTab> {
  bool _isApplying = false;
  bool _isEntering = false;

  @override
  void initState() {
    super.initState();
    GuildWarManager.instance.refreshTaxPool();
    GuildWarManager.instance.refreshMyWar();
  }

  Future<void> _apply() async {
    if (_isApplying) {
      return;
    }
    setState(() => _isApplying = true);
    final bool success = await GuildWarManager.instance.applyForWar();
    if (!mounted) {
      return;
    }
    setState(() => _isApplying = false);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(success ? '이번 주 길드 전쟁에 신청했습니다.' : '신청에 실패했어요.')),
      );
  }

  Future<void> _enter() async {
    if (_isEntering) {
      return;
    }
    setState(() => _isEntering = true);
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const GuildWarScreen()));
    if (mounted) {
      setState(() => _isEntering = false);
      await GuildWarManager.instance.refreshMyWar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: GuildWarManager.instance,
      builder: (context, _) {
        final GuildWarManager manager = GuildWarManager.instance;
        final GuildWar? war = manager.myWar;

        return RefreshIndicator(
          onRefresh: manager.refreshMyWar,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _TaxPoolBanner(taxPool: manager.taxPool),
              const SizedBox(height: 20),
              if (war == null) ...[
                const Text(
                  '평일(월~금)에 신청하면 토요일 오후 9시에 상대 길드와 매칭돼\n전쟁이 시작됩니다. 일요일 자정에 정산돼요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: withTapHaptic(_isApplying ? null : _apply),
                  icon: const Icon(Icons.flag),
                  label: const Text('길드 전쟁 신청'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB8860B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ] else
                _WarStatusCard(
                  war: war,
                  isEntering: _isEntering,
                  onEnter: _enter,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 화면 중앙에 화려하게 보여주는 서버 누적 세금 배너 — 요구사항: "현재
/// 누적된 서버 세금(코인/보석)을 화려하게".
class _TaxPoolBanner extends StatelessWidget {
  const _TaxPoolBanner({required this.taxPool});

  final GlobalTaxPool taxPool;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4A3B0A), Color(0xFF1B1B26)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFD54F), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD54F).withValues(alpha: 0.35),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.account_balance, color: Color(0xFFFFD54F), size: 32),
          const SizedBox(height: 8),
          const Text(
            '서버 누적 전쟁 세금',
            style: TextStyle(
              color: Color(0xFFFFD54F),
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.monetization_on,
                color: Colors.amberAccent,
                size: 22,
              ),
              const SizedBox(width: 6),
              Text(
                NumberFormatter.format(taxPool.coinPool.toDouble()),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
              const SizedBox(width: 20),
              const Icon(Icons.diamond, color: Colors.cyanAccent, size: 20),
              const SizedBox(width: 6),
              Text(
                NumberFormatter.format(taxPool.gemPool.toDouble()),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '이번 주 승리 길드에게 분배됩니다',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _WarStatusCard extends StatelessWidget {
  const _WarStatusCard({
    required this.war,
    required this.isEntering,
    required this.onEnter,
  });

  final GuildWar war;
  final bool isEntering;
  final VoidCallback onEnter;

  String get _statusLabel => switch (war.status) {
    GuildWarStatus.applied => '매칭 대기 중 (토요일 오후 9시 시작)',
    GuildWarStatus.matched => '전쟁 진행 중 — 지금 공격하세요!',
    GuildWarStatus.destroyed => '상대 거점 파괴! 정산을 기다리는 중',
    GuildWarStatus.settled => switch (war.result) {
      GuildWarResult.win => '승리! 길드 금고에 보상이 지급됐어요',
      GuildWarResult.lose => '패배했어요. 다음 주에 다시 도전하세요',
      _ => '정산 완료',
    },
  };

  @override
  Widget build(BuildContext context) {
    final bool canFight = war.isMatched;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF20202C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFB8860B).withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _statusLabel,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (war.isMatched) ...[
            const SizedBox(height: 12),
            const Row(
              children: [
                Icon(Icons.castle, color: Color(0xFFB8860B), size: 18),
                SizedBox(width: 6),
                Text(
                  '상대 거점 체력',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: war.baseHpRatio,
                minHeight: 10,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation(Color(0xFFB8860B)),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${NumberFormatter.format(war.baseCurrentHp.toDouble())} / '
              '${NumberFormatter.format(war.baseMaxHp.toDouble())}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: withTapHaptic(
                canFight && !isEntering ? onEnter : null,
              ),
              icon: const Icon(Icons.sports_kabaddi),
              label: const Text('거점 공격'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB8860B),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF3A3A4A),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
