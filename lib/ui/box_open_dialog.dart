import 'dart:math';

import 'package:flutter/material.dart';

import '../managers/box_reward_manager.dart';
import '../models/box_reward_model.dart';
import '../models/consumable_item_model.dart';
import '../widgets/safe_image.dart';

/// Shows [box name, 보상 구성, 열기 버튼] then, once opened, the rolled
/// result — see BoxRewardManager for the actual reward table/roll.
void showBoxOpenDialog(BuildContext context, ConsumableType boxType) {
  showDialog<void>(
    context: context,
    builder: (context) => _BoxOpenDialog(boxType: boxType),
  );
}

class _BoxOpenDialog extends StatefulWidget {
  const _BoxOpenDialog({required this.boxType});

  final ConsumableType boxType;

  @override
  State<_BoxOpenDialog> createState() => _BoxOpenDialogState();
}

class _BoxOpenDialogState extends State<_BoxOpenDialog> {
  bool _opening = false;
  BoxRewardEntry? _result;

  Future<void> _open() async {
    setState(() => _opening = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) {
      return;
    }

    final BoxRewardEntry? reward = BoxRewardManager.instance.openBox(
      widget.boxType,
    );
    setState(() {
      _opening = false;
      _result = reward;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = widget.boxType.boxColor;
    final BoxRewardEntry? result = _result;

    return Dialog(
      backgroundColor: const Color(0xFF1B1B26),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accent),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.boxType.displayName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 90,
              child: Center(
                child: result != null
                    ? _ResultIcon(entry: result)
                    : _BoxSpinEffect(opening: _opening, accent: accent),
              ),
            ),
            const SizedBox(height: 12),
            if (result == null) ...[
              const Text(
                '보상 구성',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 6),
              ...BoxRewardManager.instance
                  .tableFor(widget.boxType)
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        entry.label,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _opening ? null : _open,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: const Color(0xFF3A3A4A),
                  ),
                  child: Text(_opening ? '개봉 중...' : '열기'),
                ),
              ),
            ] else ...[
              Text(
                '${result.label} 획득!',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C4FCE),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('확인'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "촤르륵" open effect: spin + pulse while [opening], static icon otherwise.
class _BoxSpinEffect extends StatelessWidget {
  const _BoxSpinEffect({required this.opening, required this.accent});

  final bool opening;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (!opening) {
      return Icon(Icons.card_giftcard, color: accent, size: 56);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 900),
      builder: (context, value, child) {
        return Transform.scale(
          scale: 1 + sin(value * pi * 6) * 0.15,
          child: Transform.rotate(
            angle: value * 2 * pi * 3,
            child: Icon(Icons.card_giftcard, color: accent, size: 56),
          ),
        );
      },
    );
  }
}

class _ResultIcon extends StatelessWidget {
  const _ResultIcon({required this.entry});

  final BoxRewardEntry entry;

  IconData get _fallbackIcon {
    switch (entry.kind) {
      case BoxRewardKind.gold:
        return Icons.monetization_on;
      case BoxRewardKind.gem:
        return Icons.diamond;
      case BoxRewardKind.dust:
        return Icons.grain;
      case BoxRewardKind.item:
        return entry.itemType?.icon ?? Icons.card_giftcard;
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? iconPath = entry.iconPath;
    if (iconPath != null) {
      return CustomSafeImage(path: iconPath, width: 56, height: 56);
    }
    return Icon(_fallbackIcon, color: Colors.amberAccent, size: 56);
  }
}
