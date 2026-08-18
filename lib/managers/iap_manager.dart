import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_manager.dart';
import 'profile_manager.dart';

/// 앱 카탈로그의 상품 하나가 소비형(consumable, 반복 구매 가능 — 보석
/// 패키지)인지 비소비형(non-consumable, 계정당 평생 1회 — 광고 제거
/// 패스)인지. 두 종류는 스토어 API 호출 자체가 다르므로([InAppPurchase]
/// .buyConsumable`/`.buyNonConsumable`) [IAPManager.buy]가 이 값으로
/// 분기한다.
enum IapProductKind { consumable, nonConsumable }

/// 이 앱이 파는 상품 하나의 정의 — [id]는 반드시 Google Play Console/App
/// Store Connect에 등록한 상품 ID와 정확히 같은 문자열이어야 한다(다르면
/// [ProductDetailsResponse.notFoundIDs]에 걸려 스토어에서 가격을 아예 못
/// 받아온다).
class IapProduct {
  const IapProduct({required this.id, required this.kind, this.gemAmount});

  final String id;
  final IapProductKind kind;

  /// consumable 전용 — 구매 성공 시 지급할 보석 개수. nonConsumable(광고
  /// 제거 패스)은 항상 null이다.
  final int? gemAmount;
}

/// 인앱 결제(IAP)를 총괄하는 싱글턴 — 상품 카탈로그 정의, 스토어 상품 정보
/// 조회, 구매 요청, 구매 스트림 처리, 구매 성공 시 실제 게임 보상 지급까지
/// 전부 이 클래스 하나로 수렴한다.
///
/// ## 상품 카탈로그
/// - [removeAdsProductId](non-consumable): 광고 제거 영구 패스. 구매 성공 시
///   [ProfileManager.setAdFree]로 계정 전체에 영구 반영된다.
/// - [gemPack1000ProductId]/[gemPack5000ProductId](consumable): 보석
///   1,000개/5,000개. 구매 성공 시 [GameManager.addGems]로 즉시 지급된다.
///
/// ## 중복 지급 방지
/// consumable은 같은 구매가 두 번 전달되면(예: [completePurchase] 호출
/// 전에 앱이 죽어 다음 실행 때 같은 트랜잭션이 재전달되는 경우) 보석을 두
/// 번 줄 위험이 있다 — [_processedPurchaseIds]에 이미 처리한 구매 id를
/// 영구 기록해 두고, 재전달돼도 지급은 건너뛰되 [completePurchase]는 항상
/// 호출해 대기 중인 트랜잭션을 정리한다.
///
/// ## ⚠️ 보안 주의사항 (실제 출시 전 필수)
/// 이 클래스는 스토어가 [PurchaseDetails.status]를 `purchased`로 알려주면
/// 그대로 신뢰하고 보상을 지급한다 — 클라이언트 단에서 영수증
/// ([PurchaseDetails.verificationData])의 서버 측 검증(Apple/Google
/// 서버에 실제로 유효한 결제인지 재확인)은 하지 않는다. 클라이언트만으로는
/// 위변조된 로컬 결제 응답을 걸러낼 수 없으므로(루팅/탈옥 기기 등),
/// 실제 스토어 출시 전에는 Supabase Edge Function 등 서버에서
/// `verificationData.serverVerificationData`를 Apple/Google에 검증
/// 요청하는 절차를 반드시 추가해야 한다. 지금 구조는 어디에 그 검증
/// 호출을 끼워 넣어야 하는지(`_deliverProduct` 진입 직후) 명확히
/// 드러나도록만 만들어 뒀다.
class IAPManager extends ChangeNotifier {
  IAPManager._internal();

  static final IAPManager instance = IAPManager._internal();

  static const String removeAdsProductId = 'remove_ads_permanent';
  static const String gemPack1000ProductId = 'gem_pack_1000';
  static const String gemPack5000ProductId = 'gem_pack_5000';

