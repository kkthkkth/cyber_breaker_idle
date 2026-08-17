import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/active_skill_model.dart';
import '../models/consumable_item_model.dart';
import '../models/pet_stat_metadata_model.dart';
import '../models/rune_model.dart';
import '../models/skill_model.dart';
import 'consumable_manager.dart';
import 'equipment_manager.dart';
import 'game_manager.dart';
import 'rune_manager.dart';
import 'supabase_manager.dart';

class SkillManager extends ChangeNotifier {
  SkillManager._internal();

  static final SkillManager instance = SkillManager._internal();

  /// The element the player has committed to — set the moment their first
  /// skill in any tree reaches level 1, locking every other tree.
  SkillElement? chosenElement;

  int skillPoints = 10;

  /// 펫 탭 전용 스킬 포인트 — 캐릭터 [skillPoints]와는 별개의 재화이며,
  /// 펫 패시브 스킬 레벨업에만 소모된다.
  int petSkillPoints = 0;

  // ── 액티브 스킬(DB 기반: skill_metadata + user_skills) ──────────────
  //
  // 위의 [skillTree](원소 트리, 조건 충족 시 자동 발동)와는 완전히 별개
  // 시스템이다 — 이쪽은 유저가 직접 탭해서 쓰는 쿨타임 스킬이며, 카탈로그/
  // 레벨/장착 여부가 전부 DB에서 온다([loadData] 참고). 별도 "습득" 단계가
  // 없어 카탈로그에 있으면 바로 레벨 1로 쓸 수 있고, 골드로 레벨만 올린다.
  List<ActiveSkill> activeSkills = [];

  /// 동시에 장착할 수 있는 액티브 스킬 수 — 홈 화면 HUD 슬롯 개수와 같다.
  static const int maxEquippedActiveSkills = 3;

  /// 광역기(active_aoe) 발동 시 호출 — (스킬, 최종 데미지)를 전달한다.
  /// Flame 쪽(IdleGame)이 이 콜백에서 낙하 이펙트/화면 흔들림 같은 연출을
  /// 재생한 뒤 실제로 데미지를 적용한다 — [SkillManager] 자체는 전투 화면
  /// 존재 여부와 무관하게 쿨타임/장착 검증과 배율 계산만 담당한다.
  void Function(ActiveSkill skill, double damage)? onActiveSkillCast;

  DateTime? _buffEndTime;
  double _buffAttackPowerBonus = 0;
  double _buffAttackSpeedBonus = 0;
  Timer? _buffTimer;

  bool get isActiveSkillBuffActive =>
      _buffEndTime != null && _buffEndTime!.isAfter(DateTime.now());

  /// [GameManager.attackPower]가 곱산 체인 끝에서 읽는 값 — 버프가 없으면
  /// 0이라 곱산에 영향이 없다.
  double get activeBuffAttackPowerBonus =>
      isActiveSkillBuffActive ? _buffAttackPowerBonus : 0;

  /// [GameManager.effectiveAttackSpeed]가 읽는 값 — 위와 같은 이유로 버프가
  /// 없으면 0.
  double get activeBuffAttackSpeedBonus =>
      isActiveSkillBuffActive ? _buffAttackSpeedBonus : 0;

  /// 버프 남은 시간(초) — HUD가 "버프 N초 남음" 같은 표시에 쓴다.
  double get activeSkillBuffRemainingSeconds {
    final DateTime? endTime = _buffEndTime;
    if (endTime == null) {
      return 0;
    }
    final double remaining = endTime.difference(DateTime.now()).inMilliseconds / 1000.0;
    return remaining > 0 ? remaining : 0;
  }

  final Random _random = Random();

  /// Fired whenever [useSkill] lands a hit, so the battle UI can play a
  /// matching effect — see home_screen.dart's SkillEffectOverlay.
  void Function(SkillNode node, double damage, bool isCritical)? onSkillUsed;

  /// Where skill damage actually lands. Defaults to the main-stage
  /// GameManager monster; a screen showing a dungeon IdleGame instance
  /// should point this at its own damage resolution while it's on top (see
  /// dungeon_screen.dart's _DungeonBattleScreenState) and restore it to
  /// null on dispose.
  void Function(double damage)? damageHandler;

