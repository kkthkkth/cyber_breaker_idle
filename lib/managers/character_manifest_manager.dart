import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/equipment.dart';
import 'supabase_manager.dart';

/// `master_characters`(Supabase) 한 행을 그대로 옮긴 캐릭터 정의 —
/// [CharacterManifestManager]가 다루는 유일한 데이터 단위. [subId]는
/// [grade] 안에서만 유일하다(예: N1과 R1은 서로 다른 캐릭터지만 둘 다
/// subId=1) — 게임 전역에서 캐릭터 하나를 가리키려면 항상 (grade, subId)
/// 쌍이 필요하다("N1"처럼 둘을 합친 문자열이 [Equipment.gradeBadgeLabel]
/// 형식이자 DB의 `sub_id` 컬럼 값이다).
class CharacterManifestEntry {
  const CharacterManifestEntry({
    required this.grade,
    required this.subId,
    required this.name,
    required this.job,
    required this.gachaWeight,
    this.imagePath,
  });

  final ItemGrade grade;
  final int subId;
  final String name;
  final String job;

  /// 가챠에서 이 캐릭터가 당첨될 상대적 가중치 — 0이면(비활성은 아니지만)
  /// 가챠 풀에서는 완전히 제외된다(도감/컬렉션에는 여전히 노출).
  final int gachaWeight;

  /// 관리자가 기본 ID 기반 에셋 경로([AppImages.playerThumbnail] 등) 대신
  /// 쓰고 싶을 때 채우는 선택적 오버라이드 — 현재는 저장만 하고 실제 렌더링
  /// 경로 결정에는 아직 반영하지 않는다(기존 UI 전역이 ID 기반 명명 규칙에
  /// 강하게 의존하고 있어, 전면 교체는 이번 리팩토링의 범위를 넘는다). 필요
  /// 시 이 필드를 실제로 소비하도록 [AppImages] 쪽을 별도로 확장하면 된다.
  final String? imagePath;
}

/// Supabase `master_characters` 테이블을 읽어, 등급별로 실제 "몇 번까지
/// 존재하는지"와 가챠 당첨 가중치를 알려주는 싱글턴.
///
/// 예전에는 이미지 레포에 동봉된 원격 `characters.json`(캐릭터 ID의 평평한
/// 배열)을 읽었고, 그와 별개로 [EquipmentManager]의 가챠 로직은
/// `ItemPoolConfig.maxCharacterCount`라는 완전히 다른 하드코딩 표를 따로
/// 참조했다 — 두 표가 서로 어긋나면(도감엔 있는데 가챠엔 없거나 그 반대)
/// 아무도 알아채지 못한 채 조용히 깨지는 구조였다. 이제 이 매니저 하나가
/// "실제로 존재하는 캐릭터"의 유일한 출처이고, 도감([EncyclopediaManager])과
/// 가챠([EquipmentManager.generateLootOfType]) 둘 다 여기만 읽는다.
///
/// `is_active = false`인 행은 서버 쿼리 단계에서부터 제외되므로([SupabaseManager
/// .fetchMasterCharacters]) 이 매니저는 애초에 비활성 캐릭터를 알 수조차
/// 없다 — 도감/가챠/컬렉션 전 UI에서 완전히 숨겨진다는 요구사항을 클라이언트
/// 쪽 필터링 실수 가능성 없이 서버에서 보장한다.
class CharacterManifestManager {
  CharacterManifestManager._internal();

  static final CharacterManifestManager instance = CharacterManifestManager._internal();

  static const String _saveKey = 'character_manifest_cache_v2';

  List<CharacterManifestEntry> _entries = const [];

  /// 단위 테스트 전용 — 실제 캐릭터 목록을 네트워크 없이 직접 주입한다
  /// ([MailboxManager.debugSeedForTest]와 같은 관례).
  @visibleForTesting
  void debugSeedForTest(List<CharacterManifestEntry> entries) {
    _entries = entries;
  }

