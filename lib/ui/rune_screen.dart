import 'package:flutter/material.dart';

import '../managers/rune_manager.dart';
import '../models/rune_model.dart';
import '../widgets/center_toast.dart';

/// 룬 인벤토리/장착/레벨업/합성 화면 — 상단에 장착 슬롯 현황과 룬 조각
/// 보유량 + 색깔별 제작 버튼, 아래에 보유 룬 그리드를 보여준다. 합성은
/// 별도 모드(우측 상단 토글)로 들어가 같은 색·같은 레벨 룬 2개를 순서대로
/// 탭하면 즉시 실행된다.
class RuneScreen extends StatefulWidget {
  const RuneScreen({super.key});

  @override
  State<RuneScreen> createState() => _RuneScreenState();
}

class _RuneScreenState extends State<RuneScreen> {
  bool _synthesizeMode = false;
  String? _selectedForSynthesis;

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _craft(RuneType type) {
    final Rune? rune = RuneManager.instance.craftRune(type);
    if (rune == null) {
      _showSnackBar('룬 조각이 부족합니다');
      return;
    }
    showCenterToast(context, '${type.displayName} 룬(${RuneStat.displayName(rune.statKey)}) 획득!');
  }

  void _onTapRune(Rune rune) {
    if (_synthesizeMode) {
      _handleSynthesisTap(rune);
      return;
    }
    showDialog<void>(context: context, builder: (context) => _RuneDetailDialog(rune: rune));
  }

  void _handleSynthesisTap(Rune rune) {
    if (_selectedForSynthesis == null) {
      setState(() => _selectedForSynthesis = rune.id);
      return;
    }
    if (_selectedForSynthesis == rune.id) {
      setState(() => _selectedForSynthesis = null);
      return;
    }

    final Rune? result = RuneManager.instance.synthesize(_selectedForSynthesis!, rune.id);
    setState(() => _selectedForSynthesis = null);
    if (result == null) {
      _showSnackBar('같은 색·같은 레벨의 룬 2개만 합성할 수 있습니다');
      return;
    }
    showCenterToast(
      context,
      '${result.type.displayName} 룬(Lv.${result.level}) 합성 성공!',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: RuneManager.instance,
      builder: (context, _) {
        final RuneManager manager = RuneManager.instance;

        return Scaffold(
          backgroundColor: const Color(0xFF14141C),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1B1B26),
            elevation: 0,
            foregroundColor: Colors.white,
            centerTitle: true,
            title: const Text('룬', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            actions: [
              TextButton.icon(
                onPressed: () => setState(() {
                  _synthesizeMode = !_synthesizeMode;
                  _selectedForSynthesis = null;
                }),
                icon: Icon(
                  Icons.auto_fix_high,
                  color: _synthesizeMode ? Colors.amberAccent : Colors.white70,
                ),
                label: Text(
                  _synthesizeMode ? '합성 중' : '합성',
                  style: TextStyle(color: _synthesizeMode ? Colors.amberAccent : Colors.white70),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF20202C),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF3A3A4A)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '장착 슬롯 ${manager.equippedRunes.length}/${RuneManager.maxSlots}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Row(
                            children: [
                              const Icon(Icons.diamond, color: Colors.tealAccent, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                '룬 조각 ${manager.runeFragments}',
                                style: const TextStyle(
                                  color: Colors.tealAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (final RuneType type in RuneType.values) ...[
                            if (type != RuneType.values.first) const SizedBox(width: 8),
                            Expanded(child: _CraftButton(type: type, onTap: () => _craft(type))),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (_synthesizeMode)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    _selectedForSynthesis == null
                        ? '합성할 첫 번째 룬을 선택하세요(같은 색·같은 레벨끼리만 가능)'
                        : '합성할 두 번째 룬을 선택하세요',
                    style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
                  ),
                ),
              Expanded(
                child: manager.runes.isEmpty
                    ? const Center(
                        child: Text('보유한 룬이 없어요. 위 버튼으로 첫 룬을 만들어 보세요!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white54)),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: manager.runes.length,
                        itemBuilder: (context, index) {
                          final Rune rune = manager.runes[index];
                          return _RuneTile(
                            rune: rune,
                            selected: _selectedForSynthesis == rune.id,
                            onTap: () => _onTapRune(rune),
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

class _CraftButton extends StatelessWidget {
  const _CraftButton({required this.type, required this.onTap});

  final RuneType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: type.color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: type.color),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hexagon, color: type.color, size: 18),
            const SizedBox(height: 2),
            Text(
              type.displayName,
              style: TextStyle(color: type.color, fontSize: 11, fontWeight: FontWeight.bold),
            ),
            Text(
              '${RuneManager.craftCostFragments} 조각',
              style: const TextStyle(color: Colors.white54, fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuneTile extends StatelessWidget {
  const _RuneTile({required this.rune, required this.selected, required this.onTap});

  final Rune rune;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: rune.isEquipped
              ? rune.type.color.withValues(alpha: 0.22)
              : const Color(0xFF20202C),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.amberAccent : rune.type.color,
            width: selected ? 2.5 : (rune.isEquipped ? 2 : 1.2),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hexagon, color: rune.type.color, size: 26),
            const SizedBox(height: 4),
            Text(
              RuneStat.displayName(rune.statKey),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              'Lv.${rune.level}',
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
            if (rune.isEquipped)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text(
                  '장착중',
                  style: TextStyle(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RuneDetailDialog extends StatelessWidget {
  const _RuneDetailDialog({required this.rune});

  final Rune rune;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1B1B26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.hexagon, color: rune.type.color),
          const SizedBox(width: 8),
          Text(
            '${rune.type.displayName} 룬',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${RuneStat.displayName(rune.statKey)} +${(rune.value * 100).toStringAsFixed(1)}%',
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            rune.isMaxLevel
                ? '레벨 ${rune.level} (MAX)'
                : '레벨 ${rune.level} → 다음 레벨 ${rune.nextLevelFragmentCost} 조각 필요',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
        if (!rune.isMaxLevel)
          TextButton(
            onPressed: () {
              final bool success = RuneManager.instance.levelUp(rune.id);
              Navigator.of(context).pop();
              if (!success) {
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(const SnackBar(content: Text('룬 조각이 부족합니다')));
              }
            },
            child: const Text('레벨업'),
          ),
        ElevatedButton(
          onPressed: () {
            final RuneManager manager = RuneManager.instance;
            if (rune.isEquipped) {
              manager.unequip(rune.id);
            } else {
              final Set<int> used =
                  manager.equippedRunes.map((r) => r.equippedSlot).whereType<int>().toSet();
              int? freeSlot;
              for (int i = 0; i < RuneManager.maxSlots; i++) {
                if (!used.contains(i)) {
                  freeSlot = i;
                  break;
                }
              }
              if (freeSlot == null) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(const SnackBar(content: Text('장착 슬롯이 가득 찼습니다')));
                return;
              }
              manager.equip(rune.id, freeSlot);
            }
            Navigator.of(context).pop();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: rune.isEquipped ? Colors.redAccent : const Color(0xFF6C4FCE),
            foregroundColor: Colors.white,
          ),
          child: Text(rune.isEquipped ? '해제' : '장착'),
        ),
      ],
    );
  }
}
