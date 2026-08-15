import 'package:flutter/material.dart';

/// 지금 화면에 떠 있는 토스트 — 앱 전체에서 항상 최대 1개만 존재한다.
/// 연타로 [showCenterToast]가 반복 호출돼도(잠긴 캐릭터 연타 등) 토스트가
/// 화면에 겹겹이 쌓이지 않고, 이전 토스트를 즉시 치우고 새 토스트로
/// 교체한다.
OverlayEntry? _activeToastEntry;

/// Shows [message] centered on screen in a translucent dark pill, fading in
/// then out over ~1.5s, then removes itself. Pure Flutter Overlay/animation
/// — no external toast package.
///
/// 이미 떠 있는 토스트가 있으면 애니메이션 없이 즉시 제거하고 새 토스트로
/// 바꿔치기한다 — 같은 동작을 짧은 시간에 여러 번 트리거해도(예: 잠긴
/// 아이템을 연타) 화면에 토스트가 도배되지 않는다.
void showCenterToast(BuildContext context, String message) {
  _activeToastEntry?.remove();
  _activeToastEntry = null;

  final OverlayState overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;

  entry = OverlayEntry(
    builder: (context) => _CenterToast(
      message: message,
      onDismissed: () {
        // activeToastEntry가 더 이상 나 자신이 아니라면(=이미 다른
        // 토스트로 강제 교체됨) 나는 이미 제거된 뒤라는 뜻이다 — 여기서
        // 또 remove()를 부르면 오버레이에 없는 엔트리를 지우려다 실패할
        // 수 있으니 자연 만료(정상 경로)일 때만 스스로 제거한다.
        if (identical(_activeToastEntry, entry)) {
          _activeToastEntry = null;
          entry.remove();
        }
      },
    ),
  );

  _activeToastEntry = entry;
  overlay.insert(entry);
}

class _CenterToast extends StatefulWidget {
  const _CenterToast({required this.message, required this.onDismissed});

  final String message;
  final VoidCallback onDismissed;

  @override
  State<_CenterToast> createState() => _CenterToastState();
}

class _CenterToastState extends State<_CenterToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) {
        return;
      }
      _controller.reverse().whenComplete(widget.onDismissed);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: FadeTransition(
            opacity: _controller,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                widget.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
