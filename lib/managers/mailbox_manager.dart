import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mailbox_item_model.dart';
import 'game_manager.dart';
import 'supabase_manager.dart';

/// 우편함(월드보스 랭킹 보상 등 서버가 발송한 우편)을 관장하는 싱글턴.
///
/// 다른 매니저들과 달리 우편 "내용"은 이 클라이언트가 만드는 게 아니라
/// 전적으로 서버(보상 정산 RPC 등)가 만든다 — 그래서 로컬 캐시는 "빠른
/// 배지 표시"용 스냅샷일 뿐, [refresh]로 서버 목록을 받아올 때마다
/// 통째로 교체된다(다른 매니저들의 "로컬이 유일한 신뢰 소스" 관례와 다른
/// 지점).
class MailboxManager extends ChangeNotifier {
  MailboxManager._internal();

  static final MailboxManager instance = MailboxManager._internal();

  List<MailboxItem> _items = [];

  List<MailboxItem> get items => List.unmodifiable(_items);

  bool get hasUnclaimedMail => _items.any((item) => !item.isClaimed);

  /// 단위 테스트 전용 — 실제 우편함 목록을 네트워크 없이 직접 주입한다
  /// ([PotionManager.debugSeedForTest]와 같은 관례). [claim]/[claimAll]이
  /// 인덱스로 직접 대입([_items]`[index] = ...`)하므로 항상 growable한
  /// 복사본으로 저장한다 — 호출부가 `const [...]` 리스트를 넘기면(흔한
  /// 테스트 습관) 그 자리에서 unmodifiable 리스트를 그대로 들고 있다가
  /// 나중에 claim 시점에야 크래시 나는 일을 막는다. 저장/서버 동기화는
  /// 건드리지 않는다.
  @visibleForTesting
  void debugSeedForTest({required List<MailboxItem> items}) {
    _items = List<MailboxItem>.from(items);
  }

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 배지를 채운 뒤
  /// [refresh]로 최신 목록을 받아온다.
  Future<void> loadData() async {
    await _loadLocal();
    await refresh();
  }

  /// 서버에서 최신 우편함 전체를 다시 받아온다 — [MailboxScreen]이 열릴
  /// 때마다 호출해, 그 사이 새로 도착한 우편(월드보스 보상 정산 등)을
  /// 놓치지 않는다.
  Future<void> refresh() async {
    final List<Map<String, dynamic>> rows = await SupabaseManager.instance.fetchMailbox();
    if (rows.isEmpty && _items.isNotEmpty) {
      // 오프라인 등으로 조회가 실패해도 SupabaseManager는 빈 리스트를
      // 돌려주는 관례라(예외를 삼킴), "정말로 우편이 하나도 없어진 것"과
      // 구분할 수 없다 — 로컬 캐시가 있다면 섣불리 지우지 않고 유지해
      // 배지가 이유 없이 사라지는 것을 막는다.
      return;
    }
    _items = rows.map(MailboxItem.fromJson).toList();
    notifyListeners();
    await _saveLocal();
  }

  /// 우편 1통을 수령한다 — 재화를 [GameManager]에 즉시 반영하고, 로컬
  /// 상태를 수령 완료로 바꾼 뒤 서버에도 반영을 시도한다. 이미 없는/이미
  /// 수령한 우편이면 false(아무것도 바꾸지 않음).
  Future<bool> claim(String mailId) async {
    final int index = _items.indexWhere((item) => item.id == mailId);
    if (index == -1 || _items[index].isClaimed) {
      return false;
    }

    final MailboxItem item = _items[index];
    _applyReward(item);
    _items[index] = item.copyAsClaimed();
    notifyListeners();
    await _saveLocal();
    unawaited(SupabaseManager.instance.claimMail(mailId));
    return true;
  }

  /// 아직 안 받은 우편을 전부 한 번에 수령한다 — 실제로 수령된 통수를
  /// 돌려준다(0이면 받을 게 없었다는 뜻).
  Future<int> claimAll() async {
    final List<MailboxItem> unclaimed = _items.where((item) => !item.isClaimed).toList();
    if (unclaimed.isEmpty) {
      return 0;
    }

    for (final MailboxItem item in unclaimed) {
      _applyReward(item);
    }
    _items = _items.map((item) => item.isClaimed ? item : item.copyAsClaimed()).toList();
    notifyListeners();
    await _saveLocal();
    unawaited(
      SupabaseManager.instance.claimMailBulk(unclaimed.map((item) => item.id).toList()),
    );
    return unclaimed.length;
  }

  void _applyReward(MailboxItem item) {
    switch (item.rewardType) {
      case 'gem':
        GameManager.instance.addGems(item.rewardAmount);
      case 'gold':
      case 'coin':
        GameManager.instance.addGold(item.rewardAmount);
      default:
        // 아직 정의되지 않은 재화 타입 — 신규 타입이 추가되면 이 분기만
        // 늘리면 된다. 조용히 무시하되 로그는 남긴다.
        debugPrint('[MailboxManager] 알 수 없는 보상 타입: ${item.rewardType}');
    }
  }

  static const String _saveKey = 'mailbox_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode(_items.map((item) => item.toCacheJson()).toList()),
    );
  }

  Future<void> _loadLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      return;
    }
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    _items = decoded
        .map((dynamic entry) => MailboxItem.fromJson(entry as Map<String, dynamic>))
        .toList();
  }
}
