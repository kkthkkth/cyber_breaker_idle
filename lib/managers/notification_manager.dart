import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// 기기 로컬 예약 알림(서버 푸시/FCM 아님)을 관장하는 싱글턴 — 유저가
/// 앱을 백그라운드로 내리거나(오프라인 보상 리마인드) 광고를 시청한
/// 직후(무료 보상 리마인드) 특정 시간 뒤에, 또는 매주 토요일 저녁(길드
/// 전쟁 시작 알림)처럼 정해진 "요일+시각"에 울리도록 예약한다.
///
/// [flutter_local_notifications]는 Android/iOS/macOS/Linux는 지원하지만
/// Windows는 지원하지 않는다 — 이 프로젝트가 Windows/Web 빌드도 함께
/// 유지하므로, [isSupportedPlatform]이 false인 플랫폼에서는 초기화/예약을
/// 전부 조용히 건너뛴다(크래시 방지).
///
/// 시간대(timezone) 처리: [flutter_timezone]으로 기기의 실제 시간대(예:
/// 'Asia/Seoul')를 조회해 [tz.local]로 등록한다 — "지금으로부터 N시간
/// 뒤" 같은 상대 예약은 시간대와 무관하게 항상 정확하지만, "매주 토요일
/// 20:50"처럼 절대 시각(wall-clock)을 반복 예약하려면 기기의 실제
/// 시간대를 알아야만 그 지역 기준으로 정확히 그 시각에 울린다(예전엔
/// 이 조회 없이 UTC를 로컬처럼 썼는데, 상대 예약만 쓰던 동안은
/// 문제없었지만 절대 시각 반복 예약([scheduleWeeklyWarStartReminder])이
/// 추가되며 더 이상 안전하지 않다).
class NotificationManager {
  NotificationManager._internal();

  static final NotificationManager instance = NotificationManager._internal();

  /// 광고 시청 1시간 뒤 리마인드 — 다시 시청해도(여러 번 봐도) 매번 이
  /// id로 덮어써져 알림이 여러 개 쌓이지 않는다.
  static const int adRewardNotificationId = 1001;

  /// 앱을 백그라운드로 내린 뒤 8시간 후 오프라인 보상 리마인드 — 포그라운드로
  /// 복귀하면([cancelOfflineReminder]) 곧바로 취소된다.
  static const int offlineRewardNotificationId = 1002;

  /// 매주 토요일 20:50(전쟁 시작 10분 전) 리마인드 — [DateTimeComponents
  /// .dayOfWeekAndTime]로 한 번만 예약하면 매주 자동으로 반복된다.
  static const int warStartNotificationId = 1003;

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
    try {
      final String deviceTimeZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(deviceTimeZone));
    } catch (error) {
      // 조회 실패(알 수 없는 시간대 이름 등) 시 UTC로 폴백 — "매주 토요일
      // 20:50" 반복 예약은 그 지역 기준으로 어긋날 수 있지만, 최소한
      // 예약 자체가 죽거나 크래시가 나지는 않는다.
      debugPrint('[NotificationManager] 기기 시간대 조회 실패, UTC로 폴백: $error');
      tz.setLocalLocation(tz.UTC);
    }

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

  /// 요구사항: "토요일 오후 8시 50분(시작 10분 전)에 '곧 길드 전쟁이
  /// 시작됩니다!' 로컬 푸시 알림" — [DateTimeComponents.dayOfWeekAndTime]로
  /// 예약하면 최초 발화 이후 매주 같은 요일·시각에 자동으로 반복되므로,
  /// main() 시작 시 딱 한 번만 호출하면 된다(중복 호출해도 같은 id라
  /// 그냥 덮어써질 뿐 여러 개 쌓이지 않는다).
  Future<void> scheduleWeeklyWarStartReminder() async {
    if (!isSupportedPlatform || !_isInitialized) {
      return;
    }
    try {
      await _plugin.zonedSchedule(
        warStartNotificationId,
        '곧 길드 전쟁이 시작됩니다!',
        '10분 뒤 길드 전쟁이 시작돼요. 지금 바로 준비하세요!',
        _nextSaturday2050(),
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    } catch (error) {
      debugPrint('[NotificationManager] 길드 전쟁 알림 예약 실패: $error');
    }
  }

  /// 지금(로컬 시간대) 이후로 가장 가까운 토요일 20:50 — 이미 이번 주
  /// 토요일 20:50을 지났으면 다음 주 토요일로 넘어간다.
  static tz.TZDateTime _nextSaturday2050() {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime candidate = tz.TZDateTime(tz.local, now.year, now.month, now.day, 20, 50);
    // DateTime.saturday == 6.
    while (candidate.weekday != DateTime.saturday || !candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

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
