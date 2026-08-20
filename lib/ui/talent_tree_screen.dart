import 'package:flutter/material.dart';

import '../managers/talent_manager.dart';
import '../models/talent_model.dart';
import '../widgets/center_toast.dart';

/// 특성(별자리) 트리 화면 — [TalentManager.nodes]를 선행 관계에 따라
/// 세로로 갈래지는 그래프로 그린다. 캐릭터 화면의 "특성" 버튼으로 들어온다.
class TalentTreeScreen extends StatelessWidget {
  const TalentTreeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B1B26),
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text(
          '특성',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: AnimatedBuilder(
        animation: TalentManager.instance,
        builder: (context, _) {
          return Column(
            children: [
              _TalentPointsBanner(points: TalentManager.instance.talentPoints),
              const Expanded(child: _TalentTreeCanvas()),
            ],
          );
        },
      ),
    );
  }
}

class _TalentPointsBanner extends StatelessWidget {
  const _TalentPointsBanner({required this.points});

  final int points;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E2350), Color(0xFF1C1730)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF8A6FE0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.auto_awesome, color: Color(0xFFC9A24B), size: 20),
          const SizedBox(width: 8),
          Text(
            '보유 특성 포인트: $points',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

/// 노드 하나의 화면상 위치를 (선행 깊이, 같은 깊이 내 순번)으로 계산해
/// [Offset]으로 배치한다 — 트리 구조가 하드코딩([TalentManager
/// ._defaultTalentTree])이라 좌표도 그 구조로부터 매번 순수하게
/// 계산되므로, 노드가 늘어나도 이 화면 코드를 손댈 필요가 없다.
class _TalentTreeCanvas extends StatelessWidget {
  const _TalentTreeCanvas();

  static const double _nodeSize = 84;
  static const double _tierHeight = 150;
  static const double _siblingGap = 110;

  /// 노드의 선행 깊이 — 루트(선행 없음)는 0, 그 외엔 자신의 모든 선행
  /// 노드 중 가장 깊은 값 + 1.
  int _depthOf(TalentNode node, List<TalentNode> all, [Set<String>? visiting]) {
    if (node.prerequisiteNodeIds.isEmpty) {
      return 0;
    }
    final Set<String> guard = visiting ?? {};
    if (guard.contains(node.id)) {
      // 순환 참조 방어 — 정상적인 트리 정의에서는 절대 발생하지 않지만,
      // 혹시 데이터가 잘못 들어와도 무한 재귀로 앱이 죽지 않게 한다.
      return 0;
    }
    guard.add(node.id);
    int maxPrereqDepth = -1;
    for (final String prereqId in node.prerequisiteNodeIds) {
      final TalentNode? prereq = all.where((n) => n.id == prereqId).firstOrNull;
      if (prereq == null) {
        continue;
      }
      final int depth = _depthOf(prereq, all, guard);
      if (depth > maxPrereqDepth) {
        maxPrereqDepth = depth;
      }
    }
    return maxPrereqDepth + 1;
  }

  @override
  Widget build(BuildContext context) {
    final List<TalentNode> nodes = TalentManager.instance.nodes;

    // 깊이별로 묶고, 같은 깊이 안에서는 정의 순서 그대로 좌우로 나열한다.
    final Map<int, List<TalentNode>> byDepth = {};
    for (final TalentNode node in nodes) {
      byDepth.putIfAbsent(_depthOf(node, nodes), () => []).add(node);
    }
    final int maxDepth = byDepth.keys.isEmpty ? 0 : byDepth.keys.reduce((a, b) => a > b ? a : b);
    final int maxSiblingCount =
        byDepth.values.map((list) => list.length).fold(1, (a, b) => a > b ? a : b);

    final double canvasWidth = maxSiblingCount * _siblingGap + _nodeSize + 32;
    final double canvasHeight = (maxDepth + 1) * _tierHeight + _nodeSize + 32;

    final Map<String, Offset> centers = {};
    byDepth.forEach((depth, siblings) {
      final double rowWidth = siblings.length * _siblingGap;
      final double startX = (canvasWidth - rowWidth) / 2 + _siblingGap / 2;
      for (int i = 0; i < siblings.length; i++) {
        centers[siblings[i].id] = Offset(
          startX + i * _siblingGap,
          _tierHeight / 2 + 16 + depth * _tierHeight,
        );
      }
    });

    return InteractiveViewer(
      minScale: 0.6,
      maxScale: 1.6,
      boundaryMargin: const EdgeInsets.all(80),
      child: SizedBox(
        width: canvasWidth,
        height: canvasHeight,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _TalentTreeLinePainter(nodes: nodes, centers: centers),
              ),
            ),
            for (final TalentNode node in nodes)
              if (centers[node.id] != null)
                Positioned(
                  left: centers[node.id]!.dx - _nodeSize / 2,
                  top: centers[node.id]!.dy - _nodeSize / 2,
                  width: _nodeSize,
                  height: _nodeSize,
                  child: _TalentNodeButton(node: node),
                ),
          ],
        ),
      ),
    );
  }
}

