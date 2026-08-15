import 'package:flutter/material.dart';

import '../constants/guild_emblems.dart';
import '../managers/game_manager.dart';
import '../managers/guild_manager.dart';
import '../managers/supabase_manager.dart';
import '../models/guild_model.dart';
import '../widgets/center_toast.dart';

/// 미가입 상태 전용 — 현재 생성된 길드 목록(즉시 가입)과 길드 창설
/// 팝업을 보여준다. [GuildManager.createGuild]/[joinGuild]가 성공하면
/// [GuildScreen]이 자동으로 [GuildMainScreen]으로 바꿔치기하므로, 이
/// 화면은 성공 후 스스로 다른 화면으로 넘어갈 필요가 없다.
class GuildLobbyScreen extends StatefulWidget {
  const GuildLobbyScreen({super.key});

  @override
  State<GuildLobbyScreen> createState() => _GuildLobbyScreenState();
}

class _GuildLobbyScreenState extends State<GuildLobbyScreen> {
  bool _isLoading = true;
  List<GuildSummary> _guilds = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    final List<Map<String, dynamic>> rows = await SupabaseManager.instance.fetchGuildList();
    if (!mounted) {
      return;
    }
    setState(() {
      _guilds = rows.map(GuildSummary.fromJson).toList();
      _isLoading = false;
    });
  }

  Future<void> _join(GuildSummary guild) async {
    final bool success = await GuildManager.instance.joinGuild(guild.id);
    if (!mounted) {
      return;
    }
    showCenterToast(
      context,
      success ? '${guild.name} 길드에 가입했어요!' : '가입에 실패했어요. 다시 시도해 주세요.',
    );
  }

  void _showCreateDialog() {
    showDialog<void>(context: context, builder: (context) => const _CreateGuildDialog());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14141C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B1B26),
        elevation: 0,
        // 뒤로 가기 버튼처럼 별도 색을 안 준 아이콘이 어두운 배경에
        // 묻히지 않도록 명시한다.
        foregroundColor: Colors.white,
        title: const Text('길드', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _isLoading ? null : _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showCreateDialog,
                icon: const Icon(Icons.add),
                label: Text('길드 창설 (보석 ${GuildManager.createCostGems}개)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C4FCE),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.white54))
                : _guilds.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        '아직 생성된 길드가 없어요.\n첫 번째 길드를 만들어 보세요!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: _guilds.length,
                    itemBuilder: (context, index) {
                      final GuildSummary guild = _guilds[index];
                      return _GuildListTile(guild: guild, onJoin: () => _join(guild));
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _GuildListTile extends StatelessWidget {
  const _GuildListTile({required this.guild, required this.onJoin});

  final GuildSummary guild;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF20202C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF3A3A4A), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF6C4FCE).withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF6C4FCE)),
            ),
            alignment: Alignment.center,
            child: Icon(GuildEmblems.iconFor(guild.emblem), color: const Color(0xFF6C4FCE)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  guild.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  'Lv.${guild.level} · 인원 ${guild.memberCount}명',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onJoin,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C4FCE),
              foregroundColor: Colors.white,
            ),
            child: const Text('가입 신청'),
          ),
        ],
      ),
    );
  }
}

/// 길드명 입력 + 엠블럼 선택 후 [GuildManager.createGuild]를 호출하는
/// 팝업 — [NicknameScreen]과 같은 관례로, 이름 중복은 별도 "중복확인"
/// 버튼 없이 창설 시도 시점에 한 번에 검증하고 결과별로 다른 안내 문구를
/// 보여준다.
class _CreateGuildDialog extends StatefulWidget {
  const _CreateGuildDialog();

  @override
  State<_CreateGuildDialog> createState() => _CreateGuildDialogState();
}

class _CreateGuildDialogState extends State<_CreateGuildDialog> {
  final TextEditingController _nameController = TextEditingController();
  String _selectedEmblem = GuildEmblems.defaultKey;
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = '길드명을 입력해 주세요.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    final GuildCreateResult result = await GuildManager.instance.createGuild(
      name: name,
      emblem: _selectedEmblem,
    );
    if (!mounted) {
      return;
    }
    switch (result) {
      case GuildCreateResult.success:
        Navigator.of(context).pop();
      case GuildCreateResult.duplicateName:
        setState(() {
          _isSubmitting = false;
          _errorText = '이미 사용 중인 길드명이에요.';
        });
      case GuildCreateResult.insufficientGems:
        setState(() {
          _isSubmitting = false;
          _errorText = '보석이 부족해요. (필요: ${GuildManager.createCostGems}개)';
        });
      case GuildCreateResult.error:
        setState(() {
          _isSubmitting = false;
          _errorText = '창설에 실패했어요. 잠시 후 다시 시도해 주세요.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1B1B26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        '길드 창설',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '보석 ${GuildManager.createCostGems}개를 소모합니다. (보유: ${GameManager.instance.gems}개)',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameController,
              maxLength: 12,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: '길드명',
                labelStyle: const TextStyle(color: Colors.white54),
                errorText: _errorText,
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF3A3A4A)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF6C4FCE)),
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '엠블럼 선택',
              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final MapEntry<String, IconData> entry in GuildEmblems.icons.entries)
                  _EmblemChoice(
                    icon: entry.value,
                    selected: entry.key == _selectedEmblem,
                    onTap: () => setState(() => _selectedEmblem = entry.key),
                  ),
              ],
            ),
          ],
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
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('창설하기'),
        ),
      ],
    );
  }
}

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
