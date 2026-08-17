import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../constants/app_images.dart';
import '../managers/sound_manager.dart';
import '../models/equipment.dart';
import '../widgets/confetti_overlay.dart';
import '../widgets/safe_image.dart';

/// 캐릭터/장비/펫 뽑기 결과를 카드 뒤집기 연출로 보여주는 전체 화면 —
/// [showBoxShakingDialog]의 상자 흔들림이 끝난 직후(`onFinished` 콜백)
/// 이 화면으로 넘어온다. 결과 목록([results])만 넘기면 되므로 캐릭터/장비/
/// 펫 어느 뽑기든 동일하게 재사용할 수 있다(shop_screen.dart의
/// `_showResultDialog` 참고) — 합성(`synthesis_screen.dart`)처럼 "가챠
/// 연출"이 아닌 배치 결과는 여전히 기존 [ItemResultDialog]를 그대로 쓴다.
///
/// 카드 양면은 [_frontImagePathFor]가 캐릭터/펫이면 실제 프론트 이미지를
/// [CustomSafeImage]로 그린다 — 뒤집기 전(밑그림)은 [ColorFilter]로 새까만
/// 실루엣만 보여주고, 뒤집은 뒤에는 원본 색 그대로 보여준다([_CardFace]
/// 참고). 장비는 아직 전용 아트가 없어([_frontImagePathFor]가 null을
/// 돌려주면) 예전처럼 부위별 [Icon]으로 대체한다.
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

  /// SSSR 이상("최고 등급")에서 폭죽을 터뜨린다 — [_CardFace.isTopGrade]와
  /// 같은 기준. UR 이상에서만 도는 [_isFlashGrade]보다 더 낮은 문턱이라,
  /// SSSR은 번쩍임 없이 폭죽만, UR/LR은 번쩍임+폭죽 둘 다 나온다.
  bool _isConfettiGrade(ItemGrade grade) => grade.index >= ItemGrade.sssr.index;

  /// [ConfettiBurst]를 새로 터뜨릴 때마다 1씩 늘려 위젯의 key로 쓴다 —
  /// key가 바뀌면 Flutter가 기존 인스턴스를 버리고 새로 만들어서, 한 번
  /// 재생되고 멈춘 애니메이션도 다음 최고 등급 카드에서 처음부터 다시
  /// 터진다.
  int _confettiTriggerCount = 0;

  @override
  void dispose() {
    _flashController.dispose();
    super.dispose();
  }

  void _onCardTapped(int index) {
    if (_flipped[index]) {
      return;
    }
    unawaited(SoundManager.instance.playGachaReveal());
    final ItemGrade grade = widget.results[index].grade;
    if (_isFlashGrade(grade)) {
      _flashController.forward(from: 0);
    }
    if (_isConfettiGrade(grade)) {
      setState(() {
        _flipped[index] = true;
        _confettiTriggerCount++;
      });
      return;
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
            // SSSR 이상 카드를 뒤집을 때 화면 전체에 터지는 폭죽.
            if (_confettiTriggerCount > 0)
              Positioned.fill(
                child: ConfettiBurst(key: ValueKey(_confettiTriggerCount)),
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
            child: _CardFace(item: widget.item, revealed: showFront),
          );
        },
      ),
    );
  }
}

/// [item]의 실제 프론트 이미지 원격 경로 — 캐릭터/펫만 아트가 있다
/// ([AppImages.playerFront]/[AppImages.petFront], 둘 다 [Equipment
/// .gradeBadgeLabel]을 id로 쓴다). 장비는 아직 전용 아트가 없어 null을
/// 돌려주고, 호출부([_CardFace])가 예전처럼 부위별 [Icon]으로 대체한다.
String? _frontImagePathFor(Equipment item) => switch (item.type) {
  EquipType.character => AppImages.playerFront(item.gradeBadgeLabel),
  EquipType.pet => AppImages.petFront(item.gradeBadgeLabel),
  _ => null,
};

/// 카드 한 면(앞/뒤)의 시각적 틀 — [revealed]가 false면(아직 안 뒤집음)
/// 모든 카드가 같은 보라색 테두리의 "미확인" 프레임을 쓰지만, 그 안에는
/// [item]의 실제 프론트 이미지를 새까만 실루엣([ColorFilter])으로 살짝
/// 보여준다("이 안에 뭐가 있는지" 밑그림 힌트). [revealed]가 true면
/// 등급색 프레임 + 원본 색 이미지 + 등급 텍스트로 결과를 보여준다. 장비처럼
/// 아직 이미지가 없는 부위([_frontImagePathFor]가 null)는 두 상태 모두
/// 기존처럼 [Icon]으로 대체된다.
class _CardFace extends StatelessWidget {
  const _CardFace({required this.item, required this.revealed});

  final Equipment item;
  final bool revealed;

  @override
  Widget build(BuildContext context) {
    final Color gradeColor = getGradeColor(item.grade);
    final bool isTopGrade = item.grade.index >= ItemGrade.sssr.index;
    final String? imagePath = _frontImagePathFor(item);

    final Widget visual = imagePath == null
        ? Icon(
            revealed ? _iconFor(item.type) : Icons.auto_awesome,
            color: revealed ? gradeColor : const Color(0xFF6C4FCE),
            size: 32,
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 56,
              height: 56,
              child: revealed
                  ? CustomSafeImage(path: imagePath, fit: BoxFit.contain)
                  : ColorFiltered(
                      // 알파(투명) 영역은 그대로 두고 그림이 그려진
                      // 부분만 새까맣게 채운다(BlendMode.srcIn) — 흐리게
                      // 어둡히는 게 아니라 진짜 실루엣(그림자) 모양이
                      // 남는다.
                      colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
                      child: CustomSafeImage(path: imagePath, fit: BoxFit.contain),
                    ),
            ),
          );

    return Container(
      decoration: BoxDecoration(
        color: revealed ? gradeColor.withValues(alpha: 0.22) : const Color(0xFF20202C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: revealed ? gradeColor : const Color(0xFF6C4FCE),
          width: revealed ? 2 : 1.5,
        ),
        boxShadow: revealed && isTopGrade
            ? [BoxShadow(color: gradeColor.withValues(alpha: 0.7), blurRadius: 16, spreadRadius: 1)]
            : null,
      ),
      alignment: Alignment.center,
      child: revealed
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                visual,
                const SizedBox(height: 6),
                Text(
                  item.grade.displayName,
                  style: TextStyle(color: gradeColor, fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            )
          : visual,
    );
  }

  /// 장비([_frontImagePathFor]가 null인 부위)는 아직 전용 아트가 없어,
  /// 부위 종류를 한눈에 구분할 수 있게 최소한으로만 아이콘을 나눈다.
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
      case EquipType.badge:
        // 휘장은 가챠로 나오지 않아(길드 전쟁 승리로만 지급) 실제로는
        // 이 분기를 타지 않는다 — switch 소진성 때문에 채워두는 값이다.
        return Icons.military_tech;
    }
  }
}
