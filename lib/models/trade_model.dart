import 'equipment.dart';

/// `trades.status` 값 — 거래 세션의 생애주기.
class TradeStatus {
  const TradeStatus._();

  /// 요청을 보냈지만 상대가 아직 수락/거절하지 않음.
  static const String pending = 'pending';

  /// 상대가 수락 — 양쪽 다 [TradeScreen]에서 아이템을 올리고 잠글 수 있다.
  static const String active = 'active';

  /// [execute_trade] RPC가 성공적으로 아이템을 이전함.
  static const String completed = 'completed';

  /// 요청이 거절되었거나, 세션 중 어느 한쪽이 취소함.
  static const String cancelled = 'cancelled';
}

/// `trades` 테이블 한 행 — 거래 요청/세션 하나.
class TradeSession {
  const TradeSession({
    required this.id,
    required this.userA,
    required this.userB,
    required this.status,
    required this.lockedA,
    required this.lockedB,
  });

  final String id;

  /// 요청을 보낸 쪽.
  final String userA;

  /// 요청을 받은 쪽.
  final String userB;

  final String status;
  final bool lockedA;
  final bool lockedB;

  /// [myUserId] 기준으로 상대방의 id.
  String otherUserId(String myUserId) => userA == myUserId ? userB : userA;

  /// [myUserId] 기준으로 내가 지금 잠금 상태인지.
  bool isLockedBy(String myUserId) => myUserId == userA ? lockedA : lockedB;

  /// [myUserId] 기준으로 상대가 지금 잠금 상태인지.
  bool isLockedByOther(String myUserId) => myUserId == userA ? lockedB : lockedA;

  bool get bothLocked => lockedA && lockedB;

  factory TradeSession.fromJson(Map<String, dynamic> json) => TradeSession(
    id: json['id'].toString(),
    userA: json['user_a'] as String,
    userB: json['user_b'] as String,
    status: json['status'] as String? ?? TradeStatus.pending,
    lockedA: json['locked_a'] as bool? ?? false,
    lockedB: json['locked_b'] as bool? ?? false,
  );
}

/// `trade_items` 테이블 한 행 + 표시용으로 곁들인 [item] 스냅샷 —
/// [TradeManager]가 `user_equipment.data`(또는 내 소유면 로컬 인벤토리)
/// 에서 채운다.
class TradeItemEntry {
  const TradeItemEntry({
    required this.id,
    required this.tradeId,
    required this.ownerUserId,
    required this.equipmentId,
    this.item,
  });

  final String id;
  final String tradeId;
  final String ownerUserId;
  final String equipmentId;

  /// 표시용 아이템 정보 — 못 구했으면(예: 원본이 이미 삭제됨) null,
  /// [TradeScreen]이 회색 placeholder로 대체한다.
  final Equipment? item;

  factory TradeItemEntry.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? embeddedEquipment =
        json['user_equipment'] as Map<String, dynamic>?;
    final Map<String, dynamic>? data = embeddedEquipment?['data'] as Map<String, dynamic>?;
    return TradeItemEntry(
      id: json['id'].toString(),
      tradeId: json['trade_id'].toString(),
      ownerUserId: json['owner_user_id'] as String,
      equipmentId: json['equipment_id'].toString(),
      item: data == null ? null : Equipment.fromJson(data),
    );
  }
}

/// [TradeManager.requestTrade]의 결과 — UI가 실패 사유를 구체적으로
/// 안내할 수 있게 세분화한다.
enum TradeRequestResult {
  success,
  myTradeDisabled,
  targetTradeDisabled,
  dailyLimitReached,
  failed,
}

/// 거래창에 올릴 수 없는 등급 — 요구사항: "최고 등급 장비는 거래 창에
/// 올릴 수 없도록". [execute_trade] RPC가 서버에서 다시 한번 같은 규칙을
/// 검증하므로(이중 검증), 이 목록을 바꾸면 RPC의 SQL도 함께 맞춰야 한다.
const Set<ItemGrade> untradeableGrades = {ItemGrade.ssr, ItemGrade.sssr, ItemGrade.ur};

/// [item]이 거래창에 올릴 수 있는지 — 등급 제한 + 보석 등 유료 재화가
/// 아예 [Equipment]로 표현되지 않는다는 점(재화는 GameManager.gold/gems
/// 정수 필드라 애초에 인벤토리에 없다)을 함께 반영한다. 캐릭터/휘장도
/// 거래 대상에서 제외한다(휘장은 기간제 비매너 재화, 캐릭터는 계정
/// 진행의 핵심 자원이라 요구사항 범위 밖으로 보수적으로 막는다).
bool isItemTradeable(Equipment item) {
  if (untradeableGrades.contains(item.grade)) {
    return false;
  }
  return item.type != EquipType.badge && item.type != EquipType.character;
}
