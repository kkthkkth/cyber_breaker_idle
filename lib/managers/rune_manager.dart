import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/quest_model.dart';
import '../models/rune_model.dart';
import 'quest_manager.dart';
import 'supabase_manager.dart';

/// 룬 인벤토리/장착/레벨업/합성을 관장하는 싱글턴 — 이 프로젝트의 다른
/// 매니저들과 같은 관례: **로컬(SharedPreferences)이 유일한 신뢰
/// 소스**이고, Supabase는 그 위에 얹는 부가적인 백업/동기화 계층이다.
/// 룬 조각(재화)은 요일 던전([WeekdayDungeonManager])이 지급한다.
class RuneManager extends ChangeNotifier {
  RuneManager._internal();

  static final RuneManager instance = RuneManager._internal();

  static const Uuid _uuid = Uuid();
  final Random _random = Random();

  /// 캐릭터가 동시에 장착할 수 있는 룬 슬롯 수.
  static const int maxSlots = 6;

  /// 룬 하나를 새로 만드는 데 드는 룬 조각 — 결과 스탯은 [type] 안에서
  /// 무작위([RuneCatalog]).
  static const int craftCostFragments = 50;

  int runeFragments = 0;
  List<Rune> runes = [];

  List<Rune> get equippedRunes => runes.where((rune) => rune.isEquipped).toList();

  /// 단위 테스트 전용 — 실제 보유 룬/조각 수를 네트워크 없이 직접
  /// 주입한다([ArtifactManager.debugSeedForTest]와 같은 관례).
  @visibleForTesting
  void debugSeedForTest({List<Rune>? runes, int? runeFragments}) {
    if (runes != null) {
      this.runes = runes;
    }
    if (runeFragments != null) {
      this.runeFragments = runeFragments;
    }
  }

  Rune? findById(String id) {
    for (final Rune rune in runes) {
      if (rune.id == id) {
        return rune;
      }
    }
    return null;
  }

  /// [statKey]를 가진 모든 "장착된" 룬의 [Rune.value] 합계 — [GameManager]가
  /// 공격력/방어력/최대체력/크리티컬 등 계산마다 호출한다. 인벤토리에만
  /// 있는(미장착) 룬은 전투에 영향을 주지 않는다.
  double totalBonus(String statKey) => equippedRunes
      .where((rune) => rune.statKey == statKey)
      .fold(0.0, (sum, rune) => sum + rune.value);

  /// 요일 던전(목요일) 등 외부에서 룬 조각을 지급할 때 호출한다.
  void addFragments(int amount) {
    if (amount <= 0) {
      return;
    }
    runeFragments += amount;
    notifyListeners();
    unawaited(_saveLocal());
    unawaited(SupabaseManager.instance.updateRuneFragments(runeFragments));
  }

  /// 조각 [craftCostFragments]개를 소모해 [type] 색깔의 새 룬 1개를
  /// 만든다(스탯은 그 색깔 풀에서 무작위) — 조각이 부족하면 아무것도
  /// 바꾸지 않고 null.
  Rune? craftRune(RuneType type) {
    if (runeFragments < craftCostFragments) {
      return null;
    }
    runeFragments -= craftCostFragments;

    final RuneStatDef def = RuneCatalog.pool[type]![_random.nextInt(RuneCatalog.pool[type]!.length)];
    final Rune rune = Rune(
      id: _uuid.v4(),
      type: type,
      statKey: def.statKey,
      baseValue: def.baseValue,
      valuePerLevel: def.valuePerLevel,
    );
    runes.add(rune);

    notifyListeners();
    unawaited(_saveLocal());
    unawaited(_syncRuneRemote(rune));
    unawaited(SupabaseManager.instance.updateRuneFragments(runeFragments));
    // 주간 퀘스트("룬 제작/합성 N회 진행") 진행도 — 제작과 합성을
    // 구분하지 않고 같은 액션으로 합산한다.
    QuestManager.instance.updateProgress(QuestActionType.runeCraftOrSynthesize, 1);
    return rune;
  }

  /// [runeId]를 [slot](0~[maxSlots]-1)에 장착한다 — 그 슬롯에 이미 다른
  /// 룬이 있으면 자동으로 해제된다. 잘못된 슬롯 번호면 false.
  bool equip(String runeId, int slot) {
    if (slot < 0 || slot >= maxSlots) {
      return false;
    }
    final int index = runes.indexWhere((rune) => rune.id == runeId);
    if (index == -1) {
      return false;
    }

    for (int i = 0; i < runes.length; i++) {
      if (runes[i].equippedSlot == slot && runes[i].id != runeId) {
        runes[i] = runes[i].copyWith(clearSlot: true);
      }
    }
    runes[index] = runes[index].copyWith(equippedSlot: slot);

    notifyListeners();
    unawaited(_saveLocal());
    unawaited(_syncRuneRemote(runes[index]));
    return true;
  }

