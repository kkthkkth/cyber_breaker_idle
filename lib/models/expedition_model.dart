/// [ExpeditionReward.type]에 쓰이는 탐험 보상 종류.
enum ExpeditionRewardType { gold, gem, talentPoint }

extension ExpeditionRewardTypeX on ExpeditionRewardType {
  String get displayName {
    switch (this) {
      case ExpeditionRewardType.gold:
        return '골드';
      case ExpeditionRewardType.gem:
        return '보석';
      case ExpeditionRewardType.talentPoint:
        return '특성 포인트';
    }
  }
}

/// 탐험 완료 시 지급되는 보상 하나 — 한 지역이 여러 종류를 동시에 줄 수
/// 있다(예: 골드 + 보석).
class ExpeditionReward {
  const ExpeditionReward({required this.type, required this.amount});

  final ExpeditionRewardType type;
  final int amount;

  String get displayText => '${type.displayName} +$amount';
}

/// 탐험 지역(카탈로그) 하나 — [ExpeditionCatalog.regions]에 하드코딩된
/// 정의다([TalentManager]의 하드코딩 트리와 같은 관례: "테스트용으로 N개
/// 정도의 하드코딩된... 구조를 만들어줘"). 서버 테이블이 아니라 이
/// 파일이 유일한 정의 소스다 — [ExpeditionManager]/Supabase
/// `user_expeditions`는 오직 "누가 어느 지역에 무엇을 보냈고 언제
/// 끝나는지" 진행도만 다룬다.
class ExpeditionRegion {
  const ExpeditionRegion({
    required this.id,
    required this.name,
    required this.description,
    required this.duration,
    required this.minUnits,
    required this.rewards,
  });

  final String id;
  final String name;
  final String description;
  final Duration duration;

  /// 파견대에 최소 이만큼의 유닛(캐릭터/펫)을 편성해야 한다 — 요구사항
  /// 예시: "펫 최소 3마리".
  final int minUnits;

  final List<ExpeditionReward> rewards;

  String get durationLabel {
    final int hours = duration.inHours;
    return '$hours시간';
  }

  String get rewardsLabel => rewards.map((reward) => reward.displayText).join(' · ');
}

/// [ExpeditionCatalog]가 정의하는 테스트용 지역 3종 — 정확한 밸런스
/// 데이터가 없어 임의로 정한 값이니, 기획 수치가 정해지면 이 리스트만
/// 고치면 된다.
class ExpeditionCatalog {
  const ExpeditionCatalog._();

  static const List<ExpeditionRegion> regions = [
    ExpeditionRegion(
      id: 'whispering_forest',
      name: '속삭이는 숲',
      description: '가벼운 정찰 임무 — 짧은 시간 안에 소소한 골드를 벌어온다.',
      duration: Duration(hours: 4),
      minUnits: 1,
      rewards: [ExpeditionReward(type: ExpeditionRewardType.gold, amount: 5000)],
    ),
    ExpeditionRegion(
      id: 'sunken_ruins',
      name: '가라앉은 유적',
      description: '보석이 매장된 유적 — 인원이 좀 더 필요하지만 보석도 함께 캐온다.',
      duration: Duration(hours: 8),
      minUnits: 2,
      rewards: [
        ExpeditionReward(type: ExpeditionRewardType.gold, amount: 15000),
        ExpeditionReward(type: ExpeditionRewardType.gem, amount: 30),
      ],
    ),
    ExpeditionRegion(
      id: 'starlit_summit',
      name: '별빛 봉우리',
      description: '가장 위험한 원정 — 대규모 파견대가 필요하지만 특성 포인트까지 얻는다.',
      duration: Duration(hours: 12),
      minUnits: 3,
      rewards: [
        ExpeditionReward(type: ExpeditionRewardType.gold, amount: 30000),
        ExpeditionReward(type: ExpeditionRewardType.talentPoint, amount: 1),
      ],
    ),
  ];

  static ExpeditionRegion? findById(String id) {
    for (final ExpeditionRegion region in regions) {
      if (region.id == id) {
        return region;
      }
    }
    return null;
  }
}

/// 진행 중(또는 완료됐지만 아직 보상을 안 받은) 탐험 임무 하나 — 지역
/// 하나당 동시에 최대 1개까지만 존재할 수 있다([ExpeditionManager]가
/// regionId를 키로 관리).
class ExpeditionMission {
  const ExpeditionMission({
    required this.regionId,
    required this.unitIds,
    required this.startTime,
    this.isCollected = false,
  });

  final String regionId;

  /// 파견 보낸 유닛(캐릭터/펫 겸용) [Equipment.id] 목록.
  final List<String> unitIds;

  final DateTime startTime;
  final bool isCollected;

  ExpeditionRegion? get region => ExpeditionCatalog.findById(regionId);

  DateTime get endTime => startTime.add(region?.duration ?? Duration.zero);

  /// [now](기기 시계 대신 NTP로 검증된 시각을 넘겨야 한다 — [DispatchMission
  /// .isCompleteAt]과 같은 이유, 기기 시계 조작으로 조기 완료를 막기 위함)
  /// 기준으로 이미 끝났는지.
  bool isCompleteAt(DateTime now) => !now.isBefore(endTime);

  /// [now] 기준 남은 시간 — 이미 끝났으면 [Duration.zero].
  Duration remainingAt(DateTime now) {
    final Duration diff = endTime.difference(now);
    return diff.isNegative ? Duration.zero : diff;
  }

  ExpeditionMission copyWith({bool? isCollected}) => ExpeditionMission(
    regionId: regionId,
    unitIds: unitIds,
    startTime: startTime,
    isCollected: isCollected ?? this.isCollected,
  );

  Map<String, dynamic> toJson() => {
    'region_id': regionId,
    'unit_ids': unitIds,
    'start_time': startTime.toIso8601String(),
    'is_collected': isCollected,
  };

  factory ExpeditionMission.fromJson(Map<String, dynamic> json) => ExpeditionMission(
    regionId: json['region_id'] as String,
    unitIds: (json['unit_ids'] as List<dynamic>).cast<String>(),
    startTime: DateTime.parse(json['start_time'] as String),
    isCollected: json['is_collected'] as bool? ?? false,
  );
}
