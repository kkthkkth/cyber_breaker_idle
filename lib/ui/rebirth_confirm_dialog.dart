import 'package:flutter/material.dart';

import '../managers/game_manager.dart';
import '../managers/prestige_manager.dart';
import '../widgets/center_toast.dart';

/// 홈 화면의 환생(⚡) 버튼이 여는 확인 팝업 — 지금 환생하면 얻을 환생석과
/// 영구 버프 미리보기를 보여주고, 실행하면 [PrestigeManager.prestige]로
/// 스테이지 진행도(와 그 골드로 산 캐릭터 기본 레벨)를 1-1로 초기화하는
/// 대신 환생석을 누적해 영구 버프를 올린다.
Future<void> showRebirthConfirmDialog(BuildContext context) {
  return showDialog<void>(context: context, builder: (context) => const RebirthConfirmDialog());
}

class RebirthConfirmDialog extends StatefulWidget {
  const RebirthConfirmDialog({super.key});

  @override
  State<RebirthConfirmDialog> createState() => _RebirthConfirmDialogState();
}

class _RebirthConfirmDialogState extends State<RebirthConfirmDialog> {
  bool _isSubmitting = false;

  Future<void> _confirm() async {
    setState(() => _isSubmitting = true);
    final int? gained = await PrestigeManager.instance.prestige();
    if (!mounted) {
      return;
    }
    if (gained != null) {
      Navigator.of(context).pop();
      showCenterToast(context, '환생 완료! 환생석 $gained개를 획득했습니다.');
    } else {
      setState(() => _isSubmitting = false);
      showCenterToast(context, '아직 환생할 수 없어요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([PrestigeManager.instance, GameManager.instance]),
      builder: (context, _) {
        final PrestigeManager prestige = PrestigeManager.instance;
        final bool canConfirm = prestige.canPrestige;
        final int gainPreview = prestige.previewRebirthStones;
        final int stonesAfter = prestige.rebirthStones + gainPreview;

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
                  '환생',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                ),
                const SizedBox(height: 10),
                Text(
                  canConfirm
                      ? '정말 환생하시겠습니까? 진행도가 1-1로 초기화되며,\n'
                            '환생석 $gainPreview개를 얻습니다.'
                      : '스테이지와 골드로 산 능력치를 처음으로 되돌리는 대신,\n'
                            '영구적으로 공격력/골드 획득량이 늘어나는 환생석을 얻습니다.',
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
                      _StatRow(label: '보유 환생석', value: '${prestige.rebirthStones}개'),
                      _StatRow(
                        label: '환생 시 획득',
                        value: canConfirm ? '+$gainPreview개 → $stonesAfter개' : '환생 조건 미달성',
                        highlight: canConfirm,
                      ),
                      _StatRow(
                        label: '영구 공격력/골드 버프',
                        value: canConfirm
                            ? '+${(prestige.rebirthStones * PrestigeManager.attackBonusPerRebirthStone * 100).toStringAsFixed(0)}%'
                                  ' → +${(stonesAfter * PrestigeManager.attackBonusPerRebirthStone * 100).toStringAsFixed(0)}%'
                            : '+${(prestige.rebirthStones * PrestigeManager.attackBonusPerRebirthStone * 100).toStringAsFixed(0)}%',
                        highlight: canConfirm,
                      ),
                    ],
                  ),
                ),
                if (!canConfirm) ...[
                  const SizedBox(height: 10),
                  Text(
                    '챕터 ${PrestigeManager.minChapterToPrestige} 이상 도달해야 환생할 수 있어요.\n'
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
                        child: Text(_isSubmitting ? '처리 중...' : '환생하기'),
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
