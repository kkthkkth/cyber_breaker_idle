import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/collection_model.dart';
import '../models/equipment.dart';
import '../models/quest_model.dart';
import '../models/skill_model.dart';
import 'consumable_manager.dart';
import 'equipment_manager.dart';
import 'guild_manager.dart';
import 'monster_drop_manager.dart';
import 'pet_manager.dart';
import 'quest_manager.dart';
import 'skill_manager.dart';
import 'speed_manager.dart';

class Skill {
  Skill({
    required this.id,
    required this.name,
    required this.icon,
    required this.cost,
    required this.cooldown,
    this.isLearned = false,
    this.lastUsedTime,
  });

  final String id;
  final String name;
  final IconData icon;
  final int cost;
  final double cooldown;
  bool isLearned;
  DateTime? lastUsedTime;

  double get cooldownRemaining {
    if (lastUsedTime == null) {
      return 0;
    }
    final double elapsed =
        DateTime.now().difference(lastUsedTime!).inMilliseconds / 1000.0;
    // Speed boosts make cooldowns tick down faster: elapsed wall-clock time
    // counts for `activeSpeed`x as much against the fixed cooldown.
    final double scaledElapsed =
        elapsed * SpeedManager.instance.gameSpeedMultiplier;
    final double remaining = cooldown - scaledElapsed;
    return remaining > 0 ? remaining : 0;
  }

  bool get isReady => isLearned && cooldownRemaining <= 0;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'isLearned': isLearned,
      'lastUsedTime': lastUsedTime?.millisecondsSinceEpoch,
    };
  }

  // icon/name/cost/cooldown come from the static catalog (not persisted,
  // since IconData isn't meaningfully JSON-serializable) — the caller
  // passes the matching catalog skill's fields back in.
  factory Skill.fromJson(
    Map<String, dynamic> json, {
    required String name,
    required IconData icon,
    required int cost,
    required double cooldown,
  }) {
    final int? lastUsedMillis = json['lastUsedTime'] as int?;
    return Skill(
      id: json['id'] as String,
      name: name,
      icon: icon,
      cost: cost,
      cooldown: cooldown,
      isLearned: json['isLearned'] as bool? ?? false,
      lastUsedTime: lastUsedMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(lastUsedMillis)
          : null,
    );
  }
}

class GameManager extends ChangeNotifier {
  GameManager._internal() {
    _resetMonsterHp();
    EquipmentManager.instance.addListener(notifyListeners);
  }

  static final GameManager instance = GameManager._internal();

  static const int maxStage = 10;
  static const double bossTimeLimit = 30.0;

  /// 기존(레거시) 장비 드랍 확률 — [_onMonsterDefeated]의 "즉시 장비 1개
  /// 지급" 판정 전용 상수다. 새로 추가된 플레이어 스탯 [itemDropRate](기본
  /// 0%, 골드 강화/장비 옵션으로 오르는 값)와 이름이 겹치지 않도록
  /// `_legacyEquipmentDropRate`로 이름을 바꿨다 — 이 상수 자체의 동작은
  /// 그대로 유지했다(monster_drop_table 기반 신규 드랍 시스템은 완전히
  /// 별도 경로로 추가된 것이지, 이 레거시 메커니즘을 대체하지 않는다).
  static const double _legacyEquipmentDropRate = 0.3;
  static const double skillMinMultiplier = 5.0;
  static const double skillMaxMultiplier = 10.0;

  // ── 절대 스테이지 번호 ↔ (챕터, 서브스테이지) 변환 ──────────────────
  // 프로젝트 전체에서 "절대 스테이지 번호로부터 챕터/서브스테이지를
  // 구한다"는 계산은 반드시 이 두 함수를 거친다 — [_onMonsterDefeated](다음
  // 스테이지 진행)와 [_regressOneStage](패배/시간초과 강등) 둘 다 여기로
  // 수렴하므로, 챕터 경계(10 스테이지마다)가 어긋날 여지가 없는 단일 소스다.
  static int chapterOf(int stageNumber) => ((stageNumber - 1) ~/ maxStage) + 1;

  static int subStageOf(int stageNumber) => ((stageNumber - 1) % maxStage) + 1;

  /// [chapter]/[stage](서브스테이지)를 절대 스테이지 번호로 합친 값 —
  /// [chapterOf]/[subStageOf]의 역변환.
  int get absoluteStage => (chapter - 1) * maxStage + stage;

