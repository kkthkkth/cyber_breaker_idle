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

    // 로컬 캐시도, 방금 받아온 Supabase 메타데이터도 둘 다 비어 있다면
    // `pet_stat_metadata` 테이블이 아직 세팅되지 않은 환경이다 — 이 경우
    // rollSpecialStats가 항상 빈 맵만 돌려줘서, GameManager에 이미 완전히
    // 연동된 펫 패시브 버프(_petSpecialStat)가 실제로는 항상 0으로만
    // 계산돼 눈에 보이지 않는다([ArtifactManager]의 더미 카탈로그 폴백과
    // 같은 이유·같은 조치).
    if (_entries.isEmpty) {
      _entries = _buildDummyMetadata();
    }

    await _saveLocal();
  }

  /// [loadData]의 더미 폴백 — 저등급(N/R)은 원래 특수 스탯을 굴리지 않는
  /// 장르 관례를 따라 제외하고, SR~LR 5개 등급에 [PetSpecialStat]의 8개
  /// 키 전부를 등급이 오를수록 커지는 범위로 채운다. 정확한 밸런스
  /// 데이터가 없어 임의로 정한 값이니, 기획 수치가 정해지면 이 함수만
  /// 지우면 된다(실제 `pet_stat_metadata` 테이블에 행이 생기면 그쪽이
  /// 자동으로 우선한다).
  static List<PetStatMetadata> _buildDummyMetadata() {
    const List<ItemGrade> eligibleGrades = [
      ItemGrade.sr,
      ItemGrade.ssr,
      ItemGrade.sssr,
      ItemGrade.ur,
      ItemGrade.lr,
    ];
    final List<PetStatMetadata> entries = [];
    for (int gradeIndex = 0; gradeIndex < eligibleGrades.length; gradeIndex++) {
      final double tier = gradeIndex + 1;
      for (final String statKey in PetSpecialStat.values) {
        // 스킬 쿨감은 SkillManager._cooldownReduction()에서 [0, 0.9]로
        // 클램프되는 값이라 다른 %보다 절반 스케일로 보수적으로 잡는다.
        final double base = statKey == PetSpecialStat.skillCooldownReduction ? 0.01 : 0.02;
        entries.add(
          PetStatMetadata(
            statKey: statKey,
            grade: eligibleGrades[gradeIndex],
            minValue: base * tier,
            maxValue: base * tier * 1.5,
          ),
        );
      }
    }
    return entries;
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
