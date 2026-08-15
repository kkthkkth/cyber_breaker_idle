import 'dart:async';
import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../constants/app_images.dart';
import '../constants/character_class_config.dart';
import '../managers/consumable_manager.dart';
import '../managers/dungeon_manager.dart';
import '../managers/equipment_manager.dart';
import '../managers/game_manager.dart';
import '../managers/guild_manager.dart';
import '../managers/mission_manager.dart';
import '../managers/potion_manager.dart';
import '../managers/speed_manager.dart';
import '../managers/tower_floor_manager.dart';
import '../managers/world_boss_manager.dart';
import '../models/consumable_item_model.dart';
import '../models/equipment.dart';
import '../models/mission_model.dart';
import '../models/tower_floor_model.dart';
import '../utils/number_formatter.dart';
import 'remote_sprite_loader.dart';

enum GameMode {
  mainStage,
  goldDungeon,
  equipDungeon,
  towerOfInfinity,
  petDungeon,
  worldBoss,
  guildDungeon,
}

/// 메인 스테이지 전용 조우 상태 — [GameMode.mainStage]일 때만 의미가
/// 있고, 던전 모드는 항상 즉시 전투(사실상 [battle] 고정)로 취급한다.
///   - [moving]: 배경이 오른쪽→왼쪽으로 스크롤되고, 몬스터가 화면 우측
///     밖에서 전투 위치(화면 중앙)까지 같은 속도로 걸어 들어온다.
///   - [battle]: 배경/몬스터 이동이 멈추고, 기존 공격 타이머 루프가
///     돌아간다.
enum _EncounterPhase { moving, battle }

class IdleGame extends FlameGame {
  final GameManager manager = GameManager.instance;
  final Random _random = Random();

  late PlayerAnimationComponent _player;
  late RectangleComponent _monster;
  /// 몬스터 자리에 얹는 이모지 오버레이 — 평소엔 빈 문자열이라 아무것도
  /// 안 보이고, 월드보스 전투에서만 [_spawnDungeonMonster]가 '🐉'를 넣어
  /// 준다([_monster]의 단색 사각형 위에 겹쳐 그려진다).
  late final TextComponent _monsterEmoji = TextComponent(
    text: '',
    anchor: Anchor.center,
    position: Vector2.all(monsterSize / 2),
    textRenderer: TextPaint(style: const TextStyle(fontSize: 64)),
  );
  late PetComponent _pet;

  /// [_onEquipmentChanged]가 매번 EquipmentManager 알림에 반응해 캐릭터를
  /// 다시 로드하지 않도록, 마지막으로 실제 반영한 캐릭터 ID를 기억해 둔다
  /// (장비 강화 등 캐릭터와 무관한 알림도 자주 오므로). 펫 표시 여부는
  /// (단순 bool이라) 매번 다시 계산해도 비용이 없어 따로 캐시하지 않는다.
  String? _lastKnownCharacterId;

  /// 다중 레이어 패럴랙스 — [_backLayer](먼 배경, 완전 정지)가 [_groundLayer]
  /// (바닥/땅, 빠르게 스크롤)보다 먼저 add되어 뒤에 깔린다.
  late ParallaxBackLayer _backLayer;
  late ParallaxGroundLayer _groundLayer;
  double _attackTimer = 0;
  double _monsterAttackTimer = 0;

  /// 물약 자동 사용 재사용 대기시간(초) — [_updateAutoPotion] 참고. 다른
  /// 전투 타이머([_attackTimer] 등)와 같은 이유로 PotionManager(앱 전역
  /// 싱글턴)가 아니라 컴포넌트 생존 기간에 종속된 IdleGame이 소유한다.
  double _potionCooldownTimer = 0;
  static const double _potionCooldownDuration = 5.0;

  // 메인 스테이지 전용 — moving/battle 전환과 배경/몬스터 위치를 관리한다.
  _EncounterPhase _encounterPhase = _EncounterPhase.moving;

  /// 바닥 레이어 스크롤 속도이자 몬스터 walk-in 속도 — "캐릭터가 걷는
  /// 속도에 맞춰" 하나의 값으로 통일한다(둘이 어긋나면 몬스터가 바닥과
  /// 미끄러지듯 보인다). 먼 배경([_backLayer])은 baseVelocity 0이라 이
  /// 값과 무관하게 완전히 정지해 있다.
  static const double _scrollSpeed = 150.0;
  static const double _monsterOffscreenMargin = 60.0;

  /// 프레임 하나당 [_fireProjectile] 발사 횟수 안전 상한 — 탭을 백그라운드에
  /// 뒀다 복귀할 때처럼 dt가 순간적으로 수 초까지 튀는 극단적인 상황에서도
  /// 그 한 프레임에 수백 발이 한꺼번에 터지지 않도록 막는다(정상적인 프레임
  /// 레이트+공속 조합에서는 절대 걸리지 않는 값).
  static const int _maxAttacksPerFrame = 20;

  // ── 렌더 순서(Z-Index) ────────────────────────────────────────────
  // Flame은 기본적으로 같은 priority끼리는 add된 순서로 그리지만(그래서
  // 지금까지는 그냥 add 순서에만 의존했다), 그 순서가 나중에 바뀌거나
  // (컴포넌트를 remove했다가 다시 add하는 등) 헷갈리는 사고를 원천 차단하기
  // 위해 값을 명시한다 — 숫자가 클수록 나중에(=위에) 그려진다. 먼 배경(0)
  // < 바닥(1) < 캐릭터/몬스터/펫(2) 순.
  static const int _backLayerPriority = 0;
  static const int _groundLayerPriority = 1;
  static const int _entityPriority = 2;

  // ── 반응형(비율 기반) 배치 기준점 ──────────────────────────────────
  // 절대 픽셀 대신 항상 [size](현재 게임 캔버스 크기)에 곱한 비율로 좌표를
  // 구한다 — 창 크기/해상도가 바뀌어도([onGameResize]) 캐릭터·몬스터·HP
  // 바가 배경의 "바닥 길" 라인에 그대로 붙어 있도록 하기 위함이다. public
  // static이라 home_screen.dart의 Flutter 오버레이(캐릭터 스프라이트/HP
  // 바/펫 아이콘)도 같은 값을 참조해 Flame 쪽과 어긋나지 않는다.
  static const double groundYRatio = 0.88;
  static const double playerXRatio = 0.2;

  /// 몬스터(RectangleComponent)의 정사각형 한 변 길이 — home_screen.dart의
  /// 몬스터 HP 바가 몬스터 머리 위 정확한 자리·너비(monsterSize * 1.2)를
  /// 계산할 때 이 값을 그대로 참조해 Flame 쪽과 어긋나지 않는다.
  static const double monsterSize = 120;

  /// [HomeScreen]이 생성한(그리고 앱 생명주기 동안 계속 살아있는) 메인
  /// 스테이지 전용 인스턴스에 대한 전역 참조 — [StoryDialogWidget]처럼
  /// 완전히 다른 위젯 트리(Navigator로 위에 띄운 풀스크린 라우트)에서
  /// 열리는 화면이 이 참조로 [setDialogActive]를 호출해 캐릭터를 대기
  /// 모션으로 전환한다. HomeScreen.initState에서 한 번만 설정되고, 매번
  /// 새로 만들고 버려지는 던전 전용 IdleGame은 여기 등록하지 않는다(스토리
  /// 대화창은 던전 중엔 뜨지 않으므로 문제없다).
  static IdleGame? mainInstance;

  /// 바닥 길 Y좌표(절대 픽셀) — 캐릭터/몬스터 모두 [Anchor.bottomCenter]로
  /// 이 지점에 발을 붙인다.
  double get _groundY => size.y * groundYRatio;

  /// [_monster]/[_player]의 실제 시각적 중심(피격 이펙트/투사체 시작·착탄점/
  /// 데미지 텍스트 기준점) — 둘 다 [Anchor.bottomCenter]라 `position`이
  /// 발밑(바닥 길)을 가리키므로, 몸통 중앙은 그보다 half-height만큼 위다.
  Vector2 get _monsterCenter => _monster.position - Vector2(0, _monster.size.y / 2);
  Vector2 get _playerCenter => _player.position - Vector2(0, _player.size.y / 2);

  /// 몬스터 처치 연출(스케일/페이드 아웃) 재생 중 — 이 동안은 공격/피격
  /// 타이머를 전부 멈춰서 죽어가는 몬스터를 계속 때리거나 죽는 몬스터가
  /// 플레이어를 때리는 것처럼 보이지 않게 한다.
  bool _monsterDying = false;

  // ── 패배 연출(피격 포즈 → 페이드아웃 → 페널티 적용 → 페이드인) ──────
  // 'HP 0 도달'([resolveMonsterAttack])과 '보스전 제한시간 초과'
  // ([GameManager.tickBossTimer]) 둘 다 여기로 수렴한다. 이 시퀀스가 도는
  // 동안은 [update]가 맨 위에서 일찍 return해 공격/몬스터 스폰/스테이지
  // 진행 판정을 전부 멈추고([_startDefeatSequence]), 스킬 버튼 등 외부
  // 입력 경로([_resolveHit]/[_resolveSkillHit]/[applySkillDamage])도 같은
  // 플래그로 무시한다.
  bool _isDefeatSequenceActive = false;
  double _defeatSequenceTimer = 0;
  bool _defeatPenaltyApplied = false;

  /// 화면이 완전히 검게 덮이기까지("페이드아웃") 걸리는 시간 — 이 시점에
  /// [GameManager.applyDefeatPenalty]가 호출된다.
  static const double _defeatFadeOutDuration = 0.5;

  /// 검은 화면에서 다시 밝아지기("페이드인")까지 걸리는 시간.
  static const double _defeatFadeInDuration = 0.5;

  static const double _defeatTotalDuration =
      _defeatFadeOutDuration + _defeatFadeInDuration;

  /// 패배 페이드아웃이 시작될 때(피격 포즈로 전환된 직후) 한 번 호출된다 —
  /// UI가 검은 오버레이를 [_defeatFadeOutDuration]초에 걸쳐 서서히
  /// 불투명해지도록 애니메이션하라는 신호.
  VoidCallback? onDefeatFadeOut;

  /// 화면이 완전히 검게 덮이고 [GameManager.applyDefeatPenalty]까지 끝난
  /// 직후 한 번 호출된다 — UI가 검은 오버레이를 [_defeatFadeInDuration]초에
  /// 걸쳐 다시 투명하게 걷어내라는 신호.
  VoidCallback? onDefeatFadeIn;

  int _lastKnownChapter = 1;

  /// [GameManager.effectiveAttackSpeed] 스냅샷 — 매 프레임 비교해서 값이
  /// 바뀌었을 때만(업그레이드/장비 착용 어느 경로든) [_player]의 공격
  /// 애니메이션 stepTime을 다시 계산해 넣는다([_syncAttackAnimationSpeed]).
  /// -1은 "아직 한 번도 동기화 안 함"을 뜻하는 유효하지 않은 값이라, 최초
  /// 프레임에서 반드시 한 번은 동기화가 일어나도록 보장한다.
  double _lastKnownAttackSpeed = -1;

  /// [GameManager.absoluteStage] 스냅샷 — 매 프레임 비교해서 값이
  /// "줄어들면"(챕터 경계를 넘는 정상 진행은 항상 늘어나기만 하므로) 패배로
  /// 스테이지가 강등된 것으로 판정해 다시 [_EncounterPhase.moving]으로
  /// 되돌린다.
  int _lastKnownAbsoluteStage = 0;

  // 스킬 히트 플래시만 예외적으로 반투명 색을 잠깐 덮는다 — 평소엔 완전
  // 투명이라 [ScrollingBackground]가 그대로 비쳐 보인다.
  static const Color _normalBackgroundColor = Colors.transparent;
  static const Color _skillFlashColor = Color(0x664A1010);
  Color _backgroundColor = _normalBackgroundColor;

  static const Color _mainStageMonsterColor = Color(0xFFE74C3C);
  static const Color _goldDungeonMonsterColor = Color(0xFFFFC107);
  static const Color _equipDungeonMonsterColor = Color(0xFF9B59B6);
  static const Color _towerMonsterColor = Color(0xFF34C6E5);
  static const Color _petDungeonMonsterColor = Color(0xFFFF9F5A);
  static const Color _worldBossMonsterColor = Color(0xFF7A0F0F);

  /// 길드 창(GuildMainScreen)의 UI 전체가 쓰는 보라색 포인트 컬러와 통일 —
  /// 이 몬스터를 보면 바로 "길드 콘텐츠"로 인지되게 한다.
  static const Color _guildDungeonMonsterColor = Color(0xFF6C4FCE);

  static const double _goldDungeonDuration = 60.0;
  static const double _equipDungeonDuration = 60.0;
  static const double _petDungeonDuration = 60.0;

  /// 월드보스 도전 1회의 제한 시간(초) — 일반 던전과 같은 "던전형 전투"
  /// 타이머 패턴을 그대로 재사용한다.
  static const double _worldBossDuration = 60.0;

