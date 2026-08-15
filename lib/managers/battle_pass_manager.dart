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

  /// 누적 BP 경험치 — 레벨은 여기서 파생된다(별도로 증가/이월시키지
  /// 않는다, 순수 나눗셈이라 이월 버그가 날 여지가 없다).
  int bpExp = 0;
  bool isPremium = false;

  final Set<int> _claimedFreeLevels = {};
  final Set<int> _claimedPremiumLevels = {};

  List<BattlePassRewardTier> _rewardTrack = const [];
  List<BattlePassRewardTier> get rewardTrack => _rewardTrack;

  /// 단위 테스트 전용 — 실제 보상 트랙/수령 이력을 네트워크 없이 직접
  /// 주입한다([PotionManager.debugSeedForTest]와 같은 관례). 저장/서버
  /// 동기화는 건드리지 않는다.
  @visibleForTesting
  void debugSeedForTest({
    List<BattlePassRewardTier>? rewardTrack,
    Set<int>? claimedFreeLevels,
    Set<int>? claimedPremiumLevels,
  }) {
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
  /// 내가 그 레벨에 도달했고, 아직 안 받았고(프리미엄이면 패스 보유까지).
  bool canClaim(int tierLevel, {required bool premium}) {
    if (level < tierLevel) {
      return false;
    }
    if (premium) {
      return isPremium && !hasClaimedPremium(tierLevel);
    }
    return !hasClaimedFree(tierLevel);
  }

  /// main()이 앱 시작 시 한 번 호출.
  Future<void> loadData() async {
    await _loadLocal();

    final List<Map<String, dynamic>> rewardRows =
        await SupabaseManager.instance.fetchBattlePassRewards();
    if (rewardRows.isNotEmpty) {
      _rewardTrack = rewardRows.map(BattlePassRewardTier.fromJson).toList();
    }

    final Map<String, dynamic>? row = await SupabaseManager.instance.fetchUserBattlePass();
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

  /// [QuestManager.claimQuest]가 퀘스트 보상을 지급할 때 부르는 진입점 —
  /// [amount]가 0 이하면 아무것도 바꾸지 않는다.
  Future<void> addBpExp(int amount) async {
    if (amount <= 0) {
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

  /// 보석 [premiumUnlockCostGems]개를 소모해 프리미엄 패스를 해금한다 —
  /// 이미 프리미엄이거나 보석이 부족하면 false(재화도 차감되지 않음).
  Future<bool> unlockPremium() async {
    if (isPremium) {
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
    unawaited(
      SupabaseManager.instance.upsertUserBattlePass(
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
    final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
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
  }
}
