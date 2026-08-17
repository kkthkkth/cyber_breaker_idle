import 'package:flutter/material.dart';

import '../constants/guild_emblems.dart';
import '../managers/guild_manager.dart';
import '../managers/supabase_manager.dart';
import '../models/guild_model.dart';
import '../utils/number_formatter.dart';
import '../widgets/center_toast.dart';
import 'guild_chat_screen.dart';
import 'guild_dungeon_screen.dart';
import 'guild_raid_screen.dart';
import 'guild_shop_screen.dart';
import 'guild_treasury_screen.dart';
import 'guild_war_screen.dart';

/// 가입 상태 전용 — 상단 헤더(엠블럼/이름/레벨/exp바/공지) + 출석체크
/// 버튼 + 하단 4개 탭(길드원 목록/길드 버프/길드 상점/길드 던전)으로
/// 구성된다. [GuildScreen]의 IndexedStack 특성상 이 화면은 가입하는 순간
/// 한 번만 새로 만들어지고 그 뒤로는 계속 같은 인스턴스가 유지되므로,
/// 다른 멤버의 활동으로 바뀐 값을 다시 보고 싶으면 AppBar의 새로고침
/// 버튼으로 수동 갱신한다.
class GuildMainScreen extends StatefulWidget {
  const GuildMainScreen({super.key});

  @override
  State<GuildMainScreen> createState() => _GuildMainScreenState();
}

class _GuildMainScreenState extends State<GuildMainScreen> {
  bool _isRefreshing = false;
  bool _isCheckingIn = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    await Future.wait([
      GuildManager.instance.refreshGuild(),
      GuildManager.instance.refreshMembers(),
      // 앱이 백그라운드로 밀려나 있는 동안 자정을 넘겼다면(모바일 OS가
      // 백그라운드 Timer를 지연/중단시킬 수 있어 MidnightResetManager의
      // 자정 타이머만으로는 못 잡을 수 있다) 이 화면에 들어올 때도 한 번
      // 더 확인해 출석체크 버튼이 계속 "완료"에 묶여있지 않게 한다.
      GuildManager.instance.checkAndResetCheckInStatus(),
    ]);
    if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  Future<void> _checkIn() async {
    if (_isCheckingIn) {
      return;
    }
    setState(() => _isCheckingIn = true);
    try {
      final bool success = await GuildManager.instance.checkIn();
      if (!mounted) {
        return;
      }
      showCenterToast(
        context,
        success
            ? '출석 완료! 길드 주화 ${GuildManager.instance.guildAttendanceCoinReward}개를 획득했습니다.'
            : '오늘은 이미 출석체크를 했어요.',
      );
    } finally {
      if (mounted) {
        setState(() => _isCheckingIn = false);
      }
    }
  }

