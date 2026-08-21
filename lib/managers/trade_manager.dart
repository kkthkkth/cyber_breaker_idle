import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/equipment.dart';
import '../models/trade_model.dart';
import 'equipment_manager.dart';
import 'supabase_manager.dart';

/// 1:1 아이템 거래를 관장하는 싱글턴 — **실제 아이템 이전은 이 클래스가
/// 직접 하지 않는다.** 요청/세션 상태(누가 무엇을 올렸는지, 잠금 여부)만
/// 다루고, 소유권을 실제로 바꾸는 유일한 지점은
/// [SupabaseManager.executeTrade]가 부르는 `execute_trade` Postgres RPC
/// (트랜잭션 + 행 잠금 + 이중 검증, `supabase/trade_reference.sql`)다 —
/// 클라이언트가 각자 REST 호출을 순서대로 보내는 방식으로는 두 클라이언트
/// 가 동시에 확정 버튼을 눌렀을 때 레이스로 아이템이 복제/증발할 수
/// 있어서, 그 경로 자체를 아예 만들지 않았다.
///
/// 세션 동기화는 [GuildChatManager]와 같은 Realtime 구독 관례를 따르되,
/// 더 단순화했다 — `trade_items`의 Realtime payload에는
/// `user_equipment` 조인 결과(표시용 아이템 정보)가 없으므로, 변경이
/// 생길 때마다 payload를 직접 patch하는 대신 세션 전체를
/// [_refreshSession]으로 다시 불러온다(거래는 사람 속도로 일어나는
/// 행동이라 왕복 한 번 더 도는 비용이 무시할 만하다).
class TradeManager extends ChangeNotifier {
  TradeManager._internal();

  static final TradeManager instance = TradeManager._internal();

  static const int maxDailyTrades = 3;

  bool allowTrade = false;
  int tradeCountToday = 0;

  List<TradeSession> incomingRequests = const [];

  TradeSession? currentSession;
  List<TradeItemEntry> currentItems = const [];

  RealtimeChannel? _sessionChannel;
  RealtimeChannel? _requestChannel;

  /// [보안 감사 2026-08-21] [requestTrade]는 대상의 `allow_trade`를
  /// 서버에 물어본 뒤(비동기 왕복) 요청 행을 만든다 — 그 왕복 사이에
  /// 같은 상대에게 연속으로 두 번 탭하면(친구/길드원 목록 타일의
  /// InkWell은 자체 잠금이 없다) 두 호출 모두 검사를 통과해 pending
  /// 거래 행이 중복 생길 수 있었다. 진행 중인 대상 id를 여기 모아
  /// 두고, 같은 대상에게 이미 요청이 나가 있는 동안은 새 호출을
  /// 조용히 막는다.
  final Set<String> _pendingRequestTargetIds = {};

  /// [_MainNavigationScreenState]가 새 거래 요청을 받았을 때 알림(토스트 등)
  /// 을 띄우기 위한 콜백 — [GameManager.onChapterAdvanced]와 같은 관례.
  void Function(TradeSession request)? onIncomingTradeRequest;

  bool get canRequestTrade => allowTrade && tradeCountToday < maxDailyTrades;

  /// main()이 앱 시작 시 한 번 호출 — 거래 허용 여부/오늘 거래 횟수/받은
  /// 요청을 불러오고, 앱이 켜져 있는 동안 계속 살아있는 전역 구독을
  /// 시작한다(길드 채팅과 달리 특정 화면에 들어가야만 알림을 받는 게
  /// 아니라, 어느 화면에 있든 거래 요청을 받을 수 있어야 하기 때문).
  Future<void> loadData() async {
    final String? userId = SupabaseManager.instance.currentUserId;
    if (userId == null) {
      return;
    }
    allowTrade = await SupabaseManager.instance.fetchAllowTrade(userId);
    tradeCountToday = await SupabaseManager.instance.fetchTradeCountToday();
    final List<Map<String, dynamic>> rows =
        await SupabaseManager.instance.fetchIncomingTradeRequests();
    incomingRequests = rows.map(TradeSession.fromJson).toList();
    notifyListeners();

    _requestChannel = SupabaseManager.instance.subscribeToIncomingTradeRequests(userId, (row) {
      final TradeSession request = TradeSession.fromJson(row);
      if (incomingRequests.any((existing) => existing.id == request.id)) {
        return;
      }
      incomingRequests = [...incomingRequests, request];
      notifyListeners();
      onIncomingTradeRequest?.call(request);
    });
  }

  Future<void> setAllowTrade(bool value) async {
    allowTrade = value;
    notifyListeners();
    await SupabaseManager.instance.updateAllowTrade(value);
  }

