import 'package:flutter/material.dart';

import '../managers/game_manager.dart';

class SkillScreen extends StatefulWidget {
  const SkillScreen({super.key});

  @override
  State<SkillScreen> createState() => _SkillScreenState();
}

class _SkillScreenState extends State<SkillScreen> {
  final GameManager _manager = GameManager.instance;

  void _learn(Skill skill) {
    if (_manager.gold < skill.cost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('골드가 부족합니다')),
      );
      return;
    }
    _manager.learnSkill(skill.id);
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
            title: const Text(
              '스킬 트리',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
          ),
          body: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _manager.skills.length,
            separatorBuilder: (context, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final Skill skill = _manager.skills[index];
              return _SkillTile(skill: skill, onLearn: () => _learn(skill));
            },
          ),
        );
      },
    );
  }
}

class _SkillTile extends StatelessWidget {
  const _SkillTile({required this.skill, required this.onLearn});

  final Skill skill;
  final VoidCallback onLearn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF20202C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: skill.isLearned ? const Color(0xFF3A3A4A) : const Color(0xFF6C4FCE),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF2C2C3A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(skill.icon, color: Colors.orangeAccent, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  skill.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '쿨타임 ${skill.cooldown.toStringAsFixed(0)}초',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          skill.isLearned
              ? const Text(
                  '학습 완료',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                )
              : ElevatedButton(
                  onPressed: onLearn,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C4FCE),
                    foregroundColor: Colors.white,
                  ),
                  child: Text('배우기 (${skill.cost} G)'),
                ),
        ],
      ),
    );
  }
}
