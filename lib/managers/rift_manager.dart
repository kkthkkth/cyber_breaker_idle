import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dungeon_reward_config_model.dart';
import '../models/rift_model.dart';
import '../utils/time_util.dart';
import 'dungeon_reward_manager.dart';

/// "차원의 균열" — 하루 한 번 즐기는 로그라이크 모드를 관장하는 싱글턴.
/// 메인 스테이지와 완전히 독립된 별도의 전투 스탯 체계를 가진다
/// (요구사항: "유저의 스탯은 메인 스탯이 아닌 균열 전용 기본 스탯 + 임시
/// 유물 버프로 덮어씌워져야 해") — 장비/펫/유물/룬/길드/환생 등 기존
/// 계정 단위 보너스는 전혀 반영하지 않는, 이 매니저 하나로 완결되는
/// 순수 로그라이크 파워 커브다. [IdleGame]이 [GameMode.dimensionalRift]
/// 일 때 [GameManager] 대신 이 매니저의 [rollAttack]/[resolveMonsterAttack]/
/// [applyLifeSteal]을 호출한다.
///
/// 한 번의 탐험(run)은 [startRun]으로 시작해 층([floor])을 하나씩
/// 올리며(전투 승리 또는 휴식) [maxFloor]를 클리어하거나 [riftHp]가
/// 0이 되면([endRun]) 끝난다. [WeekdayDungeonManager]와 같은 관례로
/// 로컬(SharedPreferences)에 진행 상태를 저장해 앱을 껐다 켜도 같은 날
/// 안에는 이어서 진행할 수 있다 — 다만 Supabase 동기화는 두지 않았다
/// (신규 GuideMissionManager와 같은 판단: 하루 단위로 리셋되는 단일 기기
/// 콘텐츠라 기기 변경 시 그날 진행분을 잃는 정도는 감수할 만하다).
class RiftManager extends ChangeNotifier {
  RiftManager._internal();

  static final RiftManager instance = RiftManager._internal();

  /// 이 층을 클리어하면(=[floor]가 이 값을 넘어서면) 탐험이 성공 종료된다.
  static const int maxFloor = 20;

  // ── 균열 전용 기본 스탯(메인 스탯과 완전히 무관) ──────────────────────
  static const double _baseAttack = 30;
  static const double _baseDefense = 10;
  static const double _baseMaxHp = 300;
  static const double _baseCritRate = 0.1;
  static const double _baseCritMultiplier = 1.5;
  static const double _baseEvasionRate = 0.05;
  static const double _maxCritRate = 0.9;

  // ── 균열 몬스터 기본 판정(GameManager의 몬스터 상수를 단순화해 그대로 참고) ──
  static const double _monsterBaseCritRate = 0.15;
  static const double _monsterCritMultiplier = 1.5;
  static const double _monsterBaseEvasionRate = 0.1;
  static const double _monsterAttackSpeed = 0.8;

  /// 휴식처 카드가 회복시키는 비율 — [riftMaxHp] 기준.
  static const double _restHealRatio = 0.3;

  final Random _random = Random();

  bool isActive = false;

  /// 지금 도전 중인 층 — [startRun]에서 1로 시작한다. [floor] > [maxFloor]
  /// 가 되면 방금 [maxFloor]층을 클리어했다는 뜻이다([isFinalFloorCleared]).
  int floor = 0;

  double riftHp = _baseMaxHp;
  bool isEliteBattle = false;

  /// 10층/20층 확정 보스 조우 여부 — [beginBattle]이 [RiftCardType.boss]
  /// 카드로 호출되면 true. 엘리트보다 훨씬 강한 배율([_monsterHpForFloor]/
  /// [_monsterAttackForFloor] 참고)로 몬스터가 스폰되고, [IdleGame]이 이
  /// 값을 보고 기존 [BossWarningText] 연출을 띄운다.
  bool isBossBattle = false;
  double currentMonsterMaxHp = 0;
  double currentMonsterAttack = 0;

  List<RiftRelic> equippedRelics = [];
  List<RiftCard> currentCards = const [];

  bool hasFreeEntryToday = true;
  String? _lastResetDate;

  double get riftMaxHp => _baseMaxHp;

