import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/affection_model.dart';
import '../models/consumable_item_model.dart';
import '../models/shop_consumable_model.dart';
import '../utils/time_util.dart';
import 'consumable_manager.dart';
import 'potion_manager.dart';

/// 캐릭터별 서브컬처(미연시풍) 호감도 시스템을 관장하는 싱글턴.
///
/// [ConsumableManager]와 같은 패턴(ChangeNotifier + SharedPreferences 직렬화)을
/// 따른다 — characterId(Equipment.gradeBadgeLabel)를 키로 [AffectionData]를
/// 보관하고, 대화([beginChat]/[completeChat])와 선물([giftItem]) 두 경로로만
/// 게이지([AffectionData.currentAffinityPercent])가 오른다. RPG의 EXP
/// 바와 동일한 구조로, 게이지가 100%에 도달할 때마다
/// [AffectionData.unlockedLevel]이 오르고 게이지는 0으로 리셋된다
/// ([_applyGain] 참고) — "누적 퍼센트로 레벨을 역산"하던 예전 방식은
/// 완전히 제거했다.
///
/// 날짜 판정([_resetIfNewDay])은 [_currentReferenceNow]가 주기적으로
/// 새로고침하는 NTP 캐시를 기준으로 한다(기기 시계를 되돌려 하루 대화
/// 제한을 우회하는 것을 막기 위함 — 2026-08-21 보안 감사에서 추가).
class AffectionManager extends ChangeNotifier {
  AffectionManager._internal();

  static final AffectionManager instance = AffectionManager._internal();

  final Random _random = Random();

  final Map<String, AffectionData> _data = {};

  /// 하루에 허용되는 최대 대화 횟수.
  static const int maxChatsPerDay = 3;

  /// 호감도 레벨 총 단계 수(Lv.1~Lv.10) — EXP 바 방식으로 게이지가
  /// 100%에 도달할 때마다 1씩 오른다([_applyGain] 참고).
  static const int maxLevel = 10;

  /// 호감도 화면 하단 슬롯에 노출되는 "선물 전용" 소모품 종류.
  static const List<ConsumableType> giftTypes = [
    ConsumableType.giftFlower,
    ConsumableType.giftChocolate,
    ConsumableType.giftJewelry,
  ];

  /// 대화창에 랜덤으로 뜨는 안부 인사 — 지금은 캐릭터 공통 풀이고, 추후
  /// DB에서 캐릭터별 전용 대사 목록을 받아오게 되면 이 상수 대신 그 목록을
  /// 쓰도록 [beginChat] 호출부만 바꾸면 된다.
  static const List<String> _dialogueLines = [
    '오늘 하루도 고생 많았어요. 잠깐 쉬어가도 괜찮아요.',
    '요즘 부쩍 강해진 것 같아요. 다 당신 덕분이죠?',
    '심심하던 참이었는데, 와줘서 좋아요.',
    '다음 전투에도 제가 힘이 되어줄게요.',
    '가끔은 이렇게 얘기 나누는 시간도 필요한 것 같아요.',
    '오늘따라 왠지... 당신이 더 특별하게 느껴져요.',
    '무리하지 말고, 필요할 때 저를 불러줘요.',
    '당신과 함께라면 어떤 던전도 두렵지 않아요.',
  ];

  AffectionData dataFor(String characterId) =>
      _data.putIfAbsent(characterId, () => AffectionData(characterId: characterId));

  /// 현재 해금된 최대 레벨(1~[maxLevel]).
  int levelFor(String characterId) => dataFor(characterId).unlockedLevel;

  /// 현재 레벨 게이지(0~100) — UI는 [dataFor]로 직접 필드를 들여다보는
  /// 대신 이 읽기 전용 게터를 쓴다(실수로 값을 직접 대입해 게이지를
  /// 조작하는 경로를 만들지 않기 위함).
  double percentFor(String characterId) => dataFor(characterId).currentAffinityPercent;

