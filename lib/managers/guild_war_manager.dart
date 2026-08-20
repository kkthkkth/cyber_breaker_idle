import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/guild_war_model.dart';
import '../utils/time_util.dart';
import 'equipment_manager.dart';
import 'game_manager.dart';
import 'guild_manager.dart';
import 'supabase_manager.dart';

/// 길드 전쟁(GvG) + 세금 시스템을 관장하는 싱글턴 — 이 프로젝트의 다른
/// 공유 상태 매니저들([GuildRaidManager] 등)과 같은 관례를 따른다:
/// 설정([config])/세금 풀([taxPool])/전쟁 상태([myWar])는 전부 길드원 전체
/// 또는 서버 전체가 공유하는 상태라 로컬에 캐시하지 않고 항상 서버에서
/// 최신값을 받아온다.
///
/// 일정: 평일(월~금) 신청 → 토요일 21:00 매칭·전투 시작 → 일요일 자정
/// (=다음 주 월요일 00:00) 정산. 매칭/정산은 특정 배치 서버 없이, 그
/// 시점 이후 앱을 켜는 아무 클라이언트나 [refreshMyWar]/
/// [checkAndSettleIfDue]를 통해 RPC를 "찔러보는" 방식으로 트리거된다 —
/// RPC 자체가 서버 시계(now())로 시간 가드를 걸고 있어 이르게 호출되거나
/// 여러 명이 동시에 호출해도 안전하다([SupabaseManager.attackGuildBoss]류
/// RPC들과 같은 설계).
class GuildWarManager extends ChangeNotifier {
  GuildWarManager._internal();

  static final GuildWarManager instance = GuildWarManager._internal();

  GuildWarConfig config = GuildWarConfig.fallback;
  GlobalTaxPool taxPool = GlobalTaxPool.zero;
  GuildWar? myWar;

  bool isLoadingWar = false;

  /// 단위 테스트 전용 — 실제 네트워크 없이 상태를 직접 주입한다.
  @visibleForTesting
  void debugSeedForTest({GuildWarConfig? config, GlobalTaxPool? taxPool, GuildWar? myWar}) {
    if (config != null) {
      this.config = config;
    }
    if (taxPool != null) {
      this.taxPool = taxPool;
    }
    if (myWar != null) {
      this.myWar = myWar;
    }
  }

  /// main()이 앱 시작 시 한 번 호출 — 로그인 여부와 무관한 공개 설정/세금
  /// 풀만 미리 받아 둔다(길드 전쟁 상태 자체는 길드 화면에 들어갈 때
  /// [refreshMyWar]가 받아온다).
  Future<void> loadData() async {
    await refreshConfig();
    await refreshTaxPool();
  }

  Future<void> refreshConfig() async {
    final Map<String, dynamic>? row = await SupabaseManager.instance.fetchGuildWarConfig();
    if (row != null) {
      config = GuildWarConfig.fromJson(row);
      notifyListeners();
    }
  }

  Future<void> refreshTaxPool() async {
    final Map<String, dynamic>? row = await SupabaseManager.instance.fetchGlobalTaxPool();
    if (row != null) {
      taxPool = GlobalTaxPool.fromJson(row);
      notifyListeners();
    }
  }

  /// 가챠/요일 던전에서 재화를 실제로 소모한 직후 호출한다 — 로컬
  /// [taxPool]을 낙관적으로(대략치) 먼저 올려 화면이 즉시 반응하게 하고,
  /// 실제 정확한 값은 서버 RPC가 원자적으로 계산해 누적한다(다음
  /// [refreshTaxPool] 때 정확한 값으로 맞춰진다). 실패해도(오프라인 등)
  /// 이미 끝난 재화 차감 자체엔 영향이 없다.
  void reportTaxableSpend({int coinSpent = 0, int gemSpent = 0}) {
    if (coinSpent <= 0 && gemSpent <= 0) {
      return;
    }
    taxPool = GlobalTaxPool(
      coinPool: taxPool.coinPool + (coinSpent * config.taxRate).floor(),
      gemPool: taxPool.gemPool + (gemSpent * config.taxRate).floor(),
    );
    notifyListeners();
    unawaited(
      SupabaseManager.instance.accrueGlobalTax(coinSpent: coinSpent, gemSpent: gemSpent),
    );
  }

  /// [DateTime]이 속한 주(월요일 시작)를 키로 — [QuestManager]의 주간
  /// 퀘스트 리셋 커서와 같은 형식(그 주 월요일 `yyyy-MM-dd`)을 그대로
  /// 재사용해, 별도의 ISO 주차 계산 없이도 "같은 주"를 일관되게 식별한다.
  static String weekKeyOf(DateTime date) {
    final DateTime monday = date.subtract(Duration(days: date.weekday - 1));
    final String month = monday.month.toString().padLeft(2, '0');
    final String day = monday.day.toString().padLeft(2, '0');
    return 'week_${monday.year}-$month-$day';
  }