  /// 탈퇴 확인 팝업을 띄우고, 확인을 누르면 [GuildManager.leaveGuild]를
  /// 실행한다 — 성공하면 [GuildManager.isInGuild]가 false가 되어
  /// [GuildScreen]이 자동으로 가입 화면으로 되돌린다(이 화면이 직접
  /// Navigator로 이동시키지 않아도 된다).
  Future<void> _confirmLeaveGuild() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '길드 탈퇴',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          '탈퇴하면 모든 기여도와 길드주화가 사라집니다. 탈퇴하시겠습니까?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('탈퇴', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final bool success = await GuildManager.instance.leaveGuild();
    if (!mounted) {
      return;
    }
    showCenterToast(context, success ? '길드를 탈퇴했습니다.' : '길드 탈퇴에 실패했어요.');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: GuildManager.instance,
      builder: (context, _) {
        final GuildManager manager = GuildManager.instance;

        return DefaultTabController(
          length: 7,
          child: Scaffold(
            backgroundColor: const Color(0xFF14141C),
            appBar: AppBar(
              backgroundColor: const Color(0xFF1B1B26),
              elevation: 0,
              // 뒤로 가기 버튼처럼 별도 색을 안 준 아이콘이 어두운 배경에
              // 묻히지 않도록 명시한다.
              foregroundColor: Colors.white,
              title: Text(
                manager.guildName,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              centerTitle: true,
              actions: [
                // Flexible로 감싸는 이유: 길드 주화가 커지면(수천~수만 이상)
                // 이 배지가 늘어나면서 오른쪽의 새로고침/탈퇴 아이콘을
                // 밀어낼 수 있었다 — main.dart/top_bar.dart의 통화 표시와
                // 같은 문제, 같은 해법이다.
                Flexible(
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF20202C),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF3A3A4A)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.savings, color: Colors.amberAccent, size: 16),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            NumberFormatter.format(manager.guildCoins.toDouble()),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 길드장에게만 보이는 전리품 분배 진입점 — 요구사항: "길드장만
                // 볼 수 있는 [전리품 분배] 메뉴".
                if (manager.isMaster)
                  IconButton(
                    icon: const Icon(Icons.card_giftcard, color: Color(0xFFFFD54F)),
                    tooltip: '전리품 분배',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const GuildTreasuryScreen()),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white70),
                  onPressed: _isRefreshing ? null : _refresh,
                ),
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.redAccent),
                  tooltip: '길드 탈퇴',
                  onPressed: _confirmLeaveGuild,
                ),
              ],
            ),
            body: Column(
              children: [
                _GuildHeader(
                  onEditNotice: () => showDialog<void>(
                    context: context,
                    builder: (context) => const _EditNoticeDialog(),
                  ),
                  onEditEmblem: () => showDialog<void>(
                    context: context,
                    builder: (context) => const _EditEmblemDialog(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (manager.hasCheckedInToday || _isCheckingIn) ? null : _checkIn,
                      icon: const Icon(Icons.event_available),
                      label: Text(manager.hasCheckedInToday ? '오늘 출석체크 완료' : '길드 출석체크'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C4FCE),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF3A3A4A),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
                const TabBar(
                  isScrollable: true,
                  indicatorColor: Color(0xFF6C4FCE),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  tabs: [
                    Tab(text: '길드원 목록'),
                    Tab(text: '길드 버프'),
                    Tab(text: '길드 상점'),
                    Tab(text: '길드 던전'),
                    Tab(text: '길드 레이드'),
                    Tab(text: '길드 전쟁'),
                    Tab(text: '길드 채팅'),
                  ],
                ),
                const Expanded(
                  child: TabBarView(
                    children: [
                      _GuildMembersTab(),
                      _GuildBuffsTab(),
                      GuildShopTab(),
                      GuildDungeonTab(),
                      GuildRaidTab(),
                      GuildWarTab(),
                      GuildChatTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GuildHeader extends StatelessWidget {
  const _GuildHeader({required this.onEditNotice, required this.onEditEmblem});

  final VoidCallback onEditNotice;
  final VoidCallback onEditEmblem;

  @override
  Widget build(BuildContext context) {
    final GuildManager manager = GuildManager.instance;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF20202C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A4A)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C4FCE).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF6C4FCE), width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      GuildEmblems.iconFor(manager.guildEmblem),
                      color: const Color(0xFF6C4FCE),
                      size: 28,
                    ),
                  ),
                  // 길드장만 엠블럼을 바꿀 수 있다 — 요구사항의 "길드장인 경우
                  // 엠블럼을 수정할 수 있는 연필 아이콘".
                  if (manager.isMaster)
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: GestureDetector(
                        onTap: onEditEmblem,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(color: Color(0xFF1B1B26), shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: const Icon(Icons.edit, size: 13, color: Colors.white70),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      manager.guildName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Lv.${manager.guildLevel}',
                      style: const TextStyle(
                        color: Color(0xFF6C4FCE),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: manager.expRatio,
                        minHeight: 8,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation(Color(0xFF6C4FCE)),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${manager.guildExp} / ${GuildManager.expForLevel(manager.guildLevel)}',
                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.campaign, color: Colors.amberAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    manager.guildNotice.isEmpty ? '등록된 공지사항이 없어요.' : manager.guildNotice,
                    style: TextStyle(
                      color: manager.guildNotice.isEmpty ? Colors.white38 : Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ),
                // 길드장만 공지사항을 바꿀 수 있다.
                if (manager.isMaster)
                  GestureDetector(
                    onTap: onEditNotice,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.edit, size: 15, color: Colors.white54),
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

class _EditNoticeDialog extends StatefulWidget {
  const _EditNoticeDialog();

  @override
  State<_EditNoticeDialog> createState() => _EditNoticeDialogState();
}

class _EditNoticeDialogState extends State<_EditNoticeDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: GuildManager.instance.guildNotice,
  );
  bool _isSubmitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    await GuildManager.instance.updateNotice(_controller.text.trim());
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1B1B26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        '공지사항 수정',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: TextField(
        controller: _controller,
        maxLength: 200,
        maxLines: 4,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: '길드원에게 전할 공지를 입력하세요.',
          hintStyle: TextStyle(color: Colors.white38),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3A3A4A))),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF6C4FCE))),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6C4FCE),
            foregroundColor: Colors.white,
          ),
          child: const Text('저장'),
        ),
      ],
    );
  }
}

