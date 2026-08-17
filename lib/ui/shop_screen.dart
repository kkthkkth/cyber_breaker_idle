import 'package:flutter/material.dart';

import '../managers/ad_manager.dart';
import '../managers/artifact_manager.dart';
import '../managers/equipment_manager.dart';
import '../managers/gacha_manager.dart';
import '../managers/game_manager.dart';
import '../managers/guild_war_manager.dart';
import '../managers/pity_manager.dart';
import '../managers/potion_manager.dart';
import '../managers/tutorial_manager.dart';
import '../models/artifact_model.dart';
import '../models/equipment.dart';
import '../models/item_model.dart';
import '../models/shop_consumable_model.dart';
import '../widgets/bouncy_button.dart';
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

class _ShopScreenState extends State<ShopScreen> with SingleTickerProviderStateMixin {
  final GameManager _gameManager = GameManager.instance;
  final EquipmentManager _equipmentManager = EquipmentManager.instance;
  final GachaManager _gachaManager = GachaManager.instance;

  /// [DefaultTabController] 대신 직접 들고 있는 이유: 온보딩 튜토리얼
  /// 3단계가 시작되면 "캐릭터" 탭(가챠 버튼이 있는 곳)으로 프로그램적으로
  /// 강제 전환해야 하는데([_onTutorialChanged]), DefaultTabController는
  /// 이 위젯의 build() 안에서 만들어져 State의 context로는 접근할 수 없다.
  late final TabController _tabController = TabController(length: 6, vsync: this);

  @override
  void initState() {
    super.initState();
    TutorialManager.instance.addListener(_onTutorialChanged);
  }

  @override
  void dispose() {
    TutorialManager.instance.removeListener(_onTutorialChanged);
    _tabController.dispose();
    super.dispose();
  }

  /// 튜토리얼이 3단계(가챠 버튼 강조)에 들어서면 "캐릭터" 탭(index 1)으로
  /// 자동 전환한다 — 상점 화면은 IndexedStack에 항상 마운트돼 있어, 유저가
  /// 아직 이 화면을 보고 있지 않은 순간에도 이 리스너는 계속 살아있다.
  void _onTutorialChanged() {
    if (TutorialManager.instance.currentStep == 2 && _tabController.index != 1) {
      _tabController.animateTo(1);
    }
  }

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
    GuildWarManager.instance.reportTaxableSpend(coinSpent: cost);

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
    GuildWarManager.instance.reportTaxableSpend(gemSpent: times * GachaManager.singlePullCost);

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
    GuildWarManager.instance.reportTaxableSpend(coinSpent: cost);

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
    GuildWarManager.instance.reportTaxableSpend(gemSpent: times * GachaManager.singlePullCost);

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
    GuildWarManager.instance.reportTaxableSpend(coinSpent: cost);

    final List<Equipment> results = List.generate(
      count,
      (_) => _equipmentManager.generateLootOfType(EquipType.character),
    );
    await showBoxShakingDialog(
      context,
      onFinished: () => _showResultDialog(results, title: '캐릭터 뽑기 결과'),
    );

