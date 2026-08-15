import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/idle_game.dart';
import '../managers/attendance_manager.dart';
import '../managers/game_manager.dart';
import '../managers/mission_manager.dart';
import '../managers/skill_manager.dart';
import '../managers/speed_manager.dart';
import '../managers/world_boss_manager.dart';
import '../models/mission_model.dart';
import '../models/skill_model.dart';
import '../utils/number_formatter.dart';
import '../widgets/center_toast.dart';
import 'mission_dialog.dart';
import 'potion_quick_slot.dart';
import 'world_boss_entry_dialog.dart';

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
    // Default skill-damage target for the whole app session — dungeon
    // screens temporarily point this at their own IdleGame instance while
    // they're on top, then restore whatever was here before them.
    SkillManager.instance.damageHandler = _idleGame.applySkillDamage;
    // StoryDialogWidget (a separate widget tree pushed as a fullscreen
    // route) uses this to switch the character to its idle motion while a
    // story dialog is showing — see IdleGame.mainInstance.
    IdleGame.mainInstance = _idleGame;
    // MainNavigationScreen이 IndexedStack으로 모든 탭을 항상 마운트해
    // 두므로, 다른 탭을 보는 중에도 이 콜백이 살아있어 알림을 놓치지 않는다.
    WorldBossManager.instance.onBossAppeared = _onWorldBossAppeared;
  }

  @override
  void dispose() {
    if (identical(WorldBossManager.instance.onBossAppeared, _onWorldBossAppeared)) {
      WorldBossManager.instance.onBossAppeared = null;
    }
    super.dispose();
  }

  void _onWorldBossAppeared() {
    if (!mounted) {
      return;
    }
    showCenterToast(context, '월드보스가 나타났어요! 지금 도전해 보세요!');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14141C),
      // 패배(피격) 연출은 배틀 뷰 영역만이 아니라 화면 전체(업그레이드
      // 버튼 패널 포함)를 덮어야 하므로, Column을 Stack으로 한 번 더
      // 감싸고 DefeatFadeOverlay를 그 위에 Positioned.fill로 올린다.
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  flex: 1,
                  child: _BattleView(game: _idleGame, manager: _manager),
                ),
                const SkillTreeQuickBar(),
                Expanded(
                  flex: 1,
                  child: _UpgradeView(manager: _manager),
                ),
              ],
            ),
            Positioned.fill(child: DefeatFadeOverlay(game: _idleGame)),
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
          final double playerHpRatio = manager.maxHp <= 0
              ? 0
              : (manager.currentHp / manager.maxHp).clamp(0.0, 1.0);

          return LayoutBuilder(
            builder: (context, constraints) {
              // IdleGame.playerXRatio/groundYRatio와 반드시 같은 값을
              // 써야 한다 — 여기(Flutter 오버레이: HP 바/펫 아이콘)와
              // Flame 쪽(PlayerAnimationComponent/RectangleComponent 몬스터)
              // 이 서로 다른 비율을 쓰면 해상도가 바뀔 때마다 둘이 어긋난다.
              final double playerX = constraints.maxWidth * IdleGame.playerXRatio;
              final double playerY = constraints.maxHeight * IdleGame.groundYRatio;
              const double spriteSize = 56;

              // 몬스터는 항상 화면 가로 중앙(전투 위치)에서 싸운다 — 몬스터
              // HP 바를 그 머리 위, 몬스터 폭의 1.2배 너비로만 짧게 띄운다.
              final double monsterCenterX = constraints.maxWidth / 2;
              final double monsterTopY = playerY - IdleGame.monsterSize;
              final double monsterHpBarWidth = IdleGame.monsterSize * 1.2;

              return Stack(
                children: [
                  // 챕터 배경은 이제 IdleGame 안의 다중 레이어 패럴랙스
                  // (ParallaxBackLayer: 정지된 먼 배경 + ParallaxGroundLayer:
                  // 빠르게 스크롤되는 바닥)가 직접 그린다 — GameWidget 캔버스
                  // 자체가 투명해서(_normalBackgroundColor) 그 위에
                  // 몬스터/이펙트가 자연스럽게 겹쳐 보인다.
                  Positioned.fill(child: GameWidget(game: game)),
                  const Positioned.fill(child: SkillEffectOverlay()),
                  Positioned.fill(child: PlayerHitFlashOverlay(game: game)),
                  Positioned(
                    left: (playerX - 40).clamp(0, constraints.maxWidth - 80),
                    // 캐릭터가 바닥에 서 있으므로 HP 바는 발밑이 아니라
                    // 머리 위에 띄운다.
                    top: playerY - spriteSize - 30,
                    child: SizedBox(
                      width: 80,
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: playerHpRatio,
                              minHeight: 8,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation(Colors.greenAccent),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${NumberFormatter.format(manager.currentHp.clamp(0, manager.maxHp))} / ${NumberFormatter.format(manager.maxHp)}',
                            style: const TextStyle(color: Colors.white70, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Positioned(
                    top: 12,
                    left: 12,
                    child: _QuestHudButton(),
                  ),
                  const Positioned(
                    top: 64,
                    left: 12,
                    child: _WorldBossHudButton(),
                  ),
                  // 상단 AppBar의 보석/코인 재화 표시(main.dart) 바로 아래,
                  // 화면 우측 상단에 위치한 물약 퀵슬롯.
                  const Positioned(
                    top: 12,
                    right: 12,
                    child: PotionQuickSlot(),
                  ),
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
                    // 몬스터 머리 바로 위(TopCenter에서 약간 더 위로)에
                    // 짧고 깔끔하게 — 예전처럼 화면 하단을 가로로 다 덮지
                    // 않는다. 몬스터는 항상 전투 위치(화면 가로 중앙,
                    // groundY 위)에서 싸우므로(IdleGame._enterBattlePhase),
                    // Flame 쪽 실제 position을 매 프레임 동기화하는 대신
                    // 전투가 실제로 벌어지는 이 고정 좌표를 그대로
                    // 재사용한다(플레이어 스프라이트 오버레이도 같은
                    // 방식으로 이미 groundY/playerXRatio를 공유한다).
                    top: monsterTopY - 40,
                    left: monsterCenterX - monsterHpBarWidth / 2,
                    width: monsterHpBarWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: hpRatio,
                            minHeight: 10,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation(Colors.redAccent),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${NumberFormatter.format(manager.monsterHp.clamp(0, manager.monsterMaxHp))} / ${NumberFormatter.format(manager.monsterMaxHp)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Plays a brief pop-in/pop-out effect over the monster whenever
/// SkillManager.useSkill lands a hit. Always mounted (even when idle) so the
/// AnimatedOpacity/AnimatedScale below have a starting value to animate
/// from — conditionally building it only once active would skip the very
/// first fade-in.
class SkillEffectOverlay extends StatefulWidget {
  const SkillEffectOverlay({super.key});

  @override
  State<SkillEffectOverlay> createState() => _SkillEffectOverlayState();
}

class _SkillEffectOverlayState extends State<SkillEffectOverlay> {
  SkillNode? _activeNode;
  double _activeDamage = 0;
  bool _activeIsCritical = false;
  bool _visible = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    SkillManager.instance.onSkillUsed = _onSkillUsed;
  }

  void _onSkillUsed(SkillNode node, double damage, bool isCritical) {
    _hideTimer?.cancel();
    setState(() {
      _activeNode = node;
      _activeDamage = damage;
      _activeIsCritical = isCritical;
      _visible = true;
    });
    _hideTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => _visible = false);
      }
    });
  }

  /// 일반 타격 팝업: 원소 색상, 기본 크기.
  Widget _buildNormalDamageText(SkillNode node) {
    return Text(
      NumberFormatter.format(_activeDamage),
      style: TextStyle(
        color: node.element.color,
        fontSize: 28,
        fontWeight: FontWeight.bold,
        shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
      ),
    );
  }

  /// 크리티컬 팝업: 노란색, 더 큰 크기로 강조.
  Widget _buildCriticalDamageText() {
    return Text(
      NumberFormatter.format(_activeDamage),
      style: const TextStyle(
        color: Colors.yellow,
        fontSize: 40,
        fontWeight: FontWeight.bold,
        shadows: [Shadow(color: Colors.black, blurRadius: 8)],
      ),
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    if (identical(SkillManager.instance.onSkillUsed, _onSkillUsed)) {
      SkillManager.instance.onSkillUsed = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SkillNode? node = _activeNode;

    return IgnorePointer(
      child: Center(
        child: AnimatedOpacity(
          opacity: _visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: AnimatedScale(
            scale: _visible ? 1.2 : 0.6,
            duration: const Duration(milliseconds: 200),
            child: node == null
                ? const SizedBox(width: 100, height: 100)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: node.element.color.withValues(alpha: 0.35),
                          border: Border.all(color: node.element.color, width: 3),
                        ),
                        child: Icon(node.element.icon, color: node.element.color, size: 48),
                      ),
                      const SizedBox(height: 6),
                      _activeIsCritical
                          ? _buildCriticalDamageText()
                          : _buildNormalDamageText(node),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// 플레이어가 몬스터에게 맞았을 때 화면 전체에 붉은 반투명 플래시를
/// 띄우는 오버레이 — 캐릭터 본체는 이제 IdleGame 안의
/// [PlayerAnimationComponent]가 실제 달리기/공격 프레임 애니메이션으로
/// Flame 캔버스에 직접 그린다(더 이상 Flutter가 단일 이미지를 스왑해
/// 그리지 않는다). SkillEffectOverlay와 동일하게 항상 마운트해 두어
/// AnimatedOpacity가 첫 피격에도 정상적으로 페이드인되도록 한다.
class PlayerHitFlashOverlay extends StatefulWidget {
  const PlayerHitFlashOverlay({super.key, required this.game});

  final IdleGame game;

  @override
  State<PlayerHitFlashOverlay> createState() => _PlayerHitFlashOverlayState();
}

class _PlayerHitFlashOverlayState extends State<PlayerHitFlashOverlay> {
  bool _isGettingHit = false;
  Timer? _hitTimer;

  @override
  void initState() {
    super.initState();
    widget.game.onPlayerHit = _onPlayerHit;
  }

  /// IdleGame.onPlayerHit은 Flame의 게임 루프(update()) 도중에 동기적으로
  /// 호출된다 — 그 시점이 Flutter의 빌드 단계와 겹치면 setState()를 바로
  /// 부를 때 "setState() or markNeedsBuild() called during build" 에러가
  /// 난다. 실제 상태 변경을 다음 마이크로태스크로 미뤄서 현재 빌드가 끝난
  /// 뒤 안전하게 반영되도록 한다.
  void _safeSetState(VoidCallback fn) {
    Future.microtask(() {
      if (mounted) {
        setState(fn);
      }
    });
  }

  void _onPlayerHit(double damage) {
    _hitTimer?.cancel();
    _safeSetState(() => _isGettingHit = true);
    _hitTimer = Timer(const Duration(milliseconds: 150), () {
      _safeSetState(() => _isGettingHit = false);
    });
  }

  @override
  void dispose() {
    _hitTimer?.cancel();
    if (identical(widget.game.onPlayerHit, _onPlayerHit)) {
      widget.game.onPlayerHit = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _isGettingHit ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 100),
        child: Container(color: Colors.redAccent.withValues(alpha: 0.35)),
      ),
    );
  }
}

/// 패배(HP 0 도달/보스전 제한시간 초과) 시 화면 전체를 검게 덮었다 걷어내는
/// 오버레이 — 실제 타이밍(언제 검어지기 시작하고, 언제 다시 밝아지는지)은
/// [IdleGame]이 [IdleGame.onDefeatFadeOut]/[IdleGame.onDefeatFadeIn] 두
/// 콜백으로 알려준다(스테이지 강등/체력 회복이 화면이 완전히 검을 때만
/// 일어나도록 IdleGame이 직접 시퀀스를 관장한다 — 여기서는 그 신호에 맞춰
/// [AnimatedOpacity]로 부드럽게 전환만 한다). [IgnorePointer]라 터치를
/// 가로막진 않지만, 그 사이 게임 로직 쪽은 IdleGame이 이미 얼려 둔다.
class DefeatFadeOverlay extends StatefulWidget {
  const DefeatFadeOverlay({super.key, required this.game});

  final IdleGame game;

  @override
  State<DefeatFadeOverlay> createState() => _DefeatFadeOverlayState();
}

class _DefeatFadeOverlayState extends State<DefeatFadeOverlay> {
  static const Duration _fadeDuration = Duration(milliseconds: 500);

  bool _isBlack = false;

  @override
  void initState() {
    super.initState();
    widget.game.onDefeatFadeOut = _onFadeOut;
    widget.game.onDefeatFadeIn = _onFadeIn;
  }

  // PlayerHitFlashOverlay._safeSetState와 같은 이유(Flame 게임 루프 도중
  // 동기 콜백이 Flutter 빌드 단계와 겹칠 수 있음) — 마이크로태스크로 한
  // 프레임 미룬다.
  void _safeSetState(VoidCallback fn) {
    Future.microtask(() {
      if (mounted) {
        setState(fn);
      }
    });
  }

  void _onFadeOut() => _safeSetState(() => _isBlack = true);

  void _onFadeIn() => _safeSetState(() => _isBlack = false);

  @override
  void dispose() {
    if (identical(widget.game.onDefeatFadeOut, _onFadeOut)) {
      widget.game.onDefeatFadeOut = null;
    }
    if (identical(widget.game.onDefeatFadeIn, _onFadeIn)) {
      widget.game.onDefeatFadeIn = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _isBlack ? 1.0 : 0.0,
        duration: _fadeDuration,
        curve: Curves.easeInOut,
        child: const ColoredBox(color: Colors.black),
      ),
    );
  }
}

class _QuestHudButton extends StatelessWidget {
  const _QuestHudButton();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([MissionManager.instance, AttendanceManager.instance]),
      builder: (context, _) {
        final bool hasClaimableMission = MissionManager.instance.activeMissions
            .any((mission) => mission.isCleared && !mission.isRewardClaimed);
        final bool showBadge = hasClaimableMission || AttendanceManager.instance.hasClaimableReward;

        return GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => const MissionDialog(),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF6C4FCE), width: 1.5),
                ),
                child: const Icon(Icons.assignment, color: Colors.white, size: 22),
              ),
              if (showBadge)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF0F0F17), width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// _QuestHudButton 바로 아래(top: 64)에 놓이는 월드보스 아이콘 — 등장
/// 여부에 따라 테두리/타이머 색이 빨강(등장중)↔회색(대기중)으로 바뀐다.
/// [WorldBossManager]가 1초마다 스스로 notifyListeners()를 부르므로, 이
/// 위젯은 별도 폴링 타이머 없이 [AnimatedBuilder] 구독만으로 실시간
/// 갱신된다.
class _WorldBossHudButton extends StatelessWidget {
  const _WorldBossHudButton();

  String _shortCountdown(Duration duration) {
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
        final Color accent = manager.isActive ? Colors.redAccent : const Color(0xFF6C4FCE);

        return GestureDetector(
          onTap: () => showWorldBossEntryDialog(context),
          // _QuestHudButton과 똑같이 44px 원 하나만 놓고 폭을 자체(shrink-wrap)
          // 크기에 맡긴다 — 예전엔 SizedBox(width: 60)로 감싸 Column의
          // crossAxisAlignment.center가 44px 원을 60px 박스 한가운데로
          // 밀어내는 바람에, 위에 있는 _QuestHudButton(left: 12에 꽉 차는
          // 44px 원)과 세로선이 8px씩 어긋나 보였다.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: 1.5),
                ),
                alignment: Alignment.center,
                child: const Text('🐉', style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(height: 2),
              _OutlinedCountdownText(text: _shortCountdown(manager.timeRemaining)),
            ],
          ),
        );
      },
    );
  }
}

