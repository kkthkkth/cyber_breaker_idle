import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../managers/dungeon_manager.dart';
import '../managers/equipment_manager.dart';
import '../managers/game_manager.dart';
import '../models/equipment.dart';

enum GameMode { mainStage, goldDungeon, equipDungeon, towerOfInfinity }

class IdleGame extends FlameGame {
  final GameManager manager = GameManager.instance;
  final Random _random = Random();

  late PlayerComponent _player;
  late RectangleComponent _monster;
  double _attackTimer = 0;

  static const Color _normalBackgroundColor = Color(0xFF0F0F17);
  static const Color _skillFlashColor = Color(0xFF4A1010);
  Color _backgroundColor = _normalBackgroundColor;

  static const Color _mainStageMonsterColor = Color(0xFFE74C3C);
  static const Color _goldDungeonMonsterColor = Color(0xFFFFC107);
  static const Color _equipDungeonMonsterColor = Color(0xFF9B59B6);
  static const Color _towerMonsterColor = Color(0xFF34C6E5);

  static const double _goldDungeonDuration = 60.0;
  static const double _equipDungeonDuration = 60.0;

  GameMode mode = GameMode.mainStage;
  double dungeonMonsterHp = 0;
  double dungeonMonsterMaxHp = 0;
  double dungeonTimeRemaining = 0;

  GameMode? _pendingMode;
  bool _dungeonEnding = false;
  int _dungeonGoldEarned = 0;

  /// Fired once when a dungeon run ends (win, loss, or timeout).
  void Function({
    required bool success,
    required int goldReward,
    Equipment? itemReward,
  })? onDungeonComplete;

  @override
  Color backgroundColor() => _backgroundColor;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    _player = PlayerComponent(position: _playerPosition(size));
    add(_player);

    _monster = RectangleComponent(
      size: Vector2(120, 120),
      paint: Paint()..color = _mainStageMonsterColor,
      anchor: Anchor.center,
      position: size / 2,
    );
    add(_monster);

    manager.onSkillUsed = _castSkill;

