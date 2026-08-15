import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/consumable_item_model.dart';
import '../models/skill_model.dart';
import 'consumable_manager.dart';
import 'game_manager.dart';
import 'pet_manager.dart';

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

  /// [node.currentCooldown]에 장착 펫의 "스킬 쿨타임 감소" 옵션을 적용한
  /// 실제 쿨타임 — 액티브 스킬 재사용 대기시간을 계산하는 곳(홈 화면 자동
  /// 스킬 슬롯)은 이 값을 써야 한다. 0.1초 밑으로는 내려가지 않는다.
  double effectiveCooldown(SkillNode node) {
    final double reduction = PetManager.instance.skillCooldownReduction.clamp(0.0, 0.9);
    return (node.currentCooldown * (1 - reduction)).clamp(0.1, node.currentCooldown);
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
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      return;
    }

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
