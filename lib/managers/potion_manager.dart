import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/quest_model.dart';
import '../models/shop_consumable_model.dart';
import '../utils/time_util.dart';
import 'game_manager.dart';
import 'quest_manager.dart';
import 'supabase_manager.dart';

/// 물약/호감도 아이템 상점 + 인벤토리 + 자동 물약 사용 설정을 관장하는
/// 싱글턴 — 이 프로젝트의 다른 매니저들과 같은 관례를 따른다: **로컬
/// (SharedPreferences)이 게임플레이의 유일한 신뢰 소스**이고, Supabase는
/// 그 위에 얹는 부가적인 백업/동기화 계층이다. 전투 중 자동 물약 사용은
/// 매 프레임 가까이 호출될 수 있으므로 네트워크 왕복 없이 항상 로컬
/// 상태만으로 즉시 판정한다([tryAutoUse]).
class PotionManager extends ChangeNotifier with WidgetsBindingObserver {
  PotionManager._internal();

  static final PotionManager instance = PotionManager._internal();

  /// 자동 물약 사용 HP% 임계값의 기본값 — [ShopConsumableEntry] 요구사항
  /// 문서의 "기본 30%"와 일치.
  static const double defaultAutoUseThreshold = 0.3;

  List<ShopConsumableEntry> _catalog = const [];
  final Map<String, int> _inventory = {};

  String? equippedPotionId;
  double autoUseThresholdRatio = defaultAutoUseThreshold;

  /// 오늘 날짜 커서 — [ShopConsumableEntry.dailyCoinLimit]가 걸린 아이템의
  /// "제한된 코인 구매" 횟수는 아이템별로 독립적이라(예: SSR 물약 A는 하루
  /// 3번, SSSR 물약 B는 하루 1번, 서로 무관) 단일 카운터가 아니라 이 맵
  /// (item_id -> 오늘 구매 횟수)으로 추적한다.
  String? _lastResetDate;
  final Map<String, int> _dailyCoinPurchaseCounts = {};

  List<ShopConsumableEntry> get potions =>
      _catalog.where((entry) => entry.category == ShopConsumableCategory.potion).toList()
        ..sort((a, b) => (a.grade?.index ?? 0).compareTo(b.grade?.index ?? 0));

  List<ShopConsumableEntry> get affectionGifts =>
      _catalog.where((entry) => entry.category == ShopConsumableCategory.affectionGift).toList();

  /// 입장 충전권(월드보스 등) — [WorldBossManager.chargeExtraTicket]이
  /// 소비할 대상을 고를 때(보유한 것만) 이 목록을 참조한다.
  List<ShopConsumableEntry> get tickets =>
      _catalog.where((entry) => entry.category == ShopConsumableCategory.ticket).toList();

  int countOf(String itemId) => _inventory[itemId] ?? 0;

  /// 단위 테스트 전용 — 실제 카탈로그/보유 목록을 네트워크 없이 직접
  /// 주입한다(`purchaseWithCoin`/`fetchConsumableCatalog` 같은 실제 경로는
  /// 전부 네트워크나 NTP를 타서 테스트에 부적합하다). 저장/서버 동기화는
  /// 건드리지 않는다 — 순수하게 메모리 상태만 세팅한다.
  @visibleForTesting
  void debugSeedForTest({List<ShopConsumableEntry>? catalog, Map<String, int>? inventory}) {
    if (catalog != null) {
      _catalog = catalog;
    }
    if (inventory != null) {
      _inventory
        ..clear()
        ..addAll(inventory);
    }
  }

  ShopConsumableEntry? get equippedPotion {
    final String? id = equippedPotionId;
    if (id == null) {
      return null;
    }
    for (final ShopConsumableEntry entry in _catalog) {
      if (entry.id == id) {
        return entry;
      }
    }
    return null;
  }

  /// [entry]를 "제한된 코인 구매" 경로로 오늘 몇 번 더 살 수 있는지 —
  /// [ShopConsumableEntry.hasLimitedCoinOption]이 false인 항목은 항상 0
  /// (애초에 그 구매 경로가 없다).
  int remainingLimitedCoinPurchasesToday(ShopConsumableEntry entry) {
    if (!entry.hasLimitedCoinOption) {
      return 0;
    }
    final int used = _dailyCoinPurchaseCounts[entry.id] ?? 0;
    return (entry.dailyCoinLimit - used).clamp(0, entry.dailyCoinLimit);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Fire-and-forget: the override signature must stay void/sync (same
      // convention as DungeonManager.didChangeAppLifecycleState).
      _checkAndResetDailyLimit();
    }
  }

