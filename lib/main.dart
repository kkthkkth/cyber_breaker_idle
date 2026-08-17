import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'constants/supabase_config.dart';
import 'managers/achievement_manager.dart';
import 'managers/ad_manager.dart';
import 'managers/artifact_manager.dart';
import 'managers/affection_manager.dart';
import 'managers/arena_manager.dart';
import 'managers/attendance_manager.dart';
import 'managers/battle_pass_manager.dart';
import 'managers/character_manifest_manager.dart';
import 'managers/character_meta_manager.dart';
import 'managers/collection_manager.dart';
import 'managers/dungeon_manager.dart';
import 'managers/encyclopedia_manager.dart';
import 'managers/equipment_manager.dart';
import 'managers/equipment_set_manager.dart';
import 'managers/gacha_manager.dart';
import 'managers/game_manager.dart';
import 'managers/guild_manager.dart';
import 'managers/guild_raid_manager.dart';
import 'managers/mailbox_manager.dart';
import 'managers/main_story_manager.dart';
import 'managers/midnight_reset_manager.dart';
import 'managers/mission_manager.dart';
import 'managers/monster_drop_manager.dart';
import 'managers/monthly_attendance_manager.dart';
import 'managers/notification_manager.dart';
import 'managers/offline_reward_manager.dart';
import 'managers/pet_stat_metadata_manager.dart';
import 'managers/pity_manager.dart';
import 'managers/potion_manager.dart';
import 'managers/prestige_manager.dart';
import 'managers/quest_manager.dart';
import 'managers/rookie_attendance_manager.dart';
import 'managers/rune_manager.dart';
import 'managers/skill_manager.dart';
import 'managers/sound_manager.dart';
import 'managers/speed_manager.dart';
import 'managers/story_manager.dart';
import 'managers/supabase_manager.dart';
import 'managers/tower_floor_manager.dart';
import 'managers/tutorial_manager.dart';
import 'managers/weekday_dungeon_manager.dart';
import 'managers/world_boss_manager.dart';
import 'models/consumable_item_model.dart';
import 'models/equipment.dart';
import 'models/story_model.dart';
import 'widgets/tutorial_overlay.dart';
import 'ui/character_illustration_dialog.dart';
import 'ui/character_screen.dart';
import 'ui/dungeon_screen.dart';
import 'ui/guild_screen.dart';
import 'ui/home_screen.dart';
import 'ui/login_screen.dart';
import 'ui/mailbox_screen.dart';
import 'ui/offline_reward_dialog.dart';
import 'ui/quest_screen.dart';
import 'ui/settings_dialog.dart';
import 'ui/shop_screen.dart';
import 'ui/skill_screen.dart';
import 'ui/top_bar.dart';
import 'utils/number_formatter.dart';
import 'widgets/center_toast.dart';
import 'widgets/story_dialog_widget.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.anonKey);
  // 로컬 알림 권한 요청 — 다른 매니저들의 await 체인과 독립적이라(알림
  // 예약은 나중에 특정 이벤트 시점에만 실제로 쓰인다) 가장 먼저 끝내
  // 둔다. 지원하지 않는 플랫폼(Web/Windows)이면 내부에서 조용히 건너뛴다.
  await NotificationManager.instance.init();
  // 길드원 목록의 접속중(🟢) 표시가 참조하는 profiles.last_seen 하트비트 —
  // 아직 로그인 전이면(게스트 로그인을 아직 안 거쳤으면) 매번 조용히
  // no-op하다가, 로그인 후 다음 주기(SupabaseManager.lastSeenInterval)부터
  // 실제로 갱신되기 시작한다.
  SupabaseManager.instance.startLastSeenHeartbeat();
  // SFX 프리로드 — 실패해도(assets/audio/ 파일 없음 등) 조용히 넘어가므로
  // 다른 매니저들의 await 체인을 막지 않는다.
  unawaited(SoundManager.instance.init());
  await EquipmentManager.instance.loadEquipment();
  // 상점 가챠 버튼(EquipmentManager.generateLootOfType/drawMultipleGacha)이
  // 곧바로 PityManager를 읽으므로, 상점 화면이 열리기 전에 끝나 있어야
  // 한다.
  await PityManager.instance.loadData();
  // GameManager._onMonsterDefeated/EquipmentManager의 가챠 진입점이 매
  // 처치/뽑기마다 AchievementManager.recordMonsterKill/recordGachaPull을
  // 호출하므로, 전투/상점이 열리기 전에 끝나 있어야 한다.
  await AchievementManager.instance.loadData();
  await AffectionManager.instance.loadData();
  await GameManager.instance.loadGame();
  // GameManager.attackPower/_onMonsterDefeated가 곧바로
  // PrestigeManager.attackBonus/goldBonus를 읽어가므로, 전투가 시작되기
  // 전(runApp 이전)에 반드시 끝나 있어야 한다.
  await PrestigeManager.instance.loadData();
  await CollectionManager.instance.loadData();
  // EncyclopediaManager.instance는 최초 접근 시 생성자에서 즉시 도감 항목을
  // 만든다(캐릭터는 CharacterManifestManager.subIdsFor를 그 자리에서
  // 읽는다) — 그래서 이 매니페스트 로드가 반드시 EncyclopediaManager를
  // 처음 건드리는 줄(바로 아래)보다 앞서 끝나 있어야 한다.
  await CharacterManifestManager.instance.loadData();
  await EncyclopediaManager.instance.loadData();
  await DungeonManager.instance.loadDungeonData();
  // 무한의 탑 화면/전투(IdleGame._activateDungeon)가 곧바로 층 데이터를
  // 읽으므로, 화면이 뜨기 전(runApp 이전)에 끝나 있어야 한다.
  await TowerFloorManager.instance.loadData();
  await GachaManager.instance.loadGachaInventory();
  await MissionManager.instance.loadData();
  await AttendanceManager.instance.checkDailyLogin();
  await RookieAttendanceManager.instance.loadData();
  await SkillManager.instance.loadData();
  await MonthlyAttendanceManager.instance.loadData();
  // 상점 펫 가챠(EquipmentManager.generateLootOfType)가 곧바로
  // PetStatMetadataManager.rollSpecialStats를 읽으므로, 상점 화면이
  // 열리기 전에 끝나 있어야 한다.
  await PetStatMetadataManager.instance.loadData();
  await PotionManager.instance.loadData();
  // GameManager.maxHp/attackPower/defensePower/goldReward가 곧바로
  // ArtifactManager.totalBonus를 읽으므로, 전투가 시작되기 전(runApp 이전)에
  // 끝나 있어야 한다.
  await ArtifactManager.instance.loadData();
  // GameManager.attackPower/defensePower/effectiveCriticalRate/maxHp가
  // 곧바로 EquipmentSetManager.totalBonus를 읽으므로, 전투가 시작되기
  // 전(runApp 이전)에 끝나 있어야 한다.
  await EquipmentSetManager.instance.loadData();
  // GameManager/SkillManager가 곧바로 RuneManager.totalBonus를 읽으므로,
  // 전투가 시작되기 전(runApp 이전)에 끝나 있어야 한다.
  await RuneManager.instance.loadData();
  await WeekdayDungeonManager.instance.loadData();
  // 온라인 사냥(GameManager._onMonsterDefeated)이 곧바로 드랍 테이블을
  // 읽으므로, 전투가 시작되기 전(runApp 이전)에 끝나 있어야 한다.
  await MonsterDropTableManager.instance.loadData();
  // IdleGame._fireProjectile이 공격마다 근접/원거리를 판정할 때 곧바로
  // 읽으므로, 마찬가지로 전투가 시작되기 전에 끝나 있어야 한다.
  await CharacterMetaManager.instance.loadData();
  await SpeedManager.instance.loadBoost();
  await StoryManager.instance.loadData();
  await MainStoryManager.instance.loadData();
  await WorldBossManager.instance.loadData();
  await MailboxManager.instance.loadData();
  // GameManager.attackPower/goldReward가 GuildManager.attackBonus/goldBonus를
  // 곧바로 읽어가므로, 전투가 시작되기 전(runApp 이전)에 반드시 끝나 있어야
  // 한다.
  await GuildManager.instance.loadData();
  await GuildRaidManager.instance.loadData();
  await ArenaManager.instance.loadData();
  // 상점 '무료 보상' 탭이 곧바로 AdManager.instance.canWatchAd/dailyAdViews를
  // 읽으므로, 화면이 뜨기 전(runApp 이전)에 끝나 있어야 한다. 지원하지
  // 않는 플랫폼(Web/Windows)이면 내부에서 조용히 건너뛴다.
  await AdManager.instance.loadData();
  // QuestManager.claimQuest가 BattlePassManager.addBpExp를 부르므로, 배틀패스
  // 보상 트랙(레벨/exp)이 먼저 로드돼 있어야 한다.
  await BattlePassManager.instance.loadData();
  await QuestManager.instance.loadData();
  MidnightResetManager.instance.start();
  await TutorialManager.instance.loadData();
  unawaited(SoundManager.instance.playLobbyBgm());
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Registered here (app lifetime) so pause/resume is tracked no matter
    // which tab is showing; the dialog itself is triggered from
    // MainNavigationScreen, which has a real BuildContext to show it with.
    WidgetsBinding.instance.addObserver(OfflineRewardManager.instance);
    WidgetsBinding.instance.addObserver(DungeonManager.instance);
    WidgetsBinding.instance.addObserver(MissionManager.instance);
    WidgetsBinding.instance.addObserver(PotionManager.instance);
    WidgetsBinding.instance.addObserver(WorldBossManager.instance);
    WidgetsBinding.instance.addObserver(ArenaManager.instance);
    WidgetsBinding.instance.addObserver(QuestManager.instance);
    WidgetsBinding.instance.addObserver(WeekdayDungeonManager.instance);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.removeObserver(OfflineRewardManager.instance);
    WidgetsBinding.instance.removeObserver(DungeonManager.instance);
    WidgetsBinding.instance.removeObserver(MissionManager.instance);
    WidgetsBinding.instance.removeObserver(PotionManager.instance);
    WidgetsBinding.instance.removeObserver(WorldBossManager.instance);
    WidgetsBinding.instance.removeObserver(ArenaManager.instance);
    WidgetsBinding.instance.removeObserver(QuestManager.instance);
    WidgetsBinding.instance.removeObserver(WeekdayDungeonManager.instance);
    MidnightResetManager.instance.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      GameManager.instance.saveGame();
      EquipmentManager.instance.saveEquipment();
      DungeonManager.instance.saveDungeonData();
      GachaManager.instance.saveGachaInventory();
      // 디바운스된(최대 2초) 퀘스트 진행도 동기화가 그 시간을 못 채우고
      // 앱이 죽는 것을 막는다 — QuestManager.flushPendingSync 문서 참고.
      unawaited(QuestManager.instance.flushPendingSync());
      // 요구사항: "게임 종료 후 8시간 뒤 ➡️ 영웅들이 지쳤습니다!..." — 앱을
      // 내릴 때마다 예약하고(다시 내릴 때마다 이전 예약을 덮어쓴다),
      // 포그라운드로 돌아오면([resumed]) 곧바로 취소한다.
      NotificationManager.instance.scheduleOfflineReminder();
    } else if (state == AppLifecycleState.resumed) {
      // 백그라운드에 있던 동안엔 startLastSeenHeartbeat()의 주기 타이머가
      // 계속 돌긴 하지만(모바일 OS가 지연시킬 수 있다), 포그라운드로
      // 돌아온 순간 즉시 한 번 더 갱신해 "접속중" 표시가 최대한 빨리
      // 정확해지게 한다.
      SupabaseManager.instance.updateLastSeen();
      NotificationManager.instance.cancelOfflineReminder();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Idle RPG',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        useMaterial3: true,
        // 거의 모든 화면이 Scaffold의 backgroundColor를 개별적으로
        // 0xFF14141C로 직접 지정하지만(그래서 화면 자체는 항상 어둡다),
        // ThemeData 기본값(Material3 라이트 톤)이 그대로 남아 있으면 라우트
        // 전환 애니메이션 도중이나 각 화면이 처음 그려지기 전 찰나에 그
        // 기본 배경이 잠깐 비쳐 하얗게 번쩍인다 — 전역 기본값 자체를
        // 앱의 메인 다크 컬러로 덮어써서 그 틈을 없앤다.
        scaffoldBackgroundColor: const Color(0xFF14141C),
        canvasColor: const Color(0xFF14141C),
        // 기본 MaterialPageRoute 전환(플랫폼별 상이, 안드로이드는 특히
        // 배경이 즉시 스냅되며 번쩍이는 느낌을 준다)을 페이드 기반 전환으로
        // 통일해서, 화면이 겹치며 부드럽게 넘어가게 한다.
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.fuchsia: FadeUpwardsPageTransitionsBuilder(),
          },
        ),
      ),
      home: const LoginScreen(),
    );
  }
}

