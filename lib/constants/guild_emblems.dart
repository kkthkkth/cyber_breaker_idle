import 'package:flutter/material.dart';

/// 길드 엠블럼 프리셋 — 실제 커스텀 아트가 없어 Material 아이콘으로 대신
/// 한다. `guilds.emblem` 컬럼에는 이 맵의 key(문자열)만 저장되고, 표시할
/// 때는 [iconFor]로 실제 [IconData]를 찾는다 — 알 수 없는 key(구버전
/// 데이터 등)가 와도 [defaultKey]로 조용히 대체된다.
class GuildEmblems {
  const GuildEmblems._();

  static const String defaultKey = 'shield';

  static const Map<String, IconData> icons = {
    'shield': Icons.shield,
    'flame': Icons.local_fire_department,
    'bolt': Icons.bolt,
    'star': Icons.star,
    'diamond': Icons.diamond,
    'trophy': Icons.emoji_events,
  };

  static IconData iconFor(String? key) => icons[key] ?? icons[defaultKey]!;
}