  /// main()이 앱 시작 시 한 번 호출 — 1) 로컬 캐시로 즉시 채우고, 2) 원격
  /// 카탈로그/보유 목록을 받아와 갱신을 시도한다(네트워크 실패는 캐시를
  /// 그대로 쓰면 되므로 조용히 넘어가되, 그 사실은 반드시 로그로 남긴다
  /// — "조용한 성공"과 "조용한 실패"를 구분할 수 없으면 디버깅이
  /// 불가능해진다).
  Future<void> loadData() async {
    await _loadLocal();

    final List<Map<String, dynamic>> catalogRows =
        await SupabaseManager.instance.fetchConsumableCatalog();
    if (catalogRows.isEmpty) {
      // fetchConsumableCatalog 내부에서 네트워크/쿼리 예외는 이미 로그를
      // 남기고 빈 리스트를 반환한다 — 여기 도달했는데도 로그가 안
      // 보인다면 "예외 없이 정상적으로 0건이 반환된" 경우다(예: RLS
      // 정책이 조용히 모든 행을 걸러내거나, 테이블에 실제로 행이 없는
      // 경우 — Postgrest는 이런 경우 에러를 던지지 않는다).
      debugPrint(
        '[PotionManager] 소모품 카탈로그가 비어 있습니다(consumable_items 테이블 데이터/RLS 정책을 확인하세요). '
        '기존 캐시(${_catalog.length}건)를 유지합니다.',
      );
    } else {
      // 한 행이라도 파싱에 실패하면 그 행만 건너뛴다 — 예전엔
      // `.map(...).toList()`로 한 번에 변환해서, 행 하나(예: grade 값
      // 대소문자 불일치)만 깨져도 예외가 이 try/catch 바깥으로 새어
      // 나가 catalogRows 전체가 버려지고 아무 로그도 없이 카탈로그가
      // 텅 빈 채로 남았다.
      //
      // id 기준으로도 한 번 더 걸러낸다 — 서버가 같은 행을 두 번 내려주면
      // (RLS 정책이 겹치는 등, 자주는 아니지만 실제로 일어날 수 있다)
      // 상점에 완전히 똑같은 물약이 2개씩 뜨는 원인이 된다. 처음 나온
      // 순서를 유지하고, 중복이 발견되면 어떤 id가 몇 번 왔는지 로그로
      // 남긴다 — DB에 진짜로 서로 다른 id를 가진 중복 행이 있는 경우까지는
      // 여기서 잡을 수 없으니(그건 상품명이 같아도 별개 상품일 수 있어
      // 함부로 합칠 수 없다), 로그를 보고 시드 데이터 자체를 확인해야 한다.
      final Map<String, ShopConsumableEntry> byId = {};
      final Map<String, int> duplicateCounts = {};
      for (final Map<String, dynamic> row in catalogRows) {
        try {
          final ShopConsumableEntry entry = ShopConsumableEntry.fromJson(row);
          if (byId.containsKey(entry.id)) {
            duplicateCounts[entry.id] = (duplicateCounts[entry.id] ?? 1) + 1;
            continue;
          }
          byId[entry.id] = entry;
        } catch (error) {
          debugPrint('[PotionManager] 소모품 카탈로그 행 파싱 실패(id=${row['id']}): $error');
        }
      }
      if (duplicateCounts.isNotEmpty) {
        debugPrint(
          '[PotionManager] 중복된 소모품 id를 걸러냈습니다: $duplicateCounts '
          '(consumable_items 테이블에 같은 id가 여러 번 조회되고 있는지 확인하세요).',
        );
      }
      if (byId.isEmpty) {
        debugPrint('[PotionManager] 파싱 가능한 소모품이 하나도 없습니다 — 컬럼명/타입을 확인하세요.');
      } else {
        _catalog = byId.values.toList();
      }
    }

    final Map<String, int> remoteInventory = await SupabaseManager.instance.fetchUserConsumables();
    if (remoteInventory.isNotEmpty) {
      _inventory
        ..clear()
        ..addAll(remoteInventory);
    }

    await _checkAndResetDailyLimit();
    await _saveLocal();
    notifyListeners();
  }

