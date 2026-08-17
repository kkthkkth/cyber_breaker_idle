import 'dart:async';

import 'package:flutter/material.dart';

import '../game/idle_game.dart';
import '../managers/profile_manager.dart';
import '../models/story_model.dart';
import 'character_face_portrait.dart';
import 'safe_image.dart';

/// story_data.dart의 `_commanderLine`이 지휘관(플레이어) 대사의 화자로 항상
/// 고정으로 넘기는 이름 — 실제로 화면에 그릴 때는(아래 [_resolveSpeakerName])
/// 이 값 대신 유저가 설정한 [ProfileManager.nickname]으로 치환한다.
const String _commanderSpeakerPlaceholder = '지휘관';

/// story_data.dart의 NPC 대사 본문 안에서 플레이어를 가리킬 때 쓰는
/// 플레이스홀더(예: `'{nickname}님, 놈이...'`) — [_resolveDialogueText]가
/// 렌더링 직전에 실제 닉네임으로 치환한다. 화자 이름([_commanderSpeakerPlaceholder])
/// 과는 별개의 자리인데, 화자는 "지휘관"이라는 고유한 문자열 전체가
/// 하나의 이름이지만, 본문은 문장 중간 어디에든 여러 번 끼어들 수 있어서
/// (예: "님", "의" 같은 조사가 바로 뒤에 붙는다) 명시적인 토큰이 필요하다.
const String _nicknamePlaceholder = '{nickname}';

/// 두 치환([_resolveSpeakerName]/[_resolveDialogueText])이 공유하는 실제
/// 닉네임 조회 — 아직 로그인 전이거나 닉네임을 설정하지 않았거나(null),
/// 어떤 이유로든 빈 문자열이면 항상 기본값 [_commanderSpeakerPlaceholder]
/// ("지휘관")로 안전하게 대체한다.
String _resolvedNickname() {
  final String? nickname = ProfileManager.instance.nickname;
  if (nickname == null || nickname.trim().isEmpty) {
    return _commanderSpeakerPlaceholder;
  }
  return nickname;
}

String _resolveSpeakerName(String speaker) {
  if (speaker != _commanderSpeakerPlaceholder) {
    return speaker;
  }
  return _resolvedNickname();
}

/// 원본 [StoryLine.text]는 그대로 두고 렌더링 시점에만 [_nicknamePlaceholder]
/// 를 실제 닉네임으로 바꾼다 — 닉네임이 나중에 바뀌어도(재로그인 등)
/// 스토리 데이터를 다시 만들 필요가 없다.
String _resolveDialogueText(String text) => text.replaceAll(_nicknamePlaceholder, _resolvedNickname());

/// 비주얼 노벨 스타일 대화창 — [story]의 대사를 한 줄씩 타자기 효과로
/// 보여주다가, 마지막 대사까지 넘기거나 스킵 버튼을 누르면 [onComplete]를
/// 호출한다. 어느 쪽으로 끝나든(완주/스킵) 결과는 동일하게 취급되므로
/// 호출부에서 따로 분기할 필요가 없다.
///
/// 화면 탭 동작:
///   - 타이핑 중이면 즉시 현재 줄 전체를 표시.
///   - 이미 전체가 표시된 상태면 다음 줄로(마지막 줄이면 [onComplete]).
class StoryDialogWidget extends StatefulWidget {
  const StoryDialogWidget({
    super.key,
    required this.story,
    required this.onComplete,
  });

  final StoryModel story;
  final VoidCallback onComplete;

  @override
  State<StoryDialogWidget> createState() => _StoryDialogWidgetState();
}

class _StoryDialogWidgetState extends State<StoryDialogWidget> {
  static const Duration _charInterval = Duration(milliseconds: 35);

  int _lineIndex = 0;
  int _visibleCharCount = 0;
  Timer? _typingTimer;

  StoryLine get _currentLine => widget.story.lines[_lineIndex];

  /// [_currentLine.text]의 `{nickname}` 플레이스홀더까지 실제 닉네임으로
  /// 치환된 최종 문자열 — 타자기 효과([_visibleCharCount])가 반드시 이
  /// "치환된 뒤" 길이를 기준으로 동작해야 한다. 원본(플레이스홀더 그대로인)
  /// 길이를 기준으로 삼으면, 닉네임 길이가 `{nickname}`(10자)과 다를 때
  /// 마지막 몇 글자가 잘리거나 남거나, 심할 땐 타이핑 도중 화면에 치환 전
  /// "{nickname}" 원문이 그대로 잠깐 보이는 문제가 생긴다.
  String get _resolvedLineText => _resolveDialogueText(_currentLine.text);

  bool get _isLastLine => _lineIndex == widget.story.lines.length - 1;
  bool get _isTyping => _visibleCharCount < _resolvedLineText.length;

