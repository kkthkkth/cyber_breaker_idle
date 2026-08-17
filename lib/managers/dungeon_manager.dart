import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/time_util.dart';
import 'supabase_manager.dart';

enum DungeonType { goldDungeon, equipmentDungeon, towerOfInfinity, petDungeon }

class DungeonManager extends ChangeNotifier with WidgetsBindingObserver {
  DungeonManager._internal();

  static final DungeonManager instance = DungeonManager._internal();

  static const int maxDailyTickets = 3;
  static const int maxDailyTowerSweeps = 3;

  int goldDungeonTickets = maxDailyTickets;
  int equipmentDungeonTickets = maxDailyTickets;

  /// '펫 산책로' 입장권 — 다른 일일 티켓들과 같은 [_lastResetDate] 커서로
  /// 자정마다 함께 초기화된다(별도 커서를 두지 않음: 모든 일일 티켓이 같은
  /// 자정 경계에서 갱신되는 게 자연스럽다).
  int petDungeonTickets = maxDailyTickets;

  /// 무한의 탑 최고 클리어 층수(0 = 아직 하나도 못 깸) — `profiles
  /// .highest_tower_floor`와 동기화된다([loadDungeonData]가 앱 시작 시
  /// 서버 값으로 갱신하고, [clearFloor]가 층을 처음 깰 때마다 서버에도
  /// push한다). 예전엔 이 값 자체를 저장하지 않고 "지금 도전 중인 층"
  /// (1부터 시작하는 currentFloor)만 로컬에 저장했다 — 서버 컬럼명에 맞춰
  /// "최고 클리어 층수"(0-indexed 의미)로 의미를 통일했다.
  int highestClearedFloor = 0;

  /// 유저가 지금 도전할 층 — 항상 [highestClearedFloor] + 1(요구사항
  /// 그대로: "유저가 도전할 층수(highest_tower_floor + 1)"). Tower of
  /// Infinity has no ticket limit — you simply can't skip floors, so
  /// progress itself is the gate.
  int get currentFloor => highestClearedFloor + 1;

  /// Daily limit on repeat-clearing the previously-cleared floor (gold
  /// "sweep" runs) — separate from the ticket-gated gold/equip dungeons.
  int dailyTowerSweepCount = maxDailyTowerSweeps;

