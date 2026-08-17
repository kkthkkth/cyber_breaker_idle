import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/artifact_model.dart';
import '../models/collection_model.dart';
import '../models/equipment.dart';
import '../models/equipment_set_model.dart';
import '../models/pet_stat_metadata_model.dart';
import '../models/quest_model.dart';
import '../models/rune_model.dart';
import '../models/skill_model.dart';
import 'achievement_manager.dart';
import 'artifact_manager.dart';
import 'battle_pass_manager.dart';
import 'consumable_manager.dart';
import 'equipment_manager.dart';
import 'equipment_set_manager.dart';
import 'guild_manager.dart';
import 'monster_drop_manager.dart';
import 'prestige_manager.dart';
import 'quest_manager.dart';
import 'rune_manager.dart';
import 'skill_manager.dart';
import 'supabase_manager.dart';

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
      _petSpecialStat(PetSpecialStat.criticalDamageBoost) +
      EquipmentManager.instance.getTotalSubStatBonus(EquipmentStatType.criticalDamage) +
      EquipmentSetManager.instance
          .totalBonus(EquipmentSetStat.criticalDamagePercent, _equippedSetCounts) +
      RuneManager.instance.totalBonus(RuneStat.criticalDamagePercent);

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
  double baseMaxHp = 200;

  /// 유물(Artifact)의 [ArtifactStat.maxHpPercent] 패시브가 곱산으로 반영된
  /// 실제 최대 체력 — 기존 필드명 `maxHp`를 그대로 getter로 남겨서 게임
  /// 내/외부의 모든 기존 호출부(전투 로직, HP바 UI 등)가 수정 없이 자동으로
  /// 유물 보너스를 받는다.
  double get maxHp =>
      baseMaxHp *
      (1 + ArtifactManager.instance.totalBonus(ArtifactStat.maxHpPercent)) *
      (1 + EquipmentSetManager.instance.totalBonus(EquipmentSetStat.maxHpPercent, _equippedSetCounts)) *
      (1 + RuneManager.instance.totalBonus(RuneStat.maxHpPercent));

  /// 장착 세트별 부위 수 — [EquipmentSetManager.totalBonus] 호출마다 매번
  /// 새로 계산하지 않도록 한 곳에 모았다(EquipmentManager.equippedItems를
  /// 그대로 위임).
  Map<String, int> get _equippedSetCounts => EquipmentManager.instance.equippedSetCounts;

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
  bool get _hasPetEquipped => EquipmentManager.instance.equippedPet != null;

  /// 장착 펫의 특수 스탯([key], [PetSpecialStat]의 6개 키 중 하나) 값 —
  /// 펫이 없거나 그 펫이 이 스탯을 안 굴렸으면 0. 예전엔 이 값들이 아무도
  /// 채우지 않는 별개의 죽은 PetManager에서 왔다 — 이제 실제로 가챠/
  /// 장착이 이뤄지는 [EquipmentManager.equippedPet]에서 직접 읽는다.
  double _petSpecialStat(String key) =>
      EquipmentManager.instance.equippedPet?.specialStats[key] ?? 0;

  double get attackPower {
    double power = baseAttackPower *
        (1 + EquipmentManager.instance.getTotalEquipmentMultiplier());
    if (_hasPetEquipped) {
      power *= 1 + SkillManager.instance.petPassiveBonus(PetPassiveType.attackPower);
    }
    power *= 1 + (collectionBonuses[CollectionStatType.attackPower] ?? 0);
    // 장착 펫(신규 Pet 모델)의 "최종 공격력 증폭" 옵션 — 위의 스킬트리 기반
    // petPassiveBonus와는 별개 소스라 곱산이 한 번 더 들어간다.
    power *= 1 + _petSpecialStat(PetSpecialStat.finalAttackBoost);
    // 장비 서브 옵션(EquipmentStatType.attack)의 "공격력" 값 — statMultiplier
    // 기반 getTotalEquipmentMultiplier()와는 별개 소스라 곱산이 한 번 더 들어간다.
    power *= 1 + EquipmentManager.instance.getTotalSubStatBonus(EquipmentStatType.attack);
    // 길드 레벨에 비례한 수동 버프 — 미가입 상태면 GuildManager.attackBonus가
    // 0이라 곱산에 영향이 없다.
    power *= 1 + GuildManager.instance.attackBonus;
    // 오버클럭(프레스티지) 누적 코어 포인트 버프 — 한 번도 오버클럭하지
    // 않았으면 PrestigeManager.attackBonus가 0이라 곱산에 영향이 없다.
    power *= 1 + PrestigeManager.instance.attackBonus;
    // 유물(Artifact) 누적 패시브 — 레벨업한 유물이 없으면 totalBonus가
    // 0이라 곱산에 영향이 없다.
    power *= 1 + ArtifactManager.instance.totalBonus(ArtifactStat.attackPercent);
    // 액티브 버프 스킬(active_buff)의 일시적 공격력 증폭 — 버프가 꺼져
    // 있으면 activeBuffAttackPowerBonus가 0이라 곱산에 영향이 없다.
    power *= 1 + SkillManager.instance.activeBuffAttackPowerBonus;
    // 장비 세트 효과(2/4부위) — 발동 중인 세트가 없으면 totalBonus가
    // 0이라 곱산에 영향이 없다.
    power *= 1 + EquipmentSetManager.instance.totalBonus(EquipmentSetStat.attackPercent, _equippedSetCounts);
    // 룬(공격형, 붉은 룬) 누적 패시브 — 장착 룬이 없으면 totalBonus가
    // 0이라 곱산에 영향이 없다.
    power *= 1 + RuneManager.instance.totalBonus(RuneStat.attackPercent);
    return power;
  }

  /// 장착 중인 실제 공격 속도 — 골드로 올린 기본치([attackSpeed])에 장비
  /// 서브 옵션(EquipmentStatType.attackSpeed)의 % 보너스와 액티브 버프
  /// 스킬의 일시적 공격 속도 증폭을 곱해 반영한다. 전투 루프(IdleGame)와
  /// 스킬 데미지 계산은 반드시 이 값을 써야 한다.
  double get effectiveAttackSpeed =>
      attackSpeed *
      (1 + EquipmentManager.instance.getTotalSubStatBonus(EquipmentStatType.attackSpeed)) *
      (1 + SkillManager.instance.activeBuffAttackSpeedBonus);

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
    rate += EquipmentSetManager.instance
        .totalBonus(EquipmentSetStat.criticalRatePercent, _equippedSetCounts);
    rate += RuneManager.instance.totalBonus(RuneStat.criticalRatePercent);
    return rate.clamp(0.0, _maxCriticalRate);
  }

  /// 장비 옵션 + 도감 보너스까지 합산된 최종 방어력(고정 수치).
  double get defensePower {
    double value = baseDefense + EquipmentManager.instance.getTotalDefenseBonus();
    value += collectionBonuses[CollectionStatType.defense] ?? 0;
    // 유물(Artifact) 누적 패시브 — 여기까지의 가산 방어력 합계에 곱산으로
    // 적용한다(공격력 곱산 체인과 같은 방식).
    value *= 1 + ArtifactManager.instance.totalBonus(ArtifactStat.defensePercent);
    // 장비 세트 효과(2/4부위) — 발동 중인 세트가 없으면 totalBonus가
    // 0이라 곱산에 영향이 없다.
    value *= 1 + EquipmentSetManager.instance.totalBonus(EquipmentSetStat.defensePercent, _equippedSetCounts);
    // 룬(방어형, 푸른 룬) 누적 패시브 — 장착 룬이 없으면 totalBonus가
    // 0이라 곱산에 영향이 없다.
    value *= 1 + RuneManager.instance.totalBonus(RuneStat.defensePercent);
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
        (collectionBonuses[CollectionStatType.evasionRate] ?? 0) +
        RuneManager.instance.totalBonus(RuneStat.evasionRatePercent);
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

  /// [chapter]/[stage] 몬스터를 처치했을 때 실제로 받는 골드 — 기본 공식과
  /// 펫/길드/오버클럭/유물 보너스 곱산 체인을 [_onMonsterDefeated]와
  /// [offlineGoldPerMinute]가 공유한다(두 곳이 서로 다른 공식을 쓰다 밸런스가
  /// 어긋나는 일을 막기 위해 여기 하나로 모았다).
  int goldRewardForKill({required int chapter, required int stage}) {
    int goldReward = (10 * chapter * stage).round();
    if (_hasPetEquipped) {
      goldReward =
          (goldReward * (1 + SkillManager.instance.petPassiveBonus(PetPassiveType.coinRate))).round();
    }
    // 장착 펫(신규 Pet 모델)의 "골드 획득 증가" 옵션 — 스킬트리 기반
    // petPassiveBonus와는 별개 소스라 곱산이 한 번 더 들어간다.
    goldReward = (goldReward * (1 + _petSpecialStat(PetSpecialStat.goldGain))).round();
    // 길드 레벨에 비례한 수동 버프 — 미가입 상태면 GuildManager.goldBonus가
    // 0이라 곱산에 영향이 없다.
    goldReward = (goldReward * (1 + GuildManager.instance.goldBonus)).round();
    // 오버클럭(프레스티지) 누적 코어 포인트 버프 — 한 번도 오버클럭하지
    // 않았으면 PrestigeManager.goldBonus가 0이라 곱산에 영향이 없다.
    goldReward = (goldReward * (1 + PrestigeManager.instance.goldBonus)).round();
    // 유물(Artifact) 누적 패시브 — 레벨업한 유물이 없으면 totalBonus가
    // 0이라 곱산에 영향이 없다.
    goldReward = (goldReward *
            (1 + ArtifactManager.instance.totalBonus(ArtifactStat.goldGainPercent)))
        .round();
    // 룬(유틸형, 초록 룬) 골드 획득량 증가 — 장착 룬이 없으면 totalBonus가
    // 0이라 곱산에 영향이 없다.
    goldReward =
        (goldReward * (1 + RuneManager.instance.totalBonus(RuneStat.goldGainPercent))).round();
    return goldReward;
  }

  /// 오프라인 방치 보상 전용 — [highestReachedChapter]의 "평균적인" 몬스터
  /// (서브스테이지 1~[maxStage]의 중간값)를 잡았을 때 골드 기준으로 분당
  /// 획득량을 추정한다. 실제 온라인 전투와 같은 공식+보너스 체인
  /// ([goldRewardForKill])을 쓰므로, 오프라인 중에도 펫/길드/오버클럭/유물
  /// 보너스가 그대로 반영된다.
  double get offlineGoldPerMinute {
    const double averageStage = (1 + maxStage) / 2;
    final int goldPerKill =
        goldRewardForKill(chapter: highestReachedChapter, stage: averageStage.round());
    return goldPerKill * estimatedKillsPerHour / 60;
  }

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

  /// "오버클럭"(프레스티지) 실행 — [PrestigeManager.prestige]가 코어
  /// 포인트를 정산한 직후 호출한다. 스테이지 진행도([chapter]/[stage])와
  /// [gold]를 처음(1-1)으로 되돌리지만, [highestReachedChapter](역대 최고
  /// 기록 — 다음 오버클럭 보상 계산의 기준)와 장비/캐릭터/보석/길드 등
  /// "수집형" 진행도는 전혀 건드리지 않는다 — 되돌리는 건 오직 이번 판의
  /// 스테이지 주행 기록뿐이다.
  void resetForPrestige() {
    chapter = 1;
    stage = 1;
    gold = 0;
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
      effectiveDamage *= 1 + _petSpecialStat(PetSpecialStat.bossDamage);
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
    // 업적("누적 몬스터 처치") 진행도 — 위 일일 퀘스트와 달리 자정에도
    // 리셋되지 않는 영구 누적값이다. AchievementManager도 로컬 저장만
    // 매번 하고 서버 동기화는 실제로 보상을 받을 때만 하므로 잦은 호출이
    // 문제되지 않는다.
    AchievementManager.instance.recordMonsterKill();

    // 배틀패스 BP — 몬스터 처치마다 저확률(BattlePassManager.monsterKillDropChance)로
    // 소량 지급된다. 활성 시즌이 없으면 addBpExp가 스스로 아무 일도 하지
    // 않으므로 여기서 별도로 시즌 유무를 확인할 필요가 없다.
    if (_random.nextDouble() < BattlePassManager.monsterKillDropChance) {
      unawaited(BattlePassManager.instance.addBpExp(BattlePassManager.monsterKillDropAmount));
    }

    final int goldReward = goldRewardForKill(chapter: chapter, stage: stage);

    final double effectiveDropRate =
        (_legacyEquipmentDropRate * (1 + _petSpecialStat(PetSpecialStat.dropRateBoost)))
            .clamp(0.0, 1.0);
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
      // 유물(Artifact)/룬(유틸형)의 드랍률 패시브는 itemDropRate와 같은
      // 가산(%) 성격이라 곱산이 아니라 그대로 더한다.
      itemDropRate: itemDropRate +
          ArtifactManager.instance.totalBonus(ArtifactStat.dropRatePercent) +
          RuneManager.instance.totalBonus(RuneStat.dropRatePercent),
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

      // 이 챕터가 역대 최초 도달이면(10 단위가 아니어도) highestReachedChapter를
      // 갱신하고 명예의 전당 랭킹([RankingManager])의 정렬 기준인
      // profiles.highest_reached_chapter도 동기화한다. 예전엔 이 갱신을
      // "10 단위 챕터일 때만" 했는데, 그러면 23챕터에 있는 유저와 21챕터에
      // 있는 유저가 둘 다 highestReachedChapter=20으로 똑같이 찍혀서
      // 랭킹/오프라인 보상 계산의 정밀도가 실제 진행도보다 훨씬 떨어졌다.
      final bool isNewHighest = chapter > highestReachedChapter;
      if (isNewHighest) {
        highestReachedChapter = chapter;
        saveGame();
        unawaited(SupabaseManager.instance.updateHighestReachedChapter(highestReachedChapter));
      }
      // 10, 20, 30... 챕터에 "처음" 도달했을 때만 캐릭터 SP 1을 지급한다 —
      // highestReachedChapter 갱신과는 독립적인, 10 단위 전용 보상이다.
      if (isNewHighest && chapter % 10 == 0) {
        SkillManager.instance.addSkillPoints(1);
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
      'maxHp': baseMaxHp,
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
    } else {
      try {
        _applySavedData(jsonDecode(raw) as Map<String, dynamic>);
      } catch (error) {
        debugPrint('[GameManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
      }
    }

    // 서버가 이 유저의 최고 도달 챕터를 더 정확히 알고 있을 수 있다(예: 다른
    // 기기에서 진행) — 로컬보다 서버 값이 더 높을 때만 반영해서, 오프라인
    // 중에 로컬에서 이미 앞서간 진행도를 실수로 되돌리지 않는다
    // ([DungeonManager.loadDungeonData]의 highestClearedFloor 병합과 같은
    // 관례).
    final int? serverHighestChapter =
        await SupabaseManager.instance.fetchHighestReachedChapter();
    if (serverHighestChapter != null && serverHighestChapter > highestReachedChapter) {
      highestReachedChapter = serverHighestChapter;
    }

    _resetMonsterHp();
    notifyListeners();
    debugPrint('Game loaded: gold=$gold, chapter=$chapter, stage=$stage');
  }

  void _applySavedData(Map<String, dynamic> data) {
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
    baseMaxHp = (data['maxHp'] as num?)?.toDouble() ?? baseMaxHp;
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
  }
}