  /// 같은 캐릭터는 씬 내내 같은 쪽에 서 있도록(대사가 바뀔 때마다 좌우가
  /// 뒤바뀌면 산만하다) [StoryLine.characterId]의 해시값으로 좌/우를
  /// 결정적으로 고정한다 — 별도의 "이 캐릭터는 왼쪽" 배치표를 관리할
  /// 필요 없이, 캐릭터가 늘어나도 자동으로 좌우에 고르게 흩어진다.
  bool _isRightSide(String characterId) => characterId.hashCode.isEven;

  @override
  void initState() {
    super.initState();
    _startTyping();
    // 인게임 전투 화면(IdleGame)이 이 대화창 뒤(다른 위젯 트리, 풀스크린
    // 라우트)에서 계속 돌아가고 있을 수 있으므로, 열려 있는 동안은 캐릭터
    // 모션을 대기(idle)로 바꿔둔다. 대화창이 프롤로그처럼 IdleGame이 아직
    // 만들어지기 전에 뜨는 경우도 있어 null 안전하게 접근한다.
    IdleGame.mainInstance?.setDialogActive(true);
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    IdleGame.mainInstance?.setDialogActive(false);
    super.dispose();
  }

  void _startTyping() {
    _typingTimer?.cancel();
    _visibleCharCount = 0;
    _typingTimer = Timer.periodic(_charInterval, (timer) {
      if (_visibleCharCount >= _resolvedLineText.length) {
        timer.cancel();
        return;
      }
      setState(() => _visibleCharCount++);
    });
  }

  void _onTapScreen() {
    if (_isTyping) {
      _typingTimer?.cancel();
      setState(() => _visibleCharCount = _resolvedLineText.length);
      return;
    }

    if (_isLastLine) {
      widget.onComplete();
      return;
    }

    setState(() => _lineIndex++);
    _startTyping();
  }

  void _skip() {
    _typingTimer?.cancel();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final StoryLine line = _currentLine;
    final String visibleText = _resolvedLineText.substring(0, _visibleCharCount);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B12),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTapScreen,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomSafeImage(
                  path: widget.story.backgroundUrl,
                  fit: BoxFit.cover,
                ),
              ),
              // 배경 위에 대화창 텍스트가 항상 잘 읽히도록 은은한 어두운
              // 스크림을 한 겹 깐다 — 배경 아트가 아직 없어 placeholder만
              // 보이는 챕터에서도 자연스럽다.
              const Positioned.fill(
                child: DecoratedBox(decoration: BoxDecoration(color: Color(0x66000000))),
              ),
              if (line.characterId != null)
                Positioned(
                  bottom: 150,
                  left: _isRightSide(line.characterId!) ? null : -16,
                  right: _isRightSide(line.characterId!) ? -16 : null,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: SizedBox(
                      key: ValueKey<String>(line.characterId!),
                      width: MediaQuery.of(context).size.width * 0.5,
                      height: MediaQuery.of(context).size.height * 0.55,
                      child: CharacterFacePortrait(
                        characterId: line.characterId!,
                        isFullBody: true,
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 12,
                right: 12,
                child: TextButton.icon(
                  onPressed: _skip,
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  icon: const Icon(Icons.fast_forward, size: 16),
                  label: const Text('SKIP'),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: _DialogueBox(
                  speaker: _resolveSpeakerName(line.speaker),
                  text: visibleText,
                  thumbnailUrl: line.thumbnailUrl,
                  showNextHint: !_isTyping,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 화면 하단의 이름/썸네일/대사 패널. 텍스트 길이가 매번 달라져도 탭 영역이
/// 들쭉날쭉하지 않도록 [minHeight]로 최소 높이를 고정한다.
class _DialogueBox extends StatelessWidget {
  const _DialogueBox({
    required this.speaker,
    required this.text,
    required this.thumbnailUrl,
    required this.showNextHint,
  });

  final String speaker;
  final String text;
  final String? thumbnailUrl;
  final bool showNextHint;

  @override
  Widget build(BuildContext context) {
    final String? url = thumbnailUrl;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      constraints: const BoxConstraints(minHeight: 130),
      decoration: BoxDecoration(
        color: const Color(0xE61B1B26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A4A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (url == null || url.isEmpty)
            const _CommanderEmblem()
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomSafeImage(
                path: url,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.none,
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  speaker,
                  style: const TextStyle(
                    color: Colors.amberAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  text,
                  style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                ),
                if (showNextHint)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Icon(Icons.expand_more, color: Colors.white54, size: 18),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 특정 캐릭터 초상화가 없는 화자("지휘관"=플레이어 자신, "모든 동료들"
/// 같은 그룹 대사)를 위한 기사단 공통 엠블럼 — 실제 캐릭터 아트가 아니라
/// 로컬 아이콘 조합이라 존재하지 않는 이미지를 참조할 위험이 없다.
class _CommanderEmblem extends StatelessWidget {
  const _CommanderEmblem();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A3A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC9A24B), width: 1.5),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.shield_moon, color: Color(0xFFC9A24B), size: 28),
    );
  }
}
