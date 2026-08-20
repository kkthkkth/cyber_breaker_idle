import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../managers/equipment_manager.dart';
import '../managers/supabase_manager.dart';
import '../managers/trade_manager.dart';
import '../models/equipment.dart';
import '../models/trade_model.dart';
import '../widgets/center_toast.dart';

/// 친구/길드원 목록 등 어디서든 공유하는 거래 요청 진입점 — 결과에 따라
/// 대기 팝업을 띄우거나([TradeRequestResult.success]) 구체적인 실패
/// 사유를 토스트로 보여준다.
Future<void> requestTradeWith(
  BuildContext context, {
  required String userId,
  required String nickname,
}) async {
  final ({TradeRequestResult result, String? tradeId}) outcome =
      await TradeManager.instance.requestTrade(userId);
  if (!context.mounted) {
    return;
  }
  switch (outcome.result) {
    case TradeRequestResult.success:
      final String? tradeId = outcome.tradeId;
      if (tradeId == null) {
        showCenterToast(context, '$nickname님에게 거래 요청을 보냈습니다.');
        return;
      }
      await showTradeRequestWaitingDialog(
        context,
        tradeId: tradeId,
        otherUserId: userId,
        otherNickname: nickname,
      );
    case TradeRequestResult.myTradeDisabled:
      showCenterToast(context, '설정에서 [거래 허용]을 먼저 켜주세요.');
    case TradeRequestResult.targetTradeDisabled:
      showCenterToast(context, '$nickname님은 거래를 허용하지 않았습니다.');
    case TradeRequestResult.dailyLimitReached:
      showCenterToast(context, '오늘의 거래 횟수(${TradeManager.maxDailyTrades}회)를 모두 사용했습니다.');
    case TradeRequestResult.failed:
      showCenterToast(context, '거래 요청에 실패했습니다.');
  }
}

/// 거래 요청을 보낸 뒤 상대 응답을 기다리는 팝업 — [TradeManager
/// .subscribeToTradeSession]과 같은 Realtime 채널을 재사용해, 상대가
/// 수락하면(status→active) 자동으로 [TradeScreen]으로 넘어가고, 거절/취소
/// 하면(status→cancelled) 안내 후 닫힌다.
Future<void> showTradeRequestWaitingDialog(
  BuildContext context, {
  required String tradeId,
  required String otherUserId,
  required String otherNickname,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _TradeRequestWaitingDialog(
      tradeId: tradeId,
      otherUserId: otherUserId,
      otherNickname: otherNickname,
    ),
  );
}

class _TradeRequestWaitingDialog extends StatefulWidget {
  const _TradeRequestWaitingDialog({
    required this.tradeId,
    required this.otherUserId,
    required this.otherNickname,
  });

  final String tradeId;
  final String otherUserId;
  final String otherNickname;

  @override
  State<_TradeRequestWaitingDialog> createState() => _TradeRequestWaitingDialogState();
}

class _TradeRequestWaitingDialogState extends State<_TradeRequestWaitingDialog> {
  RealtimeChannel? _channel;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _channel = SupabaseManager.instance.subscribeToTradeSession(widget.tradeId, _onChange);
  }

  Future<void> _onChange() async {
    if (_resolved || !mounted) {
      return;
    }
    final Map<String, dynamic>? row =
        await SupabaseManager.instance.fetchTradeSession(widget.tradeId);
    final String? status = row?['status'] as String?;
    if (status == TradeStatus.active) {
      _resolved = true;
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TradeScreen(
            tradeId: widget.tradeId,
            otherUserId: widget.otherUserId,
            otherNickname: widget.otherNickname,
          ),
        ),
      );
    } else if (status == TradeStatus.cancelled) {
      _resolved = true;
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      showCenterToast(context, '${widget.otherNickname}님이 거래 요청을 거절했습니다.');
    }
  }

  @override
  void dispose() {
    final RealtimeChannel? channel = _channel;
    if (channel != null) {
      SupabaseManager.instance.unsubscribeChannel(channel);
    }
    super.dispose();
  }

  Future<void> _cancel() async {
    await SupabaseManager.instance.updateTradeStatus(widget.tradeId, TradeStatus.cancelled);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1B1B26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Color(0xFF6C4FCE)),
          const SizedBox(height: 16),
          Text(
            '${widget.otherNickname}님에게 거래 요청을 보냈습니다.\n응답을 기다리는 중...',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: _cancel, child: const Text('취소')),
      ],
    );
  }
}

