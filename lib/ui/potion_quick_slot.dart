import 'package:flutter/material.dart';

import '../managers/potion_manager.dart';
import '../models/equipment.dart';
import '../models/shop_consumable_model.dart';

/// 전투 화면(HomeScreen._BattleView) 우측 상단의 동그란 물약 퀵슬롯 —
/// 장착된 물약이 없으면 빈 슬롯(+ 아이콘), 있으면 등급색 테두리 + 보유
/// 개수를 보여준다. 탭하면 [_PotionSelectDialog]가 화면 중앙에 떠서
/// 장착/자동 사용 임계값을 설정할 수 있다.
class PotionQuickSlot extends StatelessWidget {
  const PotionQuickSlot({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: PotionManager.instance,
      builder: (context, _) {
        final ShopConsumableEntry? equipped = PotionManager.instance.equippedPotion;
        final Color ringColor = equipped != null
            ? getGradeColor(equipped.grade ?? ItemGrade.n)
            : Colors.white38;

        return GestureDetector(
          onTap: () => showPotionSelectSheet(context),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF20202C),
              border: Border.all(color: ringColor, width: 2),
              boxShadow: equipped == null
                  ? null
                  : [BoxShadow(color: ringColor.withValues(alpha: 0.5), blurRadius: 8)],
            ),
            alignment: Alignment.center,
            child: equipped == null
                ? const Icon(Icons.add, color: Colors.white54, size: 22)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_drink, color: ringColor, size: 16),
                      Text(
                        '${PotionManager.instance.countOf(equipped.id)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

/// 물약 목록(보유 중인 것만) + 자동 사용 HP% 슬라이더를 보여주는 화면
/// 중앙 다이얼로그 — [PotionQuickSlot]/상점 등 어디서든 재사용할 수 있게
/// 최상위 함수로 뺐다.
Future<void> showPotionSelectSheet(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _PotionSelectDialog(),
  );
}

class _PotionSelectDialog extends StatefulWidget {
  const _PotionSelectDialog();

  @override
  State<_PotionSelectDialog> createState() => _PotionSelectDialogState();
}

class _PotionSelectDialogState extends State<_PotionSelectDialog> {
  late double _threshold = PotionManager.instance.autoUseThresholdRatio;

  /// 인벤토리 그리드 한 줄에 놓을 칸 수 — 요구사항: "1줄에 딱 5개씩".
  static const int _gridColumns = 5;

  /// 그리드가 스크롤 없이 한 번에 보여줄 최대 줄 수 — 요구사항: "세로로는
  /// 최대 3줄까지만 보이도록". 그보다 칸이 많아지면 [_gridMaxVisibleRows]
  /// 높이로 잘린 [GridView]가 자체적으로 세로 스크롤된다.
  static const int _gridMaxVisibleRows = 3;
  static const double _gridSpacing = 8;

  /// 타일의 가로:세로 비율 — 일반 인벤토리 화면(ConsumableInventoryScreen의
  /// `_ConsumableSlot` 그리드)과 완전히 같은 정사각형(1.0)으로 맞춘다.
  static const double _tileAspectRatio = 1.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: PotionManager.instance,
      builder: (context, _) {
        final List<ShopConsumableEntry> owned = PotionManager.instance.potions
            .where((entry) => PotionManager.instance.countOf(entry.id) > 0)
            .toList();
        final String? equippedId = PotionManager.instance.equippedPotionId;
        // "해제" 칸을 항상 그리드 맨 앞(1번 슬롯, index 0)에 고정한다 —
        // 예전엔 맨 뒤(owned.length번째)에 있어서 보유 물약 종류가 늘고
        // 줄 때마다 "해제" 칸의 위치(몇 번째 열/행)가 계속 바뀌었고,
        // 물약이 하나도 없을 때는 이 칸 하나만 덩그러니 그리드 끝(즉
        // index 0, 결과적으론 같은 자리)에 남아 안내 문구와 어색하게
        // 붙어 보였다. 항상 첫 칸으로 고정해 두면 보유 물약 수와 무관하게
        // 위치가 절대 흔들리지 않는다.
        final int totalSlots = owned.length + 1;
        final int rowCount = (totalSlots / _gridColumns).ceil().clamp(1, 1 << 30);
        final int visibleRows = _gridMaxVisibleRows.clamp(1, rowCount);

        return Dialog(
          backgroundColor: const Color(0xFF1B1B26),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '물약 장착',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 16),
                // 상단: 자동 사용 임계값 — 그리드보다 먼저 보여준다.
                Text(
                  'HP가 ${(_threshold * 100).round()}% 이하일 때 자동 사용',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                Slider(
                  value: _threshold,
                  min: 0.1,
                  max: 0.9,
                  divisions: 16,
                  activeColor: const Color(0xFF6C4FCE),
                  label: '${(_threshold * 100).round()}%',
                  onChanged: (value) => setState(() => _threshold = value),
                  onChangeEnd: (value) => PotionManager.instance.setAutoUseThreshold(value),
                ),
                const SizedBox(height: 12),
                const Text(
                  '보유 물약',
                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                // 하단: 인벤토리 그리드 — 5열 고정, 최대 3줄 높이로 상자를
                // 제한하고 그보다 물약 종류가 많으면 세로 스크롤된다(예전
                // 가로 ListView는 스크롤이 잘 안 먹고 칸이 넘칠 때
                // 오버플로우가 났었다). 높이 상자를 [LayoutBuilder]로 실제
                // 렌더링 폭에서 역산하는 이유: 예전엔 타일 한 변 길이를
                // 상수(68 등)로 미리 "짐작"해서 상자 높이를 계산했는데,
                // GridView 자신은 항상 실제로 주어진 폭을 5등분해서 타일
                // 크기를 정하기 때문에(SliverGridDelegateWithFixedCrossAxisCount의
                // 기본 동작), 팝업 실제 폭이 그 짐작과 어긋나면 상자
                // 높이와 실제 3줄 높이가 안 맞아 3번째 줄이 살짝 잘리거나
                // 아래에 빈 여백이 남았다. 여기서 GridView와 완전히 같은
                // 폭/여백/aspectRatio 공식으로 계산하면 항상 정확히
                // 들어맞는다.
                LayoutBuilder(
                  builder: (context, constraints) {
                    final double totalSpacing = _gridSpacing * (_gridColumns - 1);
                    final double tileWidth =
                        (constraints.maxWidth - totalSpacing) / _gridColumns;
                    final double tileHeight = tileWidth / _tileAspectRatio;
                    final double gridHeight =
                        tileHeight * visibleRows + _gridSpacing * (visibleRows - 1);

                    return SizedBox(
                      height: gridHeight,
                      child: GridView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: _gridColumns,
                          mainAxisSpacing: _gridSpacing,
                          crossAxisSpacing: _gridSpacing,
                          childAspectRatio: _tileAspectRatio,
                        ),
                        itemCount: totalSlots,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            // 1번 슬롯 = 항상 고정된 해제 버튼 — 물약과
                            // 헷갈리지 않도록 물약 아이콘에 사선이 그어진
                            // "no_drinks" 아이콘을 쓰고, 수량 뱃지는 없다.
                            return _PotionOptionTile(
                              selected: equippedId == null,
                              color: Colors.white38,
                              icon: Icons.no_drinks,
                              count: null,
                              onTap: () => PotionManager.instance.equipPotion(null),
                            );
                          }
                          final ShopConsumableEntry entry = owned[index - 1];
                          return _PotionOptionTile(
                            selected: equippedId == entry.id,
                            color: getGradeColor(entry.grade ?? ItemGrade.n),
                            icon: Icons.local_drink,
                            count: PotionManager.instance.countOf(entry.id),
                            onTap: () => PotionManager.instance.equipPotion(entry.id),
                          );
                        },
                      ),
                    );
                  },
                ),
                if (owned.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: SizedBox(
                      width: double.infinity,
                      child: Center(
                        child: Text(
                          '보유 중인 물약이 없어요. 상점에서 구매해보세요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 일반 인벤토리(ConsumableInventoryScreen의 `_ConsumableSlot`)와 완전히
/// 같은 타일 디자인 — padding 3 / radius 8 / 중앙 아이콘(26px) / 우측 하단
/// "xN" 뱃지(검정 알약 배경). 아이템 이름 텍스트는 두지 않는다(요구사항:
/// "오직 아이콘과 수량만"). `_ConsumableSlot`은 "보유 여부"만으로 색을
/// 정하지만, 여기는 "장착 중인지"(selected)가 그 역할을 대신한다는 점만
/// 다르다.
class _PotionOptionTile extends StatelessWidget {
  const _PotionOptionTile({
    required this.selected,
    required this.color,
    required this.icon,
    required this.count,
    required this.onTap,
  });

  final bool selected;
  final Color color;
  final IconData icon;

  /// null이면 수량 뱃지 자체를 그리지 않는다(해제 타일 전용).
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.25) : const Color(0xFF20202C),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : const Color(0xFF3A3A4A),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Stack(
          children: [
            Center(child: Icon(icon, color: color, size: 26)),
            if (count != null)
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'x$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
