import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/battle_pass_model.dart';
import 'game_manager.dart';
import 'supabase_manager.dart';

/// 배틀패스(시즌 경험치/레벨/무료·프리미엄 보상 수령/프리미엄 해금)를
/// 관장하는 싱글턴 — 이 프로젝트의 다른 매니저들과 같은 관례를 따른다:
/// **로컬(SharedPreferences)이 유일한 신뢰 소스**이고, Supabase는 그 위에
/// 얹는 부가적인 백업/동기화 계층이다. BP 경험치 자체는 [QuestManager]가
/// 퀘스트 보상으로 넣어준다([addBpExp]) — 이 매니저는 그 값을 레벨/보상
/// 수령 상태로만 관리한다.
class BattlePassManager extends ChangeNotifier {
  BattlePassManager._internal();

  static final BattlePassManager instance = BattlePassManager._internal();

  /// 레벨업에 필요한 BP — "100 BP당 1레벨업".
  static const int bpPerLevel = 100;

  static const int premiumUnlockCostGems = 3000;

  /// 몬스터 처치 시 BP를 얻을 확률과 그 획득량 — 정확한 밸런스 데이터가
  /// 없어 임의로 정한 값(다른 매니저의 `_averageHitsPerKill`류 상수와
  /// 같은 성격)이니, 기획 수치가 정해지면 이 두 상수만 바꾸면 된다.
  static const double monsterKillDropChance = 0.05;
  static const int monsterKillDropAmount = 5;

  /// 오프라인 방치 보상 수령 시 분당 BP 지급량 — [OfflineRewardManager
  /// .claimReward]가 방치 시간(분)에 곱해서 지급한다.
  static const double bpExpPerOfflineMinute = 1.0;

  /// 지금 진행 중인 시즌 — null이면 활성 시즌이 없다는 뜻으로, 이 경우
  /// [addBpExp]/[claimReward]/[unlockPremium]이 전부 조용히 아무 일도
  /// 하지 않는다(시즌이 없으면 배틀패스 자체가 존재하지 않는 것과 같다).
  BattlePassSeason? currentSeason;

  /// 로컬에 마지막으로 저장된 진행도가 어느 시즌 것이었는지 — [loadData]가
  /// 이 값과 [currentSeason]의 id가 다르면(시즌이 바뀌었으면) 진행도를
  /// 전부 초기화한 뒤 새 시즌 데이터를 받아온다.
  String? _localSeasonId;

  /// 누적 BP 경험치 — 레벨은 여기서 파생된다(별도로 증가/이월시키지
  /// 않는다, 순수 나눗셈이라 이월 버그가 날 여지가 없다). 시즌이 바뀌면
  /// [loadData]에서 0으로 초기화된다.
  int bpExp = 0;
  bool isPremium = false;

  final Set<int> _claimedFreeLevels = {};
  final Set<int> _claimedPremiumLevels = {};

  List<BattlePassRewardTier> _rewardTrack = const [];
  List<BattlePassRewardTier> get rewardTrack => _rewardTrack;

  /// 단위 테스트 전용 — 실제 시즌/보상 트랙/수령 이력을 네트워크 없이
  /// 직접 주입한다([PotionManager.debugSeedForTest]와 같은 관례). 저장/
  /// 서버 동기화는 건드리지 않는다.
  @visibleForTesting
  void debugSeedForTest({
    BattlePassSeason? season,
    List<BattlePassRewardTier>? rewardTrack,
    Set<int>? claimedFreeLevels,
    Set<int>? claimedPremiumLevels,
  }) {
    if (season != null) {
      currentSeason = season;
    }
    if (rewardTrack != null) {
      _rewardTrack = rewardTrack;
    }
    if (claimedFreeLevels != null) {
      _claimedFreeLevels
        ..clear()
        ..addAll(claimedFreeLevels);
    }
    if (claimedPremiumLevels != null) {
      _claimedPremiumLevels
        ..clear()
        ..addAll(claimedPremiumLevels);
    }
  }

