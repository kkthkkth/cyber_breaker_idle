import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/idle_game.dart';
import '../managers/guild_raid_manager.dart';
import '../managers/skill_manager.dart';
import '../models/active_skill_model.dart';
import '../models/guild_boss_model.dart';
import '../utils/number_formatter.dart';
import '../widgets/bouncy_button.dart';
import 'home_screen.dart' show SkillEffectOverlay, SkillTreeQuickBar;
import 'top_bar.dart';

/// 길드 레이드 탭에서 [도전하기]를 누르면 곧장 여기로 진입한다 — 길드
/// 던전 전투 화면([GuildDungeonScreen])과 같은 [IdleGame] + [GameWidget]
/// 뼈대를 그대로 재사용하되, 몬스터 체력이 "나만의 인스턴스 체력"이 아니라
/// 길드원 전원이 공유하는 서버 보스 체력이라는 점이 다르다. 30초가 끝나면
/// 이번 도전에서 누적으로 가한 데미지([IdleGame.guildRaidDamageDealt])를
/// [GuildRaidManager.submitDamage]로 한 번에 서버에 제출한다.
class GuildRaidScreen extends StatefulWidget {
  const GuildRaidScreen({super.key});

  @override
  State<GuildRaidScreen> createState() => _GuildRaidScreenState();
}

class _GuildRaidScreenState extends State<GuildRaidScreen> {
  late final IdleGame _game;
  bool _resultShown = false;
  bool _isSubmitting = false;

  void Function(double damage)? _previousDamageHandler;

  // 광역기(active_aoe) 낙하 이펙트/데미지도 damageHandler와 같은 이유로
  // 저장해뒀다가 복원한다(dungeon_screen.dart의 _DungeonBattleScreen과
  // 동일한 관례) — 안 그러면 이 화면을 나간 뒤 홈 화면에서 광역기를 써도
  // 이미 dispose된 이 IdleGame의 콜백이 계속 남아 있어(1) 아무 효과가
  // 없고 (2) 이 dispose된 인스턴스가 클로저를 통해 계속 메모리에 붙잡혀
  // 있게 된다.
  void Function(ActiveSkill skill, double damage)? _previousActiveSkillCast;

  @override
  void initState() {
    super.initState();
    _game = IdleGame();
    _game.guildRaidBossHp = (GuildRaidManager.instance.boss?.currentHp ?? 0)
        .toDouble();
    _game.onDungeonComplete = _handleDungeonComplete;
    _game.startDungeon(GameMode.guildRaid);
    // [퍼포먼스 감사 2026-08-21] 화면 전체를 다시 그리던 폴링 타이머 제거
    // — [_GuildRaidTimerBadge]/[_GuildRaidBossHpBar]가 각자 스스로 틱한다
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

  /// 30초가 끝나는 순간([IdleGame]은 길드 레이드를 "타임아웃=성공"으로
  /// 취급한다 — 처치가 목표가 아니라 누적 데미지가 목표라서) 호출된다.
  /// 실제 서버 반영([GuildRaidManager.submitDamage])은 여기서 비동기로
  /// 진행하고, 끝나는 대로 결과 팝업을 띄운다.
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
    final int totalDamage = _game.guildRaidDamageDealt.round();
    final GuildBossAttackResult? result = await GuildRaidManager.instance
        .submitDamage(totalDamage);
    if (!mounted) {
      return;
    }
    setState(() => _isSubmitting = false);
    _showResultDialog(totalDamage: totalDamage, result: result);
  }

