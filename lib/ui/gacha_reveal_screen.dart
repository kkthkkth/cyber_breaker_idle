import 'dart:math';

import 'package:flutter/material.dart';

import '../models/equipment.dart';

/// 캐릭터/장비/펫 뽑기 결과를 카드 뒤집기 연출로 보여주는 전체 화면 —
/// [showBoxShakingDialog]의 상자 흔들림이 끝난 직후(`onFinished` 콜백)
/// 이 화면으로 넘어온다. 결과 목록([results])만 넘기면 되므로 캐릭터/장비/
/// 펫 어느 뽑기든 동일하게 재사용할 수 있다(shop_screen.dart의
/// `_showResultDialog` 참고) — 합성(`synthesis_screen.dart`)처럼 "가챠
/// 연출"이 아닌 배치 결과는 여전히 기존 [ItemResultDialog]를 그대로 쓴다.
///
/// [주의: 이미지 자리표시자] 카드 앞/뒷면에 실제 캐릭터·장비 아트가 아직
/// 없어서, 지금은 등급 색([getGradeColor])만 칠한 단색 컨테이너로 틀만
/// 잡아 뒀다 — 나중에 아트가 준비되면 [_CardFace]의 `_buildBack`/
/// `_buildFront` 안에 `CustomSafeImage`만 끼워 넣으면 된다.
class GachaRevealScreen extends StatefulWidget {
  const GachaRevealScreen({super.key, required this.results, this.title = '뽑기 결과'});

  final List<Equipment> results;
  final String title;

  @override
  State<GachaRevealScreen> createState() => _GachaRevealScreenState();
}

class _GachaRevealScreenState extends State<GachaRevealScreen>
    with SingleTickerProviderStateMixin {
  late final List<bool> _flipped = List.filled(widget.results.length, false);

  /// UR(이상) 카드를 뒤집을 때 화면 전체에 터지는 번쩍임 — [AnimatedOpacity]
  /// 는 "목표 값으로의 전환"용이라 한 번 켰다가 저절로 꺼지는 "펄스"에는
  /// 맞지 않아서, 같은 목적(투명도 애니메이션)을 [AnimationController] +
  /// [TweenSequence]로 구현했다 — 둘 다 플러터 내장 애니메이션 API다.
  /// UR 카드를 연달아 눌러도 `forward(from: 0)`로 즉시 다시 터지도록
  /// 재시작된다.
  late final AnimationController _flashController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final Animation<double> _flashOpacity = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.9), weight: 15),
    TweenSequenceItem(tween: Tween(begin: 0.9, end: 0.0), weight: 85),
  ]).animate(CurvedAnimation(parent: _flashController, curve: Curves.easeOut));

  bool get _allFlipped => _flipped.every((flipped) => flipped);

  /// UR/LR처럼 "최상위 등급"에서만 화면 전체 번쩍임을 터뜨린다 — SSSR 이하는
  /// 카드 자체의 그로우(`_CardFace`)만으로 충분히 차등을 준다.
  bool _isFlashGrade(ItemGrade grade) => grade.index >= ItemGrade.ur.index;

  @override
  void dispose() {
    _flashController.dispose();
    super.dispose();
  }

  void _onCardTapped(int index) {
    if (_flipped[index]) {
      return;
    }
    if (_isFlashGrade(widget.results[index].grade)) {
      _flashController.forward(from: 0);
    }
    setState(() => _flipped[index] = true);
  }

  /// "모두 열기" — 답답한 유저를 위한 스킵. 연출을 건너뛰는 게 목적이므로
  /// 개별 카드 뒤집기 애니메이션도, UR 번쩍임도 다시 재생하지 않고 즉시
  /// 전부 뒤집힌 상태로 만든다.
  void _skipAll() {
    if (_allFlipped) {
      return;
    }
    setState(() {
      for (int i = 0; i < _flipped.length; i++) {
        _flipped[i] = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B12),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                const SizedBox(height: 12),
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '카드를 눌러 결과를 확인하세요',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: GridView.builder(
                      itemCount: widget.results.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.72,
                      ),
                      itemBuilder: (context, index) {
                        return _GachaCard(
                          item: widget.results[index],
                          flipped: _flipped[index],
                          onTap: () => _onCardTapped(index),
                        );
                      },
                    ),
                  ),
                ),
                // 전부 뒤집히기 전엔 자리만 예약해 두고(AnimatedOpacity로
                // 페이드 인/아웃), 버튼이 나타나고 사라질 때 레이아웃이
                // 덜컹거리지 않게 한다.
                AnimatedOpacity(
                  opacity: _allFlipped ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: IgnorePointer(
                    ignoring: !_allFlipped,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6C4FCE),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('확인', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              top: 8,
              right: 12,
              child: AnimatedOpacity(
                opacity: _allFlipped ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: _allFlipped,
                  child: TextButton.icon(
                    onPressed: _skipAll,
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.black54,
                      foregroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                    icon: const Icon(Icons.flash_on, size: 16),
                    label: const Text('모두 열기'),
                  ),
                ),
              ),
            ),
            // UR 등급 카드를 뒤집을 때 화면 전체에 터지는 번쩍임 — 입력을
            // 가로채면 안 되므로 IgnorePointer로 감싼다.
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _flashOpacity,
                builder: (context, child) {
                  return Opacity(
                    opacity: _flashOpacity.value,
                    child: Container(color: const Color(0xFFEDE4FF)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GachaCard extends StatefulWidget {
  const _GachaCard({required this.item, required this.flipped, required this.onTap});

  final Equipment item;
  final bool flipped;
  final VoidCallback onTap;

  @override
  State<_GachaCard> createState() => _GachaCardState();
}

class _GachaCardState extends State<_GachaCard> with SingleTickerProviderStateMixin {
  late final AnimationController _flipController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  @override
  void didUpdateWidget(covariant _GachaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 부모(GachaRevealScreen)가 개별 탭이든 "모두 열기"든 flipped를
    // true로 바꿔주면 그 즉시 이 카드의 뒤집기 애니메이션을 재생한다 —
    // 카드 자신은 "누가 왜 뒤집으라 했는지" 알 필요가 없다.
    if (widget.flipped && !oldWidget.flipped) {
      _flipController.forward();
    }
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _flipController,
        builder: (context, child) {
          // dart:math 기반 3D 회전 — 0~pi를 절반씩 나눠 앞/뒷면을
          // 교체한다. 절반을 넘긴 뒤에는 각도를 pi만큼 되돌려서(각도 -
          // pi) 앞면 텍스트가 좌우 반전(거울상)으로 보이지 않게 한다.
          final double angle = _flipController.value * pi;
          final bool showFront = angle > pi / 2;
          final double displayAngle = showFront ? angle - pi : angle;

          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(displayAngle),
            child: showFront ? _CardFace.front(item: widget.item) : const _CardFace.back(),
          );
        },
      ),
    );
  }
}