  /// Deals damage to the current monster using
  /// `(스킬 고유 데미지 + 공격력) * 공격속도`, then rolls the player's
  /// critical chance for a `* 크리티컬 데미지` multiplier on top. Notifies
  /// [onSkillUsed]. Returns false if the skill hasn't been learned.
  bool useSkill(String skillId) {
    final SkillNode? node = findById(skillId);
    if (node == null || !node.isLearned) {
      return false;
    }

    final GameManager gameManager = GameManager.instance;
    double damage =
        (node.currentDamage + gameManager.attackPower) * gameManager.effectiveAttackSpeed;

    final bool isCritical = _random.nextDouble() < gameManager.effectiveCriticalRate;
    if (isCritical) {
      damage *= gameManager.effectiveCriticalMultiplier;
    }

    if (damageHandler != null) {
      damageHandler!(damage);
    } else {
      gameManager.damageMonster(damage);
    }
    onSkillUsed?.call(node, damage, isCritical);
    return true;
  }

  /// Dummy tree for now; swap for a server-fetched list once skill data
  /// moves to a DB (see the TODO on [_defaultSkillTree]) — everything below
  /// only ever reads/writes through [skillTree].
  final List<SkillNode> skillTree = _defaultSkillTree();

  List<SkillNode> nodesForElement(SkillElement element) =>
      skillTree.where((node) => node.element == element).toList();

  bool isElementLocked(SkillElement element) =>
      chosenElement != null && chosenElement != element;

  /// [node.currentCooldown]에 장착 펫의 "스킬 쿨타임 감소" 옵션 + 룬
  /// (유틸형, 초록 룬)의 쿨타임 감소를 적용한 실제 쿨타임 — 액티브 스킬
  /// 재사용 대기시간을 계산하는 곳(홈 화면 자동 스킬 슬롯)은 이 값을
  /// 써야 한다. 0.1초 밑으로는 내려가지 않는다.
  double effectiveCooldown(SkillNode node) {
    final double reduction = _cooldownReduction();
    return (node.currentCooldown * (1 - reduction)).clamp(0.1, node.currentCooldown);
  }

  /// 펫 특수 스탯 + 룬 유틸 스탯을 합친 쿨타임 감소 비율(0.0~0.9로
  /// clamp) — [effectiveCooldown]/[effectiveActiveSkillCooldown] 둘 다
  /// 공유한다.
  double _cooldownReduction() {
    final double petReduction =
        EquipmentManager.instance.equippedPet?.specialStats[PetSpecialStat.skillCooldownReduction] ??
            0;
    final double runeReduction =
        RuneManager.instance.totalBonus(RuneStat.skillCooldownReductionPercent);
    return (petReduction + runeReduction).clamp(0.0, 0.9);
  }

  SkillNode? findById(String id) {
    for (final SkillNode node in skillTree) {
      if (node.id == id) {
        return node;
      }
    }
    return null;
  }

  void addSkillPoints(int amount) {
    if (amount <= 0) {
      return;
    }
    skillPoints += amount;
    notifyListeners();
    saveData();
  }

  void addPetSkillPoints(int amount) {
    if (amount <= 0) {
      return;
    }
    petSkillPoints += amount;
    notifyListeners();
    saveData();
  }

  /// Dummy pool for now; swap for a server-fetched list once pet skills
  /// move to a DB — everything below only ever reads/writes through
  /// [petSkillTree].
  final List<PetPassiveSkill> petSkillTree = _defaultPetSkillTree();

  static List<PetPassiveSkill> _defaultPetSkillTree() {
    return [
      for (final PetPassiveType type in PetPassiveType.values)
        PetPassiveSkill(type: type, maxLevel: 10),
    ];
  }

  /// 현재 [type]의 %가산 보너스 값. 장착된 펫 유무는 호출부(GameManager)가
  /// 직접 확인한다 — 이 값 자체는 펫 장착 여부와 무관하게 "레벨에 따른
  /// 잠재 보너스"만 반환한다.
  double petPassiveBonus(PetPassiveType type) {
    final PetPassiveSkill skill = petSkillTree.firstWhere((s) => s.type == type);
    return skill.bonusValue;
  }

