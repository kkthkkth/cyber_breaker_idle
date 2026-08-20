import 'package:flutter/material.dart';

import '../managers/equipment_manager.dart';
import '../managers/expedition_manager.dart';
import '../models/equipment.dart';
import '../models/expedition_model.dart';
import '../widgets/center_toast.dart';

/// 용병 파견/탐험 화면 — [ExpeditionCatalog.regions]를 카드로 나열하고,
/// 각 지역 상태(미진행/진행 중/완료)에 맞는 버튼을 보여준다.
class ExpeditionScreen extends StatelessWidget {
  const ExpeditionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14141C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B1B26),
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text(
          '탐험',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([ExpeditionManager.instance, EquipmentManager.instance]),
        builder: (context, _) {
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: ExpeditionCatalog.regions.length,
            itemBuilder: (context, index) {
              final ExpeditionRegion region = ExpeditionCatalog.regions[index];
              return _ExpeditionRegionCard(region: region);
            },
          );
        },
      ),
    );
  }
}

class _ExpeditionRegionCard extends StatefulWidget {
  const _ExpeditionRegionCard({required this.region});

  final ExpeditionRegion region;

  @override
  State<_ExpeditionRegionCard> createState() => _ExpeditionRegionCardState();
}

class _ExpeditionRegionCardState extends State<_ExpeditionRegionCard> {
  bool _claiming = false;

  String _formatDuration(Duration duration) {
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${pad(hours)}:${pad(minutes)}:${pad(seconds)}';
  }

  Future<void> _openPicker(BuildContext context) async {
    final List<String>? selectedIds = await showModalBottomSheet<List<String>>(
      context: context,
      backgroundColor: const Color(0xFF1B1B26),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ExpeditionUnitPickerSheet(region: widget.region),
    );
    if (selectedIds == null || !context.mounted) {
      return;
    }
    final bool success = await ExpeditionManager.instance.startExpedition(
      regionId: widget.region.id,
      unitIds: selectedIds,
    );
    if (!context.mounted) {
      return;
    }
    showCenterToast(
      context,
      success ? '${widget.region.name}(으)로 파견대를 보냈습니다!' : '파견대 편성에 실패했습니다.',
    );
  }

  Future<void> _claim(BuildContext context) async {
    if (_claiming) {
      return;
    }
    setState(() => _claiming = true);
    try {
      final List<ExpeditionReward>? rewards =
          await ExpeditionManager.instance.claimReward(widget.region.id);
      if (!context.mounted) {
        return;
      }
      if (rewards == null) {
        showCenterToast(context, '아직 탐험이 끝나지 않았습니다.');
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => _ExpeditionRewardDialog(region: widget.region, rewards: rewards),
      );
    } finally {
      if (mounted) {
        setState(() => _claiming = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ExpeditionRegion region = widget.region;
    final ExpeditionMission? mission = ExpeditionManager.instance.missionFor(region.id);
    final DateTime now = DateTime.now();
    final bool inProgress = mission != null && !mission.isCompleteAt(now);
    final bool complete = mission != null && mission.isCompleteAt(now);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF20202C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: complete
              ? const Color(0xFFC9A24B)
              : (inProgress ? const Color(0xFF6C4FCE) : const Color(0xFF3A3A4A)),
          width: complete || inProgress ? 1.6 : 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  region.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                '소요 시간 ${region.durationLabel}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            region.description,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            '최소 인원 ${region.minUnits}명 · 보상 ${region.rewardsLabel}',
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          if (complete)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _claiming ? null : () => _claim(context),
                icon: const Icon(Icons.emoji_events),
                label: const Text('보상 수령'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC9A24B),
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            )
          else if (inProgress)
            _CountdownRow(
              label: '남은 시간 ${_formatDuration(mission.remainingAt(now))}',
              progress: 1 -
                  (mission.remainingAt(now).inSeconds /
                          (region.duration.inSeconds == 0 ? 1 : region.duration.inSeconds))
                      .clamp(0.0, 1.0),
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openPicker(context),
                icon: const Icon(Icons.groups),
                label: const Text('파견대 편성'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C4FCE),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CountdownRow extends StatelessWidget {
  const _CountdownRow({required this.label, required this.progress});

  final String label;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation(Color(0xFF6C4FCE)),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// 파견 가능한(미장착, 다른 지역에 파견 중이지 않은) 캐릭터/펫을 고르는
/// 바텀 시트 — 요구 최소 인원을 채워야 확정 버튼이 활성화된다.
class _ExpeditionUnitPickerSheet extends StatefulWidget {
  const _ExpeditionUnitPickerSheet({required this.region});

  final ExpeditionRegion region;

  @override
  State<_ExpeditionUnitPickerSheet> createState() => _ExpeditionUnitPickerSheetState();
}

class _ExpeditionUnitPickerSheetState extends State<_ExpeditionUnitPickerSheet> {
  final Set<String> _selectedIds = {};

  List<Equipment> get _eligibleUnits => EquipmentManager.instance.inventory
      .where(
        (item) =>
            !item.isEquipped &&
            (item.type == EquipType.character || item.type == EquipType.pet) &&
            !ExpeditionManager.instance.isUnitDispatched(item.id),
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    final List<Equipment> units = _eligibleUnits;
    final bool canConfirm = _selectedIds.length >= widget.region.minUnits;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.region.name} 파견대 편성',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '최소 ${widget.region.minUnits}명 선택 (${_selectedIds.length}/${widget.region.minUnits})',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 12),
                if (units.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      '파견 보낼 수 있는 캐릭터/펫이 없습니다.\n(미장착 상태여야 하며, 다른 곳에 파견 중이면 안 됩니다)',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                else
                  Flexible(
                    child: GridView.builder(
                      shrinkWrap: true,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.85,
                      ),
                      itemCount: units.length,
                      itemBuilder: (context, index) {
                        final Equipment unit = units[index];
                        final bool selected = _selectedIds.contains(unit.id);
                        return GestureDetector(
                          onTap: () => setState(() {
                            if (selected) {
                              _selectedIds.remove(unit.id);
                            } else {
                              _selectedIds.add(unit.id);
                            }
                          }),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF20202C),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: selected ? const Color(0xFF6C4FCE) : const Color(0xFF3A3A4A),
                                    width: selected ? 2 : 1,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  unit.type == EquipType.pet ? Icons.pets : Icons.person,
                                  color: selected ? const Color(0xFF6C4FCE) : Colors.white54,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                unit.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selected ? Colors.white : Colors.white54,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canConfirm
                        ? () => Navigator.of(context).pop(_selectedIds.toList())
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C4FCE),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF3A3A4A),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('파견 확정', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 보상 수령 결과 팝업 — [CollectionScreen]/[OfflineRewardDialog] 등과
/// 같은 "화려하게 보여주기" 관례(요구사항: "화려한 토스트/다이얼로그").
class _ExpeditionRewardDialog extends StatelessWidget {
  const _ExpeditionRewardDialog({required this.region, required this.rewards});

  final ExpeditionRegion region;
  final List<ExpeditionReward> rewards;

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
          border: Border.all(color: const Color(0xFFC9A24B), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFC9A24B).withValues(alpha: 0.5),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events, color: Color(0xFFC9A24B), size: 48),
            const SizedBox(height: 12),
            Text(
              '${region.name} 탐험 완료!',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            for (final ExpeditionReward reward in rewards)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  reward.displayText,
                  style: const TextStyle(
                    color: Colors.amberAccent,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const SizedBox(height: 20),
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
                child: const Text('확인', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
