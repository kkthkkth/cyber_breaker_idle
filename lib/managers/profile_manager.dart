import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_manager.dart';

/// 로그인한 유저의 프로필(닉네임, 광고 제거 구매 여부)을 앱 전역에서
/// 참조할 수 있게 들고 있는 가벼운 싱글턴 — 이 프로젝트의 다른 매니저들과
/// 같은 관례(정적 [instance])를 따른다.
///
/// `nickname`은 서버(Supabase)가 유일한 신뢰 소스라 SharedPreferences에
/// 별도로 영속화하지 않는다(로그인 직후 항상 [SupabaseManager.fetchNickname]
/// 으로 새로 채워진다 — [LoginScreen]의 `_routeAfterAuth` 참고).
///
/// `isAdFree`(인앱 결제로 구매하는 영구 상태)는 반대로 로컬 캐시를 1차
/// 소스로 쓴다 — 오프라인이어도 이미 구매한 유저가 앱을 켜자마자 곧바로
/// 반영돼야 하기 때문이다([loadData] 참고, 다른 매니저들의 "로컬 우선 +
/// 서버 백업 동기화" 관례와 동일).
///
/// [StoryDialogWidget]이 "지휘관" 플레이스홀더 화자를 실제 닉네임으로
/// 치환해 보여줄 때 [nickname]을 읽는다.
class ProfileManager extends ChangeNotifier {
  ProfileManager._internal();

  static final ProfileManager instance = ProfileManager._internal();

  String? _nickname;
  bool _isAdFree = false;

  /// 아직 로그인 전이거나 닉네임을 설정하지 않은 유저면 null.
  String? get nickname => _nickname;

  /// [IAPManager]가 광고 제거 영구 패스(`remove_ads_permanent`, non-
  /// consumable) 구매를 확인하면 true로 굳힌다. 한 번 true가 되면 이
  /// 세션 안에서는 다시 false로 내려가지 않는다([clear]에서 로그아웃 시
  /// 로컬 값만 초기화하는 경우 제외).
  bool get isAdFree => _isAdFree;

  void setNickname(String? nickname) {
    if (_nickname == nickname) {
      return;
    }
    _nickname = nickname;
    notifyListeners();
  }

  /// 로그인 직후([LoginScreen._routeAfterAuth]) 한 번 호출 — 로컬 캐시로
  /// [isAdFree]를 즉시 채운 뒤, `profiles.is_ad_free`로 서버 값을 다시
  /// 확인한다. 서버가 true라고 하면(다른 기기에서 구매했거나 재설치로
  /// 로컬 캐시가 사라진 경우) 항상 그 값을 신뢰해 로컬도 true로 맞춘다 —
  /// 반대로 서버가 false라고 로컬의 true를 덮어쓰지는 않는다(오프라인 구매
  /// 직후 아직 서버 동기화가 안 끝났을 수 있으므로, 한 번 true가 된 구매
  /// 확정 상태를 네트워크 타이밍 때문에 잃어버리면 안 된다).
  Future<void> loadData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _isAdFree = prefs.getBool(_adFreeSaveKey) ?? _isAdFree;

    final bool? serverValue = await SupabaseManager.instance.fetchIsAdFree();
    if (serverValue == true && !_isAdFree) {
      _isAdFree = true;
      await prefs.setBool(_adFreeSaveKey, true);
    }
    notifyListeners();
  }

  /// [IAPManager]가 광고 제거 패스 구매를 확인했을 때만 호출한다 —
  /// 로컬에 즉시 저장하고 서버에도 동기화(fire-and-forget)한다.
  Future<void> setAdFree(bool value) async {
    if (_isAdFree == value) {
      return;
    }
    _isAdFree = value;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_adFreeSaveKey, value);
    unawaited(SupabaseManager.instance.upsertIsAdFree(value));
  }

  static const String _adFreeSaveKey = 'profile_manager_is_ad_free';

  /// 로그아웃 시 이전 유저의 닉네임/광고 제거 상태가 다음 유저 화면에
  /// 잠깐이라도 새어 보이지 않도록 초기화한다 — 로컬 캐시 값 자체는
  /// 지우지 않는다(같은 기기에 같은 유저가 다시 로그인하면 [loadData]가
  /// 다시 그 캐시를 읽어야 하므로).
  void clear() {
    setNickname(null);
    if (_isAdFree) {
      _isAdFree = false;
      notifyListeners();
    }
  }
}