  static const List<IapProduct> catalog = [
    IapProduct(id: removeAdsProductId, kind: IapProductKind.nonConsumable),
    IapProduct(id: gemPack1000ProductId, kind: IapProductKind.consumable, gemAmount: 1000),
    IapProduct(id: gemPack5000ProductId, kind: IapProductKind.consumable, gemAmount: 5000),
  ];

  /// [InAppPurchase.instance]를 곧바로 필드 초기화식으로 잡아 두면(예전
  /// 코드), 그 게터 내부의 플러그인 자체 `late` 싱글턴이 아직 준비되지
  /// 않은 환경(대표적으로 웹 — `in_app_purchase_platform_interface`의
  /// 플랫폼 구현체가 web에는 등록되지 않는다, 실측 확인됨)에서
  /// `LateInitializationError`를 던지며 [IAPManager._internal()] 생성자
  /// 자체가 실패한다 — 그 생성자는 `IAPManager.instance`를 맨 처음 참조하는
  /// 순간(main.dart의 부팅 시퀀스) 실행되므로, 앱 전체가 시작도 못 하고
  /// 죽는다. 그래서 이 필드는 `late`도 즉시 초기화도 아니고, 실제로 결제
  /// 기능이 필요한 시점([_resolveIap])에만 안전하게(try/catch) 접근한다.
  InAppPurchase? _iap;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  /// [_iap]를 안전하게 확보한다 — 웹(kIsWeb)이거나 플러그인 초기화 자체가
  /// 실패하면 null을 반환해 호출부가 결제 기능을 조용히 건너뛰게 한다
  /// (이 프로젝트의 다른 매니저들과 같은 "부가 기능 실패가 앱 부팅/동작을
  /// 막지 않는다" 관례 — [AdManager]/[NotificationManager]가 지원하지
  /// 않는 플랫폼을 건너뛰는 것과 동일).
  InAppPurchase? _resolveIap() {
    if (kIsWeb) {
      return null;
    }
    final InAppPurchase? cached = _iap;
    if (cached != null) {
      return cached;
    }
    try {
      final InAppPurchase resolved = InAppPurchase.instance;
      _iap = resolved;
      return resolved;
    } catch (error) {
      debugPrint('[IAPManager] InAppPurchase.instance 초기화 실패 — 결제 기능을 비활성화합니다: $error');
      return null;
    }
  }

  /// 이 기기/플랫폼에서 결제 자체를 지원하는지 — false면 스토어 조회/구매를
  /// 전부 시도하지 않는다(예: 에뮬레이터, 스토어 미로그인 등).
  bool isAvailable = false;

  /// [catalog]의 각 상품 id에 대해 스토어가 돌려준 실제 상품 정보(가격/
  /// 통화 등) — [loadData]가 채운다. 아직 로드 전이거나 스토어에 등록되지
  /// 않은 상품은 여기 없다.
  List<ProductDetails> products = [];

  /// 스토어에 아직 등록되지 않은(또는 오타 등으로 못 찾은) 카탈로그 상품
  /// id — 개발 중 진단용. 실제 배포 전 반드시 비어 있어야 한다.
  List<String> notFoundProductIds = const [];

  final Set<String> _pendingProductIds = {};

  /// 마지막 구매 실패 사유 — 상점 UI가 토스트 등으로 보여줄 때 읽는다.
  String? lastErrorMessage;

  bool isPending(String productId) => _pendingProductIds.contains(productId);

  ProductDetails? _productDetailsFor(String productId) {
    for (final ProductDetails details in products) {
      if (details.id == productId) {
        return details;
      }
    }
    return null;
  }

  IapProduct? _catalogEntryFor(String productId) {
    for (final IapProduct product in catalog) {
      if (product.id == productId) {
        return product;
      }
    }
    return null;
  }

  Set<String> _processedPurchaseIds = {};