/// 받은 거래 요청 팝업 — [수락]하면 곧장 [TradeScreen]으로 이동한다.
/// main.dart가 [TradeManager.onIncomingTradeRequest]에 연결해 둔다.
Future<void> showIncomingTradeRequestDialog(
  BuildContext context, {
  required TradeSession request,
  required String requesterNickname,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF1B1B26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('거래 요청', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      content: Text(
        '$requesterNickname님이 거래를 요청했습니다.',
        style: const TextStyle(color: Colors.white70),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            await TradeManager.instance.declineRequest(request);
          },
          child: const Text('거절'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C4FCE)),
          onPressed: () async {
            final bool success = await TradeManager.instance.acceptRequest(request);
            if (!dialogContext.mounted) {
              return;
            }
            Navigator.of(dialogContext).pop();
            if (success) {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TradeScreen(
                    tradeId: request.id,
                    otherUserId: request.userA,
                    otherNickname: requesterNickname,
                  ),
                ),
              );
            }
          },
          child: const Text('수락'),
        ),
      ],
    ),
  );
}

/// 실시간 1:1 거래 화면 — 왼쪽은 내 인벤토리+올린 아이템, 오른쪽은 상대가
/// 올린 아이템(읽기 전용 미러)을 보여주는 반반 스플릿. [준비 완료]는
/// 아이템 구성이 바뀌면 즉시 해제되는 2단 잠금이고, 둘 다 잠기면 [거래
/// 확정] 버튼이 활성화된다 — 실제 아이템 이전은 여기서 계산하지 않고
/// [TradeManager.confirmTrade]가 부르는 서버 RPC 결과를 그대로 믿는다.
class TradeScreen extends StatefulWidget {
  const TradeScreen({
    super.key,
    required this.tradeId,
    required this.otherUserId,
    required this.otherNickname,
  });

  final String tradeId;
  final String otherUserId;
  final String otherNickname;

  @override
  State<TradeScreen> createState() => _TradeScreenState();
}

class _TradeScreenState extends State<TradeScreen> {
  bool _isConfirming = false;

  @override
  void initState() {
    super.initState();
    TradeManager.instance.openSession(widget.tradeId);
  }

  @override
  void dispose() {
    TradeManager.instance.closeSession();
    super.dispose();
  }

