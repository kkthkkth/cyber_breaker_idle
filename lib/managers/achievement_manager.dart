import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/achievement_model.dart';
import 'game_manager.dart';
import 'supabase_manager.dart';

/// 방치형 RPG 핵심 지표 3종(몬스터 누적 처치/최고 도달 챕터/누적 가챠
/// 횟수)에 대한 단계형 업적을 관장하는 싱글턴 — [MonthlyAttendanceManager]
/// 와 같은 관례(Set 기반 수령 목록, 로컬 우선)를 따른다.
///
/// [GameManager._onMonsterDefeated]가 몬스터를 잡을 때마다 [recordMonsterKill]
/// 을, [EquipmentManager]의 가챠 전용 진입점(`generateLootOfType`/
/// `drawMultipleGacha`)이 실제 뽑기 1회마다 [recordGachaPull]을 호출한다 —
/// 둘 다 절대 리셋되지 않는 누적값이다(일일 퀘스트의 QuestActionType
/// .monsterKill이나 [PityManager]의 천장 카운터와 달리, 자정이나 확정
/// 지급으로도 0으로 돌아가지 않는다). [GameManager.highestReachedChapter]
/// 는 이미 존재하는 값을 그대로 읽어 쓴다(별도 카운터 불필요).
class AchievementManager extends ChangeNotifier {
  AchievementManager._internal();

  static final AchievementManager instance = AchievementManager._internal();

  /// 카테고리별 단계 구성 — 단계가 오를수록 [AchievementTier.gemReward]도
  /// 커진다. 수치 밸런스는 1차 초안이라 실측 후 조정 가능.
  static const Map<AchievementCategory, List<AchievementTier>> tiers = {
    AchievementCategory.monsterKill: [
      AchievementTier(threshold: 100, gemReward: 10),
      AchievementTier(threshold: 1000, gemReward: 50),
      AchievementTier(threshold: 10000, gemReward: 200),
      AchievementTier(threshold: 100000, gemReward: 1000),
    ],
    AchievementCategory.highestChapter: [
      AchievementTier(threshold: 5, gemReward: 20),
      AchievementTier(threshold: 10, gemReward: 50),
      AchievementTier(threshold: 20, gemReward: 100),
      AchievementTier(threshold: 30, gemReward: 200),
      AchievementTier(threshold: 50, gemReward: 500),
    ],
    AchievementCategory.gachaCount: [
      AchievementTier(threshold: 50, gemReward: 30),
      AchievementTier(threshold: 100, gemReward: 80),
      AchievementTier(threshold: 300, gemReward: 200),
      AchievementTier(threshold: 500, gemReward: 400),
      AchievementTier(threshold: 1000, gemReward: 1000),
    ],
  };

  int totalMonsterKills = 0;
  int totalGachaPulls = 0;

  final Set<String> _claimedKeys = {};

  /// [category]의 현재 진행도 — [AchievementCategory.highestChapter]는
  /// 별도 카운터 없이 [GameManager.highestReachedChapter]를 그대로 읽는다.
  int progressFor(AchievementCategory category) => switch (category) {
    AchievementCategory.monsterKill => totalMonsterKills,
    AchievementCategory.gachaCount => totalGachaPulls,
    AchievementCategory.highestChapter => GameManager.instance.highestReachedChapter,
  };

  bool isTierClaimed(AchievementCategory category, int threshold) =>
      _claimedKeys.contains(achievementKey(category, threshold));

  bool canClaimTier(AchievementCategory category, int threshold) =>
      progressFor(category) >= threshold && !isTierClaimed(category, threshold);

  AchievementTier? _tierFor(AchievementCategory category, int threshold) {
    for (final AchievementTier tier in tiers[category] ?? const []) {
      if (tier.threshold == threshold) {
        return tier;
      }
    }
    return null;
  }

  /// 단위 테스트 전용 — 실제 카운터/수령 목록을 네트워크 없이 직접
  /// 주입한다([PityManager.debugSeedForTest]와 같은 관례).
  @visibleForTesting
  void debugSeedForTest({
    int? monsterKills,
    int? gachaPulls,
    Set<String>? claimedKeys,
  }) {
    if (monsterKills != null) totalMonsterKills = monsterKills;
    if (gachaPulls != null) totalGachaPulls = gachaPulls;
    if (claimedKeys != null) {
      _claimedKeys
        ..clear()
        ..addAll(claimedKeys);
    }
  }

  void recordMonsterKill() {
    totalMonsterKills += 1;
    notifyListeners();
    unawaited(_saveLocal());
  }

  void recordGachaPull() {
    totalGachaPulls += 1;
    notifyListeners();
    unawaited(_saveLocal());
  }

  /// [category]의 [threshold] 단계를 수령한다 — 아직 도달하지 못했거나
  /// (진행도 미달) 이미 수령했으면 아무것도 하지 않고 false.
  Future<bool> claimTier(AchievementCategory category, int threshold) async {
    if (!canClaimTier(category, threshold)) {
      return false;
    }
    final AchievementTier? tier = _tierFor(category, threshold);
    if (tier == null) {
      return false;
    }

    _claimedKeys.add(achievementKey(category, threshold));
    GameManager.instance.addGems(tier.gemReward);
    notifyListeners();
    await _saveLocal();
    unawaited(SupabaseManager.instance.claimAchievement(achievementKey(category, threshold)));
    unawaited(
      SupabaseManager.instance.updateAchievementCounters(
        monsterKills: totalMonsterKills,
        gachaPulls: totalGachaPulls,
      ),
    );
    return true;
  }

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 채운 뒤, 서버 값과
  /// 병합한다. 카운터는 더 큰 쪽(=더 진행된 쪽)을 신뢰하고, 수령 목록은
  /// 합집합으로 합친다 — 어느 쪽이 뒤처져 있어도 유저에게 불리한 방향으로
  /// 되돌리지 않는다.
  Future<void> loadData() async {
    await _loadLocal();

    final ({int monsterKills, int gachaPulls, Set<String> claimedKeys})? remote =
        await SupabaseManager.instance.fetchAchievementData();
    if (remote == null) {
      notifyListeners();
      return;
    }
    totalMonsterKills = max(totalMonsterKills, remote.monsterKills);
    totalGachaPulls = max(totalGachaPulls, remote.gachaPulls);
    final int beforeCount = _claimedKeys.length;
    _claimedKeys.addAll(remote.claimedKeys);
    if (beforeCount != _claimedKeys.length ||
        totalMonsterKills != remote.monsterKills ||
        totalGachaPulls != remote.gachaPulls) {
      await _saveLocal();
    }
    notifyListeners();
  }

  static const String _saveKey = 'achievement_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode({
        'totalMonsterKills': totalMonsterKills,
        'totalGachaPulls': totalGachaPulls,
        'claimedKeys': _claimedKeys.toList(),
      }),
    );
  }

  Future<void> _loadLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      return;
    }
    try {
      final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
      totalMonsterKills = (data['totalMonsterKills'] as num?)?.toInt() ?? totalMonsterKills;
      totalGachaPulls = (data['totalGachaPulls'] as num?)?.toInt() ?? totalGachaPulls;
      final List<dynamic>? keys = data['claimedKeys'] as List<dynamic>?;
      if (keys != null) {
        _claimedKeys
          ..clear()
          ..addAll(keys.cast<String>());
      }
    } catch (error) {
      debugPrint('[AchievementManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }
  }
}