  /// main()이 앱 시작 시 한 번 호출 — 결제 지원 여부 확인, 구매 스트림
  /// 구독 시작(반드시 앱 초반에 구독해야 이전 세션에서 못 끝낸 트랜잭션의
  /// 재전달을 놓치지 않는다 — [InAppPurchase.purchaseStream] 문서 참고),
  /// 스토어 상품 정보 조회까지 끝낸다.
  Future<void> loadData() async {
    await _loadProcessedPurchaseIds();

    final InAppPurchase? iap = _resolveIap();
    if (iap == null) {
      // kIsWeb이거나 플러그인 초기화 자체가 실패한 경우 — [_resolveIap]가
      // 이미 사유를 로그로 남겼으므로 여기서는 조용히 비활성화만 한다.
      isAvailable = false;
      notifyListeners();
      return;
    }

    // 이 블록 전체가 네이티브 플랫폼 채널(Google Play Billing/StoreKit)을
    // 두드린다 — 결제 플러그인이 아직 초기화되지 않았거나(테스트 환경 등)
    // 기기에 결제 서비스가 아예 없는 드문 경우에도, 이 프로젝트의 다른
    // 매니저들과 같은 관례대로 앱 시작 자체는 절대 막지 않아야 한다.
    try {
      isAvailable = await iap.isAvailable();
    } catch (error) {
      debugPrint('[IAPManager] 결제 지원 여부 확인 실패: $error');
      isAvailable = false;
    }
    if (!isAvailable) {
      debugPrint('[IAPManager] 이 플랫폼/기기에서는 인앱 결제를 사용할 수 없습니다.');
      notifyListeners();
      return;
    }

    try {
      _subscription = iap.purchaseStream.listen(
        _onPurchaseUpdate,
        onDone: () => _subscription?.cancel(),
        onError: (Object error) => debugPrint('[IAPManager] 구매 스트림 오류: $error'),
      );

      final ProductDetailsResponse response =
          await iap.queryProductDetails(catalog.map((product) => product.id).toSet());
      if (response.error != null) {
        debugPrint('[IAPManager] 상품 조회 실패: ${response.error}');
      }
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint(
          '[IAPManager] 스토어에 등록되지 않은 상품 ID: ${response.notFoundIDs} '
          '— Play Console/App Store Connect에서 먼저 등록해야 가격이 표시된다.',
        );
      }
      products = response.productDetails;
      notFoundProductIds = response.notFoundIDs;
    } catch (error) {
      debugPrint('[IAPManager] 상품 조회 중 오류: $error');
    }
    notifyListeners();
  }

  /// [productId] 상품 구매를 시작한다 — 실제 성공/실패는 이 호출이 아니라
  /// [purchaseStream](→ [_onPurchaseUpdate])로 비동기 전달된다. 상품 정보를
  /// 아직 못 받아왔으면(스토어 미등록/오프라인) 아무 일도 하지 않는다.
  Future<void> buy(String productId) async {
    final InAppPurchase? iap = _resolveIap();
    final ProductDetails? details = _productDetailsFor(productId);
    final IapProduct? catalogEntry = _catalogEntryFor(productId);
    if (iap == null || details == null || catalogEntry == null || isPending(productId)) {
      return;
    }

    _pendingProductIds.add(productId);
    notifyListeners();

    try {
      final PurchaseParam param = PurchaseParam(productDetails: details);
      final bool started = catalogEntry.kind == IapProductKind.consumable
          ? await iap.buyConsumable(purchaseParam: param, autoConsume: true)
          : await iap.buyNonConsumable(purchaseParam: param);

      if (!started) {
        // 스토어 결제창 자체를 못 띄운 경우(드묾) — 대기 상태를 바로
        // 풀어준다. 정상적으로 창이 뜬 뒤의 성공/실패/취소는 전부
        // purchaseStream이 처리한다.
        _pendingProductIds.remove(productId);
        notifyListeners();
      }
    } catch (error) {
      debugPrint('[IAPManager] 구매 요청 실패($productId): $error');
      lastErrorMessage = error.toString();
      _pendingProductIds.remove(productId);
      notifyListeners();
    }
  }

  /// 기기 변경/재설치 후 비소비형 상품(광고 제거 패스)을 복원한다 —
  /// App Store 심사 가이드라인이 요구하는 필수 기능이라 상점 UI에 항상
  /// 버튼으로 노출해야 한다. 복원된 항목은 [purchaseStream]에
  /// [PurchaseStatus.restored]로 전달된다.
  Future<void> restorePurchases() async {
    final InAppPurchase? iap = _resolveIap();
    if (iap == null) {
      return;
    }
    try {
      await iap.restorePurchases();
    } catch (error) {
      debugPrint('[IAPManager] 구매 복원 실패: $error');
      lastErrorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final PurchaseDetails purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          _pendingProductIds.add(purchase.productID);
          notifyListeners();
        case PurchaseStatus.error:
          lastErrorMessage = purchase.error?.message;
          _pendingProductIds.remove(purchase.productID);
          notifyListeners();
        case PurchaseStatus.canceled:
          _pendingProductIds.remove(purchase.productID);
          notifyListeners();
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _deliverProduct(purchase);
          _pendingProductIds.remove(purchase.productID);
          notifyListeners();
      }

      // 이 콜백은 loadData()가 [_resolveIap]로 확보해 캐시해 둔 [_iap]의
      // purchaseStream 구독에서만 오므로 이 시점엔 항상 non-null이지만,
      // 널 안전을 위해 그래도 방어적으로 접근한다.
      if (purchase.pendingCompletePurchase) {
        await _iap?.completePurchase(purchase);
      }
    }
  }

  /// 실제 게임 보상을 지급한다 — 여기가 서버 영수증 검증을 끼워 넣어야 할
  /// 지점이다(클래스 문서의 "보안 주의사항" 참고). 같은 구매가 두 번
  /// 전달돼도([_processedPurchaseIds]에 이미 있으면) 보상은 다시 주지
  /// 않는다.
  Future<void> _deliverProduct(PurchaseDetails purchase) async {
    final IapProduct? catalogEntry = _catalogEntryFor(purchase.productID);
    if (catalogEntry == null) {
      debugPrint('[IAPManager] 카탈로그에 없는 상품의 구매 이벤트를 받았습니다: ${purchase.productID}');
      return;
    }

    final String dedupeKey = purchase.purchaseID ?? '${purchase.productID}_${purchase.transactionDate}';
    if (_processedPurchaseIds.contains(dedupeKey)) {
      debugPrint('[IAPManager] 이미 처리한 구매를 다시 건너뜁니다: $dedupeKey');
      return;
    }

    switch (catalogEntry.kind) {
      case IapProductKind.nonConsumable:
        if (catalogEntry.id == removeAdsProductId) {
          await ProfileManager.instance.setAdFree(true);
        }
      case IapProductKind.consumable:
        final int amount = catalogEntry.gemAmount ?? 0;
        if (amount > 0) {
          GameManager.instance.addGems(amount);
          // 실제 결제로 얻은 재화라 다음 주기적 저장을 기다리지 않고 즉시
          // 디스크에 반영한다 — 지급 직후 앱이 죽어도 보석이 사라지면 안 된다.
          await GameManager.instance.saveGame();
        }
    }

    await _markPurchaseProcessed(dedupeKey);
  }

  static const String _processedPurchasesSaveKey = 'iap_manager_processed_purchases';

  Future<void> _loadProcessedPurchaseIds() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_processedPurchasesSaveKey);
    if (raw == null) {
      return;
    }
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      _processedPurchaseIds = decoded.cast<String>().toSet();
    } catch (error) {
      debugPrint('[IAPManager] 처리된 구매 내역 캐시가 손상되어 건너뜁니다: $error');
    }
  }

  Future<void> _markPurchaseProcessed(String dedupeKey) async {
    _processedPurchaseIds.add(dedupeKey);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_processedPurchasesSaveKey, jsonEncode(_processedPurchaseIds.toList()));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
