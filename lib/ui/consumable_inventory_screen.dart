import 'package:flutter/material.dart';

import '../managers/consumable_manager.dart';
import '../managers/dungeon_manager.dart';
import '../models/consumable_item_model.dart';
import 'box_open_dialog.dart';
import 'top_bar.dart';

class ConsumableInventoryScreen extends StatefulWidget {
  const ConsumableInventoryScreen({super.key});

  @override
  State<ConsumableInventoryScreen> createState() =>
      _ConsumableInventoryScreenState();
}

class _ConsumableInventoryScreenState extends State<ConsumableInventoryScreen> {
  static const int _minSlotCount = 12;

  ConsumableItem? _selectedItem;
  String? _selectedDescription;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14141C),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                const TopBar(),
                SizedBox(
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Align(
                        alignment: Alignment.center,
                        child: Text(
                          '인벤토리',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: AnimatedBuilder(
                    animation: ConsumableManager.instance,
                    builder: (context, _) {
                      final List<ConsumableItem> inventory = ConsumableManager
                          .instance
                          .inventory
                          .where((item) => item.count > 0)
                          .toList();
                      final int totalSlots = inventory.length > _minSlotCount
                          ? inventory.length
                          : _minSlotCount;

                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: GridView.builder(
                          itemCount: totalSlots,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 6,
                                crossAxisSpacing: 8.0,
                                mainAxisSpacing: 8.0,
                                childAspectRatio: 1.0,
                              ),
                          itemBuilder: (context, index) {
                            final ConsumableItem? item =
                                index < inventory.length
                                ? inventory[index]
                                : null;
                            return _ConsumableSlot(
                              item: item,
                              onTap: item == null ? null : () => _useItem(item),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            if (_selectedItem != null)
              Center(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _selectedItem = null;
                    _selectedDescription = null;
                  }),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1B26).withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF6C4FCE)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _selectedItem!.type.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _selectedDescription ?? '',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _useItem(ConsumableItem item) {
    final String message;
    switch (item.type) {
      case ConsumableType.skillReset:
        final bool success = ConsumableManager.instance.useSkillReset();
        message = success ? '스킬을 초기화하고 SP를 모두 반환했습니다.' : '사용할 수 없습니다.';
        break;
      case ConsumableType.speed2x:
      case ConsumableType.speed3x:
        message = '상단 배속 버튼에서 사용할 수 있습니다.';
        break;
      case ConsumableType.premiumGachaTicket:
        message = '상점의 고급 뽑기에서 자동으로 사용됩니다.';
        break;
      case ConsumableType.crossElementBook:
        message = '스킬 화면에서 다른 속성 스킬 습득 시 자동으로 사용됩니다.';
        break;
      case ConsumableType.dust:
        message = '장비 합성/강화 재료로 사용될 예정입니다.';
        break;
      case ConsumableType.pawprint:
        message = '펫 합성/강화 재료로 사용될 예정입니다.';
        break;
      case ConsumableType.goldDungeonTicket:
        final bool success = ConsumableManager.instance.consume(
          ConsumableType.goldDungeonTicket,
        );
        if (success) {
          DungeonManager.instance.addGoldDungeonTicket();
        }
        message = success ? '골드 던전 입장 횟수가 1 증가했습니다.' : '사용할 수 없습니다.';
        break;
      case ConsumableType.equipDungeonTicket:
        final bool success = ConsumableManager.instance.consume(
          ConsumableType.equipDungeonTicket,
        );
        if (success) {
          DungeonManager.instance.addEquipmentDungeonTicket();
        }
        message = success ? '장비 던전 입장 횟수가 1 증가했습니다.' : '사용할 수 없습니다.';
        break;
      case ConsumableType.towerSweepTicket:
        final bool success = ConsumableManager.instance.consume(
          ConsumableType.towerSweepTicket,
        );
        if (success) {
          DungeonManager.instance.addTowerSweepTicket();
        }
        message = success ? '무한의 탑 소탕 횟수가 1 증가했습니다.' : '사용할 수 없습니다.';
        break;
      case ConsumableType.normalBox:
      case ConsumableType.advancedBox:
      case ConsumableType.heroBox:
      case ConsumableType.legendaryBox:
        showBoxOpenDialog(context, item.type);
        return;
      case ConsumableType.giftFlower:
      case ConsumableType.giftChocolate:
      case ConsumableType.giftJewelry:
        message = '캐릭터 상세 팝업의 호감도 화면에서 선물할 수 있습니다.';
        break;
      case ConsumableType.oathRing:
        message = '호감도 Lv.MAX 화면에서 서약할 때 사용할 수 있습니다.';
        break;
      case ConsumableType.enhanceStone:
        message = '요일 던전(수요일) 보상 재화입니다. 향후 강화 콘텐츠에서 사용될 예정입니다.';
        break;
    }
    setState(() {
      _selectedItem = item;
      _selectedDescription = message;
    });
  }
}

class _ConsumableSlot extends StatelessWidget {
  const _ConsumableSlot({this.item, this.onTap});

  final ConsumableItem? item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ConsumableItem? current = item;
    final bool hasItem = current != null;
    const Color accentColor = Color(0xFF6C4FCE);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: hasItem
              ? accentColor.withValues(alpha: 0.25)
              : const Color(0xFF20202C),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasItem ? accentColor : const Color(0xFF3A3A4A),
            width: hasItem ? 1.5 : 1,
          ),
        ),
        child: hasItem
            ? Stack(
                children: [
                  Center(
                    child: Icon(
                      current.type.icon,
                      color: accentColor,
                      size: 26,
                    ),
                  ),
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'x${current.count}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}
