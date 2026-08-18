import 'package:flutter/material.dart';

import '../managers/tutorial_manager.dart';

/// [MainNavigationScreen]의 최상위 [Stack]에 마지막 레이어로 올라가는
/// 스포트라이트 오버레이 — 화면을 반투명하게 어둡게 덮되,
/// [TutorialManager.currentTargetKey]가 가리키는 위젯 자리만 구멍을 뚫어
/// 실제로 그 위젯을 탭할 수 있게 둔다(구멍 영역엔 이 오버레이의 위젯을
/// 아예 놓지 않는 방식 — 4방향 띠로 감싸 나머지만 흡수한다). 구멍 밖을
/// 탭하면 아무 일도 일어나지 않고([_AbsorbBand]), "건너뛰기"만 튜토리얼을
/// 끝낸다.
class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({super.key});

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  /// [_targetRect]가 이번 프레임엔 아직 레이아웃이 안 끝난 타겟을 만나
  /// null을 반환했을 때, 다음 프레임에 한 번 더 재시도를 예약했는지 —
  /// 매 build마다 새 콜백을 쌓지 않도록 막는 플래그.
  bool _retryScheduled = false;

  @override
  void initState() {
    super.initState();
    TutorialManager.instance.addListener(_onTutorialChanged);
  }

  @override
  void dispose() {
    TutorialManager.instance.removeListener(_onTutorialChanged);
    super.dispose();
  }

  void _onTutorialChanged() {
    // 다음 단계 위젯이 실제로 배치된 뒤에야 위치를 잴 수 있다 — 한 프레임
    // 미뤄서 다시 그린다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  /// build() 시점에 곧바로 재시도를 예약(다음 프레임에 setState)한다 —
  /// 타겟 위젯이 이번 프레임엔 아직 레이아웃을 마치지 못한 경우(예:
  /// 진입 애니메이션 중인 위젯이라 RenderBox가 NEEDS-LAYOUT 상태)를 위한
  /// 것. [_onTutorialChanged]는 "다음 단계로 넘어갈 때"만 반응하므로,
  /// 같은 단계 안에서 레이아웃이 늦게 끝나는 경우까지는 커버하지 못한다.
  void _scheduleRetry() {
    if (_retryScheduled) {
      return;
    }
    _retryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _retryScheduled = false;
      if (mounted) {
        setState(() {});
      }
    });
  }

  Rect? _targetRect() {
    final GlobalKey? key = TutorialManager.instance.currentTargetKey;
    final BuildContext? ctx = key?.currentContext;
    if (ctx == null) {
      return null;
    }
    final RenderObject? renderObject = ctx.findRenderObject();
    // hasSize가 false면(=이번 프레임엔 아직 레이아웃을 거치지 않은
    // RenderBox) `.size`를 읽는 순간 "RenderBox was not laid out" 단언이
    // 터진다 — 진입 애니메이션(FractionalTranslation 등)이 걸린 타겟
    // 위젯이 막 나타난 프레임에 특히 자주 일어난다. 이번 프레임은 그냥
    // 스포트라이트 없이 넘어가고, 다음 프레임에 다시 시도한다.
    if (renderObject is! RenderBox || !renderObject.attached || !renderObject.hasSize) {
      _scheduleRetry();
      return null;
    }
    try {
      final Offset topLeft = renderObject.localToGlobal(Offset.zero);
      return (topLeft & renderObject.size).inflate(6);
    } catch (_) {
      // hasSize 체크로 걸러지지 않는 드문 엣지 케이스(레이아웃 트리에서
      // 막 분리되는 중 등)에 대한 마지막 방어선 — 튜토리얼 오버레이
      // 하나 때문에 화면 전체가 크래시하는 일은 없어야 한다.
      _scheduleRetry();
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!TutorialManager.instance.isActive) {
      return const SizedBox.shrink();
    }

    final Rect? hole = _targetRect();
    final Size screenSize = MediaQuery.sizeOf(context);
    final String message = TutorialManager.instance.currentMessage ?? '';

    return Stack(
      children: [
        IgnorePointer(
          child: CustomPaint(
            size: screenSize,
            painter: _SpotlightPainter(hole: hole),
          ),
        ),
        if (hole != null) ..._absorbBands(hole, screenSize),
        Positioned(
          left: 20,
          right: 20,
          top: hole == null
              ? screenSize.height / 2 - 40
              : (hole.top > screenSize.height / 2 ? hole.top - 96 : hole.bottom + 20),
          child: _TutorialBubble(message: message),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          right: 12,
          child: TextButton(
            onPressed: TutorialManager.instance.skip,
            style: TextButton.styleFrom(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white70,
            ),
            child: const Text('건너뛰기'),
          ),
        ),
      ],
    );
  }

  /// 구멍 사각형 바깥의 나머지 화면을 상/하/좌/우 4개 띠로 덮어 탭을
  /// 흡수한다 — 구멍 자리에는 아무 위젯도 놓지 않으므로 그 아래 실제
  /// 버튼이 정상적으로 탭을 받는다.
  List<Widget> _absorbBands(Rect hole, Size screenSize) {
    return [
      Positioned(
        left: 0,
        top: 0,
        right: 0,
        height: hole.top.clamp(0.0, screenSize.height),
        child: const _AbsorbBand(),
      ),
      Positioned(
        left: 0,
        top: hole.bottom.clamp(0.0, screenSize.height),
        right: 0,
        bottom: 0,
        child: const _AbsorbBand(),
      ),
      Positioned(
        left: 0,
        top: hole.top.clamp(0.0, screenSize.height),
        width: hole.left.clamp(0.0, screenSize.width),
        height: hole.height,
        child: const _AbsorbBand(),
      ),
      Positioned(
        left: hole.right.clamp(0.0, screenSize.width),
        top: hole.top.clamp(0.0, screenSize.height),
        right: 0,
        height: hole.height,
        child: const _AbsorbBand(),
      ),
    ];
  }
}

/// 탭을 흡수하기만 하고 아무 반응도 하지 않는 투명 영역 — 유저가 구멍
/// 밖을 눌러 튜토리얼을 건너뛰지 못하게(의도적으로 "건너뛰기" 버튼으로만
/// 스킵 가능하도록) 막는다.
class _AbsorbBand extends StatelessWidget {
  const _AbsorbBand();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({required this.hole});

  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint dimPaint = Paint()..color = Colors.black.withValues(alpha: 0.78);
    final Path outer = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    if (hole == null) {
      canvas.drawPath(outer, dimPaint);
      return;
    }

    final RRect holeRRect = RRect.fromRectAndRadius(hole!, const Radius.circular(16));
    final Path holePath = Path()..addRRect(holeRRect);
    canvas.drawPath(Path.combine(PathOperation.difference, outer, holePath), dimPaint);

    canvas.drawRRect(
      holeRRect,
      Paint()
        ..color = Colors.amberAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) => oldDelegate.hole != hole;
}

class _TutorialBubble extends StatelessWidget {
  const _TutorialBubble({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF6C4FCE), width: 1.5),
        boxShadow: [
          BoxShadow(color: const Color(0xFF6C4FCE).withValues(alpha: 0.5), blurRadius: 20),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.touch_app, color: Colors.amberAccent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
