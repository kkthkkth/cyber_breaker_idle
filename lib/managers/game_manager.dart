import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/equipment.dart';
import 'equipment_manager.dart';

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
    final double remaining = cooldown - elapsed;
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

class GameManager extends ChangeNotifier with WidgetsBindingObserver {
  GameManager._internal() {
    _resetMonsterHp();
    WidgetsBinding.instance.addObserver(this);
    EquipmentManager.instance.addListener(notifyListeners);
  }

  static final GameManager instance = GameManager._internal();

  static const int maxStage = 10;
  static const double bossTimeLimit = 30.0;
  static const double itemDropRate = 0.3;
  static const double skillMinMultiplier = 5.0;
  static const double skillMaxMultiplier = 10.0;

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
  int chapter = 1;
  int stage = 1;

  double monsterHp = 0;
  double monsterMaxHp = 0;

  double baseAttackPower = 10;
  double attackSpeed = 1.0;
  double criticalRate = 0.05;
  double criticalMultiplier = 2.0;

  int attackLevel = 1;
  int attackSpeedLevel = 1;
  int criticalRateLevel = 1;

  static const double _maxCriticalRate = 0.75;

  final Random _random = Random();

  double bossTimeRemaining = bossTimeLimit;

  /// Fired when a skill successfully activates, so Flame can play the effect.
  void Function(Skill skill)? onSkillUsed;

  bool get isBossStage => stage == maxStage;

  double get attackPower =>
      baseAttackPower *
      (1 + EquipmentManager.instance.getTotalEquipmentMultiplier());

  double get goldPerHour => attackPower * attackSpeed * 60;

  int get attackUpgradeCost => (50 * pow(1.15, attackLevel - 1)).round();

  int get speedUpgradeCost => (80 * pow(1.2, attackSpeedLevel - 1)).round();

  int get criticalUpgradeCost => (100 * pow(1.18, criticalRateLevel - 1)).round();

  void _resetMonsterHp() {
    const double base = 50.0;
    final int progressIndex = (chapter - 1) * maxStage + (stage - 1);
    double hp = base * pow(1.15, progressIndex);

    if (isBossStage) {
      hp *= 5;
      bossTimeRemaining = bossTimeLimit;
    }

    monsterMaxHp = hp;
    monsterHp = hp;
  }

  ({Equipment? droppedItem, int goldReward}) damageMonster(double damage) {
    if (monsterHp <= 0) {
      return (droppedItem: null, goldReward: 0);
    }

    monsterHp -= damage;
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
    final int goldReward = (10 * chapter * stage).round();

    final Equipment? droppedItem = _random.nextDouble() < itemDropRate
        ? EquipmentManager.instance.generateRandomLoot()
        : null;

    if (isBossStage) {
      chapter++;
      stage = 1;
    } else {
      stage++;
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

  void tickBossTimer(double dt) {
    if (!isBossStage) {
      return;
    }

    bossTimeRemaining -= dt;
    if (bossTimeRemaining <= 0) {
      onBossFailed();
    }
  }

  void onBossFailed() {
    stage = maxStage - 1;
    if (stage < 1) {
      stage = 1;
    }
    _resetMonsterHp();
    notifyListeners();
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

  ({double damage, bool isCritical}) rollAttack() {
    final bool isCritical = _random.nextDouble() < criticalRate;
    final double damage =
        isCritical ? attackPower * criticalMultiplier : attackPower;
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
      'chapter': chapter,
      'stage': stage,
      'attackLevel': attackLevel,
      'attackSpeedLevel': attackSpeedLevel,
      'criticalRateLevel': criticalRateLevel,
      'baseAttackPower': baseAttackPower,
      'attackSpeed': attackSpeed,
      'criticalRate': criticalRate,
      'skills': skills.map((skill) => skill.toJson()).toList(),
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
    chapter = data['chapter'] as int? ?? chapter;
    stage = data['stage'] as int? ?? stage;
    attackLevel = data['attackLevel'] as int? ?? attackLevel;
    attackSpeedLevel = data['attackSpeedLevel'] as int? ?? attackSpeedLevel;
    criticalRateLevel = data['criticalRateLevel'] as int? ?? criticalRateLevel;
    baseAttackPower =
        (data['baseAttackPower'] as num?)?.toDouble() ?? baseAttackPower;
    attackSpeed = (data['attackSpeed'] as num?)?.toDouble() ?? attackSpeed;
    criticalRate = (data['criticalRate'] as num?)?.toDouble() ?? criticalRate;

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

  Future<void> saveLastPlayTime() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastPlayTime', DateTime.now().millisecondsSinceEpoch);
  }

  Future<int> calculateOfflineReward() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int? lastMillis = prefs.getInt('lastPlayTime');

    if (lastMillis == null) {
      return 0;
    }

    final DateTime lastPlayTime = DateTime.fromMillisecondsSinceEpoch(lastMillis);
    final double offlineHours =
        DateTime.now().difference(lastPlayTime).inSeconds / 3600.0;

    if (offlineHours <= 0) {
      return 0;
    }

    final int reward = (goldPerHour * offlineHours).round();
    if (reward > 0) {
      gold += reward;
      notifyListeners();
    }
    return reward;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      saveLastPlayTime();
    }
  }
}
