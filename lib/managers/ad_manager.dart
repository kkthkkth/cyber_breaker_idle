import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/time_util.dart';
import 'notification_manager.dart';
import 'supabase_manager.dart';

/// 보상형 광고(Rewarded Ads) 시청/제한을 관장하는 싱글턴 — 광고 단위 ID를
/// 하드코딩하지 않고 `ad_unit_config` 테이블에서 현재 플랫폼에 맞는 값을
/// 받아와 로드한다(요구사항: "앱 업데이트 없이 광고 교체 가능"). 시청
/// 횟수/쿨타임은 `profiles.daily_ad_views`/`last_ad_viewed_at`을 서버에도
/// 동기화하지만, 이 프로젝트의 다른 매니저들과 같은 관례대로 로컬
/// (SharedPreferences)이 즉시 판정의 1차 소스이고 서버는 기기 간 정합성을
/// 맞추는 부가 계층이다.
///
/// [google_mobile_ads]는 Android/iOS 전용 플러그인이라(Web/Windows/Linux/
/// macOS 데스크톱은 네이티브 구현이 없다), [isSupportedPlatform]이 false인
/// 플랫폼에서는 초기화/로드/표시를 전부 조용히 건너뛴다 — 이 프로젝트가
/// `flutter build web`/데스크톱 빌드도 함께 유지하므로, 지원하지 않는
/// 플랫폼에서 플러그인 채널 호출로 인한 크래시가 나면 안 된다.
///
/// [주의] AndroidManifest.xml/Info.plist에 넣어 둔 App ID는 Google이
/// 공개한 "테스트용 ID"다 — 실제 배포 전 AdMob 콘솔에서 발급받은 진짜 App
/// ID로 반드시 교체해야 한다(테스트 ID로는 실제 광고가 채워지지 않는다).
/// `ad_unit_config`에 아직 행이 없어도(운영 등록 전) 같은 이유로 테스트용
/// 보상형 광고 단위 ID로 폴백해 개발 중에도 동작을 확인할 수 있게 했다.
class AdManager extends ChangeNotifier {
  AdManager._internal();

  static final AdManager instance = AdManager._internal();

  /// 하루 최대 시청 횟수 — 4곳(코인/펫 상자/장비 상자/캐릭터 상자) 버튼이
  /// 전부 이 카운터 하나를 공유한다(요구사항의 `daily_ad_views`가 단수
  /// 컬럼 하나이므로, 어느 버튼으로 보든 같이 줄어든다).
  static const int maxDailyViews = 5;

  /// 시청 1회 이후 다음 시청까지의 쿨타임.
  static const Duration cooldown = Duration(hours: 1);

  /// Google 공개 테스트용 보상형 광고 단위 ID — `ad_unit_config`에서 값을
  /// 못 받아왔을 때만(운영 미등록/오프라인) 폴백으로 쓴다.
  static const String _testRewardedAdUnitIdAndroid = 'ca-app-pub-3940256099942544/5224354917';
  static const String _testRewardedAdUnitIdIOS = 'ca-app-pub-3940256099942544/1712485313';

  String? _rewardedAdUnitId;
  RewardedAd? _rewardedAd;
  bool _isLoadingAd = false;

  int dailyAdViews = 0;
  DateTime? lastAdViewedAt;
  String? _lastResetDate;

  Timer? _cooldownTicker;

  bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  bool get hasDailyViewsLeft => dailyAdViews < maxDailyViews;