/// 선행 관계 선 — 잠금 해제된 연결(선행 노드에 이미 투자한 레벨이 있음)은
/// 밝은 보라색, 아직 잠긴 연결은 흐린 회색으로 그려서 "어디를 더 찍어야
/// 다음이 열리는지"를 한눈에 보여준다.
class _TalentTreeLinePainter extends CustomPainter {
  _TalentTreeLinePainter({required this.nodes, required this.centers});

  final List<TalentNode> nodes;
  final Map<String, Offset> centers;

  @override
  void paint(Canvas canvas, Size size) {
    for (final TalentNode node in nodes) {
      final Offset? end = centers[node.id];
      if (end == null) {
        continue;
      }
      for (final String prereqId in node.prerequisiteNodeIds) {
        final Offset? start = centers[prereqId];
        if (start == null) {
          continue;
        }
        final TalentNode? prereq = nodes.where((n) => n.id == prereqId).firstOrNull;
        final bool unlocked = (prereq?.currentLevel ?? 0) >= node.requiredPrerequisiteLevel;
        final Paint paint = Paint()
          ..color = unlocked ? const Color(0xFF8A6FE0) : const Color(0xFF3A3A4A)
          ..strokeWidth = unlocked ? 3 : 2;
        canvas.drawLine(start, end, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TalentTreeLinePainter oldDelegate) =>
      oldDelegate.nodes != nodes || oldDelegate.centers != centers;
}

class _TalentNodeButton extends StatelessWidget {
  const _TalentNodeButton({required this.node});

  final TalentNode node;

  void _onTap(BuildContext context) {
    final TalentManager manager = TalentManager.instance;
    if (manager.isLocked(node)) {
      showCenterToast(context, '선행 노드를 먼저 ${node.requiredPrerequisiteLevel}레벨까지 올려야 합니다.');
      return;
    }
    if (node.isMaxLevel) {
      showCenterToast(context, '이미 최대 레벨입니다.');
      return;
    }
    if (manager.talentPoints < node.pointCostPerLevel) {
      showCenterToast(context, '특성 포인트가 부족합니다.');
      return;
    }
    if (manager.levelUp(node.id)) {
      showCenterToast(context, '${node.name} Lv.${node.currentLevel} 달성!');
    }
  }

  @override
  Widget build(BuildContext context) {
    final TalentManager manager = TalentManager.instance;
    final bool locked = manager.isLocked(node);
    final bool maxed = node.isMaxLevel;
    final Color accent = maxed
        ? const Color(0xFFC9A24B)
        : (locked ? Colors.white24 : const Color(0xFF6C4FCE));

    return GestureDetector(
      onTap: () => _onTap(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: locked ? const Color(0xFF17171F) : const Color(0xFF20202C),
              border: Border.all(color: accent, width: 2),
              boxShadow: maxed
                  ? [BoxShadow(color: accent.withValues(alpha: 0.6), blurRadius: 12)]
                  : null,
            ),
            alignment: Alignment.center,
            child: locked
                ? const Icon(Icons.lock, color: Colors.white38, size: 26)
                : Icon(Icons.auto_awesome, color: accent, size: 28),
          ),
          const SizedBox(height: 4),
          Text(
            node.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: locked ? Colors.white38 : Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '${node.currentLevel}/${node.maxLevel}',
            style: TextStyle(
              color: locked ? Colors.white24 : Colors.amberAccent,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
