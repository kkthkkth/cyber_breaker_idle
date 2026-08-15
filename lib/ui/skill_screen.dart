import 'package:flutter/material.dart';

import '../managers/skill_manager.dart';
import '../models/skill_model.dart';

class SkillScreen extends StatefulWidget {
  const SkillScreen({super.key});

  @override
  State<SkillScreen> createState() => _SkillScreenState();
}

class _SkillScreenState extends State<SkillScreen> {
  final SkillManager _manager = SkillManager.instance;

  // 0: 캐릭터, 1: 펫
  int _selectedMainTab = 0;

  void _levelUpPetSkill(PetPassiveSkill skill) {
    if (_manager.learnPetSkill(skill.type)) {
      return;
    }
    final String message =
        skill.isMaxLevel ? '이미 최고 레벨입니다' : '펫 스킬 포인트가 부족합니다';
    // clearSnackBars()로 대기 중인 이전 스낵바를 먼저 치운다 — 연타로
    // 같은 실패 메시지가 여러 번 트리거돼도 큐에 쌓여 한참 뒤까지
    // 순서대로 재생되지 않도록 막는다.
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _learn(SkillNode node) {
    if (_manager.learnSkill(node.id)) {
      return;
    }

    String message = '학습할 수 없습니다';
    if (node.isMaxLevel) {
      message = '이미 최고 레벨입니다';
    } else if (_manager.isElementLocked(node.element)) {
      message = '다른 속성을 이미 선택했습니다';
    } else if (_manager.skillPoints <= 0) {
      message = '스킬 포인트가 부족합니다';
    } else if (node.requiredSkillId != null) {
      message = '선행 스킬을 먼저 배우세요';
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showInfo(SkillNode node) {
    showDialog<void>(
      context: context,
      builder: (context) => _SkillInfoDialog(node: node),
    );
  }

  Widget _buildCharacterTab() {
    return DefaultTabController(
      length: SkillElement.values.length,
      child: Column(
        children: [
          Container(
            color: const Color(0xFF1B1B26),
            child: TabBar(
              isScrollable: true,
              indicatorColor: const Color(0xFF6C4FCE),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: [
                for (final SkillElement element in SkillElement.values)
                  Tab(icon: Icon(element.icon, color: element.color), text: element.displayName),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final SkillElement element in SkillElement.values)
                  _ElementTreeView(
                    nodes: _manager.nodesForElement(element),
                    locked: _manager.isElementLocked(element),
                    findById: _manager.findById,
                    onLearn: _learn,
                    onInfo: _showInfo,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPetTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final PetPassiveSkill skill in _manager.petSkillTree)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PetSkillTile(
                  skill: skill,
                  onLevelUp: () => _levelUpPetSkill(skill),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _manager,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF14141C),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1B1B26),
            elevation: 0,
            // 뒤로 가기 버튼처럼 별도 색을 안 준 아이콘이 어두운 배경에
            // 묻히지 않도록 명시한다.
            foregroundColor: Colors.white,
            centerTitle: true,
            title: const Text(
              '스킬',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    _selectedMainTab == 0
                        ? 'SP ${_manager.skillPoints}'
                        : '펫 SP ${_manager.petSkillPoints}',
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _MainTabButton(
                        label: '캐릭터',
                        selected: _selectedMainTab == 0,
                        onTap: () => setState(() => _selectedMainTab = 0),
                      ),
                    ),
                    Expanded(
                      child: _MainTabButton(
                        label: '펫',
                        selected: _selectedMainTab == 1,
                        onTap: () => setState(() => _selectedMainTab = 1),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _selectedMainTab == 0 ? _buildCharacterTab() : _buildPetTab(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MainTabButton extends StatelessWidget {
  const _MainTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? const Color(0xFF8A6FE0) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white54,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _PetSkillTile extends StatelessWidget {
  const _PetSkillTile({required this.skill, required this.onLevelUp});

  final PetPassiveSkill skill;
  final VoidCallback onLevelUp;

  @override
  Widget build(BuildContext context) {
    const Color color = Color(0xFFE0A83A);
    final bool learned = skill.currentLevel > 0;
    final bool maxed = skill.isMaxLevel;

    return Container(
      width: 300,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: learned ? color.withValues(alpha: 0.16) : const Color(0xFF20202C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: learned ? color : const Color(0xFF3A3A4A),
          width: learned ? 2 : 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(skill.type.icon, color: learned ? color : Colors.white38, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  skill.type.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: learned ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  skill.type.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Text(
                  '${skill.currentLevel}/${skill.maxLevel}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: maxed ? null : onLevelUp,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.black,
              disabledBackgroundColor: const Color(0xFF3A3A4A),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            child: Text(
              maxed ? 'MAX' : '레벨업',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ElementTreeView extends StatelessWidget {
  const _ElementTreeView({
    required this.nodes,
    required this.locked,
    required this.findById,
    required this.onLearn,
    required this.onInfo,
  });

  final List<SkillNode> nodes;
  final bool locked;
  final SkillNode? Function(String id) findById;
  final ValueChanged<SkillNode> onLearn;
  final ValueChanged<SkillNode> onInfo;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IgnorePointer(
          ignoring: locked,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (int i = 0; i < nodes.length; i++) ...[
                    Builder(
                      builder: (context) {
                        final SkillNode node = nodes[i];
                        bool prereqMet = true;
                        if (node.requiredSkillId != null) {
                          final SkillNode? prerequisite = findById(node.requiredSkillId!);
                          prereqMet = prerequisite != null && prerequisite.currentLevel >= 1;
                        }
                        return _SkillNodeTile(
                          node: node,
                          prereqMet: prereqMet,
                          onLearn: () => onLearn(node),
                          onInfo: () => onInfo(node),
                        );
                      },
                    ),
                    if (i != nodes.length - 1)
                      Container(width: 2, height: 30, color: Colors.grey.withValues(alpha: 0.5)),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (locked)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.75),
              alignment: Alignment.center,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B1B26),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF6C4FCE)),
                ),
                child: const Text(
                  '다른 속성을 이미 선택했습니다',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SkillNodeTile extends StatelessWidget {
  const _SkillNodeTile({
    required this.node,
    required this.prereqMet,
    required this.onLearn,
    required this.onInfo,
  });

  final SkillNode node;
  final bool prereqMet;
  final VoidCallback onLearn;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final Color color = node.element.color;
    final bool available = prereqMet && !node.isMaxLevel;
    final bool locked = !node.isLearned && !prereqMet;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: available ? onLearn : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: node.isLearned ? color.withValues(alpha: 0.16) : const Color(0xFF20202C),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: node.isLearned
                  ? color
                  : (prereqMet ? const Color(0xFF6C4FCE) : const Color(0xFF3A3A4A)),
              width: node.isLearned ? 2 : 1.2,
            ),
          ),
          child: Row(
            children: [
              // 좌측: 스킬 아이콘 (잠금 상태면 자물쇠 오버레이)
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      node.element.icon,
                      color: node.isLearned ? color : Colors.white38,
                      size: 28,
                    ),
                    if (locked)
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.lock, color: Colors.white70, size: 20),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 중앙: 이름 + 레벨
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      node.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: node.isLearned ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${node.currentLevel}/${node.maxLevel}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 우측: 정보(!) 버튼
              GestureDetector(
                onTap: onInfo,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(color: Color(0xFF3498DB), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: const Text(
                    '!',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillInfoDialog extends StatelessWidget {
  const _SkillInfoDialog({required this.node});

  final SkillNode node;

  @override
  Widget build(BuildContext context) {
    final Color color = node.element.color;

    return AlertDialog(
      backgroundColor: const Color(0xFF1B1B26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(node.element.icon, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(node.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(node.description, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          if (node.isMaxLevel)
            const Text(
              'MAX LEVEL',
              style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 16),
            )
          else ...[
            _StatRow(label: '데미지', current: node.currentDamage, next: node.nextDamage),
            const SizedBox(height: 8),
            _StatRow(label: '쿨타임(초)', current: node.currentCooldown, next: node.nextCooldown),
          ],
        ],
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

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.current, required this.next});

  final String label;
  final double current;
  final double next;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label  ', style: const TextStyle(color: Colors.white54, fontSize: 13)),
        Text(current.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(width: 6),
        const Icon(Icons.arrow_forward, color: Colors.white38, size: 14),
        const SizedBox(width: 6),
        Text(next.toStringAsFixed(1), style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
