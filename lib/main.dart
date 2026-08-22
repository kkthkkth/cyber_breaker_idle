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
import 'managers/character_metadata_manager.dart';
import 'managers/collection_manager.dart';
import 'managers/config_manager.dart';
import 'managers/dungeon_manager.dart';
import 'managers/dungeon_reward_manager.dart';
import 'managers/encyclopedia_manager.dart';
import 'managers/equipment_manager.dart';
import 'managers/expedition_manager.dart';
import 'managers/equipment_set_manager.dart';
import 'managers/friend_manager.dart';
import 'managers/game_manager.dart';
import 'managers/guide_mission_manager.dart';
import 'managers/guild_manager.dart';
import 'managers/guild_raid_manager.dart';
import 'managers/guild_war_manager.dart';
import 'managers/iap_manager.dart';
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
import 'managers/profile_manager.dart';
import 'managers/quest_manager.dart';
import 'managers/rift_manager.dart';
import 'managers/rookie_attendance_manager.dart';
import 'managers/rune_manager.dart';
import 'managers/skill_manager.dart';
import 'managers/sound_manager.dart';
import 'managers/speed_manager.dart';
import 'managers/story_manager.dart';
import 'managers/supabase_manager.dart';
import 'managers/title_manager.dart';
import 'managers/talent_manager.dart';
import 'managers/tower_floor_manager.dart';
import 'managers/trade_manager.dart';
import 'managers/tutorial_manager.dart';
import 'managers/weekday_dungeon_manager.dart';
import 'managers/world_boss_manager.dart';
import 'models/consumable_item_model.dart';
import 'models/equipment.dart';
import 'models/story_model.dart';
import 'models/title_model.dart';
import 'models/trade_model.dart';
import 'widgets/tutorial_overlay.dart';
import 'ui/character_screen.dart';
import 'ui/comprehensive_stats_dialog.dart';
import 'ui/dungeon_screen.dart';
import 'ui/friend_screen.dart';
import 'ui/guild_screen.dart';
import 'ui/home_screen.dart';
import 'ui/login_screen.dart';
import 'ui/nickname_screen.dart';
import 'ui/offline_reward_dialog.dart';
import 'ui/shop_screen.dart';
import 'ui/skill_screen.dart';
import 'ui/top_bar.dart';
import 'ui/trade_screen.dart';
import 'utils/number_formatter.dart';
import 'widgets/center_toast.dart';
import 'widgets/story_dialog_widget.dart';
import 'widgets/total_combat_power_banner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );
  // 로컬 알림 권한 요청 — 다른 매니저들의 await 체인과 독립적이라(알림
  // 예약은 나중에 특정 이벤트 시점에만 실제로 쓰인다) 가장 먼저 끝내
  // 둔다. 지원하지 않는 플랫폼(Web/Windows)이면 내부에서 조용히 건너뛴다.
  await NotificationManager.instance.init();
  // 요구사항: "토요일 오후 8시 50분(시작 10분 전)" 길드 전쟁 알림 — 최초
  // 한 번만 예약하면 매주 자동으로 반복된다.
  unawaited(NotificationManager.instance.scheduleWeeklyWarStartReminder());
  // 길드원 목록의 접속중(🟢) 표시가 참조하는 profiles.last_seen 하트비트 —
  // 아직 로그인 전이면(게스트 로그인을 아직 안 거쳤으면) 매번 조용히
  // no-op하다가, 로그인 후 다음 주기(SupabaseManager.lastSeenInterval)부터
  // 실제로 갱신되기 시작한다.
  SupabaseManager.instance.startLastSeenHeartbeat();
  // 오프라인 보상의 "마지막 접속 시각" 마커를 30초마다 갱신한다 —
  // AppLifecycleState.paused/detached(앱 종료 시점)에만 의존하면, 웹
  // 브라우저에서 탭을 그냥 닫을 때는 그 생명주기 이벤트가 신뢰성 있게
  // 오지 않아 마커가 훨씬 이전 값에 멈춰 있을 수 있다
  // (OfflineRewardManager.startPeriodicAutoSave 문서 참고).
  OfflineRewardManager.instance.startPeriodicAutoSave();
  // SFX 프리로드 — 실패해도(assets/audio/ 파일 없음 등) 조용히 넘어가므로
  // 다른 매니저들의 await 체인을 막지 않는다.
  unawaited(SoundManager.instance.init());
  await EquipmentManager.instance.loadEquipment();
  // 상점 가챠 버튼(EquipmentManager.generateLootOfType/drawMultipleGacha)이
  // 곧바로 PityManager를 읽으므로, 상점 화면이 열리기 전에 끝나 있어야
  // 한다. 캐릭터 가챠는 추가로 CharacterManifestManager(아래, Supabase
  // master_characters)도 읽지만 그건 훨씬 나중에(EncyclopediaManager
  // 직전에) 로드된다 — runApp() 전에만 끝나면 되므로 문제없다.
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
  // GameManager.attackPower/defensePower/effectiveCriticalRate/
  // goldRewardForKill이 곧바로 TalentManager.totalBonus를 읽으므로, 전투가
  // 시작되기 전(runApp 이전)에 끝나 있어야 한다.
  await TalentManager.instance.loadData();
  // ExpeditionManager.claimReward가 특성 포인트 보상을 TalentManager로
  // 넘기므로, 그보다 뒤에 로드돼야 한다.
  await ExpeditionManager.instance.loadData();
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
  // 룬의 미궁/승리자의 성소 클리어(IdleGame._damageDungeonMonster)가 곧바로
  // DungeonRewardManager.grantRewardsFor를 읽으므로, 던전 화면이 열리기
  // 전(runApp 이전)에 끝나 있어야 한다.
  await DungeonRewardManager.instance.loadData();
  // IdleGame._fireProjectile이 공격마다 근접/원거리를 판정할 때 곧바로
  // 읽으므로, 마찬가지로 전투가 시작되기 전에 끝나 있어야 한다.
  await CharacterMetaManager.instance.loadData();
  // GameManager.attackPower/defensePower/maxHp/effectiveAttackSpeed가 곧바로
  // 장착 캐릭터의 기본 스탯을 읽으므로(character_metadata 기반), 전투가
  // 시작되기 전에 끝나 있어야 한다.
  await CharacterMetadataManager.instance.loadData();
  // GameManager.totalCombatPower가 곧바로 이 가중치(defWeight/offenseWeight)를
  // 읽으므로, 전투력 배너가 뜨는 화면(프로필 팝업 등)이 열리기 전에 끝나
  // 있어야 한다 — 실패해도 ConfigManager.combatPowerWeights가 안전한
  // 기본값(20.0/10.0)을 이미 들고 있어 게임 진행에는 영향이 없다.
  await ConfigManager.instance.loadConfig();
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
  await GuildWarManager.instance.loadData();
  // EquipmentManager.loadEquipment()가 이미 끝난 뒤라(위쪽), 지난 정산으로
  // 받은 휘장이 있으면 지금 바로 인벤토리에 반영/만료 회수한다.
  await GuildWarManager.instance.syncBadgeOnStartup();
  await ArenaManager.instance.loadData();
  // 상점 '무료 보상' 탭이 곧바로 AdManager.instance.canWatchAd/dailyAdViews를
  // 읽으므로, 화면이 뜨기 전(runApp 이전)에 끝나 있어야 한다. 지원하지
  // 않는 플랫폼(Web/Windows)이면 내부에서 조용히 건너뛴다.
  await AdManager.instance.loadData();
  // 상점 '충전' 탭이 곧바로 IAPManager.instance.products/isAvailable을
  // 읽으므로, 화면이 뜨기 전에 스토어 상품 조회가 끝나 있어야 한다. 구매
  // 스트림 구독도 이 안에서 시작하는데, 이전 세션에서 completePurchase가
  // 안 끝난 트랜잭션이 있으면 이 시점에 재전달되므로 최대한 앱 초반에
  // 호출해야 놓치지 않는다.
  await IAPManager.instance.loadData();
  // QuestManager.claimQuest가 BattlePassManager.addBpExp를 부르므로, 배틀패스
  // 보상 트랙(레벨/exp)이 먼저 로드돼 있어야 한다.
  await BattlePassManager.instance.loadData();
  await QuestManager.instance.loadData();
  await GuideMissionManager.instance.loadData();
  await RiftManager.instance.loadData();
  await TitleManager.instance.loadData();
  await TradeManager.instance.loadData();
  // 친구 목록/받은 요청은 다른 유저와 함께 바뀌는 서버 전용 상태라
  // 로컬 저장이 없다 — 부팅 시 한 번 미리 불러 둬야 앱바 친구 버튼
  // 배지(받은 요청 수)가 화면을 열기 전에도 정확하다. 부팅을 막지
  // 않도록 await하지 않는다.
  unawaited(FriendManager.instance.loadAll());
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
      // 디바운스된(최대 2초) 퀘스트 진행도 동기화가 그 시간을 못 채우고
      // 앱이 죽는 것을 막는다 — QuestManager.flushPendingSync 문서 참고.
      unawaited(QuestManager.instance.flushPendingSync());
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // 요구사항: "백그라운드로 내려가거나 종료될 때(paused, detached)
      // 오프라인 보상 MAX(24시간)/차원의 균열 충전(다음 자정) 알림을
      // 예약" — 내려갈 때마다 다시 계산해서 예약한다(다시 내릴 때마다
      // 이전 예약을 덮어쓴다).
      unawaited(NotificationManager.instance.scheduleOfflineReminder());
      unawaited(NotificationManager.instance.scheduleRiftReminder());
      // 요구사항: "ends_at 시간에 맞춰... 로컬 푸시 알림을 스케줄링" —
      // cancelAllReminders(resumed)가 진행 중인 탐험 알림도 함께 지우므로,
      // 위 두 알림과 같은 이유로 내려갈 때마다 남은 시간 기준으로 다시
      // 예약해 둔다(ExpeditionManager.rescheduleReturnNotifications 문서
      // 참고).
      unawaited(ExpeditionManager.instance.rescheduleReturnNotifications());
      // 요구사항: "paused 될 때도 한 번 더 업데이트" — 친구 목록의 온라인
      // 판정(profiles.last_seen 5분 이내)이 "마지막으로 본 시각"에
      // 최대한 가깝도록, 백그라운드로 내려가는 순간에도 한 번 더
      // 갱신해 둔다(하트비트 주기 최대 2분 오차를 줄인다).
      unawaited(SupabaseManager.instance.updateLastSeen());
    } else if (state == AppLifecycleState.resumed) {
      // 백그라운드에 있던 동안엔 startLastSeenHeartbeat()의 주기 타이머가
      // 계속 돌긴 하지만(모바일 OS가 지연시킬 수 있다), 포그라운드로
      // 돌아온 순간 즉시 한 번 더 갱신해 "접속중" 표시가 최대한 빨리
      // 정확해지게 한다.
      SupabaseManager.instance.updateLastSeen();
      // 요구사항: "resumed면 예약된 모든 로컬 알림을 취소" — cancelAll이
      // 매주 반복되는 길드 전쟁 알림도 함께 지우므로, 곧바로 다시
      // 예약해 둔다(NotificationManager.cancelAllReminders 문서 참고).
      unawaited(NotificationManager.instance.cancelAllReminders());
      unawaited(NotificationManager.instance.scheduleWeeklyWarStartReminder());
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
      ),
      home: const LoginScreen(),
    );
  }
}

