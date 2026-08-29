import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cloudflare R2에 비공개로 보관된 게임 에셋(일러스트 등)의 Presigned URL을
/// 발급받아 재사용하는 싱글턴 — Supabase Edge Function
/// `get-r2-url`(`supabase/functions/get-r2-url/index.ts`)이 실제 서명을
/// 담당하고, 이 매니저는 그 결과를 메모리에 캐싱해 같은 이미지를 반복
/// 렌더링할 때마다 Edge Function을 다시 호출하지 않게 한다.
///
/// [주의: 캐시는 "영원히"가 아니라 "발급된 URL의 유효기간 동안만"이다]
/// 서명 URL은 1시간이 지나면 서버(R2)가 요청 자체를 거부한다 — 단순히
/// `Map<String, String>`에 값을 넣고 끝까지 재사용하면, 딱 1시간 뒤부터
/// 캐시가 "유효해 보이지만 실제로는 죽은" URL을 계속 돌려주게 되고,
/// 이미지가 아무 경고 없이 안 보이기 시작한다(방치형 게임 특성상 유저가
/// 탭을 몇 시간씩 켜 두는 경우가 흔해서 실제로 부딪힐 확률이 높다). 그래서
/// 각 캐시 항목에 만료 시각을 함께 저장해 두고, 실제 만료보다
/// [_refreshMargin]만큼 미리 "낡음" 처리해 새로 발급받는다 — "꺼내 쓰려는
/// 순간 방금 만료됐다" 같은 경계 상황도 피한다.
///
/// [주의: 아직 인프라 연결 전] 이 클래스는 R2/Edge Function 인프라가
/// 준비되기 전에 미리 작성해 둔 것이다 — 기존
/// [CustomSafeImage]/`RemoteSpriteLoader` 호출부는 아직 이 매니저를 쓰도록
/// 바뀌지 않았다. R2 버킷에 에셋이 올라가고 `get-r2-url`이 배포된 뒤에
/// 그 호출부들을 이 매니저를 쓰도록 바꾸는 작업이 별도로 필요하다(지금
/// 미리 전부 바꿔 버리면, 그 인프라가 실제로 준비되기 전까지 게임 이미지가
/// 전부 깨진다).
class StorageManager {
  StorageManager._internal();

  static final StorageManager instance = StorageManager._internal();

  static const String _functionName = 'get-r2-url';

  /// Edge Function이 요청마다 실제 유효기간을 응답(`expiresIn`)으로
  /// 같이 내려주지만, 그 값을 못 받은 경우(응답 형식이 예상과 다른 등)를
  /// 대비한 안전한 기본값 — Edge Function 쪽 `PRESIGNED_URL_EXPIRES_IN_SECONDS`
  /// (3600)와 맞춰 뒀다.
  static const Duration _defaultUrlLifetime = Duration(seconds: 3600);

  /// 실제 만료 시각보다 이만큼 미리 캐시를 "낡음" 처리한다 — 1시간 중
  /// 5분이면 충분한 여유다.
  static const Duration _refreshMargin = Duration(minutes: 5);

  final Map<String, _CachedUrl> _cache = {};

  /// 같은 key를 여러 위젯이 동시에(캐시가 비어 있는 상태에서) 요청하면
  /// (예: 같은 캐릭터 아이콘이 목록에 여러 번 보이는 경우) Edge Function을
  /// 그 개수만큼 따로 부르지 않도록, 이미 진행 중인 요청의 Future를 그대로
  /// 공유한다.
  final Map<String, Future<String?>> _pendingRequests = {};

  /// [key](R2 오브젝트 키, 예: `characters/n1/n1_run1.png` — 슬래시로
  /// 시작하지 않는 상대 경로)의 임시 서명 URL을 반환한다.
  ///
  /// 캐시에 아직 유효한 값이 있으면 네트워크 요청 없이 즉시 반환하고,
  /// 없거나 만료가 임박했으면 Edge Function을 호출해 새로 받아온다.
  /// 실패하면(오프라인, 아직 배포 전인 함수, R2에 없는 키 등) null을
  /// 반환한다 — 호출부가 [CustomSafeImage]의 fallback 관례와 같은 방식으로
  /// placeholder를 보여주면 된다(이 매니저 자체는 예외를 던지지 않는다).
  Future<String?> imageUrl(String key) async {
    final _CachedUrl? cached = _cache[key];
    if (cached != null && !cached.isStaleAt(DateTime.now())) {
      return cached.url;
    }

    final Future<String?>? inFlight = _pendingRequests[key];
    if (inFlight != null) {
      return inFlight;
    }

    final Future<String?> request = _fetchAndCache(key);
    _pendingRequests[key] = request;
    try {
      return await request;
    } finally {
      _pendingRequests.remove(key);
    }
  }

  Future<String?> _fetchAndCache(String key) async {
    try {
      final FunctionResponse response = await Supabase.instance.client.functions
          .invoke(_functionName, body: {'objectKey': key});
      final dynamic data = response.data;
      final String? url = data is Map ? data['url'] as String? : null;
      if (url == null) {
        debugPrint('[StorageManager] URL 발급 실패($key): 응답에 url이 없습니다 — $data');
        return null;
      }
      final int expiresInSeconds = data is Map ? (data['expiresIn'] as int? ?? -1) : -1;
      final Duration lifetime = expiresInSeconds > 0
          ? Duration(seconds: expiresInSeconds)
          : _defaultUrlLifetime;
      // 유효기간이 리프레시 여유(_refreshMargin)보다 짧으면(예상 밖으로
      // 아주 짧게 발급된 경우) 음수 Duration이 되어 매번 즉시 재요청하는
      // 사고가 나므로, 최소 0으로 눌러 둔다.
      final Duration safeLifetime = lifetime > _refreshMargin
          ? lifetime - _refreshMargin
          : Duration.zero;
      _cache[key] = _CachedUrl(
        url: url,
        staleAt: DateTime.now().add(safeLifetime),
      );
      return url;
    } catch (error) {
      debugPrint('[StorageManager] URL 발급 실패($key): $error');
      return null;
    }
  }

  /// 캐시 전체를 비운다 — 로그아웃/계정 전환처럼 이전에 발급받은 서명
  /// URL의 근거(세션)가 바뀌는 시점에 호출한다. 개별 URL은 어차피
  /// 시간이 지나면 스스로 낡음 처리되므로, 평소 게임플레이 중에는 호출할
  /// 필요가 없다.
  void clearCache() {
    _cache.clear();
    _pendingRequests.clear();
  }
}

class _CachedUrl {
  const _CachedUrl({required this.url, required this.staleAt});

  final String url;

  /// 이 시각을 지나면 캐시를 신뢰하지 않고 다시 발급받는다 — 실제 R2
  /// 서명 만료 시각보다 [StorageManager._refreshMargin]만큼 이르다.
  final DateTime staleAt;

  bool isStaleAt(DateTime now) => !now.isBefore(staleAt);
}
