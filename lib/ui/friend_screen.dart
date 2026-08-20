import 'package:flutter/material.dart';

import '../managers/friend_manager.dart';
import '../models/friend_model.dart';
import '../widgets/center_toast.dart';
import '../widgets/user_avatar.dart';
import 'trade_screen.dart';

/// 메인 화면 앱바 우측의 친구 진입 버튼 — 받은 요청이 하나라도 있으면
/// [_DailyQuestHudButton]과 같은 빨간 점 배지를 띄운다. main()이 부팅 시
/// [FriendManager.loadAll]을 한 번 불러 두므로, 이 화면을 열기 전에도
/// 배지가 정확하다.
class FriendHudButton extends StatelessWidget {
  const FriendHudButton({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: FriendManager.instance,
      builder: (context, _) {
        final bool hasIncoming = FriendManager.instance.incomingRequests.isNotEmpty;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const CircleAvatar(
                backgroundColor: Color(0xFF2C2C3A),
                child: Icon(Icons.people, color: Colors.white70),
              ),
              tooltip: '친구',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const FriendScreen()),
              ),
            ),
            if (hasIncoming)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF1B1B26), width: 1.5),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 친구 화면 — [내 친구]/[받은 요청]/[친구 검색] 3탭. 열릴 때마다
/// [FriendManager.loadAll]로 최신 목록을 다시 불러온다.
class FriendScreen extends StatefulWidget {
  const FriendScreen({super.key});

  @override
  State<FriendScreen> createState() => _FriendScreenState();
}

class _FriendScreenState extends State<FriendScreen> {
  @override
  void initState() {
    super.initState();
    FriendManager.instance.loadAll();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFF14141C),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1B1B26),
          elevation: 0,
          foregroundColor: Colors.white,
          title: const Text('친구', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          centerTitle: true,
          bottom: TabBar(
            indicatorColor: const Color(0xFF6C4FCE),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: [
              const Tab(text: '내 친구'),
              Tab(
                child: AnimatedBuilder(
                  animation: FriendManager.instance,
                  builder: (context, _) {
                    final int count = FriendManager.instance.incomingRequests.length;
                    return Text(count > 0 ? '받은 요청 ($count)' : '받은 요청');
                  },
                ),
              ),
              const Tab(text: '친구 검색'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_FriendListTab(), _RequestsTab(), _SearchTab()],
        ),
      ),
    );
  }
}


class _CombatPowerChip extends StatelessWidget {
  const _CombatPowerChip({required this.combatPower});