  double get attackPower => _baseAttack * (1 + _relicSum(RiftRelicEffect.attackPercent));

  double get defense => _baseDefense * (1 + _relicSum(RiftRelicEffect.defensePercent));

  double get critRate =>
      (_baseCritRate + _relicSum(RiftRelicEffect.critRatePercent)).clamp(0.0, _maxCritRate);

  double get lifeSteal => _relicSum(RiftRelicEffect.lifeStealPercent);

  double get hpRegenPerFloorRatio => _relicSum(RiftRelicEffect.hpRegenPerFloor);

  double get monsterAttackSpeed => _monsterAttackSpeed;

  bool get isFinalFloorCleared => floor > maxFloor;

  bool get canStartNewRun => isActive || hasFreeEntryToday;

  double _relicSum(RiftRelicEffect effect) => equippedRelics
      .where((relic) => relic.effect == effect)
      .fold(0.0, (sum, relic) => sum + relic.value);

  /// 단위 테스트 전용 — 실제 상태를 네트워크/저장소 없이 직접 주입한다
  /// ([PotionManager.debugSeedForTest]와 같은 관례).
  @visibleForTesting
  void debugSeedForTest({
    bool? isActive,
    int? floor,
    double? riftHp,
    List<RiftRelic>? equippedRelics,
    bool? hasFreeEntryToday,
  }) {
    if (isActive != null) this.isActive = isActive;
    if (floor != null) this.floor = floor;
    if (riftHp != null) this.riftHp = riftHp;
    if (equippedRelics != null) this.equippedRelics = equippedRelics;
    if (hasFreeEntryToday != null) this.hasFreeEntryToday = hasFreeEntryToday;
  }

  /// [DungeonManager.checkAndResetDailyCounts]와 동일한 관례 — 서버(NTP)
  /// 기준 날짜가 바뀌면 무료 입장권을 다시 채운다. 진행 중인 탐험
  /// ([isActive])은 날짜가 바뀌어도 강제로 끊지 않는다 — 자정을 걸친
  /// 세션은 계속 이어서 할 수 있고, 다음 "새 탐험"부터 새 티켓을 쓴다.
  Future<void> checkAndResetDailyTicket() async {
    final DateTime now = await getNetworkTime();
    final String today = _formatDate(now);
    if (_lastResetDate == today) {
      return;
    }
    _lastResetDate = today;
    hasFreeEntryToday = true;
    notifyListeners();
    await _saveLocal();
  }

  /// 균열 탐험을 시작한다 — 이미 진행 중인 탐험이 있으면(예: 앱을 껐다가
  /// 같은 날 다시 켠 경우) 티켓을 새로 쓰지 않고 그대로 재개한다. 무료
  /// 입장권이 없으면 false.
  Future<bool> startRun() async {
    await checkAndResetDailyTicket();
    if (isActive) {
      return true;
    }
    if (!hasFreeEntryToday) {
      return false;
    }
    hasFreeEntryToday = false;
    isActive = true;
    floor = 1;
    riftHp = riftMaxHp;
    equippedRelics = [];
    _rollCards();
    notifyListeners();
    await _saveLocal();
    return true;
  }

  /// 10층/20층은 무작위 뽑기 없이 무조건 [RiftCardPool.boss] 3장으로
  /// 채운다(요구사항: "확정 보스 조우") — 그 외 층은 기존처럼
  /// [_rollSingleCard]를 3번 굴린다.
  static const Set<int> _bossFloors = {10, 20};

  void _rollCards() {
    if (_bossFloors.contains(floor)) {
      currentCards = List.filled(3, RiftCardPool.boss);
      return;
    }
    currentCards = List.generate(3, (_) => _rollSingleCard());
  }

  /// 50% 일반 전투 / 30% 엘리트 전투 / 20% 휴식처 — 1차 확률(추후 조정
  /// 대상). 카드 3장은 서로 독립적으로 뽑히므로 같은 카드가 중복될 수
  /// 있다(요구사항에 "서로 달라야 한다"는 제약이 없다).
  RiftCard _rollSingleCard() {
    final double roll = _random.nextDouble();
    if (roll < 0.5) {
      return RiftCardPool.normalBattle;
    }
    if (roll < 0.8) {
      return RiftCardPool.eliteBattle;
    }
    return RiftCardPool.rest;
  }

