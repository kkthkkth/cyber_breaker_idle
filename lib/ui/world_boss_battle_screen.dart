import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/idle_game.dart';
import '../managers/skill_manager.dart';
import '../managers/world_boss_manager.dart';
import '../models/active_skill_model.dart';
import '../utils/number_formatter.dart';
import 'home_screen.dart' show SkillEffectOverlay, SkillTreeQuickBar;
import 'top_bar.dart';
import 'world_boss_ranking_dialog.dart';

/// 월드보스("용의 동굴") 전용 전투 화면 — 일반 스테이지/던전 전투 화면과
/// 완전히 같은 [IdleGame] + [GameWidget] 구조를 그대로 재사용한다
/// (dungeon_screen.dart의 `_DungeonBattleScreen`과 동일한 뼈대). 왼쪽엔 내
/// 캐릭터가, 오른쪽 몬스터 자리엔 용 이모지가 서서 서로 때리고, 배경도
/// 인게임과 같은 배경을 그대로 쓴다 — [IdleGame]이 GameMode.worldBoss일
/// 때 몬스터를 어떻게 스폰하는지는 idle_game.dart의 `_activateDungeon`을
/// 참고. [WorldBossEntryDialog]가 입장 티켓을 먼저 소비한 뒤에만 이
/// 화면으로 진입시킨다(티켓 소비는 이 화면의 책임이 아니다).
class WorldBossBattleScreen extends StatefulWidget {
  const WorldBossBattleScreen({super.key});

  @override
  State<WorldBossBattleScreen> createState() => _WorldBossBattleScreenState();
}

class _WorldBossBattleScreenState extends State<WorldBossBattleScreen> {
  late final IdleGame _game;
  bool _resultShown = false;

  // 이 화면 진입 전 스킬 데미지가 향하던 곳(보통 홈 화면의 IdleGame) —
  // dispose에서 복원해야 용의 동굴을 나간 뒤에도 스킬이 이미 사라진
  // 던전용 IdleGame을 계속 가리키는 일이 없다.
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
    _game.onDungeonComplete = _handleDungeonComplete;
    _game.startDungeon(GameMode.worldBoss);
    // [퍼포먼스 감사 2026-08-21] 화면 전체를 다시 그리던 폴링 타이머 제거
    // — [_WorldBossTimerBadge]/[_WorldBossMonsterHpBar]가 각자 스스로
    // 틱한다([_DungeonBattleScreen]과 같은 수정).

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
    // 이 화면 전용 IdleGame 인스턴스는 매번 새로 만들고 여기서 버린다 —
    // EquipmentManager 리스너를 해제하지 않으면 용의 동굴에 들어갔다
    // 나올 때마다 계속 쌓인다.
    _game.detachListeners();
    super.dispose();
  }

  /// 던전 공용 콜백([IdleGame.onDungeonComplete])을 통해 60초 타임아웃
  /// 시점에 호출된다 — 골드/장비 보상 대신 이번 전투 누적 데미지
  /// ([IdleGame.worldBossDamageDealt])를 [WorldBossManager]에 반영하고
  /// 결과 팝업을 띄운다. 결과 팝업 자체는 이전 커스텀 화면과 같은 디자인을
  /// 그대로 유지한다(사용자가 바꿔달라고 한 건 전투 레이아웃이지 결과
  /// 팝업이 아니다).
  Future<void> _handleDungeonComplete({
    required bool success,
    required int goldReward,
    int gemReward = 0,
    dynamic itemReward,
    int pawprintReward = 0,
    int guildCoinReward = 0,
    dynamic consumableItemReward,
  }) async {
    if (_resultShown || !mounted) {
      return;
    }
    // [퍼포먼스 감사 2026-08-21] 폴링 타이머를 없앴으므로 뒤로가기 버튼
    // 활성화를 반영하려면 명시적으로 setState해야 한다.
    setState(() => _resultShown = true);

    final double damageDealt = _game.worldBossDamageDealt;
    // 결과 팝업이 "이번 세션 누적 데미지"(WorldBossManager.totalDamageDealt)를
    // 곧바로 보여줘야 하므로, 로컬 반영이 끝날 때까지 기다린 뒤 팝업을
    // 띄운다(서버 동기화 자체는 recordBattleDamage 내부에서 여전히
    // fire-and-forget이라 오래 걸리지 않는다).
    await WorldBossManager.instance.recordBattleDamage(damageDealt);
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showResultDialog(damageDealt),
    );
  }

  void _showResultDialog(double damageDealt) {
    if (!mounted) {
      return;
    }
    final int sessionTotal = WorldBossManager.instance.totalDamageDealt;
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
            '도전 종료',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '용의 동굴에서 물러났습니다.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 4),
              Text(
                '이번 전투 데미지: ${NumberFormatter.format(damageDealt)}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 10),
              const Text(
                '이번 회차 내 총 누적 데미지',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                NumberFormatter.format(sessionTotal.toDouble()),
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
            ],
          ),
          actions: [
            OutlinedButton(
              onPressed: () => showWorldBossRankingDialog(dialogContext),
              child: const Text('랭킹 보기'),
            ),
            ElevatedButton(
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
                        '월드보스: 용의 동굴',
                        style: TextStyle(
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
                    Positioned(
                      top: 12,
                      left: 0,
                      right: 0,
                      child: Center(child: _WorldBossTimerBadge(game: _game)),
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
                      child: _WorldBossMonsterHpBar(game: _game),
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
class _WorldBossTimerBadge extends StatefulWidget {
  const _WorldBossTimerBadge({required this.game});

  final IdleGame game;

  @override
  State<_WorldBossTimerBadge> createState() => _WorldBossTimerBadgeState();
}

class _WorldBossTimerBadgeState extends State<_WorldBossTimerBadge> {
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

/// 몬스터 HP 바 — [_WorldBossTimerBadge]와 같은 이유로 분리.
class _WorldBossMonsterHpBar extends StatefulWidget {
  const _WorldBossMonsterHpBar({required this.game});

  final IdleGame game;

  @override
  State<_WorldBossMonsterHpBar> createState() => _WorldBossMonsterHpBarState();
}

class _WorldBossMonsterHpBarState extends State<_WorldBossMonsterHpBar> {
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
          '${NumberFormatter.format(widget.game.dungeonMonsterHp.clamp(0, widget.game.dungeonMonsterMaxHp))} / '
          '${NumberFormatter.format(widget.game.dungeonMonsterMaxHp)}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}
