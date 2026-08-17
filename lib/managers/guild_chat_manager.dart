import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/guild_model.dart';
import 'guild_manager.dart';
import 'supabase_manager.dart';

/// 길드 채팅 탭([GuildChatTab])이 쓰는 싱글턴 — 다른 매니저들과 달리
/// SharedPreferences에 저장하지 않는다(채팅 내역은 서버가 유일한 신뢰
/// 소스이고, 로컬 캐시가 필요할 만큼 오프라인 접근성이 중요한 데이터가
/// 아니다). 탭에 들어올 때 [openChat]으로 최근 내역을 불러오고 Realtime
/// 구독을 시작하며, 탭(=[GuildMainScreen])을 떠날 때 [closeChat]으로
/// 구독을 정리한다.
class GuildChatManager extends ChangeNotifier {
  GuildChatManager._internal();

  static final GuildChatManager instance = GuildChatManager._internal();

  List<GuildMessage> messages = const [];
  bool isLoading = false;

  String? _subscribedGuildId;
  RealtimeChannel? _channel;

  /// Realtime INSERT 페이로드에는 발신자 닉네임이 없으므로(임베드 미지원),
  /// 이미 로드돼 있는 [GuildManager.members] 로스터에서 찾는다 — 채팅
  /// 탭은 항상 같은 길드의 "길드원 목록" 탭과 함께 쓰이므로 대부분의 경우
  /// 곧바로 찾아진다. 못 찾으면(방금 가입해 로스터가 아직 안 갱신된 경우
  /// 등) [GuildMember]의 기본 placeholder와 같은 문구로 대체한다.
  String _resolveNickname(String userId) {
    for (final GuildMember member in GuildManager.instance.members) {
      if (member.userId == userId) {
        return member.nickname;
      }
    }
    return '익명의 모험가';
  }

  /// [guildId] 채팅방을 연다 — 최근 내역을 불러오고 실시간 구독을
  /// 시작한다. 이미 같은 길드를 구독 중이면 아무것도 하지 않는다(탭을
  /// 벗어났다 다시 들어와도 중복 구독/재조회하지 않도록).
  Future<void> openChat(String guildId) async {
    if (_subscribedGuildId == guildId && _channel != null) {
      return;
    }
    await closeChat();

    isLoading = true;
    notifyListeners();

    final List<Map<String, dynamic>> rows = await SupabaseManager.instance.fetchGuildMessages(guildId);
    messages = rows
        .map((row) => GuildMessage.fromJson(row, resolveNickname: _resolveNickname))
        .toList();
    isLoading = false;
    notifyListeners();

    _subscribedGuildId = guildId;
    _channel = SupabaseManager.instance.subscribeToGuildMessages(guildId, (row) {
      final GuildMessage incoming = GuildMessage.fromJson(row, resolveNickname: _resolveNickname);
      // 내가 방금 보낸 메시지도 이 콜백으로 되돌아온다(Realtime은 누가
      // 바꿨는지와 무관하게 그 행을 볼 수 있는 모든 구독자에게 브로드캐스트
      // 한다) — id가 이미 있으면 중복 추가하지 않는다.
      if (messages.any((existing) => existing.id == incoming.id)) {
        return;
      }
      messages = [...messages, incoming];
      notifyListeners();
    });
  }

  /// 채팅방 구독을 정리한다 — [GuildMainScreen]이 dispose될 때 호출한다.
  Future<void> closeChat() async {
    final RealtimeChannel? channel = _channel;
    if (channel != null) {
      await SupabaseManager.instance.unsubscribeChannel(channel);
    }
    _channel = null;
    _subscribedGuildId = null;
    messages = const [];
  }

  /// [guildId]에 [text]를 보낸다 — 빈 문자열/공백만 있으면 서버 호출 없이
  /// false. 성공하면 [subscribeToGuildMessages]의 Realtime 에코가 곧
  /// [messages]에 추가하므로, 여기서 직접 리스트에 넣지 않는다.
  Future<bool> sendMessage(String guildId, String text) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    return SupabaseManager.instance.sendGuildMessage(guildId: guildId, message: trimmed);
  }
}