  /// [RiftScreen]이 전투 카드를 탭했을 때 호출 — 이번 층 몬스터의 체력/
  /// 공격력을 확정한다. [IdleGame._activateDungeon]이 이 값(과
  /// [isBossBattle])을 그대로 읽어 몬스터를 스폰한다.
  void beginBattle(RiftCardType type) {
    isEliteBattle = type == RiftCardType.eliteBattle;
    isBossBattle = type == RiftCardType.boss;
    currentMonsterMaxHp = _monsterHpForFloor(floor, type);
    currentMonsterAttack = _monsterAttackForFloor(floor, type);
    notifyListeners();
  }

  /// 층이 깊어질수록 12%씩 복리로 강해지는 1차 공식 — 엘리트는 체력
  /// 2.2배, 보스는 4배("엘리트보다 훨씬 강한 진짜 벽" 요구사항)로 순간
  /// 뻥튀기한다. 밸런스는 전부 1차 값이라 추후 실측 후 조정 대상.
  static double _monsterHpForFloor(int floor, RiftCardType type) {
    final double base = 60 * pow(1.14, floor - 1).toDouble();
    return switch (type) {
      RiftCardType.normalBattle => base,
      RiftCardType.eliteBattle => base * 2.2,
      RiftCardType.boss => base * 4.0,
      RiftCardType.rest => base,
    };
  }

  static double _monsterAttackForFloor(int floor, RiftCardType type) {
    final double base = 6 * pow(1.09, floor - 1).toDouble();
    return switch (type) {
      RiftCardType.normalBattle => base,
      RiftCardType.eliteBattle => base * 1.6,
      RiftCardType.boss => base * 2.5,
      RiftCardType.rest => base,
    };
  }

  /// 플레이어의 공격 1회를 판정한다 — [GameManager.rollAttack]과 같은
  /// 구조(회피→크리티컬→데미지)를 균열 전용 스탯으로 단순화해 재현한다.
  ({double damage, bool isCritical, bool evaded}) rollAttack() {
    final double monsterEvasionRate = _monsterBaseEvasionRate.clamp(0.0, 1.0);
    if (_random.nextDouble() < monsterEvasionRate) {
      return (damage: 0, isCritical: false, evaded: true);
    }
    final bool isCritical = _random.nextDouble() < critRate;
    final double damage = isCritical ? attackPower * _baseCritMultiplier : attackPower;
    return (damage: damage, isCritical: isCritical, evaded: false);
  }

  /// 몬스터가 플레이어를 공격 — [GameManager.resolveMonsterAttack]과 같은
  /// 구조를 [riftHp]에 적용한다. 실제 패배 처리([IdleGame._endDungeon])는
  /// 여기서 하지 않고 [playerDefeated] 신호만 돌려준다.
  ({bool playerDefeated, bool evaded, bool isCritical, double damageDealt}) resolveMonsterAttack() {
    final bool evaded = _random.nextDouble() < _baseEvasionRate;
    if (evaded) {
      return (playerDefeated: false, evaded: true, isCritical: false, damageDealt: 0);
    }

    final bool isCritical = _random.nextDouble() < _monsterBaseCritRate;
    double rawDamage = currentMonsterAttack;
    if (isCritical) {
      rawDamage *= _monsterCritMultiplier;
    }

    final double finalDamage = (rawDamage - defense).clamp(0.0, double.infinity);
    riftHp = (riftHp - finalDamage).clamp(0.0, riftMaxHp);
    notifyListeners();

    return (
      playerDefeated: riftHp <= 0,
      evaded: false,
      isCritical: isCritical,
      damageDealt: finalDamage,
    );
  }

  /// [GameManager.applyLifeSteal]과 같은 관례 — 실제로 회복된 절대량을
  /// 반환한다.
  double applyLifeSteal(double damageDealt) {
    if (lifeSteal <= 0 || riftHp >= riftMaxHp) {
      return 0;
    }
    final double healAmount = damageDealt * lifeSteal;
    final double before = riftHp;
    riftHp = (riftHp + healAmount).clamp(0.0, riftMaxHp);
    notifyListeners();
    return riftHp - before;
  }