    // 튜토리얼 3단계("무료 가챠를 뽑아보세요!")가 이 버튼을 강조하고 있던
    // 중이면, 실제로 뽑기에 성공한 지금 튜토리얼을 마지막 단계까지
    // 진행시킨다.
    if (TutorialManager.instance.currentStep == 2) {
      TutorialManager.instance.advance();
    }
  }

  Future<void> _characterDrawPremium(int times) async {
    if (!_gameManager.spendGems(times * GachaManager.singlePullCost)) {
      _showSnackBar('보석이 부족합니다');
      return;
    }
    GuildWarManager.instance.reportTaxableSpend(gemSpent: times * GachaManager.singlePullCost);

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
        return Scaffold(
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
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: const Color(0xFF6C4FCE),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: const [
                Tab(text: '무료 보상'),
                Tab(text: '캐릭터'),
                Tab(text: '장비'),
                Tab(text: '펫'),
                Tab(text: '소모품'),
                Tab(text: '유물'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              const _FreeRewardsTab(),
              _GachaOffersTab(
                coinSectionTitle: '코인 캐릭터 가챠',
                coinOffers: _characterCoinGachaOffers,
                onCoinPull: _characterPull,
                premiumSectionTitle: '프리미엄 캐릭터 소환',
                premiumOffers: _characterPremiumGachaOffers,
                gems: _gameManager.gems,
                onPremiumPull: _characterDrawPremium,
                pityCategory: GachaPityCategory.character,
                highlightFirstCoinButton: true,
              ),
              _GachaOffersTab(
                coinSectionTitle: '코인 가챠',
                coinOffers: _coinGachaOffers,
                onCoinPull: _pull,
                premiumSectionTitle: '프리미엄 장비 소환',
                premiumOffers: _premiumGachaOffers,
                gems: _gameManager.gems,
                onPremiumPull: _drawPremium,
                pityCategory: GachaPityCategory.equipment,
              ),
              _GachaOffersTab(
                coinSectionTitle: '코인 펫 가챠',
                coinOffers: _petCoinGachaOffers,
                onCoinPull: _petPull,
                premiumSectionTitle: '프리미엄 펫 소환',
                premiumOffers: _petPremiumGachaOffers,
                gems: _gameManager.gems,
                onPremiumPull: _petDrawPremium,
                pityCategory: GachaPityCategory.pet,
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
              const _ArtifactTab(),
            ],
          ),
        );
      },
    );
  }
}


/// 상점 첫 탭 — DB 주도형 보상형 광고(AdManager) 4곳: 코인/일반 상자(펫)/
/// 일반 상자(장비)/일반 상자(캐릭터). 4곳 전부 `daily_ad_views`(일일 5회)/
/// `last_ad_viewed_at`(1시간 쿨타임) 카운터 하나를 공유한다 — 어느 버튼으로
/// 봐도 같이 줄어들고, 같이 쿨타임에 걸린다([AdManager] 문서 참고).
class _FreeRewardsTab extends StatefulWidget {
  const _FreeRewardsTab();

  @override
  State<_FreeRewardsTab> createState() => _FreeRewardsTabState();
}

class _FreeRewardsTabState extends State<_FreeRewardsTab> {
  bool _isWatching = false;

