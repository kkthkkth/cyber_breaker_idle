import 'package:flutter/material.dart';

import '../managers/title_manager.dart';
import '../models/title_model.dart';
import '../widgets/center_toast.dart';
import '../widgets/title_badge.dart';

/// 칭호 화면 — 보유한 칭호는 장착/해제할 수 있고, 미획득 칭호는 회색조로
/// 비활성화된 채 달성 조건([PlayerTitle.conditionLabel])만 보여준다.
class TitleScreen extends StatelessWidget {
  const TitleScreen({super.key});

  Future<void> _toggleEquip(BuildContext context, PlayerTitle title) async {
    final TitleManager manager = TitleManager.instance;
    if (manager.equippedTitleId == title.id) {
      await manager.unequip();
      if (context.mounted) {
        showCenterToast(context, '칭호를 해제했습니다.');
      }
      return;
    }
    final bool success = await manager.equip(title.id);
    if (context.mounted && success) {
      showCenterToast(context, '"${title.name}" 칭호를 장착했습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: TitleManager.instance,
      builder: (context, _) {
        final TitleManager manager = TitleManager.instance;
        // 보유한 칭호를 먼저, 그 안에서는 장착 중인 칭호를 맨 위로 —
        // 미획득 칭호는 뒤에 목표 순서(condition_goal 오름차순)로 붙인다.
        final List<PlayerTitle> owned = manager.ownedTitles
          ..sort((a, b) {
            if (a.id == manager.equippedTitleId) return -1;
            if (b.id == manager.equippedTitleId) return 1;
            return a.name.compareTo(b.name);
          });
        final List<PlayerTitle> locked =
            manager.catalog.where((title) => !manager.isOwned(title.id)).toList()
              ..sort((a, b) => a.conditionGoal.compareTo(b.conditionGoal));
        final List<PlayerTitle> ordered = [...owned, ...locked];

        return Scaffold(
          backgroundColor: const Color(0xFF14141C),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1B1B26),
            elevation: 0,
            foregroundColor: Colors.white,
            centerTitle: true,
            title: const Text('칭호', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          body: ordered.isEmpty
              ? const Center(
                  child: Text('아직 등록된 칭호가 없어요.', style: TextStyle(color: Colors.white54)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: ordered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final PlayerTitle title = ordered[index];
                    final bool owned = manager.isOwned(title.id);
                    final bool equipped = manager.equippedTitleId == title.id;
                    return _TitleTile(
                      title: title,
                      owned: owned,
                      equipped: equipped,
                      onTap: owned ? () => _toggleEquip(context, title) : null,
                    );
                  },
                ),
        );
      },
    );
  }
}

class _TitleTile extends StatelessWidget {
  const _TitleTile({
    required this.title,
    required this.owned,
    required this.equipped,
    required this.onTap,
  });

  final PlayerTitle title;
  final bool owned;
  final bool equipped;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: owned ? 1.0 : 0.5,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF20202C),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: equipped ? Colors.amberAccent : const Color(0xFF3A3A4A),
            width: equipped ? 1.6 : 1.2,
          ),
        ),
        child: Row(
          children: [
            TitleBadge(title: title, height: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (owned)
                    Text(
                      title.buffLabel,
                      style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold),
                    )
                  else
                    Text(
                      '달성 조건: ${title.conditionLabel}',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (owned)
              ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: equipped ? const Color(0xFF3A3A4A) : Colors.amberAccent,
                  foregroundColor: equipped ? Colors.white70 : Colors.black87,
                ),
                child: Text(equipped ? '해제' : '장착'),
              )
            else
              const Icon(Icons.lock, color: Colors.white24),
          ],
        ),
      ),
    );
  }
}
