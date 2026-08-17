import 'dart:math';

import 'package:flutter/material.dart';

/// 최고 등급 가챠 결과([GachaRevealScreen])처럼 "화면 전체에 폭죽이
/// 터지는" 연출이 필요한 곳에서 쓰는 1회성 컨페티 오버레이 — 외부
/// 패키지 없이 [CustomPainter]로 직접 그린다(이 프로젝트의 다른 이펙트
/// — [Meteor], `DamageTextComponent`, 카메라 흔들림 — 와 같은 관례).
/// 한 번 재생되면 끝(반복 없음)이라, 다시 터뜨리려면 호출부가 `key`를
/// 바꿔 새 인스턴스로 교체해야 한다.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, this.particleCount = 80});

  final int particleCount;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..forward();

  final Random _random = Random();
  late final List<_ConfettiParticle> _particles = List.generate(
    widget.particleCount,
    (_) => _ConfettiParticle.random(_random),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            size: Size.infinite,
            painter: _ConfettiPainter(particles: _particles, progress: _controller.value),
          );
        },
      ),
    );
  }
}

/// 한 조각의 낙하 궤적을 결정하는 무작위 파라미터 — [progress](0~1)만
/// 넣으면 매 프레임 위치/회전/투명도가 다시 계산되는 순수 데이터라,
/// 위젯 트리와 독립적으로 테스트하기도 쉽다.
class _ConfettiParticle {
  const _ConfettiParticle({
    required this.startXFraction,
    required this.horizontalDriftFraction,
    required this.fallSpeed,
    required this.rotationSpeed,
    required this.size,
    required this.color,
    required this.delay,
  });

  /// 시작 x좌표(화면 너비 대비 0.0~1.0).
  final double startXFraction;

  /// 낙하하는 동안 옆으로 흘러가는 양(화면 너비 대비 비율).
  final double horizontalDriftFraction;

  /// 낙하 속도 배율 — 클수록 화면 아래로 더 빨리 떨어진다.
  final double fallSpeed;

  /// 라디안/초 단위가 아니라 [progress] 1.0에 도달했을 때 총 회전량(π 단위).
  final double rotationSpeed;

  final double size;
  final Color color;

  /// 이 파티클이 낙하를 시작하는 시점(0.0~1.0) — 0이면 처음부터,
  /// 0.25면 애니메이션의 첫 25% 동안은 안 보이다가 뒤늦게 떨어지기
  /// 시작한다(전부 동시에 시작하면 부자연스럽게 "줄 맞춰" 떨어져 보인다).
  final double delay;

  static const List<Color> _palette = [
    Colors.amberAccent,
    Colors.cyanAccent,
    Colors.pinkAccent,
    Colors.greenAccent,
    Colors.purpleAccent,
    Colors.white,
    Colors.orangeAccent,
  ];

  factory _ConfettiParticle.random(Random random) {
    return _ConfettiParticle(
      startXFraction: random.nextDouble(),
      horizontalDriftFraction: (random.nextDouble() - 0.5) * 0.5,
      fallSpeed: 0.75 + random.nextDouble() * 0.5,
      rotationSpeed: (random.nextDouble() - 0.5) * 10,
      size: 5 + random.nextDouble() * 6,
      color: _palette[random.nextInt(_palette.length)],
      delay: random.nextDouble() * 0.3,
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({required this.particles, required this.progress});

  final List<_ConfettiParticle> particles;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    for (final _ConfettiParticle particle in particles) {
      final double span = 1 - particle.delay;
      final double localProgress = span <= 0
          ? 1.0
          : ((progress - particle.delay) / span).clamp(0.0, 1.0);
      if (progress < particle.delay) {
        continue;
      }

      // 화면 위쪽 바깥에서 시작해 아래로 떨어지다가, 수명이 끝날 무렵
      // 서서히 투명해진다.
      final double y = -size.height * 0.1 +
          size.height * 1.2 * particle.fallSpeed * localProgress;
      if (y > size.height) {
        continue;
      }
      final double x = size.width * particle.startXFraction +
          size.width * particle.horizontalDriftFraction * localProgress;
      final double opacity = localProgress < 0.75 ? 1.0 : (1 - localProgress) * 4;
      final double angle = particle.rotationSpeed * localProgress * pi;

      final Paint paint = Paint()..color = particle.color.withValues(alpha: opacity.clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: particle.size, height: particle.size * 1.6),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => oldDelegate.progress != progress;
}