  final List<Skill> skills = [
    Skill(
      id: 'meteor_strike',
      name: '메테오 스트라이크',
      icon: Icons.whatshot,
      cost: 500,
      cooldown: 10.0,
    ),
    Skill(
      id: 'blizzard',
      name: '블리자드',
      icon: Icons.ac_unit,
      cost: 800,
      cooldown: 15.0,
    ),
    Skill(
      id: 'thunder_strike',
      name: '썬더 스트라이크',
      icon: Icons.bolt,
      cost: 1200,
      cooldown: 20.0,
    ),
  ];

  int gold = 0;
  int gems = 0;
  int chapter = 1;
  int stage = 1;

  /// 10 챕터 단위 최초 돌파 SP 보상이 반복 파밍으로 중복 지급되지 않도록
  /// 막는 커서 — 지급된 챕터 번호까지만 갱신되고, 그 이하 챕터를 다시
  /// 지나가도(예: 보스 실패 후 재도전) 다시 지급되지 않는다.
  int highestReachedChapter = 1;

  double monsterHp = 0;
  double monsterMaxHp = 0;

  double baseAttackPower = 10;
  double attackSpeed = 1.0;
  double criticalRate = 0.05;
  double criticalMultiplier = 2.0;

  /// 장착 펫의 "크리티컬 데미지 증폭" 옵션까지 더한 최종 크리티컬 배율.
  /// criticalMultiplier 자체가 이미 배율 단위(2.0 == 200%)라 펫 옵션값
  /// (0.05 == +5%)을 그대로 더하면 된다.
  double get effectiveCriticalMultiplier =>
      criticalMultiplier +
      PetManager.instance.criticalDamageBoost +
      EquipmentManager.instance.getTotalSubStatBonus(EquipmentStatType.criticalDamage);

  int attackLevel = 1;
  int attackSpeedLevel = 1;
  int criticalRateLevel = 1;

  static const double _maxCriticalRate = 0.75;

  // ── 방어 스탯 4종 (골드로 업그레이드) ──────────────────────────────
  double baseDefense = 0;
  double defenseRate = 0.0;
  double evasionRate = 0.0;
  double critDefenseRate = 0.0;

  int defenseLevel = 1;
  int defenseRateLevel = 1;
  int evasionRateLevel = 1;
  int critDefenseRateLevel = 1;

  static const double _maxDefenseRate = 0.8;
  static const double _maxEvasionRate = 0.5;
  static const double _maxCritDefenseRate = 0.8;

  // ── 아이템 드랍 확률 (신규 monster_drop_table 시스템 전용) ────────────
  //
  // 몬스터 처치 시 monster_drop_table의 각 항목 확률에 곱산으로 적용되는
  // 플레이어 스탯 — 기본 0%, 골드 강화나 장비 옵션으로 오를 수 있는
  // 구조로 만들어 뒀다(둘 다 아직 실제 업그레이드 UI/장비 옵션 타입으로는
  // 연결하지 않았다 — 이 필드 자체가 그 확장의 준비 지점이다). 위의
  // [_legacyEquipmentDropRate](기존 30% 즉시 장비 드랍)와는 완전히 별개
  // 경로라 서로 영향을 주지 않는다.
  double itemDropRate = 0.0;

  // ── 플레이어 HP ─────────────────────────────────────────────────
  double maxHp = 200;
  double currentHp = 200;

  bool get isPlayerDefeated => currentHp <= 0;

  // ── 몬스터 공격 스탯 (메인 스테이지 진행도에 비례, _resetMonsterHp에서
  // 함께 갱신) ────────────────────────────────────────────────────
  double monsterAttackPower = 0;
  double monsterAttackSpeed = 0.5;

  static const double _monsterBaseCritRate = 0.15;
  static const double _monsterCritMultiplier = 1.5;

  /// 도감(Collection) 완성 보상으로 쌓이는 영구 스탯 보너스 — 장착/해제와
  /// 무관하게 항상 합산된다. [CollectionManager.register]가 완료 시점에
  /// 한 번만 [addCollectionBonus]를 호출해 누적한다.
  final Map<CollectionStatType, double> collectionBonuses = {
    for (final CollectionStatType type in CollectionStatType.values) type: 0.0,
  };

  void addCollectionBonus(CollectionStatType type, double value) {
    collectionBonuses[type] = (collectionBonuses[type] ?? 0) + value;
    notifyListeners();
    saveGame();
  }

  final Random _random = Random();

  double bossTimeRemaining = bossTimeLimit;