  /// 길드 던전 도전 1회의 제한 시간(초) — 장비 던전/펫 산책로처럼 이
  /// 시간 안에 몬스터를 처치하지 못하면 실패로 끝난다(월드보스처럼
  /// "타임아웃=성공"이 아니다 — 요구사항의 "던전 클리어 시 보상 지급"은
  /// 처치가 목표라는 뜻이다).
  static const double _guildDungeonDuration = 60.0;

  /// '펫 산책로' 보스를 잡으면 한 번에 지급되는 발바닥 수량.
  static const int _petDungeonPawprintReward = 300;

  /// 길드 던전 몬스터 체력 — "적당히 강하게"라는 요구사항에 맞춰 장비
  /// 던전(1200)보다 훨씬 높게 잡은 자리표시 값이다. 실제 밸런스 데이터가
  /// 없어 임의로 정했으니, 기획 수치가 정해지면 이 값만 바꾸면 된다.
  /// (참고: 이 엔진의 던전형 전투는 전부 "플레이어→몬스터" 단방향 공격만
  /// 있고 몬스터가 반격하지 않는 구조라 — 월드보스/장비 던전/펫 산책로
  /// 전부 동일 — "공격력을 강하게"는 체력으로만 체감 난이도를 낼 수
  /// 있었다. 몬스터가 플레이어 체력을 실제로 깎게 하려면 메인 스테이지
  /// 수준의 양방향 전투 구조가 추가로 필요하다.)
  static const double _guildDungeonMonsterHp = 5000;

  /// 길드 던전 클리어 보상 — "예: 30개"라는 요구사항 그대로. 골드/보석
  /// 값은 명시되지 않아 다른 던전 보상과 비슷한 규모로 임의 설정했다.
  static const int _guildDungeonGoldReward = 500;
  static const int _guildDungeonGemReward = 20;
  static const int _guildDungeonCoinReward = 30;

  /// 이번 월드보스 도전에서 누적으로 가한 데미지 — [WorldBossBattleScreen]
  /// 이 도전이 끝난 뒤 이 값을 읽어 [WorldBossManager.recordBattleDamage]
  /// 에 반영한다. 골드 던전의 [_dungeonGoldEarned]와 같은 성격의 "실시간
  /// 누적" 필드다.
  double _worldBossDamageDealt = 0;
  double get worldBossDamageDealt => _worldBossDamageDealt;

  GameMode mode = GameMode.mainStage;
  double dungeonMonsterHp = 0;
  double dungeonMonsterMaxHp = 0;
  double dungeonTimeRemaining = 0;

  GameMode? _pendingMode;
  bool _pendingSweepMode = false;
  bool _isSweepMode = false;
  bool _dungeonEnding = false;
  int _dungeonGoldEarned = 0;

  /// Fired once when a dungeon run ends (win, loss, or timeout).
  void Function({
    required bool success,
    required int goldReward,
    int gemReward,
    Equipment? itemReward,
    int pawprintReward,
    int guildCoinReward,
    // 무한의 탑 보상 텍스트 — ConsumableType으로 안 풀리는 자유 텍스트
    // (예: "장비 강화 가루")까지 그대로 보여줘야 해서 enum이 아니라 이미
    // 화면에 표시할 최종 문자열로 넘어온다([_damageDungeonMonster]의
    // towerOfInfinity 분기 참고).
    String? consumableItemReward,
  })? onDungeonComplete;

  /// Fired whenever the monster lands a non-evaded hit on the player during
  /// main-stage combat (see [resolveMonsterAttack] loop in [update]) — used
  /// by the UI to flash a hit overlay. Not fired on evasion (damage == 0).
  /// (Player pose while attacking/moving is no longer driven by a callback —
  /// [_player] is a real [PlayerAnimationComponent] that Flame animates
  /// directly via [PlayerState], switched in [_enterMovingPhase]/
  /// [_enterBattlePhase].)
  void Function(double damage)? onPlayerHit;

  @override
  Color backgroundColor() => _backgroundColor;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // priority를 명시해 렌더 순서를 고정한다(배경 0 < 바닥 1 < 엔티티 2)
    // — add 순서에만 의존하지 않으므로 나중에 컴포넌트를 remove/재add해도
    // 순서가 흐트러지지 않는다.
    _backLayer = ParallaxBackLayer(getSize: () => size)..priority = _backLayerPriority;
    add(_backLayer);
    _groundLayer = ParallaxGroundLayer(getSize: () => size)..priority = _groundLayerPriority;
    add(_groundLayer);

    _player = PlayerAnimationComponent(position: _playerPosition(size))
      ..priority = _entityPriority;
    add(_player);

    // 캐릭터 바로 좌측 뒤쪽에서 졸졸 따라다니는 펫 — 매 프레임 [_player]의
    // 실제 position을 그대로 읽어 따라가므로(update() 참고), moving/battle
    // 어느 상태든, 리사이즈로 플레이어 위치가 바뀌든 별도 동기화 없이 항상
    // 붙어 있다. 장착된 펫이 없으면 visible이 false라 그냥 아무것도
    // 그리지 않는다.
    _pet = PetComponent(getPlayerPosition: () => _player.position)..priority = _entityPriority;
    add(_pet);

    _monster = RectangleComponent(
      size: Vector2.all(monsterSize),
      paint: Paint()..color = _mainStageMonsterColor,
      anchor: Anchor.bottomCenter,
      position: Vector2(size.x / 2, _groundY),
      priority: _entityPriority,
    );
    add(_monster);
    _monster.add(_monsterEmoji);

    manager.onSkillUsed = _castSkill;

    // 장착 캐릭터/펫이 바뀔 때(가챠/장착 화면)마다 새 캐릭터의 프레임을
    // 다시 불러오고 펫 표시 여부를 갱신한다 — dungeon_screen.dart처럼 이
    // IdleGame을 버릴 때는 [detachListeners]로 반드시 해제해야 한다
    // (HomeScreen의 IdleGame은 앱 생명주기 동안 계속 살아있어 해제할
    // 필요가 없다).
    EquipmentManager.instance.addListener(_onEquipmentChanged);
    _onEquipmentChanged();

