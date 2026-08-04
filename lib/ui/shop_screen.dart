import 'package:flutter/material.dart';

import '../managers/equipment_manager.dart';
import '../managers/game_manager.dart';
import '../models/equipment.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final GameManager _gameManager = GameManager.instance;
  final EquipmentManager _equipmentManager = EquipmentManager.instance;

  static const int _singlePullCost = 100;
  static const int _multiPullCost = 1000;
  static const int _multiPullCount = 11;

  void _pull(int count, int cost) {
    if (!_gameManager.spendGold(cost)) {
      _showSnackBar('골드가 부족합니다');
      return;
    }

    final List<Equipment> results = List.generate(
      count,
      (_) => _equipmentManager.generateRandomLoot(),
    );

    final Equipment best = results.reduce(
      (Equipment a, Equipment b) => b.grade.index > a.grade.index ? b : a,
    );

    _showResultDialog(best);
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showResultDialog(Equipment best) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1B1B26),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            '뽑기 결과',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            '${best.name} 획득!',
            style: TextStyle(
              color: getGradeColor(best.grade),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _gameManager,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF14141C),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1B1B26),
            elevation: 0,
            title: const Text(
              '샵',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.monetization_on, color: Colors.amber, size: 22),
                    const SizedBox(width: 6),
                    Text(
                      '${_gameManager.gold} G',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _GachaButton(
                          title: '1회 뽑기',
                          subtitle: '$_singlePullCost G',
                          icon: Icons.card_giftcard,
                          onTap: () => _pull(1, _singlePullCost),
                        ),
                        const SizedBox(height: 16),
                        _GachaButton(
                          title: '11회 연속 뽑기',
                          subtitle: '$_multiPullCost G (1회 보너스)',
                          icon: Icons.auto_awesome,
                          onTap: () => _pull(_multiPullCount, _multiPullCost),
                        ),
                      ],
                    ),
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

class _GachaButton extends StatelessWidget {
  const _GachaButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF20202C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF6C4FCE), width: 1.5),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.amberAccent, size: 28),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.amberAccent, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