  /// 광고를 보여주고, 끝까지 시청했을 때만 [grantReward]로 실제 게임
  /// 보상을 지급한다 — [AdManager.showRewardedAd]는 "시청했는지"만
  /// 책임지고, 무엇을 줄지는 항상 호출부가 결정한다.
  Future<void> _watchAd({
    required String rewardLabel,
    required VoidCallback grantReward,
  }) async {
    if (_isWatching) {
      return;
    }
    setState(() => _isWatching = true);
    final bool watched = await AdManager.instance.showRewardedAd();
    if (!mounted) {
      return;
    }
    setState(() => _isWatching = false);
    if (watched) {
      grantReward();
      showCenterToast(context, '$rewardLabel 획득!');
    } else {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('광고를 끝까지 시청하지 못했어요.')));
    }
  }

  void _watchForGold() {
    _watchAd(
      rewardLabel: '골드 500',
      grantReward: () => GameManager.instance.addGold(500),
    );
  }

  /// [type]이 null이면 "장비" 박스 — 무기/방어구 등 여러 슬롯 중 무작위
  /// 하나를 뽑는 기존 "코인 가챠" 버튼과 같은 경로([EquipmentManager
  /// .generateRandomLoot]). null이 아니면(펫/캐릭터) 해당 타입 전용 경로
  /// ([EquipmentManager.generateLootOfType]) — 기존 상점의 펫/캐릭터 코인
  /// 가챠 버튼과 동일하게, 그 타입의 천장 카운터도 함께 소비한다.
  void _watchForBox(EquipType? type, String label) {
    _watchAd(
      rewardLabel: label,
      grantReward: () {
        final Equipment result = type == null
            ? EquipmentManager.instance.generateRandomLoot()
            : EquipmentManager.instance.generateLootOfType(type);
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (context) => GachaRevealScreen(title: '$label 결과', results: [result]),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AdManager.instance,
      builder: (context, _) {
        final AdManager ads = AdManager.instance;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!ads.isSupportedPlatform)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF20202C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF3A3A4A)),
                ),
                child: const Text(
                  '이 플랫폼에서는 광고 시청을 지원하지 않아요.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _SectionTitle(title: '무료 보상', color: Colors.amberAccent),
                Text(
                  '오늘 ${ads.dailyAdViews}/${AdManager.maxDailyViews}회 시청',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '광고를 시청하고 무료 보상을 받아보세요. 시청 후 1시간 동안은\n다시 볼 수 없어요.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 16),
            _AdRewardCard(
              icon: Icons.monetization_on,
              iconColor: Colors.amber,
              title: '코인',
              subtitle: '골드 500 획득',
              busy: _isWatching,
              onWatch: _watchForGold,
            ),
            const SizedBox(height: 12),
            _AdRewardCard(
              icon: Icons.pets,
              iconColor: Colors.orangeAccent,
              title: '일반 상자 (펫)',
              subtitle: '펫 1마리 획득',
              busy: _isWatching,
              onWatch: () => _watchForBox(EquipType.pet, '일반 상자 (펫)'),
            ),
            const SizedBox(height: 12),
            _AdRewardCard(
              icon: Icons.shield,
              iconColor: Colors.cyanAccent,
              title: '일반 상자 (장비)',
              subtitle: '장비 1개 획득',
              busy: _isWatching,
              onWatch: () => _watchForBox(null, '일반 상자 (장비)'),
            ),
            const SizedBox(height: 12),
            _AdRewardCard(
              icon: Icons.person,
              iconColor: Colors.purpleAccent,
              title: '일반 상자 (캐릭터)',
              subtitle: '캐릭터 1명 획득',
              busy: _isWatching,
              onWatch: () => _watchForBox(EquipType.character, '일반 상자 (캐릭터)'),
            ),
          ],
        );
      },
    );
  }
}

/// 광고 시청 카드 하나 — 쿨타임 중이면 "남은 시간 (mm:ss)"이 매초
/// 줄어들고(AdManager가 1초 주기로 notifyListeners를 쏘므로 이 위젯도 그
/// 주기로 다시 그려진다), 오늘 시청 횟수를 다 썼으면 그 문구로 바뀐다.
class _AdRewardCard extends StatelessWidget {
  const _AdRewardCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.onWatch,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool busy;
  final VoidCallback onWatch;