  bool learnPetSkill(PetPassiveType type) {
    final PetPassiveSkill skill = petSkillTree.firstWhere((s) => s.type == type);
    if (skill.isMaxLevel || petSkillPoints <= 0) {
      return false;
    }

    skill.currentLevel++;
    petSkillPoints--;
    notifyListeners();
    saveData();
    return true;
  }

  bool learnSkill(String skillId) {
    final SkillNode? node = findById(skillId);
    if (node == null || node.isMaxLevel) {
      return false;
    }
    if (skillPoints <= 0) {
      return false;
    }
    if (node.requiredSkillId != null) {
      final SkillNode? prerequisite = findById(node.requiredSkillId!);
      if (prerequisite == null || prerequisite.currentLevel < 1) {
        return false;
      }
    }

    // Off-element learns are normally blocked, unless the player spends a
    // 다른 속성 스킬권 to bypass the lock for this one skill point.
    final bool needsCrossElementBook =
        chosenElement != null && chosenElement != node.element;
    if (needsCrossElementBook) {
      if (!ConsumableManager.instance.consume(ConsumableType.crossElementBook)) {
        return false;
      }
    }

    node.currentLevel++;
    skillPoints--;
    chosenElement ??= node.element;
    notifyListeners();
    saveData();
    return true;
  }

  /// Refunds every spent skill point across the whole tree and unlocks
  /// [chosenElement]. Used by 스킬 초기화권 (see ConsumableManager.useSkillReset).
  void resetAllSkills() {
    int refundedPoints = 0;
    for (final SkillNode node in skillTree) {
      refundedPoints += node.currentLevel;
      node.currentLevel = 0;
    }
    skillPoints += refundedPoints;
    chosenElement = null;
    notifyListeners();
    saveData();
  }

  /// 단위 테스트 전용 — 실제 카탈로그/진행도/버프 상태를 네트워크 없이
  /// 직접 주입/초기화한다([ArtifactManager.debugSeedForTest]와 같은 관례).
  @visibleForTesting
  void debugResetActiveSkillStateForTest([List<ActiveSkill> skills = const []]) {
    activeSkills = skills;
    _buffTimer?.cancel();
    _buffTimer = null;
    _buffEndTime = null;
    _buffAttackPowerBonus = 0;
    _buffAttackSpeedBonus = 0;
  }

  ActiveSkill? findActiveSkillById(String id) {
    for (final ActiveSkill skill in activeSkills) {
      if (skill.id == id) {
        return skill;
      }
    }
    return null;
  }

  List<ActiveSkill> get equippedActiveSkills =>
      activeSkills.where((skill) => skill.isEquipped).toList();

  /// [skill.baseCooldown]에 장착 펫의 "스킬 쿨타임 감소" 옵션 + 룬(유틸형)
  /// 쿨타임 감소를 적용한 실제 쿨타임 — [effectiveCooldown](원소 트리
  /// 전용)과 같은 계산을 액티브 스킬에 적용한 버전.
  double effectiveActiveSkillCooldown(ActiveSkill skill) {
    final double reduction = _cooldownReduction();
    return (skill.baseCooldown * (1 - reduction)).clamp(0.1, skill.baseCooldown);
  }

  /// [skillId] 스킬의 남은 쿨타임(초) — 아직 한 번도 안 썼으면 0.
  double activeSkillCooldownRemaining(String skillId) {
    final ActiveSkill? skill = findActiveSkillById(skillId);
    if (skill?.lastUsedAt == null) {
      return 0;
    }
    final double elapsed =
        DateTime.now().difference(skill!.lastUsedAt!).inMilliseconds / 1000.0;
    final double remaining = effectiveActiveSkillCooldown(skill) - elapsed;
    return remaining > 0 ? remaining : 0;
  }

  bool isActiveSkillReady(String skillId) => activeSkillCooldownRemaining(skillId) <= 0;

