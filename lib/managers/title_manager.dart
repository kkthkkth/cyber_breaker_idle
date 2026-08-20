import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/title_model.dart';
import 'achievement_manager.dart';
import 'game_manager.dart';
import 'prestige_manager.dart';
import 'supabase_manager.dart';

/// 칭호(PlayerTitle) 수집/장착을 관장하는 싱글턴 — [PetStatMetadataManager]와
/// 같은 관례(카탈로그는 로그인 여부와 무관한 공개 참조 데이터, 로컬 캐시
/// 우선)를 따르되, 이 매니저는 그 위에 "보유 목록"(`user_titles`)과
/// "장착 중인 칭호 하나"(`profiles.equipped_title`)까지 함께 관리한다.
///
/// [checkAndGrantTitles]는 [GameManager._onMonsterDefeated]/
/// [EquipmentManager.drawMultipleGacha]/[PrestigeManager.prestige]처럼
/// 조건 진행도가 실제로 바뀌는 지점에서만 명시적으로 호출된다 —
/// [GameManager]를 통째로 구독(addListener)하면 전투 중 매 프레임 가까운
/// 빈도로 알림이 오는데, 그때마다 카탈로그 전체를 순회하는 건 낭비이자
/// 불필요한 성능 부담이라 피했다.
class TitleManager extends ChangeNotifier {
  TitleManager._internal();

  static final TitleManager instance = TitleManager._internal();

  List<PlayerTitle> catalog = const [];
  final Set<String> ownedTitleIds = {};
  String? equippedTitleId;

  Map<String, PlayerTitle> get _catalogById => {for (final PlayerTitle title in catalog) title.id: title};

  PlayerTitle? get equippedTitle =>
      equippedTitleId == null ? null : _catalogById[equippedTitleId];

  List<PlayerTitle> get ownedTitles => [
    for (final String id in ownedTitleIds)
      if (_catalogById[id] case final PlayerTitle title) title,
  ];

  bool isOwned(String titleId) => ownedTitleIds.contains(titleId);

  /// [TitleScreen]/[home_screen]이 새로 칭호를 획득한 순간 토스트를
  /// 띄우기 위한 콜백 — main()이 부팅 시 등록해 둘 필요는 없다(놓쳐도
  /// [TitleScreen]에 들어가면 이미 보유 목록에 반영돼 있다).
  void Function(PlayerTitle title)? onTitleGranted;

  /// [buffType]이 지금 장착 중인 칭호와 일치할 때만 그 칭호의
  /// [PlayerTitle.buffValue]를 돌려준다 — 유물/장비 세트처럼 여러 개를 합산하는
  /// 구조가 아니라 "한 번에 하나만 장착"이라 단순 조건부 반환이면 충분하다.
  double bonusFor(String buffType) {
    final PlayerTitle? title = equippedTitle;
    if (title == null || title.buffType != buffType) {
      return 0;
    }
    return title.buffValue;
  }

  /// 단위 테스트 전용 — 실제 상태를 네트워크 없이 직접 주입한다
  /// ([PotionManager.debugSeedForTest]와 같은 관례).
  @visibleForTesting
  void debugSeedForTest({
    List<PlayerTitle>? catalog,
    Set<String>? ownedTitleIds,
    String? equippedTitleId,
  }) {
    if (catalog != null) {
      this.catalog = catalog;
    }
    if (ownedTitleIds != null) {
      this.ownedTitleIds
        ..clear()
        ..addAll(ownedTitleIds);
    }
    if (equippedTitleId != null) {
      this.equippedTitleId = equippedTitleId;
    }
  }

  /// [conditionType]에 맞는 "현재 진행도" — 전부 이미 다른 시스템이
  /// 추적 중인 값을 그대로 읽는다(칭호 전용 카운터를 새로 두지 않는다).
  double _progressFor(String conditionType) => switch (conditionType) {
    TitleConditionType.monsterKillCount => AchievementManager.instance.totalMonsterKills.toDouble(),
    TitleConditionType.highestChapter => GameManager.instance.highestReachedChapter.toDouble(),
    TitleConditionType.gachaCount => AchievementManager.instance.totalGachaPulls.toDouble(),
    TitleConditionType.prestigeCount => PrestigeManager.instance.prestigeCount.toDouble(),
    _ => 0,
  };

  /// 아직 보유하지 않은 칭호 중 조건을 만족한 것을 전부 획득 처리한다 —
  /// 조건 진행도가 바뀌는 호출부(몬스터 처치/가챠/환생)가 그때마다
  /// 부른다. 여러 칭호가 동시에 조건을 만족해도 한 번에 다 처리된다.
  void checkAndGrantTitles() {
    bool changed = false;
    for (final PlayerTitle title in catalog) {
      if (ownedTitleIds.contains(title.id)) {
        continue;
      }
      if (_progressFor(title.conditionType) >= title.conditionGoal) {
        ownedTitleIds.add(title.id);
        changed = true;
        unawaited(SupabaseManager.instance.grantTitle(title.id));
        onTitleGranted?.call(title);
      }
    }
    if (!changed) {
      return;
    }
    notifyListeners();
    unawaited(_saveLocal());
  }

  /// 보유 중인 [titleId]를 장착한다 — 보유하지 않았으면 false.
  Future<bool> equip(String titleId) async {
    if (!ownedTitleIds.contains(titleId)) {
      return false;
    }
    equippedTitleId = titleId;
    notifyListeners();
    await _saveLocal();
    unawaited(SupabaseManager.instance.updateEquippedTitle(titleId));
    return true;
  }

  /// 장착 중인 칭호를 해제한다.
  Future<void> unequip() async {
    equippedTitleId = null;
    notifyListeners();
    await _saveLocal();
    unawaited(SupabaseManager.instance.updateEquippedTitle(null));
  }

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 채운 뒤 서버에서
  /// 카탈로그/보유 목록/장착 칭호를 다시 확인한다. 병합이 끝난 뒤 곧바로
  /// [checkAndGrantTitles]를 한 번 돌려, 마지막 세션 이후 조건을 만족한
  /// 칭호가 있으면(예: 오프라인 중 서버 값만 갱신된 경우) 놓치지 않는다.
  Future<void> loadData() async {
    await _loadLocal();

    final List<Map<String, dynamic>> catalogRows =
        await SupabaseManager.instance.fetchTitleCatalog();
    if (catalogRows.isNotEmpty) {
      catalog = catalogRows.map(PlayerTitle.fromJson).toList();
    }

    final List<String> owned = await SupabaseManager.instance.fetchOwnedTitleIds();
    if (owned.isNotEmpty) {
      ownedTitleIds.addAll(owned);
    }

    final String? remoteEquipped = await SupabaseManager.instance.fetchEquippedTitle();
    if (remoteEquipped != null) {
      equippedTitleId = remoteEquipped;
    }

    await _saveLocal();
    notifyListeners();
    checkAndGrantTitles();
  }

  static const String _saveKey = 'title_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode({
        'ownedTitleIds': ownedTitleIds.toList(),
        'equippedTitleId': equippedTitleId,
      }),
    );
  }

  Future<void> _loadLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      return;
    }
    try {
      final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
      final List<dynamic>? ids = data['ownedTitleIds'] as List<dynamic>?;
      if (ids != null) {
        ownedTitleIds
          ..clear()
          ..addAll(ids.cast<String>());
      }
      equippedTitleId = data['equippedTitleId'] as String?;
    } catch (error) {
      debugPrint('[TitleManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }
  }
}
