import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// 기기 로컬 예약 알림(서버 푸시/FCM 아님)을 관장하는 싱글턴 — 유저가
/// 앱을 백그라운드로 내리거나(오프라인 보상 리마인드) 광고를 시청한
/// 직후(무료 보상 리마인드) 특정 시간 뒤에 울리도록 예약한다.
///
/// [flutter_local_notifications]는 Android/iOS/macOS/Linux는 지원하지만
/// Windows는 지원하지 않는다 — 이 프로젝트가 Windows/Web 빌드도 함께
/// 유지하므로, [isSupportedPlatform]이 false인 플랫폼에서는 초기화/예약을
/// 전부 조용히 건너뛴다(크래시 방지).
///
/// 시간대(timezone) 처리: [zonedSchedule]은 [tz.TZDateTime]을 요구하는데,
/// 이 매니저가 예약하는 알림은 전부 "지금으로부터 N시간 뒤"라는 상대
/// 시간이라 실제 발화 시각(내부적으론 UTC 기준 절대 시각/epoch)만
/// 정확하면 되고, 화면에 표시할 절대 시각 라벨이 필요한 게 아니다 —
/// 그래서 기기의 실제 시간대를 조회하는 별도 패키지 없이 [tz.UTC]를 로컬
/// 위치로 그대로 쓴다(발화 시점 자체는 시간대 표기와 무관하게 정확하다).
class NotificationManager {
  NotificationManager._internal();

  static final NotificationManager instance = NotificationManager._internal();

  /// 광고 시청 1시간 뒤 리마인드 — 다시 시청해도(여러 번 봐도) 매번 이
  /// id로 덮어써져 알림이 여러 개 쌓이지 않는다.
  static const int adRewardNotificationId = 1001;

  /// 앱을 백그라운드로 내린 뒤 8시간 후 오프라인 보상 리마인드 — 포그라운드로
  /// 복귀하면([cancelOfflineReminder]) 곧바로 취소된다.
  static const int offlineRewardNotificationId = 1002;

  static const AndroidNotificationDetails _androidDetails = AndroidNotificationDetails(
    'cyberbreaker_reminders',
    '보상 알림',
    channelDescription: '광고 시청/오프라인 보상 등 유저 복귀를 유도하는 알림',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static const NotificationDetails _details = NotificationDetails(
    android: _androidDetails,
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// main()이 앱 시작 시 한 번 호출 — 플러그인 초기화 + 알림 권한 요청까지
  /// 끝낸다. 지원하지 않는 플랫폼(Web/Windows)이면 아무것도 하지 않는다.
  Future<void> init() async {
    if (!isSupportedPlatform || _isInitialized) {
      return;
    }
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _isInitialized = true;

    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (error) {
      debugPrint('[NotificationManager] 알림 권한 요청 실패: $error');
    }
  }

  Future<void> _scheduleIn({
    required int id,
    required Duration delay,
    required String title,
    required String body,
  }) async {
    if (!isSupportedPlatform || !_isInitialized) {
      return;
    }
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.now(tz.local).add(delay),
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (error) {
      debugPrint('[NotificationManager] 알림 예약 실패(id=$id): $error');
    }
  }

  /// 요구사항 예시: "광고 시청 후 정확히 1시간 뒤 ➡️ 상점에서 무료 보상을
  /// 다시 받을 수 있습니다!" — `AdManager.showRewardedAd`가 보상 지급에
  /// 성공할 때마다 호출한다(다시 볼 때마다 이전 예약을 덮어쓴다). [delay]는
  /// `AdManager.cooldown`(1시간)을 그대로 넘겨받는다 — 이 매니저가
  /// AdManager를 직접 import하면 순환 의존(AdManager → NotificationManager
  /// → AdManager)이 생기므로, 값만 매개변수로 받는다.
  Future<void> scheduleAdRewardReminder({required Duration delay}) => _scheduleIn(
    id: adRewardNotificationId,
    delay: delay,
    title: '상점에 무료 보상이 도착했어요!',
    body: '상점에서 무료 보상을 다시 받을 수 있습니다!',
  );

  /// 요구사항 예시: "게임 종료 후 8시간 뒤 ➡️ 영웅들이 지쳤습니다! 접속해서
  /// 오프라인 보상을 수령하세요." — 앱이 백그라운드로 내려갈 때마다
  /// 호출한다.
  Future<void> scheduleOfflineReminder() => _scheduleIn(
    id: offlineRewardNotificationId,
    delay: const Duration(hours: 8),
    title: '영웅들이 지쳤습니다!',
    body: '영웅들이 지쳤습니다! 접속해서 오프라인 보상을 수령하세요.',
  );

  /// 포그라운드로 복귀했을 때 대기 중인 오프라인 보상 리마인드를 취소한다
  /// — 이미 돌아왔는데 몇 시간 뒤 뜬금없이 "접속해서 수령하세요" 알림이
  /// 오는 것을 막는다.
  Future<void> cancelOfflineReminder() async {
    if (!isSupportedPlatform || !_isInitialized) {
      return;
    }
    try {
      await _plugin.cancel(offlineRewardNotificationId);
    } catch (error) {
      debugPrint('[NotificationManager] 오프라인 보상 알림 취소 실패: $error');
    }
  }
}