  /// [grade] 등급에 실제로 존재하는(활성 상태인) 캐릭터의 subId 목록 —
  /// 오름차순 정렬. [EncyclopediaManager]가 도감 칸 개수를 정하는 데 쓴다.
  /// 가챠 가중치가 0이라도(=가챠로는 안 나오지만 다른 경로로 얻을 수 있는
  /// 캐릭터라도) 여기엔 포함된다 — "존재 여부"와 "가챠로 뽑히는지"는 서로
  /// 다른 질문이다([hasGachaPoolFor]/[rollGachaSubId] 참고).
  List<int> subIdsFor(ItemGrade grade) {
    final List<int> subIds = _entries
        .where((entry) => entry.grade == grade)
        .map((entry) => entry.subId)
        .toList();
    subIds.sort();
    return subIds;
  }

  /// [grade] 등급 안에 가챠 가중치(> 0)를 가진 캐릭터가 하나라도 있는지 —
  /// [EquipmentManager._pickAvailableGrade]/[_topAvailableGrade]가 "이
  /// 등급을 가챠 후보로 삼을 수 있는지" 판정하는 데 쓴다.
  bool hasGachaPoolFor(ItemGrade grade) =>
      _entries.any((entry) => entry.grade == grade && entry.gachaWeight > 0);

  /// [grade] 등급 안에서 가챠 가중치 기반으로 당첨 subId를 하나 뽑는다 —
  /// 가중치를 가진 캐릭터가 하나도 없으면(설정 누락 등) null(호출부가
  /// [subIdsFor]로 균등 추첨 폴백을 해야 한다).
  int? rollGachaSubId(ItemGrade grade, Random random) {
    final List<CharacterManifestEntry> pool =
        _entries.where((entry) => entry.grade == grade && entry.gachaWeight > 0).toList();
    if (pool.isEmpty) {
      return null;
    }
    final int totalWeight = pool.fold(0, (sum, entry) => sum + entry.gachaWeight);
    int roll = random.nextInt(totalWeight);
    for (final CharacterManifestEntry entry in pool) {
      if (roll < entry.gachaWeight) {
        return entry.subId;
      }
      roll -= entry.gachaWeight;
    }
    return pool.last.subId; // 부동소수점 등으로 도달할 일 없는 최후 방어선.
  }

  /// (grade, subId) 조합의 전체 정의(이름/직업/이미지 경로 등) — 아직
  /// 어디에서도 소비하지 않지만(위 [CharacterManifestEntry] 문서 참고),
  /// 미래의 UI(캐릭터 이름 표시 등)가 필요할 때 바로 쓸 수 있도록 공개해
  /// 둔다.
  CharacterManifestEntry? entryFor(ItemGrade grade, int subId) {
    for (final CharacterManifestEntry entry in _entries) {
      if (entry.grade == grade && entry.subId == subId) {
        return entry;
      }
    }
    return null;
  }

  /// main()이 [EncyclopediaManager.instance]를 처음 건드리기 전에 반드시
  /// await해야 한다 — [EncyclopediaManager]는 생성자에서 즉시 도감 항목을
  /// 만들기 때문에, 이 로드가 끝나기 전에 그 싱글턴이 먼저 초기화되면 빈
  /// 목록으로 굳어버린다.
  ///
  /// 1) 로컬 캐시(SharedPreferences)에 이전에 받아 둔 목록이 있으면 먼저
  ///    그걸로 채운다 — 오프라인이어도 지난 실행 때 봤던 캐릭터들은 그대로
  ///    도감/가챠에 나온다. 2) 그다음 Supabase에서 최신 목록을 받아와
  ///    덮어쓴다. 조회가 실패하거나(오프라인) 빈 결과가 오면(네트워크 실패와
  ///    "정말로 활성 캐릭터가 하나도 없음"을 구분할 수 없으므로) 캐시가 이미
  ///    있는 한 그 캐시를 그대로 유지한다 — 다른 매니저들([MailboxManager]
  ///    등)과 동일한 방어적 관례.
  Future<void> loadData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? cached = prefs.getString(_saveKey);
    if (cached != null) {
      try {
        final List<dynamic> decoded = jsonDecode(cached) as List<dynamic>;
        _entries = parseRows(decoded.cast<Map<String, dynamic>>());
      } catch (error) {
        debugPrint('[CharacterManifestManager] 로컬 캐시 데이터가 손상되어 건너뜁니다: $error');
      }
    }