  static String _formatRemaining(Duration remaining) {
    final int minutes = remaining.inMinutes;
    final int seconds = remaining.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final AdManager ads = AdManager.instance;
    final bool canWatch = ads.canWatchAd && !busy;

    final String buttonLabel = !ads.isSupportedPlatform
        ? '지원 안 됨'
        : !ads.hasDailyViewsLeft
        ? '오늘 시청 완료'
        : ads.isOnCooldown
        ? '남은 시간 (${_formatRemaining(ads.cooldownRemaining)})'
        : '광고 보고 받기';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: iconColor.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: iconColor),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: withTapHaptic(canWatch ? onWatch : null),
            icon: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.play_circle_fill, size: 16),
            label: Text(buttonLabel, style: const TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: iconColor,
              foregroundColor: Colors.black,
              disabledBackgroundColor: const Color(0xFF3A3A4A),
              disabledForegroundColor: Colors.white38,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
        ],
      ),
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
  const _ShopItemIcon({required this.iconPath, this.fallbackPath, required this.accent});

  final String iconPath;
  final String? fallbackPath;
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
        child: CustomSafeImage(
          path: iconPath,
          fallbackPath: fallbackPath,
          width: 32,
          height: 32,
          fit: BoxFit.contain,
        ),
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
          _ShopItemIcon(
            iconPath: entry.iconPath,
            fallbackPath: entry.iconFallbackPath,
            accent: gradeColor,
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
          _ShopItemIcon(
            iconPath: entry.iconPath,
            fallbackPath: entry.iconFallbackPath,
            accent: accent,
          ),
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
          _ShopItemIcon(
            iconPath: entry.iconPath,
            fallbackPath: entry.iconFallbackPath,
            accent: accent,
          ),
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
                child: CustomSafeImage(
                  path: entry.iconPath,
                  fallbackPath: entry.iconFallbackPath,
                  width: 44,
                  height: 44,
                  fit: BoxFit.contain,
                ),
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
    required this.pityCategory,
    this.highlightFirstCoinButton = false,
  });

  final String coinSectionTitle;
  final List<_GachaOffer> coinOffers;
  final void Function(int count, int cost) onCoinPull;
  final String premiumSectionTitle;
  final List<_PremiumOffer> premiumOffers;
  final int gems;
  final void Function(int times) onPremiumPull;

  /// 온보딩 튜토리얼 3단계("무료 가챠를 뽑아보세요!")가 이 탭의 첫 코인
  /// 뽑기 버튼을 스포트라이트로 강조하게 한다 — 캐릭터 탭에서만 true.
  final bool highlightFirstCoinButton;

  /// 코인/프리미엄 뽑기가 공유하는 천장 카운터 — 같은 탭(캐릭터/장비/펫)
  /// 안에서는 어느 쪽으로 뽑든 같은 카운터가 오른다([PityManager] 문서
  /// 참고).
  final GachaPityCategory pityCategory;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _PityProgressBar(category: pityCategory),
          const SizedBox(height: 16),
          _SectionTitle(title: coinSectionTitle, color: Colors.amberAccent),
          const SizedBox(height: 12),
          Row(
            children: [
              for (int i = 0; i < coinOffers.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(
                  child: KeyedSubtree(
                    key: (highlightFirstCoinButton && i == 0)
                        ? TutorialManager.freeGachaButtonKey
                        : null,
                    child: _GachaButton(
                      title: coinOffers[i].title,
                      subtitle: coinOffers[i].subtitle,
                      icon: coinOffers[i].icon,
                      onTap: () =>
                          onCoinPull(coinOffers[i].pullCount, coinOffers[i].cost),
                    ),
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

/// "천장까지 N회 남음" 게이지 — [PityManager]가 관리하는 [category] 전용
/// 카운터를 그대로 보여준다. 코인/프리미엄 뽑기 모두 이 카운터 하나를
/// 공유하므로 탭 상단에 한 번만 놓는다. 유저가 "조금만 더 뽑으면 확정"임을
/// 한눈에 보고 계속 뽑고 싶어지도록, 남은 횟수를 숫자와 채워지는 바
/// 둘 다로 강조한다.
class _PityProgressBar extends StatelessWidget {
  const _PityProgressBar({required this.category});

  final GachaPityCategory category;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: PityManager.instance,
      builder: (context, _) {
        final PityManager pity = PityManager.instance;
        final int remaining = pity.remainingFor(category);
        final double progress = pity.progressFor(category);

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF20202C),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.amberAccent, size: 16),
                      SizedBox(width: 6),
                      Text(
                        '최고 등급 확정 천장',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '$remaining회 남음',
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(Colors.amberAccent),
                ),
              ),
            ],
          ),
        );
      },
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
    return BouncyButton(
      onTap: onTap,
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
    return BouncyButton(
      onTap: enabled ? onTap : null,
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

/// 보석을 소모해 유물 조각을 뽑고, 모은 조각으로 레벨업하는 탭 —
/// [ArtifactManager]가 카탈로그+진행도를 합쳐 들고 있는 [Artifact] 목록을
/// 그대로 그린다("장착" 개념이 없어 캐릭터/장비/펫 탭과 달리 보유한 모든
/// 유물이 항상 동시에 패시브를 제공한다).
class _ArtifactTab extends StatelessWidget {
  const _ArtifactTab();

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _pull(BuildContext context, int times) {
    final List<Artifact> results = ArtifactManager.instance.drawMultiple(times);
    if (results.isEmpty) {
      _showSnackBar(context, '보석이 부족합니다');
      return;
    }
    final String summary = results.map((artifact) => '${artifact.name} 조각').join(', ');
    _showSnackBar(
      context,
      results.length < times
          ? '보석이 부족해 ${results.length}회만 뽑았어요: $summary'
          : '유물 조각 획득: $summary',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([ArtifactManager.instance, GameManager.instance]),
      builder: (context, _) {
        final ArtifactManager manager = ArtifactManager.instance;
        final int gems = GameManager.instance.gems;
        final bool canPullOnce = gems >= ArtifactManager.pullCost;
        final bool canPullTen = gems >= ArtifactManager.pullCost * 10;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(title: '유물 조각 뽑기', color: Colors.cyanAccent),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _PremiumGachaButton(
                      title: '1회 뽑기',
                      cost: ArtifactManager.pullCost,
                      enabled: canPullOnce,
                      onTap: () => _pull(context, 1),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PremiumGachaButton(
                      title: '10회 뽑기',
                      cost: ArtifactManager.pullCost * 10,
                      enabled: canPullTen,
                      onTap: () => _pull(context, 10),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              const Divider(color: Color(0xFF2A2A38)),
              const SizedBox(height: 16),
              const _SectionTitle(title: '보유 유물', color: Colors.amberAccent),
              const SizedBox(height: 12),
              if (manager.artifacts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    '유물 정보를 불러오는 중입니다...',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              else
                for (final Artifact artifact in manager.artifacts) ...[
                  _ArtifactCard(
                    artifact: artifact,
                    onLevelUp: () {
                      final bool success = manager.levelUp(artifact.id);
                      if (!success) {
                        _showSnackBar(context, '조각이 부족합니다');
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        );
      },
    );
  }
}

class _ArtifactCard extends StatelessWidget {
  const _ArtifactCard({required this.artifact, required this.onLevelUp});

  final Artifact artifact;
  final VoidCallback onLevelUp;

  @override
  Widget build(BuildContext context) {
    final bool canLevelUp = artifact.canLevelUp;
    final double ratio = artifact.isMaxLevel
        ? 1.0
        : (artifact.nextLevelFragmentCost <= 0
            ? 0.0
            : (artifact.fragmentCount / artifact.nextLevelFragmentCost).clamp(0.0, 1.0));

    return Container(
      decoration: canLevelUp
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.amberAccent.withValues(alpha: 0.4),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            )
          : null,
      child: Card(
        color: const Color(0xFF20202C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: canLevelUp ? Colors.amberAccent : const Color(0xFF3A3A4A),
            width: canLevelUp ? 1.5 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            artifact.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Text(
                          artifact.isMaxLevel ? 'MAX' : 'Lv.${artifact.level}/${artifact.maxLevel}',
                          style: const TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${ArtifactStat.displayName(artifact.statKey)} '
                      '+${(artifact.passiveValue * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 8,
                        backgroundColor: Colors.white24,
                        valueColor: AlwaysStoppedAnimation(
                          canLevelUp ? Colors.greenAccent : const Color(0xFF6C4FCE),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      artifact.isMaxLevel
                          ? '최대 레벨 달성'
                          : '조각 ${artifact.fragmentCount}/${artifact.nextLevelFragmentCost}',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: canLevelUp ? onLevelUp : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canLevelUp ? Colors.amberAccent : const Color(0xFF6C4FCE),
                  foregroundColor: canLevelUp ? Colors.black : Colors.white,
                  disabledBackgroundColor: const Color(0xFF3A3A4A),
                  disabledForegroundColor: Colors.white54,
                  elevation: canLevelUp ? 6 : 0,
                ),
                child: const Text('레벨업'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