  /// Fired when a skill successfully activates, so Flame can play the effect.
  void Function(Skill skill)? onSkillUsed;

  /// Fired the moment [chapter] advances into a brand-new chapter's first
  /// stage (right after a boss clear) — [_MainNavigationScreenState] uses
  /// this to trigger that chapter's main-story cutscene
  /// ([MainStoryManager]/[seasonOneMainStory]). Not fired for ordinary
  /// stage advances within the same chapter, and not fired on cold start
  /// (main.dart checks the current chapter once at startup for that case).
  void Function(int chapter)? onChapterAdvanced;

  /// Fired the moment [stage] first reaches [maxStage] within the current
  /// [chapter] — i.e. the boss stage was just entered ("보스 몬스터가
  /// 등장할 때"). [_MainNavigationScreenState] uses this to trigger that
  /// chapter's boss-intro cutscene. Only fires once per approach (retrying
  /// a failed boss attempt drops [stage] back to maxStage-1 via
  /// [applyDefeatPenalty], so clearing stage 9 again re-fires this — but
  /// [MainStoryManager] already gates the actual popup to "first time only").
  void Function(int chapter)? onBossStageEntered;

  bool get isBossStage => stage == maxStage;

  /// 펫 패시브 스킬은 장착된 펫(EquipType.pet)이 1개 이상 있을 때만 합산되고,
  /// 해제하는 즉시(다음 계산부터) 0으로 취급된다 — 캐시하지 않고 매번 조회.
  bool get _hasPetEquipped =>
      EquipmentManager.instance.equippedItems[EquipType.pet] != null;

  double get attackPower {
    double power = baseAttackPower *
        (1 + EquipmentManager.instance.getTotalEquipmentMultiplier());
    if (_hasPetEquipped) {
      power *= 1 + SkillManager.instance.petPassiveBonus(PetPassiveType.attackPower);
    }
    power *= 1 + (collectionBonuses[CollectionStatType.attackPower] ?? 0);
    // 장착 펫(신규 Pet 모델)의 "최종 공격력 증폭" 옵션 — 위의 스킬트리 기반
    // petPassiveBonus와는 별개 소스라 곱산이 한 번 더 들어간다.
    power *= 1 + PetManager.instance.finalAttackBoost;
    // 장비 서브 옵션(EquipmentStatType.attack)의 "공격력" 값 — statMultiplier
    // 기반 getTotalEquipmentMultiplier()와는 별개 소스라 곱산이 한 번 더 들어간다.
    power *= 1 + EquipmentManager.instance.getTotalSubStatBonus(EquipmentStatType.attack);
    // 길드 레벨에 비례한 수동 버프 — 미가입 상태면 GuildManager.attackBonus가
    // 0이라 곱산에 영향이 없다.
    power *= 1 + GuildManager.instance.attackBonus;
    return power;
  }

  /// 장착 중인 실제 공격 속도 — 골드로 올린 기본치([attackSpeed])에 장비
  /// 서브 옵션(EquipmentStatType.attackSpeed)의 % 보너스를 곱해 반영한다.
  /// 전투 루프(IdleGame)와 스킬 데미지 계산은 반드시 이 값을 써야 한다.
  double get effectiveAttackSpeed =>
      attackSpeed * (1 + EquipmentManager.instance.getTotalSubStatBonus(EquipmentStatType.attackSpeed));

  /// 스킬 크리티컬 판정에 실제로 쓰이는 확률 — 업그레이드로 쌓인 [criticalRate]에
  /// 펫이 장착돼 있을 때만 크리티컬 확률 증가 패시브를, 도감 보너스와 장비
  /// 서브 옵션(EquipmentStatType.criticalRate)은 항상 더한다.
  double get effectiveCriticalRate {
    double rate = criticalRate;
    if (_hasPetEquipped) {
      rate += SkillManager.instance.petPassiveBonus(PetPassiveType.criticalRate);
    }
    rate += collectionBonuses[CollectionStatType.criticalRate] ?? 0;
    rate += EquipmentManager.instance.getTotalSubStatBonus(EquipmentStatType.criticalRate);
    return rate.clamp(0.0, _maxCriticalRate);
  }

  /// 장비 옵션 + 도감 보너스까지 합산된 최종 방어력(고정 수치).
  double get defensePower {
    double value = baseDefense + EquipmentManager.instance.getTotalDefenseBonus();
    value += collectionBonuses[CollectionStatType.defense] ?? 0;
    return value;
  }

