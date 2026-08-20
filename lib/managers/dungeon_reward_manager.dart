import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/consumable_item_model.dart';
import '../models/dungeon_reward_config_model.dart';
import 'consumable_manager.dart';
import 'equipment_manager.dart';
import 'game_manager.dart';
import 'monster_drop_manager.dart';
import 'rune_manager.dart';
import 'supabase_manager.dart';

/// 던전 클리어 보상 설정(`dungeon_rewards_config`)을 관장하는 싱글턴 —
/// [MonsterDropTableManager]와 완전히 같은 관례(로컬 캐시 우선, Supabase는
/// 부가적인 백업/동기화 계층, 각 행을 독립적으로 굴리는 방식)를 따른다.
/// 하드코딩된 던전별 보상 상수([lib/game/idle_game.dart]의
/// `_guildDungeonGoldReward` 등) 대신, "던전 타입" 문자열 키 하나로 여러
/// 던전이 이 테이블 하나를 공유해서 원격에서 보상을 조정할 수 있게 하는
/// 것이 목적이다.
class DungeonRewardManager {
  DungeonRewardManager._internal();

  static final DungeonRewardManager instance = DungeonRewardManager._internal();

  /// "룬의 미궁"(요일 던전 목요일 슬롯)이 [grantRewardsFor]를 호출할 때
  /// 쓰는 던전 타입 키.
  static const String runeLabyrinth = 'rune_labyrinth';

  /// "승리자의 성소"(길드전 승리 전용 길드 던전)가 [grantRewardsFor]를
  /// 호출할 때 쓰는 던전 타입 키.
  static const String guildVictorySanctuary = 'guild_victory_sanctuary';

  /// "차원의 균열"(하루 한 번 로그라이크 모드)이 [RiftManager.endRun]에서
  /// 도달한 층수만큼 반복 호출할 때 쓰는 던전 타입 키.
  static const String dimensionalRift = 'dimensional_rift';

  final Random _random = Random();

  List<DungeonRewardConfigEntry> _config = const [];
  List<DungeonRewardConfigEntry> get config => _config;

  /// 단위 테스트 전용 — 실제 설정을 네트워크 없이 직접 주입한다
  /// ([MonsterDropTableManager.debugSeedForTest]와 같은 관례).
  @visibleForTesting
  void debugSeedForTest(List<DungeonRewardConfigEntry> config) {
    _config = config;
  }

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 채운 뒤 원격 설정을
  /// 받아와 갱신을 시도한다.
  Future<void> loadData() async {
    await _loadLocal();

    final List<Map<String, dynamic>> rows =
        await SupabaseManager.instance.fetchDungeonRewardsConfig();
    if (rows.isEmpty) {
      debugPrint(
        '[DungeonRewardManager] 던전 보상 설정이 비어 있습니다(dungeon_rewards_config 테이블/RLS '
        '정책을 확인하세요). 기존 캐시(${_config.length}건)를 유지합니다.',
      );
    } else {
      final List<DungeonRewardConfigEntry> parsed = [];
      for (final Map<String, dynamic> row in rows) {
        try {
          parsed.add(DungeonRewardConfigEntry.fromJson(row));
        } catch (error) {
          debugPrint('[DungeonRewardManager] 설정 행 파싱 실패(id=${row['id']}): $error');
        }
      }
      if (parsed.isNotEmpty) {
        _config = parsed;
      } else {
        debugPrint('[DungeonRewardManager] 파싱 가능한 보상 항목이 하나도 없습니다 — 컬럼명/타입을 확인하세요.');
      }
    }

    await _saveLocal();
  }

  /// [dungeonType]에 해당하는 설정 행들을 각각 독립적으로 굴려서, 당첨된
  /// 보상을 그 자리에서 곧장 지급하고 지급 내역을 반환한다(결과 다이얼로그가
  /// "무엇을 얼마나 받았는지" 보여줄 때 쓴다). 설정이 아직 비어 있으면(DB에
  /// 해당 던전 행이 없거나 로드 실패) 조용히 빈 리스트만 돌아온다 —
  /// [rollDropsForKill]과 마찬가지로 호출부가 별도 예외 처리를 할 필요가
  /// 없다.
  List<DungeonRewardGrant> grantRewardsFor(String dungeonType, {int chapter = 1}) {
    final List<DungeonRewardGrant> granted = [];
    for (final DungeonRewardConfigEntry entry in _config) {
      if (entry.dungeonType != dungeonType) {
        continue;
      }
      if (_random.nextDouble() >= entry.probability.clamp(0.0, 1.0)) {
        continue;
      }
      final int quantity = _rollQuantity(entry);
      if (quantity <= 0) {
        continue;
      }

      switch (entry.itemType) {
        case DungeonRewardItemType.gold:
          GameManager.instance.addGold(quantity);
        case DungeonRewardItemType.gem:
          GameManager.instance.addGems(quantity);
        case DungeonRewardItemType.runeFragment:
          RuneManager.instance.addFragments(quantity);
        case DungeonRewardItemType.consumable:
          final ConsumableType? type = entry.consumableType;
          if (type != null) {
            ConsumableManager.instance.addItem(type, quantity);
          }
        case DungeonRewardItemType.equipment:
          // 몬스터 드랍 테이블과 같은 챕터 기준 등급 풀을 그대로 재사용한다
          // ([MonsterDropTableManager.equipmentGradesForChapter]).
          for (int i = 0; i < quantity; i++) {
            EquipmentManager.instance.generateGuaranteedLoot(
              MonsterDropTableManager.equipmentGradesForChapter(chapter),
            );
          }
      }

      granted.add(
        DungeonRewardGrant(
          itemType: entry.itemType,
          quantity: quantity,
          consumableType: entry.consumableType,
        ),
      );
    }
    return granted;
  }

  int _rollQuantity(DungeonRewardConfigEntry entry) {
    if (entry.maxQuantity <= entry.minQuantity) {
      return entry.minQuantity;
    }
    return entry.minQuantity + _random.nextInt(entry.maxQuantity - entry.minQuantity + 1);
  }

  static const String _saveKey = 'dungeon_reward_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode(_config.map((entry) => entry.toCacheJson()).toList()),
    );
  }

  Future<void> _loadLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      return;
    }
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      _config = decoded
          .map((entry) => DungeonRewardConfigEntry.fromJson(entry as Map<String, dynamic>))
          .toList();
    } catch (error) {
      debugPrint('[DungeonRewardManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }
  }
}