  /// 이미 만렙(Lv.[maxLevel])에 도달했는지 — 도달했다면 대화/선물 어느
  /// 경로로도 게이지가 더 오르지 않고([_applyGain]), [giftItem]은 아이템
  /// 소모 자체를 거절한다.
  bool isMaxLevel(String characterId) => dataFor(characterId).unlockedLevel >= maxLevel;

  bool isLevelUnlocked(String characterId, int level) {
    if (level < 1 || level > maxLevel) {
      return false;
    }
    return level <= dataFor(characterId).unlockedLevel;
  }

  // ── 서약(Oath) ──────────────────────────────────────────────────────
  //
  // 서약 반지는 장비가 아니라 "1회성 특수 소모품"이다 — 장착/해제 슬롯이
  // 없고, [tryOath]로 한 번 소모하면 [AffectionData.isOathed]가 영구
  // true로 굳는다(장비 강화처럼 되돌릴 수 없다). 조건은 만렙([isMaxLevel])
  // 도달 + 아직 서약 안 함 + 인벤토리에 [ConsumableType.oathRing] 재고.

  bool isOathed(String characterId) => dataFor(characterId).isOathed;

  /// [AffectionScreen]이 "[서약하기]" 버튼을 보여줄지 판단하는 조건.
  bool canOath(String characterId) => isMaxLevel(characterId) && !isOathed(characterId);

  /// 서약 반지 1개를 소모하고 영구적으로 서약 상태로 바꾼다. 조건 미충족
  /// (만렙 아님/이미 서약함) 또는 반지 재고가 없으면 아무것도 바꾸지 않고
  /// false — 재고 확인 전에 조건부터 검사하므로, 조건이 안 맞으면 반지를
  /// 헛되이 들여다보지도 않는다([giftItem]의 만렙 사전 차단과 같은 패턴).
  bool tryOath(String characterId) {
    if (!canOath(characterId)) {
      return false;
    }
    final bool consumed = ConsumableManager.instance.consume(ConsumableType.oathRing);
    if (!consumed) {
      return false;
    }

    dataFor(characterId).isOathed = true;
    _saveData();
    notifyListeners();
    return true;
  }

  /// 서약 상태일 때 적용되는 기본 스탯 배율 보너스 — 지금은 10% 고정
  /// 더미값이다. **주의**: 이 게터는 값만 계산해 줄 뿐, 아직 실제 전투
  /// 스탯 합산 로직에 연결돼 있지 않다 — 연결 지점과 방법은
  /// [EquipmentManager.getTotalEquipmentMultiplier] 바로 위 주석에 정리해
  /// 뒀다(그 메서드를 직접 건드리지 않고 주석으로만 남겨 둔 이유도 함께
  /// 설명돼 있다).
  double statMultiplierBonus(String characterId) => isOathed(characterId) ? 1.1 : 1.0;

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// [_lastNtpSync] 이후 이만큼 지나면 다음 [_currentReferenceNow] 호출에서
  /// NTP를 다시 왕복한다 — 매 호출마다 네트워크 요청을 하지 않으면서도
  /// 기기 시계 조작으로부터 하루 대화 제한을 지킨다.
  static const Duration _ntpRefreshInterval = Duration(minutes: 5);

  DateTime? _cachedNtpNow;
  DateTime? _lastNtpSync;
  bool _ntpFetchInFlight = false;

