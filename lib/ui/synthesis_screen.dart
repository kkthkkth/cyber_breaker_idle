import 'dart:async';

import 'package:flutter/material.dart';

import '../managers/equipment_manager.dart';
import '../models/equipment.dart';
import '../widgets/center_toast.dart';
import 'character_screen.dart' show InventorySlot;
import 'item_result_dialog.dart';

/// '합성' 탭 2Depth 서브 탭 — 장비/캐릭터/펫 중 어떤 [EquipType]들을
/// 이 카테고리로 볼지는 [SynthesisCategoryX.matches]가 결정한다.
enum SynthesisCategory { equipment, character, pet }

extension SynthesisCategoryX on SynthesisCategory {
  String get label {
    switch (this) {
      case SynthesisCategory.equipment:
        return '장비';
      case SynthesisCategory.character:
        return '캐릭터';
      case SynthesisCategory.pet:
        return '펫';
    }
  }

  bool matches(EquipType type) {
    switch (this) {
      case SynthesisCategory.character:
        return type == EquipType.character;
      case SynthesisCategory.pet:
        return type == EquipType.pet;
      case SynthesisCategory.equipment:
        // 휘장(EquipType.badge)은 길드 전쟁 승리로만 지급되는 기간제
        // 아이템이라 강화/분해/합성이 전부 불가능해야 한다 — "그 외 전부"
        // 캐치올에 걸려 들어오지 않도록 명시적으로 제외한다.
        return type != EquipType.character && type != EquipType.pet && type != EquipType.badge;
    }
  }
}

class _SynthesisGroup {
  _SynthesisGroup({
    required this.type,
    required this.grade,
    required this.subId,
    required this.star,
    required this.items,
  });

  final EquipType type;
  final ItemGrade grade;
  final int subId;
  final int star;
  final List<Equipment> items;

  int get count => items.length;

  int get requiredCount => EquipmentManager.materialCountForStarUp(star);

  bool get canSynthesize => star < Equipment.maxStar && count >= requiredCount;

  String get gradeBadgeLabel => '${grade.displayName}$subId';
}

/// Embeddable synthesis UI — no [Scaffold]/[AppBar] of its own, so it can be
/// swapped in as a screen's body. [category]는 상위 CraftingScreen의 2Depth
/// 서브 탭(장비/캐릭터/펫)에서 전달되며, 해당 타입의 만렙(Lv.50) 아이템만
/// 합성 후보로 다룬다.
class SynthesisView extends StatefulWidget {
  const SynthesisView({super.key, required this.category});

  final SynthesisCategory category;

  @override
  State<SynthesisView> createState() => _SynthesisViewState();
}

class _SynthesisViewState extends State<SynthesisView> {
  final EquipmentManager _manager = EquipmentManager.instance;
  _SynthesisGroup? _selectedGroup;

  /// 만렙(Lv.50)이면서 현재 카테고리에 해당하는 아이템만 (type, grade,
  /// subId, star)로 묶는다 — 별 진화 조건 자체가 "만렙 동일 아이템"이라,
  /// 레벨이 덜 찬 아이템은 애초에 이 목록에 나타나지 않는다. 장착 중인
  /// 아이템도 후보에서 제외하지 않는다 — 장착 중인 게 재료로 쓰이면
  /// [EquipmentManager.synthesizeGroup]이 합성 결과물을 그 슬롯에 자동으로
  /// 다시 장착해 준다.
  List<_SynthesisGroup> _buildGroups() {
    final Map<String, _SynthesisGroup> map = {};
    for (final Equipment item in _manager.inventory.where(
      (e) => e.isMaxLevel && widget.category.matches(e.type),
    )) {
      final String key = '${item.type.name}_${item.grade.name}_${item.subId}_${item.star}';
      map
          .putIfAbsent(
            key,
            () => _SynthesisGroup(
              type: item.type,
              grade: item.grade,
              subId: item.subId,
              star: item.star,
              items: [],
            ),
          )
          .items
          .add(item);
    }

    // 인벤토리 그리드/분해 화면과 같은 우선순위(성급→등급 내림차순)를 쓴다
    // — 이 목록의 모든 아이템은 항상 만렙(Lv.50)이라 레벨 자체는 그룹을
    // 나눠주지 않으므로([Equipment.compareForDisplay]의 2순위가 여기선
    // 무의미), 성급이 최상위 기준이 되고 그다음이 등급이다. subId(같은
    // 등급 내 캐릭터/장비 종류 번호)는 요구사항에 없는 별개의 축이라 두
    // 기준 다음 순서를 그대로 유지한다.
    final List<_SynthesisGroup> groups = map.values.toList()
      ..sort((a, b) {
        final int starCompare = b.star.compareTo(a.star);
        if (starCompare != 0) {
          return starCompare;
        }
        final int gradeCompare = b.grade.index.compareTo(a.grade.index);
        return gradeCompare != 0 ? gradeCompare : a.subId.compareTo(b.subId);
      });
    return groups;
  }

