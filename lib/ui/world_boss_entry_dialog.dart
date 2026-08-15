import 'package:flutter/material.dart';

import '../managers/potion_manager.dart';
import '../managers/world_boss_manager.dart';
import '../models/shop_consumable_model.dart';
import '../widgets/center_toast.dart';
import '../widgets/safe_image.dart';
import 'world_boss_battle_screen.dart';

/// 홈 화면 아이콘/던전 배너 어디서 눌러도 같은 "용의 동굴" 입장 팝업을
/// 띄운다 — 티켓이 충분하면 곧장 [WorldBossBattleScreen]으로, 부족하면
/// [_ChargeTicketDialog]로 안내한다.
Future<void> showWorldBossEntryDialog(BuildContext context) {
  return showDialog<void>(context: context, builder: (context) => const _WorldBossEntryDialog());
}

String _formatCountdown(Duration duration) {
  final int hours = duration.inHours;
  final int minutes = duration.inMinutes.remainder(60);
  final int seconds = duration.inSeconds.remainder(60);
  final String mm = minutes.toString().padLeft(2, '0');
  final String ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:$mm:$ss';
  }
  return '$mm:$ss';
}

class _WorldBossEntryDialog extends StatelessWidget {
  const _WorldBossEntryDialog();

  Future<void> _challenge(BuildContext context) async {
    final WorldBossManager manager = WorldBossManager.instance;
    if (!manager.isActive) {
      return;
    }
    final bool consumed = await manager.consumeTicket();
    if (!context.mounted) {
      return;
    }
    if (!consumed) {
      showCenterToast(context, '입장 티켓이 부족합니다.');
      return;
    }
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const WorldBossBattleScreen()),
    );
  }

  void _showChargeDialog(BuildContext context) {
    showDialog<void>(context: context, builder: (context) => const _ChargeTicketDialog());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: WorldBossManager.instance,
      builder: (context, _) {
        final WorldBossManager manager = WorldBossManager.instance;
        final bool hasTickets = manager.remainingTickets > 0;

        return Dialog(
          backgroundColor: const Color(0xFF1B1B26),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🐉', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 8),
                const Text(
                  '용의 동굴',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                ),
                const SizedBox(height: 10),
                Text(
                  manager.isActive ? '보스 등장 중! 남은 시간' : '다음 등장까지',
                  style: TextStyle(
                    color: manager.isActive ? Colors.redAccent : Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _formatCountdown(manager.timeRemaining),
                  style: TextStyle(
                    color: manager.isActive ? Colors.redAccent : Colors.white70,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: !manager.isActive
                        ? null
                        : (hasTickets ? () => _challenge(context) : () => _showChargeDialog(context)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasTickets ? const Color(0xFFE0503D) : const Color(0xFF6C4FCE),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF3A3A4A),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      hasTickets
                          ? '도전하기 (${manager.remainingTickets}/${WorldBossManager.maxDailyTickets}회)'
                          : '충전권 사용하기',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
                if (!manager.isActive) ...[
                  const SizedBox(height: 8),
                  const Text(
                    '보스가 등장했을 때만 도전할 수 있어요.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('닫기', style: TextStyle(color: Colors.white54)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 오늘 티켓을 다 썼을 때 뜨는 보조 팝업 — 인벤토리에 보유한
/// `item_type == 'ticket'` 아이템(상점에서 구매)을 소모해
/// [WorldBossManager.extraTickets]를 올린다. 재고가 없으면 상점 구매를
/// 안내만 하고 소비 버튼은 아예 보여주지 않는다.
class _ChargeTicketDialog extends StatelessWidget {
  const _ChargeTicketDialog();

  Future<void> _charge(BuildContext context, ShopConsumableEntry entry) async {
    final bool success = await WorldBossManager.instance.chargeExtraTicket(entry.id);
    if (!context.mounted) {
      return;
    }
    if (success) {
      showCenterToast(context, '충전권을 사용해 도전 횟수를 1회 늘렸어요!');
      Navigator.of(context).pop();
    } else {
      showCenterToast(context, '충전권이 부족합니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: PotionManager.instance,
      builder: (context, _) {
        final List<ShopConsumableEntry> owned = PotionManager.instance.tickets
            .where((entry) => PotionManager.instance.countOf(entry.id) > 0)
            .toList();

        return AlertDialog(
          backgroundColor: const Color(0xFF1B1B26),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            '충전권 사용',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: owned.isEmpty
              ? const Text(
                  '보유한 월드보스 입장 충전권이 없어요.\n상점에서 구매해 보세요!',
                  style: TextStyle(color: Colors.white70),
                )
              : SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final ShopConsumableEntry entry in owned)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CustomSafeImage(path: entry.iconPath, width: 36, height: 36),
                          ),
                          title: Text(entry.name, style: const TextStyle(color: Colors.white)),
                          subtitle: Text(
                            '보유 ${PotionManager.instance.countOf(entry.id)}개',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          trailing: ElevatedButton(
                            onPressed: () => _charge(context, entry),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6C4FCE),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('사용'),
                          ),
                        ),
                    ],
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('닫기', style: TextStyle(color: Colors.white54)),
            ),
          ],
        );
      },
    );
  }
}