  /// 현재 레벨(1부터 시작) — [bpPerLevel] BP마다 1레벨.
  int get level => 1 + (bpExp ~/ bpPerLevel);

  /// 지금 레벨 안에서의 진행률(0.0~1.0) — 상단 exp 바 표시용.
  double get levelProgressRatio => (bpExp % bpPerLevel) / bpPerLevel;

  bool hasClaimedFree(int level) => _claimedFreeLevels.contains(level);
  bool hasClaimedPremium(int level) => _claimedPremiumLevels.contains(level);

  /// [tierLevel]의 무료(또는 프리미엄) 보상을 지금 수령할 수 있는지 —
  /// 활성 시즌이 있고, 내가 그 레벨에 도달했고, 아직 안 받았고(프리미엄이면
  /// 패스 보유까지).
  bool canClaim(int tierLevel, {required bool premium}) {
    if (currentSeason == null || level < tierLevel) {
      return false;
    }
    if (premium) {
      return isPremium && !hasClaimedPremium(tierLevel);
    }
    return !hasClaimedFree(tierLevel);
  }

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 채운 뒤, 지금
  /// 기간에 걸쳐 있는 시즌을 찾아 그 시즌의 진행도로 갱신한다. 로컬에
  /// 남아있던 진행도가 지난 시즌 것이면(또는 처음 실행이면) 0으로
  /// 초기화한 뒤 이번 시즌 데이터를 받아온다.
  Future<void> loadData() async {
    await _loadLocal();

    final List<Map<String, dynamic>> seasonRows =
        await SupabaseManager.instance.fetchBattlePassSeasons();
    BattlePassSeason? activeSeason;
    for (final Map<String, dynamic> row in seasonRows) {
      try {
        final BattlePassSeason season = BattlePassSeason.fromJson(row);
        if (season.isActive) {
          activeSeason = season;
          break;
        }
      } catch (error) {
        debugPrint('[BattlePassManager] 시즌 행 파싱 실패(id=${row['id']}): $error');
      }
    }
    currentSeason = activeSeason;

    final List<Map<String, dynamic>> rewardRows =
        await SupabaseManager.instance.fetchBattlePassRewards();
    if (rewardRows.isNotEmpty) {
      _rewardTrack = rewardRows.map(BattlePassRewardTier.fromJson).toList();
    }

    if (activeSeason == null) {
      notifyListeners();
      return;
    }

    if (_localSeasonId != activeSeason.id) {
      // 로컬 캐시가 이전 시즌 것이었거나 아예 없었다 — 새 시즌은 항상
      // 0부터 시작한다(실제 시즌제 배틀패스의 표준 동작).
      bpExp = 0;
      isPremium = false;
      _claimedFreeLevels.clear();
      _claimedPremiumLevels.clear();
      _localSeasonId = activeSeason.id;
    }

    final Map<String, dynamic>? row =
        await SupabaseManager.instance.fetchUserBattlePass(seasonId: activeSeason.id);
    if (row != null) {
      bpExp = (row['bp_exp'] as num?)?.toInt() ?? bpExp;
      isPremium = row['is_premium'] as bool? ?? isPremium;
      final List<dynamic>? freeLevels = row['claimed_free_levels'] as List<dynamic>?;
      if (freeLevels != null) {
        _claimedFreeLevels
          ..clear()
          ..addAll(freeLevels.map((dynamic e) => (e as num).toInt()));
      }
      final List<dynamic>? premiumLevels = row['claimed_premium_levels'] as List<dynamic>?;
      if (premiumLevels != null) {
        _claimedPremiumLevels
          ..clear()
          ..addAll(premiumLevels.map((dynamic e) => (e as num).toInt()));
      }
    }

    await _saveLocal();
    notifyListeners();
  }