  void _selectGroup(_SynthesisGroup group) {
    setState(() => _selectedGroup = group);
  }

  /// 재료/골드는 이미 이 시점에 확정 소모되지만(합성 자체는 즉시 처리되는
  /// 동기 연산이라), 결과는 곧바로 보여주지 않고 [_playSynthesisEffect]가
  /// 화면을 덮은 채로 ~1.2초 재생된 뒤에야 결과 다이얼로그를 띄운다 —
  /// 오버레이가 화면을 완전히 가리므로 유저 입장에서는 "합성 중..." 연출이
  /// 끝난 뒤에야 결과가 정해지는 것처럼 자연스럽게 보인다.
  Future<void> _synthesizeSelected() async {
    final _SynthesisGroup? group = _selectedGroup;
    if (group == null) {
      return;
    }

    final Equipment? result =
        _manager.synthesizeGroup(group.type, group.grade, group.subId, group.star);
    if (result == null) {
      showCenterToast(context, '만렙(Lv.50) 아이템 및 재료 수량이 부족합니다.');
      return;
    }

    setState(() => _selectedGroup = null);
    await _playSynthesisEffect();
    if (!mounted) {
      return;
    }
    _showResultDialog([result]);
  }

  Future<void> _autoSynthesizeAll() async {
    final List<Equipment> results = _manager.autoSynthesizeAll();
    if (results.isEmpty) {
      showCenterToast(context, '합성 가능한 아이템이 없습니다');
      return;
    }

    setState(() => _selectedGroup = null);
    await _playSynthesisEffect();
    if (!mounted) {
      return;
    }
    _showResultDialog(results);
  }

  /// 회전하는 마법진 + 반짝이는 스케일 펄스와 "합성 중..." 텍스트를 약
  /// 1.2초간 보여주는 모달 — [_SynthesisEffectOverlay]가 시간이 다 되면
  /// 스스로 [Navigator.pop]하므로, 반환된 Future가 바로 그 완료 신호다.
  /// barrierDismissible이 false라 탭해서 건너뛸 수 없다(결과가 바로 툭
  /// 뜨던 예전 동작으로 되돌아가는 걸 막는다).
  Future<void> _playSynthesisEffect() {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (context) => const _SynthesisEffectOverlay(),
    );
  }

  void _showResultDialog(List<Equipment> results) {
    showDialog<void>(
      context: context,
      builder: (context) => ItemResultDialog(title: '합성 결과', results: results),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _manager,
      builder: (context, _) {
        final List<_SynthesisGroup> groups = _buildGroups();

        _SynthesisGroup? selected;
        if (_selectedGroup != null) {
          for (final _SynthesisGroup group in groups) {
            if (group.type == _selectedGroup!.type &&
                group.grade == _selectedGroup!.grade &&
                group.subId == _selectedGroup!.subId &&
                group.star == _selectedGroup!.star) {
              selected = group;
              break;
            }
          }
        }

        return Container(
          color: const Color(0xFF14141C),
          child: Stack(
            children: [
              SingleChildScrollView(
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Text(
                        'Lv.50(만렙) 아이템만 합성 후보로 표시됩니다.',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ),
                    _ForgeArea(
                      group: selected,
                      onSynthesize: _synthesizeSelected,
                    ),
                    _InventoryGrid(
                      groups: groups,
                      selected: selected,
                      onSelect: _selectGroup,
                    ),
                    const SizedBox(height: 90),
                  ],
                ),
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton.extended(
                  onPressed: _autoSynthesizeAll,
                  backgroundColor: const Color(0xFF6C4FCE),
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('일괄 합성'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 합성 버튼을 누른 직후, 결과 다이얼로그가 뜨기 전 약 1.2초간 재생되는
/// 연출 — 회전하는 마법진 아이콘 위에 반짝이는 스케일 펄스를 얹고
/// "합성 중..." 텍스트를 곁들인다. 정해진 시간이 지나면 스스로
/// [Navigator.pop]해서, 이 다이얼로그를 띄운 [showDialog]의 Future가 곧
/// "연출이 끝났다"는 신호가 되도록 한다([_SynthesisViewState._playSynthesisEffect]
/// 참고) — 별도의 완료 콜백을 따로 두지 않아도 된다.
class _SynthesisEffectOverlay extends StatefulWidget {
  const _SynthesisEffectOverlay();

  @override
  State<_SynthesisEffectOverlay> createState() => _SynthesisEffectOverlayState();
}

class _SynthesisEffectOverlayState extends State<_SynthesisEffectOverlay>
    with TickerProviderStateMixin {
  static const Duration _visibleDuration = Duration(milliseconds: 1200);

  late final AnimationController _rotationController;
  late final AnimationController _pulseController;
  Timer? _closeTimer;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
    _closeTimer = Timer(_visibleDuration, () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _rotationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // barrierDismissible: false(showDialog 호출부)만으로 바깥 탭은 이미
    // 막힌다. 여기에 PopScope(canPop: false)까지 더하면 하드웨어 뒤로가기는
    // 막을 수 있지만, `canPop: false`인 라우트는 [_closeTimer]가 부르는
    // Navigator.pop()마저(프로그램적 호출이라 exempt일 거라 예상했지만
    // 실제로는 아니었다) 함께 막아버려 연출이 영원히 안 닫히는 버그가
    // 났었다 — 그래서 여기서는 일부러 PopScope를 쓰지 않는다.
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RotationTransition(
            turns: _rotationController,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.85, end: 1.15).animate(
                CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Color(0xFFFFD700),
                size: 96,
                shadows: [Shadow(color: Colors.orangeAccent, blurRadius: 24)],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '합성 중...',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
              shadows: [Shadow(color: Colors.black, blurRadius: 6)],
            ),
          ),
        ],
      ),
    );
  }
}

class _ForgeArea extends StatelessWidget {
  const _ForgeArea({required this.group, required this.onSynthesize});

  final _SynthesisGroup? group;
  final VoidCallback onSynthesize;

  @override
  Widget build(BuildContext context) {
    final _SynthesisGroup? selectedGroup = group;
    final bool isMaxStar = selectedGroup != null && selectedGroup.star >= Equipment.maxStar;
    final bool canSynthesize = selectedGroup != null && selectedGroup.canSynthesize;
    final int slotCount = selectedGroup?.requiredCount ?? 3;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3A2412), Color(0xFF1B1208)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFB0703A), width: 1.5),
      ),
      child: Column(
        children: [
          const Icon(Icons.local_fire_department, color: Colors.deepOrangeAccent, size: 40),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(slotCount, (index) {
              // Only the first `count` slots show the item — the rest stay
              // empty, so the row visually tracks how many copies are held.
              final bool slotFilled = selectedGroup != null && index < selectedGroup.count;
              return Padding(
                padding: EdgeInsets.only(left: index == 0 ? 0 : 8.0),
                child: _ForgeSlot(group: slotFilled ? selectedGroup : null),
              );
            }),
          ),
          const SizedBox(height: 14),
          Text(
            selectedGroup == null
                ? '합성할 만렙(Lv.50) 아이템을 선택하세요'
                : '${selectedGroup.gradeBadgeLabel} ★${selectedGroup.star} ${selectedGroup.type.displayName}  '
                    '${selectedGroup.count}/${selectedGroup.requiredCount}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selectedGroup == null ? Colors.white54 : getGradeColor(selectedGroup.grade),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: canSynthesize ? onSynthesize : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB0703A),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF3A3A4A),
              disabledForegroundColor: Colors.white54,
            ),
            child: Text(isMaxStar ? '최고 등급입니다' : '합성하기 (★${(selectedGroup?.star ?? 0) + 1})'),
          ),
        ],
      ),
    );
  }
}