  /// yyyy-MM-dd of the last time daily counters were reset.
  String? _lastResetDate;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Fire-and-forget: the override signature must stay void/sync.
      checkAndResetDailyCounts();
    }
  }

  Future<bool> consumeTicket(DungeonType type) async {
    await checkAndResetDailyCounts();

    switch (type) {
      case DungeonType.goldDungeon:
        if (goldDungeonTickets <= 0) {
          return false;
        }
        goldDungeonTickets--;
      case DungeonType.equipmentDungeon:
        if (equipmentDungeonTickets <= 0) {
          return false;
        }
        equipmentDungeonTickets--;
      case DungeonType.petDungeon:
        if (petDungeonTickets <= 0) {
          return false;
        }
        petDungeonTickets--;
      case DungeonType.towerOfInfinity:
        break;
    }

    notifyListeners();
    return true;
  }

  /// Consumes one daily tower-sweep attempt. Returns false (without
  /// consuming anything) if none remain today.
  Future<bool> consumeTowerSweep() async {
    await checkAndResetDailyCounts();
    if (dailyTowerSweepCount <= 0) {
      return false;
    }
    dailyTowerSweepCount--;
    notifyListeners();
    saveDungeonData();
    return true;
  }

  /// +1 charges granted by consuming a 던전 충전권 (see ConsumableManager /
  /// consumable_inventory_screen.dart's useItem switch).
  void addGoldDungeonTicket() {
    goldDungeonTickets++;
    notifyListeners();
    saveDungeonData();
  }

  void addEquipmentDungeonTicket() {
    equipmentDungeonTickets++;
    notifyListeners();
    saveDungeonData();
  }

  void addPetDungeonTicket() {
    petDungeonTickets++;
    notifyListeners();
    saveDungeonData();
  }

  /// Gold-per-damage ratio for the gold dungeon. Swappable at runtime once
  /// this moves to a DB — [goldForDamage] is what every hit (normal attack
  /// or skill) reads through.
  double goldRatio = 0.2;

  int goldForDamage(double damage) => (damage * goldRatio).round();

  void addTowerSweepTicket() {
    dailyTowerSweepCount++;
    notifyListeners();
    saveDungeonData();
  }

  /// Resets today's dungeon counters (gold/equip tickets, tower sweeps) back
  /// to their daily maximums if the device date has rolled over since
  /// [_lastResetDate]. Safe to call repeatedly — a no-op once already
  /// current for today. Saves immediately when a reset actually happens.
  Future<void> checkAndResetDailyCounts() async {
    final DateTime now = await getNetworkTime();
    final String today = _formatDate(now);
    if (_lastResetDate == today) {
      return;
    }

    goldDungeonTickets = maxDailyTickets;
    equipmentDungeonTickets = maxDailyTickets;
    petDungeonTickets = maxDailyTickets;
    dailyTowerSweepCount = maxDailyTowerSweeps;
    _lastResetDate = today;

    notifyListeners();
    await saveDungeonData();
  }

  static String _formatDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  /// [floor]층을 처음으로 클리어했다 — [highestClearedFloor]를 그 값으로
  /// 올리고 로컬 저장 + 서버 `profiles.highest_tower_floor` UPDATE까지
  /// 확실하게 연결한다(요구사항: "탑 클리어 시... DB의 highest_tower_floor
  /// 값을 클리어한 층수로 UPDATE"). [floor]가 이미 깬 층 이하면(소탕 모드
  /// 등으로 중복 호출돼도) 아무것도 바꾸지 않는다 — 진행도는 항상 앞으로만
  /// 나아간다.
  Future<void> clearFloor(int floor) async {
    if (floor <= highestClearedFloor) {
      return;
    }
    highestClearedFloor = floor;
    notifyListeners();
    await saveDungeonData();
    unawaited(SupabaseManager.instance.updateHighestTowerFloor(highestClearedFloor));
  }

  static const String _saveKey = 'dungeon_manager_save';

  Future<void> saveDungeonData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final Map<String, dynamic> data = {
      'goldDungeonTickets': goldDungeonTickets,
      'equipmentDungeonTickets': equipmentDungeonTickets,
      'petDungeonTickets': petDungeonTickets,
      'highestClearedFloor': highestClearedFloor,
      'dailyTowerSweepCount': dailyTowerSweepCount,
      'lastResetDate': _lastResetDate,
    };

    await prefs.setString(_saveKey, jsonEncode(data));
  }

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 채운 뒤, 서버의
  /// `profiles.highest_tower_floor`를 다시 확인해 갱신한다(요구사항: "유저
  /// 데이터를 불러올 때... highest_tower_floor 값을 불러와줘").
  Future<void> loadDungeonData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);

    if (raw != null) {
      try {
        final Map<String, dynamic> data =
            jsonDecode(raw) as Map<String, dynamic>;

        goldDungeonTickets =
            data['goldDungeonTickets'] as int? ?? goldDungeonTickets;
        equipmentDungeonTickets =
            data['equipmentDungeonTickets'] as int? ?? equipmentDungeonTickets;
        petDungeonTickets = data['petDungeonTickets'] as int? ?? petDungeonTickets;
        // 예전 저장 파일은 "지금 도전 중인 층"(1부터 시작하는 currentFloor)을
        // 저장했다 — 그 값이 남아있으면 새 의미(최고 클리어 층수, 0부터
        // 시작)로 변환해서 기존 유저의 진행도가 1층으로 리셋되지 않게 한다.
        if (data.containsKey('highestClearedFloor')) {
          highestClearedFloor =
              data['highestClearedFloor'] as int? ?? highestClearedFloor;
        } else if (data['currentFloor'] is int) {
          highestClearedFloor = ((data['currentFloor'] as int) - 1).clamp(0, 1 << 30);
        }
        dailyTowerSweepCount =
            data['dailyTowerSweepCount'] as int? ?? dailyTowerSweepCount;
        // lastResetDate used to be saved as a millisecondsSinceEpoch int;
        // migrate old saves instead of crashing on the type cast.
        final dynamic savedResetDate = data['lastResetDate'];
        if (savedResetDate is String) {
          _lastResetDate = savedResetDate;
        } else if (savedResetDate is int) {
          _lastResetDate = _formatDate(
            DateTime.fromMillisecondsSinceEpoch(savedResetDate),
          );
        } else {
          _lastResetDate = null;
        }
      } catch (error) {
        debugPrint('[DungeonManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
      }
    }

    // 서버가 이 유저의 최고 클리어 층수를 더 정확히 알고 있을 수 있다
    // (예: 다른 기기에서 진행) — 로컬보다 서버 값이 더 높을 때만 반영해서,
    // 오프라인 중에 로컬에서 이미 앞서간 진행도를 실수로 되돌리지 않는다.
    final int? serverFloor = await SupabaseManager.instance.fetchHighestTowerFloor();
    if (serverFloor != null && serverFloor > highestClearedFloor) {
      highestClearedFloor = serverFloor;
    }

    await checkAndResetDailyCounts();
    notifyListeners();
  }
}