  /// 앱 종료/테스트 정리용 — [_requestChannel]은 앱이 살아있는 동안은
  /// 계속 열려 있어야 하므로([loadData] 문서 참고) 보통 호출할 필요는
  /// 없다([SupabaseManager.stopLastSeenHeartbeat]과 같은 관례).
  Future<void> stopListeningForRequests() async {
    final RealtimeChannel? channel = _requestChannel;
    if (channel != null) {
      await SupabaseManager.instance.unsubscribeChannel(channel);
    }
    _requestChannel = null;
  }

  /// [targetUserId]에게 거래를 요청한다 — 나/상대 둘 다 거래를 허용
  /// 중이고 내 오늘 거래 횟수가 [maxDailyTrades] 미만일 때만 실제로
  /// 요청 행을 만든다. 실패 사유를 구분해 돌려줘서 호출부(UI)가 구체적인
  /// 안내를 보여줄 수 있게 하고, 성공하면 방금 만든 거래의 [tradeId]도
  /// 함께 돌려준다(대기 팝업이 그 id로 곧장 구독을 시작할 수 있도록 —
  /// "방금 보낸 요청"을 다시 조회할 방법이 없어 여기서 직접 전달해야
  /// 한다).
  Future<({TradeRequestResult result, String? tradeId})> requestTrade(String targetUserId) async {
    if (_pendingRequestTargetIds.contains(targetUserId)) {
      return (result: TradeRequestResult.failed, tradeId: null);
    }
    if (!allowTrade) {
      return (result: TradeRequestResult.myTradeDisabled, tradeId: null);
    }
    if (tradeCountToday >= maxDailyTrades) {
      return (result: TradeRequestResult.dailyLimitReached, tradeId: null);
    }
    _pendingRequestTargetIds.add(targetUserId);
    try {
      final bool targetAllows = await SupabaseManager.instance.fetchAllowTrade(targetUserId);
      if (!targetAllows) {
        return (result: TradeRequestResult.targetTradeDisabled, tradeId: null);
      }
      final Map<String, dynamic>? row =
          await SupabaseManager.instance.createTradeRequest(targetUserId);
      if (row == null) {
        return (result: TradeRequestResult.failed, tradeId: null);
      }
      return (result: TradeRequestResult.success, tradeId: row['id'].toString());
    } finally {
      _pendingRequestTargetIds.remove(targetUserId);
    }
  }

  Future<bool> acceptRequest(TradeSession request) async {
    final bool success =
        await SupabaseManager.instance.updateTradeStatus(request.id, TradeStatus.active);
    if (success) {
      incomingRequests = incomingRequests.where((existing) => existing.id != request.id).toList();
      notifyListeners();
    }
    return success;
  }

  Future<void> declineRequest(TradeSession request) async {
    await SupabaseManager.instance.updateTradeStatus(request.id, TradeStatus.cancelled);
    incomingRequests = incomingRequests.where((existing) => existing.id != request.id).toList();
    notifyListeners();
  }

  /// [TradeScreen]이 열릴 때 호출 — 세션 상태를 불러오고 실시간 구독을
  /// 시작한다.
  Future<void> openSession(String tradeId) async {
    await _closeSessionChannel();
    await _refreshSession(tradeId);
    _sessionChannel = SupabaseManager.instance.subscribeToTradeSession(
      tradeId,
      () => unawaited(_refreshSession(tradeId)),
    );
  }

  /// [TradeScreen]이 dispose될 때 호출 — 구독만 정리하고 세션 자체를
  /// 취소하지는 않는다(화면을 잠깐 나갔다 돌아올 수도 있으므로).
  Future<void> closeSession() async {
    await _closeSessionChannel();
    currentSession = null;
    currentItems = const [];
  }

  Future<void> _closeSessionChannel() async {
    final RealtimeChannel? channel = _sessionChannel;
    if (channel != null) {
      await SupabaseManager.instance.unsubscribeChannel(channel);
    }
    _sessionChannel = null;
  }

  Future<void> _refreshSession(String tradeId) async {
    final Map<String, dynamic>? row = await SupabaseManager.instance.fetchTradeSession(tradeId);
    if (row == null) {
      return;
    }
    currentSession = TradeSession.fromJson(row);
    final List<Map<String, dynamic>> itemRows =
        await SupabaseManager.instance.fetchTradeItems(tradeId);
    // [보안 감사 2026-08-21] 이 메서드는 Realtime 콜백(다른 유저가 자기
    // 쪽 trade_items를 바꿀 때마다)에서도 호출된다 — [TradeItemEntry
    // .fromJson] 자체는 내부 [Equipment.fromJson] 파싱을 이미
    // try/catch로 감쌌지만, id/trade_id/owner_user_id 같은 행 필드는
    // 여전히 non-null 캐스트다. 행 하나가 예상 밖 모양이어도(스키마
    // 드리프트 등) 그 아이템만 건너뛰고 나머지 거래 화면은 계속
    // 살아있도록, 목록 전체를 한 번에 `.map()`하는 대신 항목별로
    // try/catch한다([EquipmentManager._restorePetsFromRemote]와 같은
    // 관례).
    final List<TradeItemEntry> parsed = [];
    for (final Map<String, dynamic> itemRow in itemRows) {
      try {
        parsed.add(TradeItemEntry.fromJson(itemRow));
      } catch (error) {
        debugPrint('[TradeManager] 거래 아이템 파싱 실패, 건너뜀: $error');
      }
    }
    currentItems = parsed;
    notifyListeners();
  }