  /// [보안 감사 2026-08-21] 예전엔 [_resetIfNewDay]가 기기 로컬 시각
  /// ([DateTime.now])만 봤다 — 클래스 문서에도 이미 "나중에 네트워크
  /// 시간으로 바꾸면 된다"고 적혀 있던 알려진 한계였다. 기기 시계를
  /// 과거로 돌리면 [AffectionData.lastChatDate]가 "아직 오늘"로 계속
  /// 남아 있어 하루 대화 횟수([maxChatsPerDay]) 제한을 무한히 우회할 수
  /// 있었다(대화는 아직 실제 전투 스탯에 연결돼 있지 않아 파급력은
  /// 작지만, 그래도 게이지 축적 자체를 무제한으로 만들 수 있는 결함).
  /// [GuildWarManager]의 배지 만료 캐시와 같은 방식으로, 매 호출마다
  /// NTP를 왕복하지 않고도([beginChat]/[remainingChatsToday]는 UI가 자주
  /// 부르는 동기 메서드라 async로 바꾸기 부담스럽다) 주기적으로만
  /// 새로고침한 서버 시간을 기준으로 판정해 기기 시계 조작을 막는다.
  DateTime _currentReferenceNow() {
    final DateTime deviceNow = DateTime.now();
    final bool stale =
        _lastNtpSync == null || deviceNow.difference(_lastNtpSync!) > _ntpRefreshInterval;
    if (stale && !_ntpFetchInFlight) {
      _ntpFetchInFlight = true;
      unawaited(
        getNetworkTime().then((DateTime now) {
          _cachedNtpNow = now;
          _lastNtpSync = DateTime.now();
        }).whenComplete(() => _ntpFetchInFlight = false),
      );
    }
    return _cachedNtpNow ?? deviceNow;
  }

  void _resetIfNewDay(AffectionData data) {
    final DateTime? last = data.lastChatDate;
    if (last == null) {
      return;
    }
    if (!_isSameDay(last, _currentReferenceNow())) {
      data.chatCountToday = 0;
    }
  }

  /// 오늘 더 나눌 수 있는 대화 횟수(0~[maxChatsPerDay]).
  ///
  /// [AffectionData.chatCountToday]를 먼저 [0, maxChatsPerDay] 범위로
  /// clamp한 뒤 뺀다 — 저장 파일 손상 등으로 음수가 들어와도
  /// `max(0, maxChatsPerDay - (-N))`처럼 하루 한도를 넘는 값이 계산되지
  /// 않도록 막는다(이 값이 그대로 [_ChatButton]의 표시/활성화 조건이 되므로
  /// 여기서 어긋나면 곧바로 어뷰징 경로가 된다).
  int remainingChatsToday(String characterId) {
    final AffectionData data = dataFor(characterId);
    _resetIfNewDay(data);
    final int usedToday = data.chatCountToday.clamp(0, maxChatsPerDay);
    return maxChatsPerDay - usedToday;
  }

  /// 대화를 "시작"한다 — 하루 제한을 소비하고 랜덤 대사 한 줄을 돌려준다.
  /// 오늘 횟수를 다 썼으면 null. 호감도 상승 자체는 대화창을 닫을 때
  /// [completeChat]에서 적용된다(요구사항: "대화를 다 보고 창을 닫으면
  /// 상승").
  String? beginChat(String characterId) {
    final AffectionData data = dataFor(characterId);
    _resetIfNewDay(data);
    if (data.chatCountToday >= maxChatsPerDay) {
      return null;
    }
    data.chatCountToday += 1;
    data.lastChatDate = _currentReferenceNow();
    _saveData();
    notifyListeners();
    return _dialogueLines[_random.nextInt(_dialogueLines.length)];
  }

  /// 대화 한 번당 오르는 호감도 — 지금은 더미 랜덤값. DB 연동 시 이
  /// 메서드만 서버 테이블 조회로 바꾸면 [beginChat]/[completeChat] 쪽은
  /// 손댈 필요 없다.
  double _affectionGainForChat() => (2 + _random.nextInt(3)).toDouble(); // 2~4%

  /// 대화창을 닫을 때 호출 — 호감도 상승을 적용하고 "실제로 반영된" 양을
  /// 돌려준다(토스트/이펙트 표시용). 이미 만렙이면 대사는 정상적으로
  /// 보여주되 게이지는 안 올라가므로 0을 돌려준다 — 호출부가 실제로
  /// 오르지 않았는데도 "+3% 올랐어요" 같은 거짓 안내를 띄우지 않도록
  /// [_applyGain]이 "적용된 양"을 그대로 리턴한다(굴린 더미 값이 아니다).
  double completeChat(String characterId) {
    final AffectionData data = dataFor(characterId);
    final double nominalGain = _affectionGainForChat();
    return _applyGain(data, nominalGain);
  }

