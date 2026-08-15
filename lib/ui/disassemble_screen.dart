import 'package:flutter/material.dart';

import '../managers/equipment_manager.dart';
import '../models/equipment.dart';
import 'character_screen.dart' show InventorySlot;
import 'synthesis_screen.dart' show SynthesisCategory, SynthesisCategoryX;

/// '제작/합성' 화면의 장비/펫 1Depth 탭 안에 얹히는 분해 서브 탭 — 캐릭터
/// 카테고리에는 분해 개념이 없어 CraftingScreen이 그 탭에는 이 위젯 자체를
/// 만들지 않는다. [SynthesisView]와 같은 관례로 Scaffold/AppBar 없이
/// 내용만 그린다 — 장비/펫 어느 카테고리인지는 부모(CraftingScreen의 1Depth
/// 탭)가 [category]로 고정해서 넘겨주므로, 예전 DisassembleScreen처럼 이
/// 위젯 스스로 장비/펫을 다시 고를 필요가 없다.
class DisassembleView extends StatefulWidget {
  const DisassembleView({super.key, required this.category});

  final SynthesisCategory category;

  @override
  State<DisassembleView> createState() => _DisassembleViewState();
}

class _DisassembleViewState extends State<DisassembleView> {
  final EquipmentManager _manager = EquipmentManager.instance;
  final Set<String> _selectedIds = {};

  bool _matchesCategory(Equipment item) => widget.category.matches(item.type);

  void _toggleSelect(Equipment item) {
    setState(() {
      if (!_selectedIds.remove(item.id)) {
        _selectedIds.add(item.id);
      }
    });
  }

  void _disassembleSelected() {
    if (_selectedIds.isEmpty) {
      return;
    }
    final int count = _selectedIds.length;
    final ({int dust, int pawprints}) reward = _manager.disassembleItems(
      _selectedIds.toList(),
    );
    setState(_selectedIds.clear);
    _showSuccessDialog(count: count, dust: reward.dust, pawprints: reward.pawprints);
  }

  /// grade: 'normal'이면 ItemGrade.n, 'advanced'면 ItemGrade.r와 정확히
  /// 일치하는(다른 등급은 절대 섞이지 않는), 현재 카테고리(장비/펫)에
  /// 해당하고 장착 중이 아닌 아이템만 골라 일괄 분해한다.
  void _disassembleByGrade(String grade) {
    final ItemGrade targetGrade = grade == 'normal' ? ItemGrade.n : ItemGrade.r;

    final List<Equipment> targets = _manager.inventory
        .where(
          (item) =>
              item.grade == targetGrade && !item.isEquipped && _matchesCategory(item),
        )
        .toList();

    if (targets.isEmpty) {
      _showNoTargetDialog();
      return;
    }

    final List<String> ids = targets.map((item) => item.id).toList();
    final ({int dust, int pawprints}) reward = _manager.disassembleItems(ids);
    setState(_selectedIds.clear);

    _showSuccessDialog(
      count: targets.length,
      dust: reward.dust,
      pawprints: reward.pawprints,
    );
  }

  /// 현재 카테고리(장비/펫)에 맞는 주어 — 분해 결과/알림 팝업 문구가
  /// 카테고리와 무관하게 항상 "장비"로 고정 출력되던 예전 버그의 근본
  /// 원인이라, 팝업을 띄우는 곳이면 어디든 이 getter를 거쳐야 한다.
  String get _itemTypeName => widget.category == SynthesisCategory.pet ? '펫' : '장비';

  void _showSuccessDialog({
    required int count,
    required int dust,
    required int pawprints,
  }) {
    final String rewardText = pawprints > 0 ? '발바닥 $pawprints개' : '가루 $dust개';
    final String itemTypeName = _itemTypeName;

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1B1B26),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFC9A24B)),
          ),
          title: const Text(
            '✨ 분해 완료!',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            '$itemTypeName $count개를 분해하여 $rewardText를 획득했습니다.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }

  void _showNoTargetDialog() {
    // "펫가"처럼 조사가 깨지지 않도록 두 분기 문장을 통째로 나눈다
    // (장비 → 받침 없음 "가", 펫 → 받침 있음 "이").
    final String message =
        widget.category == SynthesisCategory.pet ? '분해할 펫이 없습니다.' : '분해할 장비가 없습니다.';

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1B1B26),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF3A3A4A)),
          ),
          title: const Text(
            '⚠️ 알림',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            message,
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _manager,
      builder: (context, _) {
        // 인벤토리 그리드/합성 화면과 동일한 규칙(성급→레벨→등급 내림차순)
        // — 성급이 높은 아이템이 항상 앞쪽에 보인다.
        final List<Equipment> inventory = _manager.inventory
            .where((item) => !item.isEquipped && _matchesCategory(item))
            .toList()
          ..sort(Equipment.compareForDisplay);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _selectedIds.isEmpty ? null : _disassembleSelected,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C4FCE),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF3A3A4A),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _selectedIds.isEmpty ? '선택 분해' : '선택 분해 (${_selectedIds.length})',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _disassembleByGrade('normal'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: getGradeColor(ItemGrade.n),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '일반 일괄 분해',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _disassembleByGrade('advanced'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: getGradeColor(ItemGrade.r),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '고급 일괄 분해',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: GridView.builder(
                  itemCount: inventory.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    crossAxisSpacing: 8.0,
                    mainAxisSpacing: 8.0,
                    childAspectRatio: 1.0,
                  ),
                  itemBuilder: (context, index) {
                    final Equipment item = inventory[index];
                    return _DisassembleGridTile(
                      item: item,
                      selected: _selectedIds.contains(item.id),
                      onTap: () => _toggleSelect(item),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}

class _DisassembleGridTile extends StatelessWidget {
  const _DisassembleGridTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final Equipment item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        children: [
          InventorySlot(item: item),
          if (selected)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white, width: 2.5),
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
              ),
            ),
          if (selected)
            const Positioned(
              top: 2,
              right: 2,
              child: Icon(
                Icons.check_circle,
                color: Colors.greenAccent,
                size: 16,
              ),
            ),
        ],
      ),
    );
  }
}
