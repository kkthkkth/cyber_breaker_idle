import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 커스텀(비-Material) 버튼에 "눌리는 손맛"을 더하는 얇은 래퍼 — 이
/// 프로젝트의 상점/가챠/보상 버튼 대부분이 `InkWell(onTap: ..., child:
/// Container(...))` 형태로 직접 그려져 있어, `InkWell`의 리플만으로는
/// 탭 반응이 밋밋했다(요구사항: "버튼이 살짝 눌리는 애니메이션이나
/// 햅틱 피드백"). `InkWell`을 이 위젯으로 그대로 바꿔 끼우면 된다 —
/// 시각적으로 그리는 내용([child])은 손대지 않고, 탭한 순간 가볍게
/// 축소됐다가 떼는 순간 되돌아오는 스케일 애니메이션 + 가벼운 햅틱을
/// 더한다. [onTap]이 null이면(비활성 버튼) 탭 자체를 무시한다.
class BouncyButton extends StatefulWidget {
  const BouncyButton({
    super.key,
    required this.onTap,
    required this.child,
    this.scaleDown = 0.95,
  });

  final VoidCallback? onTap;
  final Widget child;

  /// 눌렸을 때 줄어드는 비율 — 1.0에 가까울수록 덜 티난다.
  final double scaleDown;

  @override
  State<BouncyButton> createState() => _BouncyButtonState();
}

class _BouncyButtonState extends State<BouncyButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null || _pressed == value) {
      return;
    }
    setState(() => _pressed = value);
  }

  void _handleTap() {
    final VoidCallback? onTap = widget.onTap;
    if (onTap == null) {
      return;
    }
    HapticFeedback.lightImpact();
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    // GestureDetector 하나만 탭을 소유한다 — 스케일 애니메이션 자체가
    // "눌림" 피드백을 이미 충분히 주므로, InkWell 리플을 겹쳐서 같은
    // onTap을 두 번 발화시키는 위험을 감수할 필요가 없다.
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: _handleTap,
      child: AnimatedScale(
        scale: _pressed ? widget.scaleDown : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// [ElevatedButton] 등 이미 Material 버튼으로 만들어진 자리에서 스케일
/// 애니메이션 없이 가벼운 탭 햅틱만 더하고 싶을 때 쓰는 헬퍼 — 버튼
/// 스타일/레이아웃은 그대로 두고 `onPressed: () => callback()`를
/// `onPressed: withTapHaptic(callback)`로만 바꿔 끼우면 된다.
VoidCallback? withTapHaptic(VoidCallback? onPressed) {
  if (onPressed == null) {
    return null;
  }
  return () {
    HapticFeedback.lightImpact();
    onPressed();
  };
}