  double get effectiveDefenseRate {
    final double rate = defenseRate +
        EquipmentManager.instance.getTotalDefenseRateBonus() +
        (collectionBonuses[CollectionStatType.defenseRate] ?? 0);
    return rate.clamp(0.0, _maxDefenseRate);
  }

  double get effectiveEvasionRate {
    final double rate = evasionRate +
        EquipmentManager.instance.getTotalEvasionRateBonus() +
        (collectionBonuses[CollectionStatType.evasionRate] ?? 0);
    return rate.clamp(0.0, _maxEvasionRate);
  }

  /// 몬스터가 플레이어를 때릴 때 크리티컬(추가 피해)이 뜰 확률을 깎는 값 —
  /// [_monsterBaseCritRate]에서 이만큼 빠진다.
  double get effectiveCritDefenseRate {
    final double rate = critDefenseRate +
        EquipmentManager.instance.getTotalCritDefenseRateBonus() +
        (collectionBonuses[CollectionStatType.critDefenseRate] ?? 0);
    return rate.clamp(0.0, _maxCritDefenseRate);
  }

  double get goldPerHour => attackPower * effectiveAttackSpeed * 60;

  /// 몬스터 1마리를 처치하는 데 평균적으로 필요한 타격 횟수 — 실제
  /// 스테이지별 몬스터 HP 스케일링을 시뮬레이션하지 않고 [goldPerHour]와
  /// 같은 성격의 단순화된 근사치를 낸다. 정확한 밸런스 데이터가 없어
  /// 임의로 정한 값이니, 기획 수치가 정해지면 이 상수만 바꾸면 된다.
  /// [OfflineRewardManager]가 오프라인 아이템 드랍 기댓값을 계산할 때만
  /// 쓰는 값이라, 실제 온라인 전투(몬스터 HP를 직접 깎는 방식)에는 전혀
  /// 관여하지 않는다.
  static const double _averageHitsPerKill = 8.0;

  /// 오프라인 방치 보상의 "예상 처치 수" 계산 전용 — [effectiveAttackSpeed]
  /// (초당 타격 횟수)를 [_averageHitsPerKill]로 나눈 값을 시간당으로
  /// 환산한다.
  double get estimatedKillsPerHour => (effectiveAttackSpeed * 3600) / _averageHitsPerKill;

  int get attackUpgradeCost => (50 * pow(1.15, attackLevel - 1)).round();

  int get speedUpgradeCost => (80 * pow(1.2, attackSpeedLevel - 1)).round();

  int get criticalUpgradeCost => (100 * pow(1.18, criticalRateLevel - 1)).round();

  int get defenseUpgradeCost => (50 * pow(1.15, defenseLevel - 1)).round();

  int get defenseRateUpgradeCost => (90 * pow(1.2, defenseRateLevel - 1)).round();

  int get evasionRateUpgradeCost => (90 * pow(1.2, evasionRateLevel - 1)).round();

  int get critDefenseRateUpgradeCost => (90 * pow(1.2, critDefenseRateLevel - 1)).round();

  void _resetMonsterHp() {
    const double base = 50.0;
    final int progressIndex = (chapter - 1) * maxStage + (stage - 1);
    double hp = base * pow(1.15, progressIndex);
    double attack = 5 + progressIndex * 1.5;

    if (isBossStage) {
      hp *= 5;
      attack *= 2;
      bossTimeRemaining = bossTimeLimit;
    }

    monsterMaxHp = hp;
    monsterHp = hp;
    monsterAttackPower = attack;
  }

