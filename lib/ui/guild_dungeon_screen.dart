import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/idle_game.dart';
import '../managers/skill_manager.dart';
import '../models/active_skill_model.dart';
import 'home_screen.dart' show SkillEffectOverlay, SkillTreeQuickBar;
import 'top_bar.dart';

/// 길드 던전 탭에서 [입장하기]를 누르면 곧장 여기로 진입한다 — 안내
/// 문구뿐인 [GuildDungeonTab]과 달리, 이 화면이 실제 전투 화면이다.
/// 일반 스테이지/던전 전투 화면과 완전히 같은 [IdleGame] + [GameWidget]
/// 구조를 그대로 재사용한다(dungeon_screen.dart의 `_DungeonBattleScreen`/
/// world_boss_battle_screen.dart의 `WorldBossBattleScreen`과 동일한 뼈대).
/// 왼쪽엔 내 캐릭터가, 오른쪽 몬스터 자리엔 길드 던전 전용 색(길드 UI와
/// 통일된 보라색)의 몬스터가 서서 서로 때린다 — [IdleGame]이
/// GameMode.guildDungeon일 때 몬스터를 어떻게 스폰/보상 지급하는지는
/// idle_game.dart의 `_activateDungeon`/`_damageDungeonMonster`를 참고
/// (별도 입장 티켓/제한은 요구사항에 없어 두지 않았다).
class GuildDungeonScreen extends StatefulWidget {
  const GuildDungeonScreen({super.key});

  @override
  State<GuildDungeonScreen> createState() => _GuildDungeonScreenState();
}

class _GuildDungeonScreenState extends State<GuildDungeonScreen> {
  late final IdleGame _game;
  late final Timer _ticker;
  bool _resultShown = false;

  // 이 화면 진입 전 스킬 데미지가 향하던 곳(보통 홈 화면의 IdleGame) —
  // dispose에서 복원해야 길드 던전을 나간 뒤에도 스킬이 이미 사라진
  // 던전용 IdleGame을 계속 가리키는 일이 없다.
  void Function(double damage)? _previousDamageHandler;

  // 광역기(active_aoe) 낙하 이펙트/데미지도 damageHandler와 같은 이유로
  // 저장해뒀다가 복원한다(dungeon_screen.dart의 _DungeonBattleScreen과
  // 동일한 관례) — 안 그러면 길드 던전을 나간 뒤 홈 화면에서 광역기를
  // 써도 이미 dispose된 이 IdleGame의 콜백이 계속 남아 있어(1) 아무
  // 효과가 없고 (2) 이 dispose된 인스턴스가 클로저를 통해 계속 메모리에
  // 붙잡혀 있게 된다.
  void Function(ActiveSkill skill, double damage)? _previousActiveSkillCast;

  @override
  void initState() {
    super.initState();
    _game = IdleGame();
    _game.onDungeonComplete = _handleDungeonComplete;
    _game.startDungeon(GameMode.guildDungeon);
    _ticker = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => setState(() {}),
    );

    _previousDamageHandler = SkillManager.instance.damageHandler;
    SkillManager.instance.damageHandler = _game.applySkillDamage;
    _previousActiveSkillCast = SkillManager.instance.onActiveSkillCast;
    SkillManager.instance.onActiveSkillCast = _game.castActiveSkill;
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
    // EquipmentManager 리스너를 해제하지 않으면 길드 던전에 들어갔다 나올
    // 때마다 계속 쌓인다.
    _game.detachListeners();
    super.dispose();
  }

  /// 던전 공용 콜백([IdleGame.onDungeonComplete])을 통해 몬스터를 처치하는
  /// 순간(성공) 또는 60초 타임아웃(실패) 시점에 호출된다 — 골드/보석/길드
  /// 주화는 [IdleGame._damageDungeonMonster]가 처치 시점에 이미 실제로
  /// 지급을 끝낸 상태이고, 여기 넘어오는 값들은 결과 팝업 표시용이다.
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
    _resultShown = true;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showResultDialog(
        success: success,
        goldReward: goldReward,
        gemReward: gemReward,
        guildCoinReward: guildCoinReward,
      ),
    );
  }

  void _showResultDialog({
    required bool success,
    required int goldReward,
    required int gemReward,
    required int guildCoinReward,
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            success ? '길드 던전 클리어!' : '클리어 실패',
            style: TextStyle(
              color: success ? Colors.greenAccent : Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (success) ...[
                if (goldReward > 0)
                  Text(
                    '획득 골드: $goldReward G',
                    style: const TextStyle(color: Colors.white70),
                  ),
                if (gemReward > 0)
                  Text(
                    '획득 보석: $gemReward 💎',
                    style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                  ),
                if (guildCoinReward > 0)
                  Text(
                    '길드 주화 +$guildCoinReward개',
                    style: const TextStyle(
                      color: Color(0xFF6C4FCE),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ] else
                const Text(
                  '제한 시간 안에 몬스터를 처치하지 못했습니다. 다시 도전해보세요!',
                  style: TextStyle(color: Colors.white70),
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
                    const Align(
                      alignment: Alignment.center,
                      child: Text(
                        '길드 던전',
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

/// 길드 던전 탭 — [GuildMainScreen] 하단 탭 중 하나로 곧장 렌더링된다.
/// 탭에 들어서자마자 [GameWidget]/전투를 바로 얹지 않고 안내 문구 +
/// [입장하기] 버튼만 보여준다 — 그렇지 않으면 다른 탭을 구경하다 다시
/// 이 탭으로 돌아올 때마다(TabBarView는 탭을 바꿔도 위젯을 계속 살려
/// 두므로) 매번 새 IdleGame 인스턴스가 백그라운드에서 만들어져 있는 등
/// 예상 밖의 상태가 쌓인다 — 실제 입장은 명시적인 버튼 탭으로 새
/// [GuildDungeonScreen]을 push할 때만 이뤄지게 한다.
class GuildDungeonTab extends StatelessWidget {
  const GuildDungeonTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.castle, color: Color(0xFF6C4FCE), size: 56),
            const SizedBox(height: 16),
            const Text(
              '길드 던전에 도전해서\n골드·보석·길드 주화를 획득하세요!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const GuildDungeonScreen()),
              ),
              icon: const Icon(Icons.sports_kabaddi),
              label: const Text('입장하기'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C4FCE),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