/// [GameEntryScreen]이 지금 보여줘야 할 화면 — 프롤로그를 "이름을 묻기
/// 전/후"로 쪼개고 그 사이에 닉네임 입력을 끼워 넣기 위한 4단계 상태.
enum _EntryStep {
  /// N1이 쓰러진 주인공을 발견하고 이름을 묻는 데까지([prologueBeforeName]).
  prologueBeforeName,

  /// N1의 질문에 실제로 답하는 닉네임 입력 UI.
  nickname,

  /// 이름을 밝힌 직후 이어지는 후반부([prologueAfterName]).
  prologueAfterName,

  /// 프롤로그를 마친 뒤(또는 이미 마친 유저의 재실행) 보여주는 메인 로비.
  main,
}

/// 로그인 완료(자동 로그인 또는 [LoginScreen]의 게스트/구글 버튼) 직후
/// 실제로 진입하는 게임 화면.
///
/// 신규 유저는 프롤로그 전반부 → (N1이 이름을 묻는 장면 직후) 닉네임 입력
/// → 프롤로그 후반부 → 메인 로비 순서로 진행한다 — 닉네임 입력이 로그인
/// 직후가 아니라 프롤로그 서사 한가운데 자연스럽게 끼워지도록 이 화면이
/// 직접 단계를 관리한다([LoginScreen]은 더 이상 닉네임 유무를 보고
/// 갈라치지 않는다). 프롤로그를 이미 마친 유저는 곧장 메인 로비로 가되,
/// 아주 드물게(구버전 계정 등) 닉네임이 없다면 안전망으로 닉네임 입력만
/// 거치게 한다.
class GameEntryScreen extends StatefulWidget {
  const GameEntryScreen({super.key});