  /// 몬스터가 플레이어를 공격 — 회피 성공 시 데미지 0, 아니면 방어력→방어율
  /// 순으로 감산한 뒤(몬스터 크리티컬이 뜨면 그 위에 배율 적용) 체력에서
  /// 뺀다. 체력이 0 이하가 되면 [playerDefeated]가 true로 돌아오지만, 실제
  /// 패배 페널티([applyDefeatPenalty])는 여기서 곧바로 적용하지 않는다 —
  /// IdleGame이 피격 포즈 전환 → 화면 페이드아웃 연출을 먼저 재생하고,
  /// 화면이 완전히 검게 덮인 순간에 직접 호출해야 스테이지 번호/체력바가
  /// 화면이 어두워지기도 전에 미리 바뀌어 보이는 일이 없다.
  ({bool playerDefeated, bool evaded, bool isCritical, double damageDealt}) resolveMonsterAttack() {
    final bool evaded = _random.nextDouble() < effectiveEvasionRate;
    if (evaded) {
      return (playerDefeated: false, evaded: true, isCritical: false, damageDealt: 0);
    }

    final double monsterCritRate =
        (_monsterBaseCritRate - effectiveCritDefenseRate).clamp(0.0, 1.0);
    final bool isCritical = _random.nextDouble() < monsterCritRate;

    double rawDamage = monsterAttackPower;
    if (isCritical) {
      rawDamage *= _monsterCritMultiplier;
    }

    final double mitigated = (rawDamage - defensePower).clamp(0.0, double.infinity);
    final double finalDamage = mitigated * (1 - effectiveDefenseRate);

    currentHp = (currentHp - finalDamage).clamp(0.0, maxHp);
    notifyListeners();

    return (
      playerDefeated: currentHp <= 0,
      evaded: false,
      isCritical: isCritical,
      damageDealt: finalDamage,
    );
  }

  /// [PotionManager]가 장착된 물약을 자동 소비했을 때 호출 — [percentOfMaxHp]
  /// (0~100)만큼 [maxHp] 대비 비율로 즉시 회복시킨다. 실제로 회복된 절대량을
  /// 반환한다(데미지 텍스트처럼 화면에 "+N" 연출을 띄우고 싶을 때 호출부가
  /// 바로 쓸 수 있도록).
  double healPlayer(double percentOfMaxHp) {
    final double healAmount = maxHp * (percentOfMaxHp / 100);
    final double before = currentHp;
    currentHp = (currentHp + healAmount).clamp(0.0, maxHp);
    notifyListeners();
    return currentHp - before;
  }

  /// 절대 스테이지를 1 낮춘다(최소 1-1 고정) — 플레이어 사망/보스전 제한
  /// 시간 초과 양쪽 모두 이 메서드 하나로 수렴한다. 챕터 경계도 자연스럽게
  /// 넘나든다(예: 12-1에서 패배하면 11-10으로 복귀) — 예전에는 stage==1
  /// (챕터의 첫 스테이지)에서 패배하면 `stage > 1` 조건에 걸리지 않아
  /// 아무 데도 후퇴하지 않는 빈틈이 있었다.
  void _regressOneStage() {
    final int previousAbsoluteStage = max(1, absoluteStage - 1);
    chapter = GameManager.chapterOf(previousAbsoluteStage);
    stage = GameManager.subStageOf(previousAbsoluteStage);
  }

  /// 패배 페널티(스테이지 1 강등 + 체력 완전 회복 + 몬스터 리셋)를
  /// 적용한다 — 'HP 0 도달'과 '보스전 제한시간 초과' 두 트리거 모두 이
  /// 메서드 하나로 수렴한다. IdleGame이 피격 포즈 → 화면 페이드아웃 연출이
  /// 화면을 완전히 검게 덮은 "바로 그 순간"에만 호출하도록 되어 있다(그
  /// 전에 호출하면 화면이 어두워지기도 전에 스테이지/체력이 바뀌어 보인다).
  void applyDefeatPenalty() {
    _regressOneStage();

    currentHp = maxHp;
    _resetMonsterHp();
    notifyListeners();
    saveGame();
  }

  ({Equipment? droppedItem, int goldReward}) damageMonster(double damage) {
    if (monsterHp <= 0) {
      return (droppedItem: null, goldReward: 0);
    }

    double effectiveDamage = damage;
    if (isBossStage) {
      if (_hasPetEquipped) {
        effectiveDamage *= 1 + SkillManager.instance.petPassiveBonus(PetPassiveType.bossDamage);
      }
      // 장착 펫(신규 Pet 모델)의 "보스 데미지 증가" 옵션 — 스킬트리 기반
      // petPassiveBonus와는 별개 소스라 곱산이 한 번 더 들어간다.
      effectiveDamage *= 1 + PetManager.instance.bossDamageBonus;
    }

    monsterHp -= effectiveDamage;
    ({Equipment? droppedItem, int goldReward}) result =
        (droppedItem: null, goldReward: 0);
    if (monsterHp <= 0) {
      monsterHp = 0;
      result = _onMonsterDefeated();
    }
    notifyListeners();
    return result;
  }