  /// 장착된 액티브 스킬을 발동한다 — 쿨타임 중이거나 미장착이면 false.
  /// 광역기는 [onActiveSkillCast]로 (스킬, 데미지)를 넘기기만 하고 실제
  /// 피해 적용은 호출부(IdleGame)가 담당한다. 버프기는 여기서 바로
  /// [GameManager]가 읽는 버프 상태를 활성화한다.
  bool useActiveSkill(String skillId) {
    final int index = activeSkills.indexWhere((skill) => skill.id == skillId);
    if (index == -1) {
      return false;
    }
    final ActiveSkill skill = activeSkills[index];
    if (!skill.isEquipped || activeSkillCooldownRemaining(skillId) > 0) {
      return false;
    }

    activeSkills[index] = skill.copyWith(lastUsedAt: DateTime.now());

    switch (skill.type) {
      case ActiveSkillType.aoe:
        final double damage = skill.aoeMultiplier * GameManager.instance.attackPower;
        onActiveSkillCast?.call(skill, damage);
      case ActiveSkillType.buff:
        _activateBuff(skill);
    }

    notifyListeners();
    return true;
  }

  void _activateBuff(ActiveSkill skill) {
    _buffTimer?.cancel();
    _buffAttackPowerBonus = skill.buffAttackPowerBonus;
    _buffAttackSpeedBonus = skill.buffAttackSpeedBonus;
    final Duration duration =
        Duration(milliseconds: (skill.buffDurationSeconds * 1000).round());
    _buffEndTime = DateTime.now().add(duration);
    _buffTimer = Timer(duration, () {
      _buffEndTime = null;
      _buffAttackPowerBonus = 0;
      _buffAttackSpeedBonus = 0;
      notifyListeners();
    });
  }

  /// 골드를 소모해 [skillId] 스킬을 한 단계 레벨업한다. 골드가 부족하거나
  /// 이미 만렙이면 아무것도 바꾸지 않고 false.
  bool levelUpActiveSkill(String skillId) {
    final int index = activeSkills.indexWhere((skill) => skill.id == skillId);
    if (index == -1) {
      return false;
    }
    final ActiveSkill skill = activeSkills[index];
    if (skill.isMaxLevel) {
      return false;
    }
    if (!GameManager.instance.spendGold(skill.nextLevelGoldCost)) {
      return false;
    }

    final ActiveSkill updated = skill.copyWith(level: skill.level + 1);
    activeSkills[index] = updated;
    notifyListeners();
    unawaited(_saveActiveSkillsLocal());
    unawaited(
      SupabaseManager.instance.syncUserSkill(
        skillId: updated.id,
        level: updated.level,
        isEquipped: updated.isEquipped,
      ),
    );
    return true;
  }

  /// [skillId]를 장착한다 — 이미 [maxEquippedActiveSkills]개가 장착돼
  /// 있으면 false(먼저 [unequipActiveSkill]로 자리를 비워야 한다). 이미
  /// 장착된 스킬을 다시 장착하면 아무 것도 바꾸지 않고 true.
  bool equipActiveSkill(String skillId) {
    final int index = activeSkills.indexWhere((skill) => skill.id == skillId);
    if (index == -1) {
      return false;
    }
    if (activeSkills[index].isEquipped) {
      return true;
    }
    if (equippedActiveSkills.length >= maxEquippedActiveSkills) {
      return false;
    }

    final ActiveSkill updated = activeSkills[index].copyWith(isEquipped: true);
    activeSkills[index] = updated;
    notifyListeners();
    unawaited(_saveActiveSkillsLocal());
    unawaited(
      SupabaseManager.instance.syncUserSkill(
        skillId: updated.id,
        level: updated.level,
        isEquipped: true,
      ),
    );
    return true;
  }

  bool unequipActiveSkill(String skillId) {
    final int index = activeSkills.indexWhere((skill) => skill.id == skillId);
    if (index == -1 || !activeSkills[index].isEquipped) {
      return false;
    }

    final ActiveSkill updated = activeSkills[index].copyWith(isEquipped: false);
    activeSkills[index] = updated;
    notifyListeners();
    unawaited(_saveActiveSkillsLocal());
    unawaited(
      SupabaseManager.instance.syncUserSkill(
        skillId: updated.id,
        level: updated.level,
        isEquipped: false,
      ),
    );
    return true;
  }

  static const String _activeSkillSaveKey = 'skill_manager_active_skills_save';