    if (_pendingMode != null) {
      _activateDungeon(_pendingMode!, isSweepMode: _pendingSweepMode);
      _pendingMode = null;
      _pendingSweepMode = false;
    } else {
      _lastKnownChapter = manager.chapter;
      _loadChapterTheme(manager.chapter);
      _enterMovingPhase();
    }
  }

  /// dungeon_screen.dart처럼 이 IdleGame 인스턴스를 더 이상 쓰지 않게 될
  /// 때 명시적으로 호출한다(SkillManager.damageHandler 복원과 같은
  /// 자리에서) — 던전 화면은 진입할 때마다 새 인스턴스를 만들고 나갈 때
  /// 버리므로, EquipmentManager 리스너가 계속 쌓이지 않도록 정리해야 한다.
  void detachListeners() {
    EquipmentManager.instance.removeListener(_onEquipmentChanged);
  }

  String get _equippedCharacterId =>
      EquipmentManager.instance.equippedItems[EquipType.character]?.gradeBadgeLabel ?? 'N1';

  /// 장착된 캐릭터의 직업 — 미장착(초기 상태 등)이면 전사로 취급한다.
  /// [_battleStopX](사거리)와 [_fireProjectile](공격 방식 분기) 둘 다 이
  /// getter 하나로 결정된다.
  CharacterClass get _equippedCharacterClass =>
      EquipmentManager.instance.equippedItems[EquipType.character]?.classType ??
      CharacterClass.warrior;

  /// EquipmentManager 알림 하나로 캐릭터 교체(로그인/장착 화면)와 펫
  /// 착용/해제 둘 다 반영한다 — 장비 강화 등 다른 이유로도 자주
  /// notifyListeners()가 오므로, 캐릭터는 실제로 바뀌었을 때만 [_player]를
  /// 다시 로드하고, 펫은 매번 [_pet.visible]만 가볍게 다시 계산한다(단순
  /// bool 비교라 캐시할 이유가 없다).
  void _onEquipmentChanged() {
    _pet.visible = EquipmentManager.instance.equippedItems[EquipType.pet] != null;

    final String characterId = _equippedCharacterId;
    if (characterId == _lastKnownCharacterId) {
      return;
    }
    _lastKnownCharacterId = characterId;
    _player.loadCharacter(characterId);
  }

  /// 챕터가 바뀔 때마다(그리고 최초 로드 시) 먼 배경과 바닥 타일을 함께
  /// 비동기로 내려받아 [_backLayer]/[_groundLayer]에 반영한다 — 보스를
  /// 잡고 다음 챕터로 넘어갈 때 배경만 바뀌고 바닥은 이전 챕터 그대로
  /// 남는 "테마 불일치"가 생기지 않도록 항상 이 메서드 하나로 세트째
  /// 교체한다([AppImages.chapterBackgroundBack]/[AppImages.groundTile]가
  /// 같은 챕터 번호를 공유). 실패해도(네트워크 오류/아직 없는 아트 등)
  /// 이전 이미지를 그대로 유지하고 조용히 넘어간다(CustomSafeImage의
  /// placeholder-fallback 관례와 동일).
  ///
  /// 두 요청 다 네트워크 왕복이 필요해 응답 순서가 요청 순서와 다를 수
  /// 있다 — 챕터가 아주 빠르게 연속으로 바뀌면(배속을 올려 순식간에 보스를
  /// 연달아 잡는 등) 먼저 보낸 이전 챕터 요청이 나중에 도착해, 방금 반영된
  /// 최신 챕터 이미지를 낡은 이미지로 덮어써 버릴 수 있다. [_themeLoadToken]
  /// 으로 "가장 마지막에 시작된 요청"의 결과만 반영되도록 막아 안전하게
  /// 동시 교체한다.
  int _themeLoadToken = 0;

  Future<void> _loadChapterTheme(int chapter) async {
    final int token = ++_themeLoadToken;
    final List<Sprite?> results = await Future.wait([
      _tryLoadSprite(AppImages.chapterBackgroundBack(chapter), '먼 배경'),
      _tryLoadSprite(AppImages.groundTile(chapter), '바닥 타일'),
    ]);

    if (token != _themeLoadToken) {
      // 그 사이 더 최신 챕터 요청이 시작됐다 — 이 응답은 이미 낡았으니
      // 화면에 반영하지 않고 버린다.
      return;
    }
    final Sprite? backSprite = results[0];
    if (backSprite != null) {
      _backLayer.sprite = backSprite;
    }
    final Sprite? groundSprite = results[1];
    if (groundSprite != null) {
      _groundLayer.sprite = groundSprite;
    }
  }

  /// 원인(주로 원격 레포에 파일이 없거나 경로가 틀린 404)을 콘솔에 남겨서
  /// "왜 안 보이지?"를 바로 진단할 수 있게 하면서도, 실패는 null로 조용히
  /// 삼켜 [_loadChapterTheme]가 나머지 하나는 정상 반영할 수 있게 한다.
  Future<Sprite?> _tryLoadSprite(String url, String label) async {
    try {
      return await RemoteSpriteLoader.loadSprite(url);
    } catch (error) {
      debugPrint('[IdleGame] $label 로드 실패($url): $error');
      return null;
    }
  }

  /// [GameManager.chapter]가 마지막으로 확인한 값과 달라졌으면(챕터 경계를
  /// 넘었으면) 배경+바닥 세트를 함께 비동기로 다시 로드한다. 매 프레임
  /// 호출해도 정수 비교 하나뿐이라 비용이 거의 없다.
  void _checkChapterBackgroundChange() {
    if (manager.chapter == _lastKnownChapter) {
      return;
    }
    _lastKnownChapter = manager.chapter;
    _loadChapterTheme(manager.chapter);
  }

  /// 배경 스크롤 재개 + 몬스터를 화면 우측 밖으로 되돌려 다음 조우를
  /// 준비한다. 승리(다음 스테이지로) / 패배(스테이지 강등) 양쪽 모두 이
  /// 메서드 하나로 수렴한다.
  void _enterMovingPhase() {
    _encounterPhase = _EncounterPhase.moving;
    _lastKnownAbsoluteStage = manager.absoluteStage;
    _monster.position = Vector2(size.x + _monsterOffscreenMargin, _groundY);
    _player.setDesiredState(PlayerState.running);
  }

  /// 스토리 대화창([StoryDialogWidget])이 열리고 닫힐 때 [mainInstance]를
  /// 통해 호출된다 — 대화창이 열려 있는 동안은 캐릭터 모션을 대기(idle)로
  /// 바꿔 자연스럽게 보이게 하고, 닫히면 그 시점의 조우 상태(이동 중이면
  /// running, 전투 중/던전이면 attacking)에 맞는 모션으로 되돌린다. 전투
  /// 로직 자체는 대화창이 떠 있는 동안에도 계속 돌아가지만(투사체는 원래
  /// 렌더링되지 않아 화면에 티가 나지 않는다), 여기서는 그와 무관하게
  /// 모션만 다룬다.
  void setDialogActive(bool active) {
    if (active) {
      _player.setDesiredState(PlayerState.idle);
      return;
    }
    _player.setDesiredState(
      mode == GameMode.mainStage && _encounterPhase == _EncounterPhase.moving
          ? PlayerState.running
          : PlayerState.attacking,
    );
  }

  /// 몬스터가 이동을 멈추고 전투를 시작하는 X좌표 — 장착 캐릭터의 직업별
  /// 사거리([CharacterClassX.attackRange])만큼 플레이어 앞에서 멈춘다.
  /// 근접(사거리 짧음)은 몬스터가 바로 코앞까지 다가오고, 원거리(사거리
  /// 김)는 훨씬 멀리서 멈춰 선다.
  double get _battleStopX => computeBattleStopX(
    playerX: _playerPosition(size).x,
    attackRange: _equippedCharacterClass.attackRange,
    screenWidth: size.x,
  );

  /// [_battleStopX]의 순수 계산 부분 — 컴포넌트 상태 없이 독립적으로
  /// 테스트할 수 있도록 분리해 뒀다. 원거리 캐릭터라도 몬스터가 화면
  /// 밖으로 밀려나지 않도록 화면 폭의 80%를 넘지 않게 clamp한다.
  @visibleForTesting
  static double computeBattleStopX({
    required double playerX,
    required double attackRange,
    required double screenWidth,
  }) {
    final double desired = playerX + attackRange;
    return desired.clamp(playerX, screenWidth * 0.8);
  }

  /// 몬스터가 전투 위치([_battleStopX], 바닥 길 위)에 도달했을 때 호출 —
  /// 스크롤/이동을 멈추고 기존 공격 타이머 루프가 이어받는다.
  void _enterBattlePhase() {
    _encounterPhase = _EncounterPhase.battle;
    _monster.position = Vector2(_battleStopX, _groundY);
    _attackTimer = 0;
    _monsterAttackTimer = 0;
    _player.setDesiredState(PlayerState.attacking);
  }

  /// Moving 상태의 프레임별 갱신 — 배경과 몬스터를 같은 속도로 왼쪽으로
  /// 옮겨서 "몬스터는 제자리, 세상이 흘러간다"는 착시를 만든다. 몬스터가
  /// 전투 위치([_battleStopX])에 도달하면 [_enterBattlePhase]로 전환한다.
  void _updateMovingPhase(double combatDt) {
    final double distance = _scrollSpeed * combatDt;
    final double battleX = _battleStopX;
    final double newX = _monster.position.x - distance;

    if (newX <= battleX) {
      _enterBattlePhase();
      return;
    }

    _monster.position.x = newX;
    // 먼 배경(_backLayer)은 baseVelocity 0이라 절대 건드리지 않는다 —
    // 바닥(_groundLayer)만 캐릭터 걸음 속도에 맞춰 스크롤된다.
    _groundLayer.advance(distance);
  }

  /// 절대 스테이지 번호가 직전 프레임보다 줄어들었으면(패배로 인한 스테이지
  /// 강등 — 정상 진행은 항상 늘어나기만 한다) 다시 Moving 상태로 되돌려
  /// 재도전 루프를 준비한다.
  void _checkStageRegression() {
    final int current = manager.absoluteStage;
    if (current < _lastKnownAbsoluteStage) {
      _enterMovingPhase();
      return;
    }
    _lastKnownAbsoluteStage = current;
  }

  /// 물약 자동 사용 — 매 프레임 쿨타임을 줄이고, 쿨타임이 다 됐을 때만
  /// [PotionManager.tryAutoUse]에 현재 HP 비율을 넘겨 판정을 위임한다.
  /// 실제로 사용됐으면(null이 아니면) [GameManager.healPlayer]로 회복시키고
  /// 쿨타임을 다시 채운다 — 쿨타임 중에는 아예 판정 자체를 하지 않으므로,
  /// 쿨타임이 도는 동안 HP가 계속 낮아도 매 프레임 재확인하는 비용이 없다.
  void _updateAutoPotion(double combatDt) {
    if (_potionCooldownTimer > 0) {
      _potionCooldownTimer = (_potionCooldownTimer - combatDt).clamp(
        0,
        _potionCooldownDuration,
      );
      return;
    }

    final double hpRatio = manager.maxHp > 0
        ? (manager.currentHp / manager.maxHp).clamp(0.0, 1.0)
        : 0.0;
    final double? healPercent = PotionManager.instance.tryAutoUse(hpRatio);
    if (healPercent == null) {
      return;
    }

    manager.healPlayer(healPercent);
    _potionCooldownTimer = _potionCooldownDuration;
  }

  /// 'HP 0 도달'/'보스전 제한시간 초과' 트리거가 뜨면 [update]가 호출한다
  /// — 캐릭터를 즉시 피격(defeat) 포즈로 바꾸고, UI에 페이드아웃을
  /// 요청한다. 실제 페널티 적용/재개는 [_updateDefeatSequence]가 매 프레임
  /// 이어받는다. 이미 진행 중이면(예: 같은 프레임에 두 트리거가 동시에
  /// 뜨는 경우) 무시해 중복 시작을 막는다.
  void _startDefeatSequence() {
    if (_isDefeatSequenceActive) {
      return;
    }
    _isDefeatSequenceActive = true;
    _defeatSequenceTimer = 0;
    _defeatPenaltyApplied = false;
    _player.setDesiredState(PlayerState.defeat);
    onDefeatFadeOut?.call();
  }

  /// 패배 시퀀스 진행 중 매 프레임 호출 — 배속 부스트와 무관하게 항상
  /// 같은 실물 시간(1초)이 걸리도록 [combatDt]가 아닌 원본 프레임 [dt]로
  /// 잰다(전투 배속이 이 극적인 연출까지 빨리 감지는 않아야 자연스럽다).
  /// [_defeatFadeOutDuration]초가 지나는 순간 정확히 한 번
  /// [GameManager.applyDefeatPenalty]를 호출해 화면이 완전히 검을 때만
  /// 스테이지/체력이 바뀌게 하고, 총 [_defeatTotalDuration]초가 지나면
  /// 시퀀스를 끝내고 다시 이동(moving) 단계로 돌아가 전투를 재개한다.
  void _updateDefeatSequence(double dt) {
    _defeatSequenceTimer += dt;

    if (!_defeatPenaltyApplied && _defeatSequenceTimer >= _defeatFadeOutDuration) {
      _defeatPenaltyApplied = true;
      manager.applyDefeatPenalty();
      onDefeatFadeIn?.call();
    }

    if (_defeatSequenceTimer >= _defeatTotalDuration) {
      _isDefeatSequenceActive = false;
      _defeatSequenceTimer = 0;
      _enterMovingPhase();
    }
  }

  /// Switches this game instance into a dungeon encounter. Safe to call
  /// before [onLoad] has finished — the request is queued and applied once
  /// the player/monster components exist. [isSweepMode] only matters for
  /// [GameMode.towerOfInfinity]: true repeats the previously-cleared floor
  /// for gold and doesn't advance, false is a first-clear attempt for gems.
  void startDungeon(GameMode dungeonMode, {bool isSweepMode = false}) {
    if (!isLoaded) {
      _pendingMode = dungeonMode;
      _pendingSweepMode = isSweepMode;
      return;
    }
    _activateDungeon(dungeonMode, isSweepMode: isSweepMode);
  }

  void _activateDungeon(GameMode dungeonMode, {bool isSweepMode = false}) {
    mode = dungeonMode;
    _isSweepMode = isSweepMode;
    _dungeonEnding = false;
    _dungeonGoldEarned = 0;
    _worldBossDamageDealt = 0;
    // 던전은 걸어 들어가는 연출 없이 곧장 전투 상태다.
    _player.setDesiredState(PlayerState.attacking);

    switch (dungeonMode) {
      case GameMode.goldDungeon:
        dungeonTimeRemaining = _goldDungeonDuration;
        _spawnDungeonMonster(hp: 80, color: _goldDungeonMonsterColor);
      case GameMode.equipDungeon:
        dungeonTimeRemaining = _equipDungeonDuration;
        _spawnDungeonMonster(hp: 1200, color: _equipDungeonMonsterColor);
      case GameMode.towerOfInfinity:
        dungeonTimeRemaining = -1;
        final int baseFloor = DungeonManager.instance.currentFloor;
        final int floor = isSweepMode ? (baseFloor - 1).clamp(1, baseFloor) : baseFloor;
        // 예전엔 이 자리에서 `60 * 1.25^(floor-1)` 같은 하드코딩 수식으로
        // 체력을 계산했다 — 이제 tower_floors 테이블 값을 그대로 쓴다.
        // 아직 이 층 데이터가 DB에 없으면(운영 미등록) 체력 0으로 폴백해
        // 최소한 화면이 멈추지 않게 한다.
        final TowerFloor? floorData = TowerFloorManager.instance.floorData(floor);
        _spawnDungeonMonster(hp: floorData?.monsterHp ?? 0, color: _towerMonsterColor);
      case GameMode.petDungeon:
        dungeonTimeRemaining = _petDungeonDuration;
        _spawnDungeonMonster(hp: 800, color: _petDungeonMonsterColor);
      case GameMode.worldBoss:
        // 일반 스테이지/던전 전투 화면과 완전히 같은 구조(IdleGame +
        // GameWidget)를 그대로 쓰되, 몬스터 자리에만 용 이모지를 얹는다
        // — [WorldBossManager.maxHp]는 "초거대 수치"라 60초 안에 0에
        // 도달할 일이 거의 없고, 이 도전의 목적도 처치가 아니라 누적
        // 데미지 랭킹이다([_damageDungeonMonster]의 worldBoss 분기 참고).
        dungeonTimeRemaining = _worldBossDuration;
        _spawnDungeonMonster(
          hp: WorldBossManager.instance.maxHp,
          color: _worldBossMonsterColor,
          emoji: '🐉',
        );
      case GameMode.guildDungeon:
        dungeonTimeRemaining = _guildDungeonDuration;
        _spawnDungeonMonster(hp: _guildDungeonMonsterHp, color: _guildDungeonMonsterColor);
      case GameMode.mainStage:
        break;
    }
  }

  void _spawnDungeonMonster({required double hp, required Color color, String emoji = ''}) {
    dungeonMonsterHp = hp;
    dungeonMonsterMaxHp = hp;
    _monster.paint = Paint()..color = color;
    _monsterEmoji.text = emoji;
  }

  Vector2 _playerPosition(Vector2 gameSize) =>
      Vector2(gameSize.x * playerXRatio, gameSize.y * groundYRatio);

  /// 창 크기/해상도가 바뀔 때마다(모바일 회전, 데스크톱 창 리사이즈 등)
  /// Flame이 자동으로 호출한다 — [size] 파라미터를 그대로 비율 계산에
  /// 써서, 캐릭터/몬스터가 새 해상도의 바닥 길 라인에 다시 정확히
  /// 맞춰지도록 한다(절대 픽셀을 그대로 두면 좁아진/넓어진 화면에서
  /// 발이 땅에서 뜨거나 파묻힌다).
  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (!isLoaded) {
      return;
    }
    final double groundY = size.y * groundYRatio;
    _monster.position = mode == GameMode.mainStage && _encounterPhase == _EncounterPhase.moving
        ? Vector2(size.x + _monsterOffscreenMargin, groundY)
        : Vector2(size.x / 2, groundY);
    _player.position = _playerPosition(size);
  }

  @override
  void update(double dt) {
    super.update(dt);

    // 패배 시퀀스(피격 포즈 → 페이드아웃 → 페널티 적용 → 페이드인) 재생
    // 중이면 그 밖의 모든 것(공격/몬스터 스폰/스테이지 진행 판정)을 멈춘다
    // — combatDt 계산조차 건너뛰어(dt 원본만 씀) 배속 부스트가 이 연출을
    // 빨리 감지 않게 한다.
    if (_isDefeatSequenceActive) {
      _updateDefeatSequence(dt);
      return;
    }

    // Speed boosts (SpeedManager.activeSpeed 2x/3x) scale how much combat
    // "time" passes per real second — everything below ticks off this
    // instead of the raw frame dt.
    final double speedMultiplier =
        SpeedManager.instance.gameSpeedMultiplier.toDouble();
    final double combatDt = dt * speedMultiplier;

    // 공격속도 스탯(업그레이드든 장비 서브 옵션이든, effectiveAttackSpeed
    // 하나로 이미 다 합산돼 있다)이 바뀌었으면 공격 애니메이션 stepTime도
    // 즉시 다시 맞춘다 — moving/battle 단계·게임 모드(메인/던전) 어디서든
    // 매 프레임 값이 실제로 달라졌을 때만(비교 비용만 지불) 반영되도록
    // 이 if 블록들보다 앞, 항상 실행되는 자리에 둔다.
    final double currentAttackSpeed = manager.effectiveAttackSpeed;
    if (currentAttackSpeed != _lastKnownAttackSpeed) {
      _lastKnownAttackSpeed = currentAttackSpeed;
      _player.updateAttackStepTime(currentAttackSpeed);
    }

    if (mode == GameMode.mainStage) {
      _checkChapterBackgroundChange();

      if (_encounterPhase == _EncounterPhase.moving) {
        _updateMovingPhase(combatDt);
        return;
      }

      if (!_monsterDying) {
        if (manager.isBossStage && manager.tickBossTimer(combatDt)) {
          // 보스전 제한시간 초과 — 피격 포즈/페이드 연출로 곧장 넘어가고,
          // 이번 프레임의 나머지 전투 판정(몬스터 공격 등)은 건너뛴다.
          _startDefeatSequence();
          return;
        }

        _monsterAttackTimer += combatDt;
        final double monsterInterval = 1 / manager.monsterAttackSpeed;
        if (_monsterAttackTimer >= monsterInterval) {
          _monsterAttackTimer -= monsterInterval;
          final result = manager.resolveMonsterAttack();
          _spawnPlayerCombatText(
            evaded: result.evaded,
            isCritical: result.isCritical,
            damage: result.damageDealt,
          );
          if (result.playerDefeated) {
            // HP 0 도달 — 붉은 히트 플래시 대신 곧장 피격 포즈/페이드
            // 연출로 넘어간다(플래시와 페이드가 겹쳐 보이면 지저분하다).
            _startDefeatSequence();
            return;
          }
          if (result.damageDealt > 0) {
            onPlayerHit?.call(result.damageDealt);
          }
        }

        _updateAutoPotion(combatDt);
        _checkStageRegression();
      }
    } else if (dungeonTimeRemaining > 0) {
      dungeonTimeRemaining -= combatDt;
      if (dungeonTimeRemaining <= 0) {
        dungeonTimeRemaining = 0;
        final bool isGoldDungeon = mode == GameMode.goldDungeon;
        // 월드보스는 처치가 아니라 "60초 생존 + 누적 데미지"가 목표라
        // 타임아웃 자체가 곧 성공이다 — 다만 골드 보상은 골드 던전
        // 전용이라 여기선 지급하지 않는다(보상은
        // [WorldBossBattleScreen]이 [worldBossDamageDealt]를 읽어
        // [WorldBossManager.recordBattleDamage]로 별도 처리한다).
        final bool cleared = isGoldDungeon || mode == GameMode.worldBoss;
        _endDungeon(
          success: cleared,
          goldReward: isGoldDungeon ? _dungeonGoldEarned : 0,
        );
      }
    }

    if (_dungeonEnding || _monsterDying) {
      return;
    }

    // 데미지 판정은 애니메이션 stepTime([PlayerAnimationComponent
    // ._computeAttackStepTime]의 clamp)과 완전히 무관하게,
    // effectiveAttackSpeed 그대로의 주기로 들어간다 — 계산 자체는
    // [computeAttackFireCount](순수 함수, 단위 테스트 가능)에 분리해 뒀다.
    final ({int fireCount, double remainingTimer}) result = computeAttackFireCount(
      currentTimer: _attackTimer,
      combatDt: combatDt,
      interval: 1 / manager.effectiveAttackSpeed,
    );
    _attackTimer = result.remainingTimer;
    for (int i = 0; i < result.fireCount; i++) {
      _fireProjectile();
    }
  }

  /// 프레임 하나 동안 몇 번 발사해야 하는지와, 다음 프레임으로 넘길 잔여
  /// 누적 시간을 계산하는 순수 함수 — [update]에서 Flame 컴포넌트 상태 없이
  /// 독립적으로 테스트할 수 있도록 분리해 뒀다.
  ///
  /// while로 누적을 소진하는 이유: [combatDt](배속 부스트 배율까지 곱해진
  /// 값)가 한 프레임 사이에 [interval]을 여러 번 넘어설 수 있는 고공속+
  /// 고배속 조합에서, 프레임당 한 번만 발사하면(예전 로직) 실제 공속보다
  /// 느리게 나가는(=데미지가 부정확한) 문제가 있었다. 다만 탭을
  /// 백그라운드에 뒀다 복귀할 때처럼 dt가 순간적으로 수 초까지 튀는
  /// 극단적인 상황에서 한 프레임에 수백 발이 터지지 않도록
  /// [maxPerFrame] 상한을 둔다 — 상한에 걸리면 밀린 시간을 계속 들고
  /// 있어봐야 다음 프레임에도 또 걸릴 뿐이므로, 잔여 시간을 0으로 버려
  /// 누적 오차가 쌓이지 않게 한다.
  @visibleForTesting
  static ({int fireCount, double remainingTimer}) computeAttackFireCount({
    required double currentTimer,
    required double combatDt,
    required double interval,
    int maxPerFrame = _maxAttacksPerFrame,
  }) {
    double timer = currentTimer + combatDt;
    int fireCount = 0;
    while (timer >= interval && fireCount < maxPerFrame) {
      timer -= interval;
      fireCount += 1;
    }
    if (fireCount == maxPerFrame) {
      timer = 0;
    }
    return (fireCount: fireCount, remainingTimer: timer);
  }

  /// 전사(warrior)는 화면에 보이지 않는 히트 딜레이용 [Projectile]로 즉발
  /// 근접 공격을, 궁수/마법사(archer/mage)는 실제로 눈에 보이며 목표를
  /// 추적하는 [ProjectileComponent]로 원거리 공격을 수행한다 — 어느 쪽이든
  /// 도착 지점에서 [_resolveHit]을 부르므로 데미지 판정/데미지 텍스트 튕김
  /// 연출/골드·아이템 드롭 로직은 완전히 동일하게 재사용된다(공격 방식만
  /// 다르고 "맞았을 때 벌어지는 일"은 하나로 통일돼 있다).
  void _fireProjectile() {
    final ({double damage, bool isCritical}) result = manager.rollAttack();
    final CharacterClass classType = _equippedCharacterClass;

    switch (classType) {
      case CharacterClass.warrior:
        add(
          Projectile(
            startPosition: _playerCenter,
            targetPosition: _monsterCenter,
            onHit: () => _resolveHit(result.damage, result.isCritical),
          ),
        );
      case CharacterClass.archer:
      case CharacterClass.mage:
        add(
          ProjectileComponent(
            startPosition: _playerCenter,
            getTargetPosition: () => _monsterCenter,
            visual: visualFor(classType),
            onHit: () => _resolveHit(result.damage, result.isCritical),
          ),
        );
    }
  }

  void _resolveHit(double damage, bool isCritical) {
    if (_isDefeatSequenceActive) {
      // 패배 연출(피격 포즈/페이드) 진행 중엔 화면이 곧 검게 덮이므로,
      // 뒤늦게 도착한 투사체의 타격은 조용히 무시한다 — 중복 데미지/골드
      // 지급을 막는다.
      return;
    }
    if (mode == GameMode.mainStage && (_monsterDying || _encounterPhase == _EncounterPhase.moving)) {
      // 죽음 연출 재생 중이거나 이미 다음 몬스터가 이동 중인 상태로
      // 넘어갔다면(발사 중이던 마지막 투사체가 뒤늦게 도착한 경우), 이
      // 히트는 무시한다 — 그러지 않으면 다음(아직 화면 밖에 있는) 몬스터가
      // 미리 데미지를 받는다.
      return;
    }

    _playHitEffect();
    _spawnMonsterDamageText(damage, isCritical);

    if (mode == GameMode.mainStage) {
      final ({Equipment? droppedItem, int goldReward}) hitResult =
          manager.damageMonster(damage);
      if (hitResult.droppedItem != null) {
        _spawnLootText(hitResult.droppedItem!);
      }
      if (hitResult.goldReward > 0) {
        _spawnGoldDrops(hitResult.goldReward);
        // ── Mission integration point ───────────────────────────────
        // goldReward > 0 only happens when GameManager._onMonsterDefeated()
        // just ran, i.e. the main-stage monster was killed right now (and,
        // in this game, one kill == one stage cleared). This is the correct
        // place to report progress for "몬스터 처치" / "스테이지 클리어" missions.
        // (Dungeon-mode kills go through _damageDungeonMonster() below and
        // are intentionally not counted here — wire them too if desired.)
        MissionManager.instance.updateProgress(ActionType.killMonster, 1);
        MissionManager.instance.updateProgress(ActionType.clearStage, 1);
        _handleMainStageKill();
      }
      return;
    }

    _damageDungeonMonster(damage);
  }

  /// Entry point for skill damage from the reusable SkillTreeQuickBar widget
  /// (SkillManager.useSkill) — routes through the same per-mode damage
  /// resolution normal hits use, so it lands on whichever monster (main
  /// stage or dungeon) this IdleGame instance is actually fighting instead
  /// of always hitting the main-stage monster.
  void applySkillDamage(double damage) {
    if (_isDefeatSequenceActive) {
      // 패배 연출 중엔 스킬 버튼을 눌러도(입력 자체는 막지 않지만) 아무
      // 효과가 없다 — 화면이 곧 검게 덮일 텐데 그 사이 몬스터가 죽는 걸
      // 막는다.
      return;
    }
    if (mode == GameMode.mainStage && (_monsterDying || _encounterPhase == _EncounterPhase.moving)) {
      return;
    }

    if (mode == GameMode.mainStage) {
      final ({Equipment? droppedItem, int goldReward}) hitResult =
          manager.damageMonster(damage);
      if (hitResult.droppedItem != null) {
        _spawnLootText(hitResult.droppedItem!);
      }
      if (hitResult.goldReward > 0) {
        _spawnGoldDrops(hitResult.goldReward);
        MissionManager.instance.updateProgress(ActionType.killMonster, 1);
        MissionManager.instance.updateProgress(ActionType.clearStage, 1);
        _handleMainStageKill();
      }
      return;
    }

    _damageDungeonMonster(damage);
  }

  void _damageDungeonMonster(double damage) {
    if (_dungeonEnding || dungeonMonsterHp <= 0) {
      return;
    }

    // 골드 던전은 킬이 아니라 타격마다 실시간으로 골드를 지급한다 —
    // 일반 공격과 스킬 공격 모두 이 함수를 거치므로 둘 다 자동 적용된다.
    if (mode == GameMode.goldDungeon) {
      final int reward = DungeonManager.instance.goldForDamage(damage);
      if (reward > 0) {
        _dungeonGoldEarned += reward;
        _spawnGoldDrops(reward);
      }
    }

    // 월드보스는 골드 던전처럼 타격마다 실시간으로 누적치를 쌓는다 —
    // 다만 쌓는 건 골드가 아니라 [worldBossDamageDealt](랭킹 제출용).
    if (mode == GameMode.worldBoss) {
      _worldBossDamageDealt += damage;
    }

    dungeonMonsterHp -= damage;
    if (dungeonMonsterHp > 0) {
      return;
    }
    dungeonMonsterHp = 0;

    switch (mode) {
      case GameMode.goldDungeon:
        _spawnDungeonMonster(hp: dungeonMonsterMaxHp, color: _goldDungeonMonsterColor);
      case GameMode.equipDungeon:
        final Equipment item = EquipmentManager.instance.generateGuaranteedLoot(
          const [ItemGrade.ssr, ItemGrade.sssr],
        );
        _spawnLootText(item);
        _endDungeon(success: true, goldReward: 0, itemReward: item);
      case GameMode.towerOfInfinity:
        // 예전엔 소탕(floor*30 골드만)과 최초 돌파(50+floor*10 보석만)가
        // 서로 다른 하드코딩 공식/재화를 썼다 — 이제 두 경우 모두 같은
        // tower_floors 행의 reward_gem/reward_gold/reward_item_name을
        // 그대로 지급한다. 최고 클리어 층수를 올리는지(서버 동기화 포함)
        // 여부만 최초 돌파/소탕을 구분한다.
        final int baseFloor = DungeonManager.instance.currentFloor;
        final int floor = _isSweepMode ? (baseFloor - 1).clamp(1, baseFloor) : baseFloor;
        final TowerFloor? floorData = TowerFloorManager.instance.floorData(floor);
        // 방어 코드: 정상 흐름에서는 dungeon_screen.dart의 입장 팝업이 이미
        // DB에 없는 층으로는 아예 못 들어오게 막지만(hp=0 폴백으로 즉시
        // "클리어"되는 걸 막기 위함), 혹시라도 이 지점에 floorData 없이
        // 도달했다면 보상 지급도 최고 클리어 층수 갱신도 건너뛴다 — 존재하지
        // 않는 층이 "클리어됨"으로 서버에 잘못 기록되는 걸 막는다.
        final int towerGemReward = floorData?.rewardGem ?? 0;
        final int towerGoldReward = floorData?.rewardGold ?? 0;
        if (towerGemReward > 0) {
          manager.addGems(towerGemReward);
        }
        if (towerGoldReward > 0) {
          manager.addGold(towerGoldReward);
        }

        // 아이템 보상 — reward_item_type/reward_item_name을 최대한 유연하게
        // 해석한다. ConsumableType으로 정확히 풀리면 그대로 인벤토리에
        // 지급하고, 'equipment'면 무작위 장비를 생성해 지급한다. 둘 다
        // 아니면(예: "장비 강화 가루"처럼 enum과 안 맞는 자유 텍스트) 실제로
        // 인벤토리에 넣을 방법이 없으니 건드리지 않고 결과 팝업에 원본
        // 텍스트만 그대로 보여준다(요구사항: "해당 텍스트가 자연스럽게
        // 표시되도록").
        Equipment? towerEquipmentReward;
        String? towerItemDisplayName;
        final ConsumableType? resolvedType = floorData?.resolvedConsumableType;
        if (resolvedType != null) {
          ConsumableManager.instance.addItem(resolvedType, 1);
          towerItemDisplayName = resolvedType.displayName;
        } else if (floorData?.rewardItemKind == TowerRewardItemKind.equipment) {
          towerEquipmentReward = EquipmentManager.instance.generateRandomLoot();
          towerItemDisplayName = floorData?.rewardItemName ?? towerEquipmentReward.name;
        } else if (floorData?.hasReward ?? false) {
          towerItemDisplayName = floorData!.rewardItemName;
        }

        if (!_isSweepMode && floorData != null) {
          unawaited(DungeonManager.instance.clearFloor(floor));
        }
        if (towerEquipmentReward != null) {
          _spawnLootText(towerEquipmentReward);
        }
        _endDungeon(
          success: true,
          goldReward: towerGoldReward,
          gemReward: towerGemReward,
          itemReward: towerEquipmentReward,
          consumableItemReward: towerItemDisplayName,
        );
      case GameMode.petDungeon:
        ConsumableManager.instance.addItem(
          ConsumableType.pawprint,
          _petDungeonPawprintReward,
        );
        _endDungeon(
          success: true,
          goldReward: 0,
          pawprintReward: _petDungeonPawprintReward,
        );
      case GameMode.worldBoss:
        // [WorldBossManager.maxHp]는 "초거대 수치"라 60초 안에 0에 닿는 건
        // 사실상 불가능하지만, 이론적으로 도달하더라도 조기 종료하지 않고
        // 골드 던전처럼 같은 HP로 다시 채워서 남은 시간 동안 계속 때릴 수
        // 있게 한다(이 도전의 목적은 처치가 아니라 누적 데미지다).
        _spawnDungeonMonster(
          hp: dungeonMonsterMaxHp,
          color: _worldBossMonsterColor,
          emoji: '🐉',
        );
      case GameMode.guildDungeon:
        // 장비 던전/펫 산책로와 같은 "처치=클리어" 구조 — 골드/보석/길드
        // 주화를 먼저 실제로 지급한 뒤, _endDungeon에는 결과 팝업 표시용으로
        // 그 값들을 그대로 넘긴다(다른 던전들과 같은 관례 — _endDungeon
        // 자체는 재화를 지급하지 않는다).
        manager.addGold(_guildDungeonGoldReward);
        manager.addGems(_guildDungeonGemReward);
        GuildManager.instance.addGuildCoins(_guildDungeonCoinReward);
        _endDungeon(
          success: true,
          goldReward: _guildDungeonGoldReward,
          gemReward: _guildDungeonGemReward,
          guildCoinReward: _guildDungeonCoinReward,
        );
      case GameMode.mainStage:
        break;
    }
  }

  void _endDungeon({
    required bool success,
    required int goldReward,
    int gemReward = 0,
    Equipment? itemReward,
    int pawprintReward = 0,
    int guildCoinReward = 0,
    String? consumableItemReward,
  }) {
    if (_dungeonEnding) {
      return;
    }
    _dungeonEnding = true;
    onDungeonComplete?.call(
      success: success,
      goldReward: goldReward,
      gemReward: gemReward,
      itemReward: itemReward,
      pawprintReward: pawprintReward,
      guildCoinReward: guildCoinReward,
      consumableItemReward: consumableItemReward,
    );
  }

  /// Returns this game instance to normal main-stage combat.
  void exitDungeon() {
    mode = GameMode.mainStage;
    _monster.paint = Paint()..color = _mainStageMonsterColor;
  }

  void _castSkill(Skill skill) {
    final double damage = manager.rollSkillDamage();

    add(
      Meteor(
        spawnPosition: Vector2(_monster.position.x, -60),
        targetPosition: _monsterCenter,
        onImpact: () => _resolveSkillHit(damage),
      ),
    );
  }

  void _resolveSkillHit(double damage) {
    if (_isDefeatSequenceActive) {
      return;
    }
    if (mode == GameMode.mainStage && (_monsterDying || _encounterPhase == _EncounterPhase.moving)) {
      return;
    }

    _playHitEffect();
    _flashBackground();
    _spawnMonsterDamageText(damage, true);

    if (mode == GameMode.mainStage) {
      final ({Equipment? droppedItem, int goldReward}) hitResult =
          manager.damageMonster(damage);
      if (hitResult.droppedItem != null) {
        _spawnLootText(hitResult.droppedItem!);
      }
      if (hitResult.goldReward > 0) {
        _spawnGoldDrops(hitResult.goldReward);
        // ── Mission integration point (skill kills) — see _resolveHit().
        MissionManager.instance.updateProgress(ActionType.killMonster, 1);
        MissionManager.instance.updateProgress(ActionType.clearStage, 1);
        _handleMainStageKill();
      }
      return;
    }

    _damageDungeonMonster(damage);
  }

  /// 메인 스테이지 몬스터가 죽었을 때의 연출 — 축소+페이드아웃 후, 다음
  /// 몬스터를 맞이하도록 다시 Moving 상태로 돌아간다. 연출 재생 중에는
  /// [update]가 공격/피격 타이머를 전부 멈춘다([_monsterDying] 참고).
  void _handleMainStageKill() {
    if (_monsterDying) {
      return;
    }
    _monsterDying = true;

    _monster.add(
      ScaleEffect.by(
        Vector2.zero(),
        EffectController(duration: 0.35, curve: Curves.easeIn),
      ),
    );
    _monster.add(
      OpacityEffect.fadeOut(
        EffectController(duration: 0.35),
        onComplete: () {
          _monster.scale = Vector2.all(1);
          _monster.opacity = 1;
          _monsterDying = false;
          _enterMovingPhase();
        },
      ),
    );
  }

  void _flashBackground() {
    _backgroundColor = _skillFlashColor;
    Future.delayed(const Duration(milliseconds: 120), () {
      _backgroundColor = _normalBackgroundColor;
    });
  }

  void _playHitEffect() {
    _monster.add(
      ScaleEffect.by(
        Vector2.all(0.9),
        EffectController(duration: 0.05, reverseDuration: 0.05),
      ),
    );
  }

  Vector2 _textJitter() => Vector2(
        (_random.nextDouble() - 0.5) * 40,
        (_random.nextDouble() - 0.5) * 20,
      );

  /// 유저가 몬스터를 타격했을 때 몬스터 머리 위에 띄운다 — 크리티컬이면
  /// 우선 "Critical N" 스타일로, 아니면 흰색 숫자로.
  void _spawnMonsterDamageText(double damage, bool isCritical) {
    add(
      DamageTextComponent(
        position: _monsterCenter + _textJitter(),
        kind: isCritical ? FloatingTextKind.critical : FloatingTextKind.normalDamage,
        damage: damage,
      ),
    );
  }

  /// 몬스터가 유저를 타격(또는 회피)했을 때 캐릭터 머리 위에 띄운다 —
  /// 회피가 최우선(피해 0), 그다음 크리티컬, 그 외엔 붉은색 피격 숫자.
  void _spawnPlayerCombatText({
    required bool evaded,
    required bool isCritical,
    required double damage,
  }) {
    final FloatingTextKind kind = evaded
        ? FloatingTextKind.evade
        : (isCritical ? FloatingTextKind.critical : FloatingTextKind.playerHit);
    add(
      DamageTextComponent(
        position: _playerCenter + _textJitter(),
        kind: kind,
        damage: damage,
      ),
    );
  }

  void _spawnLootText(Equipment item) {
    add(
      LootText(
        position: _monsterCenter + Vector2(0, -40),
        itemName: item.name,
        color: getGradeColor(item.grade),
      ),
    );
  }

  void _spawnGoldDrops(int totalGold) {
    const int coinCount = 6;
    final int share = totalGold ~/ coinCount;
    final int remainder = totalGold % coinCount;

    for (int i = 0; i < coinCount; i++) {
      final int amount = share + (i < remainder ? 1 : 0);
      if (amount <= 0) {
        continue;
      }

      final Vector2 scatterOffset = Vector2(
        (_random.nextDouble() - 0.5) * 80,
        (_random.nextDouble() - 0.5) * 40,
      );

      add(
        GoldCoin(
          position: _monsterCenter + scatterOffset,
          // Fly toward the top-right corner of the game canvas — that's the
          // side the real gold/gem chip lives on (see TopBar/main.dart's
          // AppBar). Flame's coordinate space is local to this GameWidget,
          // so it can't reach the AppBar's exact pixel position directly;
          // this at least points the right direction instead of top-left.
          target: Vector2(size.x - 24, 24),
          amount: amount,
          onCollected: manager.addGold,
        ),
      );
    }
  }
}

