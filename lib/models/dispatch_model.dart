import '../models/consumable_item_model.dart';

/// 파견(아르바이트) 임무 소요 시간 — [DispatchManager.maxSlots]개의 슬롯
/// 각각이 이 셋 중 하나를 골라 시작한다.
enum DispatchDuration {
  twoHours,
  fourHours,
  eightHours,
}

extension DispatchDurationX on DispatchDuration {
  Duration get duration {
    switch (this) {
      case DispatchDuration.twoHours:
        return const Duration(hours: 2);
      case DispatchDuration.fourHours:
        return const Duration(hours: 4);
      case DispatchDuration.eightHours:
        return const Duration(hours: 8);
    }
  }

  String get displayName {
    switch (this) {
      case DispatchDuration.twoHours:
        return '2시간';
      case DispatchDuration.fourHours:
        return '4시간';
      case DispatchDuration.eightHours:
        return '8시간';
    }
  }
}

/// 진행 중인 파견 임무 하나 — 슬롯(0~[DispatchManager.maxSlots]-1)에 최대
/// [DispatchManager.maxCharactersPerMission]명까지 편성해서 보낸다.
/// [remaining]/[isComplete]는 저장된 [startTime] + [duration]으로부터 매번
/// 새로 계산하는 파생값이라, 앱을 껐다 켜도(오프라인 방치) 정확하다 —
/// 별도의 "남은 시간" 필드를 직접 들고 다니지 않는다.
class DispatchMission {
  DispatchMission({
    required this.slotIndex,
    required this.characterIds,
    required this.duration,
    required this.startTime,
  });

  final int slotIndex;

  /// 이 임무에 편성된 캐릭터 ID들(Equipment.gradeBadgeLabel) — 1~
  /// [DispatchManager.maxCharactersPerMission]명.
  final List<String> characterIds;

  final DispatchDuration duration;
  final DateTime startTime;

  DateTime get endTime => startTime.add(duration.duration);

  /// 남은 시간 — 이미 끝났다면 [Duration.zero](음수를 돌려주지 않는다).
  Duration get remaining {
    final Duration left = endTime.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  bool get isComplete => remaining == Duration.zero;

  Map<String, dynamic> toJson() => {
    'slotIndex': slotIndex,
    'characterIds': characterIds,
    'duration': duration.name,
    'startTime': startTime.toIso8601String(),
  };

  factory DispatchMission.fromJson(Map<String, dynamic> json) => DispatchMission(
    slotIndex: json['slotIndex'] as int,
    characterIds: (json['characterIds'] as List<dynamic>).cast<String>(),
    duration: DispatchDuration.values.byName(json['duration'] as String),
    startTime: DateTime.parse(json['startTime'] as String),
  );
}

/// [DispatchManager.claimReward] 정산 결과 — 완료 다이얼로그/토스트가 이
/// 그대로 보여준다.
class DispatchRewardResult {
  const DispatchRewardResult({
    required this.gold,
    required this.exp,
    required this.giftItems,
  });

  final int gold;

  /// 캐릭터 개별 경험치 — 이 프로젝트에는 아직 "경험치"라는 진짜 재화가
  /// 없어서(장비 레벨업은 골드로만 진행) 지금은 표시용 더미 값이다. 실제
  /// 경험치/성장 시스템이 확정되면 [DispatchManager._expRewardFor]가
  /// 그 시스템에 값을 흘려주도록 바꾸면 되고, 이 결과 클래스의 구조 자체는
  /// 그대로 재사용할 수 있다.
  final int exp;

  /// 파견 완료 시 확률적으로 얻는 호감도 선물 아이템(꽃/초콜릿/보석) —
  /// [DispatchManager._rollGiftDrops] 참고.
  final List<ConsumableType> giftItems;
}
