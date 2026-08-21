import 'package:flutter/foundation.dart';

import '../models/friend_model.dart';
import 'supabase_manager.dart';

/// 친구 목록/친구 요청/유저 검색을 관장하는 싱글턴 — 다른 매니저들과
/// 달리 로컬(SharedPreferences) 캐시를 두지 않는다: 친구 관계는 다른
/// 유저와 함께 바뀌는 서버 전용 상태라 로컬에 남겨 봐야 stale해지기만
/// 하고, 화면을 열 때마다 [loadAll]로 다시 불러오는 비용도 크지 않다
/// ([RankingManager]와 같은 "항상 서버가 최신 소스" 판단).
class FriendManager extends ChangeNotifier {
  FriendManager._internal();

  static final FriendManager instance = FriendManager._internal();

  List<FriendEntry> friends = const [];
  List<FriendRequestEntry> incomingRequests = const [];
  bool isLoading = false;

  /// [_MainNavigationScreenState]의 앱바 친구 버튼이 배지(받은 요청 수)를
  /// 그리려면 화면을 열기 전에도 이 값이 채워져 있어야 하므로, main()이
  /// 부팅 시 한 번 호출해 둔다.
  Future<void> loadAll() async {
    isLoading = true;
    notifyListeners();

    // [보안 감사 2026-08-21] 이 메서드는 main() 부팅 시/friend_screen에서
    // 전부 `unawaited(...)`로 fire-and-forget 호출된다 — 중간에 뭔가
    // 하나라도 throw하면(예상 밖 프로필 shape 등) 예외가 그냥 버려지고
    // [isLoading]이 true로 영원히 멈춰, 친구 화면이 로딩 스피너에서
    // 다시는 빠져나오지 못했다. try/finally로 감싸서 성공하든 실패하든
    // 반드시 [isLoading]이 풀리게 한다(이 프로젝트의 다른 매니저들이
    // 이미 따르는 관례).
    try {
      final List<Map<String, dynamic>> rows =
          await SupabaseManager.instance.fetchMyFriendshipRows();
      final String? myId = SupabaseManager.instance.currentUserId;

      final List<String> acceptedOtherIds = [];
      final List<String> pendingRequesterIds = [];
      for (final Map<String, dynamic> row in rows) {
        final String requesterId = row['user_id'] as String;
        final String targetId = row['friend_id'] as String;
        final String status = row['status'] as String? ?? '';
        if (status == FriendshipStatus.accepted) {
          acceptedOtherIds.add(requesterId == myId ? targetId : requesterId);
        } else if (status == FriendshipStatus.pending && targetId == myId) {
          pendingRequesterIds.add(requesterId);
        }
      }

      final List<Map<String, dynamic>> profiles = await SupabaseManager.instance
          .fetchProfilesByIds([...acceptedOtherIds, ...pendingRequesterIds]);
      final Map<String, Map<String, dynamic>> profileById = {
        for (final Map<String, dynamic> profile in profiles) profile['id'] as String: profile,
      };

      friends =
          [
            for (final String id in acceptedOtherIds)
              if (profileById[id] case final Map<String, dynamic> profile)
                FriendEntry.fromProfileJson(profile),
          ]
          // 온라인인 친구를 위로, 그 안에서는 닉네임 순으로 — 접속 기록이
          // 없는 친구(lastSeen null)는 항상 맨 아래로 밀린다.
          ..sort((a, b) {
            if (a.isOnline != b.isOnline) {
              return a.isOnline ? -1 : 1;
            }
            return a.nickname.compareTo(b.nickname);
          });

      incomingRequests = [
        for (final String id in pendingRequesterIds)
          if (profileById[id] case final Map<String, dynamic> profile)
            FriendRequestEntry.fromProfileJson(profile),
      ];
    } catch (error) {
      debugPrint('[FriendManager] loadAll 실패: $error');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// 닉네임/유저 id로 검색하고, 검색 결과 각각에 이미 친구거나 요청을
  /// 보낸 사이인지([UserSearchResult.relationStatus])를 표시한다.
  Future<List<UserSearchResult>> search(String query) async {
    final List<Map<String, dynamic>> profiles =
        await SupabaseManager.instance.searchProfilesForFriend(query);
    if (profiles.isEmpty) {
      return const [];
    }

    final List<Map<String, dynamic>> relationRows =
        await SupabaseManager.instance.fetchMyFriendshipRows();
    final String? myId = SupabaseManager.instance.currentUserId;
    final Map<String, String> relationByOtherId = {};
    for (final Map<String, dynamic> row in relationRows) {
      final String requesterId = row['user_id'] as String;
      final String targetId = row['friend_id'] as String;
      final String status = row['status'] as String? ?? '';
      final String otherId = requesterId == myId ? targetId : requesterId;
      relationByOtherId[otherId] = status;
    }

    return [
      for (final Map<String, dynamic> profile in profiles)
        UserSearchResult.fromProfileJson(
          profile,
          relationStatus: relationByOtherId[profile['id'] as String],
        ),
    ];
  }

  /// [targetUserId]에게 친구 요청을 보낸다 — 이미 친구거나 이미 보낸/받은
  /// 요청이 있으면(양방향 모두 확인) 서버에 새로 쓰지 않고 그대로 false.
  Future<bool> sendFriendRequest(String targetUserId) async {
    final List<Map<String, dynamic>> rows =
        await SupabaseManager.instance.fetchMyFriendshipRows();
    final String? myId = SupabaseManager.instance.currentUserId;
    final bool alreadyRelated = rows.any((row) {
      final String requesterId = row['user_id'] as String;
      final String targetId = row['friend_id'] as String;
      final String otherId = requesterId == myId ? targetId : requesterId;
      return otherId == targetUserId;
    });
    if (alreadyRelated) {
      return false;
    }
    return SupabaseManager.instance.sendFriendRequest(targetUserId);
  }

  /// [requesterId]의 요청을 수락한다 — 성공하면 [loadAll]로 목록을 즉시
  /// 갱신해 "받은 요청" 탭에서 사라지고 "내 친구" 탭에 나타나게 한다.
  Future<bool> acceptRequest(String requesterId) async {
    final bool success = await SupabaseManager.instance.acceptFriendRequest(requesterId);
    if (success) {
      await loadAll();
    }
    return success;
  }

  /// [requesterId]의 요청을 거절한다 — 성공하면 [loadAll]로 "받은 요청"
  /// 탭에서 즉시 사라지게 한다.
  Future<bool> declineRequest(String requesterId) async {
    final bool success = await SupabaseManager.instance.declineFriendRequest(requesterId);
    if (success) {
      await loadAll();
    }
    return success;
  }
}