  /// 지금 이 순간 남은 쿨타임 — 매초 [notifyListeners]가 다시 계산해
  /// 호출부(상점 화면의 "남은 시간 (59:59)" 텍스트)가 실시간으로 줄어들게
  /// 한다.
  Duration get cooldownRemaining {
    final DateTime? last = lastAdViewedAt;
    if (last == null) {
      return Duration.zero;
    }
    final Duration remaining = cooldown - DateTime.now().difference(last);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool get isOnCooldown => cooldownRemaining > Duration.zero;

  /// 지금 광고를 시청할 수 있는지 — 플랫폼 지원 + 일일 횟수 + 쿨타임 +
  /// 실제로 로드된 광고가 있는지까지 전부 만족해야 true.
  bool get canWatchAd =>
      isSupportedPlatform && hasDailyViewsLeft && !isOnCooldown && _rewardedAd != null;

  /// 단위 테스트 전용 — 실제 광고/네트워크 없이 카운터 상태를 직접
  /// 주입한다([RookieAttendanceManager.debugSeedForTest]와 같은 관례).
  @visibleForTesting
  void debugSeedForTest({int? dailyAdViews, DateTime? lastAdViewedAt, String? lastResetDate}) {
    if (dailyAdViews != null) {
      this.dailyAdViews = dailyAdViews;
    }
    if (lastAdViewedAt != null) {
      this.lastAdViewedAt = lastAdViewedAt;
    }
    if (lastResetDate != null) {
      _lastResetDate = lastResetDate;
    }
  }

  /// 단위 테스트 전용 — [canWatchAd]가 실제 로드된 광고 유무까지 확인하면
  /// 테스트에서 항상 false가 되므로, 로드 여부와 무관하게 카운터/쿨타임
  /// 판정만 확인할 때 쓴다.
  @visibleForTesting
  bool get debugCanWatchAdIgnoringAdLoad => isSupportedPlatform && hasDailyViewsLeft && !isOnCooldown;

  /// 단위 테스트 전용 — [_checkAndResetDaily]를 네트워크 없이 직접 한 번
  /// 돌려본다.
  @visibleForTesting
  Future<void> debugCheckAndResetDailyForTest(DateTime now) => _checkAndResetDaily(now);

  /// 단위 테스트 전용 — [_lastResetDate]를 직접 읽고 쓴다(null로도 되돌릴
  /// 수 있어 "첫 관측" 분기를 테스트할 수 있다 — [debugSeedForTest]는 null
  /// 대입을 지원하지 않는다).
  @visibleForTesting
  String? get debugLastResetDate => _lastResetDate;

  @visibleForTesting
  set debugLastResetDate(String? value) => _lastResetDate = value;

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 채운 뒤, 서버에서
  /// 광고 단위 ID/시청 상태를 다시 확인하고, 지원 플랫폼이면 광고 SDK를
  /// 초기화해 첫 광고를 미리 로드해 둔다.
  Future<void> loadData() async {
    await _loadLocal();

    final String platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
    final String testFallback =
        defaultTargetPlatform == TargetPlatform.iOS ? _testRewardedAdUnitIdIOS : _testRewardedAdUnitIdAndroid;
    _rewardedAdUnitId = await SupabaseManager.instance.fetchRewardedAdUnitId(platform) ?? testFallback;

    final ({int dailyAdViews, DateTime? lastAdViewedAt})? serverState =
        await SupabaseManager.instance.fetchAdViewState();
    if (serverState != null) {
      dailyAdViews = serverState.dailyAdViews;
      lastAdViewedAt = serverState.lastAdViewedAt;
    }

    final DateTime now = await getNetworkTime();
    await _checkAndResetDaily(now);
    await _saveLocal();
    _startCooldownTicker();
    notifyListeners();

    if (isSupportedPlatform) {
      await MobileAds.instance.initialize();
      _loadRewardedAd();
    }
  }

  /// 쿨타임 표시가 실시간으로 줄어들도록 매초 다시 그리게 한다 — 쿨타임이
  /// 없는(한 번도 광고를 안 본) 동안엔 굳이 매초 알림을 쏘지 않는다.
  void _startCooldownTicker() {
    _cooldownTicker?.cancel();
    _cooldownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (lastAdViewedAt != null) {
        notifyListeners();
      }
    });
  }

  /// [DungeonManager.checkAndResetDailyCounts]와 동일한 관례 — 서버(NTP)
  /// 시간 기준 `yyyy-MM-dd` 커서가 오늘과 다르면 [dailyAdViews]를 0으로
  /// 되돌린다. 로컬 커서가 아예 없으면(최초 실행/재설치) 서버에서 이미
  /// 받아온 값이 실제로는 "오늘" 값일 수 있어 지우지 않고 기준점만 잡는다
  /// ([RookieAttendanceManager]와 같은 "첫 관측은 베이스라인만" 관례).
  Future<void> _checkAndResetDaily(DateTime now) async {
    final String today = _formatDate(now);
    if (_lastResetDate == today) {
      return;
    }
    final bool isFirstObservation = _lastResetDate == null;
    _lastResetDate = today;
    if (!isFirstObservation) {
      dailyAdViews = 0;
    }
  }

  void _loadRewardedAd() {
    final String? unitId = _rewardedAdUnitId;
    if (unitId == null || _isLoadingAd || _rewardedAd != null) {
      return;
    }
    _isLoadingAd = true;
    RewardedAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isLoadingAd = false;
          notifyListeners();
        },
        onAdFailedToLoad: (error) {
          debugPrint('[AdManager] 보상형 광고 로드 실패: $error');
          _isLoadingAd = false;
        },
      ),
    );
  }

  /// 로드된 광고를 실제로 보여준다 — 끝까지 시청해 보상을 실제로 받았을
  /// 때만 true를 돌려주고([RewardedAd]의 `onUserEarnedReward`), 중간에
  /// 닫거나 표시 자체에 실패하면 false. 호출부([_AdRewardCard])는 이
  /// 반환값이 true일 때만 실제 게임 보상(골드/상자)을 지급한다 — 광고
  /// 시청과 게임 보상 지급을 분리해서, 이 매니저는 "시청했는지"만 책임지고
  /// 무엇을 줄지는 호출부가 결정한다.
  Future<bool> showRewardedAd() async {
    if (!canWatchAd) {
      return false;
    }
    final RewardedAd ad = _rewardedAd!;
    _rewardedAd = null;

    bool earned = false;
    final Completer<bool> completer = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (dismissedAd) {
        dismissedAd.dispose();
        _loadRewardedAd();
        if (!completer.isCompleted) {
          completer.complete(earned);
        }
      },
      onAdFailedToShowFullScreenContent: (failedAd, error) {
        debugPrint('[AdManager] 보상형 광고 표시 실패: $error');
        failedAd.dispose();
        _loadRewardedAd();
        if (!completer.isCompleted) {
          completer.complete(false);
        }
      },
    );

    await ad.show(
      onUserEarnedReward: (adWithoutView, reward) {
        earned = true;
      },
    );

    final bool success = await completer.future;
    if (success) {
      await _recordAdWatched();
    }
    return success;
  }

  Future<void> _recordAdWatched() async {
    final DateTime now = await getNetworkTime();
    await _checkAndResetDaily(now);
    dailyAdViews += 1;
    lastAdViewedAt = now;
    notifyListeners();
    await _saveLocal();
    unawaited(
      SupabaseManager.instance.upsertAdViewState(
        dailyAdViews: dailyAdViews,
        lastAdViewedAtIso: now.toIso8601String(),
      ),
    );
    // 요구사항: "광고를 본 직후 정확히 1시간 뒤" 상점 무료 보상 알림 예약.
    if (NotificationManager.instance.isSupportedPlatform) {
      unawaited(NotificationManager.instance.scheduleAdRewardReminder(delay: cooldown));
    }
  }

  static String _formatDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static const String _saveKey = 'ad_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode({
        'dailyAdViews': dailyAdViews,
        'lastAdViewedAt': lastAdViewedAt?.toIso8601String(),
        'lastResetDate': _lastResetDate,
      }),
    );
  }

  Future<void> _loadLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      return;
    }
    try {
      final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
      dailyAdViews = (data['dailyAdViews'] as num?)?.toInt() ?? 0;
      final String? lastAdViewedRaw = data['lastAdViewedAt'] as String?;
      lastAdViewedAt = lastAdViewedRaw == null ? null : DateTime.tryParse(lastAdViewedRaw);
      _lastResetDate = data['lastResetDate'] as String?;
    } catch (error) {
      debugPrint('[AdManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }
  }

  @override
  void dispose() {
    _cooldownTicker?.cancel();
    _rewardedAd?.dispose();
    super.dispose();
  }
}