  ({Equipment? droppedItem, int goldReward}) _onMonsterDefeated() {
    // 스테이지 클리어(몬스터 처치) 보상으로 플레이어 체력을 완전히 회복시킨다
    // — 호출부인 damageMonster()가 끝에서 항상 notifyListeners()를 호출하므로
    // 전투 화면 HP바에 별도 처리 없이 바로 반영된다.
    currentHp = maxHp;

    // 일일 퀘스트("몬스터 N마리 처치") 진행도 — 몬스터 처치는 매우 잦은
    // 이벤트라 QuestManager가 스스로 서버 동기화를 디바운스한다(여기서는
    // 그냥 부담 없이 매번 호출).
    QuestManager.instance.updateProgress(QuestActionType.monsterKill, 1);

    int goldReward = (10 * chapter * stage).round();
    if (_hasPetEquipped) {
      goldReward = (goldReward * (1 + SkillManager.instance.petPassiveBonus(PetPassiveType.coinRate))).round();
    }
    // 장착 펫(신규 Pet 모델)의 "골드 획득 증가" 옵션 — 스킬트리 기반
    // petPassiveBonus와는 별개 소스라 곱산이 한 번 더 들어간다.
    goldReward = (goldReward * (1 + PetManager.instance.goldGainBonus)).round();
    // 길드 레벨에 비례한 수동 버프 — 미가입 상태면 GuildManager.goldBonus가
    // 0이라 곱산에 영향이 없다.
    goldReward = (goldReward * (1 + GuildManager.instance.goldBonus)).round();

    final double effectiveDropRate =
        (_legacyEquipmentDropRate * (1 + PetManager.instance.dropRateBonus)).clamp(0.0, 1.0);
    final Equipment? droppedItem = _random.nextDouble() < effectiveDropRate
        ? EquipmentManager.instance.generateRandomLoot()
        : null;

    ConsumableManager.instance.rollDrops();

    // 신규 monster_drop_table 기반 드랍 — 위의 레거시 30% 즉시 장비 드랍/
    // rollDrops()와는 완전히 별개 경로로 추가 지급된다(항목별로 독립
    // 판정되므로 한 번의 처치에서 여러 개가 동시에 나올 수도, 하나도 안
    // 나올 수도 있다).
    MonsterDropTableManager.instance.rollDropsForKill(
      chapter: chapter,
      itemDropRate: itemDropRate,
    );

    // 다음 (챕터, 서브스테이지)는 항상 [chapterOf]/[subStageOf] 공식 하나로만
    // 유도한다 — 예전에는 여기서 "stage==maxStage면 chapter++ / 아니면
    // stage++"를 손으로 직접 굴렸는데, [_regressOneStage]는 이미 같은 공식을
    // 쓰고 있어 두 로직이 서로 다른 곳에서 따로 챕터 경계를 판정하는
    // 셈이었다(값 자체는 우연히 같았지만 소스가 둘로 나뉘어 있었다). 이제는
    // "방금 깬 절대 스테이지 + 1"을 공식에 넣는 방식 하나로 합쳐서, 챕터
    // 전환이 정확히 10 스테이지마다(서브스테이지 1로 새로 진입할 때만)
    // 일어난다는 게 코드상으로도 명백해진다.
    final int nextAbsoluteStage = absoluteStage + 1;
    chapter = GameManager.chapterOf(nextAbsoluteStage);
    stage = GameManager.subStageOf(nextAbsoluteStage);

    if (stage == 1) {
      // 새 챕터의 첫 스테이지(1-1, 11-1, 21-1...)에 "방금" 진입했다 —
      // 오프닝 스토리/배경 전환 트리거.
      onChapterAdvanced?.call(chapter);

      // 10, 20, 30... 챕터에 "처음" 도달했을 때만 캐릭터 SP 1을 지급한다.
      if (chapter % 10 == 0 && chapter > highestReachedChapter) {
        SkillManager.instance.addSkillPoints(1);
        highestReachedChapter = chapter;
        saveGame();
      }
    } else if (stage == maxStage) {
      // 챕터의 보스 스테이지(1-10, 11-10, 21-10...)에 "방금" 진입했다 —
      // 보스 인트로 스토리 트리거.
      onBossStageEntered?.call(chapter);
    }
    _resetMonsterHp();
    return (droppedItem: droppedItem, goldReward: goldReward);
  }

  void addGold(int amount) {
    if (amount <= 0) {
      return;
    }
    gold += amount;
    notifyListeners();
  }

  bool spendGold(int amount) {
    if (amount <= 0 || gold < amount) {
      return false;
    }
    gold -= amount;
    notifyListeners();
    return true;
  }