  /// 장착된 물약을 바꾼다(null이면 해제) — 즉시 로컬에 반영하고 서버에도
  /// 반영을 시도한다.
  Future<void> equipPotion(String? itemId) async {
    equippedPotionId = itemId;
    notifyListeners();
    await _saveLocal();
    unawaited(SupabaseManager.instance.updateEquippedPotion(itemId));
  }

  /// 자동 물약 사용 HP% 임계값을 바꾼다 — [ratio]는 0.0~1.0(예: 0.3 = 30%).
  Future<void> setAutoUseThreshold(double ratio) async {
    autoUseThresholdRatio = ratio.clamp(0.0, 1.0);
    notifyListeners();
    await _saveLocal();
    unawaited(SupabaseManager.instance.updateAutoPotionThreshold(autoUseThresholdRatio));
  }

  /// [entry.baseCurrency]/[entry.basePrice]로 [quantity]개를 한 번에
  /// 구매한다 — 하루 제한이 없는 "기본" 구매 경로다(N/R/SR 물약과 코인
  /// 티어 호감도 아이템은 baseCurrency가 coin이라 사실상 코인 무제한
  /// 구매, SSR 이상 물약과 보석 티어 호감도 아이템은 baseCurrency가
  /// gem). 총액(단가 × [quantity])만큼 재화가 부족하면 아무것도 차감/
  /// 지급하지 않고 false.
  Future<bool> purchaseWithBaseCurrency(ShopConsumableEntry entry, {int quantity = 1}) async {
    if (quantity <= 0) {
      return false;
    }
    final int totalPrice = entry.basePrice * quantity;
    final bool success = entry.baseCurrency == ShopCurrency.gem
        ? GameManager.instance.spendGems(totalPrice)
        : GameManager.instance.spendGold(totalPrice);
    if (!success) {
      return false;
    }
    await _grant(entry.id, quantity);
    return true;
  }

  /// [entry.hasLimitedCoinOption]인 아이템(주로 SSR 이상 물약)을 그 한도
  /// 안에서 [entry.coinPriceForLimit] 코인으로 [quantity]개를 한 번에
  /// 구매한다 — 오늘 남은 횟수([remainingLimitedCoinPurchasesToday])보다
  /// [quantity]가 많거나, 애초에 이 경로 자체가 없는 아이템
  /// (dailyCoinLimit == 0)이거나, 총액(단가 × [quantity])만큼 골드가
  /// 부족하면 아무것도 차감/지급하지 않고 false.
  Future<bool> purchaseWithLimitedCoin(ShopConsumableEntry entry, {int quantity = 1}) async {
    if (quantity <= 0 || !entry.hasLimitedCoinOption) {
      return false;
    }

    await _checkAndResetDailyLimit();
    final int used = _dailyCoinPurchaseCounts[entry.id] ?? 0;
    if (used + quantity > entry.dailyCoinLimit) {
      return false;
    }

    final int totalPrice = entry.coinPriceForLimit * quantity;
    if (!GameManager.instance.spendGold(totalPrice)) {
      return false;
    }

    _dailyCoinPurchaseCounts[entry.id] = used + quantity;
    unawaited(
      SupabaseManager.instance.upsertDailyCoinPurchaseCount(
        entry.id,
        _lastResetDate!,
        _dailyCoinPurchaseCounts[entry.id]!,
      ),
    );

    await _grant(entry.id, quantity);
    return true;
  }

  /// 전투 루프에서 매 프레임 호출한다 — [currentHpRatio](0.0~1.0)가 설정된
  /// 임계값 이하이고, 장착된 물약이 있고 재고가 남아 있으면 1개를 소모하고
  /// 회복 비율(effectValue, %)을 반환한다. 그 외에는 null — 호출부
  /// ([IdleGame])가 null이면 아무것도 하지 않는다.
  ///
  /// 쿨타임은 여기서 다루지 않는다 — 매 프레임 호출되는 함수 하나에 "쿨타임
  /// 중이면 스스로 무시"까지 넣으면 쿨타임 타이머를 이 매니저가 소유해야
  /// 하는데, 그건 [IdleGame]의 다른 전투 타이머(`_attackTimer` 등)와 같은
  /// 성격의 "컴포넌트 생존 기간에 종속된 프레임 타이머"라 IdleGame 쪽이
  /// 갖는 게 일관적이다 — IdleGame이 쿨타임이 남아있는 동안은 이 함수 자체를
  /// 호출하지 않는 방식으로 막는다.
  double? tryAutoUse(double currentHpRatio) {
    final String? id = equippedPotionId;
    if (id == null) {
      return null;
    }
    if (currentHpRatio > autoUseThresholdRatio) {
      return null;
    }
    if (countOf(id) <= 0) {
      return null;
    }
    final ShopConsumableEntry? entry = equippedPotion;
    if (entry == null) {
      return null;
    }

    unawaited(_consume(id));
    QuestManager.instance.updateProgress(QuestActionType.potionUse, 1);
    return entry.effectValue;
  }

