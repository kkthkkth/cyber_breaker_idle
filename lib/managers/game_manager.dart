import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/artifact_model.dart';
import '../models/character_metadata_model.dart';
import '../models/collection_model.dart';
import '../models/combat_power_weights_model.dart';
import '../models/equipment.dart';
import '../models/equipment_set_model.dart';
import '../models/guide_mission_model.dart';
import '../models/pet_stat_metadata_model.dart';
import '../models/quest_model.dart';
import '../models/rune_model.dart';
import '../models/skill_model.dart';
import '../models/talent_model.dart';
import '../models/title_model.dart';
import 'achievement_manager.dart';
import 'artifact_manager.dart';
import 'battle_pass_manager.dart';
import 'character_metadata_manager.dart';
import 'config_manager.dart';
import 'consumable_manager.dart';
import 'equipment_manager.dart';
import 'equipment_set_manager.dart';
import 'guide_mission_manager.dart';
import 'guild_manager.dart';
import 'guild_war_manager.dart';
import 'monster_drop_manager.dart';
import 'prestige_manager.dart';
import 'quest_manager.dart';
import 'rune_manager.dart';
import 'skill_manager.dart';
import 'supabase_manager.dart';
import 'talent_manager.dart';
import 'title_manager.dart';

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

  // 환생(PrestigeManager) 시 아래 7종 골드 강화 트랙(레벨+값)을 전부 이
  // 초기값으로 되돌린다([resetForPrestige] 참고) — gold 자체는 이미 0으로
  // 돌아가지만, 이미 구매해 둔 레벨/스탯 증분은 gold와 완전히 별개의
  // 필드라 초기화해 주지 않으면 영구히 남는다.
  static const double _baseAttackPowerDefault = 10;
  static const double _attackSpeedDefault = 1.0;
  static const double _criticalRateDefault = 0.05;
  static const double _baseDefenseDefault = 0;
  static const double _defenseRateDefault = 0.0;
  static const double _evasionRateDefault = 0.0;
  static const double _critDefenseRateDefault = 0.0;

  double baseAttackPower = _baseAttackPowerDefault;
  double attackSpeed = _attackSpeedDefault;
  double criticalRate = _criticalRateDefault;
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
      RuneManager.instance.totalBonus(RuneStat.criticalDamagePercent) +
      // 길드 전쟁 승리 휘장("승리자의 기운") — 만료되지 않은 휘장이 없으면
      // GuildWarManager.badgeCritDamageBonus가 0이라 영향이 없다.
      GuildWarManager.instance.badgeCritDamageBonus;

  int attackLevel = 1;
  int attackSpeedLevel = 1;
  int criticalRateLevel = 1;

  static const double _maxCriticalRate = 0.75;

  // ── 방어 스탯 4종 (골드로 업그레이드) ──────────────────────────────
  double baseDefense = _baseDefenseDefault;
  double defenseRate = _defenseRateDefault;
  double evasionRate = _evasionRateDefault;
  double critDefenseRate = _critDefenseRateDefault;

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

  // ── 특수 스탯 10종 뼈대 (2026-08 추가) ────────────────────────────────
  //
  // 방치형 성장 극대화를 위해 요청받은 10개 스탯 중 하나([itemDropRate])는
  // 위에 이미 존재해 그대로 재사용하고, 나머지 9개를 여기 새로 추가한다.
  // 전부 기본값 0(=효과 없음)이고, 전부 "값을 담아두는 뼈대"일 뿐이다 —
  // 아직 실제 업그레이드 UI/장비 옵션/보상 지급 로직 어디에도 연결돼
  // 있지 않다(요구사항: "추후 전투/보상 로직에 반영할 수 있도록 뼈대를
  // 만들어 달라" — 실제 연결은 각 시스템이 준비되면 그때 진행). 전부
  // ComprehensiveStatsDialog(프로필 팝업)가 그대로 표시한다.
  //
  // [주의] 아래 goldGain/bossDamageBonus는 이미 존재하는 펫 전용 소스
  // (PetSpecialStat.goldGain/bossDamage, EquipmentManager.equippedPet의
  // specialStats)와 이름은 겹치지만 완전히 별개의 "계정 단위 일반" 소스다
  // — 나중에 실제로 연결할 때는 그 펫 전용 값에 곱/가산으로 추가되어야
  // 하며, 대체해서는 안 된다(이 파일의 다른 모든 다중 소스 스탯과 같은
  // "여러 출처가 함께 쌓인다" 관례).

  /// 골드 획득량 증가율(%) — 0.1 = 몬스터 처치 골드 +10%.
  double goldGain = 0.0;

  /// 경험치 획득량 증가율(%) 기초값 — 이 프로젝트엔 아직 "경험치"라는
  /// 별도 재화 개념이 없어(챕터/스테이지 진행 자체가 성장이다) 지금은
  /// 실제 소비처가 없다 — 요구사항대로 뼈대만 먼저 마련해 둔다. 실제 값은
  /// [expGain] getter를 통해 읽는다(유물 [ArtifactStat.expGainPercent] 포함).
  double baseExpGain = 0.0;
  double get expGain =>
      baseExpGain + ArtifactManager.instance.totalBonus(ArtifactStat.expGainPercent);

  /// 이동 속도 배율 기초값 — 0.1 = +10%. IdleGame의 캐릭터 이동/애니메이션
  /// 속도 계산과 아직 연결되지 않았다. 실제 값은 [moveSpeed] getter를
  /// 통해 읽는다(유물 [ArtifactStat.moveSpeedPercent] 포함).
  double baseMoveSpeed = 0.0;
  double get moveSpeed =>
      baseMoveSpeed + ArtifactManager.instance.totalBonus(ArtifactStat.moveSpeedPercent);

  /// 흡혈 기초값 — 가한 피해의 이 비율(%)만큼 체력을 회복한다. 0.1 = 가한
  /// 피해의 10%를 체력으로 환원. 실제 값은 [lifeSteal] getter를 통해
  /// 읽는다(유물 [ArtifactStat.lifeStealPercent] 포함) — [IdleGame]이 매
  /// 타격마다 [applyLifeSteal]을 호출해 실제로 체력을 회복시킨다.
  double baseLifeSteal = 0.0;
  double get lifeSteal =>
      baseLifeSteal + ArtifactManager.instance.totalBonus(ArtifactStat.lifeStealPercent);

  /// 초당 체력 자연 회복량 기초값(고정 수치, 비율이 아니다) — IdleGame의
  /// 매 프레임 currentHp 갱신 루프와 아직 연결되지 않았다. 실제 값은
  /// [hpRegen] getter를 통해 읽는다(유물 [ArtifactStat.hpRegenFlat] 포함).
  double baseHpRegen = 0.0;
  double get hpRegen =>
      baseHpRegen + ArtifactManager.instance.totalBonus(ArtifactStat.hpRegenFlat);

  /// 보스 몬스터 대상 추가 피해 증가율(%) 기초값 — 이미 존재하는 펫
  /// 보스뎀 보너스([PetSpecialStat.bossDamage])와는 별개의 계정 단위 일반
  /// 소스로 설계됐다. 실제 값은 [bossDamageBonus] getter를 통해 읽는다
  /// (유물 [ArtifactStat.bossDamageBonusPercent] 포함).
  double baseBossDamageBonus = 0.0;
  double get bossDamageBonus =>
      baseBossDamageBonus +
      ArtifactManager.instance.totalBonus(ArtifactStat.bossDamageBonusPercent);

  /// 방어구 관통율(%) 기초값 — 몬스터의 방어 효율을 이 비율만큼 무시하는
  /// 용도로 설계됐다(현재 몬스터 쪽에 별도 방어율 개념이 없어 연결 지점만
  /// 마련해 둔다). 실제 값은 [armorPenetration] getter를 통해 읽는다(유물
  /// [ArtifactStat.armorPenetrationPercent] 포함).
  double baseArmorPenetration = 0.0;
  double get armorPenetration =>
      baseArmorPenetration +
      ArtifactManager.instance.totalBonus(ArtifactStat.armorPenetrationPercent);

  /// 스킬 피해량 증가율(%) 기초값 — [SkillManager]의 스킬 데미지 계산에
  /// 아직 연결되지 않았다. 실제 값은 [skillDamage] getter를 통해 읽는다
  /// (유물 [ArtifactStat.skillDamagePercent] 포함).
  double baseSkillDamage = 0.0;
  double get skillDamage =>
      baseSkillDamage + ArtifactManager.instance.totalBonus(ArtifactStat.skillDamagePercent);

  /// 명중률(%) 기초값 — 몬스터의 회피 판정에 대응하는 개념으로 설계됐다
  /// (현재 몬스터에게는 회피 개념이 없어 연결 지점만 마련해 둔다). 실제
  /// 값은 [accuracy] getter를 통해 읽는다(유물 [ArtifactStat.accuracyPercent]
  /// 포함).
  double baseAccuracy = 0.0;
  double get accuracy =>
      baseAccuracy + ArtifactManager.instance.totalBonus(ArtifactStat.accuracyPercent);

  // ── 플레이어 HP ─────────────────────────────────────────────────
  double baseMaxHp = 200;

  /// 장착 캐릭터의 character_metadata 기반 체력([_equippedCharacterStats.hp],
  /// [attackPower] 문서와 같은 "추가되는 소스" 취급)과 유물(Artifact)의
  /// [ArtifactStat.maxHpPercent] 패시브가 곱산으로 반영된 실제 최대 체력 —
  /// 기존 필드명 `maxHp`를 그대로 getter로 남겨서 게임 내/외부의 모든 기존
  /// 호출부(전투 로직, HP바 UI 등)가 수정 없이 자동으로 두 보너스를 받는다.
  double get maxHp =>
      (baseMaxHp + _equippedCharacterStats.hp) *
      (1 + ArtifactManager.instance.totalBonus(ArtifactStat.maxHpPercent)) *
      (1 + EquipmentSetManager.instance.totalBonus(EquipmentSetStat.maxHpPercent, _equippedSetCounts)) *
      (1 + RuneManager.instance.totalBonus(RuneStat.maxHpPercent)) *
      (1 + TitleManager.instance.bonusFor(TitleBuffType.maxHpPercent)) *
      // 도감(컬렉션) 완성 보상 — 다른 소스들과 같은 "장착 여부와 무관하게
      // 항상 합산" 곱산 체인의 한 항이다(요구사항 예시: "슬라임 반지 3개
      // 등록 ➔ 최대 체력 2% 증가").
      (1 + (collectionBonuses[CollectionStatType.maxHpPercent] ?? 0));

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

  /// 몬스터의 기본 회피율 — [accuracy](명중률, 유물 [ArtifactStat
  /// .accuracyPercent] 포함)가 이만큼을 깎는다([_monsterBaseCritRate]와
  /// 같은 "몬스터 기초값 - 플레이어 스탯" 관례). 몬스터 쪽에 별도 회피
  /// 스탯 개념이 없어(명중률 요구사항 이전엔 항상 100% 명중이었다) 이
  /// 하나의 상수가 유일한 소스다.
  static const double _monsterBaseEvasionRate = 0.15;

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

  /// 장착된 캐릭터(EquipType.character)의 `character_metadata` 기반 최종
  /// 스탯 — [CharacterMetadataManager]에 아직 그 캐릭터 행이 없거나
  /// (마이그레이션 전 등) 장착된 캐릭터 자체가 없으면 안전하게
  /// [CharacterFinalStats.zero]를 반환한다(기존 계정 단위 스탯 체인 —
  /// [baseAttackPower]/[baseDefense]/[baseMaxHp]/[attackSpeed] 골드 강화
  /// 등 — 에 아무 영향도 주지 않는다). 캐릭터 탭 상세 화면
  /// ([CharacterDetailScreen])이 같은 방식으로 계산한 값을 표시하므로,
  /// 전투에 실제로 반영되는 수치와 화면에 보이는 수치가 항상 일치한다.
  CharacterFinalStats get _equippedCharacterStats {
    final Equipment? character = EquipmentManager.instance.equippedItems[EquipType.character];
    if (character == null) {
      return CharacterFinalStats.zero;
    }
    final CharacterMetadata? metadata =
        CharacterMetadataManager.instance.byId(character.gradeBadgeLabel);
    if (metadata == null) {
      return CharacterFinalStats.zero;
    }
    // Equipment.level은 0-indexed("Lv.0"=미강화)라 요청받은 공식의
    // (level-1)과 정확히 같다 — CharacterMetadata.computeFinalStats 문서
    // 참고. 별도 변환 없이 그대로 넘긴다.
    return metadata.computeFinalStats(level: character.level, star: character.star);
  }

  double get attackPower {
    // 장착 캐릭터의 character_metadata 기반 공격력([_equippedCharacterStats])을
    // 골드 강화([baseAttackPower])와 같은 "기초 수치" 층에 더한 뒤, 기존
    // 장비/펫/도감 등 곱산 체인을 그 합계에 그대로 적용한다 — 이 프로젝트의
    // 다른 모든 스탯 소스(펫 specialStats, 유물, 세트, 룬 등)와 동일하게
    // "추가되는 소스"로 취급하며, 기존 골드 강화 진행도를 무효화하지 않는다.
    double power = (baseAttackPower + _equippedCharacterStats.attack) *
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
    // 환생(프레스티지) 누적 환생석 버프 — 한 번도 환생하지 않았으면
    // PrestigeManager.attackBonus가 0이라 곱산에 영향이 없다.
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
    // 칭호(Title) 버프 — 장착 중인 칭호가 attack_percent 타입이 아니면
    // bonusFor가 0이라 곱산에 영향이 없다.
    power *= 1 + TitleManager.instance.bonusFor(TitleBuffType.attackPercent);
    // 특성(별자리) 트리 — 투자한 레벨이 없으면 totalBonus가 0이라 곱산에
    // 영향이 없다.
    power *= 1 + TalentManager.instance.totalBonus(TalentBuffType.attackPercent);
    return power;
  }

  /// 장착 중인 실제 공격 속도. HP/ATK/DEF와 달리 ASPD는 요청받은 예외
  /// 규칙("레벨/별 등급의 영향을 받지 않고 base_aspd를 그대로 사용")이
  /// 있어서 이 프로젝트의 다른 스탯들처럼 "더해지는 보너스"가 아니라
  /// "그 자체가 기초 수치"로 취급한다 — 장착 캐릭터에
  /// character_metadata 행이 있으면([_equippedCharacterStats.attackSpeed]
  /// > 0) 그 base_aspd가 골드로 올린 기존 기본치([attackSpeed])를 대체한다.
  /// 아직 메타데이터가 없는 캐릭터(마이그레이션 전 등)나 캐릭터 자체가
  /// 없으면 기존처럼 [attackSpeed]로 안전하게 대체된다. 어느 쪽이든 장비
  /// 서브 옵션(EquipmentStatType.attackSpeed)의 % 보너스와 액티브 버프
  /// 스킬의 일시적 공격 속도 증폭은 그대로 곱해 반영한다. 전투 루프
  /// (IdleGame)와 스킬 데미지 계산은 반드시 이 값을 써야 한다.
  double get effectiveAttackSpeed {
    final double baseSpeed = _equippedCharacterStats.attackSpeed > 0
        ? _equippedCharacterStats.attackSpeed
        : attackSpeed;
    return baseSpeed *
        (1 + EquipmentManager.instance.getTotalSubStatBonus(EquipmentStatType.attackSpeed)) *
        (1 + SkillManager.instance.activeBuffAttackSpeedBonus);
  }

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
    rate += TalentManager.instance.totalBonus(TalentBuffType.criticalRatePercent);
    return rate.clamp(0.0, _maxCriticalRate);
  }

  /// 장비 옵션 + 도감 보너스 + 장착 캐릭터의 character_metadata 기반
  /// 방어력([_equippedCharacterStats.defense], [attackPower] 문서와 같은
  /// "추가되는 소스" 취급)까지 합산된 최종 방어력(고정 수치).
  double get defensePower {
    double value = baseDefense +
        _equippedCharacterStats.defense +
        EquipmentManager.instance.getTotalDefenseBonus();
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
    // 칭호(Title) 버프 — 장착 중인 칭호가 defense_percent 타입이 아니면
    // bonusFor가 0이라 곱산에 영향이 없다.
    value *= 1 + TitleManager.instance.bonusFor(TitleBuffType.defensePercent);
    // 특성(별자리) 트리 — 투자한 레벨이 없으면 totalBonus가 0이라 곱산에
    // 영향이 없다.
    value *= 1 + TalentManager.instance.totalBonus(TalentBuffType.defensePercent);
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
        RuneManager.instance.totalBonus(RuneStat.evasionRatePercent) +
        _petSpecialStat(PetSpecialStat.evasionBoost);
    return rate.clamp(0.0, _maxEvasionRate);
  }

  /// 몬스터가 플레이어를 때릴 때 크리티컬(추가 피해)이 뜰 확률을 깎는 값 —
  /// [_monsterBaseCritRate]에서 이만큼 빠진다.
  double get effectiveCritDefenseRate {
    final double rate = critDefenseRate +
        EquipmentManager.instance.getTotalCritDefenseRateBonus() +
        (collectionBonuses[CollectionStatType.critDefenseRate] ?? 0) +
        _petSpecialStat(PetSpecialStat.critDefenseBoost);
    return rate.clamp(0.0, _maxCritDefenseRate);
  }

  double get goldPerHour => attackPower * effectiveAttackSpeed * 60;

  // ── 총 전투력 (Combat Power, 2026-08 추가) ──────────────────────────
  //
  // 요청받은 계산식 그대로:
  //   공격 점수 = ATK * ASPD * (1 + (CR * CD)) * (1 + BossDmg + ArmorPen + SkillDmg)
  //   방어 점수 = HP + (DEF * defWeight) * (1 + Evasion + Block)
  //   최종 전투력 = (공격 점수 * offenseWeight) + 방어 점수   (소수점 버림, 정수 반환)
  //
  // 변수 대응(이 프로젝트의 실제 필드/게터로 매핑):
  //   ATK=attackPower, ASPD=effectiveAttackSpeed
  //   CR=effectiveCriticalRate(0~1 확률), CD=effectiveCriticalMultiplier
  //     (배율 자체, 2.0=200%로 이미 정의돼 있는 기존 필드를 그대로 썼다)
  //   BossDmg=bossDamageBonus, ArmorPen=armorPenetration, SkillDmg=skillDamage
  //     (전부 "특수 스탯 10종 뼈대"로 추가한 필드 — 아직 실제 전투 데미지
  //     계산에는 연결 안 됐지만, 전투력 점수에는 이미 반영된다)
  //   HP=maxHp, DEF=defensePower
  //   Evasion=effectiveEvasionRate
  //   Block: 이 프로젝트엔 아직 별도의 "차단율" 스탯이 없다 — 개념이 가장
  //     가까운 [effectiveDefenseRate](방어율, 받는 피해를 비율로 깎는 기존
  //     스탯)를 대신 대응시켰다. 나중에 진짜 Block 스탯이 따로 생기면 이
  //     자리만 바꾸면 된다.
  //   defWeight/offenseWeight: 예전엔 20/10으로 하드코딩돼 있었지만, 이제
  //     [ConfigManager.combatPowerWeights](Supabase `game_config` 테이블,
  //     id='cp_weights')에서 앱 업데이트 없이 서버가 실시간으로 조정한다 —
  //     조회 실패 시에도 그 매니저 자체가 안전하게 20.0/10.0으로 시작하므로
  //     여기서 다시 null-체크할 필요가 없다.
  int get totalCombatPower {
    final CombatPowerWeights weights = ConfigManager.instance.combatPowerWeights;
    final double attackScore = attackPower *
        effectiveAttackSpeed *
        (1 + (effectiveCriticalRate * effectiveCriticalMultiplier)) *
        (1 + bossDamageBonus + armorPenetration + skillDamage);
    final double defenseScore = maxHp +
        (defensePower * weights.defWeight) * (1 + effectiveEvasionRate + effectiveDefenseRate);
    return (attackScore * weights.offenseWeight + defenseScore).floor();
  }

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
  /// 펫/길드/환생/유물 보너스 곱산 체인을 [_onMonsterDefeated]와
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
    // 환생(프레스티지) 누적 환생석 버프 — 한 번도 환생하지 않았으면
    // PrestigeManager.goldBonus가 0이라 곱산에 영향이 없다.
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
    // 길드 전쟁 승리 휘장("승리자의 기운") — 만료되지 않은 휘장이 없으면
    // GuildWarManager.badgeGoldRateBonus가 0이라 곱산에 영향이 없다.
    goldReward = (goldReward * (1 + GuildWarManager.instance.badgeGoldRateBonus)).round();
    // 계정 단위 골드 획득량([goldGain]) — 위 [ArtifactStat.goldGainPercent]와는
    // 별개 소스라(둘 다 0이 기본값) 곱산이 한 번 더 들어간다(요구사항:
    // "몬스터 처치 시 지급되는 최종 골드... 계산식에 이 비율을 곱해서").
    goldReward = (goldReward * (1 + goldGain)).round();
    // 칭호(Title) 버프 — 장착 중인 칭호가 gold_gain_percent 타입이 아니면
    // bonusFor가 0이라 곱산에 영향이 없다.
    goldReward =
        (goldReward * (1 + TitleManager.instance.bonusFor(TitleBuffType.goldGainPercent))).round();
    // 특성(별자리) 트리 — 투자한 레벨이 없으면 totalBonus가 0이라 곱산에
    // 영향이 없다.
    goldReward =
        (goldReward * (1 + TalentManager.instance.totalBonus(TalentBuffType.goldGainPercent)))
            .round();
    return goldReward;
  }

  /// 오프라인 방치 보상 전용 — [highestReachedChapter]의 "평균적인" 몬스터
  /// (서브스테이지 1~[maxStage]의 중간값)를 잡았을 때 골드 기준으로 분당
  /// 획득량을 추정한다. 실제 온라인 전투와 같은 공식+보너스 체인
  /// ([goldRewardForKill])을 쓰므로, 오프라인 중에도 펫/길드/환생/유물
  /// 보너스가 그대로 반영된다.
  double get offlineGoldPerMinute {
    const double averageStage = (1 + maxStage) / 2;
    final int goldPerKill =
        goldRewardForKill(chapter: highestReachedChapter, stage: averageStage.round());
    return goldPerKill * estimatedKillsPerHour / 60;
  }

  // ── 골드 업그레이드 비용 공식 ────────────────────────────────────
  // 전부 `base * growthRate^(level-1)` 형태의 지수 비용 곡선을 쓴다.
  // 예전엔 이 (base, growthRate) 쌍이 7개 getter에 리터럴로 각각
  // 흩어져 있었다 — 공격력/방어력처럼 원래도 같은 값을 쓰던 두 스탯이
  // "우연히 같다"인지 "같아야 한다"인지 코드만 봐서는 알 수 없었고,
  // 방어율/회피율/크리 방어율 세 스탯도 마찬가지였다. 이제 이름 있는
  // 상수 하나씩으로 묶어서, 밸런스를 바꿀 때 그 스탯 계열 전체가 함께
  // 바뀌어야 하는지 한눈에 보이게 했다(정확한 밸런스 데이터가 없어
  // 임의로 정한 값인 건 그대로다).
  static const double _attackAndDefenseCostBase = 50;
  static const double _attackAndDefenseCostGrowth = 1.15;

  static const double _speedCostBase = 80;
  static const double _speedCostGrowth = 1.2;

  static const double _criticalCostBase = 100;
  static const double _criticalCostGrowth = 1.18;

  /// 방어율/회피율/크리티컬 방어율 — 세 스탯 모두 같은 비용 곡선을 공유.
  static const double _defensiveRateCostBase = 90;
  static const double _defensiveRateCostGrowth = 1.2;

  static int _upgradeCost({required double base, required double growth, required int level}) =>
      (base * pow(growth, level - 1)).round();

  int get attackUpgradeCost => _upgradeCost(
    base: _attackAndDefenseCostBase,
    growth: _attackAndDefenseCostGrowth,
    level: attackLevel,
  );

  int get speedUpgradeCost =>
      _upgradeCost(base: _speedCostBase, growth: _speedCostGrowth, level: attackSpeedLevel);

  int get criticalUpgradeCost =>
      _upgradeCost(base: _criticalCostBase, growth: _criticalCostGrowth, level: criticalRateLevel);

  int get defenseUpgradeCost => _upgradeCost(
    base: _attackAndDefenseCostBase,
    growth: _attackAndDefenseCostGrowth,
    level: defenseLevel,
  );

  int get defenseRateUpgradeCost => _upgradeCost(
    base: _defensiveRateCostBase,
    growth: _defensiveRateCostGrowth,
    level: defenseRateLevel,
  );

  int get evasionRateUpgradeCost => _upgradeCost(
    base: _defensiveRateCostBase,
    growth: _defensiveRateCostGrowth,
    level: evasionRateLevel,
  );

  int get critDefenseRateUpgradeCost => _upgradeCost(
    base: _defensiveRateCostBase,
    growth: _defensiveRateCostGrowth,
    level: critDefenseRateLevel,
  );

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

  /// [IdleGame]이 몬스터에게 피해를 입힐 때마다 호출 — [lifeSteal](흡혈,
  /// 유물 [ArtifactStat.lifeStealPercent] 포함)이 0보다 크면 가한 피해의
  /// 그 비율만큼 체력을 회복시킨다. [healPlayer]와 같은 반환 관례(실제로
  /// 회복된 절대량)를 따른다 — 흡혈이 없거나(대부분의 경우) 이미
  /// 풀피면 아무 것도 바꾸지 않고 0을 돌려준다.
  double applyLifeSteal(double damageDealt) {
    if (lifeSteal <= 0 || currentHp >= maxHp) {
      return 0;
    }
    final double healAmount = damageDealt * lifeSteal;
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

  /// 환생(PrestigeManager) 실행 — [PrestigeManager.prestige]가 환생석을
  /// 정산한 직후 호출한다. **초기화 대상**: 스테이지 진행도([chapter]/
  /// [stage])와 [gold], 그리고 그 골드로 산 "캐릭터 기본 레벨" 7종
  /// (공격력/공속/치명타 확률/방어력/방어율/회피율/치명타 저항 — 각각의
  /// 레벨 카운터와 실제 스탯 증분 둘 다)을 전부 최초 상태로 되돌린다.
  /// **보존 대상**([highestReachedChapter](역대 최고 기록 — 다음 환생
  /// 보상 계산의 기준)과 보석/장비/캐릭터 등급/유물/펫/룬/도감/길드 등
  /// "수집형" 진행도, 그리고 이 매니저 밖에 있는 QuestManager 진행도·
  /// PrestigeManager의 누적 환생석/환생 횟수)는 이 메서드가 전혀 건드리지
  /// 않는다 — 되돌리는 건 오직 이번 판의 스테이지 주행 기록과 그 골드로
  /// 산 임시 전투력뿐이다.
  void resetForPrestige() {
    chapter = 1;
    stage = 1;
    gold = 0;

    attackLevel = 1;
    baseAttackPower = _baseAttackPowerDefault;
    attackSpeedLevel = 1;
    attackSpeed = _attackSpeedDefault;
    criticalRateLevel = 1;
    criticalRate = _criticalRateDefault;
    defenseLevel = 1;
    baseDefense = _baseDefenseDefault;
    defenseRateLevel = 1;
    defenseRate = _defenseRateDefault;
    evasionRateLevel = 1;
    evasionRate = _evasionRateDefault;
    critDefenseRateLevel = 1;
    critDefenseRate = _critDefenseRateDefault;

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
      // 계정 단위 보스 피해 증가([bossDamageBonus], 유물 [ArtifactStat
      // .bossDamageBonusPercent] 포함) — 지금 잡고 있는 몬스터가 보스일
      // 때만 곱산으로 들어간다(요구사항: "타격 시 대상이 보스일 경우...
      // 최종 데미지에 곱연산으로 적용").
      effectiveDamage *= 1 + bossDamageBonus;
    }
    // 방어구 관통([armorPenetration], 유물 [ArtifactStat
    // .armorPenetrationPercent] 포함) — 몬스터 쪽에 별도 방어력 스탯이
    // 없어(순수 HP만 갖는다) "그 방어력의 N%를 무시"할 대상 자체가 없다.
    // 대신 방어구를 뚫고 들어간 만큼 더 많은 피해를 입힌다는 것과 최종
    // 효과가 동일한 직접 데미지 증폭으로 반영한다 — 보스가 아닌 일반
    // 몬스터에게도 항상 적용된다(보스 한정인 [bossDamageBonus]와 다른 점).
    effectiveDamage *= 1 + armorPenetration;

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
    // 초보자 가이드 미션("몬스터 N마리 처치") 진행도 — 위 일일 퀘스트와
    // 똑같은 이벤트를 공유하지만 완전히 독립된 시스템(GuideMissionManager)
    // 이라 서로 영향을 주지 않는다.
    GuideMissionManager.instance.updateProgress(GuideMissionActionType.monsterKill, 1);
    // 업적("누적 몬스터 처치") 진행도 — 위 일일 퀘스트와 달리 자정에도
    // 리셋되지 않는 영구 누적값이다. AchievementManager도 로컬 저장만
    // 매번 하고 서버 동기화는 실제로 보상을 받을 때만 하므로 잦은 호출이
    // 문제되지 않는다.
    AchievementManager.instance.recordMonsterKill();

    // 배틀패스 BP — 몬스터 처치마다 저확률(BattlePassManager.monsterKillDropChance)로
    // 소량 지급된다. 활성 시즌이 없으면 addBpExp가 스스로 아무 일도 하지
    // 않으므로 여기서 별도로 시즌 유무를 확인할 필요가 없다. 이 프로젝트엔
    // 별도의 "경험치" 재화가 없어(챕터/스테이지 진행 자체가 성장이다),
    // 몬스터 처치로 얻는 실질적 "경험치"에 가장 가까운 이 BP 지급량에
    // [expGain](경험치 획득량, 유물 [ArtifactStat.expGainPercent] 포함)을
    // 곱해 반영한다(요구사항: "몬스터 처치 시 지급되는... 경험치 계산식에
    // 이 비율을 곱해서").
    if (_random.nextDouble() < BattlePassManager.monsterKillDropChance) {
      final int bpAmount = (BattlePassManager.monsterKillDropAmount * (1 + expGain)).round();
      unawaited(BattlePassManager.instance.addBpExp(bpAmount));
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

    // 초보자 가이드 미션("N-M 스테이지 도달") 진행도 — 누적 카운트가
    // 아니라 "지금까지 도달한 절대 스테이지"를 그대로 보고하는 이벤트라
    // reportAbsoluteValue로만 반영된다([GuideMissionActionType.stageReached]
    // 문서 참고).
    GuideMissionManager.instance.reportAbsoluteValue(
      GuideMissionActionType.stageReached,
      nextAbsoluteStage,
    );

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

    // 칭호(Title) 자동 획득 판정 — 이 시점이면 누적 몬스터 처치
    // (AchievementManager.recordMonsterKill)와 최고 도달 챕터
    // (highestReachedChapter, 방금 갱신됐을 수도 있다) 둘 다 이미
    // 최신값이라, 두 조건 타입(monster_kill_count/highest_chapter)을
    // 이 한 번의 호출로 함께 확인할 수 있다.
    TitleManager.instance.checkAndGrantTitles();

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
    // 초보자 가이드 미션("공격력 N회 강화") 진행도 — 골드가 부족해 실패한
    // 시도는(위 조기 return) 세지 않는다.
    GuideMissionManager.instance.updateProgress(GuideMissionActionType.attackUpgrade, 1);
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
    // 초보자 가이드 미션("방어력 N회 강화") 진행도.
    GuideMissionManager.instance.updateProgress(GuideMissionActionType.defenseUpgrade, 1);
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

  /// 플레이어의 공격 1회를 판정한다 — 명중률([accuracy], 유물 [ArtifactStat
  /// .accuracyPercent] 포함)이 [_monsterBaseEvasionRate]를 깎아 몬스터의
  /// 회피 여부를 먼저 정하고([evaded]), 회피가 아니면 기존처럼 크리티컬
  /// 여부/데미지를 계산한다. 회피면 데미지는 0이고 [IdleGame]이 "회피"
  /// 텍스트만 띄운 채 골드/드랍/흡혈 등 명중 후속 처리를 전부 건너뛴다.
  ({double damage, bool isCritical, bool evaded}) rollAttack() {
    final double monsterEvasionRate = (_monsterBaseEvasionRate - accuracy).clamp(0.0, 1.0);
    if (_random.nextDouble() < monsterEvasionRate) {
      return (damage: 0, isCritical: false, evaded: true);
    }
    final bool isCritical = _random.nextDouble() < effectiveCriticalRate;
    final double damage =
        isCritical ? attackPower * effectiveCriticalMultiplier : attackPower;
    return (damage: damage, isCritical: isCritical, evaded: false);
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
      'goldGain': goldGain,
      'expGain': baseExpGain,
      'moveSpeed': baseMoveSpeed,
      'lifeSteal': baseLifeSteal,
      'hpRegen': baseHpRegen,
      'bossDamageBonus': baseBossDamageBonus,
      'armorPenetration': baseArmorPenetration,
      'skillDamage': baseSkillDamage,
      'accuracy': baseAccuracy,
      'maxHp': baseMaxHp,
      'collectionBonuses': {
        for (final MapEntry<CollectionStatType, double> entry in collectionBonuses.entries)
          entry.key.name: entry.value,
      },
    };

    await prefs.setString(_saveKey, jsonEncode(data));
    debugPrint('Game saved: gold=$gold, chapter=$chapter, stage=$stage');

    _syncCombatPowerIfChanged();
  }

  /// [saveGame]이 마지막으로 서버에 반영한 [totalCombatPower] 값 — null이면
  /// 아직 한 번도 동기화하지 않은 상태(앱 갓 시작).
  int? _lastSyncedCombatPower;

  /// 명예의 전당 [전투력] 랭킹([RankingCategory.combatPower])이 읽는
  /// `profiles.combat_power`를 최신 [totalCombatPower]로 맞춘다
  /// (요구사항: "Auto-save할 때 함께 저장"). [saveGame]은 골드 변화 등으로
  /// 매우 자주 불리지만, 총 전투력은 그중 실제 스탯이 바뀌는 드문 호출
  /// (레벨업/장착 변경 등)에서만 실제로 달라진다 — 그래서 "마지막으로
  /// 올린 값과 실제로 달라졌을 때만 Supabase에 쓴다"는 이 값-비교 자체가
  /// 자연스러운 스로틀 역할을 한다(매 saveGame 호출마다 무조건 네트워크
  /// 요청을 보내지 않는다). 로그인 전이면
  /// [SupabaseManager.updateCombatPower]가 스스로 조용히 아무 일도 하지
  /// 않는다.
  void _syncCombatPowerIfChanged() {
    final int current = totalCombatPower;
    if (current == _lastSyncedCombatPower) {
      return;
    }
    _lastSyncedCombatPower = current;
    unawaited(SupabaseManager.instance.updateCombatPower(current));
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
    goldGain = (data['goldGain'] as num?)?.toDouble() ?? goldGain;
    baseExpGain = (data['expGain'] as num?)?.toDouble() ?? baseExpGain;
    baseMoveSpeed = (data['moveSpeed'] as num?)?.toDouble() ?? baseMoveSpeed;
    baseLifeSteal = (data['lifeSteal'] as num?)?.toDouble() ?? baseLifeSteal;
    baseHpRegen = (data['hpRegen'] as num?)?.toDouble() ?? baseHpRegen;
    baseBossDamageBonus =
        (data['bossDamageBonus'] as num?)?.toDouble() ?? baseBossDamageBonus;
    baseArmorPenetration =
        (data['armorPenetration'] as num?)?.toDouble() ?? baseArmorPenetration;
    baseSkillDamage = (data['skillDamage'] as num?)?.toDouble() ?? baseSkillDamage;
    baseAccuracy = (data['accuracy'] as num?)?.toDouble() ?? baseAccuracy;
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
