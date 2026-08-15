/// 캐릭터 한 명당 호감도 저장 데이터 — [AffectionManager]가
/// characterId(Equipment.gradeBadgeLabel, 예: "N1")를 키로 관리한다.
///
/// RPG의 EXP 바와 동일한 구조다: [currentAffinityPercent]가 게이지이고,
/// 100에 도달할 때마다 [unlockedLevel]이 1씩 오르며 게이지는 0으로
/// 되돌아간다. 둘은 항상 분리된 상태로 관리된다 — "누적 퍼센트로 레벨을
/// 역산"하던 예전 방식은 쓰지 않는다.
class AffectionData {
  AffectionData({
    required this.characterId,
    this.unlockedLevel = 1,
    this.currentAffinityPercent = 0,
    this.chatCountToday = 0,
    this.lastChatDate,
    this.isOathed = false,
  });

  final String characterId;

  /// 현재 해금되어 탭 선택이 가능한 최대 레벨(1~[AffectionManager.maxLevel]).
  int unlockedLevel;

  /// 현재 레벨에서의 호감도 게이지(0~100) — 100에 도달하면
  /// [AffectionManager]가 [unlockedLevel]을 올리고 이 값을 0으로
  /// 리셋한다(초과분은 다음 레벨 게이지로 이월).
  double currentAffinityPercent;

  /// 오늘 나눈 대화 횟수 — [AffectionManager.maxChatsPerDay]에 도달하면
  /// 더 이상 대화를 시작할 수 없다. 날짜가 바뀌면(=[lastChatDate]가 오늘이
  /// 아니면) 0으로 리셋된다.
  int chatCountToday;

  /// 마지막으로 대화를 시작한 시각 — null이면 아직 한 번도 대화한 적 없음.
  DateTime? lastChatDate;

  /// 서약(Oath) 완료 여부 — 기본 false, [AffectionManager.tryOath]로 한 번
  /// true가 되면 절대 되돌아가지 않는 영구 상태다(장비처럼 뺐다 꼈다 하는
  /// 개념이 아니라 "1회성 소모품을 써서 영구히 바뀌는 신분"에 가깝다).
  /// true가 되면 적용되는 혜택(스킨 일러스트, 스탯 보너스, UI 뱃지)은 전부
  /// [AffectionManager.isOathed]/[AffectionManager.statMultiplierBonus]를
  /// 거쳐서 읽는다 — 이 필드를 UI에서 직접 읽지 않는다.
  bool isOathed;

  Map<String, dynamic> toJson() => {
    'characterId': characterId,
    'unlockedLevel': unlockedLevel,
    'currentAffinityPercent': currentAffinityPercent,
    'chatCountToday': chatCountToday,
    'lastChatDate': lastChatDate?.toIso8601String(),
    'isOathed': isOathed,
  };

  factory AffectionData.fromJson(Map<String, dynamic> json) => AffectionData(
    characterId: json['characterId'] as String,
    unlockedLevel: json['unlockedLevel'] as int? ?? 1,
    currentAffinityPercent: (json['currentAffinityPercent'] as num?)?.toDouble() ?? 0,
    chatCountToday: json['chatCountToday'] as int? ?? 0,
    lastChatDate: json['lastChatDate'] != null
        ? DateTime.parse(json['lastChatDate'] as String)
        : null,
    isOathed: json['isOathed'] as bool? ?? false,
  );
}
