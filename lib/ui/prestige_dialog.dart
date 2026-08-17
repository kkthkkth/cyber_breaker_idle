import 'package:flutter/material.dart';

import '../managers/game_manager.dart';
import '../managers/prestige_manager.dart';
import '../widgets/center_toast.dart';

/// 홈 화면의 오버클럭(⚡) 버튼이 여는 확인 팝업 — 현재/실행 시 코어
/// 포인트와 영구 버프 미리보기를 보여주고, 실행하면
/// [PrestigeManager.prestige]로 스테이지 진행도를 초기화하는 대신 영구
/// 버프를 올린다.
Future<void> showPrestigeDialog(BuildContext context) {
  return showDialog<void>(context: context, builder: (context) => const _PrestigeDialog());
}

class _PrestigeDialog extends StatefulWidget {
  const _PrestigeDialog();

  @override
  State<_PrestigeDialog> createState() => _PrestigeDialogState();
}

class _PrestigeDialogState extends State<_PrestigeDialog> {
  bool _isSubmitting = false;

  Future<void> _confirm() async {
    setState(() => _isSubmitting = true);
    final bool success = await PrestigeManager.instance.prestige();
    if (!mounted) {
      return;
    }
    if (success) {
      Navigator.of(context).pop();
      showCenterToast(context, '오버클럭 완료! 영구 버프가 올랐습니다.');
    } else {
      setState(() => _isSubmitting = false);
      showCenterToast(context, '지금은 오버클럭으로 얻을 게 없어요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([PrestigeManager.instance, GameManager.instance]),
      builder: (context, _) {
        final PrestigeManager prestige = PrestigeManager.instance;
        final bool eligible = prestige.canPrestige;
        final int nextCorePoints = prestige.previewCorePoints;
        final bool willGain = nextCorePoints > prestige.corePoints;
        final bool canConfirm = eligible && willGain;

        return Dialog(
          backgroundColor: const Color(0xFF1B1B26),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('⚡', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 8),
                const Text(
                  '오버클럭',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                ),
                const SizedBox(height: 10),
                Text(
                  '스테이지와 골드를 처음으로 되돌리는 대신, 영구적으로\n'
                  '공격력/골드 획득량이 늘어나는 코어 포인트를 얻습니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF20202C),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF3A3A4A)),
                  ),
                  child: Column(
                    children: [
                      _StatRow(label: '보유 코어 포인트', value: '${prestige.corePoints}'),
                      _StatRow(
                        label: '실행 시 코어 포인트',
                        value: willGain
                            ? '${prestige.corePoints} → $nextCorePoints'
                            : '$nextCorePoints (변화 없음)',
                        highlight: willGain,
                      ),
                      _StatRow(
                        label: '영구 공격력/골드 버프',
                        value:
                            '+${(nextCorePoints * PrestigeManager.attackBonusPerCorePoint * 100).toStringAsFixed(0)}%',
                        highlight: willGain,
                      ),
                    ],
                  ),
                ),
                if (!canConfirm) ...[
                  const SizedBox(height: 10),
                  Text(
                    eligible
                        ? '이전 오버클럭 이후로 더 멀리 가지 못했어요.\n챕터를 더 진행한 뒤 다시 시도하세요.'
                        : '챕터 ${PrestigeManager.minChapterToPrestige} 이상 도달해야 오버클럭을 실행할 수 있어요.\n'
                              '(현재 최고 기록: ${GameManager.instance.highestReachedChapter}챕터)',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.amberAccent, fontSize: 11),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: (_isSubmitting || !canConfirm) ? null : _confirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C4FCE),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFF3A3A4A),
                        ),
                        child: Text(_isSubmitting ? '처리 중...' : '오버클럭 실행'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value, this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Text(
            value,
            style: TextStyle(
              color: highlight ? Colors.greenAccent : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