  void _showResultDialog({
    required int totalDamage,
    required GuildBossAttackResult? result,
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
            '레이드 결과',
            style: TextStyle(
              color: Colors.redAccent,
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
              else ...[
                if (result.defeated)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '보스를 처치했습니다! Lv.${result.newLevel} 보스가 새로 나타났어요.',
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (result.coinReward > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '길드 주화 +${result.coinReward}개',
                      style: const TextStyle(
                        color: Color(0xFF6C4FCE),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
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
                        '길드 레이드',
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
                      child: Center(child: _GuildRaidTimerBadge(game: _game)),
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
                      child: _GuildRaidBossHpBar(game: _game),
                    ),
                    if (_isSubmitting)
                      Container(
                        color: Colors.black54,
                        alignment: Alignment.center,
                        child: const CircularProgressIndicator(
                          color: Colors.redAccent,
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

/// "남은 시간" 배지 — 스스로만 100ms마다 다시 그린다([_DungeonTimerBadge]
/// 와 같은 이유의 같은 패턴).
class _GuildRaidTimerBadge extends StatefulWidget {
  const _GuildRaidTimerBadge({required this.game});

  final IdleGame game;

  @override
  State<_GuildRaidTimerBadge> createState() => _GuildRaidTimerBadgeState();
}

class _GuildRaidTimerBadgeState extends State<_GuildRaidTimerBadge> {
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

/// 길드 보스 HP 바 — [_GuildRaidTimerBadge]와 같은 이유로 분리.
class _GuildRaidBossHpBar extends StatefulWidget {
  const _GuildRaidBossHpBar({required this.game});

  final IdleGame game;

  @override
  State<_GuildRaidBossHpBar> createState() => _GuildRaidBossHpBarState();
}

class _GuildRaidBossHpBarState extends State<_GuildRaidBossHpBar> {
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
            valueColor: const AlwaysStoppedAnimation(Colors.redAccent),
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

/// 길드 레이드 탭 — [GuildMainScreen] 하단 탭 중 하나. 탭에 들어설 때마다
/// 최신 보스 상태를 받아오고(다른 길드원의 공격을 반영), 오늘 남은 도전
/// 횟수/보스 체력 바를 보여준다.
class GuildRaidTab extends StatefulWidget {
  const GuildRaidTab({super.key});

  @override
  State<GuildRaidTab> createState() => _GuildRaidTabState();
}

class _GuildRaidTabState extends State<GuildRaidTab> {
  bool _isEntering = false;

  @override
  void initState() {
    super.initState();
    GuildRaidManager.instance.refreshBoss();
    GuildRaidManager.instance.refreshLeaderboard();
    // 요구사항: "다른 길드원이 때린 데미지가 내 화면의 보스 HP 바에도
    // 반영될 수 있도록... Realtime으로 갱신" — 이 탭이 떠 있는 동안만
    // 구독하고, dispose에서 반드시 정리한다.
    GuildRaidManager.instance.startLiveUpdates();
  }

  @override
  void dispose() {
    GuildRaidManager.instance.stopLiveUpdates();
    super.dispose();
  }

  Future<void> _enter() async {
    if (_isEntering || GuildRaidManager.instance.boss == null) {
      // 보스 정보가 아직 로드되기 전(refreshBoss 진행 중)에는 입장을 막는다
      // — 그러지 않으면 IdleGame이 guildRaidBossHp=0으로 시작해 1(최소
      // 폴백값)짜리 표시 체력으로 전투가 시작되는(실제 서버 반영은
      // 정상이지만 체력 바만 잘못 보이는) 경합 상태가 생긴다.
      return;
    }
    setState(() => _isEntering = true);
    final bool consumed = await GuildRaidManager.instance.consumeAttempt();
    if (!mounted) {
      return;
    }
    setState(() => _isEntering = false);
    if (!consumed) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('오늘 도전 횟수를 모두 사용했어요.')));
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const GuildRaidScreen()));
    if (mounted) {
      await GuildRaidManager.instance.refreshBoss();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: GuildRaidManager.instance,
      builder: (context, _) {
        final GuildRaidManager manager = GuildRaidManager.instance;
        final GuildBoss? boss = manager.boss;

        return RefreshIndicator(
          onRefresh: manager.refreshBoss,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF20202C),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.6),
                  ),
                ),
                child: boss == null
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            '보스 정보를 불러오는 중입니다...',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '길드 레이드 보스',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Lv.${boss.level}',
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // 거대한 보스 이미지(요구사항) — 전용 아트가 아직
                          // 없어 이 프로젝트의 다른 던전 이모지 연출
                          // (idle_game.dart의 🐉/👹/🏰/👑)과 같은 관례로
                          // 큼직한 이모지로 대체한다.
                          const Center(
                            child: Text('🐉', style: TextStyle(fontSize: 88)),
                          ),
                          const SizedBox(height: 10),
                          // "엄청나게 긴 통합 HP 바"(요구사항) — 기존
                          // 10px보다 훨씬 두껍게 키워서 길드 전체가 공유하는
                          // 체력이라는 느낌을 강조한다.
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: boss.hpRatio,
                              minHeight: 22,
                              backgroundColor: Colors.white12,
                              valueColor: const AlwaysStoppedAnimation(
                                Colors.redAccent,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: double.infinity,
                            child: Text(
                              '${NumberFormatter.format(boss.currentHp.toDouble())} / '
                              '${NumberFormatter.format(boss.maxHp.toDouble())}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 20),
              Text(
                '오늘 남은 도전 횟수: ${manager.remainingAttemptsToday} / ${GuildRaidManager.maxDailyAttempts}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 8),
              const Text(
                '30초 동안 온 힘을 다해 보스를 공격하세요! 보스 체력이 0이 되면\n다음 레벨 보스가 나타나고, 참여한 길드원 전원에게 길드 주화가 지급돼요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: withTapHaptic(
                  (manager.hasAttemptsLeft && !_isEntering && boss != null)
                      ? _enter
                      : null,
                ),
                icon: const Icon(Icons.sports_kabaddi),
                label: Text(
                  !manager.hasAttemptsLeft
                      ? '도전 횟수 소진'
                      : boss == null
                      ? '불러오는 중...'
                      : '도전하기',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF3A3A4A),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              _RaidLeaderboard(contributions: manager.leaderboard),
            ],
          ),
        );
      },
    );
  }
}

/// 길드원 누적 딜량 랭킹 1~5위(요구사항) — [GuildRaidManager.leaderboard]를
/// 그대로 그린다. 보스 체력과 마찬가지로 Realtime 구독([GuildRaidManager
/// .startLiveUpdates])이 갱신할 때마다 이 위젯도 함께 다시 그려진다(부모
/// [_GuildRaidTabState.build]가 이미 GuildRaidManager 전체를 구독 중).
class _RaidLeaderboard extends StatelessWidget {
  const _RaidLeaderboard({required this.contributions});

  final List<GuildRaidContribution> contributions;

  static const List<Color> _rankColors = [
    Color(0xFFFFD700), // 1위 금
    Color(0xFFC0C0C0), // 2위 은
    Color(0xFFCD7F32), // 3위 동
    Color(0xFF8A6FE0),
    Color(0xFF8A6FE0),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF20202C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF3A3A4A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.leaderboard, color: Color(0xFFC9A24B), size: 18),
              SizedBox(width: 6),
              Text(
                '누적 딜량 랭킹',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (contributions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '아직 이번 보스에게 데미지를 넣은 길드원이 없습니다.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            )
          else
            for (int i = 0; i < contributions.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color:
                              _rankColors[i.clamp(0, _rankColors.length - 1)],
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        contributions[i].nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      NumberFormatter.format(
                        contributions[i].totalDamageDealt.toDouble(),
                      ),
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