/// 다중 레이어 패럴랙스의 "먼 배경" 레이어 — [RemoteSpriteLoader]로 원격에서
/// 내려받은 [Sprite]를 화면 전체(0~[getSize].y)에 한 장 그대로 그린다.
/// baseVelocity가 0(완전 정지)이라 스크롤 오프셋 자체가 없다 — 매 프레임
/// 같은 자리에 같은 이미지를 그리기만 한다.
class ParallaxBackLayer extends Component {
  ParallaxBackLayer({required this.getSize});

  final Vector2 Function() getSize;

  Sprite? sprite;

  /// 매 프레임 새로 만들지 않도록 한 번만 만들어 재사용한다 — 픽셀 아트가
  /// 확대돼도 뭉개지지 않게 안티앨리어싱/필터링을 끈 Paint
  /// ([RemoteSpriteLoader.pixelArtPaint] 참고).
  final Paint _pixelArtPaint = RemoteSpriteLoader.pixelArtPaint();

  @override
  void render(Canvas canvas) {
    final Sprite? activeSprite = sprite;
    if (activeSprite == null) {
      return;
    }
    activeSprite.render(
      canvas,
      position: Vector2.zero(),
      size: getSize(),
      overridePaint: _pixelArtPaint,
    );
  }
}

/// 다중 레이어 패럴랙스의 "바닥/땅" 레이어 — 원본 가로세로 비율을 유지한
/// 채 화면 폭에 맞추고(fitWidth), 화면 맨 아래에 밀착시켜 그린다
/// (Alignment.bottomLeft와 동일한 효과 — 이 타일의 아래쪽 끝이 항상
/// `getSize().y`, 즉 화면 맨 아래와 일치한다). 임의의 고정 높이로 늘려
/// 그리면(예: [IdleGame.groundYRatio] 라인부터 화면 아래까지) 원본 비율이
/// 깨져 픽셀이 위아래로 늘어나 보이므로, 높이는 항상 `size.x`에 원본
/// 비율을 곱해 유도한다(render() 참고). [ParallaxBackLayer]와 달리 같은
/// 이미지를 두 장 나란히 그려두고 [advance]만큼씩 왼쪽으로 밀다가 한 장
/// 너비만큼 넘어가면 다시 오른쪽 끝으로 이어붙인다(고전적인 2-타일 무한
/// 스크롤 트릭). 프레임별 이동 거리 계산은 전부 [IdleGame.update]가
/// 소유한다(스피드 부스트 배율까지 고려한 combatDt를 이미 그쪽이 계산해
/// 두므로, 이 컴포넌트 스스로는 시간을 재지 않는다).
class ParallaxGroundLayer extends Component {
  ParallaxGroundLayer({required this.getSize});

