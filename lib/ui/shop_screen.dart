import 'package:flutter/material.dart';

import '../managers/equipment_manager.dart';
import '../managers/gacha_manager.dart';
import '../managers/game_manager.dart';
import '../managers/potion_manager.dart';
import '../models/equipment.dart';
import '../models/item_model.dart';
import '../models/shop_consumable_model.dart';
import '../widgets/center_toast.dart';
import '../widgets/safe_image.dart';
import 'box_shaking_dialog.dart';
import 'gacha_reveal_screen.dart';

class _GachaOffer {
  const _GachaOffer({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.pullCount,
    required this.cost,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final int pullCount;
  final int cost;
}

class _PremiumOffer {
  const _PremiumOffer({
    required this.title,
    required this.pullCount,
    required this.cost,
  });

  final String title;
  final int pullCount;
  final int cost;
}

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final GameManager _gameManager = GameManager.instance;
  final EquipmentManager _equipmentManager = EquipmentManager.instance;
  final GachaManager _gachaManager = GachaManager.instance;

  // TODO(server): replace with a real fetch of shop offers once they move
  // to a DB — the Row builders below only ever read through these.
  static const List<_GachaOffer> _coinGachaOffers = [
    _GachaOffer(
      title: '1회 뽑기',
      subtitle: '100 G',
      icon: Icons.card_giftcard,
      pullCount: 1,
      cost: 100,
    ),
    _GachaOffer(
      title: '11회 연속 뽑기',
      subtitle: '1000 G (1회 보너스)',
      icon: Icons.auto_awesome,
      pullCount: 11,
      cost: 1000,
    ),
  ];

  static const List<_PremiumOffer> _premiumGachaOffers = [
    _PremiumOffer(
      title: '1회 소환',
      pullCount: 1,
      cost: GachaManager.singlePullCost,
    ),
    _PremiumOffer(
      title: '10회 소환',
      pullCount: 10,
      cost: GachaManager.singlePullCost * 10,
    ),
  ];

  // TODO(server): dummy pet-gacha offers — same shape as the equipment
  // offers above, just re-labeled, until the real pet gacha exists.
  static const List<_GachaOffer> _petCoinGachaOffers = [
    _GachaOffer(
      title: '1회 뽑기',
      subtitle: '100 G',
      icon: Icons.pets,
      pullCount: 1,
      cost: 100,
    ),
    _GachaOffer(
      title: '11회 연속 뽑기',
      subtitle: '1000 G (1회 보너스)',
      icon: Icons.auto_awesome,
      pullCount: 11,
      cost: 1000,
    ),
  ];

  static const List<_PremiumOffer> _petPremiumGachaOffers = [
    _PremiumOffer(
      title: '1회 소환',
      pullCount: 1,
      cost: GachaManager.singlePullCost,
    ),
    _PremiumOffer(
      title: '10회 소환',
      pullCount: 10,
      cost: GachaManager.singlePullCost * 10,
    ),
  ];

  // TODO(server): dummy character-gacha offers — same shape as the
  // equipment/pet offers above, just re-labeled, until the real character
  // gacha exists.
  static const List<_GachaOffer> _characterCoinGachaOffers = [
    _GachaOffer(
      title: '1회 뽑기',
      subtitle: '100 G',
      icon: Icons.person,
      pullCount: 1,
      cost: 100,
    ),
    _GachaOffer(
      title: '11회 연속 뽑기',
      subtitle: '1000 G (1회 보너스)',
      icon: Icons.auto_awesome,
      pullCount: 11,
      cost: 1000,
    ),
  ];

  static const List<_PremiumOffer> _characterPremiumGachaOffers = [
    _PremiumOffer(
      title: '1회 소환',
      pullCount: 1,
      cost: GachaManager.singlePullCost,
    ),
    _PremiumOffer(
      title: '10회 소환',
      pullCount: 10,
      cost: GachaManager.singlePullCost * 10,
    ),
  ];

  Future<void> _pull(int count, int cost) async {
    if (!_gameManager.spendGold(cost)) {
      _showSnackBar('골드가 부족합니다');
      return;
    }

    final List<Equipment> results = _equipmentManager.drawMultipleGacha(count);
    await showBoxShakingDialog(
      context,
      onFinished: () => _showResultDialog(results),
    );
  }

  Future<void> _drawPremium(int times) async {
    final List<Item> results = _gachaManager.drawPremiumGacha(times);
    if (results.isEmpty) {
      _showSnackBar('보석이 부족합니다');
      return;
    }

    final Item best = results.reduce(
      (Item a, Item b) => b.rarity.index > a.rarity.index ? b : a,
    );

    await showBoxShakingDialog(
      context,
      onFinished: () => _showPremiumResultDialog(best),
    );
  }

  // 기존 장비 뽑기 로직(EquipmentManager)을 재활용하되 type을 pet으로 고정.
  Future<void> _petPull(int count, int cost) async {
    if (!_gameManager.spendGold(cost)) {
      _showSnackBar('골드가 부족합니다');
      return;
    }

    final List<Equipment> results = List.generate(
      count,
      (_) => _equipmentManager.generateLootOfType(EquipType.pet),
    );
    await showBoxShakingDialog(
      context,
      onFinished: () => _showResultDialog(results, title: '펫 뽑기 결과'),
    );
  }

  Future<void> _petDrawPremium(int times) async {
    if (!_gameManager.spendGems(times * GachaManager.singlePullCost)) {
      _showSnackBar('보석이 부족합니다');
      return;
    }

    final List<Equipment> results = List.generate(
      times,
      (_) => _equipmentManager.generateLootOfType(
        EquipType.pet,
        allowedGrades: const [
          ItemGrade.r,
          ItemGrade.sr,
          ItemGrade.ssr,
          ItemGrade.sssr,
          ItemGrade.ur,
        ],
      ),
    );
    await showBoxShakingDialog(
      context,
      onFinished: () => _showResultDialog(results, title: '프리미엄 펫 소환 결과'),
    );
  }

  // 기존 장비/펫 뽑기 로직(EquipmentManager)을 재활용하되 type을 character로 고정.
  Future<void> _characterPull(int count, int cost) async {
    if (!_gameManager.spendGold(cost)) {
      _showSnackBar('골드가 부족합니다');
      return;
    }

    final List<Equipment> results = List.generate(
      count,
      (_) => _equipmentManager.generateLootOfType(EquipType.character),
    );
    await showBoxShakingDialog(
      context,
      onFinished: () => _showResultDialog(results, title: '캐릭터 뽑기 결과'),
    );
  }

  Future<void> _characterDrawPremium(int times) async {
    if (!_gameManager.spendGems(times * GachaManager.singlePullCost)) {
      _showSnackBar('보석이 부족합니다');
      return;
    }

    final List<Equipment> results = List.generate(
      times,
      (_) => _equipmentManager.generateLootOfType(
        EquipType.character,
        allowedGrades: const [
          ItemGrade.r,
          ItemGrade.sr,
          ItemGrade.ssr,
          ItemGrade.sssr,
          ItemGrade.ur,
        ],
      ),
    );
    await showBoxShakingDialog(
      context,
      onFinished: () => _showResultDialog(results, title: '프리미엄 캐릭터 소환 결과'),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // 캐릭터/장비/펫 가챠 결과는 전부 카드 뒤집기 연출이 있는 전체 화면
  // (GachaRevealScreen)으로 보여준다 — 합성(synthesis_screen.dart)처럼
  // "가챠 연출"이 아닌 배치 결과는 여전히 기존 ItemResultDialog(다이얼로그)
  // 를 그대로 쓴다.
  void _showResultDialog(List<Equipment> results, {String title = '뽑기 결과'}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => GachaRevealScreen(title: title, results: results),
      ),
    );
  }

  void _showPremiumResultDialog(Item best) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1B1B26),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            '프리미엄 소환 결과',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            '${best.name} 획득!',
            style: TextStyle(
              color: getRarityColor(best.rarity),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
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
      animation: Listenable.merge([_gameManager, _gachaManager, PotionManager.instance]),
      builder: (context, _) {
        return DefaultTabController(
          length: 5,
          child: Scaffold(
            backgroundColor: const Color(0xFF14141C),
            appBar: AppBar(
              backgroundColor: const Color(0xFF1B1B26),
              elevation: 0,
              // 뒤로 가기 버튼처럼 별도 색을 안 준 아이콘이 어두운 배경에
              // 묻히지 않도록 명시한다.
              foregroundColor: Colors.white,
              title: const Text(
                '상점',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              centerTitle: true,
              bottom: const TabBar(
                isScrollable: true,
                indicatorColor: Color(0xFF6C4FCE),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                tabs: [
                  Tab(text: '패키지'),
                  Tab(text: '캐릭터'),
                  Tab(text: '장비'),
                  Tab(text: '펫'),
                  Tab(text: '소모품'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                const _ComingSoonTab(),
                _GachaOffersTab(
                  coinSectionTitle: '코인 캐릭터 가챠',
                  coinOffers: _characterCoinGachaOffers,
                  onCoinPull: _characterPull,
                  premiumSectionTitle: '프리미엄 캐릭터 소환',
                  premiumOffers: _characterPremiumGachaOffers,
                  gems: _gameManager.gems,
                  onPremiumPull: _characterDrawPremium,
                ),
                _GachaOffersTab(
                  coinSectionTitle: '코인 가챠',
                  coinOffers: _coinGachaOffers,
                  onCoinPull: _pull,
                  premiumSectionTitle: '프리미엄 장비 소환',
                  premiumOffers: _premiumGachaOffers,
                  gems: _gameManager.gems,
                  onPremiumPull: _drawPremium,
                ),
                _GachaOffersTab(
                  coinSectionTitle: '코인 펫 가챠',
                  coinOffers: _petCoinGachaOffers,
                  onCoinPull: _petPull,
                  premiumSectionTitle: '프리미엄 펫 소환',
                  premiumOffers: _petPremiumGachaOffers,
                  gems: _gameManager.gems,
                  onPremiumPull: _petDrawPremium,
                ),
                // 일부러 const를 안 붙였다 — const로 만들면 Dart가 항상
                // 똑같은(canonicalized) 인스턴스를 재사용해서, 바깥
                // AnimatedBuilder가 PotionManager.notifyListeners()로
                // 다시 그려져도 Flutter의 Element.updateChild가
                // "이전 위젯과 새 위젯이 identical하다"고 보고 이 위젯의
                // build()를 아예 다시 안 불렀다(그래서 구매 직후 '보유
                // N개'가 탭을 나갔다 들어와야만 갱신됐다 — 탭 전환은
                // 위젯 트리를 통째로 새로 만들어서 우연히 값이 맞았을
                // 뿐이다).
                _ConsumablesShopTab(),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ComingSoonTab extends StatelessWidget {
  const _ComingSoonTab();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('준비 중입니다.', style: TextStyle(color: Colors.white54)),
    );
  }
}

/// 상점 '소모품' 탭 — 물약(등급별 구매 규칙)과 호감도 아이템(코인/보석
/// 티어)을 나열한다. 실제 목록은 [PotionManager]가 원격 카탈로그
/// (`consumable_items`)에서 받아오므로, 아직 로드 전이거나 등록된 상품이
/// 없으면 안내 문구만 보여준다.
class _ConsumablesShopTab extends StatelessWidget {
  const _ConsumablesShopTab();

  /// 기본 구매(하루 제한 없음) 경로용 수량 선택 팝업을 띄운다 — 최대
  /// 99개, [entry.basePrice] 단가.
  void _openBaseCurrencyDialog(BuildContext context, ShopConsumableEntry entry) {
    showDialog<void>(
      context: context,
      builder: (context) => _PurchaseQuantityDialog(
        entry: entry,
        unitPrice: entry.basePrice,
        isGemCurrency: entry.baseCurrency == ShopCurrency.gem,
        maxQuantity: 99,
        onConfirm: (quantity) =>
            PotionManager.instance.purchaseWithBaseCurrency(entry, quantity: quantity),
      ),
    );
  }

  /// [entry.hasLimitedCoinOption]인 아이템의 "하루 N번 코인" 구매 경로용
  /// 수량 선택 팝업 — 최대 수량은 오늘 남은 횟수로 제한된다(그보다 많이
  /// 사려는 시도 자체를 UI에서 막는다).
  void _openLimitedCoinDialog(BuildContext context, ShopConsumableEntry entry) {
    final int remaining = PotionManager.instance.remainingLimitedCoinPurchasesToday(entry);
    if (remaining <= 0) {
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => _PurchaseQuantityDialog(
        entry: entry,
        unitPrice: entry.coinPriceForLimit,
        isGemCurrency: false,
        maxQuantity: remaining.clamp(1, 99),
        onConfirm: (quantity) =>
            PotionManager.instance.purchaseWithLimitedCoin(entry, quantity: quantity),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<ShopConsumableEntry> potions = PotionManager.instance.potions;
    final List<ShopConsumableEntry> gifts = PotionManager.instance.affectionGifts;
    final List<ShopConsumableEntry> tickets = PotionManager.instance.tickets;

    if (potions.isEmpty && gifts.isEmpty && tickets.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            '상점 목록을 불러오는 중이거나 아직 등록된 상품이 없습니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (potions.isNotEmpty) ...[
          const _SectionHeader(title: '물약'),
          const SizedBox(height: 8),
          for (final ShopConsumableEntry entry in potions)
            _PotionShopTile(
              entry: entry,
              onBuyBase: () => _openBaseCurrencyDialog(context, entry),
              onBuyLimitedCoin: () => _openLimitedCoinDialog(context, entry),
            ),
        ],
        if (gifts.isNotEmpty) ...[
          const SizedBox(height: 20),
          const _SectionHeader(title: '호감도 아이템'),
          const SizedBox(height: 8),
          for (final ShopConsumableEntry entry in gifts)
            _AffectionGiftTile(entry: entry, onBuy: () => _openBaseCurrencyDialog(context, entry)),
        ],
        if (tickets.isNotEmpty) ...[
          const SizedBox(height: 20),
          const _SectionHeader(title: '입장 충전권'),
          const SizedBox(height: 8),
          for (final ShopConsumableEntry entry in tickets)
            _TicketShopTile(entry: entry, onBuy: () => _openBaseCurrencyDialog(context, entry)),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
    );
  }
}

/// 아이콘 컨테이너 — 물약/호감도 아이템 타일이 공유한다. 실제 아트가
/// 준비되기 전까지는 [CustomSafeImage]가 404를 조용히 회색 placeholder로
/// 대체한다.
class _ShopItemIcon extends StatelessWidget {
  const _ShopItemIcon({required this.iconPath, required this.accent});

  final String iconPath;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent),
      ),
      alignment: Alignment.center,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CustomSafeImage(path: iconPath, width: 32, height: 32, fit: BoxFit.contain),
      ),
    );
  }
}

/// 기본 구매(baseCurrency/basePrice)는 항상 보여주고, [hasLimitedCoinOption]
/// 인 아이템(주로 SSR 이상 물약)만 "하루 N번 코인" 보조 버튼을 추가로
/// 보여준다 — 등급을 하드코딩해서 나누지 않고 서버 데이터
/// (`daily_coin_limit`)로만 판단한다.
class _PotionShopTile extends StatelessWidget {
  const _PotionShopTile({
    required this.entry,
    required this.onBuyBase,
    required this.onBuyLimitedCoin,
  });

  final ShopConsumableEntry entry;
  final VoidCallback onBuyBase;
  final VoidCallback onBuyLimitedCoin;

  @override
  Widget build(BuildContext context) {
    final Color gradeColor = getGradeColor(entry.grade ?? ItemGrade.n);
    final int owned = PotionManager.instance.countOf(entry.id);
    final bool isGemBase = entry.baseCurrency == ShopCurrency.gem;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gradeColor.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          _ShopItemIcon(iconPath: entry.iconPath, accent: gradeColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '[${(entry.grade ?? ItemGrade.n).displayName}]',
                      style: TextStyle(color: gradeColor, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Text(
                  'HP ${entry.effectValue.toStringAsFixed(0)}% 회복 · 보유 $owned개',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BuyButton(
                label: isGemBase ? '${entry.basePrice} 💎' : '${entry.basePrice} G',
                color: isGemBase ? const Color(0xFF6C4FCE) : Colors.amber.shade700,
                onTap: onBuyBase,
              ),
              if (entry.hasLimitedCoinOption) ...[
                const SizedBox(height: 4),
                _BuyButton(
                  label:
                      '${entry.coinPriceForLimit} G '
                      '(${PotionManager.instance.remainingLimitedCoinPurchasesToday(entry)}/'
                      '${entry.dailyCoinLimit})',
                  color: Colors.amber.shade700,
                  onTap: PotionManager.instance.remainingLimitedCoinPurchasesToday(entry) <= 0
                      ? null
                      : onBuyLimitedCoin,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 호감도 아이템 — 코인 티어(상승치 낮음)와 보석 티어(상승치 높음)는
/// 각각 별개의 카탈로그 항목(baseCurrency만 다른 entry)으로 온다. 둘 다
/// [ShopConsumableEntry.hasLimitedCoinOption]이 없는(daily_coin_limit=0)
/// 게 보통이라 기본 구매 버튼 하나면 된다.
class _AffectionGiftTile extends StatelessWidget {
  const _AffectionGiftTile({required this.entry, required this.onBuy});

  final ShopConsumableEntry entry;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final bool isGemTier = entry.baseCurrency == ShopCurrency.gem;
    final Color accent = isGemTier ? const Color(0xFFFF6FA5) : Colors.amber.shade700;
    final int owned = PotionManager.instance.countOf(entry.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          _ShopItemIcon(iconPath: entry.iconPath, accent: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                Text(
                  '호감도 +${entry.effectValue.toStringAsFixed(0)}% · 보유 $owned개',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _BuyButton(
            label: isGemTier ? '${entry.basePrice} 💎' : '${entry.basePrice} G',
            color: accent,
            onTap: onBuy,
          ),
        ],
      ),
    );
  }
}

/// 입장 충전권(월드보스 등) — 등급/티어 구분 없이 [entry.baseCurrency]로만
/// 색을 정한다. [WorldBossManager.chargeExtraTicket]이 이 카탈로그에서 산
/// 재고를 소비한다.
class _TicketShopTile extends StatelessWidget {
  const _TicketShopTile({required this.entry, required this.onBuy});

  final ShopConsumableEntry entry;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final bool isGemTier = entry.baseCurrency == ShopCurrency.gem;
    final Color accent = isGemTier ? const Color(0xFF6C4FCE) : Colors.amber.shade700;
    final int owned = PotionManager.instance.countOf(entry.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          _ShopItemIcon(iconPath: entry.iconPath, accent: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                Text(
                  '보유 $owned개',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _BuyButton(
            label: isGemTier ? '${entry.basePrice} 💎' : '${entry.basePrice} G',
            color: accent,
            onTap: onBuy,
          ),
        ],
      ),
    );
  }
}

class _BuyButton extends StatelessWidget {
  const _BuyButton({required this.label, required this.color, required this.onTap});

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFF3A3A4A),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(0, 32),
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      ),
      child: Text(label),
    );
  }
}

/// 소모품 구매 수량 선택 팝업 — 모바일 RPG 상점의 정석대로, 탭 즉시
/// 구매하는 대신 이 다이얼로그에서 수량(1~[maxQuantity])과 총액을 확인한
/// 뒤에만 실제로 구매가 일어난다. [onConfirm]은 [PotionManager
/// .purchaseWithBaseCurrency]/[purchaseWithLimitedCoin] 중 호출부가 고른
/// 경로를 그대로 감싼 콜백이라, 이 위젯 자체는 "기본 구매"인지 "제한된
/// 코인 구매"인지 알 필요가 없다 — 단가/최대 수량/재화 종류만 받는다.
class _PurchaseQuantityDialog extends StatefulWidget {
  const _PurchaseQuantityDialog({
    required this.entry,
    required this.unitPrice,
    required this.isGemCurrency,
    required this.maxQuantity,
    required this.onConfirm,
  });

  final ShopConsumableEntry entry;
  final int unitPrice;
  final bool isGemCurrency;
  final int maxQuantity;

  /// 실제 구매를 수행하고 성공 여부를 돌려준다 — [PotionManager]의 두
  /// 구매 메서드 중 하나를 그대로 바인딩해서 넘겨받는다.
  final Future<bool> Function(int quantity) onConfirm;

  @override
  State<_PurchaseQuantityDialog> createState() => _PurchaseQuantityDialogState();
}

class _PurchaseQuantityDialogState extends State<_PurchaseQuantityDialog> {
  int _quantity = 1;
  bool _isSubmitting = false;

  int get _totalPrice => widget.unitPrice * _quantity;

  int get _ownedCurrency =>
      widget.isGemCurrency ? GameManager.instance.gems : GameManager.instance.gold;

  bool get _canAfford => _ownedCurrency >= _totalPrice;

  void _changeQuantity(int delta) {
    setState(() => _quantity = (_quantity + delta).clamp(1, widget.maxQuantity));
  }

  void _setMax() {
    setState(() => _quantity = widget.maxQuantity);
  }

  Future<void> _confirm() async {
    if (_isSubmitting || !_canAfford) {
      return;
    }
    setState(() => _isSubmitting = true);
    final bool success = await widget.onConfirm(_quantity);
    if (!mounted) {
      return;
    }
    if (success) {
      final int purchasedQuantity = _quantity;
      Navigator.of(context).pop();
      showCenterToast(context, '${widget.entry.name}을(를) $purchasedQuantity개 구매했습니다.');
    } else {
      setState(() => _isSubmitting = false);
      showCenterToast(context, '구매에 실패했습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ShopConsumableEntry entry = widget.entry;
    final Color accent = entry.isPotion
        ? getGradeColor(entry.grade ?? ItemGrade.n)
        : (widget.isGemCurrency ? const Color(0xFFFF6FA5) : Colors.amber.shade700);
    final String currencySuffix = widget.isGemCurrency ? '💎' : 'G';

    return Dialog(
      backgroundColor: const Color(0xFF1B1B26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent),
              ),
              alignment: Alignment.center,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CustomSafeImage(path: entry.iconPath, width: 44, height: 44, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              entry.name,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (entry.isPotion) ...[
              const SizedBox(height: 2),
              Text(
                '[${(entry.grade ?? ItemGrade.n).displayName}]',
                style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _QuantityStepButton(
                  icon: Icons.remove,
                  onTap: _quantity > 1 ? () => _changeQuantity(-1) : null,
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    '$_quantity',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                _QuantityStepButton(
                  icon: Icons.add,
                  onTap: _quantity < widget.maxQuantity ? () => _changeQuantity(1) : null,
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _quantity == widget.maxQuantity ? null : _setMax,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(color: accent),
                  ),
                  child: const Text('MAX'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('총 금액', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              '$_totalPrice $currencySuffix',
              style: TextStyle(
                color: _canAfford ? Colors.white : Colors.redAccent,
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
            if (!_canAfford) ...[
              const SizedBox(height: 4),
              Text(
                widget.isGemCurrency ? '보석이 부족합니다.' : '골드가 부족합니다.',
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Color(0xFF3A3A4A)),
                    ),
                    child: const Text('취소'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_isSubmitting || !_canAfford) ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF3A3A4A),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('구매 확인'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuantityStepButton extends StatelessWidget {
  const _QuantityStepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFF20202C) : Colors.black26,
          shape: BoxShape.circle,
          border: Border.all(color: enabled ? Colors.white38 : Colors.white12),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: enabled ? Colors.white : Colors.white24),
      ),
    );
  }
}

/// Shared "코인 가챠 + 프리미엄 소환" layout — used by both the 장비 tab and
/// the 펫 tab (with different offer lists/section titles/handlers).
class _GachaOffersTab extends StatelessWidget {
  const _GachaOffersTab({
    required this.coinSectionTitle,
    required this.coinOffers,
    required this.onCoinPull,
    required this.premiumSectionTitle,
    required this.premiumOffers,
    required this.gems,
    required this.onPremiumPull,
  });

  final String coinSectionTitle;
  final List<_GachaOffer> coinOffers;
  final void Function(int count, int cost) onCoinPull;
  final String premiumSectionTitle;
  final List<_PremiumOffer> premiumOffers;
  final int gems;
  final void Function(int times) onPremiumPull;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _SectionTitle(title: coinSectionTitle, color: Colors.amberAccent),
          const SizedBox(height: 12),
          Row(
            children: [
              for (int i = 0; i < coinOffers.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(
                  child: _GachaButton(
                    title: coinOffers[i].title,
                    subtitle: coinOffers[i].subtitle,
                    icon: coinOffers[i].icon,
                    onTap: () =>
                        onCoinPull(coinOffers[i].pullCount, coinOffers[i].cost),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 28),
          const Divider(color: Color(0xFF2A2A38)),
          const SizedBox(height: 16),
          _SectionTitle(title: premiumSectionTitle, color: Colors.cyanAccent),
          const SizedBox(height: 12),
          Row(
            children: [
              for (int i = 0; i < premiumOffers.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: _PremiumGachaButton(
                    title: premiumOffers[i].title,
                    cost: premiumOffers[i].cost,
                    enabled: gems >= premiumOffers[i].cost,
                    onTap: () => onPremiumPull(premiumOffers[i].pullCount),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.color});

  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }
}

class _GachaButton extends StatelessWidget {
  const _GachaButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF20202C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF6C4FCE), width: 1.5),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.amberAccent, size: 28),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.amberAccent, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumGachaButton extends StatelessWidget {
  const _PremiumGachaButton({
    required this.title,
    required this.cost,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final int cost;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: enabled
                ? const [Color(0xFF123B4A), Color(0xFF0B222B)]
                : const [Color(0xFF20202C), Color(0xFF20202C)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: enabled ? Colors.cyanAccent : const Color(0xFF3A3A4A),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.diamond,
              color: enabled ? Colors.cyanAccent : Colors.white24,
              size: 26,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: enabled ? Colors.white : Colors.white38,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '💎 $cost',
              style: TextStyle(
                color: enabled ? Colors.cyanAccent : Colors.white24,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
