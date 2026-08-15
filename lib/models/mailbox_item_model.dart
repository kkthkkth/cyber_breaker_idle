/// `mailbox` 테이블 한 행 — 월드보스 랭킹 보상 등 서버가 발송한 우편
/// 하나를 나타낸다. 실제 컬럼 스키마(유저 확인 완료): `id`, `title`,
/// `content`(선택, 본문), `reward_type`('gold'|'gem' 등),
/// `reward_amount`, `is_claimed`, `created_at`, `expires_at`(발송 30일
/// 뒤 만료 — 지금은 값만 들고 있고 UI/로직에서는 아직 안 쓴다).
class MailboxItem {
  const MailboxItem({
    required this.id,
    required this.title,
    required this.rewardType,
    required this.rewardAmount,
    required this.isClaimed,
    this.content,
    this.createdAt,
    this.expiresAt,
  });

  final String id;
  final String title;
  final String? content;

  /// 'gold' | 'gem' 등 — 서버 값을 그대로 보관한다.
  final String rewardType;
  final int rewardAmount;
  final bool isClaimed;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  /// "보석 10000개" / "골드 500" 처럼 사람이 읽는 라벨.
  String get rewardLabel => switch (rewardType) {
    'gem' => '보석 $rewardAmount개',
    'gold' || 'coin' => '골드 $rewardAmount',
    _ => '$rewardType $rewardAmount',
  };

  MailboxItem copyAsClaimed() => MailboxItem(
    id: id,
    title: title,
    content: content,
    rewardType: rewardType,
    rewardAmount: rewardAmount,
    isClaimed: true,
    createdAt: createdAt,
    expiresAt: expiresAt,
  );

  factory MailboxItem.fromJson(Map<String, dynamic> json) => MailboxItem(
    id: json['id'].toString(),
    title: json['title'] as String? ?? '우편',
    content: json['content'] as String?,
    rewardType: json['reward_type'] as String? ?? 'gold',
    rewardAmount: (json['reward_amount'] as num?)?.toInt() ?? 0,
    isClaimed: json['is_claimed'] as bool? ?? false,
    createdAt: json['created_at'] != null
        ? DateTime.tryParse(json['created_at'] as String)
        : null,
    expiresAt: json['expires_at'] != null
        ? DateTime.tryParse(json['expires_at'] as String)
        : null,
  );

  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'title': title,
    'content': content,
    'reward_type': rewardType,
    'reward_amount': rewardAmount,
    'is_claimed': isClaimed,
    'created_at': createdAt?.toIso8601String(),
    'expires_at': expiresAt?.toIso8601String(),
  };
}
