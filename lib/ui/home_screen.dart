import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/idle_game.dart';
import '../managers/attendance_manager.dart';
import '../managers/battle_pass_manager.dart';
import '../managers/equipment_manager.dart';
import '../managers/game_manager.dart';
import '../managers/mailbox_manager.dart';
import '../managers/mission_manager.dart';
import '../managers/prestige_manager.dart';
import '../managers/quest_manager.dart';
import '../managers/skill_manager.dart';
import '../managers/speed_manager.dart';
import '../managers/title_manager.dart';
import '../managers/tutorial_manager.dart';
import '../managers/world_boss_manager.dart';
import '../models/active_skill_model.dart';
import '../models/equipment.dart';
import '../models/mission_model.dart';
import '../models/skill_model.dart';
import '../models/title_model.dart';
import '../utils/number_formatter.dart';
import '../widgets/center_toast.dart';
import '../widgets/guide_mission_banner.dart';
import '../widgets/title_badge.dart';
import 'battle_pass_screen.dart';
import 'mailbox_screen.dart';
import 'mission_dialog.dart';
import 'potion_quick_slot.dart';
import 'quest_screen.dart';
import 'ranking_screen.dart';
import 'rebirth_confirm_dialog.dart';
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
    // 바닥 텍스처가 비동기로 도착해 IdleGame이 캐릭터/몬스터 Y좌표를
    // 바로잡은 직후(IdleGame._loadChapterTheme 문서 참고) _BattleView를
    // 다시 그려서, 그 안의 HP 바 위치도 같은 자리로 맞춘다 — _BattleView의
    // LayoutBuilder는 리사이즈 때만 다시 빌드되므로, 이 신호가 없으면
    // 텍스처가 도착해도 HP 바만 예전 자리에 계속 멈춰 있는다.
    _idleGame.onGroundThemeReady = () {
      if (mounted) {
        setState(() {});
      }
    };
  }

  @override
  void dispose() {
    if (identical(
      WorldBossManager.instance.onBossAppeared,
      _onWorldBossAppeared,
    )) {
      WorldBossManager.instance.onBossAppeared = null;
    }
    // _idleGame은 이 State가 단독으로 소유한다(WorldBossManager.instance와
    // 달리 공유 싱글턴이 아니다) — 다른 인스턴스가 덮어썼을 리 없으니
    // identical 체크 없이 바로 지운다.
    _idleGame.onGroundThemeReady = null;
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
                // 초보자 온보딩용 메인 가이드 미션 배너 — 화면 최상단(퀘스트
                // HUD 아이콘이 있는 배틀 뷰보다 위)에 고정, 시퀀스를 전부
                // 끝내면(GuideMissionManager.isAllCompleted) 스스로 아무것도
                // 그리지 않는다.
                const GuideMissionBanner(),
                Expanded(
                  flex: 1,
                  child: KeyedSubtree(
                    key: TutorialManager.battleViewKey,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () {
                        if (TutorialManager.instance.currentStep == 0) {
                          TutorialManager.instance.advance();
                        }
                      },
                      child: _BattleView(game: _idleGame, manager: _manager),
                    ),
                  ),
                ),
                const SkillTreeQuickBar(),
                const ActiveSkillQuickBar(),
                Expanded(flex: 1, child: _UpgradeView(manager: _manager)),
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
    // [퍼포먼스 감사 2026-08-21] 예전엔 이 전체 서브트리(LayoutBuilder +
    // GameWidget + HUD 버튼들 + Stack)가 [AnimatedBuilder]에 감싸여
    // 있어서, 전투 중 몬스터를 때릴 때마다(GameManager.notifyListeners,
    // 초당 여러 번) 여기 아래 전부가 매번 다시 빌드됐다 — 그런데 실제로
    // `manager`를 읽어서 프레임마다 달라지는 건 HP 바 두 개/챕터 라벨/
    // 보스 타이머, 딱 4곳뿐이고 나머지(GameWidget, HUD 버튼, 레이아웃
    // 계산)는 화면 크기가 바뀔 때만 달라진다. 그래서 이 바깥 래퍼는
    // 이제 [LayoutBuilder]뿐이고(그마저도 리사이즈 때만 다시 빌드),
    // `manager`를 실제로 구독하는 건 아래 4개의 작은 위젯
    // ([_PlayerHpBar]/[_ChapterLabel]/[_BossTimerBadge]/
    // [_MonsterHpBar]) 각각이 자기 몫만 [AnimatedBuilder]로 감싸서
    // 진행한다. Stack의 Positioned/여백/Z-순서/시각적 결과물은 전혀
    // 바뀌지 않았다 — 무엇이 언제 다시 빌드되는지만 좁혔다.
    // [주의: width: double.infinity] HomeScreen의 바깥 Column이
    // crossAxisAlignment를 stretch로 지정하지 않아서(기본값 center), 이
    // 위젯이 받는 가로 제약은 "느슨함"(minWidth: 0)이다 — 세로는
    // Expanded가 강제로 꽉 채우지만(tight) 가로는 그렇지 않다. 그런데 아래
    // Stack엔 [_BossTimerBadge]처럼 Positioned로 안 감싼 채(자기 자신의
    // build()가 조건부로 Positioned를 반환하는 패턴이라 그렇다) 보스전이
    // 아닐 때 SizedBox.shrink()(크기 0)를 그대로 돌려주는 자식이 있다 —
    // Flutter의 Stack은 "포지션 안 된 자식이 하나라도 있으면 그 자식들
    // 크기에 맞춰(=제약의 최솟값부터) 스스로 크기를 정한다"는 규칙이 있어,
    // 느슨한 가로 제약(최솟값 0) + 크기 0짜리 비-Positioned 자식이 겹치면
    // Stack의 가로폭이 통째로 0이 돼 버린다 — 실측: LayoutBuilder는
    // maxWidth=1085를 받는데 그 아래 GameWidget/Flame이 실제로 받는 크기는
    // size=[0, 373.3](세로만 정상)이었다. width: double.infinity로 이
    // Container 자체를 "가능한 최대 폭"으로 강제하면, 안쪽 LayoutBuilder는
    // 항상 꽉 찬(tight) 가로 제약을 받으므로 어떤 자식이 뭘 반환하든 이
    // 문제가 다시 생기지 않는다([_BossTimerBadge]도 별도로 방어해 뒀다).
    return Container(
      width: double.infinity,
      color: const Color(0xFF0F0F17),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // IdleGame.playerXRatio와 반드시 같은 값을 써야 한다 — 여기
          // (Flutter 오버레이: HP 바/펫 아이콘)와 Flame 쪽
          // (PlayerAnimationComponent/RectangleComponent 몬스터)이 서로
          // 다른 비율을 쓰면 해상도가 바뀔 때마다 둘이 어긋난다.
          final double playerX = constraints.maxWidth * IdleGame.playerXRatio;
          // [주의] 예전엔 여기서도 그냥 `constraints.maxHeight *
          // IdleGame.groundYRatio`(고정 비율)를 썼다 — 그런데 실제
          // 바닥 텍스처가 그려지는 위치는 텍스처 원본 가로세로비 +
          // 화면 가로세로비로 매번 다시 계산되는 별개의 값이라, 특정
          // 화면 비율에서 우연히 맞아떨어졌을 뿐이었다. 앱을 폰 폭
          // (500px)으로 레터박스 처리하며 화면 비율이 바뀌자 캐릭터가
          // 바닥에서 붕 뜬 것처럼 어긋났다(실측 확인됨). IdleGame쪽과
          // 똑같이 [IdleGame.computeGroundY]를 그대로 호출해 실제 바닥
          // 텍스처 위치를 직접 읽어오도록 고쳤다 — game.size를 읽는
          // 대신(IdleGame.computeBattleStopX 문서와 같은 이유로) 이
          // LayoutBuilder의 constraints를 그대로 넘긴다.
          final double playerY = IdleGame.computeGroundY(
            groundSpriteSize: game.groundSpriteSize,
            screenSize: Vector2(constraints.maxWidth, constraints.maxHeight),
          );
          // PlayerAnimationComponent.boxSize와 반드시 같은 값을 써야
          // 한다 — 상자 크기가 바뀌면(56 → 180 → 120 → 60 → 84로 조정돼
          // 온 이력) 이 HP 바 위치도 함께 따라가지 않으면 캐릭터
          // 머리와 겹쳐 보인다. 상수를 직접 참조하므로(하드코딩된
          // 숫자가 아니라) boxSize가 바뀌는 순간 이 위치도 자동으로
          // 따라간다.
          const double spriteSize = PlayerAnimationComponent.boxSize;
          // 머리 꼭대기(발밑에서 얼마나 위인지)는 상자 전체 높이가
          // 아니라 표준 캔버스 규격(800x720, 콘텐츠 50%)에서 유도한
          // [contentTopHeightRatio]로 계산해야 한다 — 상자 전체
          // (spriteSize)를 그대로 쓰면 공격 이펙트용 여백까지 캐릭터
          // 키에 포함시켜, 실제 머리보다 훨씬 위(텅 빈 여백 위)에
          // 체력바가 뜬다.
          final double headTopY =
              playerY -
              spriteSize * PlayerAnimationComponent.contentTopHeightRatio;
          // 머리에 딱 붙지 않도록 살짝 여유를 둔다.
          const double playerHpBarBreathingRoom = 12;
          // 체력바 블록 자체의 높이(진행바 8 + 간격 2 + "200/200" 텍스트
          // 한 줄 약 13, 아래 Column 구성과 맞춘 값) — Positioned.top은
          // 이 블록의 "위쪽 끝"을 가리키고 블록은 거기서부터 아래로
          // 그려지므로, top을 머리 바로 위 선에만 맞추면 블록 자체가
          // 아래로 자라나며 머리와 겹친다. 블록 높이만큼 한 번 더
          // 끌어올려야 블록 전체(진행바+텍스트)가 머리 위 여백에 뜬다.
          const double playerHpBarBlockHeight = 8 + 2 + 13;
          // 위 계산(contentTopHeightRatio 기반 이론값)만으로는 실제
          // 화면에서 여전히 머리와 겹쳐 보인다는 피드백을 받아, 눈으로
          // 확인 가능한 여유가 생기도록 추가로 더 끌어올리는 보정치 —
          // 이론적으로 유도한 값이 아니라 실측 피드백에 따라 수동으로
          // 얹은 값이다.
          const double playerHpBarExtraLift = 24;

          // [주의] 예전엔 "몬스터는 항상 화면 가로 중앙에서 싸운다"고
          // 가정해 여기서 그냥 constraints.maxWidth / 2를 썼다 — 실제
          // 전투 위치(IdleGame._battleStopX)는 "플레이어 위치 +
          // 장착 캐릭터의 사거리"라 화면 정중앙과는 별개의 값이다. 좁은
          // 모바일 폭에서는 이 캐릭터의 사거리가 우연히 화면 폭의
          // 절반과 비슷해 어긋난 티가 잘 안 났을 뿐 — 화면이 넓어지거나
          // 사거리가 다른 캐릭터를 장착하면 HP 바가 실제 몬스터 자리와
          // 완전히 따로 놀았다(실측: 몬스터는 화면 왼쪽 근처인데 HP
          // 바만 정중앙 근처에 떠 있었다).
          //
          // [주의: game.size를 직접 읽지 않는다] 처음엔 IdleGame에 이
          // 값을 그대로 노출하는 공개 getter를 두고 여기서 읽게 했었다
          // — 그런데 이 build()(HP 바 포함)는 Flame이 GameWidget의 실제
          // 레이아웃을 아직 못 받은 시점에도 먼저 실행될 수 있어서, 그
          // 순간 Game.size를 읽으면 hasLayout이 아직 false라 "size is
          // not ready yet" 어서션이 그대로 터졌다(실측: 레드 스크린).
          // 이 LayoutBuilder의 constraints는 그런 타이밍 문제가 없으므로
          // (항상 유효), IdleGame.computeBattleStopX(순수 함수, size를
          // 전혀 읽지 않는다)에 constraints.maxWidth를 직접 넘겨 같은
          // 공식을 여기서 독자적으로 계산한다 — Positioned.fill로 감싼
          // GameWidget이 결국 받게 될 크기와 이 constraints가 항상
          // 같으므로(_BattleView의 Stack 안에 함께 있다), 결과는
          // game.size를 읽었을 때와 완전히 동일하면서 레이스 컨디션만
          // 없앤다.
          final CharacterClass equippedCharacterClass =
              EquipmentManager.instance.equippedItems[EquipType.character]?.classType ??
              CharacterClass.warrior;
          final double monsterCenterX = IdleGame.computeBattleStopX(
            playerX: playerX,
            attackRange: equippedCharacterClass.attackRange,
            screenWidth: constraints.maxWidth,
          );
          final double monsterTopY = playerY - IdleGame.monsterSize;
          final double monsterHpBarWidth = IdleGame.monsterSize * 1.2;

          // 기존 80px는 캐릭터 체형(60px 상자) 대비 길어 보인다는
          // 피드백으로 약 19% 줄였다.
          const double playerHpBarWidth = 65;

          // 장착 중인 칭호(PlayerTitle) — 체력바보다 한 단계 더 위, 머리
          // 바로 위에 띄운다(요구사항: "내 캐릭터 머리 위에 장착 중인
          // 칭호를 띄워줘"). 폭이 이름 길이에 따라 달라지므로 체력바와
          // 달리 고정 폭을 주지 않고, 최대 폭 안에서 내용 크기만큼만
          // 차지하게 한 뒤 [playerX] 기준으로 가운데 정렬한다.
          const double titleBadgeHeight = 20;
          const double titleBadgeGap = 4;
          const double titleBadgeMaxWidth = 140;
          // 화면 폭이 titleBadgeMaxWidth/playerHpBarWidth보다 좁아지는
          // 순간(리사이즈 도중 과도기 프레임 등) 아래 clamp의 상한이
          // 하한(0)보다 작아져 ArgumentError로 이 서브트리 전체가
          // 크래시했었다 — 상한 자체를 먼저 0 이상으로 고정해 둔다.
          final double titleBadgeLeftMax =
              constraints.maxWidth - titleBadgeMaxWidth < 0
              ? 0.0
              : constraints.maxWidth - titleBadgeMaxWidth;
          final double playerHpBarLeftMax =
              constraints.maxWidth - playerHpBarWidth < 0
              ? 0.0
              : constraints.maxWidth - playerHpBarWidth;
          final double titleBadgeTop =
              headTopY -
              playerHpBarBreathingRoom -
              playerHpBarBlockHeight -
              playerHpBarExtraLift -
              titleBadgeHeight -
              titleBadgeGap;

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
              if (TitleManager.instance.equippedTitle
                  case final PlayerTitle equippedTitle)
                Positioned(
                  left: (playerX - titleBadgeMaxWidth / 2).clamp(
                    0.0,
                    titleBadgeLeftMax,
                  ),
                  top: titleBadgeTop,
                  width: titleBadgeMaxWidth,
                  child: Center(
                    child: TitleBadge(
                      title: equippedTitle,
                      height: titleBadgeHeight,
                    ),
                  ),
                ),
              Positioned(
                left: (playerX - playerHpBarWidth / 2).clamp(
                  0.0,
                  playerHpBarLeftMax,
                ),
                // 캐릭터가 바닥에 서 있으므로 HP 바는 발밑이 아니라
                // 머리 위에 띄운다 — 블록 높이(playerHpBarBlockHeight)
                // 만큼 더 끌어올려야 블록의 "아래쪽 끝"이 머리 위
                // 여유선에 맞고, 그 위에 [playerHpBarExtraLift]만큼
                // 한 번 더 끌어올려 시원한 여백을 확보한다(위 주석
                // 참고).
                top:
                    headTopY -
                    playerHpBarBreathingRoom -
                    playerHpBarBlockHeight -
                    playerHpBarExtraLift,
                child: SizedBox(
                  width: playerHpBarWidth,
                  child: _PlayerHpBar(manager: manager),
                ),
              ),
              const Positioned(top: 12, left: 12, child: _QuestHudButton()),
              const Positioned(top: 64, left: 12, child: _WorldBossHudButton()),
              const Positioned(top: 116, left: 12, child: _PrestigeHudButton()),
              const Positioned(top: 168, left: 12, child: _RankingHudButton()),
              // 예전엔 여기(top:220)에 배틀패스 버튼이 있었지만, 그건
              // 물약 슬롯 왼쪽 Row로 옮겨서 이 자리가 비었다 — 대신
              // 상단 앱바(main.dart)에서 빠진 일일 퀘스트 진입점을
              // 옮겨 왔다(요구사항: "프로필 옆... 스크롤 아이콘은 삭제").
              const Positioned(
                top: 220,
                left: 12,
                child: _DailyQuestHudButton(),
              ),
              // 상단 AppBar의 보석/코인 재화 표시(main.dart) 바로 아래,
              // 화면 우측 상단에 위치한 유틸리티 버튼 묶음. 원래 상단
              // AppBar에 있던 우편함/배틀패스 버튼을 이리로 옮기면서,
              // 기존 물약 퀵슬롯 바로 왼쪽에 나란히 붙였다.
              const Positioned(
                top: 12,
                right: 12,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MailboxHudButton(),
                    SizedBox(width: 8),
                    _BattlePassHudButton(),
                    SizedBox(width: 8),
                    PotionQuickSlot(),
                  ],
                ),
              ),
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // [주의] 예전엔 여기서 _ChapterLabel을 Flexible 없이
                      // 그냥 넣었다 — 화면 폭이 넓을 땐(원래 데스크톱
                      // 브라우저 전체 폭) 여유가 충분해 문제가 없었지만,
                      // 앱 전체를 폰 폭(500px)으로 좁히고 나니 챕터
                      // 라벨의 지역명·챕터명 부제("N지역 · ○○○")가 길어
                      // 질 때 Row가 감당 못 하고 오른쪽으로 삐져나갔다
                      // (RenderFlex overflow, 실측 확인됨). Flexible로
                      // 감싸면 필요할 때 줄어들고, _ChapterLabel 안쪽
                      // Text들에 ellipsis를 달아 잘린 티만 나고 절대
                      // 넘치지 않는다.
                      Flexible(child: _ChapterLabel(manager: manager)),
                      const SizedBox(width: 8),
                      _HardModeToggleButton(manager: manager),
                    ],
                  ),
                ),
              ),
              // isBossStage가 false인 동안은 [_BossTimerBadge]가 내부에서
              // SizedBox.shrink()를 돌려주므로, 예전 `if (manager
              // .isBossStage) Positioned(...)`와 똑같이 화면에는 아무것도
              // 그려지지 않는다 — 다만 이제 Stack.children 목록 자체는
              // 리사이즈 때만 다시 만들어지고, 보이고/숨는 판단은 이
              // 위젯이 매 틱마다 스스로 다시 한다.
              _BossTimerBadge(manager: manager),
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
                child: _MonsterHpBar(manager: manager),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 플레이어 HP 바(진행바+수치 텍스트)만 담당 — [_BattleView]가 통째로
