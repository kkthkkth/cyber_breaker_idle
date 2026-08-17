import 'package:flutter/material.dart';

import '../managers/dispatch_manager.dart';
import '../managers/equipment_manager.dart';
import '../models/consumable_item_model.dart';
import '../models/dispatch_model.dart';
import '../models/equipment.dart';
import '../widgets/center_toast.dart';
import '../widgets/character_face_portrait.dart';

/// 파견(아르바이트) 화면 — [DispatchManager.maxSlots]개의 슬롯에 각각
/// 최대 [DispatchManager.maxCharactersPerMission]명의 "잉여 캐릭터"(장착
/// 중이 아니고 다른 슬롯에도 편성돼 있지 않은 캐릭터)를 편성해 2/4/8시간
/// 임무를 보내고, 완료되면 골드/경험치/호감도 선물 아이템을 정산받는다.
///
/// 상태는 전부 [DispatchManager]/[EquipmentManager] 싱글턴이 들고 있고,
/// 이 화면은 [AnimatedBuilder]로 구독만 한다 — 프로젝트 전체가 Provider
/// 없이 이 패턴을 쓴다.
class DispatchScreen extends StatefulWidget {
  const DispatchScreen({super.key});

  @override
  State<DispatchScreen> createState() => _DispatchScreenState();
}

class _DispatchScreenState extends State<DispatchScreen> {
  final DispatchManager _manager = DispatchManager.instance;

  /// 슬롯별 "수령하기" 처리 중 잠금 — 연타로 같은 슬롯을 두 번 정산하는
  /// 것을 막는다([AffectionScreen]의 `_isGiftInFlight` 등과 같은 패턴).
  final Set<int> _claimingSlots = {};

  /// 편성 다이얼로그 진입 처리 중 잠금 — 슬롯 버튼을 연타해도 편성
  /// 다이얼로그가 여러 장 겹쳐 뜨지 않게 한다.
  bool _isOpeningPicker = false;

  Future<void> _openPicker(int slotIndex) async {
    if (_isOpeningPicker) {
      return;
    }
    setState(() => _isOpeningPicker = true);
    try {
      final _DispatchOrder? order = await showModalBottomSheet<_DispatchOrder>(
        context: context,
        backgroundColor: const Color(0xFF1B1B26),
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => _DispatchPickerSheet(slotIndex: slotIndex),
      );
      if (order == null || !mounted) {
        return;
      }

      final bool success = await _manager.startDispatch(
        slotIndex: order.slotIndex,
        characterIds: order.characterIds,
        duration: order.duration,
      );
      if (!mounted) {
        return;
      }
      if (!success) {
        showCenterToast(context, '파견을 시작할 수 없어요. 편성을 다시 확인해 주세요.');
        return;
      }
      showCenterToast(context, '파견을 시작했어요!');
    } finally {
      if (mounted) {
        setState(() => _isOpeningPicker = false);
      } else {
        _isOpeningPicker = false;
      }
    }
  }