  /// [item]을 거래창에 올린다 — 장착 중이거나(들고 있는 무기를 빼서 주는
  /// 건 진행 중인 전투 상태를 깨뜨린다) 등급/타입 제한([isItemTradeable])
  /// 에 걸리면 false. 성공하면 2단 잠금 요구사항대로 내 잠금을 즉시
  /// 해제한다(이미 잠긴 상태에서 아이템을 바꿨다는 뜻이므로).
  Future<bool> addItem(Equipment item) async {
    final TradeSession? session = currentSession;
    final String? myId = SupabaseManager.instance.currentUserId;
    if (session == null || myId == null) {
      return false;
    }
    if (item.isEquipped || !isItemTradeable(item)) {
      return false;
    }
    if (session.isLockedBy(myId)) {
      await setLocked(false);
    }
    final bool success =
        await SupabaseManager.instance.addTradeItem(tradeId: session.id, equipmentId: item.id);
    if (success) {
      await _refreshSession(session.id);
    }
    return success;
  }

  Future<bool> removeItem(TradeItemEntry entry) async {
    final TradeSession? session = currentSession;
    final String? myId = SupabaseManager.instance.currentUserId;
    if (session == null || myId == null) {
      return false;
    }
    if (session.isLockedBy(myId)) {
      await setLocked(false);
    }
    final bool success = await SupabaseManager.instance.removeTradeItem(entry.id);
    if (success) {
      await _refreshSession(session.id);
    }
    return success;
  }

  Future<void> setLocked(bool locked) async {
    final TradeSession? session = currentSession;
    final String? myId = SupabaseManager.instance.currentUserId;
    if (session == null || myId == null) {
      return;
    }
    final bool isUserA = session.userA == myId;
    await SupabaseManager.instance.updateTradeLock(session.id, isUserA: isUserA, locked: locked);
    // Realtime 구독이 곧 currentSession을 다시 불러오지만, 버튼 상태가
    // 왕복 지연 없이 즉시 바뀌도록 낙관적으로 먼저 반영한다.
    currentSession = TradeSession(
      id: session.id,
      userA: session.userA,
      userB: session.userB,
      status: session.status,
      lockedA: isUserA ? locked : session.lockedA,
      lockedB: isUserA ? session.lockedB : locked,
    );
    notifyListeners();
  }

  /// 둘 다 잠긴 뒤에만 호출 가능 — 실제 이전은
  /// [SupabaseManager.executeTrade](execute_trade RPC)가 전담한다.
  /// 성공하면 이미 받아 둔 [currentItems](서버가 확정한 최종 상태)를
  /// 그대로 로컬 인벤토리에 반영한다 — 재조회 없이 곧바로 "내가 준
  /// 아이템은 빼고 받은 아이템은 더하기"만 하면 되므로 안전하다(서버가
  /// 이미 확정한 뒤이기 때문).
  Future<bool> confirmTrade() async {
    final TradeSession? session = currentSession;
    if (session == null || !session.bothLocked) {
      return false;
    }
    final bool success = await SupabaseManager.instance.executeTrade(session.id);
    if (success) {
      tradeCountToday += 1;
      _applyResultToLocalInventory();
      await closeSession();
    }
    return success;
  }

  void _applyResultToLocalInventory() {
    final String? myId = SupabaseManager.instance.currentUserId;
    if (myId == null) {
      return;
    }
    final EquipmentManager equipment = EquipmentManager.instance;
    for (final TradeItemEntry entry in currentItems) {
      final Equipment? item = entry.item;
      if (item == null) {
        continue;
      }
      if (entry.ownerUserId == myId) {
        // 내가 준 아이템 — 로컬 인벤토리에서 제거.
        equipment.inventory.removeWhere((existing) => existing.id == entry.equipmentId);
      } else if (!equipment.inventory.any((existing) => existing.id == entry.equipmentId)) {
        // 상대가 준 아이템(=내가 받음) — 아직 없으면 추가.
        equipment.inventory.add(item);
      }
    }
    equipment.notifyListeners();
    unawaited(equipment.saveEquipment());
  }

  Future<void> cancelTrade() async {
    final TradeSession? session = currentSession;
    if (session == null) {
      return;
    }
    await SupabaseManager.instance.updateTradeStatus(session.id, TradeStatus.cancelled);
    await closeSession();
  }
}
