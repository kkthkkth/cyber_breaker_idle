import 'package:flutter/material.dart';

import '../managers/profile_manager.dart';
import '../managers/supabase_manager.dart';

/// 아직 `profiles.nickname`이 없는 유저에게 닉네임을 받는 화면.
///
/// 신규 유저는 프롤로그 중 N1이 이름을 묻는 장면([prologueBeforeName]의
/// 마지막 대사) 직후 [GameEntryScreen]이 이 화면을 끼워 넣어 보여준다 —
/// 그래서 이 화면 자체는 독립된 안내 문구 대신 "방금 그 질문에 답한다"는
/// 톤을 유지한다. 이미 프롤로그를 마쳤지만 어떤 이유로든 닉네임이 없는
/// 드문 경우(구버전 계정 등)에는 같은 화면을 안전망으로 재사용한다.
///
/// 닉네임 설정에 성공하면 화면이 스스로 네비게이션하지 않고 [onComplete]를
/// 호출한다 — 호출부([GameEntryScreen], 프롤로그 흐름 안에서 쓰일 수도
/// 있고 안전망으로 단독으로 쓰일 수도 있음)가 다음 화면을 결정한다. 뒤로
/// 가기로 건너뛸 수 없게(닉네임 없이 게임에 들어가면 [StoryDialogWidget]의
/// "지휘관" 치환이 전부 깨진다) `PopScope`로 뒤로 가기를 막는다.
class NicknameScreen extends StatefulWidget {
  const NicknameScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen> {
  final TextEditingController _controller = TextEditingController();

  bool _isProcessing = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (_isProcessing) {
      return;
    }
    final String nickname = _controller.text.trim();
    if (nickname.isEmpty) {
      setState(() => _errorText = '닉네임을 입력해주세요.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorText = null;
    });
    try {
      final NicknameUpdateResult result = await SupabaseManager.instance.setNickname(nickname);
      if (!mounted) {
        return;
      }
      switch (result) {
        case NicknameUpdateResult.success:
          ProfileManager.instance.setNickname(nickname);
          widget.onComplete();
        case NicknameUpdateResult.duplicate:
          setState(() => _errorText = '이미 사용 중인 닉네임입니다.');
        case NicknameUpdateResult.error:
          setState(() => _errorText = '닉네임 설정에 실패했어요. 잠시 후 다시 시도해주세요.');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF14141C),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '부디, 당신의 존함을...',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'N1이 당신의 이름을 기다리고 있어요. 앞으로 동료들도 이 이름으로 당신을 부를 거예요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _controller,
                    maxLength: 12,
                    enabled: !_isProcessing,
                    style: const TextStyle(color: Colors.white),
                    onSubmitted: (_) => _handleSubmit(),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF1B1B26),
                      hintText: '닉네임 입력',
                      hintStyle: const TextStyle(color: Colors.white38),
                      errorText: _errorText,
                      counterStyle: const TextStyle(color: Colors.white38),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF3A3A4A)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF6C4FCE)),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isProcessing ? null : _handleSubmit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C4FCE),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF6C4FCE).withValues(alpha: 0.4),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                            )
                          : const Text('결정', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
