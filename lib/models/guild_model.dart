import '../constants/guild_emblems.dart';

/// `guilds` 테이블 한 행의 목록용 요약 — [GuildLobbyScreen]의 길드 리스트
/// 카드에 필요한 최소 정보만 담는다. `memberCount`는 별도 컬럼이 아니라
/// PostgREST의 `guild_members(count)` 임베드 집계로 채운다(요구사항에
/// 인원수 컬럼이 명시되지 않아, 실제 멤버 행 수를 세는 쪽이 항상 정확).
class GuildSummary {
  const GuildSummary({
    required this.id,
    required this.name,
    required this.emblem,
    required this.level,
    required this.memberCount,
  });

  final String id;
  final String name;
  final String emblem;
  final int level;
  final int memberCount;

  factory GuildSummary.fromJson(Map<String, dynamic> json) {
    final List<dynamic>? countEmbed = json['guild_members'] as List<dynamic>?;
    final int memberCount = (countEmbed != null && countEmbed.isNotEmpty)
        ? ((countEmbed.first as Map<String, dynamic>)['count'] as num?)?.toInt() ?? 0
        : 0;
    return GuildSummary(
      id: json['id'].toString(),
      name: json['name'] as String,
      emblem: json['emblem'] as String? ?? GuildEmblems.defaultKey,
      level: (json['level'] as num?)?.toInt() ?? 1,
      memberCount: memberCount,
    );
  }
}

/// `guilds` 테이블 한 행 전체 — [GuildMainScreen] 상단 헤더가 쓰는 상세
/// 정보. 실제 컬럼 스키마는 요구사항에 명시되지 않아, 이 장르에서 흔히
/// 쓰는 최소 구성으로 가정했다: `id`, `name`, `emblem`, `level`, `exp`,
/// `notice`, `master_id`.
class GuildInfo {
  const GuildInfo({
    required this.id,
    required this.name,
    required this.emblem,
    required this.level,
    required this.exp,
    required this.notice,
    required this.masterId,
  });

  final String id;
  final String name;
  final String emblem;
  final int level;
  final int exp;
  final String notice;
  final String masterId;

  factory GuildInfo.fromJson(Map<String, dynamic> json) => GuildInfo(
    id: json['id'].toString(),
    name: json['name'] as String,
    emblem: json['emblem'] as String? ?? GuildEmblems.defaultKey,
    level: (json['level'] as num?)?.toInt() ?? 1,
    exp: (json['exp'] as num?)?.toInt() ?? 0,
    notice: json['notice'] as String? ?? '',
    masterId: json['master_id'] as String? ?? '',
  );
}

/// [GuildManager.createGuild] 결과 — [SupabaseManager.setNickname]의
/// [NicknameUpdateResult]와 같은 관례: 실패 이유별로 갈래를 나눠서,
/// 호출부([_CreateGuildDialog])가 정확한 안내 문구를 보여줄 수 있게 한다.
enum GuildCreateResult { success, duplicateName, insufficientGems, error }

/// `guild_members.role` 값 — 문자열을 직접 여기저기서 비교하지 않도록
/// enum으로 감싼다.
enum GuildRole { master, elder, member }

GuildRole guildRoleFromString(String? value) => switch (value) {
  'master' => GuildRole.master,
  'elder' => GuildRole.elder,
  _ => GuildRole.member,
};

String guildRoleColumnValue(GuildRole role) => switch (role) {
  GuildRole.master => 'master',
  GuildRole.elder => 'elder',
  GuildRole.member => 'member',
};

String guildRoleLabel(GuildRole role) => switch (role) {
  GuildRole.master => '길드장',
  GuildRole.elder => '부길드장',
  GuildRole.member => '길드원',
};

/// `guild_members` + `profiles(nickname)` 임베드 조회 결과 한 행 —
/// [GuildMainScreen]의 "길드원 목록" 탭 리스트 아이템.
class GuildMember {
  const GuildMember({
    required this.userId,
    required this.nickname,
    required this.role,
    required this.contribution,
  });

  final String userId;
  final String nickname;
  final GuildRole role;
  final int contribution;

  factory GuildMember.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? profile = json['profiles'] as Map<String, dynamic>?;
    final String? nickname = profile?['nickname'] as String?;
    return GuildMember(
      userId: json['user_id'] as String,
      nickname: (nickname == null || nickname.trim().isEmpty) ? '익명의 모험가' : nickname,
      role: guildRoleFromString(json['role'] as String?),
      contribution: (json['contribution'] as num?)?.toInt() ?? 0,
    );
  }
}