  @override
  State<GameEntryScreen> createState() => _GameEntryScreenState();
}

class _GameEntryScreenState extends State<GameEntryScreen> {
  // main()에서 StoryManager.instance.loadData()를 이미 await한 뒤 runApp이
  // 호출되므로, 이 시점엔 로컬 저장값이 확정돼 있다.
  late _EntryStep _step = _resolveInitialStep();

  _EntryStep _resolveInitialStep() {
    final bool hasNickname = ProfileManager.instance.nickname != null;
    if (StoryManager.instance.isPrologueCleared) {
      // 이미 프롤로그를 본 유저 — 정상적인 경우 닉네임도 이미 있다.
      // 구버전 계정 등으로 닉네임만 없는 드문 경우에만 안전망으로 다시 묻는다.
      return hasNickname ? _EntryStep.main : _EntryStep.nickname;
    }
    // 신규 유저(최초 실행) — 이름을 아직 안 밝혔다면 프롤로그 전반부부터,
    // 이미 밝혔지만 후반부를 못 본 채 앱이 죽었다면 후반부부터 이어본다.
    return hasNickname
        ? _EntryStep.prologueAfterName
        : _EntryStep.prologueBeforeName;
  }

  void _advanceToNickname() {
    setState(() => _step = _EntryStep.nickname);
  }