  /// 몬스터 처치([GameManager._onMonsterDefeated]의 저확률 드랍) /
  /// 오프라인 보상 수령([OfflineRewardManager.claimReward]) / 퀘스트 보상
  /// ([QuestManager.claimQuest])이 공유하는 BP 획득 진입점 — [amount]가
  /// 0 이하이거나 활성 시즌이 없으면 아무것도 바꾸지 않는다.
  Future<void> addBpExp(int amount) async {
    if (amount <= 0 || currentSeason == null) {
      return;
    }
    bpExp += amount;
    notifyListeners();
    await _saveLocal();
    _syncRemote();
  }

  /// [tierLevel]의 무료/프리미엄 보상 하나를 수령한다 — 조건 미충족이면
  /// 아무것도 바꾸지 않고 false.
  Future<bool> claimReward(int tierLevel, {required bool premium}) async {
    if (!canClaim(tierLevel, premium: premium)) {
      return false;
    }
    BattlePassRewardTier? tier;
    for (final BattlePassRewardTier candidate in _rewardTrack) {
      if (candidate.level == tierLevel) {
        tier = candidate;
        break;
      }
    }
    if (tier == null) {
      return false;
    }

    final String rewardType = premium ? tier.premiumRewardType : tier.freeRewardType;
    final int rewardAmount = premium ? tier.premiumRewardAmount : tier.freeRewardAmount;
    _applyReward(rewardType, rewardAmount);

    if (premium) {
      _claimedPremiumLevels.add(tierLevel);
    } else {
      _claimedFreeLevels.add(tierLevel);
    }
    notifyListeners();
    await _saveLocal();
    _syncRemote();
    return true;
  }

  void _applyReward(String rewardType, int amount) {
    switch (rewardType) {
      case 'gem':
        GameManager.instance.addGems(amount);
      case 'gold':
      case 'coin':
        GameManager.instance.addGold(amount);
      default:
        debugPrint('[BattlePassManager] 알 수 없는 보상 타입: $rewardType');
    }
  }

  /// 보석 [premiumUnlockCostGems]개를 소모해 이번 시즌 프리미엄 패스를
  /// 해금한다 — 활성 시즌이 없거나 이미 프리미엄이거나 보석이 부족하면
  /// false(재화도 차감되지 않음).
  Future<bool> unlockPremium() async {
    if (currentSeason == null || isPremium) {
      return false;
    }
    if (!GameManager.instance.spendGems(premiumUnlockCostGems)) {
      return false;
    }
    isPremium = true;
    notifyListeners();
    await _saveLocal();
    _syncRemote();
    return true;
  }

  void _syncRemote() {
    final String? seasonId = currentSeason?.id;
    if (seasonId == null) {
      return;
    }
    unawaited(
      SupabaseManager.instance.upsertUserBattlePass(
        seasonId: seasonId,
        bpExp: bpExp,
        isPremium: isPremium,
        claimedFreeLevels: _claimedFreeLevels.toList(),
        claimedPremiumLevels: _claimedPremiumLevels.toList(),
      ),
    );
  }

  static const String _saveKey = 'battle_pass_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode({
        'seasonId': _localSeasonId,
        'bpExp': bpExp,
        'isPremium': isPremium,
        'claimedFreeLevels': _claimedFreeLevels.toList(),
        'claimedPremiumLevels': _claimedPremiumLevels.toList(),
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
      _localSeasonId = data['seasonId'] as String?;
      bpExp = (data['bpExp'] as num?)?.toInt() ?? bpExp;
      isPremium = data['isPremium'] as bool? ?? isPremium;
      final List<dynamic>? freeLevels = data['claimedFreeLevels'] as List<dynamic>?;
      if (freeLevels != null) {
        _claimedFreeLevels
          ..clear()
          ..addAll(freeLevels.map((dynamic e) => (e as num).toInt()));
      }
      final List<dynamic>? premiumLevels = data['claimedPremiumLevels'] as List<dynamic>?;
      if (premiumLevels != null) {
        _claimedPremiumLevels
          ..clear()
          ..addAll(premiumLevels.map((dynamic e) => (e as num).toInt()));
      }
    } catch (error) {
      debugPrint('[BattlePassManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }
  }
}
