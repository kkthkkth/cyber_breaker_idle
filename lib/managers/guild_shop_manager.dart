import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/guild_shop_model.dart';
import 'consumable_manager.dart';
import 'guild_manager.dart';
import 'supabase_manager.dart';

/// 길드 상점(길드 주화로 구매하는 소모품 카탈로그)을 관장하는 싱글턴 —
/// [PotionManager]와 같은 관례를 따른다: 로컬(SharedPreferences)이 카탈로그
/// 캐시를 들고 있고, Supabase는 그 위에 얹는 부가적인 백업/동기화 계층이다.
/// 재화(길드 주화) 자체는 [GuildManager.guildCoins]가 유일한 신뢰 소스라
/// 여기서는 따로 들고 있지 않는다 — 이 매니저는 "무엇을 파는지"와 "사면
/// 무슨 아이템을 얼마나 주는지"만 책임진다.
class GuildShopManager extends ChangeNotifier {
  GuildShopManager._internal();

  static final GuildShopManager instance = GuildShopManager._internal();

  List<GuildShopItem> _catalog = const [];
  List<GuildShopItem> get catalog => _catalog;

  /// 단위 테스트 전용 — 실제 카탈로그를 네트워크 없이 직접 주입한다
  /// ([PotionManager.debugSeedForTest]와 같은 관례).
  @visibleForTesting
  void debugSeedForTest(List<GuildShopItem> catalog) {
    _catalog = catalog;
  }

  /// [GuildShopScreen]이 열릴 때 호출 — 로컬 캐시로 즉시 채운 뒤 원격
  /// 카탈로그를 받아와 갱신을 시도한다. 전투 스탯과 무관한 화면 전용
  /// 데이터라 main()의 필수 시작 시퀀스에는 포함하지 않고, 이렇게 화면이
  /// 열릴 때 지연 로드한다.
  Future<void> loadData() async {
    await _loadLocal();

    final List<Map<String, dynamic>> rows = await SupabaseManager.instance.fetchGuildShopItems();
    if (rows.isEmpty) {
      debugPrint(
        '[GuildShopManager] 길드 상점 카탈로그가 비어 있습니다(guild_shop_items 테이블/RLS 정책을 확인하세요). '
        '기존 캐시(${_catalog.length}건)를 유지합니다.',
      );
    } else {
      // 행 하나가 깨져도(예: item_type이 ConsumableType에 없는 값) 그 행만
      // 건너뛴다 — PotionManager.loadData()와 같은 방어적 파싱 관례.
      final List<GuildShopItem> parsed = [];
      for (final Map<String, dynamic> row in rows) {
        try {
          parsed.add(GuildShopItem.fromJson(row));
        } catch (error) {
          debugPrint('[GuildShopManager] 길드 상점 상품 파싱 실패(id=${row['id']}): $error');
        }
      }
      if (parsed.isNotEmpty) {
        _catalog = parsed;
      } else {
        debugPrint('[GuildShopManager] 파싱 가능한 길드 상점 상품이 하나도 없습니다 — 컬럼명/타입을 확인하세요.');
      }
    }

    await _saveLocal();
    notifyListeners();
  }

  /// [item]을 구매한다 — [GuildManager.spendGuildCoins]로 먼저 길드 주화를
  /// 차감하고, 성공했을 때만 [ConsumableManager]에 아이템을 지급한다.
  /// 재화가 부족하면 아무것도 바뀌지 않고 false.
  Future<bool> purchase(GuildShopItem item) async {
    final bool spent = GuildManager.instance.spendGuildCoins(item.price);
    if (!spent) {
      return false;
    }
    ConsumableManager.instance.addItem(item.type, item.rewardAmount);
    return true;
  }

  static const String _saveKey = 'guild_shop_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode(_catalog.map((item) => item.toCacheJson()).toList()),
    );
  }

  Future<void> _loadLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      return;
    }
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    _catalog = decoded
        .map((entry) => GuildShopItem.fromJson(entry as Map<String, dynamic>))
        .toList();
  }
}
