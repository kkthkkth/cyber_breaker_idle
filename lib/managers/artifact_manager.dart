import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/artifact_model.dart';
import 'game_manager.dart';
import 'supabase_manager.dart';

/// 보석 가챠로 조각을 모아 레벨업하는 "유물" 시스템을 관장하는 싱글턴.
/// [PetStatMetadataManager]와 같은 관례(카탈로그는 로그인 여부와 무관한
/// 공개 참조 데이터, 로컬 캐시 우선)를 따르되, 펫과 달리 "장착" 개념이
/// 없다 — 레벨 1 이상인(=[Artifact.level] > 0) 유물은 전부 동시에 항상
/// 패시브를 제공한다([totalBonus], [GameManager]가 공격력/방어력/최대체력/
/// 골드 획득/드랍률 계산에 반영한다).
class ArtifactManager extends ChangeNotifier {
  ArtifactManager._internal();

  static final ArtifactManager instance = ArtifactManager._internal();

  /// 유물 가챠 1회 비용 — 다른 프리미엄(보석) 가챠와 같은 가격
  /// ([GachaManager.singlePullCost]와 같은 상수를 여기서 다시 정의하지
  /// 않고 직접 100으로 고정한 이유: 유물 매니저가 상점 UI의 GachaManager
  /// 의존을 새로 만들 필요가 없어서다 — 값 자체는 동일하게 유지).
  static const int pullCost = 100;

  /// 1회 뽑기당 얻는 조각 수(1~3, 무작위) — 등급 개념이 없는 유물이라
  /// 뽑을 때마다 카탈로그 중 하나가 무작위로 골라지고, 그 유물의 조각만
  /// 늘어난다.
  static const int _minFragmentsPerPull = 1;
  static const int _maxFragmentsPerPull = 3;

  final Random _random = Random();

  List<Artifact> _artifacts = const [];
  List<Artifact> get artifacts => _artifacts;

  /// [statKey]를 가진 모든 유물의 [Artifact.passiveValue] 합계 — 레벨 0
  /// (조각만 있고 아직 레벨업 전)인 유물은 passiveValue가 0이라 자동으로
  /// 제외된다. [GameManager]가 공격력/방어력/최대체력/골드 획득/드랍률
  /// 계산마다 호출한다.
  double totalBonus(String statKey) => _artifacts
      .where((artifact) => artifact.statKey == statKey)
      .fold(0.0, (sum, artifact) => sum + artifact.passiveValue);

  /// 단위 테스트 전용 — 실제 카탈로그/진행도를 네트워크 없이 직접
  /// 주입한다([PetStatMetadataManager.debugSeedForTest]와 같은 관례).
  @visibleForTesting
  void debugSeedForTest(List<Artifact> artifacts) {
    _artifacts = artifacts;
  }

  /// 유물 가챠 1회 — 보석이 부족하면 아무것도 바꾸지 않고 null. 성공하면
  /// 무작위로 고른 유물의 조각을 1~3개 늘리고, 갱신된 [Artifact]를
  /// 돌려준다(호출부가 결과 팝업에 "OO 조각 +N" 형태로 보여줄 수 있게).
  Artifact? rollArtifact() {
    if (_artifacts.isEmpty) {
      return null;
    }
    if (!GameManager.instance.spendGems(pullCost)) {
      return null;
    }

    final int index = _random.nextInt(_artifacts.length);
    final int fragmentsGained =
        _minFragmentsPerPull + _random.nextInt(_maxFragmentsPerPull - _minFragmentsPerPull + 1);
    final Artifact updated = _artifacts[index].copyWith(
      fragmentCount: _artifacts[index].fragmentCount + fragmentsGained,
    );
    _artifacts[index] = updated;

    notifyListeners();
    unawaited(_saveLocal());
    unawaited(
      SupabaseManager.instance.syncUserArtifact(
        artifactId: updated.id,
        level: updated.level,
        fragmentCount: updated.fragmentCount,
      ),
    );
    return updated;
  }

  /// [times]번 연속 뽑기 — 도중에 보석이 떨어지면 그 시점까지의 결과만
  /// 돌려준다(전부 성공하지 못했다고 예외를 던지지 않는다).
  List<Artifact> drawMultiple(int times) {
    final List<Artifact> results = [];
    for (int i = 0; i < times; i++) {
      final Artifact? result = rollArtifact();
      if (result == null) {
        break;
      }
      results.add(result);
    }
    return results;
  }