/// [manager]를 구독하던 시절엔 이 텍스트 하나 바뀌자고 GameWidget/HUD
/// 버튼까지 매 틱 다시 빌드됐다. 이제 이 작은 서브트리만
/// [AnimatedBuilder]로 [manager]를 구독한다 — 표시 결과(진행바 색/두께,
/// 텍스트 스타일)는 예전과 완전히 동일하다.
class _PlayerHpBar extends StatelessWidget {
  const _PlayerHpBar({required this.manager});

  final GameManager manager;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        final double safeMaxHp = manager.maxHp <= 0 ? 0 : manager.maxHp;
        final double playerHpRatio = safeMaxHp <= 0
            ? 0
            : (manager.currentHp / safeMaxHp).clamp(0.0, 1.0);
        return Column(
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
              '${NumberFormatter.format(manager.currentHp.clamp(0, safeMaxHp))} / ${NumberFormatter.format(manager.maxHp)}',
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ],
        );
      },
    );
  }
}

/// 하드 모드 전용 강조 색 — [_ChapterLabel]/[_HardModeToggleButton]이
/// 공유한다(요구사항: "하드 모드일 때는 UI... 붉은색 계열로 바꿔서
/// 시각적으로 위험해 보이게").
const Color _hardModeRed = Color(0xFFFF1744);