/// 카드 한 면(앞/뒤)의 시각적 틀 — [_CardFace.back]은 아직 뒤집지 않은
/// 모든 카드가 공유하는 고정 디자인, [_CardFace.front]는 등급색으로
/// 채워진 결과 표시다. 실제 아트가 준비되면 이 클래스의 두 named
/// constructor 안쪽만 `CustomSafeImage`로 바꾸면 된다.
class _CardFace extends StatelessWidget {
  const _CardFace.back() : item = null;

  const _CardFace.front({required Equipment this.item});

  final Equipment? item;

  @override
  Widget build(BuildContext context) {
    final Equipment? item = this.item;
    if (item == null) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF20202C),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF6C4FCE), width: 1.5),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.auto_awesome, color: Color(0xFF6C4FCE), size: 32),
      );
    }

    final Color gradeColor = getGradeColor(item.grade);
    final bool isTopGrade = item.grade.index >= ItemGrade.sssr.index;

    return Container(
      decoration: BoxDecoration(
        color: gradeColor.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gradeColor, width: 2),
        boxShadow: isTopGrade
            ? [BoxShadow(color: gradeColor.withValues(alpha: 0.7), blurRadius: 16, spreadRadius: 1)]
            : null,
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconFor(item.type), color: gradeColor, size: 28),
          const SizedBox(height: 6),
          Text(
            item.grade.displayName,
            style: TextStyle(color: gradeColor, fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ],
      ),
    );
  }

  /// 실제 캐릭터/장비/펫 아트가 붙기 전까지, 부위 종류를 한눈에 구분할 수
  /// 있게 최소한으로만 아이콘을 나눈다.
  IconData _iconFor(EquipType type) {
    switch (type) {
      case EquipType.character:
        return Icons.person;
      case EquipType.pet:
        return Icons.pets;
      case EquipType.weapon:
        return Icons.gavel;
      case EquipType.helmet:
        return Icons.sports_motorsports;
      case EquipType.armor:
        return Icons.shield;
      case EquipType.shield:
        return Icons.security;
      case EquipType.boots:
        return Icons.directions_walk;
      case EquipType.ring:
        return Icons.circle_outlined;
      case EquipType.glove:
        return Icons.back_hand;
      case EquipType.belt:
        return Icons.horizontal_rule;
      case EquipType.relic:
        return Icons.auto_awesome;
    }
  }
}