  /// 선물 아이템 등급별 호감도 상승량 — 지금은 등급별 랜덤 범위의 더미
  /// 값이다. DB 연동 시 이 메서드 하나만 서버가 내려준 등급별 수치 조회로
  /// 바꾸면 [giftItem] 호출부는 그대로 재사용할 수 있다.
  double affectionGainForGift(ConsumableType type) {
    switch (type) {
      case ConsumableType.giftFlower:
        return (3 + _random.nextInt(3)).toDouble(); // 3~5%
      case ConsumableType.giftChocolate:
        return (6 + _random.nextInt(5)).toDouble(); // 6~10%
      case ConsumableType.giftJewelry:
        return (12 + _random.nextInt(9)).toDouble(); // 12~20%
      default:
        return (1 + _random.nextInt(2)).toDouble(); // 선물 전용 외 아이템 대비 fallback
    }
  }

  /// [ConsumableManager] 재고에서 [type] 1개를 소비하고 호감도를 올린다.
  /// 재고가 없으면(비정상 호출) null. **이미 만렙이면 재고를 건드리지도
  /// 않고 그 자리에서 거절한다** — 만렙 상태에서 선물해도 게이지가
  /// 안 오르는 건 물론, 아이템이 헛되이 소모되는 것 자체를 막는다
  /// (요구사항: "선물을 주거나 대화를 해도... 완벽하게 차단").
  double? giftItem(String characterId, ConsumableType type) {
    final AffectionData data = dataFor(characterId);
    if (data.unlockedLevel >= maxLevel) {
      return null;
    }

    final bool consumed = ConsumableManager.instance.consume(type);
    if (!consumed) {
      return null;
    }
    final double nominalGain = affectionGainForGift(type);
    return _applyGain(data, nominalGain);
  }

  /// [giftItem]과 같은 모양이지만, 재고 출처가 [ConsumableManager]가 아니라
  /// 상점에서 구매한 [PotionManager]의 `user_consumables` 인벤토리다
  /// ([entry.isAffectionGift]인 [ShopConsumableEntry]만 넘겨야 한다 — 물약을
  /// 실수로 넘겨도 막지는 않으니 호출부(UI)에서 필터링해서 골라준다). 상승치는
  /// 등급별 더미 랜덤이 아니라 DB의 `effect_value`를 그대로 쓴다. 만렙이면
  /// [giftItem]과 동일하게 재고를 건드리지 않고 그 자리에서 거절한다.
  Future<double?> giftShopItem(String characterId, ShopConsumableEntry entry) async {
    final AffectionData data = dataFor(characterId);
    if (data.unlockedLevel >= maxLevel) {
      return null;
    }

    final bool consumed = await PotionManager.instance.consumeItem(entry.id);
    if (!consumed) {
      return null;
    }
    return _applyGain(data, entry.effectValue);
  }

  /// EXP 바처럼 게이지에 [nominalGain]을 더한다 — 100을 넘기면 그때마다
  /// [AffectionData.unlockedLevel]을 1씩 올리고 초과분을 다음 레벨
  /// 게이지로 이월한다(한 번의 큰 값으로 여러 레벨이 연속으로 오를 수도
  /// 있다 — 이월 중 손실되는 퍼센트는 없다). 이미 [maxLevel]이면 게이지를
  /// 100에 고정하고 아무것도 반영하지 않는다.
  ///
  /// 리턴값은 "실제로 게이지에 반영된 양"이다 — 정상 상황에서는
  /// [nominalGain]과 같지만, 이미 만렙이거나 [nominalGain]이 0 이하인
  /// (방어적 가드) 경우엔 0을 돌려줘서 호출부가 거짓으로 "+N% 올랐어요"
  /// 안내를 띄우지 않게 한다.
  double _applyGain(AffectionData data, double nominalGain) {
    if (nominalGain <= 0) {
      return 0;
    }
    if (data.unlockedLevel >= maxLevel) {
      data.currentAffinityPercent = 100;
      return 0;
    }

    double gauge = data.currentAffinityPercent + nominalGain;
    while (gauge >= 100 && data.unlockedLevel < maxLevel) {
      gauge -= 100;
      data.unlockedLevel += 1;
    }
    if (data.unlockedLevel >= maxLevel) {
      gauge = 100;
    }
    data.currentAffinityPercent = gauge.clamp(0, 100).toDouble();

    _saveData();
    notifyListeners();
    return nominalGain;
  }

