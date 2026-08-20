import 'package:flutter/material.dart';

import '../managers/dungeon_manager.dart';
import '../managers/equipment_manager.dart';
import '../managers/game_manager.dart';
import '../managers/trade_manager.dart';

void showSettingsDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => _SettingsDialog(rootContext: context),
  );
}

class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog({required this.rootContext});

  /// The context of the screen that opened the dialog — used for SnackBars
  /// so they still work correctly after this dialog has been popped.
  final BuildContext rootContext;

  void _notify(String message) {
    ScaffoldMessenger.of(rootContext)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _closeAndNotify(BuildContext context, String message) {
    Navigator.of(context).pop();
    _notify(message);
  }

  /// 대소문자 구분 없이 코드를 매칭한다 — 지금은 테스트용 재화 쿠폰
  /// "test1" 하나뿐이지만, 새 쿠폰이 늘어나도 이 맵에 한 줄만 추가하면
  /// 된다.
  static final Map<String, VoidCallback> _couponRewards = {
    'test1': () {
      GameManager.instance.addGold(100000000);
      GameManager.instance.addGems(100000000);
    },
  };

  void _openCouponDialog(BuildContext context) {
    Navigator.of(context).pop();
    final TextEditingController controller = TextEditingController();

    showDialog<void>(
      context: rootContext,
      builder: (couponContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1B1B26),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            '쿠폰 입력',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: '쿠폰 코드를 입력하세요',
              hintStyle: TextStyle(color: Colors.white38),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF3A3A4A)),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF6C4FCE)),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(couponContext).pop(),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () {
                final String code = controller.text.trim().toLowerCase();
                Navigator.of(couponContext).pop();

                final VoidCallback? grantReward = _couponRewards[code];
                if (grantReward == null) {
                  _notify('유효하지 않은 쿠폰입니다.');
                  return;
                }
                grantReward();
                _notify('테스트 재화(코인 1억, 보석 1억)가 지급되었습니다!');
              },
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveGame(BuildContext context) async {
    await GameManager.instance.saveGame();
    await EquipmentManager.instance.saveEquipment();
    await DungeonManager.instance.saveDungeonData();
    if (context.mounted) {
      Navigator.of(context).pop();
    }
    _notify('게임 정보가 저장되었습니다!');
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1B1B26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.settings, color: Colors.white70),
                  SizedBox(width: 8),
                  Text(
                    '설정',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF34344A), height: 20),
            _SettingsTile(
              icon: Icons.account_circle,
              label: '구글 계정 연동',
              onTap: () => _closeAndNotify(context, '준비 중입니다'),
            ),
            _SettingsTile(
              icon: Icons.campaign,
              label: '공지사항',
              onTap: () => _closeAndNotify(context, '준비 중입니다'),
            ),
            _SettingsTile(
              icon: Icons.public,
              label: '공식 카페/사이트 가기',
              onTap: () => _closeAndNotify(context, '준비 중입니다'),
            ),
            _SettingsTile(
              icon: Icons.card_giftcard,
              label: '쿠폰 입력',
              onTap: () => _openCouponDialog(context),
            ),
            _SettingsTile(
              icon: Icons.privacy_tip,
              label: '개인정보 처리방침',
              onTap: () => _closeAndNotify(context, '준비 중입니다'),
            ),
            // 요구사항: "거래 허용을 켜고 끌 수 있게" — 켜져 있어야
            // 다른 유저가 나에게 거래를 요청할 수 있다(TradeManager
            // .requestTrade가 상대방 이 값을 먼저 확인한다).
            AnimatedBuilder(
              animation: TradeManager.instance,
              builder: (context, _) => SwitchListTile(
                secondary: const Icon(Icons.swap_horiz, color: Colors.white70),
                title: const Text('거래 허용', style: TextStyle(color: Colors.white)),
                activeThumbColor: const Color(0xFF6C4FCE),
                value: TradeManager.instance.allowTrade,
                onChanged: (value) => TradeManager.instance.setAllowTrade(value),
              ),
            ),
            _SettingsTile(
              icon: Icons.save,
              label: '게임 저장하기',
              onTap: () => _saveGame(context),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
      onTap: onTap,
    );
  }
}