  final int combatPower;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF20202C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF3A3A4A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bolt, color: Color(0xFFFFD700), size: 14),
          const SizedBox(width: 3),
          Text(
            '$combatPower',
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _FriendListTab extends StatelessWidget {
  const _FriendListTab();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: FriendManager.instance,
      builder: (context, _) {
        final FriendManager manager = FriendManager.instance;
        if (manager.isLoading && manager.friends.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF6C4FCE)));
        }
        if (manager.friends.isEmpty) {
          return const Center(
            child: Text('아직 친구가 없어요.\n[친구 검색] 탭에서 친구를 추가해 보세요.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
          );
        }
        return RefreshIndicator(
          onRefresh: manager.loadAll,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: manager.friends.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final FriendEntry friend = manager.friends[index];
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => requestTradeWith(context, userId: friend.userId, nickname: friend.nickname),
                child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF20202C),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF3A3A4A)),
                ),
                child: Row(
                  children: [
                    UserAvatar(onlineDot: friend.isOnline, characterId: friend.equippedCharacter),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            friend.nickname,
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                friend.isOnline ? '🟢' : '⚪',
                                style: const TextStyle(fontSize: 10),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                friend.presenceLabel,
                                style: TextStyle(
                                  color: friend.isOnline ? Colors.greenAccent : Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _CombatPowerChip(combatPower: friend.combatPower),
                  ],
                ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _RequestsTab extends StatelessWidget {
  const _RequestsTab();

  Future<void> _accept(BuildContext context, FriendRequestEntry request) async {
    final bool success = await FriendManager.instance.acceptRequest(request.userId);
    if (context.mounted && success) {
      showCenterToast(context, '${request.nickname}님과 친구가 되었습니다!');
    }
  }

  Future<void> _decline(BuildContext context, FriendRequestEntry request) async {
    await FriendManager.instance.declineRequest(request.userId);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: FriendManager.instance,
      builder: (context, _) {
        final FriendManager manager = FriendManager.instance;
        if (manager.incomingRequests.isEmpty) {
          return const Center(
            child: Text('받은 친구 요청이 없어요.', style: TextStyle(color: Colors.white54)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: manager.incomingRequests.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final FriendRequestEntry request = manager.incomingRequests[index];
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF20202C),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF6C4FCE)),
              ),
              child: Row(
                children: [
                  UserAvatar(characterId: request.equippedCharacter),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.nickname,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        _CombatPowerChip(combatPower: request.combatPower),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.check_circle, color: Colors.greenAccent),
                    tooltip: '수락',
                    onPressed: () => _accept(context, request),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.white38),
                    tooltip: '거절',
                    onPressed: () => _decline(context, request),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SearchTab extends StatefulWidget {
  const _SearchTab();

  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab> {
  final TextEditingController _controller = TextEditingController();
  List<UserSearchResult> _results = const [];
  bool _isSearching = false;
  bool _hasSearched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final String query = _controller.text.trim();
    if (query.isEmpty) {
      return;
    }
    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });
    final List<UserSearchResult> results = await FriendManager.instance.search(query);
    if (!mounted) {
      return;
    }
    setState(() {
      _results = results;
      _isSearching = false;
    });
  }

  Future<void> _sendRequest(UserSearchResult result) async {
    final bool success = await FriendManager.instance.sendFriendRequest(result.userId);
    if (!mounted) {
      return;
    }
    if (success) {
      showCenterToast(context, '${result.nickname}님에게 친구 요청을 보냈습니다.');
      await _search();
    } else {
      showCenterToast(context, '이미 친구이거나 요청을 보낸 상대예요.');
    }
  }

  String _actionLabel(String? relationStatus) => switch (relationStatus) {
    FriendshipStatus.accepted => '이미 친구',
    FriendshipStatus.pending => '요청됨',
    _ => '친구 요청',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: '닉네임 또는 유저 ID로 검색',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF20202C),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isSearching ? null : _search,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C4FCE),
                  foregroundColor: Colors.white,
                ),
                child: const Text('검색'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C4FCE)))
                : (!_hasSearched
                      ? const Center(
                          child: Text('닉네임이나 유저 ID를 검색해 친구를 추가해 보세요.',
                              style: TextStyle(color: Colors.white54)),
                        )
                      : (_results.isEmpty
                            ? const Center(
                                child:
                                    Text('검색 결과가 없어요.', style: TextStyle(color: Colors.white54)),
                              )
                            : ListView.separated(
                                itemCount: _results.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final UserSearchResult result = _results[index];
                                  final bool canRequest = result.relationStatus == null;
                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF20202C),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: const Color(0xFF3A3A4A)),
                                    ),
                                    child: Row(
                                      children: [
                                        UserAvatar(characterId: result.equippedCharacter),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                result.nickname,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14),
                                              ),
                                              const SizedBox(height: 2),
                                              _CombatPowerChip(combatPower: result.combatPower),
                                            ],
                                          ),
                                        ),
                                        ElevatedButton(
                                          onPressed:
                                              canRequest ? () => _sendRequest(result) : null,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF6C4FCE),
                                            foregroundColor: Colors.white,
                                            disabledBackgroundColor: const Color(0xFF3A3A4A),
                                            disabledForegroundColor: Colors.white38,
                                          ),
                                          child: Text(_actionLabel(result.relationStatus)),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ))),
          ),
        ],
      ),
    );
  }
}
