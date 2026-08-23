import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../managers/profile_manager.dart';
import '../managers/supabase_manager.dart';
import '../widgets/center_toast.dart';

/// [state]가 "방금 구글 로그인이 완료됐다"고 반응해야 할 이벤트인지
/// 판단한다 — [AuthChangeEvent.signedIn]이 아니면(콜드 스타트 세션 복원인
/// [AuthChangeEvent.initialSession] 등) 무시하고, provider가 google이
/// 아니면(게스트 로그인 등) 역시 무시한다. 순수 함수라 네트워크 없이 단위
/// 테스트할 수 있다.
@visibleForTesting
bool isFreshGoogleSignIn(AuthState state) {
  if (state.event != AuthChangeEvent.signedIn) {
    return false;
  }
  final User? user = state.session?.user;
  if (user == null) {
    return false;
  }
  return user.appMetadata['provider'] == 'google' ||
      (user.identities?.any((identity) => identity.provider == 'google') ?? false);
}

/// 앱 최초 진입 화면 — 로그인 상태를 확인해서 이미 로그인된 유저(게스트든
/// 구글이든, 그리고 닉네임까지 설정을 마친 유저)는 이 화면을 보여줄 새도
/// 없이 곧장 [GameEntryScreen]으로 넘기고, 로그인 정보가 없는 신규/로그아웃
/// 유저에게는 "게스트로 시작하기"/"구글 로그인" 두 버튼을 보여준다.
///
/// 배경 이미지는 아직 준비되지 않아 프로젝트 공용 다크 톤 단색
/// (0xFF14141C, main.dart의 scaffoldBackgroundColor와 동일)만 깔아 뒀다 —
/// 나중에 아트가 준비되면 `Scaffold.backgroundColor`를 지우고
/// `body`를 `DecorationImage`로 감싸면 된다.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  /// 게스트/구글 버튼 처리 중 잠금 — 처리 중엔 두 버튼 모두 비활성화해
  /// 연타로 로그인 요청이 중복으로 나가는 것을 막는다.
  bool _isProcessing = false;

  /// [_routeAfterAuth]가 이미 한 번 화면을 넘겼는지 — [_checkAutoLogin]
  /// (currentUser 동기 확인)과 [_onAuthStateChange](signedIn 스트림, 구독
  /// 즉시 과거 이벤트가 재생되는 ReplaySubject라 거의 동시에 도착할 수
  /// 있다)가 같은 로그인 하나를 두고 동시에 라우팅을 시도할 수 있어서,
  /// 실제로는 한 번만 [Navigator.pushReplacement]가 일어나도록 막는다.
  bool _hasRoutedAfterAuth = false;

  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    // Navigator.of(context)는 이 State가 트리에 완전히 삽입된 뒤(첫 프레임
    // 이후)에만 안전하게 쓸 수 있다 — initState 도중 곧바로 호출하면 "build
    // 중에 새 build를 요청했다"는 에러가 난다. addPostFrameCallback으로
    // 첫 프레임이 그려지자마자(사실상 지연 없이) 넘긴다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAutoLogin());

    // 구글 로그인(signInWithOAuth)은 브라우저로 나갔다가 돌아오는 비동기
    // 흐름이라 — 웹은 리다이렉트로 페이지 자체가 새로고침되고, 모바일은
    // 딥링크로 앱에 돌아온다 — "로그인 완료" 시점을 이 스트림으로 감지해야
    // 한다([SupabaseManager.signInWithGoogle] 문서 참고).
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      _onAuthStateChange,
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkAutoLogin() async {
    final User? currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      return; // 로그인 UI를 그대로 보여준다(build()가 이미 그리고 있다).
    }
    try {
      await _routeAfterAuth();
    } catch (error) {
      // 콜드 스타트 자동 로그인은 유저가 누른 버튼이 없어 에러를 보여줄
      // 곳이 마땅치 않다 — 조용히 실패하고 로그인 화면을 그대로 둔다
      // (SupabaseManager의 refresh_token_already_used 자가 치유 리스너
      // 문서 참고 — 이 실패는 보통 저장된 세션이 이미 정리된 상황이라,
      // 다시 그리면 자연스럽게 "게스트로 시작하기" 버튼을 볼 수 있다).
      debugPrint('[LoginScreen] 자동 로그인 라우팅 실패: $error');
    }
  }

  /// 구글 로그인 완료(웹 페이지 복귀/모바일 딥링크 복귀)를 이 콜백으로
  /// 감지한다 — 게스트 로그인은 [_handleGuestLogin]이 직접 결과를 기다려
  /// 처리하므로 여기서 다시 손대지 않는다(provider가 google일 때만
  /// 반응하도록 걸러서, 게스트 로그인 직후 같은 signedIn 이벤트가 와도
  /// 중복 처리되지 않는다).
  Future<void> _onAuthStateChange(AuthState state) async {
    if (!isFreshGoogleSignIn(state) || !mounted) {
      return;
    }
    final User user = state.session!.user;

    try {
      await SupabaseManager.instance.upsertGoogleProfile(user);
      if (!mounted) {
        return;
      }
      showCenterToast(context, '로그인되었습니다.');
      await _routeAfterAuth();
    } catch (error) {
      if (mounted) {
        _showDebugError('구글 로그인 후처리 오류: $error');
      }
    }
  }

  /// 디버깅 전용 — 실제 예외 메시지를 그대로 화면에 보여준다.
  /// [showCenterToast]는 이미 정해진 친절한 문구만 보여주는 용도라 "왜
  /// 실패했는지" 원인 파악에는 안 맞는다 — "버튼이 먹통"처럼 보이는 문제의
  /// 실제 원인(Supabase 대시보드 설정 미비, Android 패키지 가시성 제한 등)
  /// 을 화면에서 바로 확인할 수 있게 하기 위한 것. 나중에 정식 출시 전에는
  /// 이 기술적인 에러 문구 대신 사용자 친화적인 문구로 교체하는 걸
  /// 권장한다.
  void _showDebugError(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          duration: const Duration(seconds: 6),
          content: Text(message, style: const TextStyle(color: Colors.white)),
        ),
      );
  }

  /// 로그인(자동/게스트/구글) 성공 직후 공통으로 거치는 라우팅 — 항상
  /// [GameEntryScreen]으로 넘긴다. 닉네임이 아직 없는 신규 유저를
  /// [NicknameScreen]으로 보내는 판단은 더 이상 여기서 하지 않는다 —
  /// 프롤로그 중 N1이 이름을 묻는 장면 직후에 끼워 넣어야 하므로
  /// [GameEntryScreen]이 "프롤로그를 아직 안 봤는지"와 "닉네임이 있는지"를
  /// 함께 보고 스스로 판단한다(프롤로그를 이미 마친 구버전 계정이 닉네임만
  /// 없는 드문 경우의 안전망도 거기서 함께 처리한다). 세 로그인 경로
  /// (콜드 스타트 자동 로그인, 게스트, 구글) 모두 이 함수 하나로 수렴한다.
  Future<void> _routeAfterAuth() async {
    if (_hasRoutedAfterAuth) {
      return;
    }
    // [주의] fetchNickname은 실패해도(오프라인 등) 조용히 null을 반환하는
    // 관례라(SupabaseManager 문서 참고), 세션 자체가 그 사이에 만료되어
    // 정리됐어도(리프레시 토큰이 이미 소진된 경우 등) 이 호출만으로는
    // "그냥 오프라인"과 구분이 안 된다 — 그래서 fetchNickname 결과가 아니라
    // currentUser를 다시 확인해서, 세션이 실제로 사라졌으면 여기서
    // 라우팅을 접는다(NicknameScreen/GameEntryScreen으로 넘어가 버리면
    // 로그인 안 된 상태로 게임에 들어가는 꼴이 된다).
    final String? nickname = await SupabaseManager.instance.fetchNickname();
    // fetchNickname의 await 구간 동안 다른 경로(_checkAutoLogin ↔
    // _onAuthStateChange)가 먼저 라우팅을 끝냈을 수 있으므로 다시 확인한다.
    if (!mounted || _hasRoutedAfterAuth) {
      return;
    }
    if (Supabase.instance.client.auth.currentUser == null) {
      // 세션이 이 사이에 만료되어 정리됐다 — 로그인 화면을 그대로 유지해
      // 유저가 다시 로그인 버튼을 누를 수 있게 한다.
      return;
    }
    _hasRoutedAfterAuth = true;
    ProfileManager.instance.setNickname(nickname);
    // 광고 제거 구매 여부(profiles.is_ad_free)를 로그인 직후 서버와 맞춘다
    // — 다른 기기에서 구매했거나 재설치로 로컬 캐시가 사라진 경우를
    // 대비한다. 화면 전환을 막지 않도록 await하되, 실패해도(오프라인 등)
    // ProfileManager.loadData 내부에서 이미 로컬 캐시로 안전하게 폴백한다.
    await ProfileManager.instance.loadData();
    if (!mounted) {
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const GameEntryScreen()),
    );
  }

  Future<void> _handleGuestLogin() async {
    if (_isProcessing) {
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B26),
        title: const Text('게스트로 시작하기', style: TextStyle(color: Colors.white)),
        content: const Text(
          '게스트 계정으로 플레이할 경우, 기기 변경이나 앱 삭제 시 소중한 게임 데이터가 영구적으로 삭제될 수 있습니다. '
          '정말 게스트로 시작하시겠습니까?',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('확인', style: TextStyle(color: Color(0xFFFF6FA5))),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final bool success = await SupabaseManager.instance.signInAsGuest();
      if (!mounted) {
        return;
      }
      if (!success) {
        showCenterToast(context, '게스트 로그인에 실패했어요. 잠시 후 다시 시도해주세요.');
        return;
      }
      await _routeAfterAuth();
    } catch (error) {
      // signInAsGuest는 이제 예외를 삼키지 않고 그대로 던진다(SupabaseManager
      // 문서 참고) — 예: Supabase 대시보드에서 "Anonymous sign-ins"가 꺼져
      // 있으면 AuthApiException(anonymous_provider_disabled)가 여기로 온다.
      if (mounted) {
        _showDebugError('게스트 로그인 오류: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _handleGoogleLogin() async {
    if (_isProcessing) {
      return;
    }
    setState(() => _isProcessing = true);
    try {
      final bool launched = await SupabaseManager.instance.signInWithGoogle();
      if (!mounted) {
        return;
      }
      if (!launched) {
        showCenterToast(context, '구글 로그인을 시작하지 못했어요.');
      }
      // 완료 처리(프로필 upsert/"로그인되었습니다" 토스트/화면 전환)는
      // _onAuthStateChange가 리다이렉트 복귀 시점에 이어받는다 — 웹은 페이지
      // 자체가 새로고침될 수 있어 이 함수가 여기서 끝까지 실행되지 않을
      // 수도 있다(정상 동작).
    } catch (error) {
      // signInWithGoogle도 예외를 그대로 던진다 — 특히 Android에서
      // launchUrl이 브라우저를 못 여는 경우(AndroidManifest.xml의 <queries>
      // 누락 등) 여기로 온다.
      if (mounted) {
        _showDebugError('구글 로그인 오류: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14141C),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Cyber Breaker Idle',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 26,
                ),
              ),
              const SizedBox(height: 56),
              SizedBox(
                width: 240,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _handleGuestLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C4FCE),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF6C4FCE).withValues(alpha: 0.4),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('게스트로 시작하기', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: 240,
                child: OutlinedButton(
                  onPressed: _isProcessing ? null : _handleGoogleLogin,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white38,
                    side: const BorderSide(color: Colors.white54),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('구글 로그인', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              if (_isProcessing) ...[
                const SizedBox(height: 28),
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white54),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