  void addGems(int amount) {
    if (amount <= 0) {
      return;
    }
    gems += amount;
    notifyListeners();
  }

  bool spendGems(int amount) {
    if (amount <= 0 || gems < amount) {
      return false;
    }
    gems -= amount;
    notifyListeners();
    return true;
  }

  /// 보스 제한시간을 [dt]만큼 깎는다. 이번 호출에서 "방금" 0 이하로
  /// 떨어졌으면 true를 반환한다 — [resolveMonsterAttack]과 마찬가지로 실제
  /// 패배 페널티는 여기서 곧바로 적용하지 않는다. IdleGame이 이 신호를 받아
  /// 피격 포즈 → 화면 페이드아웃 연출을 먼저 재생한 뒤, 화면이 완전히
  /// 검어진 순간 [applyDefeatPenalty]를 직접 호출한다.
  bool tickBossTimer(double dt) {
    if (!isBossStage || bossTimeRemaining <= 0) {
      return false;
    }

    bossTimeRemaining -= dt;
    if (bossTimeRemaining <= 0) {
      bossTimeRemaining = 0;
      return true;
    }
    return false;
  }

  bool upgradeAttack() {
    final int cost = attackUpgradeCost;
    if (gold < cost) {
      return false;
    }

    gold -= cost;
    attackLevel++;
    baseAttackPower += 5;
    notifyListeners();
    return true;
  }

  bool upgradeAttackSpeed() {
    final int cost = speedUpgradeCost;
    if (gold < cost) {
      return false;
    }

    gold -= cost;
    attackSpeedLevel++;
    attackSpeed += 0.1;
    notifyListeners();
    return true;
  }

  bool upgradeCriticalRate() {
    final int cost = criticalUpgradeCost;
    if (gold < cost) {
      return false;
    }

    gold -= cost;
    criticalRateLevel++;
    criticalRate = (criticalRate + 0.01).clamp(0.0, _maxCriticalRate);
    notifyListeners();
    return true;
  }

  bool upgradeDefense() {
    final int cost = defenseUpgradeCost;
    if (gold < cost) {
      return false;
    }

    gold -= cost;
    defenseLevel++;
    baseDefense += 2;
    notifyListeners();
    return true;
  }

  bool upgradeDefenseRate() {
    final int cost = defenseRateUpgradeCost;
    if (gold < cost) {
      return false;
    }

    gold -= cost;
    defenseRateLevel++;
    defenseRate = (defenseRate + 0.01).clamp(0.0, _maxDefenseRate);
    notifyListeners();
    return true;
  }

  bool upgradeEvasionRate() {
    final int cost = evasionRateUpgradeCost;
    if (gold < cost) {
      return false;
    }

    gold -= cost;
    evasionRateLevel++;
    evasionRate = (evasionRate + 0.005).clamp(0.0, _maxEvasionRate);
    notifyListeners();
    return true;
  }

  bool upgradeCritDefenseRate() {
    final int cost = critDefenseRateUpgradeCost;
    if (gold < cost) {
      return false;
    }

    gold -= cost;
    critDefenseRateLevel++;
    critDefenseRate = (critDefenseRate + 0.01).clamp(0.0, _maxCritDefenseRate);
    notifyListeners();
    return true;
  }

  ({double damage, bool isCritical}) rollAttack() {
    final bool isCritical = _random.nextDouble() < effectiveCriticalRate;
    final double damage =
        isCritical ? attackPower * effectiveCriticalMultiplier : attackPower;
    return (damage: damage, isCritical: isCritical);
  }

  bool learnSkill(String skillId) {
    final Skill skill = skills.firstWhere((s) => s.id == skillId);
    if (skill.isLearned || gold < skill.cost) {
      return false;
    }

    gold -= skill.cost;
    skill.isLearned = true;
    notifyListeners();
    return true;
  }

  bool useActiveSkill(String skillId) {
    final Skill skill = skills.firstWhere((s) => s.id == skillId);
    if (!skill.isReady) {
      return false;
    }

    skill.lastUsedTime = DateTime.now();
    notifyListeners();
    onSkillUsed?.call(skill);
    return true;
  }

  double rollSkillDamage() {
    final double multiplier = skillMinMultiplier +
        _random.nextDouble() * (skillMaxMultiplier - skillMinMultiplier);
    return attackPower * multiplier;
  }

  static const String _saveKey = 'game_manager_save';