/// 로그인 완료(자동 로그인 또는 [LoginScreen]의 게스트/구글 버튼) 직후
/// 실제로 진입하는 게임 화면 — 최초 실행이라 아직 프롤로그를 안 봤다면
/// 프롤로그 스토리를, 이미 봤다면 곧장 메인 로비([MainNavigationScreen])를
/// 보여준다. 로그인 여부와 프롤로그 시청 여부는 서로 다른 축의 상태라
/// [LoginScreen]과 이 화면으로 분리해 뒀다 — 로그인은 항상 이 화면보다
/// 먼저 확인된다.
class GameEntryScreen extends StatefulWidget {
  const GameEntryScreen({super.key});

  @override
  State<GameEntryScreen> createState() => _GameEntryScreenState();
}

class _GameEntryScreenState extends State<GameEntryScreen> {
  // main()에서 StoryManager.instance.loadData()를 이미 await한 뒤 runApp이
  // 호출되므로, 이 시점엔 로컬 저장값이 확정돼 있다 — 신규 유저(최초 실행)면
  // false라 프롤로그가 먼저 뜨고, 이미 클리어한 유저면 true라 바로 메인 화면.
  bool _showPrologue = !StoryManager.instance.isPrologueCleared;

  /// 스토리를 끝까지 보든 스킵하든 결과는 동일하다: 초반 동료를 지급하고
  /// 클리어 플래그를 저장한 뒤 메인 화면으로 전환한다. 저장 자체는
  /// fire-and-forget으로 던진다 — GameManager.addCollectionBonus 등 이
  /// 프로젝트의 다른 저장 호출들과 같은 관례.
  void _onPrologueComplete() {
    EquipmentManager.instance.grantStarterCharacters();
    StoryManager.instance.markPrologueCleared();
    setState(() => _showPrologue = false);
  }

