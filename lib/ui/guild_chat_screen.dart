import 'package:flutter/material.dart';

import '../managers/guild_chat_manager.dart';
import '../managers/guild_manager.dart';
import '../managers/supabase_manager.dart';
import '../models/guild_model.dart';

/// 길드 메인 화면의 "길드 채팅" 탭 — [GuildMainScreen]이 소속 길드에서만
/// 보여준다. 탭이 마운트되면 [GuildChatManager.openChat]으로 최근 내역을
/// 불러오고 Realtime 구독을 시작하고, dispose되면(=[GuildMainScreen] 자체를
/// 떠날 때) [GuildChatManager.closeChat]으로 정리한다 — `TabBarView`는 한 번
/// 만들어진 탭을 계속 살려 두므로(다른 탭으로 옮겨가도 dispose되지 않는다),
/// 채팅 탭을 보고 있지 않을 때도 구독은 계속 살아 있어 새 메시지가 조용히
/// 쌓인다.
class GuildChatTab extends StatefulWidget {
  const GuildChatTab({super.key});

  @override
  State<GuildChatTab> createState() => _GuildChatTabState();
}

class _GuildChatTabState extends State<GuildChatTab> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  /// 직전 빌드에서 그린 메시지 개수 — 이 값이 바뀔 때만(새 메시지 도착/
  /// 최초 로드) 맨 아래로 스크롤한다. 매 rebuild마다 무조건 스크롤하면,
  /// 유저가 과거 대화를 보려고 위로 스크롤해 둔 걸 계속 아래로 끌어내리게
  /// 된다.
  int _lastRenderedCount = 0;

  @override
  void initState() {
    super.initState();
    final String? guildId = GuildManager.instance.guildId;
    if (guildId != null) {
      GuildChatManager.instance.openChat(guildId);
    }
  }

  @override
  void dispose() {
    GuildChatManager.instance.closeChat();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) {
      return;
    }
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final String? guildId = GuildManager.instance.guildId;
    final String text = _controller.text;
    if (guildId == null || text.trim().isEmpty || _isSending) {
      return;
    }
    setState(() => _isSending = true);
    _controller.clear();
    await GuildChatManager.instance.sendMessage(guildId, text);
    if (mounted) {
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? guildId = GuildManager.instance.guildId;
    if (guildId == null) {
      return const Center(
        child: Text('길드에 가입되어 있지 않아요.', style: TextStyle(color: Colors.white54)),
      );
    }

    return AnimatedBuilder(
      animation: GuildChatManager.instance,
      builder: (context, _) {
        final GuildChatManager chat = GuildChatManager.instance;
        final String? myUserId = SupabaseManager.instance.currentUserId;

        if (chat.messages.length != _lastRenderedCount) {
          _lastRenderedCount = chat.messages.length;
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }

        return Padding(
          // 키보드가 올라올 때 입력창이 가려지지 않도록 시스템 인셋만큼
          // 아래 여백을 준다.
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            children: [
              Expanded(
                child: chat.isLoading && chat.messages.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(color: Color(0xFF6C4FCE)),
                      )
                    : chat.messages.isEmpty
                    ? const Center(
                        child: Text(
                          '아직 대화가 없어요. 첫 메시지를 남겨보세요!',
                          style: TextStyle(color: Colors.white38),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: chat.messages.length,
                        itemBuilder: (context, index) {
                          final GuildMessage message = chat.messages[index];
                          return _ChatBubble(
                            message: message,
                            isMe: message.userId == myUserId,
                          );
                        },
                      ),
              ),
              _ChatInputBar(controller: _controller, onSend: _send, enabled: !_isSending),
            ],
          ),
        );
      },
    );
  }
}

/// 카카오톡 스타일 말풍선 — 내 메시지([isMe])는 오른쪽/보라색, 다른
/// 사람은 왼쪽/회색이고 닉네임을 말풍선 위에 함께 표시한다.
class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, required this.isMe});

  final GuildMessage message;
  final bool isMe;

  String get _time {
    final String hour = message.createdAt.hour.toString().padLeft(2, '0');
    final String minute = message.createdAt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final Widget bubble = Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFF6C4FCE) : const Color(0xFF20202C),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: Radius.circular(isMe ? 14 : 2),
          bottomRight: Radius.circular(isMe ? 2 : 14),
        ),
        border: isMe ? null : Border.all(color: const Color(0xFF3A3A4A)),
      ),
      child: Text(
        message.message,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );

    final Text timeLabel = Text(
      _time,
      style: const TextStyle(color: Colors.white38, fontSize: 10),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 2),
              child: Text(
                message.nickname,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: isMe
                ? [timeLabel, const SizedBox(width: 6), Flexible(child: bubble)]
                : [Flexible(child: bubble), const SizedBox(width: 6), timeLabel],
          ),
        ],
      ),
    );
  }
}

class _ChatInputBar extends StatelessWidget {
  const _ChatInputBar({required this.controller, required this.onSend, required this.enabled});

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1B1B26),
        border: Border(top: BorderSide(color: Color(0xFF3A3A4A))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              maxLength: 200,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                counterText: '',
                hintText: '메시지를 입력하세요',
                hintStyle: TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Color(0xFF20202C),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: (_) {
                if (enabled) {
                  onSend();
                }
              },
            ),
          ),
          IconButton(
            onPressed: enabled ? onSend : null,
            icon: const Icon(Icons.send),
            color: const Color(0xFF6C4FCE),
          ),
        ],
      ),
    );
  }
}
