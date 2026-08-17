import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/equipment.dart' show ItemGrade;
import '../models/pet_stat_metadata_model.dart';
import 'supabase_manager.dart';

/// 펫 특수 스탯(골드 획득/드랍률/보스 데미지/최종 공격력 증폭/스킬 쿨감/
/// 크리티컬 데미지)의 등급별 값 범위(`pet_stat_metadata` 테이블)를 관장하는
/// 싱글턴 — [TowerFloorManager]/[CharacterMetaManager]와 같은 관례(로컬
/// 캐시 우선, Supabase는 참조 데이터 원본). 값 자체를 코드에 하드코딩하지
/// 않고 서버에서 실시간으로 밸런스를 조정할 수 있게 하는 것이 목적이다.
///
/// [EquipmentManager.generateLootOfType]이 `EquipType.pet`을 생성할 때마다
/// [rollSpecialStats]를 호출해 이 캐시에서 값을 뽑아 [Equipment.specialStats]
/// 를 채운다.
class PetStatMetadataManager {
  PetStatMetadataManager._internal();

  static final PetStatMetadataManager instance = PetStatMetadataManager._internal();

  List<PetStatMetadata> _entries = const [];

  final Random _random = Random();

  /// 단위 테스트 전용 — 실제 메타데이터를 네트워크 없이 직접 주입한다
  /// ([TowerFloorManager.debugSeedForTest]와 같은 관례).
  @visibleForTesting
  void debugSeedForTest(List<PetStatMetadata> entries) {
    _entries = entries;
  }

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 채운 뒤 원격
  /// 테이블을 받아와 갱신을 시도한다.
  Future<void> loadData() async {
    await _loadLocal();

    final List<Map<String, dynamic>> rows = await SupabaseManager.instance.fetchPetStatMetadata();
    if (rows.isEmpty) {
      debugPrint(
        '[PetStatMetadataManager] 펫 스탯 메타데이터가 비어 있습니다(pet_stat_metadata 테이블/RLS '
        '정책을 확인하세요). 기존 캐시(${_entries.length}건)를 유지합니다.',
      );
    } else {
      final List<PetStatMetadata> parsed = [];
      for (final Map<String, dynamic> row in rows) {
        try {
          parsed.add(PetStatMetadata.fromJson(row));
        } catch (error) {
          debugPrint('[PetStatMetadataManager] 행 파싱 실패(stat_key=${row['stat_key']}): $error');
        }
      }
      if (parsed.isNotEmpty) {
        _entries = parsed;
      } else {
        debugPrint('[PetStatMetadataManager] 파싱 가능한 메타데이터가 하나도 없습니다 — 컬럼명/타입을 확인하세요.');
      }
    }

    await _saveLocal();
  }

  /// [grade]에 해당하는 모든 (스탯 키, 등급) 조합에 대해 [min_value, max_value]
  /// 범위 안에서 값을 하나씩 뽑아 [Equipment.specialStats]로 바로 쓸 수 있는
  /// 맵을 만든다 — 이 등급에 등록된 메타데이터가 없는 스탯 키는 조용히
  /// 건너뛴다(아직 밸런스 데이터가 없는 등급이라도 가챠 자체는 안전하게
  /// 계속 동작해야 하므로, [ItemPoolConfig.maxCount]가 0인 조합을 건너뛰는
  /// 것과 같은 관례). 순수 함수가 아니라(`_random` 사용) 단위 테스트에서는
  /// [debugSeedForTest]로 메타데이터를 고정한 뒤 결과 범위만 검증한다.
  Map<String, double> rollSpecialStats(ItemGrade grade) {
    final Map<String, double> result = {};
    for (final PetStatMetadata entry in _entries) {
      if (entry.grade != grade) {
        continue;
      }
      final double min = entry.minValue;
      final double max = entry.maxValue;
      final double value = max <= min ? min : min + _random.nextDouble() * (max - min);
      result[entry.statKey] = double.parse(value.toStringAsFixed(4));
    }
    return result;
  }

  static const String _saveKey = 'pet_stat_metadata_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode([
        for (final PetStatMetadata entry in _entries)
          {
            'stat_key': entry.statKey,
            'grade': entry.grade.name,
            'min_value': entry.minValue,
            'max_value': entry.maxValue,
          },
      ]),
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
          .map((entry) => PetStatMetadata.fromJson(entry as Map<String, dynamic>))
          .toList();
    } catch (error) {
      debugPrint('[PetStatMetadataManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }
  }
}
