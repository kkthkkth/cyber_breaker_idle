import 'package:flutter/material.dart';

import '../models/consumable_item_model.dart';

/// 순수 표시 전용 위젯 — 보상 지급([OfflineRewardManager.claimReward])은
/// 이 다이얼로그가 아니라 호출부([_MainNavigationScreenState
/// ._showOfflineRewardDialog])의 `showDialog().then()`에서 담당한다.
/// 버튼이든 바깥 탭/뒤로 가기든 팝업이 어떻게 닫히든 항상 같은 한 경로로
/// 귀결되게 해서, "버튼을 안 누르고 강제로 닫으면 보상을 못 받는" 문제를
/// 구조적으로 없앤다.
class OfflineRewardDialog extends StatelessWidget {
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

  bool get _hasLoot => equipmentCount > 0 || consumableDrops.isNotEmpty;

  String get _formattedDuration {
    final int hours = offlineSeconds ~/ 3600;
    final int minutes = (offlineSeconds % 3600) ~/ 60;
    final int seconds = offlineSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}시간 '
        '${minutes.toString().padLeft(2, '0')}분 '
        '${seconds.toString().padLeft(2, '0')}초';
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
          // 크기가 커진 상태에서도, 위쪽 내용만 스크롤되고 "수령하기"
          // 버튼은 항상 화면에 고정돼 보이게 한다(RenderFlex overflow
          // 방지).
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.nights_stay, color: Colors.amberAccent, size: 48),
                      const SizedBox(height: 12),
                      const Text(
                        '환영합니다!\n잠시 자리를 비운 동안 영웅들이 열심히 싸웠습니다.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 20),
                      _InfoRow(label: '방치 시간', value: _formattedDuration),
                      const SizedBox(height: 10),
                      _InfoRow(label: '획득한 골드', value: '🪙 $rewardGold', valueColor: Colors.amberAccent),
                      if (bpExpGained > 0) ...[
                        const SizedBox(height: 10),
                        _InfoRow(
                          label: '획득한 경험치(BP)',
                          value: '✨ $bpExpGained',
                          valueColor: Colors.lightBlueAccent,
                        ),
                      ],
                      if (runeFragmentsGained > 0) ...[
                        const SizedBox(height: 10),
                        _InfoRow(
                          label: '획득한 룬 조각',
                          value: '🔮 $runeFragmentsGained',
                          valueColor: Colors.tealAccent,
                        ),
                      ],
                      if (_hasLoot) ...[
                        const SizedBox(height: 16),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '획득한 전리품',
                            style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _LootGrid(equipmentCount: equipmentCount, consumableDrops: consumableDrops),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C4FCE),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('수령하기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
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
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Text(
            value,
            style: TextStyle(color: valueColor ?? Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
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
  const _LootGrid({required this.equipmentCount, required this.consumableDrops});

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
        for (final MapEntry<ConsumableType, int> entry in consumableDrops.entries)
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
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