    final List<Map<String, dynamic>> rows = await SupabaseManager.instance.fetchMasterCharacters();
    if (rows.isEmpty) {
      if (_entries.isEmpty) {
        debugPrint(
          '[CharacterManifestManager] master_characters 조회 결과가 비어 있습니다 '
          '(네트워크 실패 또는 실제로 활성 캐릭터가 없음) — 도감/가챠가 빈 상태로 시작됩니다.',
        );
      }
      return;
    }
    _entries = parseRows(rows);
    await prefs.setString(_saveKey, jsonEncode(rows));
  }

  /// Supabase 행 목록을 [CharacterManifestEntry] 목록으로 파싱한다 — 순수
  /// 함수라 네트워크 없이 단위 테스트할 수 있다. 개별 행이 형식에 안 맞으면
  /// (등급 코드가 [ItemGrade] 중 어디에도 안 맞거나, `sub_id`가 그 등급
  /// 접두어로 시작하지 않는 등) 그 행 하나만 조용히 건너뛴다 — 행 하나의
  /// 오타 때문에 전체 캐릭터 목록이 깨지면 안 되기 때문이다.
  @visibleForTesting
  static List<CharacterManifestEntry> parseRows(List<Map<String, dynamic>> rows) {
    final List<CharacterManifestEntry> result = [];

    for (final Map<String, dynamic> row in rows) {
      // 서버가 이미 `is_active = true`만 내려주지만(SupabaseManager
      // .fetchMasterCharacters), 로컬 캐시에 남아있던 구 데이터 등을 대비해
      // 한 번 더 방어적으로 확인한다.
      if (row['is_active'] == false) {
        continue;
      }

      final String? compositeId = row['sub_id'] as String?;
      final String? rawGradeCode = row['grade'] as String?;
      if (compositeId == null || rawGradeCode == null) {
        continue;
      }

      final String gradeCode = rawGradeCode.toUpperCase();
      final ItemGrade? grade = _gradeFromCode(gradeCode);
      if (grade == null) {
        continue;
      }

      final String normalizedId = compositeId.toUpperCase();
      if (!normalizedId.startsWith(gradeCode)) {
        debugPrint(
          '[CharacterManifestManager] sub_id($compositeId)가 grade($rawGradeCode) 접두어로 '
          '시작하지 않아 건너뜁니다.',
        );
        continue;
      }
      final int? subId = int.tryParse(normalizedId.substring(gradeCode.length));
      if (subId == null) {
        continue;
      }

      result.add(
        CharacterManifestEntry(
          grade: grade,
          subId: subId,
          name: row['name'] as String? ?? compositeId,
          job: row['job'] as String? ?? '',
          gachaWeight: (row['gacha_weight'] as num?)?.toInt() ?? 0,
          imagePath: row['image_path'] as String?,
        ),
      );
    }

    result.sort((a, b) {
      final int gradeCompare = a.grade.index.compareTo(b.grade.index);
      return gradeCompare != 0 ? gradeCompare : a.subId.compareTo(b.subId);
    });
    return result;
  }

  static ItemGrade? _gradeFromCode(String code) {
    for (final ItemGrade grade in ItemGrade.values) {
      if (grade.displayName == code) {
        return grade;
      }
    }
    return null;
  }
}