  /// [artifactId] 유물을 한 단계 레벨업한다 — 조각이 부족하거나 이미
  /// 만렙이면 아무것도 바꾸지 않고 false.
  bool levelUp(String artifactId) {
    final int index = _artifacts.indexWhere((artifact) => artifact.id == artifactId);
    if (index == -1) {
      return false;
    }
    final Artifact artifact = _artifacts[index];
    if (!artifact.canLevelUp) {
      return false;
    }

    final Artifact updated = artifact.copyWith(
      level: artifact.level + 1,
      fragmentCount: artifact.fragmentCount - artifact.nextLevelFragmentCost,
    );
    _artifacts[index] = updated;

    notifyListeners();
    unawaited(_saveLocal());
    unawaited(
      SupabaseManager.instance.syncUserArtifact(
        artifactId: updated.id,
        level: updated.level,
        fragmentCount: updated.fragmentCount,
      ),
    );
    return true;
  }

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 채운 뒤, 카탈로그와
  /// 유저 진행도를 원격에서 받아와 병합한다.
  Future<void> loadData() async {
    await _loadLocal();

    final List<Map<String, dynamic>> catalogRows =
        await SupabaseManager.instance.fetchArtifactCatalog();
    if (catalogRows.isEmpty) {
      debugPrint(
        '[ArtifactManager] 유물 카탈로그가 비어 있습니다(artifacts 테이블/RLS 정책을 확인하세요). '
        '기존 캐시(${_artifacts.length}건)를 유지합니다.',
      );
    } else {
      final List<Artifact> catalog = [];
      for (final Map<String, dynamic> row in catalogRows) {
        try {
          catalog.add(Artifact.fromCatalogJson(row));
        } catch (error) {
          debugPrint('[ArtifactManager] 카탈로그 행 파싱 실패(id=${row['id']}): $error');
        }
      }
      if (catalog.isNotEmpty) {
        // 로컬에 이미 있던 레벨/조각 진행도를 새 카탈로그 정의 위로
        // 그대로 이식한다(id로 매칭) — 카탈로그 자체(이름/스탯/성장치)는
        // 항상 서버 최신본을 신뢰하고, 진행도는 아래에서 서버와 다시
        // 한 번 병합한다.
        final Map<String, Artifact> existingById = {
          for (final Artifact artifact in _artifacts) artifact.id: artifact,
        };
        _artifacts = catalog.map((definition) {
          final Artifact? existing = existingById[definition.id];
          return existing == null
              ? definition
              : definition.copyWith(level: existing.level, fragmentCount: existing.fragmentCount);
        }).toList();
      }
    }

    final List<Map<String, dynamic>> progressRows =
        await SupabaseManager.instance.fetchUserArtifacts();
    for (final Map<String, dynamic> row in progressRows) {
      final String? artifactId = row['artifact_id'] as String?;
      if (artifactId == null) {
        continue;
      }
      final int index = _artifacts.indexWhere((artifact) => artifact.id == artifactId);
      if (index == -1) {
        // 카탈로그에 더 이상 없는(삭제/개편된) 유물의 예전 진행도 —
        // 안전하게 무시한다.
        continue;
      }
      final int remoteLevel = (row['level'] as num?)?.toInt() ?? 0;
      final int remoteFragments = (row['fragment_count'] as num?)?.toInt() ?? 0;
      final Artifact local = _artifacts[index];
      // 서버가 더 진행돼 있으면(기기 변경/재설치 등) 그쪽을 신뢰한다 —
      // 유저에게 불리한 방향으로 로컬이 뒤처진 값을 덮어쓰지 않는다.
      final bool remoteIsAhead =
          remoteLevel > local.level || (remoteLevel == local.level && remoteFragments > local.fragmentCount);
      if (remoteIsAhead) {
        _artifacts[index] = local.copyWith(level: remoteLevel, fragmentCount: remoteFragments);
      }
    }

    await _saveLocal();
    notifyListeners();
  }

  static const String _saveKey = 'artifact_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode([
        for (final Artifact artifact in _artifacts)
          {
            'id': artifact.id,
            'name': artifact.name,
            'stat_key': artifact.statKey,
            'value_per_level': artifact.valuePerLevel,
            'max_level': artifact.maxLevel,
            'level': artifact.level,
            'fragment_count': artifact.fragmentCount,
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
      _artifacts = decoded.map((entry) {
        final Map<String, dynamic> map = entry as Map<String, dynamic>;
        return Artifact(
          id: map['id'] as String,
          name: map['name'] as String,
          statKey: map['stat_key'] as String,
          valuePerLevel: (map['value_per_level'] as num).toDouble(),
          maxLevel: (map['max_level'] as num?)?.toInt() ?? 20,
          level: (map['level'] as num?)?.toInt() ?? 0,
          fragmentCount: (map['fragment_count'] as num?)?.toInt() ?? 0,
        );
      }).toList();
    } catch (error) {
      debugPrint('[ArtifactManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }
  }
}
