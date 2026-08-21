import 'package:flutter/material.dart';

import '../managers/ad_manager.dart';
import '../models/consumable_item_model.dart';
import '../widgets/bouncy_button.dart';
import '../widgets/center_toast.dart';

/// 순수 표시 전용 위젯 — 보상 지급([OfflineRewardManager.claimReward])은
/// 이 다이얼로그가 아니라 호출부([_MainNavigationScreenState
/// ._showOfflineRewardDialog])의 `showDialog().then()`에서 담당한다.
/// 버튼이든 바깥 탭/뒤로 가기든 팝업이 어떻게 닫히든 항상 같은 한 경로로
/// 귀결되게 해서, "버튼을 안 누르고 강제로 닫으면 보상을 못 받는" 문제를
/// 구조적으로 없앤다. 팝업이 pop하는 값(`bool?`)이 그 경로에 "2배 적용
/// 여부"를 실어 나른다 — `true`면 광고를 끝까지 봐서 2배 확정, 그 외
/// (`false`/`null`, 바깥 탭으로 닫은 경우 포함)는 항상 기본 배율.
class OfflineRewardDialog extends StatefulWidget {
  const OfflineRewardDialog({
    super.key,
    required this.offlineSeconds,
    required this.rewardGold,
    this.equipmentCount = 0,
    this.consumableDrops = const {},
    this.bpExpGained = 0,
    this.runeFragmentsGained = 0,
  });

  final int offlineSeconds;
  final int rewardGold;

  /// 이번 방치 동안 획득한(기댓값 기준) 무작위 장비 개수.
  final int equipmentCount;

  /// 이번 방치 동안 획득한 소모품 종류별 수량.
  final Map<ConsumableType, int> consumableDrops;

  /// 방치 시간에 비례해 획득한 배틀패스 BP 경험치 — 활성 시즌이 없으면
  /// [OfflineRewardManager.claimReward]에서 실제로는 지급되지 않지만,
  /// 표시 자체는 그대로 한다(팝업이 뜨는 시점엔 이미 [OfflineRewardManager
  /// .checkOfflineReward]가 값을 계산해 넘겨준 상태라 시즌 유무를 다시
  /// 확인할 필요가 없다).
  final int bpExpGained;

  /// 방치 시간에 비례해 획득한 룬 조각(요구사항: "룬 조각(시간 비례)").
  final int runeFragmentsGained;

  @override
  State<OfflineRewardDialog> createState() => _OfflineRewardDialogState();
}

class _OfflineRewardDialogState extends State<OfflineRewardDialog> {
  bool _isWatchingAd = false;

  /// 광고를 끝까지 봐서 2배가 확정됐는지 — 한 번 true가 되면 되돌리지
  /// 않는다(광고 재시청으로 4배, 8배가 되는 것을 막는다).
  bool _doubled = false;

  bool get _hasLoot =>
      widget.equipmentCount > 0 || widget.consumableDrops.isNotEmpty;