  /// 길드 전쟁 탭에 들어설 때마다 호출 — 이번 주 내 길드의 전쟁 상태를
  /// 받아오고, 토요일 21:00이 지났는데 아직 매칭 전이면 매칭 RPC도 함께
  /// 찔러본다(매칭 RPC 자체가 서버 시간으로 한 번 더 가드하므로 이르게
  /// 호출해도 안전 — [SupabaseManager.triggerMatchGuildWars] 문서 참고).
  Future<void> refreshMyWar() async {
    final String? guildId = GuildManager.instance.guildId;
    if (guildId == null) {
      return;
    }
    isLoadingWar = true;
    notifyListeners();

    final DateTime now = await getNetworkTime();
    final String weekKey = weekKeyOf(now);

    await SupabaseManager.instance.triggerMatchGuildWars(weekKey);

    final Map<String, dynamic>? row = await SupabaseManager.instance.fetchMyGuildWar(
      guildId: guildId,
      weekKey: weekKey,
    );
    myWar = row != null ? GuildWar.fromJson(row) : null;

    isLoadingWar = false;
    notifyListeners();
  }

  /// 이번 주 전쟁에 신청한다 — 신청 직전 내 전투력을 서버에 동기화해서
  /// 토요일 매칭 공식이 최대한 최신 값을 쓰게 한다. 이미 신청했으면
  /// (서버가 중복 무시) 그냥 현재 상태를 다시 받아온다.
  ///
  /// [주의] 예전엔 이 자리에서 `(attackPower + defensePower).round()`라는
  /// 길드 전쟁 전용 임시 공식으로 `profiles.combat_power`를 채웠다 —
  /// 이제 명예의 전당 [전투력] 랭킹도 같은 컬럼을 읽으므로(GameManager
  /// ._syncCombatPowerIfChanged 참고), 두 기능이 같은 컬럼에 서로 다른
  /// 공식을 계속 쓰면 어느 쪽이 마지막에 썼는지에 따라 값이 오락가락한다.
  /// 그래서 이제 [GameManager.totalCombatPower](가중치까지 반영된 정식
  /// 전투력 공식)로 통일했다 — 길드 전쟁 매칭 결과가 예전 공식과 달라질
  /// 수 있다는 점은 감안해야 한다.
  Future<bool> applyForWar() async {
    final String? guildId = GuildManager.instance.guildId;
    if (guildId == null) {
      return false;
    }
    unawaited(SupabaseManager.instance.updateCombatPower(GameManager.instance.totalCombatPower));

    final DateTime now = await getNetworkTime();
    final String weekKey = weekKeyOf(now);
    final bool success = await SupabaseManager.instance.applyForGuildWar(
      guildId: guildId,
      weekKey: weekKey,
    );
    if (success) {
      await refreshMyWar();
    }
    return success;
  }

  /// 전투 종료 시점에 이번 도전에서 누적한 총 데미지([totalDamage])를
  /// 서버에 한 번에 제출한다 — [GuildRaidManager.submitDamage]와 동일한
  /// 패턴. 실패(오프라인 등)하면 null.
  Future<GuildWarAttackResult?> submitDamage(int totalDamage) async {
    final GuildWar? war = myWar;
    if (war == null || totalDamage <= 0) {
      return null;
    }
    final GuildWarAttackResult? result = await SupabaseManager.instance.attackGuildWarBase(
      warId: war.id,
      damage: totalDamage,
    );
    if (result == null) {
      return null;
    }
    myWar = GuildWar(
      id: war.id,
      weekKey: war.weekKey,
      guildId: war.guildId,
      opponentGuildId: war.opponentGuildId,
      baseMaxHp: war.baseMaxHp,
      baseCurrentHp: result.newCurrentHp,
      baseDefense: war.baseDefense,
      status: result.baseDestroyed ? GuildWarStatus.destroyed : war.status,
      result: war.result,
    );
    notifyListeners();
    return result;
  }

