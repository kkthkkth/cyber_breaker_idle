import 'package:flutter/material.dart';

import '../managers/consumable_manager.dart';
import '../managers/guild_manager.dart';
import '../managers/guild_shop_manager.dart';
import '../models/equipment.dart';
import '../models/guild_shop_model.dart';
import '../utils/number_formatter.dart';
import '../widgets/center_toast.dart';

/// 길드 상점 탭 — [GuildMainScreen] 하단 탭 중 하나로 곧장 렌더링된다
/// (별도 화면으로 이동하지 않음). 기존 소모품 상점([ShopScreen]의
/// `_ConsumablesShopTab`)과 같은 형태의 타일 목록이지만, 결제 재화가
/// 골드/보석이 아니라 길드 주화([GuildManager.guildCoins])다.
class GuildShopTab extends StatefulWidget {
  const GuildShopTab({super.key});

  @override
  State<GuildShopTab> createState() => _GuildShopTabState();
}

class _GuildShopTabState extends State<GuildShopTab> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    await GuildShopManager.instance.loadData();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _buy(GuildShopItem item) async {
    final bool success = await GuildShopManager.instance.purchase(item);
    if (!mounted) {
      return;
    }
    showCenterToast(
      context,
      success ? '${item.name}을(를) 구매했습니다.' : '길드 주화가 부족합니다.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([GuildShopManager.instance, GuildManager.instance]),
      builder: (context, _) {
        final List<GuildShopItem> catalog = GuildShopManager.instance.catalog;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF20202C),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF3A3A4A)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.savings, color: Colors.amberAccent, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        NumberFormatter.format(GuildManager.instance.guildCoins.toDouble()),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: catalog.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          _isLoading
                              ? '불러오는 중...'
                              : '상점 목록을 불러오는 중이거나 아직 등록된 상품이 없습니다.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: catalog.length,
                      itemBuilder: (context, index) {
                        final GuildShopItem item = catalog[index];
                        return _GuildShopItemTile(item: item, onBuy: () => _buy(item));
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _GuildShopItemTile extends StatelessWidget {
  const _GuildShopItemTile({required this.item, required this.onBuy});

  final GuildShopItem item;
  final VoidCallback onBuy;

  static const Color _accent = Color(0xFF6C4FCE);

  @override
  Widget build(BuildContext context) {
    final int owned = ConsumableManager.instance.countOf(item.type);
    final bool canAfford = GuildManager.instance.guildCoins >= item.price;
    // 등급 개념이 있는 상품(물약류 등)은 그 등급색을, 없는 상품(재료/
    // 충전권)은 길드 테마 보라색을 아이콘/테두리 색으로 쓴다 — 구매 버튼은
    // "이 재화가 길드 주화"라는 걸 항상 같은 색으로 보여주기 위해 등급과
    // 무관하게 항상 길드 보라색을 유지한다([_PotionShopTile]과 같은 관례:
    // 아이템 색은 등급, 구매 버튼 색은 재화 종류).
    final Color itemAccent = item.grade != null ? getGradeColor(item.grade!) : _accent;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: itemAccent.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: itemAccent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: itemAccent),
            ),
            alignment: Alignment.center,
            child: Icon(item.icon, color: itemAccent, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (item.grade != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '[${item.grade!.displayName}]',
                        style: TextStyle(
                          color: itemAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  '${item.rewardAmount}개 지급 · 보유 $owned개',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: canAfford ? onBuy : null,
            icon: const Icon(Icons.savings, size: 14),
            label: Text(NumberFormatter.format(item.price.toDouble())),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF3A3A4A),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(0, 32),
              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