  static const String _saveKey = 'affection_manager_save';

  /// 직렬 저장 큐 — [_saveData]가 연타 등으로 아주 짧은 간격에 여러 번
  /// 겹쳐 호출되면, 각자 독립적으로 떠 있는 `await`들이 완료되는 순서가
  /// 호출 순서와 뒤바뀔 수 있다(예: 나중에 시작한 저장이 먼저 끝나버려서,
  /// 그 뒤에 끝나는 "오래된 스냅샷" 저장이 최신 상태를 덮어써 디스크에는
  /// 옛 값이 남는 경우). 매 호출을 이 체인 뒤에 이어 붙여서 항상 호출한
  /// 순서 그대로 하나씩 끝나도록 강제한다 — 마지막에 이어붙은 저장이
  /// 결국 가장 최신 상태를 디스크에 남긴다.
  Future<void> _pendingSave = Future<void>.value();

  Future<void> _saveData() {
    final Future<void> next = _pendingSave.then((_) => _writeData());
    _pendingSave = next;
    return next;
  }

  Future<void> _writeData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String json = jsonEncode(
      _data.map((key, value) => MapEntry(key, value.toJson())),
    );
    await prefs.setString(_saveKey, json);
  }

  /// main()이 runApp 전에 반드시 await해야 한다(다른 매니저들과 동일한
  /// 관례 — EquipmentManager.loadEquipment/StoryManager.loadData 등). 예전엔
  /// 이 로드를 생성자에서 fire-and-forget으로 던졌는데, 그러면
  /// [AffectionManager.instance]가 최초로 접근되는 시점(대개 AffectionScreen
  /// 최초 build)과 로드 완료 시점이 경쟁해 "저장된 호감도가 있는데도 처음엔
  /// 0%로 보였다가 아무 터치(=setState)가 있어야 갱신되는" 버그가 있었다
  /// (AffectionScreen이 ChangeNotifier를 구독하지 않고 build 시점 값만
  /// 스냅샷으로 읽기 때문). runApp 이전에 로드가 끝나 있으면 이 문제 자체가
  /// 발생할 수 없다.
  Future<void> loadData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      return;
    }

    try {
      final Map<String, dynamic> decoded = jsonDecode(raw) as Map<String, dynamic>;
      _data.clear();
      decoded.forEach((key, value) {
        final AffectionData data = AffectionData.fromJson(value as Map<String, dynamic>);
        // 로컬 저장 파일이 손상되거나(수동 편집 등) 예전 버전의 규칙으로
        // 저장된 값이 남아 있어도 항상 유효한 범위 안으로 강제한다 — 여기서
        // 클램프해 두면 그 이후의 모든 읽기/쓰기 경로는 항상 정상 범위라고
        // 믿고 써도 된다.
        data.unlockedLevel = data.unlockedLevel.clamp(1, maxLevel);
        data.currentAffinityPercent = data.currentAffinityPercent.clamp(0, 100).toDouble();
        data.chatCountToday = data.chatCountToday.clamp(0, maxChatsPerDay);
        _data[key] = data;
      });
    } catch (error) {
      debugPrint('[AffectionManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
      return;
    }

    notifyListeners();
  }
}
