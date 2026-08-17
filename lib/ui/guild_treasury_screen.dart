import 'package:flutter/material.dart';

import '../managers/guild_manager.dart';
import '../managers/guild_war_manager.dart';
import '../models/guild_model.dart';
import '../utils/number_formatter.dart';
import '../widgets/bouncy_button.dart';
import '../widgets/center_toast.dart';

/// [전리품 분배] 화면 — 길드장 전용. 길드 금고(길드 전쟁 승리 보상이
/// 쌓이는 곳, 유저 개인 재화와 완전히 분리)에서 길드원 한 명을 골라
/// 원하는 금액만큼 개인 재화로 옮긴다(Transfer). [GuildMainScreen]에서
/// 길드장에게만 보이는 진입점(AppBar 아이콘 등)으로 연결한다.
class GuildTreasuryScreen extends StatefulWidget {
  const GuildTreasuryScreen({super.key});

  @override
  State<GuildTreasuryScreen> createState() => _GuildTreasuryScreenState();
}

class _GuildTreasuryScreenState extends State<GuildTreasuryScreen> {
  @override
  void initState() {
    super.initState();
    GuildManager.instance.refreshGuild();
    GuildManager.instance.refreshMembers();
  }

  void _openTransferDialog(GuildMember member) {
    showDialog<void>(
      context: context,
      builder: (context) => _TransferDialog(member: member),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: GuildManager.instance,
      builder: (context, _) {
        final GuildManager manager = GuildManager.instance;
        return Scaffold(
          backgroundColor: const Color(0xFF14141C),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1B1B26),
            elevation: 0,
            foregroundColor: Colors.white,
            title: const Text('전리품 분배', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            centerTitle: true,
          ),
          body: Column(
            children: [
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF20202C),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFFD54F).withValues(alpha: 0.6)),
                ),
                child: Column(
                  children: [
                    const Text('길드 금고', style: TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.monetization_on, color: Colors.amberAccent, size: 20),
                        const SizedBox(width: 6),
                        Text(
                          NumberFormatter.format(manager.treasuryCoin.toDouble()),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        const SizedBox(width: 20),
                        const Icon(Icons.diamond, color: Colors.cyanAccent, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          NumberFormatter.format(manager.treasuryGem.toDouble()),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('길드원을 선택해 금고에서 재화를 지급하세요.', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: manager.members.isEmpty
                    ? const Center(
                        child: Text('길드원 정보를 불러오는 중이에요.', style: TextStyle(color: Colors.white54)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: manager.members.length,
                        itemBuilder: (context, index) {
                          final GuildMember member = manager.members[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF20202C),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF3A3A4A)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.person, color: Colors.white54, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    member.nickname,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: withTapHaptic(() => _openTransferDialog(member)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFFD54F),
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  ),
                                  child: const Text('지급'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TransferDialog extends StatefulWidget {
  const _TransferDialog({required this.member});

  final GuildMember member;

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  final TextEditingController _coinController = TextEditingController();
  final TextEditingController _gemController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _coinController.dispose();
    _gemController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final int coinAmount = int.tryParse(_coinController.text.trim()) ?? 0;
    final int gemAmount = int.tryParse(_gemController.text.trim()) ?? 0;
    if (coinAmount <= 0 && gemAmount <= 0) {
      showCenterToast(context, '지급할 금액을 입력해주세요.');
      return;
    }
    setState(() => _isSubmitting = true);
    final bool success = await GuildWarManager.instance.transferTreasury(
      targetUserId: widget.member.userId,
      coinAmount: coinAmount,
      gemAmount: gemAmount,
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    showCenterToast(
      context,
      success ? '${widget.member.nickname}님에게 지급했습니다.' : '지급에 실패했어요(금고 잔액을 확인해주세요).',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1B1B26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        '${widget.member.nickname}님에게 지급',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _coinController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: '코인',
              labelStyle: TextStyle(color: Colors.white54),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3A3A4A))),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFFFD54F))),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _gemController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: '보석',
              labelStyle: TextStyle(color: Colors.white54),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3A3A4A))),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFFFD54F))),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: withTapHaptic(_isSubmitting ? null : _submit),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD54F), foregroundColor: Colors.black),
          child: _isSubmitting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('지급'),
        ),
      ],
    );
  }
}