  Future<void> saveGame() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final Map<String, dynamic> data = {
      'gold': gold,
      'gems': gems,
      'chapter': chapter,
      'stage': stage,
      'highestReachedChapter': highestReachedChapter,
      'attackLevel': attackLevel,
      'attackSpeedLevel': attackSpeedLevel,
      'criticalRateLevel': criticalRateLevel,
      'baseAttackPower': baseAttackPower,
      'attackSpeed': attackSpeed,
      'criticalRate': criticalRate,
      'defenseLevel': defenseLevel,
      'defenseRateLevel': defenseRateLevel,
      'evasionRateLevel': evasionRateLevel,
      'critDefenseRateLevel': critDefenseRateLevel,
      'baseDefense': baseDefense,
      'defenseRate': defenseRate,
      'evasionRate': evasionRate,
      'critDefenseRate': critDefenseRate,
      'itemDropRate': itemDropRate,
      'maxHp': maxHp,
      'skills': skills.map((skill) => skill.toJson()).toList(),
      'collectionBonuses': {
        for (final MapEntry<CollectionStatType, double> entry in collectionBonuses.entries)
          entry.key.name: entry.value,
      },
    };

    await prefs.setString(_saveKey, jsonEncode(data));
    debugPrint('Game saved: gold=$gold, chapter=$chapter, stage=$stage');
  }

  Future<void> loadGame() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      debugPrint('Game loaded: no saved data found under "$_saveKey"');
      return;
    }

    final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;

    gold = data['gold'] as int? ?? gold;
    gems = data['gems'] as int? ?? gems;
    chapter = data['chapter'] as int? ?? chapter;
    highestReachedChapter =
        data['highestReachedChapter'] as int? ?? highestReachedChapter;
    stage = data['stage'] as int? ?? stage;
    attackLevel = data['attackLevel'] as int? ?? attackLevel;
    attackSpeedLevel = data['attackSpeedLevel'] as int? ?? attackSpeedLevel;
    criticalRateLevel = data['criticalRateLevel'] as int? ?? criticalRateLevel;
    baseAttackPower =
        (data['baseAttackPower'] as num?)?.toDouble() ?? baseAttackPower;
    attackSpeed = (data['attackSpeed'] as num?)?.toDouble() ?? attackSpeed;
    criticalRate = (data['criticalRate'] as num?)?.toDouble() ?? criticalRate;
    defenseLevel = data['defenseLevel'] as int? ?? defenseLevel;
    defenseRateLevel = data['defenseRateLevel'] as int? ?? defenseRateLevel;
    evasionRateLevel = data['evasionRateLevel'] as int? ?? evasionRateLevel;
    critDefenseRateLevel =
        data['critDefenseRateLevel'] as int? ?? critDefenseRateLevel;
    baseDefense = (data['baseDefense'] as num?)?.toDouble() ?? baseDefense;
    defenseRate = (data['defenseRate'] as num?)?.toDouble() ?? defenseRate;
    evasionRate = (data['evasionRate'] as num?)?.toDouble() ?? evasionRate;
    critDefenseRate =
        (data['critDefenseRate'] as num?)?.toDouble() ?? critDefenseRate;
    itemDropRate = (data['itemDropRate'] as num?)?.toDouble() ?? itemDropRate;
    maxHp = (data['maxHp'] as num?)?.toDouble() ?? maxHp;
    currentHp = maxHp;

    final Map<String, dynamic>? savedCollectionBonuses =
        data['collectionBonuses'] as Map<String, dynamic>?;
    if (savedCollectionBonuses != null) {
      for (final CollectionStatType type in CollectionStatType.values) {
        final num? saved = savedCollectionBonuses[type.name] as num?;
        if (saved != null) {
          collectionBonuses[type] = saved.toDouble();
        }
      }
    }

    final List<dynamic>? savedSkills = data['skills'] as List<dynamic>?;
    if (savedSkills != null) {
      for (final dynamic entry in savedSkills) {
        final Map<String, dynamic> json = entry as Map<String, dynamic>;
        final int index = skills.indexWhere((s) => s.id == json['id']);
        if (index == -1) {
          continue;
        }
        final Skill catalogSkill = skills[index];
        skills[index] = Skill.fromJson(
          json,
          name: catalogSkill.name,
          icon: catalogSkill.icon,
          cost: catalogSkill.cost,
          cooldown: catalogSkill.cooldown,
        );
      }
    }

    _resetMonsterHp();
    notifyListeners();
    debugPrint('Game loaded: gold=$gold, chapter=$chapter, stage=$stage');
  }

}
