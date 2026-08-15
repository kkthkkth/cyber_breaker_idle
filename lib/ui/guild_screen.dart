import 'package:flutter/material.dart';

import '../managers/guild_manager.dart';
import 'guild_lobby_screen.dart';
import 'guild_main_screen.dart';

/// 하단 '길드' 탭의 진입점 — [GuildManager.isInGuild] 하나로 미가입
/// 상태([GuildLobbyScreen])와 가입 상태([GuildMainScreen])를 갈라준다.
/// [GuildManager]를 구독만 하므로, 로비에서 창설/가입에 성공하는 순간
/// 자동으로 메인 화면으로 전환된다(별도 네비게이션 불필요).
class GuildScreen extends StatelessWidget {
  const GuildScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: GuildManager.instance,
      builder: (context, _) {
        return GuildManager.instance.isInGuild
            ? const GuildMainScreen()
            : const GuildLobbyScreen();
      },
    );
  }
}