/// 챕터-스테이지 라벨("3-12" / "3-12 보스!" / 하드 모드면 "⚠️ 하드
/// 100-3") — [manager.chapter]/[manager.stage]/[manager.isBossStage]/
/// [manager.isHardMode]가 바뀔 때만 다시 그려진다. 정상 모드에서는 pill
/// 아래에 지역명·챕터명(예: "3지역 · 폐허가 된 왕도 외곽")을 함께
/// 보여준다(요구사항: "각 챕터 진입 시 UI에 표시되는 지역명과 챕터명") —
/// 하드 모드는 챕터/지역 개념이 없는 구간이라 이 줄을 생략한다.
class _ChapterLabel extends StatelessWidget {
  const _ChapterLabel({required this.manager});

  final GameManager manager;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        final bool hard = manager.isHardMode;
        final Color textColor = hard
            ? _hardModeRed
            : (manager.isBossStage ? Colors.redAccent : Colors.white);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
            border: hard
                ? Border.all(color: _hardModeRed.withValues(alpha: 0.6))
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                hard
                    ? '⚠️ 하드 ${manager.chapter}-${manager.stage}'
                    : (manager.isBossStage
                          ? '${manager.chapter}-${manager.stage} 보스!'
                          : '${manager.chapter}-${manager.stage}'),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              if (!hard) ...[
                const SizedBox(height: 2),
                Text(
                  '${manager.regionName} · ${manager.chapterName}',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// 하드 모드 해금 후에만 나타나는 [일반 ↔ 하드] 전환 버튼 —
/// [_BossTimerBadge]와 같은 자기-숨김 패턴([manager.hardModeUnlocked]가
/// false면 [SizedBox.shrink]). 탭하면 [GameManager.setHardMode]가 즉시
/// (몬스터/체력 포함) 다른 모드로 리로드한다.
class _HardModeToggleButton extends StatelessWidget {
  const _HardModeToggleButton({required this.manager});

  final GameManager manager;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        if (!manager.hardModeUnlocked) {
          return const SizedBox.shrink();
        }
        final bool hard = manager.isHardMode;
        return GestureDetector(
          onTap: () => manager.setHardMode(!hard),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: hard
                  ? _hardModeRed.withValues(alpha: 0.25)
                  : Colors.black54,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: hard ? _hardModeRed : Colors.white38),
            ),
            child: Text(
              hard ? '하드 → 일반' : '일반 → 하드',
              style: TextStyle(
                color: hard ? _hardModeRed : Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 보스 스테이지에서만 뜨는 남은 시간 배지 — 매 틱 카운트다운되므로 가장
/// 자주 다시 그려지는 위젯이다.
///
/// [주의] [manager.isBossStage]가 false일 때 예전엔 그냥
/// `SizedBox.shrink()`를 돌려줬는데, 이 위젯은(자기 자신의 build()가
/// 조건부로 Positioned를 반환해야 해서) [_BattleView]의 Stack에
/// Positioned로 안 감싼 채 직접 자식으로 들어가 있다 — 그러면
/// `SizedBox.shrink()`가 Stack의 "포지션 안 된(non-positioned)" 자식이
/// 되고, Flutter의 Stack은 포지션 안 된 자식이 하나라도 있으면 그 자식들
/// 크기에 맞춰(제약의 최솟값부터) 스스로 크기를 정한다 — 가로 제약이
/// 느슨한 상황(HomeScreen의 Column이 stretch가 아니라 기본 center라
/// minWidth: 0)과 겹치면 Stack 전체의 가로폭이 0으로 무너져 버렸다
/// (실측: GameWidget이 실제로 받은 크기가 `size=[0, 373.3]` — 세로만
/// 정상이고 가로가 0이라 전투 화면 전체가 까맣게 보이던 원인). 지금은
/// 숨김 상태에서도 크기 0짜리 [Positioned]를 돌려줘서, 이 위젯이 절대
/// "포지션 안 된 자식"이 되지 않도록 막는다(그 자체로 화면상 결과는
/// 전과 동일 — 어차피 크기 0이라 아무것도 안 보인다).
class _BossTimerBadge extends StatelessWidget {
  const _BossTimerBadge({required this.manager});

  final GameManager manager;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        if (!manager.isBossStage) {
          return const Positioned(width: 0, height: 0, child: SizedBox.shrink());
        }
        return Positioned(
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
        );
      },
    );
  }
}

/// 몬스터 HP 바(진행바+수치 텍스트) — [_PlayerHpBar]와 같은 이유로 분리.
class _MonsterHpBar extends StatelessWidget {
  const _MonsterHpBar({required this.manager});

  final GameManager manager;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        final double safeMonsterMaxHp = manager.monsterMaxHp <= 0
            ? 0
            : manager.monsterMaxHp;
        final double hpRatio = safeMonsterMaxHp <= 0
            ? 0
            : (manager.monsterHp / safeMonsterMaxHp).clamp(0.0, 1.0);
        return Column(
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
              '${NumberFormatter.format(manager.monsterHp.clamp(0, safeMonsterMaxHp))} / ${NumberFormatter.format(manager.monsterMaxHp)}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                shadows: [Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
          ],
        );
      },
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
                          border: Border.all(
                            color: node.element.color,
                            width: 3,
                          ),
                        ),
                        child: Icon(
                          node.element.icon,
                          color: node.element.color,
                          size: 48,
                        ),
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
      animation: Listenable.merge([
        MissionManager.instance,
        AttendanceManager.instance,
      ]),
      builder: (context, _) {
        final bool hasClaimableMission = MissionManager.instance.activeMissions
            .any((mission) => mission.isCleared && !mission.isRewardClaimed);
        final bool showBadge =
            hasClaimableMission ||
            AttendanceManager.instance.hasClaimableReward;

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
                  border: Border.all(
                    color: const Color(0xFF6C4FCE),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.assignment,
                  color: Colors.white,
                  size: 22,
                ),
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
                      border: Border.all(
                        color: const Color(0xFF0F0F17),
                        width: 1.5,
                      ),
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
        final Color accent = manager.isActive
            ? Colors.redAccent
            : const Color(0xFF6C4FCE);

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
              _OutlinedCountdownText(
                text: _shortCountdown(manager.timeRemaining),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 환생(프레스티지) 진입 버튼 — [_WorldBossHudButton] 바로 아래(같은 44px
/// 원 규격)에 놓인다. 아직 최소 챕터([PrestigeManager
/// .minChapterToPrestige])에 도달하지 못했어도 숨기지 않고 회색으로
/// "잠김" 상태를 보여준다 — 기능 자체를 미리 알려줘야 유저가 그 챕터까지
/// 갈 목표가 생긴다(완전히 숨기면 이 기능이 있는지조차 모른다). 조건을
/// 채운 순간(=[PrestigeManager.canPrestige])에는 테두리/아이콘이 보라색
/// 강조색으로 바뀌는 것과 별개로, [_DailyQuestHudButton]의 "수령 가능"
/// 빨간 점과 같은 자리에 초록 점 배지를 띄워 "지금 환생할 수 있다"는
/// 신호를 한눈에 놓치지 않게 한다.
class _PrestigeHudButton extends StatelessWidget {
  const _PrestigeHudButton();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        PrestigeManager.instance,
        GameManager.instance,
      ]),
      builder: (context, _) {
        final PrestigeManager prestige = PrestigeManager.instance;
        final bool ready = prestige.canPrestige;
        final Color accent = ready ? const Color(0xFF6C4FCE) : Colors.white24;

        return GestureDetector(
          onTap: () => showRebirthConfirmDialog(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
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
                    child: Text(
                      '⚡',
                      style: TextStyle(fontSize: 22, color: accent),
                    ),
                  ),
                  if (ready)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.greenAccent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF0F0F17),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (prestige.rebirthStones > 0) ...[
                const SizedBox(height: 2),
                _OutlinedCountdownText(text: '${prestige.rebirthStones}P'),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// 명예의 전당(랭킹) 진입 버튼 — [_PrestigeHudButton] 바로 아래(같은 44px
/// 원 규격)에 놓인다. 항상 같은 색(잠금 상태 없음)으로 표시한다 — 챕터
/// 진행도와 무관하게 누구나 바로 랭킹을 확인할 수 있어야 하기 때문.
class _RankingHudButton extends StatelessWidget {
  const _RankingHudButton();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showRankingScreen(context),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
        ),
        alignment: Alignment.center,
        child: const Text('🏆', style: TextStyle(fontSize: 20)),
      ),
    );
  }
}

