import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/character_metadata_model.dart';
import 'supabase_manager.dart';

/// 캐릭터별 기본 전투 스탯(HP/ATK/DEF/ASPD) + 성장률을 관장하는 싱글턴 —
/// [CharacterMetaManager](공격 타입 하나만 담는 기존 매니저)와 같은 관례
/// (로컬 캐시 우선, Supabase는 부가적인 백업/동기화 계층)를 따르지만,
/// 완전히 별개의 새 테이블(`character_metadata`)을 담당한다.
///
/// [GameManager]가 매 스탯 계산마다 [byId]로 장착 캐릭터의 메타데이터를
/// 조회해 `Equipment.level`/`Equipment.star`와 함께
/// [CharacterMetadata.computeFinalStats]에 넘긴다.
class CharacterMetadataManager {
  CharacterMetadataManager._internal();

  static final CharacterMetadataManager instance = CharacterMetadataManager._internal();

  List<CharacterMetadata> _entries = const [];

  /// 단위 테스트 전용 — 실제 캐릭터 메타데이터를 네트워크 없이 직접
  /// 주입한다([CharacterMetaManager.debugSeedForTest]와 같은 관례).
  @visibleForTesting
  void debugSeedForTest(List<CharacterMetadata> entries) {
    _entries = entries;
  }

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 채운 뒤 원격
  /// 테이블을 받아와 갱신을 시도한다. [GameManager.attackPower] 등
  /// 전투 스탯 계산이 곧바로 [byId]를 읽으므로, 전투 화면이 뜨기 전에
  /// 끝나 있어야 한다(main.dart의 다른 로드 호출과 같은 제약).
  Future<void> loadData() async {
    await _loadLocal();

    final List<Map<String, dynamic>> rows =
        await SupabaseManager.instance.fetchCharacterMetadata();
    if (rows.isEmpty) {
      debugPrint(
        '[CharacterMetadataManager] 캐릭터 기본 스탯 데이터가 비어 있습니다(character_metadata '
        '테이블/RLS 정책을 확인하세요). 기존 캐시(${_entries.length}건)를 유지합니다.',
      );
    } else {
      final List<CharacterMetadata> parsed = [];
      for (final Map<String, dynamic> row in rows) {
        try {
          parsed.add(CharacterMetadata.fromJson(row));
        } catch (error) {
          debugPrint(
            '[CharacterMetadataManager] 캐릭터 기본 스탯 행 파싱 실패'
            '(character_id=${row['character_id']}): $error',
          );
        }
      }
      if (parsed.isNotEmpty) {
        _entries = parsed;
      } else {
        debugPrint(
          '[CharacterMetadataManager] 파싱 가능한 캐릭터 기본 스탯 데이터가 하나도 없습니다 — '
          '컬럼명/타입을 확인하세요.',
        );
      }
    }

    await _saveLocal();
  }

  /// [characterId](Equipment.gradeBadgeLabel, 예: 'N1')의 기본 스탯/성장률
  /// — 테이블에 아직 없는 캐릭터거나(신규 추가 캐릭터, 마이그레이션 전
  /// 등) 로드 전이면 null을 반환한다. 호출부(GameManager/UI)는 null일 때
  /// [CharacterFinalStats.zero]로 안전하게 대체해야 한다.
  CharacterMetadata? byId(String characterId) {
    for (final CharacterMetadata metadata in _entries) {
      if (metadata.characterId == characterId) {
        return metadata;
      }
    }
    return null;
  }

  static const String _saveKey = 'character_metadata_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode(_entries.map((entry) => entry.toCacheJson()).toList()),
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
      _entries = decoded
          .map((entry) => CharacterMetadata.fromJson(entry as Map<String, dynamic>))
          .toList();
    } catch (error) {
      debugPrint('[CharacterMetadataManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }
  }
}