  final Vector2 Function() getSize;

  Sprite? sprite;
  double _offsetX = 0;

  /// 매 프레임 새로 만들지 않도록 한 번만 만들어 재사용한다 — 픽셀 아트가
  /// 확대돼도 뭉개지지 않게 안티앨리어싱/필터링을 끈 Paint
  /// ([RemoteSpriteLoader.pixelArtPaint] 참고).
  final Paint _pixelArtPaint = RemoteSpriteLoader.pixelArtPaint();

  /// 테스트 전용 — 두 타일의 루프 이음매 계산이 끊기지 않는지(offsetX가
  /// 정확히 -tileWidth에서 랩어라운드하는지) 검증할 때만 읽는다.
  @visibleForTesting
  double get offsetXForTest => _offsetX;

  void advance(double distance) {
    final double tileWidth = getSize().x;
    if (tileWidth <= 0) {
      return;
    }
    _offsetX -= distance;
    if (_offsetX <= -tileWidth) {
      _offsetX += tileWidth;
    }
  }

  /// [nativeSize](스프라이트 원본 픽셀 크기)를 [screenSize.x]에 맞춰
  /// 원본 가로세로 비율을 유지한 채(fitWidth) 계산한 타일 크기와, 그
  /// 타일을 화면 맨 아래에 붙였을 때의 Y좌표(top) — render()와 단위
  /// 테스트 양쪽에서 재사용하는 순수 계산이라 실제 Canvas 없이도
  /// 검증할 수 있다. 임의의 고정 높이(예: 화면 하단 12% 띠)로 늘려
  /// 그리면 원본 비율이 깨져 픽셀이 위아래로 늘어나 보이므로, 높이는
  /// 항상 `screenSize.x`에 원본 비율을 곱해 유도한다.
  static ({Vector2 tileSize, double top}) computeBottomAlignedTile(
    Vector2 nativeSize,
    Vector2 screenSize,
  ) {
    final double scale = nativeSize.x > 0 ? screenSize.x / nativeSize.x : 1;
    final Vector2 tileSize = Vector2(screenSize.x, nativeSize.y * scale);
    final double top = screenSize.y - tileSize.y;
    return (tileSize: tileSize, top: top);
  }