/// 일일 퀘스트 진입 버튼 — [_RankingHudButton] 바로 아래(같은 44px 원
/// 규격)에 놓인다. 원래 상단 앱바(옛 `DailyQuestHudButton`, main.dart)에
/// 있었지만, 앱바 개편(요구사항: "프로필 → 배속 → 총 전투력 → 골드 →
/// 보석"만 남기기)으로 이 자리로 옮겨오면서 다른 HUD 버튼들과 같은 원형
/// 스타일로 새로 만들었다. 수령 가능한 (배틀패스) 퀘스트가 있으면
/// [_BattlePassHudButton]과 같은 빨간 점 배지를 띄운다.
class _DailyQuestHudButton extends StatelessWidget {
  const _DailyQuestHudButton();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: QuestManager.instance,
      builder: (context, _) {
        final bool hasClaimable = QuestManager.instance.hasClaimableQuest;

        return GestureDetector(
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const QuestScreen())),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF4F8FE0),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: const Text('📜', style: TextStyle(fontSize: 20)),
              ),
              if (hasClaimable)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0F0F17),
                        width: 1.5,
                      ),
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

/// 배틀패스 진입 버튼 — [_RankingHudButton] 바로 아래(같은 44px 원
/// 규격)에 놓인다. 지금 레벨에서 아직 안 받은 보상(무료든 프리미엄이든)이
/// 하나라도 있으면 [_QuestHudButton]과 같은 빨간 점 배지를 띄운다.
class _BattlePassHudButton extends StatelessWidget {
  const _BattlePassHudButton();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: BattlePassManager.instance,
      builder: (context, _) {
        final BattlePassManager manager = BattlePassManager.instance;
        final bool hasClaimable = manager.rewardTrack.any(
          (tier) =>
              manager.canClaim(tier.level, premium: false) ||
              manager.canClaim(tier.level, premium: true),
        );

        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const BattlePassScreen()),
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
                  border: Border.all(
                    color: const Color(0xFF6C4FCE),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: const Text('🎫', style: TextStyle(fontSize: 20)),
              ),
              if (hasClaimable)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0F0F17),
                        width: 1.5,
                      ),
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