/// 배경(전투 화면의 패럴랙스/몬스터 등 시각적으로 복잡한 배경)에 텍스트가
/// 묻히지 않도록, 굵은 검은 테두리(Stroke) 위에 노란 글자를 겹쳐 그리는
/// 아웃라인 텍스트. `Paint()..style = PaintingStyle.stroke`로 뒤에 테두리용
/// Text를 한 번 깔고, 그 위에 칠(fill) 텍스트를 정확히 겹쳐 그린다 — 여러
/// 방향의 [Shadow]를 흩뿌리는 방식보다 작은 폰트에서도 테두리가 끊기지
/// 않고 또렷하다.
class _OutlinedCountdownText extends StatelessWidget {
  const _OutlinedCountdownText({required this.text});

  final String text;

  static const double _fontSize = 10;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: _fontSize,
            fontWeight: FontWeight.bold,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5
              ..color = Colors.black,
          ),
        ),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.amberAccent,
            fontSize: _fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// Horizontal strip of learned skill-tree nodes, shown just above the
/// upgrade panel.
class SkillTreeQuickBar extends StatelessWidget {
  const SkillTreeQuickBar({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SkillManager.instance,
      builder: (context, _) {
        final List<SkillNode> learnedSkills = SkillManager.instance.skillTree
            .where((node) => node.isLearned)
            .toList();

        if (learnedSkills.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          color: const Color(0xFF1B1B26),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            height: 56,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: learnedSkills.length,
              itemBuilder: (context, index) {
                final SkillNode node = learnedSkills[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _AutoSkillSlot(key: ValueKey(node.id), node: node),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// One skill icon with its own one-shot cooldown countdown: runs from
/// [SkillManager.effectiveCooldown] (node's currentCooldown minus the
/// equipped pet's cooldown-reduction option) down to 0 (scaled by
/// SpeedManager's active speed each tick) and then stops — it does not
/// restart on its own.
class _AutoSkillSlot extends StatefulWidget {
  const _AutoSkillSlot({super.key, required this.node});

  final SkillNode node;

  @override
  State<_AutoSkillSlot> createState() => _AutoSkillSlotState();
}

class _AutoSkillSlotState extends State<_AutoSkillSlot> {
  double _remainingSeconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = SkillManager.instance.effectiveCooldown(widget.node);
    _timer = Timer.periodic(const Duration(milliseconds: 100), _onTick);
  }

  void _onTick(Timer timer) {
    final double delta = 0.1 * SpeedManager.instance.gameSpeedMultiplier;
    bool cooldownJustFinished = false;
    setState(() {
      _remainingSeconds -= delta;
      if (_remainingSeconds <= 0) {
        _remainingSeconds = 0;
        timer.cancel();
        cooldownJustFinished = true;
      }
    });

    // 배속(2x/3x) 버프가 활성화된 동안에는 쿨타임이 돌아온 순간 유저 터치 없이
    // 곧바로 재발동한다 — _useSkill()을 그대로 타므로 데미지 계산/이펙트
    // 렌더링은 수동 발동과 완전히 동일한 경로를 거친다. 버프가 꺼져 있으면
    // 기존처럼 수동 탭을 기다린다.
    if (cooldownJustFinished && SpeedManager.instance.gameSpeedMultiplier > 1) {
      _useSkill();
    }
  }

  void _useSkill() {
    if (!SkillManager.instance.useSkill(widget.node.id)) {
      return;
    }
    _timer?.cancel();
    setState(() {
      _remainingSeconds = SkillManager.instance.effectiveCooldown(widget.node);
    });
    _timer = Timer.periodic(const Duration(milliseconds: 100), _onTick);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SkillNode node = widget.node;
    final bool isOnCooldown = _remainingSeconds > 0;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: isOnCooldown ? null : _useSkill,
      child: Container(
        width: 48,
        height: 48,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF20202C),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: node.element.color, width: 1.2),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(node.element.icon, color: node.element.color, size: 22),
            if (isOnCooldown)
              IgnorePointer(
                child: Container(
                  color: Colors.black54,
                  alignment: Alignment.center,
                  child: Text(
                    _remainingSeconds.ceil().toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
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
          return SingleChildScrollView(
            child: Column(
              children: [
                _UpgradeButton(
                  title: '공격력',
                  level: manager.attackLevel,
                  valueLabel: NumberFormatter.format(manager.attackPower),
                  cost: manager.attackUpgradeCost,
                  gold: manager.gold,
                  icon: Icons.local_fire_department,
                  // ── Mission integration point ─────────────────────
                  // Only report progress when the upgrade actually went
                  // through (i.e. the player could afford it) — a failed
                  // tap shouldn't count towards "N회 강화" missions.
                  onTap: () {
                    if (manager.upgradeAttack()) {
                      MissionManager.instance.updateProgress(ActionType.upgrade, 1);
                    }
                  },
                ),
                const SizedBox(height: 12),
                _UpgradeButton(
                  title: '공격속도',
                  level: manager.attackSpeedLevel,
                  valueLabel: '${manager.effectiveAttackSpeed.toStringAsFixed(2)}/s',
                  cost: manager.speedUpgradeCost,
                  gold: manager.gold,
                  icon: Icons.bolt,
                  onTap: () {
                    if (manager.upgradeAttackSpeed()) {
                      MissionManager.instance.updateProgress(ActionType.upgrade, 1);
                    }
                  },
                ),
                const SizedBox(height: 12),
                _UpgradeButton(
                  title: '크리티컬 확률',
                  level: manager.criticalRateLevel,
                  valueLabel: '${(manager.criticalRate * 100).toStringAsFixed(0)}%',
                  cost: manager.criticalUpgradeCost,
                  gold: manager.gold,
                  icon: Icons.flash_on,
                  onTap: () {
                    if (manager.upgradeCriticalRate()) {
                      MissionManager.instance.updateProgress(ActionType.upgrade, 1);
                    }
                  },
                ),
                const SizedBox(height: 12),
                _UpgradeButton(
                  title: '방어력',
                  level: manager.defenseLevel,
                  valueLabel: NumberFormatter.format(manager.defensePower),
                  cost: manager.defenseUpgradeCost,
                  gold: manager.gold,
                  icon: Icons.shield,
                  onTap: () {
                    if (manager.upgradeDefense()) {
                      MissionManager.instance.updateProgress(ActionType.upgrade, 1);
                    }
                  },
                ),
                const SizedBox(height: 12),
                _UpgradeButton(
                  title: '방어율',
                  level: manager.defenseRateLevel,
                  valueLabel: '${(manager.effectiveDefenseRate * 100).toStringAsFixed(0)}%',
                  cost: manager.defenseRateUpgradeCost,
                  gold: manager.gold,
                  icon: Icons.security,
                  onTap: () {
                    if (manager.upgradeDefenseRate()) {
                      MissionManager.instance.updateProgress(ActionType.upgrade, 1);
                    }
                  },
                ),
                const SizedBox(height: 12),
                _UpgradeButton(
                  title: '회피율',
                  level: manager.evasionRateLevel,
                  valueLabel: '${(manager.effectiveEvasionRate * 100).toStringAsFixed(0)}%',
                  cost: manager.evasionRateUpgradeCost,
                  gold: manager.gold,
                  icon: Icons.directions_run,
                  onTap: () {
                    if (manager.upgradeEvasionRate()) {
                      MissionManager.instance.updateProgress(ActionType.upgrade, 1);
                    }
                  },
                ),
                const SizedBox(height: 12),
                _UpgradeButton(
                  title: '크리티컬 방어율',
                  level: manager.critDefenseRateLevel,
                  valueLabel: '${(manager.effectiveCritDefenseRate * 100).toStringAsFixed(0)}%',
                  cost: manager.critDefenseRateUpgradeCost,
                  gold: manager.gold,
                  icon: Icons.gpp_good,
                  onTap: () {
                    if (manager.upgradeCritDefenseRate()) {
                      MissionManager.instance.updateProgress(ActionType.upgrade, 1);
                    }
                  },
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

