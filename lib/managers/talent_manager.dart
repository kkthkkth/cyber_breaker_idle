import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/talent_model.dart';
import 'supabase_manager.dart';

/// 특성(별자리) 트리를 관장하는 싱글턴 — [SkillManager.skillTree]와 같은
/// 관례로 노드 카탈로그(id/이름/설명/최대 레벨/선행 조건/버프)는 하드코딩
/// 트리이고([_defaultTalentTree]), 유저별 진행도(레벨/보유 포인트)만
/// SharedPreferences(1차 신뢰 소스) + Supabase(`profiles.talent_points`,
/// `user_talents` 테이블, 백업/동기화 계층)로 관리한다.
///
/// 포인트는 환생([PrestigeManager.prestige])할 때마다 지급되고, 노드에
/// 투자하면 [GameManager]가 읽는 영구 스탯([totalBonus])으로 곧장
/// 반영된다 — 유물/도감/룬 등 이 프로젝트의 다른 모든 영구 패시브 소스와
/// 같은 "여러 출처가 함께 쌓인다" 관례를 따른다.
class TalentManager extends ChangeNotifier {
  TalentManager._internal();

  static final TalentManager instance = TalentManager._internal();

  int talentPoints = 0;

  List<TalentNode> nodes = _defaultTalentTree();

  TalentNode? findById(String id) {
    for (final TalentNode node in nodes) {
      if (node.id == id) {
        return node;
      }
    }
    return null;
  }

  /// [buffType]을 가진 모든 노드의 [TalentNode.passiveValue] 합계 — 레벨
  /// 0(아직 한 번도 투자 안 함)인 노드는 passiveValue가 0이라 자동으로
  /// 제외된다. [GameManager]가 공격력/골드 획득/크리티컬/방어력 계산마다
  /// 호출한다.
  double totalBonus(String buffType) => nodes
      .where((node) => node.buffType == buffType)
      .fold(0.0, (sum, node) => sum + node.passiveValue);

  /// [node]가 요구하는 선행 노드 조건을 전부 만족하는지 — 빈 리스트면
  /// (루트 노드) 항상 true.
  bool prerequisitesMet(TalentNode node) {
    for (final String prereqId in node.prerequisiteNodeIds) {
      final TalentNode? prereq = findById(prereqId);
      if (prereq == null || prereq.currentLevel < node.requiredPrerequisiteLevel) {
        return false;
      }
    }
    return true;
  }

  /// [node]가 지금 잠겨 있는지(=선행 조건 미달성) — 화면이 자물쇠/흑백
  /// 처리를 판단할 때 쓴다. 이미 레벨이 있는 노드는 선행 조건을 이미
  /// 만족했던 것이므로 항상 false(선행 노드를 나중에 초기화하는 기능이
  /// 없어 역전될 일이 없다).
  bool isLocked(TalentNode node) => node.currentLevel <= 0 && !prerequisitesMet(node);

  /// [node]를 한 단계 레벨업할 수 있는지 — 1) 잠겨 있지 않고, 2) 아직
  /// 만렙이 아니고, 3) 포인트가 충분해야 한다.
  bool canLevelUp(TalentNode node) =>
      !isLocked(node) && !node.isMaxLevel && talentPoints >= node.pointCostPerLevel;

  /// [nodeId] 노드를 한 단계 레벨업한다 — 조건 미충족 시 아무것도 바꾸지
  /// 않고 false. 성공하면 포인트를 차감하고, 로컬 저장 + Supabase 동기화
  /// (포인트/노드 레벨 둘 다)를 fire-and-forget으로 던진다.
  bool levelUp(String nodeId) {
    final int index = nodes.indexWhere((node) => node.id == nodeId);
    if (index == -1) {
      return false;
    }
    final TalentNode node = nodes[index];
    if (!canLevelUp(node)) {
      return false;
    }

    talentPoints -= node.pointCostPerLevel;
    final TalentNode updated = node.copyWith(currentLevel: node.currentLevel + 1);
    nodes[index] = updated;

    notifyListeners();
    unawaited(_saveLocal());
    unawaited(SupabaseManager.instance.updateTalentPoints(talentPoints));
    unawaited(
      SupabaseManager.instance.syncUserTalent(nodeId: updated.id, level: updated.currentLevel),
    );
    return true;
  }

  /// [PrestigeManager.prestige]가 환생에 성공할 때마다 호출 — 특성
  /// 포인트를 지급한다. 정확한 밸런스 데이터가 없어 환생 1회당 고정
  /// [pointsPerPrestige]개로 임의로 정했으니, 기획 수치가 정해지면 이
  /// 상수만 바꾸면 된다.
  static const int pointsPerPrestige = 3;

  void grantTalentPoints([int amount = pointsPerPrestige]) {
    if (amount <= 0) {
      return;
    }
    talentPoints += amount;
    notifyListeners();
    unawaited(_saveLocal());
    unawaited(SupabaseManager.instance.updateTalentPoints(talentPoints));
  }