    if (_pendingMode != null) {
      _activateDungeon(_pendingMode!);
      _pendingMode = null;
    }
  }

  /// Switches this game instance into a dungeon encounter. Safe to call
  /// before [onLoad] has finished — the request is queued and applied once
  /// the player/monster components exist.
  void startDungeon(GameMode dungeonMode) {
    if (!isLoaded) {
      _pendingMode = dungeonMode;
      return;
    }
    _activateDungeon(dungeonMode);
  }

  void _activateDungeon(GameMode dungeonMode) {
    mode = dungeonMode;
    _dungeonEnding = false;
    _dungeonGoldEarned = 0;

    switch (dungeonMode) {
      case GameMode.goldDungeon:
        dungeonTimeRemaining = _goldDungeonDuration;
        _spawnDungeonMonster(hp: 80, color: _goldDungeonMonsterColor);
      case GameMode.equipDungeon:
        dungeonTimeRemaining = _equipDungeonDuration;
        _spawnDungeonMonster(hp: 1200, color: _equipDungeonMonsterColor);
      case GameMode.towerOfInfinity:
        dungeonTimeRemaining = -1;
        final int floor = DungeonManager.instance.currentFloor;
        final double hp = 60 * pow(1.25, floor - 1).toDouble();
        _spawnDungeonMonster(hp: hp, color: _towerMonsterColor);
      case GameMode.mainStage:
        break;
    }
  }

  void _spawnDungeonMonster({required double hp, required Color color}) {
    dungeonMonsterHp = hp;
    dungeonMonsterMaxHp = hp;
    _monster.paint = Paint()..color = color;
  }

  Vector2 _playerPosition(Vector2 gameSize) =>
      Vector2(gameSize.x * 0.2, gameSize.y / 2);

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) {
      _monster.position = size / 2;
      _player.position = _playerPosition(size);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (mode == GameMode.mainStage) {
      if (manager.isBossStage) {
        manager.tickBossTimer(dt);
      }
    } else if (dungeonTimeRemaining > 0) {
      dungeonTimeRemaining -= dt;
      if (dungeonTimeRemaining <= 0) {
        dungeonTimeRemaining = 0;
        final bool cleared = mode == GameMode.goldDungeon;
        _endDungeon(
          success: cleared,
          goldReward: cleared ? _dungeonGoldEarned : 0,
        );
      }
    }

    if (_dungeonEnding) {
      return;
    }

    _attackTimer += dt;
    final double interval = 1 / manager.attackSpeed;
    if (_attackTimer >= interval) {
      _attackTimer -= interval;
      _fireProjectile();
    }
  }

  void _fireProjectile() {
    final ({double damage, bool isCritical}) result = manager.rollAttack();

    add(
      Projectile(
        startPosition: _player.position.clone(),
        targetPosition: _monster.position.clone(),
        onHit: () => _resolveHit(result.damage, result.isCritical),
      ),
    );
  }

  void _resolveHit(double damage, bool isCritical) {
    _playHitEffect();
    _spawnDamageText(damage, isCritical);

    if (mode == GameMode.mainStage) {
      final ({Equipment? droppedItem, int goldReward}) hitResult =
          manager.damageMonster(damage);
      if (hitResult.droppedItem != null) {
        _spawnLootText(hitResult.droppedItem!);
      }
      if (hitResult.goldReward > 0) {
        _spawnGoldDrops(hitResult.goldReward);
      }
      return;
    }

    _damageDungeonMonster(damage);
  }

  void _damageDungeonMonster(double damage) {
    if (_dungeonEnding || dungeonMonsterHp <= 0) {
      return;
    }

    dungeonMonsterHp -= damage;
    if (dungeonMonsterHp > 0) {
      return;
    }
    dungeonMonsterHp = 0;

    switch (mode) {
      case GameMode.goldDungeon:
        final int reward = (manager.attackPower * 10).round();
        _dungeonGoldEarned += reward;
        _spawnGoldDrops(reward);
        _spawnDungeonMonster(hp: dungeonMonsterMaxHp, color: _goldDungeonMonsterColor);
      case GameMode.equipDungeon:
        final Equipment item = EquipmentManager.instance.generateGuaranteedLoot(
          const [ItemGrade.epic, ItemGrade.legendary],
        );
        _spawnLootText(item);
        _endDungeon(success: true, goldReward: 0, itemReward: item);
      case GameMode.towerOfInfinity:
        final int reward = (manager.attackPower * 5).round();
        _spawnGoldDrops(reward);
        DungeonManager.instance.advanceFloor();
        _endDungeon(success: true, goldReward: reward);
      case GameMode.mainStage:
        break;
    }
  }

  void _endDungeon({
    required bool success,
    required int goldReward,
    Equipment? itemReward,
  }) {
    if (_dungeonEnding) {
      return;
    }
    _dungeonEnding = true;
    onDungeonComplete?.call(
      success: success,
      goldReward: goldReward,
      itemReward: itemReward,
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
        targetPosition: _monster.position.clone(),
        onImpact: () => _resolveSkillHit(damage),
      ),
    );
  }

  void _resolveSkillHit(double damage) {
    _playHitEffect();
    _flashBackground();
    _spawnDamageText(damage, true);

    if (mode == GameMode.mainStage) {
      final ({Equipment? droppedItem, int goldReward}) hitResult =
          manager.damageMonster(damage);
      if (hitResult.droppedItem != null) {
        _spawnLootText(hitResult.droppedItem!);
      }
      if (hitResult.goldReward > 0) {
        _spawnGoldDrops(hitResult.goldReward);
      }
      return;
    }

    _damageDungeonMonster(damage);
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

  void _spawnDamageText(double damage, bool isCritical) {
    final Vector2 offset = Vector2(
      (_random.nextDouble() - 0.5) * 40,
      (_random.nextDouble() - 0.5) * 20,
    );
    add(
      DamageText(
        position: _monster.position + offset,
        damage: damage,
        isCritical: isCritical,
      ),
    );
  }

  void _spawnLootText(Equipment item) {
    add(
      LootText(
        position: _monster.position + Vector2(0, -40),
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
          position: _monster.position + scatterOffset,
          target: Vector2(24, 24),
          amount: amount,
          onCollected: manager.addGold,
        ),
      );
    }
  }
}

class PlayerComponent extends RectangleComponent {
  PlayerComponent({required Vector2 position})
      : super(
          size: Vector2(56, 56),
          paint: Paint()..color = const Color(0xFF3498DB),
          anchor: Anchor.center,
          position: position,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    add(
      MoveByEffect(
        Vector2(0, -10),
        EffectController(
          duration: 0.6,
          reverseDuration: 0.6,
          infinite: true,
          curve: Curves.easeInOut,
        ),
      ),
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

class DamageText extends TextComponent {
  DamageText({
    required Vector2 position,
    required double damage,
    required this.isCritical,
  }) : super(
          text: damage.toStringAsFixed(0),
          position: position,
          anchor: Anchor.center,
          textRenderer: TextPaint(
            style: TextStyle(
              color: isCritical ? Colors.yellow : Colors.white,
              fontSize: isCritical ? 27 : 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        );

  final bool isCritical;
  final Random _random = Random();

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final double duration = 0.5 + _random.nextDouble() * 0.5;

    add(
      MoveByEffect(
        Vector2(0, -40),
        EffectController(duration: duration, curve: Curves.easeOut),
      ),
    );
    add(
      OpacityEffect.fadeOut(
        EffectController(duration: duration),
        onComplete: removeFromParent,
      ),
    );
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