  @override
  void render(Canvas canvas) {
    final Sprite? activeSprite = sprite;
    if (activeSprite == null) {
      return;
    }
    final Vector2 size = getSize();
    // 이미지 자체의 풀밭/흙 영역이 하단에 있으므로, 비율을 유지한 채
    // 화면 맨 아래에 붙이면(Alignment.bottomLeft와 동일한 효과) 그
    // 부분만 자연스럽게 노출된다.
    final ({Vector2 tileSize, double top}) layout =
        computeBottomAlignedTile(activeSprite.srcSize, size);

    activeSprite.render(
      canvas,
      position: Vector2(_offsetX, layout.top),
      size: layout.tileSize,
      overridePaint: _pixelArtPaint,
    );
    activeSprite.render(
      canvas,
      position: Vector2(_offsetX + size.x, layout.top),
      size: layout.tileSize,
      overridePaint: _pixelArtPaint,
    );
  }
}

/// [PlayerAnimationComponent]가 표현하는 애니메이션 상태 — 배경이 스크롤되며
/// 이동하는 동안은 [running], 몬스터와 조우해 전투가 시작되면 [attacking]으로
/// 전환된다([IdleGame._enterMovingPhase]/[IdleGame._enterBattlePhase]/
/// [IdleGame._activateDungeon]). [idle]은 스토리 대화창이 열려 있는 동안
/// ([IdleGame.setDialogActive])만 쓰이고, [defeat]은 패배 연출(피격 포즈)
/// 동안만 쓰인다([IdleGame._startDefeatSequence]).
enum PlayerState { running, attacking, idle, defeat }

/// 장착 캐릭터의 달리기/공격 프레임 시퀀스(각 5장,
/// `player_{id}_run1~5.png` / `player_{id}_attack1~5.png`)를 내려받아
/// 부드러운 프레임 애니메이션으로 재생하는 컴포넌트 — 예전엔 이 자리에
/// 아무것도 그리지 않는 RectangleComponent를 좌표 기준점으로만 쓰고 실제
/// 캐릭터는 Flutter 오버레이(PlayerHitFlashOverlay)가 단일 이미지를
/// 스왑해 그렸지만, 이제 실제 프레임 그림이 있는 캐릭터는 Flame이 직접
/// 애니메이션으로 그린다(더 이상 코드로 위아래 바운스/회전을 흉내 낼
/// 필요가 없다). 아직 프레임 시퀀스가 없는(404) 캐릭터는 [loadCharacter]
/// 가 기존 단일 포즈 이미지로 조용히 대체한다.
class PlayerAnimationComponent extends SpriteAnimationGroupComponent<PlayerState> {
  PlayerAnimationComponent({required Vector2 position})
      : super(
          size: Vector2.all(56),
          // 발이 바닥 길(IdleGame.groundYRatio)에 정확히 붙도록
          // bottomCenter로 고정 — position은 항상 발밑 좌표를 가리킨다.
          anchor: Anchor.bottomCenter,
          position: position,
          // SpriteAnimationGroupComponent는 렌더링할 때 이 paint로 개별
          // 프레임 Sprite의 paint를 덮어써 버리므로([RemoteSpriteLoader
          // .pixelArtPaint] 문서 참고), 여기서 직접 넘겨야 캐릭터가
          // 확대돼도 뭉개지지 않는다.
          paint: RemoteSpriteLoader.pixelArtPaint(),
        );

  /// 프레임 존재 여부를 확인할 때 시도해 볼 상한 — 실제 프레임 수는
  /// 캐릭터/액션마다 다르고(N1 run=3장, attack=5장, 앞으로 추가될 다른
  /// 캐릭터는 또 다를 수 있다) 하드코딩된 고정값으로 가정하지 않는다.
  /// 대신 1번부터 이 개수까지를 병렬로 미리 확인해 본 뒤, 끊기지 않고
  /// 연속으로 성공한 구간만큼만 실제 프레임으로 채택한다([_loadAction]/
  /// [countContiguousLoaded] 참고) — 실제 있는 프레임 수보다 넉넉히 크면서도
  /// 무한정 확인하지는 않도록 적당한 상한을 둔다.
  static const int _maxProbeFrameCount = 10;

  static const double _frameStepTime = 0.1;

  /// 공격 프레임 아트가 (칼을 크게 휘두르는 동작 탓에) run/idle 프레임보다
  /// 훨씬 넓은 여백을 포함한 캔버스에 그려져 있어서, 고정 [size](56x56)
  /// 박스에 맞춰 그대로 렌더링하면 캐릭터 자체가 상대적으로 작아 보이는
  /// 문제가 있다 — [attacking] 상태일 때만 이 배율만큼 확대해 시각적
  /// 크기를 run/idle과 비슷하게 보정한다. [Anchor.bottomCenter]라
  /// 확대해도 발 위치(바닥 길)는 그대로 고정되고 위로만 커진다.
  static const double _attackScale = 1.3;
  static const double _normalScale = 1.0;

  /// 대기(wait) 모션은 달리기/공격보다 조금 더 느긋하게 재생한다 —
  /// player_{id}_wait1~5.png, stepTime 0.15초.
  static const double _idleFrameStepTime = 0.15;

  /// 공격 애니메이션 stepTime의 하한/상한 — 실제 데미지 판정 주기
  /// ([IdleGame._attackTimer]/`effectiveAttackSpeed`)와는 완전히 분리된
  /// "순수 시각 연출용" 값이다. 공속이 오를수록 모션도 어느 정도 같이
  /// 빨라져야 "손이 빠르다"는 느낌이 살지만, 무한정 따라가게 두면 후반
  /// 공속(수십/s)에서 5프레임이 한 프레임당 20ms 미만으로 넘어가 눈에는
  /// 그냥 깜빡이는 글리치처럼 보인다. 그래서 하한선(=이 이상 빨라지지
  /// 않음)을 사람 눈에 자연스러운 "빠르지만 읽히는" 속도로 고정해 둔다 —
  /// 프레임당 50ms(5프레임 기준 한 사이클 250ms = 초당 최대 4회 스윙).
  /// 반대로 공속이 아주 낮을 때는 한 프레임이 너무 오래 멈춰 있지 않도록
  /// 상한선도 둔다. 데미지는 이 값과 무관하게 항상 실제 공속 그대로
  /// 정확한 주기로 들어간다([update]의 `_attackTimer` 참고) — 모션은
  /// 느려도(또는 상한에 걸려도) 타격 판정 자체는 절대 느려지지 않는다.
  static const double _minAttackStepTime = 0.05;
  static const double _maxAttackStepTime = 0.2;

  /// [computeAttackStepTime]의 [frameCount] 인자를 생략했을 때 쓰는 기본값
  /// — 실제 로드 흐름([loadCharacter]/[updateAttackStepTime])은 항상 실제로
  /// 로드된 공격 프레임 개수를 명시적으로 넘기므로, 이 기본값은 그 흐름을
  /// 거치지 않는 외부 호출(예: 단위 테스트)에서만 의미가 있다.
  static const int _defaultFrameCount = 5;

  /// 공격 1회([frameCount]프레임)가 `1.0 / attackSpeed`초 안에 끝나도록
  /// 프레임당 시간을 역산한 뒤 [_minAttackStepTime]/[_maxAttackStepTime]로
  /// clamp한다([updateAttackStepTime]/[loadCharacter] 양쪽에서 쓴다).
  /// [frameCount]는 캐릭터마다 실제로 로드된 공격 프레임 개수를 그대로
  /// 넘겨야 한다 — 프레임 수가 다른데 이 값을 고정해 버리면, 프레임이
  /// 적은 캐릭터는 한 사이클이 원래 의도보다 짧게, 많은 캐릭터는 길게
  /// 재생되어 공속과 모션 속도가 어긋난다. clamp 때문에 실제 표시 시간과
  /// 데미지 주기가 어긋나는 건 의도된 동작이다 — 모션은 "보기 좋은
  /// 정도"로만 빨라지고, 데미지는 이 함수와 별개로 `effectiveAttackSpeed`
  /// 를 그대로 따른다(단위 테스트를 위해 public).
  @visibleForTesting
  static double computeAttackStepTime(double attackSpeed, {int frameCount = _defaultFrameCount}) {
    final double totalDuration = 1.0 / attackSpeed;
    final double stepTime = totalDuration / frameCount;
    return stepTime.clamp(_minAttackStepTime, _maxAttackStepTime);
  }

  /// [loadCharacter]의 네트워크 왕복이 끝나기 전(컴포넌트가 add된 직후,
  /// 또는 완전 오프라인이라 영영 끝나지 않는 경우)에도 Flame이 매 프레임
  /// update/render를 계속 호출한다 — [animations]가 아직 비어 있는 채로
  /// 그 경로를 타면 Flame 내부에서 "Animations not set" 단언(assert)이
  /// 터진다. 그 창을 그냥 아무것도 안 그리는 것으로 방어한다.
  bool get _isReady => animations != null && animations!.containsKey(current);

  /// IdleGame이 [setDesiredState]로 요청한 마지막 상태 — [loadCharacter]의
  /// 네트워크 왕복이 끝나기 전에 걸어 들어오는 모션이 끝나 전투가
  /// 시작되는 등 상태 전환 요청이 먼저 도착할 수 있으므로, animations가
  /// 준비될 때까지 여기 기억해 뒀다가 그때 반영한다.
  PlayerState _desiredState = PlayerState.running;

  bool get _isLoaded => animations != null;

  @override
  void update(double dt) {
    if (!_isReady) {
      return;
    }
    super.update(dt);
  }

  @override
  void render(Canvas canvas) {
    if (!_isReady) {
      return;
    }
    super.render(canvas);
  }

  /// [current]를 안전하게 바꾼다 — [animations]가 아직 로드되지 않았으면
  /// (loadCharacter의 네트워크 왕복이 끝나기 전) Flame의 setter가 바로
  /// "Animations not set" 단언으로 터지므로, 그 경우엔 [_desiredState]에만
  /// 기억해 뒀다가 로드가 끝나는 순간([loadCharacter]) 반영한다.
  void setDesiredState(PlayerState state) {
    _desiredState = state;
    if (_isLoaded) {
      current = state;
    }
    scale = Vector2.all(state == PlayerState.attacking ? _attackScale : _normalScale);
  }

  /// [IdleGame.update]가 매 프레임 [GameManager.effectiveAttackSpeed]를
  /// 감시하다가 값이 바뀔 때마다 호출한다 — 이미 로드된 공격 애니메이션의
  /// 프레임별 stepTime을 네트워크 재요청 없이 그 자리에서 다시 계산해
  /// 넣는다([SpriteAnimationFrame.stepTime]이 mutable이라 가능). 아직
  /// [loadCharacter]가 끝나기 전이면(animations가 비어 있으면) 아무 것도
  /// 하지 않는다 — loadCharacter 자신이 그 시점의 공속으로 이미 stepTime을
  /// 계산해 넣으므로 놓치지 않는다.
  void updateAttackStepTime(double attackSpeed) {
    final SpriteAnimation? attackAnimation = animations?[PlayerState.attacking];
    if (attackAnimation == null) {
      return;
    }
    final double stepTime = computeAttackStepTime(
      attackSpeed,
      frameCount: attackAnimation.frames.length,
    );
    for (final SpriteAnimationFrame frame in attackAnimation.frames) {
      frame.stepTime = stepTime;
    }
  }