  String get _formattedDuration {
    final int hours = widget.offlineSeconds ~/ 3600;
    final int minutes = (widget.offlineSeconds % 3600) ~/ 60;
    final int seconds = widget.offlineSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}시간 '
        '${minutes.toString().padLeft(2, '0')}분 '
        '${seconds.toString().padLeft(2, '0')}초';
  }

  /// [AdManager.showRewardedAd]를 재사용해 광고를 보여준다 — 성공하면
  /// [_doubled]를 true로 바꿔서 아래 [TweenAnimationBuilder]가 이미 0→1로
  /// 차오른 숫자를 이어서 1→2로 다시 애니메이션한다(요구사항: "광고 보고
  /// 보상 2배 수령"). 이 매니저는 "시청했는지"만 책임지고 실제 지급
  /// 배율은 이 다이얼로그가 pop하는 값을 통해 호출부가 결정한다 —
  /// [_AdRewardCard](shop_screen.dart)와 동일한 관례.
  Future<void> _watchAdToDouble() async {
    if (_isWatchingAd || _doubled || !AdManager.instance.canWatchAd) {
      return;
    }
    setState(() => _isWatchingAd = true);
    final bool watched = await AdManager.instance.showRewardedAd();
    if (!mounted) {
      return;
    }
    setState(() {
      _isWatchingAd = false;
      _doubled = watched;
    });
    if (!watched) {
      showCenterToast(context, '광고를 불러오지 못했어요. 잠시 후 다시 시도해주세요.');
    }
  }

  static String _formatCooldown(Duration remaining) {
    final int minutes = remaining.inMinutes;
    final int seconds = remaining.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF3D2C6D), Color(0xFF1B1B26)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF8A6FE0), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6C4FCE).withValues(alpha: 0.5),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ConstrainedBox(
          // item_detail_dialog.dart와 같은 관례 — 방치 동안 쌓인 소모품
          // 종류가 많거나(_LootGrid가 그만큼 키가 커진다) 접근성 글자
          // 크기가 커진 상태에서도, 위쪽 내용만 스크롤되고 버튼 영역은
          // 항상 화면에 고정돼 보이게 한다(RenderFlex overflow 방지).
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  // [멀티플라이어] 0→1로 한 번 차오른 뒤([_doubled]가 계속
                  // false면 거기서 멈춘다), 광고를 다 보면 1→2로 이어서
                  // 애니메이션한다 — TweenAnimationBuilder는 tween의 end가
                  // 바뀌면 처음(0)부터가 아니라 "지금 값"에서 새 목표로
                  // 이어서 애니메이션하므로, 이 하나의 빌더로 "카운트업"과
                  // "2배 연출"을 동시에 자연스럽게 표현할 수 있다.
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: _doubled ? 2.0 : 1.0),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, multiplier, _) {
                      final int animatedGold = (widget.rewardGold * multiplier)
                          .round();
                      final int animatedBpExp =
                          (widget.bpExpGained * multiplier).round();
                      final int animatedRuneFragments =
                          (widget.runeFragmentsGained * multiplier).round();
                      final int animatedEquipmentCount =
                          (widget.equipmentCount * multiplier).round();

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.nights_stay,
                            color: Colors.amberAccent,
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '환영합니다!\n잠시 자리를 비운 동안 영웅들이 열심히 싸웠습니다.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 20),
                          _InfoRow(label: '방치 시간', value: _formattedDuration),
                          const SizedBox(height: 10),
                          _InfoRow(
                            label: '획득한 골드',
                            value: '🪙 $animatedGold',
                            valueColor: Colors.amberAccent,
                          ),
                          if (widget.bpExpGained > 0) ...[
                            const SizedBox(height: 10),
                            _InfoRow(
                              label: '획득한 경험치(BP)',
                              value: '✨ $animatedBpExp',
                              valueColor: Colors.lightBlueAccent,
                            ),
                          ],
                          if (widget.runeFragmentsGained > 0) ...[
                            const SizedBox(height: 10),
                            _InfoRow(
                              label: '획득한 룬 조각',
                              value: '🔮 $animatedRuneFragments',
                              valueColor: Colors.tealAccent,
                            ),
                          ],
                          if (_doubled) ...[
                            const SizedBox(height: 10),
                            const _DoubledBanner(),
                          ],
                          if (_hasLoot) ...[
                            const SizedBox(height: 16),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '획득한 전리품',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _LootGrid(
                              equipmentCount: animatedEquipmentCount,
                              consumableDrops: widget.consumableDrops.map(
                                (type, count) => MapEntry(
                                  type,
                                  (count * multiplier).round(),
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _doubled
                  ? SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: withTapHaptic(
                          () => Navigator.of(context).pop(true),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amberAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          '2배 보상 수령하기 🎉',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: withTapHaptic(
                              () => Navigator.of(context).pop(false),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Color(0xFF6C4FCE)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              '일반 수령',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: AnimatedBuilder(
                            animation: AdManager.instance,
                            builder: (context, _) {
                              final AdManager ads = AdManager.instance;
                              final bool canWatch =
                                  ads.canWatchAd && !_isWatchingAd;
                              final String label = !ads.isSupportedPlatform
                                  ? '지원 안 됨'
                                  : !ads.hasDailyViewsLeft
                                  ? '오늘 시청 완료'
                                  : ads.isOnCooldown
                                  ? '대기 (${_formatCooldown(ads.cooldownRemaining)})'
                                  : '광고 보고 2배 수령';
                              return ElevatedButton.icon(
                                onPressed: withTapHaptic(
                                  canWatch ? _watchAdToDouble : null,
                                ),
                                icon: _isWatchingAd
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.play_circle_fill,
                                        size: 18,
                                      ),
                                label: Text(
                                  label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.amberAccent,
                                  foregroundColor: Colors.black,
                                  disabledBackgroundColor: const Color(
                                    0xFF3A3A4A,
                                  ),
                                  disabledForegroundColor: Colors.white38,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "2배 적용됨"을 알리는 짧은 배지 — 광고 시청 성공 직후에만 나타난다.
class _DoubledBanner extends StatelessWidget {
  const _DoubledBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amberAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.6)),
      ),
      child: const Text(
        '⚡ 광고 시청으로 보상 2배 적용!',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.amberAccent,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

/// 골드/경험치뿐이던 예전 팝업에 새로 추가된 "전리품" 영역 — 장비(등급
/// 없이 뭉뚱그린 개수)와 소모품 종류별 수량을 아이콘+수량 칩으로
/// 나열한다. 실제 장비 개별 등급/이름은 방치 종료 시점이 아니라 나중에
/// 인벤토리에서 확인하면 되므로, 여기서는 "몇 개 얻었는지"만 한눈에
/// 보여주는 요약 그리드로 충분하다.
class _LootGrid extends StatelessWidget {
  const _LootGrid({
    required this.equipmentCount,
    required this.consumableDrops,
  });

  final int equipmentCount;
  final Map<ConsumableType, int> consumableDrops;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (equipmentCount > 0)
          _LootChip(
            icon: Icons.shield,
            label: '장비',
            count: equipmentCount,
            color: const Color(0xFF6C4FCE),
          ),
        for (final MapEntry<ConsumableType, int> entry
            in consumableDrops.entries)
          if (entry.value > 0)
            _LootChip(
              icon: entry.key.icon,
              label: entry.key.displayName,
              count: entry.value,
              color: Colors.amberAccent,
            ),
      ],
    );
  }
}

class _LootChip extends StatelessWidget {
  const _LootChip({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 9),
          ),
          Text(
            'x$count',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
