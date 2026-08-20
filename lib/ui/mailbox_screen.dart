import 'package:flutter/material.dart';

import '../managers/mailbox_manager.dart';
import '../models/mailbox_item_model.dart';
import '../widgets/bouncy_button.dart';
import '../widgets/center_toast.dart';

/// 우편함 화면 — 수령 가능한 우편을 리스트로 보여주고, 개별 [수령]과
/// 하단 고정 [모두 수령] 버튼으로 받는다. 서버가 우편 내용을 직접
/// 생성하는 구조라(월드보스 랭킹 보상 정산 RPC 등) 화면을 열 때마다
/// [MailboxManager.refresh]로 최신 목록을 다시 받아온다.
class MailboxScreen extends StatefulWidget {
  const MailboxScreen({super.key});

  @override
  State<MailboxScreen> createState() => _MailboxScreenState();
}

class _MailboxScreenState extends State<MailboxScreen> {
  bool _isRefreshing = true;
  bool _isClaimingAll = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    await MailboxManager.instance.refresh();
    if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  Future<void> _claim(MailboxItem item) async {
    final bool success = await MailboxManager.instance.claim(item.id);
    if (!mounted || !success) {
      return;
    }
    showCenterToast(context, '${item.rewardLabel}을(를) 받았어요!');
  }

  Future<void> _claimAll() async {
    if (_isClaimingAll) {
      return;
    }
    setState(() => _isClaimingAll = true);
    try {
      final int count = await MailboxManager.instance.claimAll();
      if (!mounted) {
        return;
      }
      if (count > 0) {
        showCenterToast(context, '우편 $count통을 모두 수령했어요!');
      }
    } finally {
      if (mounted) {
        setState(() => _isClaimingAll = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14141C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B1B26),
        elevation: 0,
        // 뒤로 가기 버튼처럼 별도 색을 안 준 아이콘이 어두운 배경에
        // 묻히지 않도록 명시한다.
        foregroundColor: Colors.white,
        title: const Text(
          '우편함',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _isRefreshing ? null : _refresh,
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: MailboxManager.instance,
        builder: (context, _) {
          final List<MailboxItem> items = MailboxManager.instance.items;

          if (_isRefreshing && items.isEmpty) {
            return const Center(child: CircularProgressIndicator(color: Colors.white54));
          }
          if (items.isEmpty) {
            return const Center(
              child: Text('우편함이 비어있어요.', style: TextStyle(color: Colors.white54)),
            );
          }

          final List<MailboxItem> unclaimed = items.where((item) => !item.isClaimed).toList();
          final List<MailboxItem> claimed = items.where((item) => item.isClaimed).toList();

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final MailboxItem item in unclaimed)
                      _MailTile(item: item, onClaim: () => _claim(item)),
                    if (claimed.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        '수령 완료',
                        style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      for (final MailboxItem item in claimed)
                        _MailTile(item: item, onClaim: null),
                    ],
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: withTapHaptic((unclaimed.isEmpty || _isClaimingAll) ? null : _claimAll),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C4FCE),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF3A3A4A),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        unclaimed.isEmpty ? '받을 우편이 없어요' : '모두 수령 (${unclaimed.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MailTile extends StatelessWidget {
  const _MailTile({required this.item, required this.onClaim});

  final MailboxItem item;

  /// null이면(=이미 수령한 우편) [수령] 버튼 자체를 숨긴다.
  final VoidCallback? onClaim;

  @override
  Widget build(BuildContext context) {
    final bool claimed = item.isClaimed;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF20202C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: claimed ? const Color(0xFF3A3A4A) : const Color(0xFF6C4FCE),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            claimed ? Icons.mark_email_read : Icons.mark_email_unread,
            color: claimed ? Colors.white24 : Colors.amberAccent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    color: claimed ? Colors.white38 : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (item.content != null && item.content!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      item.content!,
                      style: TextStyle(
                        color: claimed ? Colors.white24 : Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  item.rewardLabel,
                  style: TextStyle(
                    color: claimed ? Colors.white38 : Colors.greenAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (onClaim != null)
            ElevatedButton(
              onPressed: withTapHaptic(onClaim),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C4FCE),
                foregroundColor: Colors.white,
              ),
              child: const Text('수령'),
            ),
        ],
      ),
    );
  }
}