  /// [MidnightResetManager]가 매 자정 호출 — 월요일(=일요일 자정이 막
  /// 지난 시점)에만 실제로 정산 RPC를 찔러본다. 정산이 실제로 일어났으면
  /// (길드가 이번 주 전쟁에 참여했다면) 길드 금고/휘장을 반영한다.
  Future<void> checkAndSettleIfDue() async {
    final DateTime now = await getNetworkTime();
    if (now.weekday != DateTime.monday) {
      return;
    }
    // 지난 주(막 끝난 그 주)의 전쟁을 정산한다 — 지금은 이미 새 주
    // (월요일)로 넘어왔으므로 weekKeyOf(now)가 아니라 하루 전 기준으로
    // 계산해야 "방금 끝난" 그 주를 가리킨다.
    final String lastWeekKey = weekKeyOf(now.subtract(const Duration(days: 1)));
    await SupabaseManager.instance.triggerSettleGuildWars(lastWeekKey);

    await refreshTaxPool();
    await _materializeBadgeIfGranted(now);
    EquipmentManager.instance.removeExpiredBadge(now);
    if (GuildManager.instance.isInGuild) {
      await GuildManager.instance.refreshGuild();
    }
  }

  /// 서버 지급 기록([SupabaseManager.fetchMyActiveWarBadge])이 있는데 아직
  /// 로컬 인벤토리에 반영되지 않았으면(예: 정산 직후 첫 접속, 또는 다른
  /// 기기에서 이미 받은 휘장) 로컬에 구현(materialize)한다 — "서버가
  /// 신호만 주고 클라이언트가 로컬 인벤토리를 실제로 채운다"는 이 프로젝트
  /// 전반의 서버-그랜트 관례([MailboxManager] 등)와 동일하다. [now]는
  /// 반드시 NTP로 받아온 시간이어야 한다([SupabaseManager
  /// .fetchMyActiveWarBadge] 문서 참고).
  Future<void> _materializeBadgeIfGranted(DateTime now) async {
    final Map<String, dynamic>? row = await SupabaseManager.instance.fetchMyActiveWarBadge(now);
    if (row == null) {
      return;
    }
    final String? expiresAtRaw = row['expires_at'] as String?;
    final DateTime? expiresAt = expiresAtRaw == null ? null : DateTime.tryParse(expiresAtRaw);
    if (expiresAt == null) {
      return;
    }
    final DateTime? currentExpiry = EquipmentManager.instance.equippedBadge?.expiresAt;
    if (currentExpiry != null && !currentExpiry.isBefore(expiresAt)) {
      return; // 이미 같거나 더 늦게 만료되는 휘장을 갖고 있음 — 다시 지급할 필요 없음.
    }
    EquipmentManager.instance.grantWarBadge(expiresAt: expiresAt.toLocal());
  }

  /// main()이 앱 시작 시 한 번(로그인 이후) 호출 — 콜드 스타트에서도 지난
  /// 정산으로 받은 휘장/만료를 즉시 반영한다([checkAndSettleIfDue]와
  /// 별개로, 자정 타이머를 기다리지 않고 시작 시점에 한 번 더 확인).
  Future<void> syncBadgeOnStartup() async {
    final DateTime now = await getNetworkTime();
    await _materializeBadgeIfGranted(now);
    EquipmentManager.instance.removeExpiredBadge(now);
  }

  /// 지금 유효한(만료되지 않은) 휘장이 있을 때만 [GuildWarConfig
  /// .badgeBuffGoldRate]를, 없으면 0을 돌려준다 — [GameManager
  /// .goldRewardForKill]이 곱산 체인에 그대로 더한다.
  double get badgeGoldRateBonus {
    final currentBadge = EquipmentManager.instance.equippedBadge;
    if (currentBadge == null || currentBadge.isExpired) {
      return 0;
    }
    return config.badgeBuffGoldRate;
  }

  /// [badgeGoldRateBonus]와 같은 조건 — [GameManager
  /// .effectiveCriticalMultiplier]가 더한다.
  double get badgeCritDamageBonus {
    final currentBadge = EquipmentManager.instance.equippedBadge;
    if (currentBadge == null || currentBadge.isExpired) {
      return 0;
    }
    return config.badgeBuffCritDmg;
  }

  /// 길드장 전용 — 길드 금고에서 [targetUserId] 개인 재화로
  /// [coinAmount]/[gemAmount]를 옮긴다(전리품 분배). 성공하면 길드 정보를
  /// 다시 받아와 금고 잔액을 즉시 갱신한다.
  Future<bool> transferTreasury({
    required String targetUserId,
    required int coinAmount,
    required int gemAmount,
  }) async {
    final String? guildId = GuildManager.instance.guildId;
    if (guildId == null) {
      return false;
    }
    final bool success = await SupabaseManager.instance.transferGuildTreasury(
      guildId: guildId,
      targetUserId: targetUserId,
      coinAmount: coinAmount,
      gemAmount: gemAmount,
    );
    if (success) {
      await GuildManager.instance.refreshGuild();
    }
    return success;
  }
}