  @override
  Widget build(BuildContext context) {
    return _showPrologue
        ? StoryDialogWidget(story: prologueStory, onComplete: _onPrologueComplete)
        : const MainNavigationScreen();
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  // 홈을 정중앙(인덱스 2)에 두기 위한 탭 순서: 샵, 캐릭터, 홈, 던전, 스킬,
  // 길드. 길드 탭은 맨 끝에 추가해 기존 5개 탭의 순서/중앙 정렬을 건드리지
  // 않았다. 아이콘/라벨/화면이 하나의 배열에 묶여 있어 순서가 절대
  // 어긋나지 않고, 추후 Icon을 커스텀 이미지로 바꿀 때도 이 배열만 수정하면
  // 된다.
  static const List<_NavTab> _navTabs = <_NavTab>[
    _NavTab(icon: Icons.store, label: '샵', screen: ShopScreen()),
    _NavTab(icon: Icons.person, label: '캐릭터', screen: CharacterScreen()),
    _NavTab(icon: Icons.home, label: '홈', screen: HomeScreen()),
    _NavTab(icon: Icons.stairs, label: '던전', screen: DungeonScreen()),
    _NavTab(icon: Icons.bolt, label: '스킬', screen: SkillScreen()),
    _NavTab(icon: Icons.shield, label: '길드', screen: GuildScreen()),
  ];

  int _selectedIndex = 2;

  /// 오프라인 보상 팝업이 지금 떠 있는지 — [OfflineRewardManager
  /// .onRewardCalculated]가 (콜드 스타트 체크와 앱 재개 체크가 겹치는 등)
  /// 짧은 시간에 두 번 이상 불려도, 이 플래그가 true인 동안은
  /// [_showOfflineRewardDialog]가 추가로 [showDialog]를 띄우지 않는다 —
  /// 팝업이 무한히 쌓이는 것을 막는다.
  bool _isOfflineRewardShowing = false;

  @override
  void initState() {
    super.initState();
    OfflineRewardManager.instance.onRewardCalculated = _showOfflineRewardDialog;
    GameManager.instance.onChapterAdvanced = _onChapterAdvanced;
    GameManager.instance.onBossStageEntered = _onBossStageEntered;
    // Cold-start check — didChangeAppLifecycleState only fires on later
    // resumes, not on the very first launch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      OfflineRewardManager.instance.checkOfflineReward();
      _checkPendingChapterStory();
    });
  }

  @override
  void dispose() {
    if (identical(GameManager.instance.onChapterAdvanced, _onChapterAdvanced)) {
      GameManager.instance.onChapterAdvanced = null;
    }
    if (identical(GameManager.instance.onBossStageEntered, _onBossStageEntered)) {
      GameManager.instance.onBossStageEntered = null;
    }
    super.dispose();
  }

  /// [OfflineRewardManager.onRewardCalculated] 콜백 — 팝업이 이미 떠 있는
  /// 동안 또 불려도([_isOfflineRewardShowing]) 무시해 팝업이 중복으로
  /// 쌓이지 않게 막는다. 보상 지급([OfflineRewardManager.claimReward])은
  /// 버튼을 눌렀을 때가 아니라 **팝업이 어떤 방식으로든(버튼/바깥 탭/뒤로
  /// 가기) 닫힌 뒤** [showDialog]가 리턴한 Future의 `.then()`에서 무조건
  /// 한 번 실행한다 — 유저가 버튼을 안 누르고 강제로 팝업을 닫아도 보상을
  /// 놓치지 않는다.
  void _showOfflineRewardDialog({
    required int offlineSeconds,
    required int rewardGold,
    required int equipmentCount,
    required Map<ConsumableType, int> consumableDrops,
  }) {
    if (!mounted || _isOfflineRewardShowing) {
      return;
    }
    _isOfflineRewardShowing = true;
    showDialog<void>(
      context: context,
      builder: (context) => OfflineRewardDialog(
        offlineSeconds: offlineSeconds,
        rewardGold: rewardGold,
        equipmentCount: equipmentCount,
        consumableDrops: consumableDrops,
      ),
    ).then((_) {
      OfflineRewardManager.instance.claimReward(
        rewardGold: rewardGold,
        offlineSeconds: offlineSeconds,
        equipmentCount: equipmentCount,
        consumableDrops: consumableDrops,
      );
      _isOfflineRewardShowing = false;
    });
  }

  /// 다른 화면(스토리 컷신 등)을 새로 띄우기 직전에 호출 — 오프라인 보상
  /// 팝업이 그 아래 떠 있는 채로 남아 화면이 겹쳐 보이지 않도록,
  /// rootNavigator 기준으로 안전하게 먼저 지운다. 팝업이 없으면(이미
  /// 닫혔거나 애초에 안 떴으면) 아무 일도 하지 않는다 — `.then()`이 이미
  /// 보상 지급과 플래그 해제를 책임지므로 여기서는 그저 화면에서 치우기만
  /// 하면 된다.
  void _dismissOfflineRewardDialogIfShowing() {
    if (!_isOfflineRewardShowing) {
      return;
    }
    final NavigatorState rootNavigator = Navigator.of(context, rootNavigator: true);
    if (rootNavigator.canPop()) {
      rootNavigator.pop();
    }
  }

  /// 앱을 새로 열었을 때(또는 저장된 진행도를 이어서) 현재 (챕터,
  /// 서브스테이지)에 아직 못 본 오프닝/보스 대화가 걸려 있는지 한 번
  /// 확인한다 — [_onChapterAdvanced]/[_onBossStageEntered]는 그 경계를
  /// "방금" 넘을 때만 불리므로, 이미 그 지점에 도달해 있는 콜드 스타트
  /// 케이스는 이걸로 따로 잡아줘야 한다. 서브스테이지가 1이면 오프닝,
  /// maxStage(10)이면 보스 대화 — 그 사이(2~9)면 둘 다 볼 게 없다.
  void _checkPendingChapterStory() {
    final GameManager manager = GameManager.instance;
    if (manager.stage == 1) {
      final StoryModel? opening = MainStoryManager.instance.pendingOpeningFor(manager.chapter);
      if (opening != null) {
        _presentOpening(manager.chapter, opening);
      }
    } else if (manager.stage == GameManager.maxStage) {
      final StoryModel? bossIntro =
          MainStoryManager.instance.pendingBossIntroFor(manager.chapter);
      if (bossIntro != null) {
        _presentBossIntro(manager.chapter, bossIntro);
      }
    }
  }

  /// GameManager.onChapterAdvanced/onBossStageEntered는 Flame의 게임 루프
  /// 도중(빌드 단계와 겹칠 수 있는 시점) 동기적으로 호출되므로, 실제
  /// 네비게이션은 PlayerHitFlashOverlay의 _safeSetState와 같은 이유로
  /// 마이크로태스크로 한 프레임 미뤄서 안전하게 처리한다.
  void _onChapterAdvanced(int chapter) {
    // 챕터가 (chapter-1)에서 chapter로 방금 넘어왔다는 건 (chapter-1)의
    // 보스를 처치했다는 뜻 — 수집→스토리 탭 해금 기록을 여기서 갱신한다.
    MainStoryManager.instance.recordChapterCleared(chapter - 1);

    final StoryModel? opening = MainStoryManager.instance.pendingOpeningFor(chapter);
    if (opening == null) {
      return;
    }
    Future.microtask(() => _presentOpening(chapter, opening));
  }

  void _onBossStageEntered(int chapter) {
    final StoryModel? bossIntro = MainStoryManager.instance.pendingBossIntroFor(chapter);
    if (bossIntro == null) {
      return;
    }
    Future.microtask(() => _presentBossIntro(chapter, bossIntro));
  }

  /// [chapter]의 오프닝을 전체 화면 라우트로 띄운다. 끝나면(완주/스킵
  /// 모두 동일) 시청 기록을 저장하고, 챕터 완료 보상이 걸려 있다면(챕터 2
  /// 오프닝 = 챕터 1 완료, 챕터 3 오프닝 = 챕터 2 완료) 스토리 종료 직후
  /// 자연스럽게 이어서 지급한다. (인게임 전투 배경은 IdleGame이
  /// GameManager.chapter 값을 직접 폴링해 스스로 전환한다 — main.dart는
  /// 더 이상 배경 전환에 관여하지 않는다.)
  Future<void> _presentOpening(int chapter, StoryModel opening) async {
    if (!mounted) {
      return;
    }
    await _presentStory(opening);
    if (!mounted) {
      return;
    }

    MainStoryManager.instance.markOpeningShown(chapter);

    if (chapter == 2) {
      final Equipment reward = EquipmentManager.instance.grantChapter1Character();
      showCenterToast(context, '챕터 1 클리어 보상! ${reward.gradeBadgeLabel} 획득');
    } else if (chapter == 3) {
      final Equipment reward = EquipmentManager.instance.grantChapter2Character();
      showCenterToast(context, '챕터 2 클리어 보상! 새로운 동료 ${reward.gradeBadgeLabel} 합류');
    }
  }

  /// [chapter]의 보스 대화를 전체 화면 라우트로 띄운다. 끝나면 시청 기록만
  /// 저장한다 — 챕터 "완료" 처리(수집 → 스토리 탭 잠금 해제)는 별도 저장이
  /// 필요 없다. 보스를 처치해야만 GameManager.chapter가 오르므로,
  /// [MainStoryManager.isChapterCleared]가 그 사실을 그대로 파생시킨다.
  Future<void> _presentBossIntro(int chapter, StoryModel bossIntro) async {
    if (!mounted) {
      return;
    }
    await _presentStory(bossIntro);
    if (!mounted) {
      return;
    }
    MainStoryManager.instance.markBossIntroShown(chapter);
  }

  Future<void> _presentStory(StoryModel story) {
    _dismissOfflineRewardDialogIfShowing();
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (routeContext) => StoryDialogWidget(
          story: story,
          onComplete: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    // 튜토리얼 2단계("하단 메뉴에서 상점으로 이동해 보세요")가 진행 중일
    // 때, 실제로 샵 탭을 탭하면 3단계(가챠 버튼 강조)로 넘어간다.
    if (TutorialManager.instance.currentStep == 1 && _navTabs[index].label == '샵') {
      TutorialManager.instance.advance();
    }
  }

  void _showCharacterIllustration() {
    final Equipment? equippedCharacter =
        EquipmentManager.instance.equippedItems[EquipType.character];
    if (equippedCharacter == null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('장착된 캐릭터가 없습니다.')));
      return;
    }

    // 연타 방지 — 이미 다른 라우트가 최상단으로 올라간 상태(직전 탭으로
    // 이미 이 다이얼로그나 다른 화면이 뜬 상태)라면 중복으로 또 띄우지
    // 않는다.
    final ModalRoute<dynamic>? currentRoute = ModalRoute.of(context);
    if (currentRoute != null && !currentRoute.isCurrent) {
      return;
    }

    showDialog<void>(
      context: context,
      builder: (context) => CharacterIllustrationDialog(character: equippedCharacter),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: _buildScaffold(context)),
        // 최초 실행 온보딩 튜토리얼 — TutorialManager가 완료 상태면
        // SizedBox.shrink()만 그리므로 평소엔 아무 비용도 들지 않는다.
        AnimatedBuilder(
          animation: TutorialManager.instance,
          builder: (context, _) => const TutorialOverlay(),
        ),
      ],
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B1B26),
        elevation: 0,
        leadingWidth: 104,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const CircleAvatar(
                backgroundColor: Color(0xFF2C2C3A),
                child: Icon(Icons.person, color: Colors.white70),
              ),
              onPressed: _showCharacterIllustration,
            ),
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white70),
              onPressed: () => showSettingsDialog(context),
            ),
          ],
        ),
        title: const Text(
          'Cyber Breaker Idle',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
        actions: [
          const DailyQuestHudButton(),
          const MailboxHudButton(),
          const SpeedButton(),
          // Flexible로 감싸는 이유: 예전엔 이 통화 표시 Container가
          // AppBar.actions의 다른 자식들처럼 자기 콘텐츠 크기만큼 무한정
          // 늘어날 수 있었다 — 숫자가 커지면(수억~수조 단위) 좌측의
          // DailyQuestHudButton/MailboxHudButton/SpeedButton을 화면 밖으로
          // 밀어내거나 AppBar 자체가 오버플로우될 수 있었다. Flexible이
          // AppBar 내부 Row가 실제로 줄 수 있는 만큼만 차지하도록 제한하고,
          // 그 안의 Text들도 ellipsis로 방어한다 — 다만 NumberFormatter의
          // K/M/B/T 축약 덕분에 실제로 이 한계에 걸릴 일은 거의 없다.
          Flexible(
            child: AnimatedBuilder(
              animation: GameManager.instance,
              builder: (context, _) {
                return Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF20202C),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF3A3A4A)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.monetization_on, color: Colors.amber, size: 18),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          NumberFormatter.format(GameManager.instance.gold.toDouble()),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.diamond, color: Colors.cyanAccent, size: 16),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          NumberFormatter.format(GameManager.instance.gems.toDouble()),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [for (final _NavTab tab in _navTabs) tab.screen],
      ),
      // 도감 보상/컬렉션 등록 알림 체인의 최종 집계 지점
      // (EncyclopediaManager.hasAnyCollectionReward)을 그대로 구독한다 —
      // 하위 슬롯 어디서든(다른 탭에 있는 동안에도) 알림이 생기면 캐릭터
      // 탭 아이콘의 레드닷이 즉시 갱신된다.
      bottomNavigationBar: AnimatedBuilder(
        animation: Listenable.merge([
          CollectionManager.instance,
          EncyclopediaManager.instance,
          EquipmentManager.instance,
        ]),
        builder: (context, _) {
          final bool showCollectionDot = EncyclopediaManager.instance.hasAnyCollectionReward;
          return BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            currentIndex: _selectedIndex,
            onTap: _onItemTapped,
            items: [
              for (final _NavTab tab in _navTabs)
                BottomNavigationBarItem(
                  icon: KeyedSubtree(
                    key: tab.label == '샵' ? TutorialManager.shopNavKey : null,
                    child: Badge(
                      isLabelVisible: tab.screen is CharacterScreen && showCollectionDot,
                      backgroundColor: Colors.redAccent,
                      smallSize: 10,
                      child: Icon(tab.icon),
                    ),
                  ),
                  label: tab.label,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 하단 탭 하나를 이루는 아이콘/라벨/화면 묶음. 이 배열 하나가 곧
/// BottomNavigationBarItem 순서와 IndexedStack 화면 순서의 단일 소스이므로
/// 둘이 어긋날 수 없고, 추후 [icon]을 커스텀 이미지로 교체할 때도 이 클래스
/// 하나만 손보면 된다.
class _NavTab {
  const _NavTab({required this.icon, required this.label, required this.screen});

  final IconData icon;
  final String label;
  final Widget screen;
}