  Future<void> _claim(int slotIndex) async {
    if (_claimingSlots.contains(slotIndex)) {
      return;
    }
    setState(() => _claimingSlots.add(slotIndex));
    try {
      final DispatchRewardResult? result = await _manager.claimReward(slotIndex);
      if (!mounted || result == null) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => _DispatchRewardDialog(result: result),
      );
    } finally {
      if (mounted) {
        setState(() => _claimingSlots.remove(slotIndex));
      } else {
        _claimingSlots.remove(slotIndex);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14141C),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('파견', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _manager,
          builder: (context, _) {
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: DispatchManager.maxSlots,
              separatorBuilder: (context, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _DispatchSlotCard(
                slotIndex: index,
                mission: _manager.missions[index],
                isClaiming: _claimingSlots.contains(index),
                onStart: () => _openPicker(index),
                onClaim: () => _claim(index),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 슬롯 한 칸 — 비어 있음/진행 중/완료(수령 대기) 세 상태를 표현한다.
class _DispatchSlotCard extends StatelessWidget {
  const _DispatchSlotCard({
    required this.slotIndex,
    required this.mission,
    required this.isClaiming,
    required this.onStart,
    required this.onClaim,
  });

  final int slotIndex;
  final DispatchMission? mission;
  final bool isClaiming;
  final VoidCallback onStart;
  final VoidCallback onClaim;

  String _formatRemaining(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final int hours = d.inHours;
    final int minutes = d.inMinutes % 60;
    final int seconds = d.inSeconds % 60;
    return '${two(hours)}:${two(minutes)}:${two(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    final DispatchMission? mission = this.mission;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: mission == null ? const Color(0xFF3A3A4A) : const Color(0xFF6C4FCE),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: mission == null
                ? Text(
                    '파견처 ${slotIndex + 1} — 대기 중',
                    style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          for (final String characterId in mission.characterIds)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: CharacterFacePortrait(
                                characterId: characterId,
                                size: 36,
                                borderRadius: 8,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${mission.duration.displayName} 임무',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        mission.isComplete ? '임무 완료!' : _formatRemaining(mission.remaining),
                        style: TextStyle(
                          color: mission.isComplete ? Colors.amberAccent : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 10),
          if (mission == null)
            ElevatedButton(
              onPressed: onStart,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C4FCE),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('편성하기'),
            )
          else if (mission.isComplete)
            ElevatedButton(
              onPressed: isClaiming ? null : onClaim,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE0B84D),
                foregroundColor: Colors.black87,
                disabledBackgroundColor: Colors.black45,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('수령하기'),
            )
          else
            const Icon(Icons.hourglass_bottom, color: Colors.white38),
        ],
      ),
    );
  }
}

/// [_DispatchPickerSheet]가 확정 시 돌려주는, 시작할 파견의 편성 내용.
class _DispatchOrder {
  const _DispatchOrder({
    required this.slotIndex,
    required this.characterIds,
    required this.duration,
  });

  final int slotIndex;
  final List<String> characterIds;
  final DispatchDuration duration;
}

/// 캐릭터 선택(최대 3명) + 시간 선택 바텀시트 — 확정하면 [_DispatchOrder]로
/// pop하고, 실제 [DispatchManager.startDispatch] 호출은 호출부
/// ([_DispatchScreenState._openPicker])가 맡는다(이 위젯은 순수하게 편성
/// 입력만 담당).
class _DispatchPickerSheet extends StatefulWidget {
  const _DispatchPickerSheet({required this.slotIndex});

  final int slotIndex;

  @override
  State<_DispatchPickerSheet> createState() => _DispatchPickerSheetState();
}

class _DispatchPickerSheetState extends State<_DispatchPickerSheet> {
  final Set<String> _selected = {};
  DispatchDuration _duration = DispatchDuration.twoHours;

  List<Equipment> get _availableCharacters {
    return EquipmentManager.instance.inventory.where((item) {
      if (item.type != EquipType.character || item.isEquipped) {
        return false;
      }
      final String characterId = item.gradeBadgeLabel;
      // 이미 다른 파견 슬롯에 나가 있는 캐릭터는 후보에서 제외 — 지금
      // 편성 중인 이 슬롯 자체는 아직 비어 있는 상태이므로 걸릴 일이 없다.
      return !DispatchManager.instance.isCharacterDispatched(characterId);
    }).toList();
  }

  void _toggle(String characterId) {
    setState(() {
      if (_selected.contains(characterId)) {
        _selected.remove(characterId);
      } else if (_selected.length < DispatchManager.maxCharactersPerMission) {
        _selected.add(characterId);
      } else {
        showCenterToast(
          context,
          '최대 ${DispatchManager.maxCharactersPerMission}명까지 편성할 수 있어요.',
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Equipment> candidates = _availableCharacters;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '파견처 ${widget.slotIndex + 1} 편성',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '잉여 캐릭터 최대 ${DispatchManager.maxCharactersPerMission}명 선택'
            ' (${_selected.length}/${DispatchManager.maxCharactersPerMission})',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: candidates.isEmpty
                ? const Center(
                    child: Text(
                      '편성 가능한 잉여 캐릭터가 없어요.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1,
                    ),
                    itemCount: candidates.length,
                    itemBuilder: (context, index) {
                      final Equipment character = candidates[index];
                      final String characterId = character.gradeBadgeLabel;
                      final bool selected = _selected.contains(characterId);
                      return InkWell(
                        onTap: () => _toggle(characterId),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected ? const Color(0xFF6C4FCE) : Colors.white24,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CharacterFacePortrait(characterId: characterId, borderRadius: 9),
                              if (selected)
                                const Positioned(
                                  top: 2,
                                  right: 2,
                                  child: Icon(
                                    Icons.check_circle,
                                    color: Color(0xFF6C4FCE),
                                    size: 16,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),
          const Text('파견 시간', style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final DispatchDuration duration in DispatchDuration.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(duration.displayName),
                    selected: _duration == duration,
                    onSelected: (_) => setState(() => _duration = duration),
                    selectedColor: const Color(0xFF6C4FCE),
                    labelStyle: TextStyle(
                      color: _duration == duration ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.bold,
                    ),
                    backgroundColor: const Color(0xFF20202C),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(
                      _DispatchOrder(
                        slotIndex: widget.slotIndex,
                        characterIds: _selected.toList(),
                        duration: _duration,
                      ),
                    ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C4FCE),
                disabledBackgroundColor: Colors.black45,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('파견 보내기', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 파견 정산 결과 팝업 — 골드/경험치/호감도 선물 아이템 드롭을 보여준다.
class _DispatchRewardDialog extends StatelessWidget {
  const _DispatchRewardDialog({required this.result});

  final DispatchRewardResult result;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1B1B26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.card_travel, color: Color(0xFFE0B84D), size: 32),
            const SizedBox(height: 10),
            const Text(
              '파견 완료!',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            _RewardRow(icon: Icons.monetization_on, color: Colors.amberAccent, label: '골드', value: '+${result.gold}'),
            const SizedBox(height: 6),
            _RewardRow(icon: Icons.star, color: Colors.lightBlueAccent, label: '경험치', value: '+${result.exp}'),
            if (result.giftItems.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: [
                  for (final ConsumableType type in result.giftItems)
                    Chip(
                      avatar: Icon(type.icon, size: 16, color: const Color(0xFFFF6FA5)),
                      label: Text(type.displayName),
                      backgroundColor: const Color(0xFF20202C),
                      labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C4FCE),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('확인'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RewardRow extends StatelessWidget {
  const _RewardRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white70)),
        const SizedBox(width: 8),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