/// 우편함 진입 버튼 — 원래 상단 AppBar([main.dart])에 있던 [MailboxHudButton]을
/// 인게임 화면 쪽으로 옮기면서, [_BattlePassHudButton]과 같은 44px 원 규격에
/// 맞춰 새로 만들었다. 수령 가능한 우편이 있으면 같은 빨간 점 배지를 띄운다.
class _MailboxHudButton extends StatelessWidget {
  const _MailboxHudButton();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: MailboxManager.instance,
      builder: (context, _) {
        final bool hasUnclaimed = MailboxManager.instance.hasUnclaimedMail;

        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const MailboxScreen()),
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
                  border: Border.all(
                    color: const Color(0xFF6C4FCE),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: const Text('✉️', style: TextStyle(fontSize: 20)),
              ),
              if (hasUnclaimed)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0F0F17),
                        width: 1.5,
                      ),
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

/// 장착된 액티브 스킬(DB 기반 광역기/버프기, 최대
/// [SkillManager.maxEquippedActiveSkills]개)을 탭해서 쓰는 HUD 슬롯 —
/// 위의 [SkillTreeQuickBar](쿨타임이 돌아오면 배속 중 자동 재발동)와 달리
/// 매번 유저가 직접 눌러야 발동하고, 쿨타임은 숫자 대신 원형 게이지로
/// 채워진다([_ActiveSkillSlot] 참고).
class ActiveSkillQuickBar extends StatelessWidget {
  const ActiveSkillQuickBar({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SkillManager.instance,
      builder: (context, _) {
        final List<ActiveSkill> equipped =
            SkillManager.instance.equippedActiveSkills;

        if (equipped.isEmpty) {
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
              itemCount: equipped.length,
              itemBuilder: (context, index) {
                final ActiveSkill skill = equipped[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _ActiveSkillSlot(
                    key: ValueKey(skill.id),
                    skillId: skill.id,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// 액티브 스킬 하나의 탭-발동 슬롯 — 0.1초마다 다시 그려 원형 게이지가
/// 실시간으로 차오르는 것처럼 보이게 한다([_AutoSkillSlot]과 같은 폴링
/// 방식이지만, 쿨타임이 끝나도 자동으로 재발동하지 않고 다음 탭을 기다린다).
class _ActiveSkillSlot extends StatefulWidget {
  const _ActiveSkillSlot({super.key, required this.skillId});

  final String skillId;

  @override
  State<_ActiveSkillSlot> createState() => _ActiveSkillSlotState();
}

class _ActiveSkillSlotState extends State<_ActiveSkillSlot> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SkillManager manager = SkillManager.instance;
    final ActiveSkill? skill = manager.findActiveSkillById(widget.skillId);
    if (skill == null) {
      return const SizedBox.shrink();
    }

    final double effectiveCooldown = manager.effectiveActiveSkillCooldown(
      skill,
    );
    final double remaining = manager.activeSkillCooldownRemaining(
      widget.skillId,
    );
    final bool isOnCooldown = remaining > 0;
    final double progress = effectiveCooldown <= 0
        ? 1
        : (1 - remaining / effectiveCooldown).clamp(0.0, 1.0);
    final Color accent = skill.type == ActiveSkillType.buff
        ? Colors.cyanAccent
        : Colors.orangeAccent;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: isOnCooldown ? null : () => manager.useActiveSkill(widget.skillId),
      child: Container(
        width: 48,
        height: 48,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF20202C),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent, width: 1.2),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(skill.icon, color: accent, size: 22),
            if (isOnCooldown) ...[
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 3,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(Colors.white70),
                  ),
                ),
              ),
              Container(
                color: Colors.black54,
                alignment: Alignment.center,
                child: Text(
                  remaining.ceil().toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
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
                      MissionManager.instance.updateProgress(
                        ActionType.upgrade,
                        1,
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),
                _UpgradeButton(
                  title: '공격속도',
                  level: manager.attackSpeedLevel,
                  valueLabel:
                      '${manager.effectiveAttackSpeed.toStringAsFixed(2)}/s',
                  cost: manager.speedUpgradeCost,
                  gold: manager.gold,
                  icon: Icons.bolt,
                  onTap: () {
                    if (manager.upgradeAttackSpeed()) {
                      MissionManager.instance.updateProgress(
                        ActionType.upgrade,
                        1,
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),
                _UpgradeButton(
                  title: '크리티컬 확률',
                  level: manager.criticalRateLevel,
                  valueLabel:
                      '${(manager.criticalRate * 100).toStringAsFixed(0)}%',
                  cost: manager.criticalUpgradeCost,
                  gold: manager.gold,
                  icon: Icons.flash_on,
                  onTap: () {
                    if (manager.upgradeCriticalRate()) {
                      MissionManager.instance.updateProgress(
                        ActionType.upgrade,
                        1,
                      );
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
                      MissionManager.instance.updateProgress(
                        ActionType.upgrade,
                        1,
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),
                _UpgradeButton(
                  title: '방어율',
                  level: manager.defenseRateLevel,
                  valueLabel:
                      '${(manager.effectiveDefenseRate * 100).toStringAsFixed(0)}%',
                  cost: manager.defenseRateUpgradeCost,
                  gold: manager.gold,
                  icon: Icons.security,
                  onTap: () {
                    if (manager.upgradeDefenseRate()) {
                      MissionManager.instance.updateProgress(
                        ActionType.upgrade,
                        1,
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),
                _UpgradeButton(
                  title: '회피율',
                  level: manager.evasionRateLevel,
                  valueLabel:
                      '${(manager.effectiveEvasionRate * 100).toStringAsFixed(0)}%',
                  cost: manager.evasionRateUpgradeCost,
                  gold: manager.gold,
                  icon: Icons.directions_run,
                  onTap: () {
                    if (manager.upgradeEvasionRate()) {
                      MissionManager.instance.updateProgress(
                        ActionType.upgrade,
                        1,
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),
                _UpgradeButton(
                  title: '크리티컬 방어율',
                  level: manager.critDefenseRateLevel,
                  valueLabel:
                      '${(manager.effectiveCritDefenseRate * 100).toStringAsFixed(0)}%',
                  cost: manager.critDefenseRateUpgradeCost,
                  gold: manager.gold,
                  icon: Icons.gpp_good,
                  onTap: () {
                    if (manager.upgradeCritDefenseRate()) {
                      MissionManager.instance.updateProgress(
                        ActionType.upgrade,
                        1,
                      );
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
            color: affordable
                ? const Color(0xFF6C4FCE)
                : const Color(0xFF3A3A4A),
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
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
            Icon(
              Icons.arrow_upward,
              color: affordable ? Colors.white : Colors.white24,
            ),
          ],
        ),
      ),
    );
  }
}
