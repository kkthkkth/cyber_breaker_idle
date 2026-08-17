import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/asset_paths.dart';
import '../models/equipment.dart';

/// 원격 이미지 레포(`assets/data/characters.json`)에 등록된 캐릭터 ID
/// 목록을 불러와, 등급별로 실제 "몇 번까지 존재하는지"를 알려주는 싱글턴.
///
/// [EncyclopediaManager]가 예전에는 [ItemPoolConfig.maxCharacterCount]에
/// 손으로 박아 둔 등급별 개수만큼만 도감 칸을 만들었다 — 그래서
/// `assets/images/player/UR/UR1/`처럼 GitHub에 새 캐릭터 폴더를 올려도
/// 그 개수를 손으로 늘리고 앱을 재배포하기 전까지는 도감에 나타나지
/// 않았다. 이 매니저는 그 개수를 하드코딩 대신 `characters.json` 파일
/// 하나(원격, 이미지 레포 안에 같이 둠)에서 읽어오므로, 새 캐릭터를 올릴
/// 때 이 JSON 파일에 ID 한 줄만 추가하면(예: `"UR1"`) 앱 코드를 건드리거나
/// 재배포하지 않아도 다음 실행부터 도감에 자동으로 나타난다.
///
/// `characters.json` 형식은 캐릭터 ID의 평평한 배열이다:
/// ```json
/// ["N1", "N2", "N3", "R1", "R2", "SSR1", "UR1"]
/// ```
/// 각 ID는 [Equipment.gradeBadgeLabel]과 같은 형식("{등급}{subId}")이어야
/// 한다 — 이 매니저가 등급 접두어와 끝의 숫자(subId)로 다시 쪼갠다.
class CharacterManifestManager {
  CharacterManifestManager._internal();

  static final CharacterManifestManager instance = CharacterManifestManager._internal();

  static const String _manifestPath = 'assets/data/characters.json';
  static const String _saveKey = 'character_manifest_cache';

  Map<ItemGrade, List<int>> _subIdsByGrade = const {};

  /// [grade] 등급에 실제로 존재하는(매니페스트에 등록된) 캐릭터의 subId
  /// 목록 — 오름차순 정렬. 아직 로드 전이거나 그 등급에 캐릭터가 하나도
  /// 없으면 빈 리스트(도감에 그 등급 칸이 하나도 안 생긴다).
  List<int> subIdsFor(ItemGrade grade) => _subIdsByGrade[grade] ?? const [];

  /// main()이 [EncyclopediaManager.instance]를 처음 건드리기 전에 반드시
  /// await해야 한다 — [EncyclopediaManager]는 생성자에서 즉시 도감 항목을
  /// 만들기 때문에, 이 로드가 끝나기 전에 그 싱글턴이 먼저 초기화되면 빈
  /// 목록으로 굳어버린다.
  ///
  /// 1) 캐시(SharedPreferences)에 이전에 받아 둔 목록이 있으면 먼저 그걸로
  ///    채운다 — 오프라인이어도 지난 실행 때 봤던 캐릭터들은 그대로 도감에
  ///    나온다. 2) 그 다음 원격에서 최신 목록을 받아와 덮어쓴다 — 실패해도
  ///    (오프라인, 아직 파일을 안 올림 등) 캐시된 이전 목록을 그대로 쓰면
  ///    되므로 예외를 조용히 삼킨다(RemoteSpriteLoader와 동일한 방어적
  ///    네트워크 호출 관례).
  Future<void> loadData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? cached = prefs.getString(_saveKey);
    if (cached != null) {
      try {
        _subIdsByGrade = parseManifest(cached);
      } catch (error) {
        debugPrint('[CharacterManifestManager] 로컬 캐시 데이터가 손상되어 건너뜁니다: $error');
      }
    }

    try {
      final http.Response response = await http.get(Uri.parse(AssetPaths.resolve(_manifestPath)));
      if (response.statusCode != 200) {
        debugPrint(
          '[CharacterManifestManager] characters.json 응답 실패: HTTP ${response.statusCode}',
        );
        return;
      }
      _subIdsByGrade = parseManifest(response.body);
      await prefs.setString(_saveKey, response.body);
    } catch (error) {
      debugPrint('[CharacterManifestManager] characters.json 로드 실패: $error');
    }
  }

  static final RegExp _trailingSubId = RegExp(r'(\d+)$');

  /// `characters.json`의 원문(ID 배열 JSON 문자열)을 등급별 subId 목록으로
  /// 파싱한다 — 순수 함수라 네트워크 없이 단위 테스트할 수 있다. 형식이
  /// 안 맞는 개별 ID(끝에 숫자가 없거나, 등급 접두어가 [ItemGrade] 중
  /// 어디에도 안 맞는 경우)는 조용히 건너뛴다 — 파일 하나의 오타 때문에
  /// 전체 도감이 깨지면 안 되기 때문이다.
  @visibleForTesting
  static Map<ItemGrade, List<int>> parseManifest(String raw) {
    final List<dynamic> ids = jsonDecode(raw) as List<dynamic>;
    final Map<ItemGrade, List<int>> grouped = {};

    for (final dynamic rawId in ids) {
      final String characterId = rawId as String;
      final RegExpMatch? match = _trailingSubId.firstMatch(characterId);
      if (match == null) {
        continue;
      }
      final int subId = int.parse(match.group(1)!);
      final String gradeFolder = characterId.substring(0, match.start);
      final ItemGrade? grade = _gradeFromFolder(gradeFolder);
      if (grade == null) {
        continue;
      }
      grouped.putIfAbsent(grade, () => []).add(subId);
    }

    for (final List<int> subIds in grouped.values) {
      subIds.sort();
    }
    return grouped;
  }

  static ItemGrade? _gradeFromFolder(String folder) {
    for (final ItemGrade grade in ItemGrade.values) {
      if (grade.displayName == folder) {
        return grade;
      }
    }
    return null;
  }
}
