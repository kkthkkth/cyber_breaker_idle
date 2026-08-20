import 'package:flutter/material.dart';

import 'character_face_portrait.dart';

/// 유저 아바타 원형 위젯 — `profiles.equipped_character`
/// ([Equipment.gradeBadgeLabel] 형식)가 있으면 [CharacterFacePortrait]
/// 썸네일을 원형으로 잘라 보여주고, 없으면(옛 계정 등) 기본 사람 아이콘
/// 으로 대체한다. [FriendScreen]/[RankingScreen] 양쪽이 공유한다.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, this.characterId, this.size = 44, this.onlineDot});

  final String? characterId;
  final double size;

  /// null이면 온라인 점을 그리지 않는다(랭킹 화면처럼 온라인 여부가
  /// 의미 없는 곳) — true/false를 주면 초록/회색 점을 오른쪽 아래에 얹는다.
  final bool? onlineDot;

  @override
  Widget build(BuildContext context) {
    final String? id = characterId;
    final Widget avatar = ClipOval(
      child: Container(
        width: size,
        height: size,
        color: const Color(0xFF2C2C3A),
        child: id == null
            ? Icon(Icons.person, color: Colors.white70, size: size * 0.55)
            : CharacterFacePortrait(characterId: id),
      ),
    );
    final bool? online = onlineDot;
    if (online == null) {
      return avatar;
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          bottom: -1,
          right: -1,
          child: Container(
            width: size * 0.32,
            height: size * 0.32,
            decoration: BoxDecoration(
              color: online ? Colors.greenAccent : Colors.white24,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF14141C), width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