  /// 단위 테스트 전용 — 실제 노드/포인트를 네트워크 없이 직접 주입한다
  /// ([ArtifactManager.debugSeedForTest]와 같은 관례).
  @visibleForTesting
  void debugSeedForTest({List<TalentNode>? nodes, int? talentPoints}) {
    if (nodes != null) {
      this.nodes = nodes;
    }
    if (talentPoints != null) {
      this.talentPoints = talentPoints;
    }
  }

  static const String _saveKey = 'talent_manager_save';

  Future<void> _saveLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _saveKey,
      jsonEncode({
        'talentPoints': talentPoints,
        'nodeLevels': {for (final TalentNode node in nodes) node.id: node.currentLevel},
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
      talentPoints = (data['talentPoints'] as num?)?.toInt() ?? talentPoints;
      final Map<String, dynamic>? levels = data['nodeLevels'] as Map<String, dynamic>?;
      if (levels != null) {
        for (int i = 0; i < nodes.length; i++) {
          final int? level = (levels[nodes[i].id] as num?)?.toInt();
          if (level != null) {
            nodes[i] = nodes[i].copyWith(currentLevel: level);
          }
        }
      }
    } catch (error) {
      debugPrint('[TalentManager] 로컬 저장 데이터가 손상되어 건너뜁니다: $error');
    }
  }

  /// main()이 앱 시작 시 한 번 호출 — 로컬 캐시로 즉시 채운 뒤, 서버 값이
  /// 더 크면(기기 변경/재설치로 로컬이 비어 있는 경우 등) 그쪽으로 갱신한다
  /// ([PrestigeManager.loadData]와 같은 "remote-ahead-wins" 관례).
  Future<void> loadData() async {
    await _loadLocal();

    final int? remotePoints = await SupabaseManager.instance.fetchTalentPoints();
    if (remotePoints != null && remotePoints > talentPoints) {
      talentPoints = remotePoints;
    }

    final List<Map<String, dynamic>> progressRows =
        await SupabaseManager.instance.fetchUserTalents();
    for (final Map<String, dynamic> row in progressRows) {
      final String? nodeId = row['node_id'] as String?;
      if (nodeId == null) {
        continue;
      }
      final int index = nodes.indexWhere((node) => node.id == nodeId);
      if (index == -1) {
        continue;
      }
      final int remoteLevel = (row['level'] as num?)?.toInt() ?? 0;
      if (remoteLevel > nodes[index].currentLevel) {
        nodes[index] = nodes[index].copyWith(currentLevel: remoteLevel);
      }
    }

    await _saveLocal();
    notifyListeners();
  }

  /// 테스트용 하드코딩 트리 4종(요구사항) — [기초 근력](공격력)을 5레벨
  /// 찍어야 [재물 탐구](골드 획득)와 [치명적 일격](크리티컬)이 해금되고,
  /// 그 둘을 각각 3레벨 이상 찍어야 마지막 [불굴의 의지](방어력)가
  /// 해금되는 다이아몬드 형태 — 두 갈래로 갈렸다가 다시 합류하는 모습을
  /// 보여주는 최소 예시다. 정확한 밸런스 데이터가 없어 임의로 정한
  /// 수치이니, 기획 수치가 정해지면 이 함수만 고치면 된다.
  static List<TalentNode> _defaultTalentTree() {
    // 바깥 List는 const가 아니어야 한다 — levelUp()/_loadLocal()이
    // nodes[index] = ...로 직접 대입하므로 growable(가변) 리스트여야
    // 한다(개별 TalentNode 값 자체는 그대로 const로 생성한다).
    return [
      TalentNode(
        id: 'basic_strength',
        name: '기초 근력',
        description: '공격력을 영구적으로 증가시킨다.',
        maxLevel: 5,
        pointCostPerLevel: 1,
        buffType: TalentBuffType.attackPercent,
        buffValuePerLevel: 0.01,
      ),
      TalentNode(
        id: 'wealth_pursuit',
        name: '재물 탐구',
        description: '몬스터 처치 시 골드 획득량을 영구적으로 증가시킨다.',
        maxLevel: 5,
        pointCostPerLevel: 1,
        prerequisiteNodeIds: ['basic_strength'],
        requiredPrerequisiteLevel: 5,
        buffType: TalentBuffType.goldGainPercent,
        buffValuePerLevel: 0.02,
      ),
      TalentNode(
        id: 'critical_strike',
        name: '치명적 일격',
        description: '크리티컬 확률을 영구적으로 증가시킨다.',
        maxLevel: 5,
        pointCostPerLevel: 1,
        prerequisiteNodeIds: ['basic_strength'],
        requiredPrerequisiteLevel: 5,
        buffType: TalentBuffType.criticalRatePercent,
        buffValuePerLevel: 0.01,
      ),
      TalentNode(
        id: 'unyielding_will',
        name: '불굴의 의지',
        description: '방어력을 영구적으로 증가시킨다.',
        maxLevel: 5,
        pointCostPerLevel: 2,
        prerequisiteNodeIds: ['wealth_pursuit', 'critical_strike'],
        requiredPrerequisiteLevel: 3,
        buffType: TalentBuffType.defensePercent,
        buffValuePerLevel: 0.015,
      ),
    ];
  }
}