  bool unequip(String runeId) {
    final int index = runes.indexWhere((rune) => rune.id == runeId);
    if (index == -1 || !runes[index].isEquipped) {
      return false;
    }
    runes[index] = runes[index].copyWith(clearSlot: true);

    notifyListeners();
    unawaited(_saveLocal());
    unawaited(_syncRuneRemote(runes[index]));
    return true;
  }

  /// [runeId]를 한 단계 레벨업한다 — 조각이 부족하거나 이미 만렙이면
  /// false.
  bool levelUp(String runeId) {
    final int index = runes.indexWhere((rune) => rune.id == runeId);
    if (index == -1) {
      return false;
    }
    final Rune rune = runes[index];
    if (!rune.canLevelUp || runeFragments < rune.nextLevelFragmentCost) {
      return false;
    }

    runeFragments -= rune.nextLevelFragmentCost;
    runes[index] = rune.copyWith(level: rune.level + 1);

    notifyListeners();
    unawaited(_saveLocal());
    unawaited(_syncRuneRemote(runes[index]));
    unawaited(SupabaseManager.instance.updateRuneFragments(runeFragments));
    return true;
  }

  /// 같은 색깔·같은 레벨인 두 룬([runeIdA]/[runeIdB])을 합성해 그 색깔의
  /// 새 룬(스탯 무작위, 레벨 +1) 하나를 만든다 — 재료 두 개는 소모되고
  /// (장착 중이었으면 자동 해제), 결과물은 인벤토리에 미장착 상태로
  /// 추가된다. 조건이 안 맞으면(다른 색/다른 레벨/만렙 재료 등) 아무것도
  /// 바꾸지 않고 null.
  Rune? synthesize(String runeIdA, String runeIdB) {
    if (runeIdA == runeIdB) {
      return null;
    }
    final Rune? a = findById(runeIdA);
    final Rune? b = findById(runeIdB);
    if (a == null || b == null) {
      return null;
    }
    if (a.type != b.type || a.level != b.level) {
      return null;
    }

    final int resultLevel = (a.level + 1).clamp(1, Rune.maxLevel);
    final RuneStatDef def =
        RuneCatalog.pool[a.type]![_random.nextInt(RuneCatalog.pool[a.type]!.length)];
    final Rune result = Rune(
      id: _uuid.v4(),
      type: a.type,
      statKey: def.statKey,
      baseValue: def.baseValue,
      valuePerLevel: def.valuePerLevel,
      level: resultLevel,
    );

    runes.removeWhere((rune) => rune.id == runeIdA || rune.id == runeIdB);
    runes.add(result);

    notifyListeners();
    unawaited(_saveLocal());
    unawaited(SupabaseManager.instance.deleteUserRunes([runeIdA, runeIdB]));
    unawaited(_syncRuneRemote(result));
    QuestManager.instance.updateProgress(QuestActionType.runeCraftOrSynthesize, 1);
    return result;
  }

  Future<void> _syncRuneRemote(Rune rune) =>
      SupabaseManager.instance.upsertUserRune(rune.toJson());

  static const String _saveKey = 'rune_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode({
        'runeFragments': runeFragments,
        'runes': runes.map((rune) => rune.toJson()).toList(),
      }),
    );
  }

  bool _hasLocalSave = false;

  Future<void> _loadLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      return;
    }
    _hasLocalSave = true;
    try {
      final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
      runeFragments = (data['runeFragments'] as num?)?.toInt() ?? runeFragments;
      final List<dynamic>? savedRunes = data['runes'] as List<dynamic>?;
      if (savedRunes != null) {
        runes = savedRunes
            .map((entry) => Rune.fromJson(entry as Map<String, dynamic>))
            .toList();
      }
    } catch (error) {
      debugPrint('[RuneManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }
  }

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 채운 뒤, 서버의
  /// 룬 보유 목록으로 다시 확인해 갱신한다(다른 기기에서 얻은 룬도
  /// 놓치지 않도록). 룬 조각은 로컬 저장이 아예 없을 때만(최초 실행/
  /// 재설치) 서버 값으로 채운다 — 있으면 로컬이 그대로 진짜 소스다
  /// ([ArtifactManager]류와 달리 "높은 쪽"이 없는 순수 소모성 재화라
  /// 단순 존재 여부로만 판단한다).
  Future<void> loadData() async {
    await _loadLocal();

    final List<Map<String, dynamic>> rows = await SupabaseManager.instance.fetchUserRunes();
    if (rows.isNotEmpty) {
      try {
        runes = rows.map(Rune.fromJson).toList();
      } catch (error) {
        debugPrint('[RuneManager] 서버 룬 목록 파싱 실패: $error');
      }
    }

    if (!_hasLocalSave) {
      final int? serverFragments = await SupabaseManager.instance.fetchRuneFragments();
      if (serverFragments != null) {
        runeFragments = serverFragments;
      }
    }

    await _saveLocal();
    notifyListeners();
  }
}
