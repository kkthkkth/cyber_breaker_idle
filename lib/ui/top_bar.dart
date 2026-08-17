import 'package:flutter/material.dart';

import '../managers/consumable_manager.dart';
import '../managers/game_manager.dart';
import '../managers/speed_manager.dart';
import '../models/consumable_item_model.dart';
import '../utils/number_formatter.dart';
import 'dispatch_screen.dart';
import 'settings_dialog.dart';

/// Common top bar: user/settings icon on the left, speed + gold/gem on the
/// right — pixel-identical to main.dart's AppBar. Placed as the first child
/// of a screen's body Column (with the rest wrapped in Expanded) so pushed
/// screens (inventory, disassemble, crafting) show the same header the
/// tab-embedded main AppBar shows.
class TopBar extends StatelessWidget {
  const TopBar({super.key});

  /// 파견 화면 진입 — 연타 방지: 이미 다른 라우트가 최상단으로 올라간
  /// 상태라면 중복으로 또 push하지 않는다([CollectionScreen]/
  /// [ItemDetailDialog]와 같은 패턴).
  void _openDispatch(BuildContext context) {
    final ModalRoute<dynamic>? currentRoute = ModalRoute.of(context);
    if (currentRoute != null && !currentRoute.isCurrent) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const DispatchScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF1B1B26),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const CircleAvatar(
              backgroundColor: Color(0xFF2C2C3A),
              child: Icon(Icons.person, color: Colors.white70),
            ),
            onPressed: () => showSettingsDialog(context),
          ),
          IconButton(
            icon: const CircleAvatar(
              backgroundColor: Color(0xFF2C2C3A),
              child: Icon(Icons.card_travel, color: Colors.white70),
            ),
            tooltip: '파견',
            onPressed: () => _openDispatch(context),
          ),
          const Spacer(),
          const SpeedButton(),
          // Flexible로 감싸는 이유: 예전엔 이 통화 표시 Container가 콘텐츠
          // 크기만큼 무한정 늘어날 수 있었다 — 숫자가 커지면(수억~수조
          // 단위) 왼쪽 아이콘(설정/파견 등)을 밀어내거나 Row 자체가
          // 오버플로우될 수 있었다(main.dart의 AppBar actions와 동일한
          // 문제이자 동일한 해법 — 이 위젯 자체가 그 AppBar와
          // "pixel-identical"하게 유지하려는 목적이라 함께 고쳤다).
          // NumberFormatter의 K/M/B/T 축약 덕분에 실제로 이 한계에 걸릴
          // 일은 거의 없지만, Text의 ellipsis까지 이중으로 방어해 둔다.
          Flexible(
            child: AnimatedBuilder(
              animation: GameManager.instance,
              builder: (context, _) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF20202C),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF3A3A4A)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.monetization_on,
                        color: Colors.amber,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          NumberFormatter.format(GameManager.instance.gold.toDouble()),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(
                        Icons.diamond,
                        color: Colors.cyanAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          NumberFormatter.format(GameManager.instance.gems.toDouble()),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Speed-boost button for the main AppBar, placed just left of the currency
/// display. Opens a [PopupMenuButton] offering the owned speed items and
/// live-renders the remaining boost time once one is active.
class SpeedButton extends StatelessWidget {
  const SpeedButton({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        SpeedManager.instance,
        ConsumableManager.instance,
      ]),
      builder: (context, _) {
        final SpeedManager speed = SpeedManager.instance;
        final bool active = speed.activeSpeed > 1;

        return Container(
          margin: const EdgeInsets.only(right: 8),
          child: PopupMenuButton<int>(
            tooltip: '배속',
            color: const Color(0xFF20202C),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (value) => _onSelect(context, value),
            itemBuilder: (context) => [
              _buildMenuItem(ConsumableType.speed2x, 2, '2배속'),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF1E8E6B)
                    : const Color(0xFF20202C),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active
                      ? const Color(0xFF3FBF94)
                      : const Color(0xFF3A3A4A),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.speed, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    active
                        ? '${speed.activeSpeed}x (${_formatTime(speed.remainingSeconds)})'
                        : '1x',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  PopupMenuItem<int> _buildMenuItem(
    ConsumableType type,
    int speedValue,
    String label,
  ) {
    final int count = ConsumableManager.instance.countOf(type);
    final bool available = count > 0;

    return PopupMenuItem<int>(
      value: speedValue,
      enabled: available,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label (30분)',
            style: TextStyle(color: available ? Colors.white : Colors.grey),
          ),
          const SizedBox(width: 12),
          Text(
            'x$count',
            style: TextStyle(
              color: available ? Colors.white : Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _onSelect(BuildContext context, int speedValue) {
    final bool success = SpeedManager.instance.activate(speedValue);
    if (!success) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('사용할 수 없습니다. (다른 배속이 활성화 중이거나 아이템이 없습니다)'),
          ),
        );
    }
  }

  String _formatTime(int totalSeconds) {
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
