import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/character_model.dart';
import 'supabase_manager.dart';

/// 캐릭터별 메타데이터(현재는 근접/원거리 공격 타입 하나뿐)를 관장하는
/// 싱글턴 — [TowerFloorManager]/[MonsterDropTableManager]와 같은 관례(로컬
/// 캐시 우선, Supabase는 부가적인 백업/동기화 계층)를 따른다.
/// [IdleGame._fireProjectile]이 매 공격마다 [attackTypeFor]를 읽어 근접/
/// 원거리를 분기한다 — 예전엔 이 분기가 [CharacterClass](직업)에서
/// 암묵적으로 추론됐지만, 이제 DB(`characters.attack_type`)가 명시적으로
/// 관리한다.
class CharacterMetaManager {
  CharacterMetaManager._internal();

  static final CharacterMetaManager instance = CharacterMetaManager._internal();

  List<CharacterMeta> _characters = const [];

  /// 단위 테스트 전용 — 실제 캐릭터 메타데이터를 네트워크 없이 직접
  /// 주입한다([TowerFloorManager.debugSeedForTest]와 같은 관례).
  @visibleForTesting
  void debugSeedForTest(List<CharacterMeta> characters) {
    _characters = characters;
  }

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 채운 뒤 원격
  /// 테이블을 받아와 갱신을 시도한다.
  Future<void> loadData() async {
    await _loadLocal();

    final List<Map<String, dynamic>> rows = await SupabaseManager.instance.fetchCharacterMeta();
    if (rows.isEmpty) {
      debugPrint(
        '[CharacterMetaManager] 캐릭터 메타데이터가 비어 있습니다(characters 테이블/RLS 정책을 '
        '확인하세요). 기존 캐시(${_characters.length}건)를 유지합니다.',
      );
    } else {
      final List<CharacterMeta> parsed = [];
      for (final Map<String, dynamic> row in rows) {
        try {
          parsed.add(CharacterMeta.fromJson(row));
        } catch (error) {
          debugPrint(
            '[CharacterMetaManager] 캐릭터 메타데이터 행 파싱 실패(character_id=${row['character_id']}): $error',
          );
        }
      }
      if (parsed.isNotEmpty) {
        _characters = parsed;
      } else {
        debugPrint('[CharacterMetaManager] 파싱 가능한 캐릭터 메타데이터가 하나도 없습니다 — 컬럼명/타입을 확인하세요.');
      }
    }

    await _saveLocal();
  }

  /// [characterId](Equipment.gradeBadgeLabel, 예: 'N1')의 공격 타입 —
  /// 테이블에 아직 없는 캐릭터거나(신규 추가 캐릭터, 마이그레이션 전 등)
  /// 로드 전이면 안전하게 [AttackType.melee]로 취급한다.
  AttackType attackTypeFor(String characterId) {
    for (final CharacterMeta meta in _characters) {
      if (meta.characterId == characterId) {
        return meta.attackType;
      }
    }
    return AttackType.melee;
  }

  static const String _saveKey = 'character_meta_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode(_characters.map((character) => character.toCacheJson()).toList()),
    );
  }

  Future<void> _loadLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_saveKey);
    if (raw == null) {
      return;
    }
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      _characters = decoded
          .map((entry) => CharacterMeta.fromJson(entry as Map<String, dynamic>))
          .toList();
    } catch (error) {
      debugPrint('[CharacterMetaManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }
  }
}