  void _onNicknameComplete() {
    // 프롤로그 도중(전반부 직후)이었는지, 이미 클리어한 유저의 안전망
    // 경로였는지에 따라 다음 목적지가 다르다.
    setState(() {
      _step = StoryManager.instance.isPrologueCleared
          ? _EntryStep.main
          : _EntryStep.prologueAfterName;
    });
  }

  /// 스토리를 끝까지 보든 스킵하든 결과는 동일하다: 초반 동료를 지급하고
  /// 클리어 플래그를 저장한 뒤 메인 화면으로 전환한다. 저장 자체는
  /// fire-and-forget으로 던진다 — GameManager.addCollectionBonus 등 이
  /// 프로젝트의 다른 저장 호출들과 같은 관례.
  void _onPrologueComplete() {
    EquipmentManager.instance.grantStarterCharacters();
    StoryManager.instance.markPrologueCleared();
    setState(() => _step = _EntryStep.main);
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _EntryStep.prologueBeforeName:
        return StoryDialogWidget(
          story: prologueBeforeName,
          onComplete: _advanceToNickname,
        );
      case _EntryStep.nickname:
        return NicknameScreen(onComplete: _onNicknameComplete);
      case _EntryStep.prologueAfterName:
        return StoryDialogWidget(
          story: prologueAfterName,
          onComplete: _onPrologueComplete,
        );
      case _EntryStep.main:
        return const MainNavigationScreen();
    }
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
    // GuideMissionBanner(홈 탭 내부 위젯)의 "바로가기" 버튼이 하단 탭을
    // 직접 전환할 방법이 없어([GuideMissionManager.onRequestTabSwitch]
    // 문서 참고) 기존 탭 탭(_onItemTapped)을 그대로 연결한다 — 튜토리얼
    // 진행 로직까지 동일하게 타므로 별도 처리가 필요 없다.
    GuideMissionManager.instance.onRequestTabSwitch = _onItemTapped;
    // 칭호 자동 획득 순간 토스트 — GameManager.onChapterAdvanced와 같은
    // 콜백 연결 관례(TitleManager.checkAndGrantTitles는 BuildContext가
    // 없는 매니저 계층에서 호출되므로, 실제 토스트는 화면 계층인 여기서
    // 띄운다).
    TitleManager.instance.onTitleGranted = _onTitleGranted;
    // 받은 거래 요청 팝업 — 화면과 무관하게 앱이 켜져 있는 동안 항상
    // 뜰 수 있어야 하므로(TradeManager.loadData가 이미 전역 구독을
    // 시작해 뒀다) 어느 탭에 있든 유효한 이 계층에서 처리한다.
    TradeManager.instance.onIncomingTradeRequest = _onIncomingTradeRequest;
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
    if (identical(
      GameManager.instance.onBossStageEntered,
      _onBossStageEntered,
    )) {
      GameManager.instance.onBossStageEntered = null;
    }
    if (identical(
      GuideMissionManager.instance.onRequestTabSwitch,
      _onItemTapped,
    )) {
      GuideMissionManager.instance.onRequestTabSwitch = null;
    }
    if (identical(
      TradeManager.instance.onIncomingTradeRequest,
      _onIncomingTradeRequest,
    )) {
      TradeManager.instance.onIncomingTradeRequest = null;
    }
    if (identical(TitleManager.instance.onTitleGranted, _onTitleGranted)) {
      TitleManager.instance.onTitleGranted = null;
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
    required int bpExpGained,
    required int runeFragmentsGained,
  }) {
    if (!mounted || _isOfflineRewardShowing) {
      return;
    }
    _isOfflineRewardShowing = true;
    showDialog<bool>(
      context: context,
      builder: (context) => OfflineRewardDialog(
        offlineSeconds: offlineSeconds,
        rewardGold: rewardGold,
        equipmentCount: equipmentCount,
        consumableDrops: consumableDrops,
        bpExpGained: bpExpGained,
        runeFragmentsGained: runeFragmentsGained,
      ),
    ).then((doubled) {
      // 바깥 탭/뒤로 가기로 닫히면 doubled가 null로 온다 — 그 경우도
      // "일반 수령"과 똑같이 취급한다(기존 관례 그대로 유지).
      OfflineRewardManager.instance.claimReward(
        rewardGold: rewardGold,
        offlineSeconds: offlineSeconds,
        equipmentCount: equipmentCount,
        consumableDrops: consumableDrops,
        bpExpGained: bpExpGained,
        runeFragmentsGained: runeFragmentsGained,
        doubled: doubled == true,
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
    final NavigatorState rootNavigator = Navigator.of(
      context,
      rootNavigator: true,
    );
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
      final StoryModel? opening = MainStoryManager.instance.pendingOpeningFor(
        manager.chapter,
      );
      if (opening != null) {
        _presentOpening(manager.chapter, opening);
      }
    } else if (manager.stage == GameManager.maxStage) {
      final StoryModel? bossIntro = MainStoryManager.instance
          .pendingBossIntroFor(manager.chapter);
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

    final StoryModel? opening = MainStoryManager.instance.pendingOpeningFor(
      chapter,
    );
    if (opening == null) {
      return;
    }
    Future.microtask(() => _presentOpening(chapter, opening));
  }

  void _onBossStageEntered(int chapter) {
    final StoryModel? bossIntro = MainStoryManager.instance.pendingBossIntroFor(
      chapter,
    );
    if (bossIntro == null) {
      return;
    }
    Future.microtask(() => _presentBossIntro(chapter, bossIntro));
  }

  void _onTitleGranted(PlayerTitle title) {
    if (!mounted) {
      return;
    }
    showCenterToast(context, '새 칭호 "${title.name}"을(를) 획득했습니다!');
  }

  /// [TradeManager.onIncomingTradeRequest] 콜백 — 요청자 닉네임을 조회한
  /// 뒤([FriendManager]가 이미 쓰던 [SupabaseManager.fetchProfilesByIds]를
  /// 재사용) 수락/거절 팝업을 띄운다.
  Future<void> _onIncomingTradeRequest(TradeSession request) async {
    if (!mounted) {
      return;
    }
    final List<Map<String, dynamic>> profiles = await SupabaseManager.instance
        .fetchProfilesByIds([request.userA]);
    if (!mounted) {
      return;
    }
    final String nickname = profiles.isEmpty
        ? '익명의 모험가'
        : (profiles.first['nickname'] as String? ?? '익명의 모험가');
    await showIncomingTradeRequestDialog(
      context,
      request: request,
      requesterNickname: nickname,
    );
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
      final Equipment reward = EquipmentManager.instance
          .grantChapter1Character();
      showCenterToast(context, '챕터 1 클리어 보상! ${reward.gradeBadgeLabel} 획득');
    } else if (chapter == 3) {
      final Equipment reward = EquipmentManager.instance
          .grantChapter2Character();
      showCenterToast(
        context,
        '챕터 2 클리어 보상! 새로운 동료 ${reward.gradeBadgeLabel} 합류',
      );
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
    if (TutorialManager.instance.currentStep == 1 &&
        _navTabs[index].label == '샵') {
      TutorialManager.instance.advance();
    }
  }

  /// 좌측 상단 '내 프로필' 버튼 — 예전엔 캐릭터 일러스트 팝업
  /// ([CharacterIllustrationDialog])을 띄웠지만, 그 팝업은 이제 캐릭터
  /// 탭의 성급(★) 갤러리에서만 연다(item_detail_dialog.dart의
  /// `_StarIllustrationGallery` 참고) — 이 버튼은 대신 종합 스탯 정보창
  /// ([ComprehensiveStatsDialog])을 연다(요구사항: "UI 스크롤 압박 해결").
  void _showComprehensiveStats() {
    // 연타 방지 — 이미 다른 라우트가 최상단으로 올라간 상태(직전 탭으로
    // 이미 이 다이얼로그나 다른 화면이 뜬 상태)라면 중복으로 또 띄우지
    // 않는다.
    final ModalRoute<dynamic>? currentRoute = ModalRoute.of(context);
    if (currentRoute != null && !currentRoute.isCurrent) {
      return;
    }

    showDialog<void>(
      context: context,
      builder: (context) => const ComprehensiveStatsDialog(),
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
        // 프로필 아이콘 하나만 남는다 — 예전엔 그 옆에 설정(톱니바퀴)
        // 아이콘도 있었지만, 새 레이아웃 순서(요구사항: "프로필 → 배속 →
        // 총 전투력 → 골드 → 보석")엔 그 자리가 없다. 설정 진입점을 아예
        // 없애지 않도록 [ComprehensiveStatsDialog]([_showComprehensiveStats],
        // 이 프로필 버튼이 여는 화면) 헤더 안에 톱니바퀴를 옮겨 뒀다.
        leading: IconButton(
          icon: const CircleAvatar(
            backgroundColor: Color(0xFF2C2C3A),
            child: Icon(Icons.person, color: Colors.white70),
          ),
          onPressed: _showComprehensiveStats,
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
        // 일일 퀘스트(옛 DailyQuestHudButton, 📜) 진입점은 인게임 화면의
        // 좌측 아이콘 열([_DailyQuestHudButton], home_screen.dart)로
        // 옮겼다 — 이 앱바에는 더 이상 없다.
        actions: [
          const SpeedButton(),
          // 상단바 정중앙에 총 전투력을 크게 강조한다(요구사항: "프로필 →
          // 배속 → 총 전투력(중앙) → 골드 → 보석"). 좁은 앱바 공간에서
          // 잘리지 않도록 Flexible + TotalCombatPowerBanner 내부의
          // FittedBox(scaleDown)가 함께 크기를 줄인다. ConfigManager도
          // 함께 구독해야 전투력 가중치가 바뀌어도 실시간으로 갱신된다.
          Flexible(
            child: AnimatedBuilder(
              animation: Listenable.merge([
                GameManager.instance,
                ConfigManager.instance,
              ]),
              builder: (context, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: TotalCombatPowerBanner(
                  combatPower: GameManager.instance.totalCombatPower,
                  fontSize: 15,
                  // 좁은 앱바 공간에 맞춰 "총 전투력:" 글씨 없이 숫자만
                  // 심플하게 보여준다(요구사항: "⚔️ 133,760"처럼).
                  showLabel: false,
                ),
              ),
            ),
          ),
          // Flexible로 감싸는 이유: 예전엔 이 통화 표시 Container가
          // AppBar.actions의 다른 자식들처럼 자기 콘텐츠 크기만큼 무한정
          // 늘어날 수 있었다 — 숫자가 커지면(수억~수조 단위) 좌측의
          // SpeedButton/전투력 배너를 화면 밖으로 밀어내거나 AppBar
          // 자체가 오버플로우될 수 있었다. Flexible이 AppBar 내부 Row가
          // 실제로 줄 수 있는 만큼만 차지하도록 제한하고, 그 안의
          // Text들도 ellipsis로 방어한다 — 다만 NumberFormatter의
          // K/M/B/T 축약 덕분에 실제로 이 한계에 걸릴 일은 거의 없다.
          Flexible(
            child: AnimatedBuilder(
              animation: GameManager.instance,
              builder: (context, _) {
                return Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF20202C),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF3A3A4A)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.monetization_on,
                        color: Colors.amber,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          NumberFormatter.format(
                            GameManager.instance.gold.toDouble(),
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      // 골드 충전 버튼 — 상점을 "충전" 탭으로 곧장 연다
                      // (요구사항).
                      _CurrencyAddButton(
                        onTap: () => showShopDialog(
                          context,
                          initialTabIndex: shopChargeTabIndex,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.diamond,
                        color: Colors.cyanAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          NumberFormatter.format(
                            GameManager.instance.gems.toDouble(),
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      // 보석 충전 버튼 — 골드 쪽과 동일하게 "충전" 탭으로
                      // 곧장 연다.
                      _CurrencyAddButton(
                        onTap: () => showShopDialog(
                          context,
                          initialTabIndex: shopChargeTabIndex,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // 친구 목록/온라인 상태 진입점 — 예전엔 이 앱바에 톱니바퀴(설정)
          // 아이콘이 있었지만 프로필 다이얼로그 헤더로 옮겨갔다(위 leading
          // 문서 참고) — 우측 끝에 새 친구 버튼을 둔다.
          const FriendHudButton(),
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
          final bool showCollectionDot =
              EncyclopediaManager.instance.hasAnyCollectionReward;
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
                      isLabelVisible:
                          tab.screen is CharacterScreen && showCollectionDot,
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
  const _NavTab({
    required this.icon,
    required this.label,
    required this.screen,
  });

  final IconData icon;
  final String label;
  final Widget screen;
}

/// 골드/보석 텍스트 바로 옆의 작고 둥근 재화 충전 버튼 — 탭하면
/// [showShopDialog]로 상점을 "충전" 탭까지 곧장 열어 준다(요구사항).
class _CurrencyAddButton extends StatelessWidget {
  const _CurrencyAddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: const Padding(
        // 골드/보석 숫자와 너무 붙지 않도록 아주 약간의 여백만 준다 —
        // Container 전체가 이미 Flexible이라 폭을 아껴야 한다.
        padding: EdgeInsets.only(left: 2),
        child: Icon(Icons.add_circle_outline, color: Colors.white54, size: 16),
      ),
    );
  }
}
