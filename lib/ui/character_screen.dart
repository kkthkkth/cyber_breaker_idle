import 'package:flutter/material.dart';

import '../managers/equipment_manager.dart';
import '../managers/game_manager.dart';
import '../models/equipment.dart';

class CharacterScreen extends StatefulWidget {
  const CharacterScreen({super.key});

  @override
  State<CharacterScreen> createState() => _CharacterScreenState();
}

class _CharacterScreenState extends State<CharacterScreen> {
  final EquipmentManager _manager = EquipmentManager.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14141C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B1B26),
        elevation: 0,
        title: const Text(
          '캐릭터',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: AnimatedBuilder(
        animation: _manager,
        builder: (context, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                SizedBox(
                  height: 230,
                  child: EquipArea(
                    equippedItems: _manager.equippedItems,
                    onUnequip: _manager.unequipItem,
                  ),
                ),
                const SizedBox(
                  height: 140,
                  child: StatPanel(),
                ),
                InventoryArea(
                  inventory: _manager.inventory
                      .where((item) => !item.isEquipped)
                      .toList(),
                  onSlotTap: _manager.equipItem,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EquipSlotInfo {
  const _EquipSlotInfo(this.type, this.label, this.icon);

  final EquipType type;
  final String label;
  final IconData icon;
}

const List<_EquipSlotInfo> _leftEquipSlots = [
  _EquipSlotInfo(EquipType.weapon, '무기', Icons.gavel),
  _EquipSlotInfo(EquipType.helmet, '투구', Icons.sports_motorsports),
  _EquipSlotInfo(EquipType.armor, '갑옷', Icons.shield_moon),
];

const List<_EquipSlotInfo> _rightEquipSlots = [
  _EquipSlotInfo(EquipType.shield, '방패', Icons.security),
  _EquipSlotInfo(EquipType.boots, '신발', Icons.directions_walk),
  _EquipSlotInfo(EquipType.ring, '반지', Icons.circle_outlined),
];

class EquipArea extends StatelessWidget {
  const EquipArea({
    super.key,
    required this.equippedItems,
    required this.onUnequip,
  });

  final Map<EquipType, Equipment?> equippedItems;
  final ValueChanged<EquipType> onUnequip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _leftEquipSlots.map((info) {
              return EquipSlot(
                label: info.label,
                icon: info.icon,
                item: equippedItems[info.type],
                onTap: () => onUnequip(info.type),
              );
            }).toList(),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF3D2C6D),
                    Color(0xFF241C40),
                  ],
                ),
                border: Border.all(color: const Color(0xFF6C4FCE), width: 1.5),
              ),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.person,
                      size: 96,
                      color: Colors.white70,
                    ),
                    SizedBox(height: 8),
                    Text(
                      '캐릭터 이미지',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _rightEquipSlots.map((info) {
              return EquipSlot(
                label: info.label,
                icon: info.icon,
                item: equippedItems[info.type],
                onTap: () => onUnequip(info.type),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class EquipSlot extends StatelessWidget {
  const EquipSlot({
    super.key,
    required this.label,
    required this.icon,
    this.item,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Equipment? item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Equipment? equipped = item;
    final bool hasItem = equipped != null;
    final Color gradeColor =
        hasItem ? getGradeColor(equipped.grade) : const Color(0xFF3A3A4A);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 64,
        height: 64,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: hasItem
              ? gradeColor.withValues(alpha: 0.25)
              : const Color(0xFF20202C),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: gradeColor, width: hasItem ? 1.5 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: hasItem ? gradeColor : Colors.white70, size: 22),
            const SizedBox(height: 4),
            Text(
              hasItem ? equipped.grade.displayName : label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: hasItem ? gradeColor : Colors.white54,
                fontSize: 10,
                fontWeight: hasItem ? FontWeight.bold : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class StatPanel extends StatelessWidget {
  const StatPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final GameManager manager = GameManager.instance;

    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF24242E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF34344A), width: 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _StatItem(
                      label: '총 공격력',
                      value: manager.attackPower.toStringAsFixed(0),
                      icon: Icons.local_fire_department,
                      color: Colors.orangeAccent,
                    ),
                  ),
                  Expanded(
                    child: _StatItem(
                      label: '공격 속도',
                      value: '${manager.attackSpeed.toStringAsFixed(2)}/s',
                      icon: Icons.bolt,
                      color: Colors.lightBlueAccent,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: _StatItem(
                      label: '크리티컬 확률',
                      value:
                          '${(manager.criticalRate * 100).toStringAsFixed(0)}%',
                      icon: Icons.flash_on,
                      color: Colors.yellowAccent,
                    ),
                  ),
                  Expanded(
                    child: _StatItem(
                      label: '크리티컬 데미지',
                      value:
                          '${(manager.criticalMultiplier * 100).toStringAsFixed(0)}%',
                      icon: Icons.whatshot,
                      color: Colors.redAccent,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class InventoryArea extends StatelessWidget {
  const InventoryArea({
    super.key,
    required this.inventory,
    this.onSlotTap,
  });

  final List<Equipment> inventory;
  final ValueChanged<Equipment>? onSlotTap;

  static const int _minSlotCount = 20;

  @override
  Widget build(BuildContext context) {
    final int totalSlots =
        inventory.length > _minSlotCount ? inventory.length : _minSlotCount;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF1B1B26),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: GridView.builder(
        itemCount: totalSlots,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1,
        ),
        itemBuilder: (context, index) {
          final Equipment? item =
              index < inventory.length ? inventory[index] : null;
          return InventorySlot(
            item: item,
            onTap: item == null ? null : () => onSlotTap?.call(item),
          );
        },
      ),
    );
  }
}

class InventorySlot extends StatelessWidget {
  const InventorySlot({
    super.key,
    required this.item,
    this.onTap,
  });

  final Equipment? item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Equipment? currentItem = item;
    final bool hasItem = currentItem != null;
    final Color gradeColor =
        hasItem ? getGradeColor(currentItem.grade) : const Color(0xFF3A3A4A);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: hasItem
              ? gradeColor.withValues(alpha: 0.25)
              : const Color(0xFF20202C),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: gradeColor,
            width: hasItem ? 1.5 : 1,
          ),
        ),
        child: hasItem
            ? Center(
                child: Text(
                  currentItem.type.displayName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: gradeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