  /// 다른 매니저([AffectionManager.giftShopItem] 등)가 자신이 소유한 상점
  /// 소모품을 소비할 때 쓰는 공개 API — [tryAutoUse]가 내부적으로 쓰는
  /// [_consume]과 동일한 동작이지만, 재고가 없으면 즉시 false를 돌려줘서
  /// 호출부가 "왜 실패했는지" 바로 알 수 있게 한다.
  Future<bool> consumeItem(String itemId) async {
    if (countOf(itemId) <= 0) {
      return false;
    }
    await _consume(itemId);
    return true;
  }

  Future<void> _grant(String itemId, int amount) async {
    _inventory[itemId] = (_inventory[itemId] ?? 0) + amount;
    notifyListeners();
    await _saveLocal();
    unawaited(SupabaseManager.instance.upsertUserConsumable(itemId, _inventory[itemId]!));
  }

  Future<void> _consume(String itemId) async {
    final int current = _inventory[itemId] ?? 0;
    if (current <= 0) {
      return;
    }
    _inventory[itemId] = current - 1;
    notifyListeners();
    await _saveLocal();
    unawaited(SupabaseManager.instance.upsertUserConsumable(itemId, _inventory[itemId]!));
  }

  /// [DungeonManager.checkAndResetDailyCounts]와 동일한 관례 — 서버(NTP)
  /// 시간 기준 `yyyy-MM-dd` 커서가 오늘과 다르면(기기 시계 조작 방지)
  /// 카운터를 0으로 되돌린다. 배경 타이머 없이 구매 시도/앱 재개 시점마다
  /// 지연 호출된다.
  Future<void> _checkAndResetDailyLimit() async {
    final DateTime now = await getNetworkTime();
    final String today = _formatDate(now);
    if (_lastResetDate == today) {
      return;
    }
    _dailyCoinPurchaseCounts.clear();
    _lastResetDate = today;
    notifyListeners();
    await _saveLocal();

    final Map<String, int> remoteCounts = await SupabaseManager.instance
        .fetchDailyCoinPurchaseCounts(today);
    if (remoteCounts.isNotEmpty) {
      _dailyCoinPurchaseCounts
        ..clear()
        ..addAll(remoteCounts);
      notifyListeners();
      await _saveLocal();
    }
  }

  static String _formatDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static const String _saveKey = 'potion_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode({
        'catalog': _catalog.map((entry) => entry.toCacheJson()).toList(),
        'inventory': _inventory,
        'equippedPotionId': equippedPotionId,
        'autoUseThresholdRatio': autoUseThresholdRatio,
        'lastResetDate': _lastResetDate,
        'dailyCoinPurchaseCounts': _dailyCoinPurchaseCounts,
      }),
    );
  }

  Future<void> _loadLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      return;
    }

    final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
    final List<dynamic>? catalogJson = data['catalog'] as List<dynamic>?;
    if (catalogJson != null) {
      _catalog = catalogJson
          .map((entry) => ShopConsumableEntry.fromJson(entry as Map<String, dynamic>))
          .toList();
    }
    final Map<String, dynamic>? inventoryJson = data['inventory'] as Map<String, dynamic>?;
    if (inventoryJson != null) {
      _inventory
        ..clear()
        ..addAll(inventoryJson.map((key, value) => MapEntry(key, (value as num).toInt())));
    }
    equippedPotionId = data['equippedPotionId'] as String?;
    autoUseThresholdRatio =
        (data['autoUseThresholdRatio'] as num?)?.toDouble() ?? defaultAutoUseThreshold;
    _lastResetDate = data['lastResetDate'] as String?;
    final Map<String, dynamic>? countsJson = data['dailyCoinPurchaseCounts'] as Map<String, dynamic>?;
    if (countsJson != null) {
      _dailyCoinPurchaseCounts
        ..clear()
        ..addAll(countsJson.map((key, value) => MapEntry(key, (value as num).toInt())));
    }
  }
}
