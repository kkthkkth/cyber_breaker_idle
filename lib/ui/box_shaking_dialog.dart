import 'package:flutter/material.dart';

/// Shows a 2-second shaking-box popup, then closes it and hands off to
/// [onFinished] — the caller decides what result UI to show (equipment,
/// premium, pet, ...), so this stays reusable across every gacha flow.
Future<void> showBoxShakingDialog(
  BuildContext context, {
  required VoidCallback onFinished,
}) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black87,
    builder: (context) => const _ShakingBoxDialog(),
  );

  await Future.delayed(const Duration(seconds: 2));
  if (!context.mounted) {
    return;
  }
  Navigator.of(context).pop();
  onFinished();
}

class _ShakingBoxDialog extends StatefulWidget {
  const _ShakingBoxDialog();

  @override
  State<_ShakingBoxDialog> createState() => _ShakingBoxDialogState();
}

class _ShakingBoxDialogState extends State<_ShakingBoxDialog>
    with SingleTickerProviderStateMixin {
  // Short, repeating wobble, slightly quicker than before so it still reads
  // as a brisk multi-shake flurry inside the shorter 2s popup lifetime
  // (controlled by showBoxShakingDialog's own delay, not this duration).
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 80),
  )..repeat(reverse: true);

  late final Animation<double> _shakeAngle = Tween<double>(
    begin: -0.12,
    end: 0.12,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: SizedBox(
        height: 200,
        child: Center(
          child: AnimatedBuilder(
            animation: _shakeAngle,
            builder: (context, child) {
              return Transform.rotate(angle: _shakeAngle.value, child: child);
            },
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A3A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amberAccent, width: 2),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.card_giftcard,
                color: Colors.amberAccent,
                size: 64,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