class _EditEmblemDialog extends StatefulWidget {
  const _EditEmblemDialog();

  @override
  State<_EditEmblemDialog> createState() => _EditEmblemDialogState();
}

class _EditEmblemDialogState extends State<_EditEmblemDialog> {
  late String _selected = GuildManager.instance.guildEmblem;
  bool _isSubmitting = false;

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    await GuildManager.instance.updateEmblem(_selected);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1B1B26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        '엠블럼 변경',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final MapEntry<String, IconData> entry in GuildEmblems.icons.entries)
            _EmblemChoice(
              icon: entry.value,
              selected: entry.key == _selected,
              onTap: () => setState(() => _selected = entry.key),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6C4FCE),
            foregroundColor: Colors.white,
          ),
          child: const Text('저장'),
        ),
      ],
    );
  }
}

/// [GuildLobbyScreen]의 창설 팝업에도 같은 모양의 위젯이 있지만, private
/// (파일 스코프) 위젯이라 공유하는 대신 여기 다시 작게 둔다.
class _EmblemChoice extends StatelessWidget {
  const _EmblemChoice({required this.icon, required this.selected, required this.onTap});

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF6C4FCE).withValues(alpha: 0.3) : Colors.black38,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? const Color(0xFF6C4FCE) : const Color(0xFF3A3A4A),
            width: selected ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: selected ? const Color(0xFF6C4FCE) : Colors.white54),
      ),
    );
  }
}

class _GuildMembersTab extends StatelessWidget {
  const _GuildMembersTab();

  Future<void> _promote(BuildContext context, GuildMember member) async {
    final bool success = await GuildManager.instance.promoteToElder(member.userId);
    if (!context.mounted) {
      return;
    }
    showCenterToast(context, success ? '${member.nickname}님을 부길드장으로 임명했어요.' : '처리에 실패했어요.');
  }