  /// [characterId]의 run/attack/wait 프레임과 패배(hit) 포즈를 (동시에)
  /// 내려받아 [animations]에 등록하고, 로드되는 동안 [setDesiredState]로
  /// 요청됐던 마지막 상태를 반영한다. 공격 애니메이션은 로드 시점의
  /// [GameManager.effectiveAttackSpeed]로 이미 맞춰서 등록되고, 이후 공속이
  /// 바뀌면 [updateAttackStepTime]이 이어받는다.
  Future<void> loadCharacter(String characterId) async {
    try {
      final List<SpriteAnimation> results = await Future.wait([
        _loadAction(characterId, 'run'),
        _loadAction(
          characterId,
          'attack',
          stepTimeForFrameCount: (frameCount) => computeAttackStepTime(
            GameManager.instance.effectiveAttackSpeed,
            frameCount: frameCount,
          ),
        ),
        _loadAction(characterId, 'wait', stepTime: _idleFrameStepTime),
        _loadDefeatPose(characterId),
      ]);
      animations = {
        PlayerState.running: results[0],
        PlayerState.attacking: results[1],
        PlayerState.idle: results[2],
        PlayerState.defeat: results[3],
      };
      current = _desiredState;
    } catch (_) {
      // 프레임도, 대체용 단일 이미지도 전부 실패(완전 오프라인 등) —
      // 조용히 포기하고 이전 상태를 유지한다. 다음 캐릭터 교체나 화면
      // 재진입 때 다시 시도된다.
    }
  }

  /// 패배(피격) 포즈 — `player_{id}_hit.png` 단일 이미지 한 장을 1프레임짜리
  /// "애니메이션"으로 감싼다. 다른 액션과 달리 5프레임 시퀀스가 아니라
  /// 아파하는 정지 표정 한 장이면 충분하다. 실패하면(아직 그림이 없는
  /// 캐릭터) [_loadAction]의 다른 액션들과 같은 관례로 [AppImages.playerSide]
  /// 단일 이미지로 조용히 대체한다.
  static Future<SpriteAnimation> _loadDefeatPose(String characterId) async {
    try {
      final Sprite sprite = await RemoteSpriteLoader.loadSprite(AppImages.playerHit(characterId));
      return SpriteAnimation.spriteList([sprite], stepTime: 1, loop: true);
    } catch (_) {
      final Sprite fallbackSprite =
          await RemoteSpriteLoader.loadSprite(AppImages.playerSide(characterId));
      return SpriteAnimation.spriteList([fallbackSprite], stepTime: 1, loop: true);
    }
  }

  /// [action]("run"/"attack"/"wait") 프레임을 1번부터 최대
  /// [_maxProbeFrameCount]장까지 병렬로 존재 여부를 확인한 뒤, 끊기지 않고
  /// 연속으로 성공한 구간만큼만([countContiguousLoaded]) 실제 프레임으로
  /// 채택해 무한 반복 애니메이션으로 합친다 — 캐릭터/액션마다 실제
  /// 업로드된 프레임 개수가 달라도(N1 run=3장, attack=5장 등) 하드코딩
  /// 없이 정확히 그만큼만 로드된다. 1번 프레임조차 없으면(프레임 시퀀스가
  /// 아예 없는 캐릭터) 기존 단일 포즈 이미지 한 장을 1프레임짜리
  /// "애니메이션"으로 감싸 그대로 대체 표시한다 — 호출부에서 캐릭터별로
  /// 프레임 존재 여부를 따로 확인할 필요가 없다.
  ///
  /// [stepTime]은 프레임 개수와 무관하게 고정된 프레임당 시간이 필요할
  /// 때(run/wait) 쓰고, [stepTimeForFrameCount]는 실제 프레임 개수를 알아야
  /// 계산할 수 있는 경우(attack — [computeAttackStepTime] 참고)에 쓴다.
  /// 둘 다 넘기면 [stepTimeForFrameCount]가 우선한다.
  static Future<SpriteAnimation> _loadAction(
    String characterId,
    String action, {
    double stepTime = _frameStepTime,
    double Function(int frameCount)? stepTimeForFrameCount,
  }) async {
    final List<Sprite?> probed = await Future.wait([
      for (int i = 1; i <= _maxProbeFrameCount; i++)
        _tryLoadFrame(AppImages.playerActionFrame(characterId, action, i)),
    ]);
    final int frameCount = countContiguousLoaded(probed);

    if (frameCount == 0) {
      final String fallbackUrl = switch (action) {
        'attack' => AppImages.playerAttack(characterId),
        'wait' => AppImages.playerFront(characterId),
        _ => AppImages.playerSide(characterId),
      };
      final Sprite fallbackSprite = await RemoteSpriteLoader.loadSprite(fallbackUrl);
      return SpriteAnimation.spriteList([fallbackSprite], stepTime: 1, loop: true);
    }

    final List<Sprite> frames = probed.sublist(0, frameCount).cast<Sprite>();
    final double resolvedStepTime = stepTimeForFrameCount?.call(frameCount) ?? stepTime;
    return SpriteAnimation.spriteList(frames, stepTime: resolvedStepTime, loop: true);
  }

  /// 프레임 하나를 시도해 보고, 실패(404 등)하면 예외를 던지는 대신
  /// null로 돌려준다 — [_loadAction]이 이 결과들을 보고 어디까지 연속으로
  /// 존재하는지([countContiguousLoaded]) 판단할 수 있게 하기 위함이다.
  static Future<Sprite?> _tryLoadFrame(String url) async {
    try {
      return await RemoteSpriteLoader.loadSprite(url);
    } catch (_) {
      return null;
    }
  }

  /// [results]의 맨 앞(인덱스 0 = 1번 프레임)부터 null이 아닌 값이 몇 개
  /// 연속되는지 센다 — 하나라도 null(로드 실패)을 만나면 그 뒤는 보지
  /// 않는다(업로드는 항상 1번부터 빠짐없이 순서대로 올라온다는 전제).
  /// 순수 함수라 네트워크 없이 단위 테스트할 수 있다.
  @visibleForTesting
  static int countContiguousLoaded(List<Sprite?> results) {
    int count = 0;
    while (count < results.length && results[count] != null) {
      count++;
    }
    return count;
  }
}

/// 착용한 펫(EquipmentManager.equippedItems[EquipType.pet])이 있을 때만
/// 캐릭터([PlayerAnimationComponent]) 바로 좌측 뒤쪽을 따라다니며 함께
/// 달리거나 대기하는 컴포넌트 — [IdleGame._onEquipmentChanged]가
/// [visible]을 갱신한다. 아직 펫 전용 스프라이트 아트가 없어([ItemPoolConfig]
/// 참고, 프로젝트 전체가 펫을 아이콘/텍스트로만 표시하는 관례) 등급색 대신
/// 고정 오렌지 톤의 원형 배지 + paw 이모지로 표현한다 — 캐릭터 탭 프리뷰의
/// `_PetPreviewAvatar`와 같은 시각 언어.
class PetComponent extends PositionComponent {
  PetComponent({required this.getPlayerPosition})
      : super(size: Vector2.all(_size), anchor: Anchor.bottomCenter);

  /// 플레이어 크기(56)의 약 0.65배 — "캐릭터보다 살짝 작은 귀여운 비율".
  static const double _size = 36;

  /// 항상 플레이어의 왼쪽(뒤쪽) [_followOffsetX]만큼, 같은 Y(바닥 길)에
  /// 선다.
  static const double _followOffsetX = 35;

  static const Color _bodyColor = Color(0xFFFF9800);
  static const Color _borderColor = Color(0xFFE65100);

  /// 매 프레임 이 값을 그대로 읽어 위치를 갱신하므로([update] 참고),
  /// moving/battle 전환이나 화면 리사이즈로 플레이어 위치가 바뀌어도 별도
  /// 동기화 로직 없이 항상 따라붙는다.
  final Vector2 Function() getPlayerPosition;

  /// [IdleGame._onEquipmentChanged]가 EquipmentManager 알림을 받을 때마다
  /// 갱신 — false면 [render]가 아무것도 그리지 않는다.
  bool visible = false;

  static final TextPainter _pawPainter = TextPainter(
    text: const TextSpan(text: '🐾', style: TextStyle(fontSize: 16)),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void update(double dt) {
    super.update(dt);
    final Vector2 playerPosition = getPlayerPosition();
    position = Vector2(playerPosition.x - _followOffsetX, playerPosition.y);
  }

  @override
  void render(Canvas canvas) {
    if (!visible) {
      return;
    }
    final Offset center = Offset(size.x / 2, size.y / 2);
    final double radius = size.x / 2;
    canvas.drawCircle(center, radius, Paint()..color = _bodyColor.withValues(alpha: 0.85));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = _borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    _pawPainter.paint(
      canvas,
      center - Offset(_pawPainter.width / 2, _pawPainter.height / 2),
    );
  }
}

class Projectile extends CircleComponent {
  Projectile({
    required Vector2 startPosition,
    required Vector2 targetPosition,
    required this.onHit,
  })  : _targetPosition = targetPosition,
        super(
          radius: 6,
          position: startPosition,
          anchor: Anchor.center,
          paint: Paint()..color = const Color(0xFF7EE8FA),
        );

  final Vector2 _targetPosition;
  final VoidCallback onHit;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    const double speed = 900;
    final double distance = (_targetPosition - position).length;
    final double duration = (distance / speed).clamp(0.08, 0.4);

    add(
      MoveEffect.to(
        _targetPosition,
        EffectController(duration: duration, curve: Curves.easeIn),
        onComplete: () {
          onHit();
          removeFromParent();
        },
      ),
    );
  }

  /// 근접 공격 컨셉이라 투사체가 화면에 보이면 안 된다 — 이동 타이밍
  /// (MoveEffect)과 도착 시 onHit 데미지 로직은 그대로 유지하고 렌더링만
  /// 지운다("보이지 않는 공격").
  @override
  void render(Canvas canvas) {}
}

/// 원거리 캐릭터(궁수/마법사 등)가 발사하는, 눈에 보이며 목표를 실시간으로
/// 추적하는 진짜 투사체 — 근접 캐릭터의 보이지 않는 히트 딜레이용
/// [Projectile]과는 별개의 컴포넌트다. [getTargetPosition]을 매 프레임
/// [update]에서 다시 읽어 그 방향으로 [speed]만큼 전진하므로, 몬스터가
/// (히트 이펙트로 살짝 움찔하는 등) 미세하게 움직여도 계속 정확히 따라간다.
///
/// 목표에 도달하면([_hasArrived]) [onHit] 콜백으로 데미지 판정을 넘기고
/// (호출부가 [IdleGame._resolveHit]을 넘기므로, 데미지 텍스트 튕김 연출
/// 등 "맞았을 때 벌어지는 일"은 근접 공격과 완전히 동일하게 재사용된다),
/// 짧은 타격 이펙트([ProjectileImpactEffect])를 남긴 뒤 스스로
/// [removeFromParent]로 소멸한다.
///
/// [확장성] 캐릭터별로 다른 투사체(화살/파이어볼 등)를 쓰고 싶으면
/// [visual](스프라이트 경로 + fallback 도형)만 다르게 넘기면 된다 —
/// [visualFor]가 [CharacterClass]별로 어떤 [ProjectileVisual]을 쓸지
/// 결정한다.
class ProjectileComponent extends PositionComponent {
  ProjectileComponent({
    required Vector2 startPosition,
    required this.getTargetPosition,
    required this.onHit,
    this.visual = ProjectileVisual.arrow,
    this.speed = 700,
  }) : super(
         position: startPosition.clone(),
         anchor: Anchor.center,
         size: Vector2.all(visual.fallbackRadius * 2),
       );

  /// 목표(몬스터) 위치를 매 프레임 다시 읽기 위한 콜백 — 발사 시점의
  /// 좌표를 한 번만 스냅샷 찍지 않고 실시간으로 추적한다.
  final Vector2 Function() getTargetPosition;

  final VoidCallback onHit;
  final ProjectileVisual visual;

  /// 이동 속도(px/s) — 근접용 [Projectile]과 달리 도착 시각을 미리
  /// 계산해 두지 않고, 매 프레임 남은 거리를 갱신하며 날아간다.
  final double speed;

  /// 스프라이트 로드에 성공하면 이걸 그리고, 실패/미지정이면 [visual]의
  /// fallback 도형을 그린다([render] 참고) — [CustomSafeImage]와 같은
  /// "항상 안전하게 대체되는" 철학.
  Sprite? _sprite;

  /// 매 프레임 새로 만들지 않도록 캐싱 — 픽셀 아트가 확대돼도 뭉개지지
  /// 않게 필터링을 끈 Paint([RemoteSpriteLoader.pixelArtPaint] 참고).
  final Paint _pixelArtPaint = RemoteSpriteLoader.pixelArtPaint();

  bool _hasHit = false;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final String? path = visual.spriteAssetPath;
    if (path == null) {
      return;
    }
    try {
      _sprite = await RemoteSpriteLoader.loadSprite(path);
    } catch (_) {
      // 조용히 무시 — _sprite가 null로 남아 fallback 도형이 계속 그려진다.
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_hasHit) {
      return;
    }

    final Vector2 target = getTargetPosition();
    final Vector2 toTarget = target - position;
    final double distance = toTarget.length;
    final double step = speed * dt;

    if (distance <= step || distance == 0) {
      position.setFrom(target);
      _resolveHit();
      return;
    }