class _ForgeSlot extends StatelessWidget {
  const _ForgeSlot({required this.group});

  final _SynthesisGroup? group;

  @override
  Widget build(BuildContext context) {
    final bool filled = group != null;
    final Color color = filled ? getGradeColor(group!.grade) : const Color(0xFF4A3826);

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.25) : const Color(0xFF241A10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: 1.5),
      ),
      child: filled
          ? Icon(Icons.shield, color: color, size: 20)
          : const Icon(Icons.add, color: Colors.white24, size: 16),
    );
  }
}

class _InventoryGrid extends StatelessWidget {
  const _InventoryGrid({required this.groups, required this.selected, required this.onSelect});

  final List<_SynthesisGroup> groups;
  final _SynthesisGroup? selected;
  final ValueChanged<_SynthesisGroup> onSelect;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text('합성 가능한 만렙(Lv.50) 아이템이 없습니다', style: TextStyle(color: Colors.white54)),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: groups.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        crossAxisSpacing: 8.0,
        mainAxisSpacing: 8.0,
        childAspectRatio: 1.0,
      ),
      itemBuilder: (context, index) {
        final _SynthesisGroup group = groups[index];
        final bool isSelected = selected != null &&
            selected!.type == group.type &&
            selected!.grade == group.grade &&
            selected!.subId == group.subId &&
            selected!.star == group.star;
        return _SynthesisGridTile(
          group: group,
          selected: isSelected,
          onTap: () => onSelect(group),
        );
      },
    );
  }
}

class _SynthesisGridTile extends StatelessWidget {
  const _SynthesisGridTile({required this.group, required this.selected, required this.onTap});

  final _SynthesisGroup group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Reuse the exact same card widget the character screen renders, so the
    // two grids are pixel-identical — the count badge/selection ring/synth
    // dot are layered on top rather than reimplemented.
    final Equipment sample = group.items.first;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InventorySlot(item: sample),
          if (selected)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 2,
            bottom: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'x${group.count}',
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          if (group.canSynthesize)
            Positioned(
              top: -3,
              right: -3,
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
              ),
            ),
        ],
      ),
    );
  }
}
