import 'package:flutter/material.dart';

/// Global-coordinate center of whatever widget [context] belongs to — handy
/// as the fly-animation start point for a tapped claim button.
Offset widgetGlobalCenter(BuildContext context) {
  final RenderBox box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(box.size.center(Offset.zero));
}

/// Final on-screen landing point for a currency fly-to-UI animation —
/// mirrors TopBar's gold/gem icon positions (see lib/ui/top_bar.dart).
Offset targetOffsetForCurrency(BuildContext context, {required bool isGold}) {
  final Size screenSize = MediaQuery.of(context).size;
  return isGold
      ? Offset(screenSize.width - 120, 20)
      : Offset(screenSize.width - 40, 20);
}

/// Flies a small gold/gem icon from [startPosition] to the matching TopBar
/// currency icon, then removes itself. Safe to call from anywhere with a
/// BuildContext — mission/attendance reward claims, etc.
void showCoinFlyAnimation(
  BuildContext context, {
  required Offset startPosition,
  required bool isGold,
}) {
  final OverlayState overlay = Overlay.of(context, rootOverlay: true);
  final Offset endPosition = targetOffsetForCurrency(context, isGold: isGold);
  late final OverlayEntry entry;

  entry = OverlayEntry(
    builder: (context) {
      return _FlyingCurrencyIcon(
        start: startPosition,
        end: endPosition,
        isGold: isGold,
        onComplete: () => entry.remove(),
      );
    },
  );

  overlay.insert(entry);
}

class _FlyingCurrencyIcon extends StatefulWidget {
  const _FlyingCurrencyIcon({
    required this.start,
    required this.end,
    required this.isGold,
    required this.onComplete,
  });

  final Offset start;
  final Offset end;
  final bool isGold;
  final VoidCallback onComplete;

  @override
  State<_FlyingCurrencyIcon> createState() => _FlyingCurrencyIconState();
}

class _FlyingCurrencyIconState extends State<_FlyingCurrencyIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete();
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Animation<Offset> position = Tween<Offset>(
      begin: widget.start,
      end: widget.end,
    ).chain(CurveTween(curve: Curves.easeInCubic)).animate(_controller);
    final Animation<double> fade = Tween<double>(begin: 1.0, end: 0.2).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.6, 1.0)),
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          left: position.value.dx,
          top: position.value.dy,
          child: Opacity(
            opacity: fade.value,
            child: Icon(
              widget.isGold ? Icons.monetization_on : Icons.diamond,
              color: widget.isGold ? Colors.amber : Colors.cyanAccent,
              size: 22,
            ),
          ),
        );
      },
    );
  }
}