  /// 전투 승리 직후 [RiftBattleScreen]이 호출 — 무작위 유물 후보 3개를
  /// 뽑아 돌려준다(실제 적용은 [applyRelicChoice]).
  List<RiftRelic> offerRelics() {
    final List<RiftRelic> pool = List<RiftRelic>.from(RiftRelicPool.all)..shuffle(_random);
    return pool.take(3).toList();
  }

  /// 유물을 고른 뒤 층을 올리고 다음 갈림길 카드를 다시 뽑는다.
  Future<void> applyRelicChoice(RiftRelic relic) async {
    equippedRelics = [...equippedRelics, relic];
    await _advanceFloor();
  }

  /// 휴식처 카드 — 전투 없이 체력을 회복하고 곧장 층을 올린다.
  Future<void> rest() async {
    riftHp = (riftHp + riftMaxHp * _restHealRatio).clamp(0.0, riftMaxHp);
    await _advanceFloor();
  }

  Future<void> _advanceFloor() async {
    floor++;
    // 층 진입마다 체력 회복 유물([RiftRelicEffect.hpRegenPerFloor]) — 휴식처
    // 자체 회복과 별개로 함께 적용된다.
    if (hpRegenPerFloorRatio > 0) {
      riftHp = (riftHp + riftMaxHp * hpRegenPerFloorRatio).clamp(0.0, riftMaxHp);
    }
    if (!isFinalFloorCleared) {
      _rollCards();
    }
    notifyListeners();
    await _saveLocal();
  }

  /// 탐험을 종료한다 — [riftHp]가 0이 되었거나(실패) [maxFloor]를
  /// 클리어했을 때(성공) [RiftBattleScreen]/[RiftScreen]이 호출한다.
  /// 도달한 층수([reachedFloor])만큼 [DungeonRewardManager.dimensionalRift]
  /// 를 반복 굴려 룬 조각/보석 등을 실제로 지급하고([DungeonRewardManager
  /// .grantRewardsFor]가 지급까지 전담), 그 결과를 그대로 돌려준다.
  Future<List<DungeonRewardGrant>> endRun() async {
    final int reachedFloor = (isFinalFloorCleared ? maxFloor : floor - 1).clamp(0, maxFloor);

    final List<DungeonRewardGrant> grants = [];
    for (int i = 0; i < reachedFloor; i++) {
      grants.addAll(DungeonRewardManager.instance.grantRewardsFor(DungeonRewardManager.dimensionalRift));
    }

    isActive = false;
    floor = 0;
    riftHp = riftMaxHp;
    equippedRelics = [];
    currentCards = const [];
    notifyListeners();
    await _saveLocal();
    return grants;
  }

  static String _formatDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static const String _saveKey = 'rift_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode({
        'isActive': isActive,
        'floor': floor,
        'riftHp': riftHp,
        'equippedRelicIds': [for (final RiftRelic relic in equippedRelics) relic.id],
        'hasFreeEntryToday': hasFreeEntryToday,
        'lastResetDate': _lastResetDate,
      }),
    );
  }

  Future<void> loadData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
        isActive = data['isActive'] as bool? ?? isActive;
        floor = (data['floor'] as num?)?.toInt() ?? floor;
        riftHp = (data['riftHp'] as num?)?.toDouble() ?? riftHp;
        hasFreeEntryToday = data['hasFreeEntryToday'] as bool? ?? hasFreeEntryToday;
        _lastResetDate = data['lastResetDate'] as String?;
        final List<dynamic>? relicIds = data['equippedRelicIds'] as List<dynamic>?;
        if (relicIds != null) {
          final List<RiftRelic> restored = [];
          for (final dynamic id in relicIds) {
            for (final RiftRelic relic in RiftRelicPool.all) {
              if (relic.id == id) {
                restored.add(relic);
                break;
              }
            }
          }
          equippedRelics = restored;
        }
        if (isActive) {
          _rollCards();
        }
      } catch (error) {
        debugPrint('[RiftManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
      }
    }

    await checkAndResetDailyTicket();
    notifyListeners();
  }
}
