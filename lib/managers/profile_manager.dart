import 'package:flutter/foundation.dart';

/// 로그인한 유저의 프로필(닉네임)을 앱 전역에서 참조할 수 있게 들고 있는
/// 가벼운 싱글턴 — 이 프로젝트의 다른 매니저들과 같은 관례(정적 [instance])
/// 를 따르되, `profiles.nickname`은 서버(Supabase)가 유일한 신뢰 소스라
/// SharedPreferences에 별도로 영속화하지 않는다(로그인 직후 항상
/// [SupabaseManager.fetchNickname]으로 새로 채워진다 — [LoginScreen]의
/// `_routeAfterAuth` 참고).
///
/// [StoryDialogWidget]이 "지휘관" 플레이스홀더 화자를 실제 닉네임으로
/// 치환해 보여줄 때 이 값을 읽는다.
class ProfileManager extends ChangeNotifier {
  ProfileManager._internal();

  static final ProfileManager instance = ProfileManager._internal();

  String? _nickname;

  /// 아직 로그인 전이거나 닉네임을 설정하지 않은 유저면 null.
  String? get nickname => _nickname;

  void setNickname(String? nickname) {
    if (_nickname == nickname) {
      return;
    }
    _nickname = nickname;
    notifyListeners();
  }

  /// 로그아웃 시 이전 유저의 닉네임이 다음 유저 화면에 잠깐이라도 새어
  /// 보이지 않도록 초기화한다.
  void clear() => setNickname(null);
}