  Future<void> _cancel() async {
    await TradeManager.instance.cancelTrade();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _confirm() async {
    setState(() => _isConfirming = true);
    final bool success = await TradeManager.instance.confirmTrade();
    if (!mounted) {
      return;
    }
    if (success) {
      Navigator.of(context).pop();
      showCenterToast(context, '거래가 완료되었습니다!');
    } else {
      setState(() => _isConfirming = false);
      showCenterToast(context, '거래에 실패했습니다. 아이템 상태를 다시 확인해 주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: TradeManager.instance,
      builder: (context, _) {
        final TradeManager manager = TradeManager.instance;
        final TradeSession? session = manager.currentSession;
        final String? myId = SupabaseManager.instance.currentUserId;

        if (session == null || myId == null) {
          return const Scaffold(
            backgroundColor: Color(0xFF14141C),
            body: Center(child: CircularProgressIndicator(color: Color(0xFF6C4FCE))),
          );
        }
        if (session.status == TradeStatus.cancelled) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
              showCenterToast(context, '거래가 취소되었습니다.');
            }
          });
        }

        final List<TradeItemEntry> myOfferedItems =
            manager.currentItems.where((entry) => entry.ownerUserId == myId).toList();
        final List<TradeItemEntry> otherOfferedItems =
            manager.currentItems.where((entry) => entry.ownerUserId != myId).toList();
        final Set<String> offeredIds = {
          for (final TradeItemEntry entry in manager.currentItems) entry.equipmentId,
        };
        final bool iAmLocked = session.isLockedBy(myId);
        final bool otherLocked = session.isLockedByOther(myId);

        return Scaffold(
          backgroundColor: const Color(0xFF14141C),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1B1B26),
            elevation: 0,
            foregroundColor: Colors.white,
            centerTitle: true,
            title: Text('${widget.otherNickname}님과 거래',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          body: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _TradeSide(
                        title: '나',
                        locked: iAmLocked,
                        offeredItems: myOfferedItems,
                        onRemove: (entry) => manager.removeItem(entry),
                        myInventory: EquipmentManager.instance.inventory
                            .where((item) => !offeredIds.contains(item.id))
                            .toList(),
                        onAdd: (item) => manager.addItem(item),
                      ),
                    ),
                    const VerticalDivider(color: Color(0xFF3A3A4A), width: 1),
                    Expanded(
                      child: _TradeSide(
                        title: widget.otherNickname,
                        locked: otherLocked,
                        offeredItems: otherOfferedItems,
                        onRemove: null,
                        myInventory: const [],
                        onAdd: null,
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isConfirming ? null : _cancel,
                          child: const Text('취소'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isConfirming ? null : () => manager.setLocked(!iAmLocked),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                iAmLocked ? const Color(0xFF3A3A4A) : Colors.amberAccent,
                            foregroundColor: iAmLocked ? Colors.white70 : Colors.black87,
                          ),
                          child: Text(iAmLocked ? '잠금 해제' : '준비 완료'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: (session.bothLocked && !_isConfirming) ? _confirm : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6C4FCE),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFF2A2A38),
                          ),
                          child: Text(_isConfirming ? '처리 중...' : '거래 확정'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TradeSide extends StatelessWidget {
  const _TradeSide({
    required this.title,
    required this.locked,
    required this.offeredItems,
    required this.onRemove,
    required this.myInventory,
    required this.onAdd,
  });

  final String title;
  final bool locked;
  final List<TradeItemEntry> offeredItems;
  final void Function(TradeItemEntry entry)? onRemove;
  final List<Equipment> myInventory;
  final void Function(Equipment item)? onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Icon(
                locked ? Icons.lock : Icons.lock_open,
                size: 16,
                color: locked ? Colors.greenAccent : Colors.white38,
              ),
            ],
          ),
        ),
        SizedBox(
          height: 90,
          child: offeredItems.isEmpty
              ? const Center(
                  child: Text('올린 아이템 없음', style: TextStyle(color: Colors.white38, fontSize: 12)),
                )
              : GridView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 1,
                    mainAxisSpacing: 6,
                  ),
                  itemCount: offeredItems.length,
                  itemBuilder: (context, index) {
                    final TradeItemEntry entry = offeredItems[index];
                    return _EquipmentChip(
                      item: entry.item,
                      onTap: onRemove == null ? null : () => onRemove!(entry),
                    );
                  },
                ),
        ),
        const Divider(color: Color(0xFF3A3A4A), height: 1),
        if (onAdd != null)
          Expanded(
            child: myInventory.isEmpty
                ? const Center(
                    child: Text('인벤토리가 비어있어요.', style: TextStyle(color: Colors.white38)),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                      childAspectRatio: 0.9,
                    ),
                    itemCount: myInventory.length,
                    itemBuilder: (context, index) {
                      final Equipment item = myInventory[index];
                      final bool tradeable = isItemTradeable(item) && !item.isEquipped;
                      return _EquipmentChip(
                        item: item,
                        locked: !tradeable,
                        lockedTooltip:
                            item.isEquipped ? '장착 중인 아이템은 거래할 수 없어요.' : '거래 불가 등급입니다.',
                        onTap: tradeable ? () => onAdd!(item) : null,
                      );
                    },
                  ),
          )
        else
          const Expanded(child: SizedBox.shrink()),
      ],
    );
  }
}

class _EquipmentChip extends StatelessWidget {
  const _EquipmentChip({
    required this.item,
    this.onTap,
    this.locked = false,
    this.lockedTooltip,
  });

  final Equipment? item;
  final VoidCallback? onTap;
  final bool locked;
  final String? lockedTooltip;

  @override
  Widget build(BuildContext context) {
    final Equipment? equipment = item;
    final Widget tile = Opacity(
      opacity: locked ? 0.4 : 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF20202C),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: equipment == null ? const Color(0xFF3A3A4A) : getGradeColor(equipment.grade),
            width: 1.4,
          ),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(4),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              equipment?.name ?? '???',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
            if (locked)
              const Positioned(
                top: 0,
                right: 0,
                child: Text('🔒', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
    );

    final Widget interactive = onTap == null ? tile : InkWell(onTap: onTap, child: tile);
    return lockedTooltip == null ? interactive : Tooltip(message: lockedTooltip!, child: interactive);
  }
}