  Future<void> _confirmKick(BuildContext context, GuildMember member) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('길드원 추방', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          '${member.nickname}님을 길드에서 추방할까요?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('추방', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final bool success = await GuildManager.instance.kickMember(member.userId);
    if (!context.mounted) {
      return;
    }
    showCenterToast(context, success ? '${member.nickname}님을 추방했어요.' : '처리에 실패했어요.');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: GuildManager.instance,
      builder: (context, _) {
        final GuildManager manager = GuildManager.instance;
        final List<GuildMember> members = manager.members;

        if (members.isEmpty) {
          return const Center(
            child: Text('길드원 정보를 불러오는 중이에요.', style: TextStyle(color: Colors.white54)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: members.length,
          itemBuilder: (context, index) {
            final GuildMember member = members[index];
            final bool isSelf = member.userId == SupabaseManager.instance.currentUserId;
            final bool canManage =
                manager.canManageMembers && !isSelf && member.role != GuildRole.master;
            return _MemberTile(
              member: member,
              canManage: canManage,
              onKick: () => _confirmKick(context, member),
              onPromote: () => _promote(context, member),
            );
          },
        );
      },
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.canManage,
    required this.onKick,
    required this.onPromote,
  });

  final GuildMember member;
  final bool canManage;
  final VoidCallback onKick;
  final VoidCallback onPromote;

  Color get _roleColor => switch (member.role) {
    GuildRole.master => Colors.amberAccent,
    GuildRole.elder => Colors.cyanAccent,
    GuildRole.member => Colors.white54,
  };

  /// "최종 접속: YYYY-MM-DD HH:MM" — intl 패키지 없이 이 프로젝트 전반의
  /// 관례([GuildManager._formatDate] 등)와 동일하게 padLeft로 직접 조립한다.
  static String _formatLastSeen(DateTime? lastSeen) {
    if (lastSeen == null) {
      return '접속 기록 없음';
    }
    String two(int n) => n.toString().padLeft(2, '0');
    final String date = '${lastSeen.year}-${two(lastSeen.month)}-${two(lastSeen.day)}';
    final String time = '${two(lastSeen.hour)}:${two(lastSeen.minute)}';
    return '최종 접속: $date $time';
  }

  @override
  Widget build(BuildContext context) {
    // 길드장 전용 정보라 요구사항대로 뷰어(나) 기준으로 판단한다 —
    // member.role이 아니라 GuildManager.instance.isMaster(내 직책).
    final bool showLastSeenToViewer = GuildManager.instance.isMaster;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF20202C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3A4A)),
      ),
      child: Row(
        children: [
          Icon(
            member.role == GuildRole.master ? Icons.workspace_premium : Icons.person,
            color: _roleColor,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // 접속중(🟢)/오프라인(⚪) 표시 — 최근 5분
                    // (GuildMember.onlineThreshold) 이내 접속이면 초록.
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: member.isOnline ? Colors.greenAccent : Colors.white24,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        member.nickname,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                Text(
                  guildRoleLabel(member.role),
                  style: TextStyle(color: _roleColor, fontSize: 11, fontWeight: FontWeight.bold),
                ),
                // 길드장에게만 보이는 다른 길드원의 최종 접속 시각 — 일반
                // 길드원은 이 줄 자체가 렌더링되지 않는다.
                if (showLastSeenToViewer)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _formatLastSeen(member.lastSeen),
                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                  ),
              ],
            ),
          ),
          Flexible(
            child: Text(
              '기여도 ${NumberFormatter.format(member.contribution.toDouble())}',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          if (canManage)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white54),
              color: const Color(0xFF20202C),
              onSelected: (value) {
                if (value == 'kick') {
                  onKick();
                } else if (value == 'promote') {
                  onPromote();
                }
              },
              itemBuilder: (context) => [
                if (member.role != GuildRole.elder)
                  const PopupMenuItem(
                    value: 'promote',
                    child: Text('부길드장 임명', style: TextStyle(color: Colors.white)),
                  ),
                const PopupMenuItem(
                  value: 'kick',
                  child: Text('추방', style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _GuildBuffsTab extends StatelessWidget {
  const _GuildBuffsTab();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: GuildManager.instance,
      builder: (context, _) {
        final GuildManager manager = GuildManager.instance;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _BuffTile(
              icon: Icons.local_fire_department,
              title: '공격력 증가',
              valueLabel: '+${(manager.attackBonus * 100).toStringAsFixed(0)}%',
            ),
            const SizedBox(height: 10),
            _BuffTile(
              icon: Icons.monetization_on,
              title: '골드 획득량 증가',
              valueLabel: '+${(manager.goldBonus * 100).toStringAsFixed(0)}%',
            ),
            const SizedBox(height: 16),
            const Text(
              '길드 레벨이 오를수록 버프 수치도 함께 증가해요. 출석체크로 길드 exp를\n올려 다 함께 레벨을 올려 보세요!',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        );
      },
    );
  }
}

class _BuffTile extends StatelessWidget {
  const _BuffTile({required this.icon, required this.title, required this.valueLabel});

  final IconData icon;
  final String title;
  final String valueLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF20202C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3A4A)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.amberAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          Text(
            valueLabel,
            style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ],
      ),
    );
  }
}