  Future<void> _saveActiveSkillsLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _activeSkillSaveKey,
      jsonEncode([
        for (final ActiveSkill skill in activeSkills)
          {
            'id': skill.id,
            'name': skill.name,
            'description': skill.description,
            'skill_type': skill.type == ActiveSkillType.buff ? 'active_buff' : 'active_aoe',
            'base_power': skill.basePower,
            'power_per_level': skill.powerPerLevel,
            'base_cooldown': skill.baseCooldown,
            'max_level': skill.maxLevel,
            'level_up_gold_cost': skill.levelUpGoldCost,
            'buff_duration_seconds': skill.buffDurationSeconds,
            'buff_attack_power_bonus': skill.buffAttackPowerBonus,
            'buff_attack_speed_bonus': skill.buffAttackSpeedBonus,
            'level': skill.level,
            'is_equipped': skill.isEquipped,
          },
      ]),
    );
  }

  Future<void> _loadActiveSkillsLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_activeSkillSaveKey);
    if (raw == null) {
      return;
    }
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      activeSkills = decoded.map((entry) {
        final Map<String, dynamic> map = entry as Map<String, dynamic>;
        return ActiveSkill.fromCatalogJson(map).copyWith(
          level: map['level'] as int? ?? 1,
          isEquipped: map['is_equipped'] as bool? ?? false,
        );
      }).toList();
    } catch (error) {
      debugPrint('[SkillManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }
  }

  /// 앱 시작 시 [loadData]가 호출 — 로컬 캐시로 즉시 채운 뒤, 카탈로그와
  /// 유저 진행도를 원격에서 받아와 병합한다([ArtifactManager.loadData]와
  /// 같은 패턴).
  Future<void> _loadActiveSkillData() async {
    await _loadActiveSkillsLocal();

    final List<Map<String, dynamic>> catalogRows =
        await SupabaseManager.instance.fetchSkillMetadata();
    if (catalogRows.isEmpty) {
      debugPrint(
        '[SkillManager] 액티브 스킬 카탈로그가 비어 있습니다(skill_metadata 테이블/RLS 정책을 '
        '확인하세요). 기존 캐시(${activeSkills.length}건)를 유지합니다.',
      );
    } else {
      final List<ActiveSkill> catalog = [];
      for (final Map<String, dynamic> row in catalogRows) {
        try {
          catalog.add(ActiveSkill.fromCatalogJson(row));
        } catch (error) {
          debugPrint('[SkillManager] 액티브 스킬 카탈로그 행 파싱 실패(id=${row['id']}): $error');
        }
      }
      if (catalog.isNotEmpty) {
        final Map<String, ActiveSkill> existingById = {
          for (final ActiveSkill skill in activeSkills) skill.id: skill,
        };
        activeSkills = catalog.map((definition) {
          final ActiveSkill? existing = existingById[definition.id];
          return existing == null
              ? definition
              : definition.copyWith(level: existing.level, isEquipped: existing.isEquipped);
        }).toList();
      }
    }

    final List<Map<String, dynamic>> progressRows =
        await SupabaseManager.instance.fetchUserSkills();
    for (final Map<String, dynamic> row in progressRows) {
      final String? skillId = row['skill_id'] as String?;
      if (skillId == null) {
        continue;
      }
      final int index = activeSkills.indexWhere((skill) => skill.id == skillId);
      if (index == -1) {
        continue;
      }
      final int remoteLevel = (row['level'] as num?)?.toInt() ?? 1;
      final bool remoteEquipped = row['is_equipped'] as bool? ?? false;
      final ActiveSkill local = activeSkills[index];
      if (remoteLevel > local.level) {
        activeSkills[index] = local.copyWith(level: remoteLevel, isEquipped: remoteEquipped);
      } else if (remoteLevel == local.level && remoteEquipped != local.isEquipped) {
        // 레벨은 같은데 장착 여부만 다르면(다른 기기에서 마지막으로 바꾼
        // 값) 서버 쪽을 신뢰한다.
        activeSkills[index] = local.copyWith(isEquipped: remoteEquipped);
      }
    }

    // 병합 과정에서(예: 서로 다른 기기에서 각각 장착) 슬롯 수가 실수로
    // [maxEquippedActiveSkills]를 넘을 수 있다 — 초과분을 안전하게 해제한다.
    int equippedCount = 0;
    for (int i = 0; i < activeSkills.length; i++) {
      if (!activeSkills[i].isEquipped) {
        continue;
      }
      equippedCount++;
      if (equippedCount > maxEquippedActiveSkills) {
        activeSkills[i] = activeSkills[i].copyWith(isEquipped: false);
      }
    }

    await _saveActiveSkillsLocal();
  }

  static const String _saveKey = 'skill_manager_save';

  Future<void> saveData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final Map<String, dynamic> data = {
      'chosenElement': chosenElement?.name,
      'skillPoints': skillPoints,
      'skillLevels': {
        for (final SkillNode node in skillTree) node.id: node.currentLevel,
      },
      'petSkillPoints': petSkillPoints,
      'petSkillLevels': {
        for (final PetPassiveSkill skill in petSkillTree)
          skill.type.name: skill.currentLevel,
      },
    };

    await prefs.setString(_saveKey, jsonEncode(data));
  }

  Future<void> loadData() async {
    // 액티브 스킬(DB 기반)은 아래의 원소 트리/펫 스킬 로컬 저장 여부와
    // 무관하게 항상 로드돼야 한다 — 바로 아래의 이른 반환(첫 실행 등 로컬
    // 저장이 아예 없는 경우)에 걸리지 않도록 제일 먼저 처리한다.
    await _loadActiveSkillData();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      notifyListeners();
      return;
    }

    try {
      final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;

      final String? elementName = data['chosenElement'] as String?;
      chosenElement =
          elementName != null ? SkillElement.values.byName(elementName) : null;
      skillPoints = data['skillPoints'] as int? ?? skillPoints;

      final Map<String, dynamic>? levels =
          data['skillLevels'] as Map<String, dynamic>?;
      if (levels != null) {
        for (final SkillNode node in skillTree) {
          node.currentLevel = levels[node.id] as int? ?? node.currentLevel;
        }
      }

      petSkillPoints = data['petSkillPoints'] as int? ?? petSkillPoints;
      final Map<String, dynamic>? petLevels =
          data['petSkillLevels'] as Map<String, dynamic>?;
      if (petLevels != null) {
        for (final PetPassiveSkill skill in petSkillTree) {
          skill.currentLevel =
              petLevels[skill.type.name] as int? ?? skill.currentLevel;
        }
      }
    } catch (error) {
      debugPrint('[SkillManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }

    notifyListeners();
  }

  // TODO(server): replace with a real fetch, e.g.:
  //   final response = await http.get(Uri.parse('$apiBase/skill-tree'));
  //   skillTree = (jsonDecode(response.body) as List)
  //       .map((e) => SkillNode.fromJson(e as Map<String, dynamic>))
  //       .toList();
  static List<SkillNode> _defaultSkillTree() {
    final List<SkillNode> nodes = [];

    for (final SkillElement element in SkillElement.values) {
      final List<String> names = _skillNamesFor(element);
      String? previousId;

      for (int tier = 0; tier < names.length; tier++) {
        final String id = '${element.name}_$tier';
        nodes.add(
          SkillNode(
            id: id,
            name: names[tier],
            element: element,
            description: '${names[tier]} — ${element.displayName} 속성 스킬.',
            maxLevel: 5,
            baseDamage: 20.0 + tier * 30.0,
            damageGrowth: 8.0 + tier * 4.0,
            baseCooldown: 8.0 - tier * 0.8,
            cooldownReduction: 0.4,
            requiredSkillId: previousId,
          ),
        );
        previousId = id;
      }
    }

    return nodes;
  }

  static List<String> _skillNamesFor(SkillElement element) {
    switch (element) {
      case SkillElement.fire:
        return ['파이어볼트', '파이어월', '메테오', '인페르노'];
      case SkillElement.water:
        return ['워터볼', '아이스니들', '블리자드', '프로즌노바'];
      case SkillElement.wind:
        return ['에어커터', '토네이도', '스톰블레이드', '헤븐즈게일'];
      case SkillElement.lightning:
        return ['스파크', '체인라이트닝', '선더스트라이크', '라이트닝스톰'];
      case SkillElement.dark:
        return ['섀도우볼트', '커스', '다크노바', '오블리비언'];
    }
  }
}
