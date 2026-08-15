import 'dart:async';

import 'package:flutter/material.dart';

import '../models/equipment.dart';
import 'character_screen.dart' show InventorySlot;

/// Multi-item result popup with a staggered "촤르륵" reveal: cards appear
/// one by one on a timer, with epic/mythic items getting an extra bounce +
/// glow. Shared by the shop's gacha pulls and the forge's batch synthesis —
/// pass whatever [title] fits the context.
class ItemResultDialog extends StatefulWidget {
  const ItemResultDialog({super.key, required this.title, required this.results});

  final String title;
  final List<Equipment> results;

  @override
  State<ItemResultDialog> createState() => _ItemResultDialogState();
}

class _ItemResultDialogState extends State<ItemResultDialog> {
  static const Duration _tickInterval = Duration(milliseconds: 150);

  int _visibleCount = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_tickInterval, (timer) {
      if (_visibleCount >= widget.results.length) {
        timer.cancel();
        return;
      }
      setState(() {
        _visibleCount++;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _skipAnimation() {
    _timer?.cancel();
    if (_visibleCount != widget.results.length) {
      setState(() {
        _visibleCount = widget.results.length;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1B1B26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.results.length > 1 ? '${widget.title} (${widget.results.length}개)' : widget.title,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skipAnimation,
        child: SizedBox(
          width: double.maxFinite,
          // Bounded (not shrink-wrapped) so a large batch of results
          // scrolls inside the dialog instead of overflowing it.
          height: 320,
          child: GridView.builder(
            itemCount: widget.results.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 8.0,
              mainAxisSpacing: 8.0,
              childAspectRatio: 1.0,
            ),
            itemBuilder: (context, index) {
              return _ItemResultCard(
                item: widget.results[index],
                visible: index < _visibleCount,
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('확인'),
        ),
      ],
    );
  }
}

class _ItemResultCard extends StatelessWidget {
  const _ItemResultCard({required this.item, required this.visible});

  final Equipment item;
  final bool visible;

  // SSSR 이상(SSSR/UR/LR)을 "고등급"으로 취급 — 등급이 늘어나도
  // index 비교라 여기만 다시 손볼 필요가 없다.
  bool get _isHighGrade => item.grade.index >= ItemGrade.sssr.index;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      child: AnimatedScale(
        scale: visible ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        child: _isHighGrade ? _HighGradeCard(item: item, visible: visible) : InventorySlot(item: item),
      ),
    );
  }
}

class _HighGradeCard extends StatelessWidget {
  const _HighGradeCard({required this.item, required this.visible});

  final Equipment item;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    // Only build the bounce/glow once the card is actually revealed, so the
    // TweenAnimationBuilder's one-shot animation starts exactly on reveal
    // instead of racing ahead while still hidden behind zero opacity.
    if (!visible) {
      return InventorySlot(item: item);
    }

    final Color glowColor = getGradeColor(item.grade);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.3, end: 1.0),
      duration: const Duration(milliseconds: 500),
      curve: Curves.elasticOut,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: glowColor.withValues(alpha: 0.8),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: InventorySlot(item: item),
      ),
    );
  }
}