    // 화살처럼 방향성이 있는 스프라이트를 나중에 넣어도 자연스럽게
    // 맞아떨어지도록 진행 방향으로 회전시켜 둔다(원형 fallback/구체
    // 스프라이트는 회전이 안 보이므로 무해하다).
    angle = atan2(toTarget.y, toTarget.x);
    position += toTarget.normalized() * step;
  }

  void _resolveHit() {
    if (_hasHit) {
      return;
    }
    _hasHit = true;
    onHit();
    parent?.add(ProjectileImpactEffect(position: position.clone(), color: visual.fallbackColor));
    removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final Sprite? sprite = _sprite;
    if (sprite != null) {
      sprite.render(canvas, size: size, overridePaint: _pixelArtPaint);
      return;
    }
    canvas.drawCircle(
      Offset(size.x / 2, size.y / 2),
      visual.fallbackRadius,
      Paint()..color = visual.fallbackColor,
    );
  }
}

/// [ProjectileComponent]가 목표에 적중했을 때 남기는 짧은 타격 이펙트 —
/// 작은 원이 빠르게 커지며 페이드아웃되는 "폭발/충격파" 느낌. 수명이
/// 끝나면 [RemoveEffect]가 자동으로 [removeFromParent]를 호출한다.
class ProjectileImpactEffect extends CircleComponent {
  ProjectileImpactEffect({required Vector2 position, required Color color})
    : super(
        radius: 4,
        position: position,
        anchor: Anchor.center,
        paint: Paint()..color = color.withValues(alpha: 0.85),
      );

  static const double _duration = 0.18;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(
      ScaleEffect.to(
        Vector2.all(3.5),
        EffectController(duration: _duration, curve: Curves.easeOut),
      ),
    );
    add(OpacityEffect.fadeOut(EffectController(duration: _duration)));
    add(RemoveEffect(delay: _duration));
  }
}

class Meteor extends CircleComponent {
  Meteor({
    required Vector2 spawnPosition,
    required Vector2 targetPosition,
    required this.onImpact,
  })  : _targetPosition = targetPosition,
        super(
          radius: 28,
          position: spawnPosition,
          anchor: Anchor.center,
          paint: Paint()..color = const Color(0xFFFF5722),
        );

  final Vector2 _targetPosition;
  final VoidCallback onImpact;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    add(
      MoveEffect.to(
        _targetPosition,
        EffectController(duration: 0.35, curve: Curves.easeIn),
        onComplete: () {
          onImpact();
          removeFromParent();
        },
      ),
    );
  }
}

/// [DamageTextComponent]가 표현할 수 있는 플로팅 컴뱃 텍스트 종류 —
/// 종류별로 색상/크기/문구가 전부 다르다([DamageTextComponent._styleFor]/
/// [DamageTextComponent._textFor] 참고).
enum FloatingTextKind {
  /// 유저가 몬스터를 타격 — 흰색 숫자.
  normalDamage,

  /// 몬스터가 유저를 타격 — 붉은색 숫자.
  playerHit,

  /// 회피 성공(피해 0) — "회피" 문구, 하늘색. 공격자가 누구든(현재는
  /// 몬스터→유저만) 이 스타일을 쓴다.
  evade,

  /// 크리티컬 — "Critical N" 문구, 더 크고 주황색. 공격 주체(유저가 몬스터를
  /// 치든, 몬스터가 유저를 치든)와 무관하게 크리티컬이면 이 스타일이
  /// normalDamage/playerHit보다 항상 우선한다.
  critical,
}

/// 전투 중 데미지/상태(회피·크리티컬)를 화면에 띄우는 재사용 가능한
/// 플로팅 컴뱃 텍스트 컴포넌트 — 생성되면 랜덤한 초기 속도로 튕겨
/// 나가면서 중력을 받아 포물선을 그리다([update] 참고), 수명이 끝나갈
/// 무렵 서서히 투명해지고([OpacityEffect]) 크리티컬이면 순간적으로
/// 커졌다 원래 크기로 돌아오는 텐션이 더해진 뒤([ScaleEffect]),
/// 애니메이션이 끝나면 스스로 소멸한다([RemoveEffect]) — 공속이 아주
/// 높아 한 프레임에 여러 발이 동시에 터져도(연속 스폰) 인스턴스마다
/// 상태가 완전히 독립적이라 서로 간섭하지 않고, 수명이 다하면 반드시
/// 제거되므로 컴포넌트가 계속 쌓여 렉을 유발하지 않는다.
class DamageTextComponent extends TextComponent {
  DamageTextComponent({
    required Vector2 position,
    required this.kind,
    double damage = 0,
  }) : super(
          text: _textFor(kind, damage),
          position: position,
          anchor: Anchor.center,
          textRenderer: TextPaint(style: _styleFor(kind)),
        );

  final FloatingTextKind kind;

  /// 인스턴스마다 새로 만들면(특히 공속이 높아 초당 여러 개씩 스폰될 때)
  /// 시드 초기화 비용이 계속 쌓이므로 클래스 전체가 하나만 공유한다 —
  /// [IdleGame._random]/[DispatchManager._random]과 같은 패턴.
  static final Random _random = Random();

  // ── 포물선 물리 튜닝 값 ────────────────────────────────────────────
  // 전부 여기 상수 몇 개로만 조절되므로, 연출 느낌을 바꾸고 싶으면 이
  // 구간만 손보면 된다.
  static const double _gravity = 640; // 아래로 당기는 가속도(px/s^2)
  static const double _minSpeedX = 30;
  static const double _maxSpeedX = 90;
  static const double _minSpeedYUp = 140; // 초기에 솟구치는 최소 속도
  static const double _maxSpeedYUp = 260;
  static const double _minLifetime = 0.5;
  static const double _maxLifetime = 1.0;

  /// 크리티컬 스케일 팝의 정점 배율 — 이 크기까지 튀었다가 1.0으로
  /// 되돌아온다.
  static const double _criticalPeakScale = 1.5;

  /// 매 프레임 [_gravity]가 누적돼 아래로 휘어지는 현재 속도(px/s) —
  /// [Effect] 시스템(시간 기반 보간)으로는 "중력을 받아 가속하며 떨어지는"
  /// 진짜 물리를 표현하기 어려워서, 이동만은 [update]에서 직접 적분한다.
  ///
  /// `late final`이 아니라 안전한 기본값으로 즉시 초기화한 일반
  /// 인스턴스 필드다 — [onLoad]가 (핫 리로드 도중 전투 중이었던 경우처럼)
  /// 어떤 이유로든 두 번 불려도 `LateInitializationError: has already
  /// been initialized`로 게임 전체가 멎지 않고, 그냥 값을 다시 굴려
  /// 덮어쓸 뿐이다 — 이 값들은 이전 상태에 의존하지 않는 "매번 새로
  /// 굴리는" 랜덤값이라 재계산해도 안전하다(멱등).
  Vector2 _velocity = Vector2.zero();
  double _lifetime = _minLifetime;

  static String _textFor(FloatingTextKind kind, double damage) {
    switch (kind) {
      case FloatingTextKind.evade:
        return '회피';
      case FloatingTextKind.critical:
        return 'Critical ${NumberFormatter.format(damage)}';
      case FloatingTextKind.normalDamage:
      case FloatingTextKind.playerHit:
        return NumberFormatter.format(damage);
    }
  }

  static TextStyle _styleFor(FloatingTextKind kind) {
    switch (kind) {
      case FloatingTextKind.normalDamage:
        return const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold);
      case FloatingTextKind.playerHit:
        return const TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold);
      case FloatingTextKind.evade:
        return const TextStyle(
          color: Colors.lightBlueAccent,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        );
      case FloatingTextKind.critical:
        return const TextStyle(
          color: Colors.orangeAccent,
          fontSize: 27,
          fontWeight: FontWeight.bold,
        );
    }
  }

  /// 좌/우 랜덤 방향 + 크기, 위로 솟구치는 속도도 랜덤으로 굴린다 — 여러
  /// 발이 동시에 뜰 때 겹치지 않고 사방으로 흩뿌려지도록 각 인스턴스가
  /// 독립적으로 계산한다. 컴포넌트 생명주기와 무관한 순수 함수라 단위
  /// 테스트로 분포 범위를 검증할 수 있다.
  @visibleForTesting
  static Vector2 rollInitialVelocity(Random random) {
    final double directionSign = random.nextBool() ? 1 : -1;
    final double speedX =
        directionSign * (_minSpeedX + random.nextDouble() * (_maxSpeedX - _minSpeedX));
    final double speedYUp = _minSpeedYUp + random.nextDouble() * (_maxSpeedYUp - _minSpeedYUp);
    return Vector2(speedX, -speedYUp); // Y는 화면 좌표계라 위쪽이 음수.
  }

  /// 텍스트 수명(초) — [_minLifetime]~[_maxLifetime] 사이 랜덤.
  @visibleForTesting
  static double rollLifetime(Random random) =>
      _minLifetime + random.nextDouble() * (_maxLifetime - _minLifetime);

  /// 한 프레임만큼 중력을 반영한 새 속도 — [update]에서 매 프레임 호출하는
  /// 오일러 적분의 "속도 갱신" 절반을 순수 함수로 분리해 뒀다(위치 적분은
  /// Flame의 `position` setter에 직접 의존해 분리하지 않았다).
  @visibleForTesting
  static Vector2 integrateGravity(Vector2 velocity, double dt) =>
      Vector2(velocity.x, velocity.y + _gravity * dt);

  /// [onLoad]가 (핫 리로드 등으로) 다시 불려도 속도/수명 재계산 및 이펙트
  /// 추가를 딱 한 번만 하도록 막는 가드 — 이게 없으면 `_velocity`가 예전
  /// `late final`처럼 크래시하진 않겠지만(더 이상 late가 아니므로), 같은
  /// [OpacityEffect]/[SequenceEffect]/[RemoveEffect]가 중복으로 더해져
  /// 페이드/제거 타이밍이 꼬일 수 있다.
  bool _isInitialized = false;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    if (_isInitialized) {
      return;
    }
    _isInitialized = true;

    _velocity = rollInitialVelocity(_random);
    _lifetime = rollLifetime(_random);

    // 숫자가 땅에 떨어질 때쯤(수명의 마지막 40%)에만 서서히 투명해진다 —
    // 처음부터 흐려지면 튀어나가는 순간의 타격감이 죽는다.
    final double fadeDuration = _lifetime * 0.4;
    add(
      OpacityEffect.fadeOut(
        EffectController(duration: fadeDuration, startDelay: _lifetime - fadeDuration),
      ),
    );

    if (kind == FloatingTextKind.critical) {
      // 크리티컬은 튕겨 나가는 순간 확 커졌다가 원래 크기로 돌아오는
      // 텐션을 얹어 타격감을 더한다.
      add(
        SequenceEffect([
          ScaleEffect.to(
            Vector2.all(_criticalPeakScale),
            EffectController(duration: 0.08, curve: Curves.easeOut),
          ),
          ScaleEffect.to(
            Vector2.all(1.0),
            EffectController(duration: 0.15, curve: Curves.easeIn),
          ),
        ]),
      );
    }

    add(RemoveEffect(delay: _lifetime));
  }

  @override
  void update(double dt) {
    super.update(dt);
    // 중력을 속도에 더하고, 그 속도를 위치에 더하는 전형적인 오일러 적분 —
    // 위로 솟구쳤다가 아래로 떨어지는 포물선이 자연스럽게 나온다. Flame의
    // Effect(시간 기반 보간) 대신 여기서 직접 적분하는 이유는 "가속하며
    // 떨어지는" 물리를 표현하려면 매 프레임 속도 자체가 바뀌어야 하기
    // 때문이다.
    _velocity = integrateGravity(_velocity, dt);
    position += _velocity * dt;
  }
}

class LootText extends TextComponent {
  LootText({
    required Vector2 position,
    required String itemName,
    required Color color,
  }) : super(
          text: '$itemName 획득!',
          position: position,
          anchor: Anchor.center,
          textRenderer: TextPaint(
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    const double duration = 1.2;

    add(
      MoveByEffect(
        Vector2(0, -60),
        EffectController(duration: duration, curve: Curves.easeOut),
      ),
    );
    add(
      OpacityEffect.fadeOut(
        EffectController(duration: duration, startDelay: 0.3),
        onComplete: removeFromParent,
      ),
    );
  }
}

class GoldCoin extends CircleComponent {
  GoldCoin({
    required Vector2 position,
    required this.target,
    required this.amount,
    required this.onCollected,
  }) : super(
          radius: 7,
          position: position,
          anchor: Anchor.center,
          paint: Paint()..color = const Color(0xFFFFD54F),
        );

  final Vector2 target;
  final int amount;
  final ValueChanged<int> onCollected;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    add(
      MoveEffect.to(
        target,
        EffectController(
          duration: 0.4,
          startDelay: 0.5,
          curve: Curves.easeIn,
        ),
        onComplete: () {
          onCollected(amount);
          removeFromParent();
        },
      ),
    );
  }
}
