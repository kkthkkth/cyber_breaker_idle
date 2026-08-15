import 'package:flutter/material.dart';

import '../managers/battle_pass_manager.dart';
import '../managers/game_manager.dart';
import '../models/battle_pass_model.dart';
import '../widgets/center_toast.dart';

/// 배틀패스 화면 — 상단에 내 레벨/exp 바(+ 프리미엄 해금 버튼), 중앙에
/// 레벨별 보상 트랙(무료/프리미엄 2열)을 세로 스크롤 리스트로 보여준다.
class BattlePassScreen extends StatelessWidget {
  const BattlePassScreen({super.key});

  Future<void> _onTapReward(
    BuildContext context,
    BattlePassRewardTier tier, {
    required bool premium,
  }) async {
    final BattlePassManager manager = BattlePassManager.instance;
    if (premium && !manager.isPremium) {
      showDialog<void>(context: context, builder: (context) => const _PremiumUnlockDialog());
      return;
    }
    if (!manager.canClaim(tier.level, premium: premium)) {
      return;
    }
    final bool success = await manager.claimReward(tier.level, premium: premium);
    if (!context.mounted || !success) {
      return;
    }
    showCenterToast(
      context,
      '${premium ? tier.premiumRewardLabel : tier.freeRewardLabel} 획득!',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: BattlePassManager.instance,
      builder: (context, _) {
        final BattlePassManager manager = BattlePassManager.instance;

        return Scaffold(
          backgroundColor: const Color(0xFF14141C),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1B1B26),
            elevation: 0,
            // 뒤로 가기 버튼처럼 별도 색을 안 준 아이콘이 어두운 배경에
            // 묻히지 않도록 명시한다.
            foregroundColor: Colors.white,
            title: const Text(
              '배틀패스',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
          ),
          body: Column(
            children: [
              _BattlePassHeader(
                level: manager.level,
                ratio: manager.levelProgressRatio,
                isPremium: manager.isPremium,
                onTapUnlock: () => showDialog<void>(
                  context: context,
                  builder: (context) => const _PremiumUnlockDialog(),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    SizedBox(width: 48, child: Text('Lv', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold))),
                    Expanded(
                      child: Center(
                        child: Text('무료', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text('프리미엄', style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: manager.rewardTrack.isEmpty
                    ? const Center(
                        child: Text(
                          '보상 트랙을 불러오는 중이에요.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: manager.rewardTrack.length,
                        itemBuilder: (context, index) {
                          final BattlePassRewardTier tier = manager.rewardTrack[index];
                          return _RewardTile(
                            tier: tier,
                            myLevel: manager.level,
                            isPremium: manager.isPremium,
                            freeClaimed: manager.hasClaimedFree(tier.level),
                            premiumClaimed: manager.hasClaimedPremium(tier.level),
                            onTapFree: () => _onTapReward(context, tier, premium: false),
                            onTapPremium: () => _onTapReward(context, tier, premium: true),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BattlePassHeader extends StatelessWidget {
  const _BattlePassHeader({
    required this.level,
    required this.ratio,
    required this.isPremium,
    required this.onTapUnlock,
  });

  final int level;
  final double ratio;
  final bool isPremium;
  final VoidCallback onTapUnlock;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF6C4FCE), Color(0xFF3A2A6E)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.black26,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.amberAccent, width: 1.5),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.military_tech, color: Colors.amberAccent, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lv.$level',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(Colors.amberAccent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (!isPremium)
            ElevatedButton(
              onPressed: onTapUnlock,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amberAccent,
                foregroundColor: Colors.black87,
              ),
              child: const Text('프리미엄 해금'),
            )
          else
            const Icon(Icons.workspace_premium, color: Colors.amberAccent, size: 28),
        ],
      ),
    );
  }
}

class _RewardTile extends StatelessWidget {
  const _RewardTile({
    required this.tier,
    required this.myLevel,
    required this.isPremium,
    required this.freeClaimed,
    required this.premiumClaimed,
    required this.onTapFree,
    required this.onTapPremium,
  });

  final BattlePassRewardTier tier;
  final int myLevel;
  final bool isPremium;
  final bool freeClaimed;
  final bool premiumClaimed;
  final VoidCallback onTapFree;
  final VoidCallback onTapPremium;

  bool get _reached => myLevel >= tier.level;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF20202C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _reached ? const Color(0xFF6C4FCE) : const Color(0xFF3A3A4A),
          width: _reached ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              '${tier.level}',
              style: TextStyle(
                color: _reached ? Colors.white : Colors.white38,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
          Expanded(
            child: _RewardCell(
              label: tier.freeRewardLabel,
              reached: _reached,
              claimed: freeClaimed,
              locked: false,
              onTap: onTapFree,
            ),
          ),
          Expanded(
            child: _RewardCell(
              label: tier.premiumRewardLabel,
              reached: _reached,
              claimed: premiumClaimed,
              locked: !isPremium,
              accent: Colors.amberAccent,
              onTap: onTapPremium,
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardCell extends StatelessWidget {
  const _RewardCell({
    required this.label,
    required this.reached,
    required this.claimed,
    required this.locked,
    required this.onTap,
    this.accent = const Color(0xFF6C4FCE),
  });

  final String label;
  final bool reached;
  final bool claimed;

  /// 프리미엄인데 프리미엄 패스가 없는 경우 — 레벨 달성 여부와 무관하게
  /// 자물쇠로 표시하고, 탭하면 해금 팝업으로 안내한다.
  final bool locked;
  final VoidCallback onTap;
  final Color accent;

  bool get _isClaimable => reached && !claimed && !locked;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: (claimed && !locked) ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: _isClaimable ? accent.withValues(alpha: 0.18) : Colors.black26,
          borderRadius: BorderRadius.circular(10),
          border: _isClaimable ? Border.all(color: accent) : null,
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              locked
                  ? Icons.lock
                  : claimed
                  ? Icons.check_circle
                  : Icons.card_giftcard,
              color: locked
                  ? Colors.white38
                  : claimed
                  ? Colors.greenAccent
                  : (reached ? accent : Colors.white38),
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: reached && !locked ? Colors.white70 : Colors.white38,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumUnlockDialog extends StatefulWidget {
  const _PremiumUnlockDialog();

  @override
  State<_PremiumUnlockDialog> createState() => _PremiumUnlockDialogState();
}

class _PremiumUnlockDialogState extends State<_PremiumUnlockDialog> {
  bool _isSubmitting = false;

  Future<void> _unlock() async {
    if (_isSubmitting) {
      return;
    }
    setState(() => _isSubmitting = true);
    final bool success = await BattlePassManager.instance.unlockPremium();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    showCenterToast(
      context,
      success ? '프리미엄 패스를 해금했어요!' : '보석이 부족해요.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1B1B26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        '프리미엄 패스 해금',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: Text(
        '보석 ${BattlePassManager.premiumUnlockCostGems}개를 소모해 프리미엄 보상 트랙 전체를 '
        '해금할까요?\n(보유 보석: ${GameManager.instance.gems}개)',
        style: const TextStyle(color: Colors.white70),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _unlock,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amberAccent,
            foregroundColor: Colors.black87,
          ),
          child: const Text('해금하기'),
        ),
      ],
    );
  }
}
