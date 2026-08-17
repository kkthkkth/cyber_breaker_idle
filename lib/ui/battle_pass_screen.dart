import 'package:flutter/material.dart';

import '../managers/battle_pass_manager.dart';
import '../managers/game_manager.dart';
import '../models/battle_pass_model.dart';
import '../widgets/center_toast.dart';

/// 배틀패스 화면 — 상단에 내 레벨/exp 바(+ 시즌 D-day, 프리미엄 해금
/// 버튼), 아래에 레벨별 보상을 가로로 스크롤하는 2행(위: 무료, 아래:
/// 프리미엄) 트랙을 보여준다(요구사항: "가로로 스크롤하며... 전형적인
/// UI").
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
              '🎫 배틀패스',
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
                season: manager.currentSeason,
                onTapUnlock: () => showDialog<void>(
                  context: context,
                  builder: (context) => const _PremiumUnlockDialog(),
                ),
              ),
              Expanded(
                child: manager.currentSeason == null
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            '현재 진행 중인 시즌이 없어요.\n다음 시즌을 기다려 주세요!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white54),
                          ),
                        ),
                      )
                    : manager.rewardTrack.isEmpty
                    ? const Center(
                        child: Text(
                          '보상 트랙을 불러오는 중이에요.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : _BattlePassTrack(
                        manager: manager,
                        onTapFree: (tier) => _onTapReward(context, tier, premium: false),
                        onTapPremium: (tier) => _onTapReward(context, tier, premium: true),
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
    required this.season,
    required this.onTapUnlock,
  });

  final int level;
  final double ratio;
  final bool isPremium;
  final BattlePassSeason? season;
  final VoidCallback onTapUnlock;

  String? get _seasonLabel {
    final BattlePassSeason? s = season;
    if (s == null) {
      return null;
    }
    final int daysLeft = s.remaining.inDays;
    return daysLeft > 0 ? '시즌 종료까지 D-$daysLeft' : '오늘 시즌 종료';
  }

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
            child: const Text('🎫', style: TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Lv.$level',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                    ),
                    if (_seasonLabel != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        _seasonLabel!,
                        style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ],
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

/// 레벨별 보상을 가로로 스크롤하는 2행 트랙 — 왼쪽엔 고정된 "무료/Lv/
/// 프리미엄" 행 라벨을, 오른쪽엔 레벨마다 한 열(무료 칸 위/프리미엄 칸
/// 아래, 그 사이에 레벨 배지)을 가로로 나열한다.
class _BattlePassTrack extends StatelessWidget {
  const _BattlePassTrack({
    required this.manager,
    required this.onTapFree,
    required this.onTapPremium,
  });

  final BattlePassManager manager;
  final ValueChanged<BattlePassRewardTier> onTapFree;
  final ValueChanged<BattlePassRewardTier> onTapPremium;

  static const double _cellHeight = 74;
  static const double _badgeRowHeight = 40;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(
          width: 52,
          child: Column(
            children: [
              SizedBox(
                height: _cellHeight,
                child: Center(
                  child: Text(
                    '무료',
                    style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              SizedBox(
                height: _badgeRowHeight,
                child: Center(
                  child: Text(
                    'Lv',
                    style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              SizedBox(
                height: _cellHeight,
                child: Center(
                  child: Text(
                    '프리미엄',
                    style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
            child: Row(
              children: [
                for (final BattlePassRewardTier tier in manager.rewardTrack)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _BattlePassColumn(
                      tier: tier,
                      myLevel: manager.level,
                      isPremium: manager.isPremium,
                      freeClaimed: manager.hasClaimedFree(tier.level),
                      premiumClaimed: manager.hasClaimedPremium(tier.level),
                      onTapFree: () => onTapFree(tier),
                      onTapPremium: () => onTapPremium(tier),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 레벨 한 칸 — 위: 무료 보상, 가운데: 레벨 배지, 아래: 프리미엄 보상.
class _BattlePassColumn extends StatelessWidget {
  const _BattlePassColumn({
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
    return SizedBox(
      width: 78,
      child: Column(
        children: [
          SizedBox(
            height: _BattlePassTrack._cellHeight,
            child: _BattlePassCell(
              label: tier.freeRewardLabel,
              reached: _reached,
              claimed: freeClaimed,
              locked: false,
              accent: const Color(0xFF6C4FCE),
              onTap: onTapFree,
            ),
          ),
          SizedBox(
            height: _BattlePassTrack._badgeRowHeight,
            child: Center(
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _reached ? const Color(0xFF6C4FCE) : const Color(0xFF20202C),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _reached ? Colors.amberAccent : const Color(0xFF3A3A4A),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${tier.level}',
                  style: TextStyle(
                    color: _reached ? Colors.white : Colors.white38,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: _BattlePassTrack._cellHeight,
            child: _BattlePassCell(
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

class _BattlePassCell extends StatelessWidget {
  const _BattlePassCell({
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
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: _isClaimable ? accent.withValues(alpha: 0.18) : const Color(0xFF20202C),
          borderRadius: BorderRadius.circular(10),
          border: _isClaimable
              ? Border.all(color: accent)
              : Border.all(color: const Color(0xFF3A3A4A), width: 1),
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
