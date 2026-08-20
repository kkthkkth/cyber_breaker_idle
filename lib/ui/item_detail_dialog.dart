import 'dart:ui';

import 'package:flutter/material.dart';

import '../constants/app_images.dart';
import '../managers/config_manager.dart';
import '../managers/equipment_manager.dart';
import '../managers/equipment_set_manager.dart';
import '../managers/game_manager.dart';
import '../managers/guild_war_manager.dart';
import '../models/equipment.dart';
import '../models/guild_war_model.dart';
import '../models/equipment_set_model.dart';
import '../models/pet_stat_metadata_model.dart';
import '../utils/number_formatter.dart';
import '../widgets/center_toast.dart';
import '../widgets/safe_image.dart';
import '../widgets/total_combat_power_banner.dart';
import 'affection_screen.dart';
import 'character_illustration_dialog.dart';
import 'character_screen.dart' show InventoryArea, InventorySlot;
import 'crafting_screen.dart';

/// 장비/펫/캐릭터 인벤토리 아이템 공용 상세 팝업 — 셋 다 [Equipment] 하나로
/// 통일돼 있다(펫은 `EquipType.pet`). [EquipmentFactory]로 생성되기 전의
/// 레거시 장비는 mainStat/subStats가 비어 있을 수 있는데, 그 경우 부위
/// (방어형/공격형)와 statMultiplier·defenseOption류 개별 필드로부터 같은
/// 형태를 합성해 채운다 — 그래서 방패를 눌러도 더 이상 무조건 "공격력"이
/// 뜨지 않는다. 펫의 특수 스탯([Equipment.specialStats])은 [_equipmentSubStats]
/// 가 일반 서브 옵션과 함께 자연스럽게 이어서 보여준다.
class ItemDetailDialog extends StatefulWidget {
  const ItemDetailDialog({super.key, required Equipment item}) : equipment = item;

  final Equipment equipment;

  @override
  State<ItemDetailDialog> createState() => _ItemDetailDialogState();
}

/// 아이템 종류(장비/펫)와 무관하게 정규화된 스탯 한 줄.
class _StatLine {
  const _StatLine({
    required this.icon,
    required this.label,
    required this.valueText,
  });

  final IconData icon;
  final String label;
  final String valueText;
}

class _ItemDetailDialogState extends State<ItemDetailDialog> {
  final EquipmentManager _equipmentManager = EquipmentManager.instance;

  /// 연타 방지 — 하트/망치 버튼처럼 "이 팝업을 pop한 뒤 다른 화면을
  /// push"하는 동작이 두 번 겹쳐 실행되면 pop을 두 번 부르게 되어 이
  /// 다이얼로그 아래에 있던 화면까지 함께 닫힐 수 있다. 한 번 라우팅을
  /// 시작하면 이 위젯이 사라질 때까지 다시 실행되지 않도록 막는다.
  bool _isNavigatingAway = false;

  static const Set<EquipType> _defensiveTypes = {
    EquipType.helmet,
    EquipType.armor,
    EquipType.boots,
    EquipType.shield,
  };

  void _toggleEquip() {
    _equipmentManager.toggleEquip(widget.equipment);
    Navigator.of(context).pop();
  }

  /// 우측 상단 망치 버튼 — 이 팝업을 닫고 '제작/합성' 화면으로 이동하되,
  /// 지금 보고 있던 아이템의 카테고리에 맞는 1Depth 탭(장비=0, 펫=1,
  /// 캐릭터=2)이 처음부터 선택돼 있도록 [CraftingScreen.initialCategoryIndex]
  /// 로 넘겨준다.
  void _navigateToCrafting() {
    if (_isNavigatingAway) {
      return;
    }
    _isNavigatingAway = true;

    final Equipment item = widget.equipment;
    final int tabIndex;
    if (item.type == EquipType.character) {
      tabIndex = 2;
    } else if (item.type == EquipType.pet) {
      tabIndex = 1;
    } else {
      tabIndex = 0; // 장비
    }

    final NavigatorState navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => CraftingScreen(initialCategoryIndex: tabIndex),
      ),
    );
  }

  /// 우측 상단 하트 버튼 — 캐릭터 전용, 이 팝업을 닫고 '호감도' 화면으로
  /// 이동한다. [_navigateToCrafting]과 같은 패턴(팝업을 pop한 뒤 push),
  /// 같은 [_isNavigatingAway] 락을 공유한다 — 두 버튼 중 하나라도 먼저
  /// 눌리면 이 팝업이 사라질 때까지 나머지 탭도 함께 막힌다(연타로 pop이
  /// 두 번 불려 이 다이얼로그 아래 화면까지 닫히는 사고 방지).
  void _navigateToAffection() {
    if (_isNavigatingAway) {
      return;
    }
    _isNavigatingAway = true;

    final Equipment character = widget.equipment;
    final NavigatorState navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => AffectionScreen(character: character)),
    );
  }

  void _levelUp() {
    final bool success = _equipmentManager.levelUpItem(widget.equipment.id);
    if (!success) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('코인이 부족합니다')));
      return;
    }
    // EquipmentManager.levelUpItem이 이미 notifyListeners()를 호출해
    // GameManager(EquipmentManager를 구독 중)까지 자동으로 갱신되므로
    // 인게임 전투 스탯(체력바 등)은 별도 처리 없이도 즉시 반영된다 — 이
    // setState는 이 다이얼로그 자신의 다른 화면 요소(레벨 표시 등)를 새
    // level로 다시 그리기 위한 것뿐이다.
    setState(() {});
  }

  IconData _iconForEquipmentStat(EquipmentStatType type) {
    switch (type) {
      case EquipmentStatType.attack:
        return Icons.local_fire_department;
      case EquipmentStatType.defense:
        return Icons.shield;
      case EquipmentStatType.attackSpeed:
        return Icons.bolt;
      case EquipmentStatType.criticalRate:
        return Icons.flash_on;
      case EquipmentStatType.criticalDamage:
        return Icons.whatshot;
      case EquipmentStatType.evasionRate:
        return Icons.directions_run;
      case EquipmentStatType.defenseRate:
        return Icons.security;
      case EquipmentStatType.critDefenseRate:
        return Icons.gpp_good;
    }
  }

  /// 펫 전용 특수 스탯([Equipment.specialStats])의 키별 아이콘 —
  /// [PetSpecialStat.values]에 없는 알 수 없는 키가 들어와도(예: 예전
  /// 메타데이터로 굴려진 뒤 서버 쪽 키 구성이 바뀐 경우) 크래시 대신
  /// 무난한 기본 아이콘으로 대체한다.
  IconData _iconForSpecialStat(String key) {
    switch (key) {
      case PetSpecialStat.dropRateBoost:
        return Icons.card_giftcard;
      case PetSpecialStat.goldGain:
        return Icons.monetization_on;
      case PetSpecialStat.bossDamage:
        return Icons.whatshot;
      case PetSpecialStat.finalAttackBoost:
        return Icons.local_fire_department;
      case PetSpecialStat.skillCooldownReduction:
        return Icons.timer;
      case PetSpecialStat.criticalDamageBoost:
        return Icons.flash_on;
      default:
        return Icons.auto_awesome;
    }
  }

  /// 장비 메인 스탯 한 줄 — [Equipment.mainStat]이 채워진 신규(EquipmentFactory
  /// 산출물) 아이템은 그대로 쓰고, 비어 있는 레거시 아이템은 부위가
  /// 방어형인지 공격형인지에 따라 라벨을 골라 statMultiplier로 합성한다.
  ///
  /// [mainStat.value] 자체는 생성 시점(가챠)에 한 번 굴려진 뒤 절대 바뀌지
  /// 않는 "기본" 수치라, 예전엔 이 값만 그대로 보여줘서 레벨업 버튼을 눌러
  /// 아무리 [Equipment.level]이 올라도 화면 숫자가 꼼짝하지 않는 버그가
  /// 있었다. 그래서 한 번은 여기 `item.statMultiplier`를 곱해 보정했었는데,
  /// `statMultiplier`는 사실 EquipmentManager.getTotalEquipmentMultiplier가
  /// 합산하는 "전체 장비 대비 기여율"(가챠 등급별로 0.05~3.00 수준의 작은
  /// 값)이지 "이 아이템 자체의 배율"이 아니었다 — 그래서 예를 들어
  /// statMultiplier가 0.08이면 mainStat.value(예: 12)를 곱한 결과가 1보다
  /// 작아져 정수로 내림되면서 "공격력 0"으로 찍히는 새 버그가 났다(특히
  /// 합성 직후 레벨이 0으로 초기화된 ★1 아이템에서 두드러졌다). 이제
  /// statMultiplier는 아예 쓰지 않고, [Equipment.star]/[Equipment.level]
  /// 두 성장 축만으로 표시값을 유도한다 — 성급이 오를수록 기본 수치 자체가
  /// (star * starGrowthPerStar만큼) 불어나 절대 0으로 뭉개지지 않는다.
  _StatLine _equipmentMainStat(Equipment item) {
    final EquipmentOption? mainStat = item.mainStat;
    if (mainStat != null) {
      if (mainStat.type.isPercentage) {
        return _StatLine(
          icon: _iconForEquipmentStat(mainStat.type),
          label: mainStat.type.displayName,
          valueText: '+${(mainStat.value * 100).toStringAsFixed(1)}%',
        );
      }

      final double starBoostedBase =
          mainStat.value * (1 + item.star * Equipment.starGrowthPerStar);
      final double levelGain =
          mainStat.value * item.level * Equipment.statGrowthPerLevel;
      final double total = starBoostedBase + levelGain;
      return _StatLine(
        icon: _iconForEquipmentStat(mainStat.type),
        label: mainStat.type.displayName,
        valueText:
            '${NumberFormatter.format(total)} (+${NumberFormatter.format(levelGain)})',
      );
    }

    final bool isDefensive = _defensiveTypes.contains(item.type);
    return _StatLine(
      icon: isDefensive ? Icons.shield : Icons.local_fire_department,
      label: isDefensive ? '방어력' : '공격력',
      valueText: '+${(item.statMultiplier * 100).round()}',
    );
  }

  /// 장비 서브 옵션 목록 — 신규 [Equipment.subStats]가 채워져 있으면 그대로
  /// 쓰고, 비어 있으면 레거시 방어 옵션 4종(defenseOption 등) 중 값이 있는
  /// 것만 모아 같은 형태로 보여준다. 펫([Equipment.specialStats])은 항상
  /// 이 목록 맨 뒤에 이어 붙는다 — 일반 서브 옵션이 없는 펫이라도 특수
  /// 스탯만으로 목록이 채워질 수 있도록 별도 섹션을 만들지 않는다.
  List<_StatLine> _equipmentSubStats(Equipment item) {
    final List<_StatLine> lines = item.subStats.isNotEmpty
        ? item.subStats
            .map(
              (option) => _StatLine(
                icon: _iconForEquipmentStat(option.type),
                label: option.type.displayName,
                valueText: option.type.isPercentage
                    ? '+${(option.value * 100).toStringAsFixed(1)}%'
                    : '+${option.value.toStringAsFixed(0)}',
              ),
            )
            .toList()
        : _legacyEquipmentSubStats(item);

    for (final MapEntry<String, double> entry in item.specialStats.entries) {
      lines.add(
        _StatLine(
          icon: _iconForSpecialStat(entry.key),
          label: PetSpecialStat.displayName(entry.key),
          valueText: '+${(entry.value * 100).toStringAsFixed(1)}%',
        ),
      );
    }
    return lines;
  }

  List<_StatLine> _legacyEquipmentSubStats(Equipment item) {
    final List<_StatLine> legacy = [];
    if (item.defenseOption > 0) {
      legacy.add(
        _StatLine(
          icon: Icons.shield,
          label: '방어력',
          valueText: '+${item.defenseOption.toStringAsFixed(0)}',
        ),
      );
    }
    if (item.defenseRateOption > 0) {
      legacy.add(
        _StatLine(
          icon: Icons.security,
          label: '방어율',
          valueText: '+${(item.defenseRateOption * 100).toStringAsFixed(1)}%',
        ),
      );
    }
    if (item.evasionRateOption > 0) {
      legacy.add(
        _StatLine(
          icon: Icons.directions_run,
          label: '회피율',
          valueText: '+${(item.evasionRateOption * 100).toStringAsFixed(1)}%',
        ),
      );
    }
    if (item.critDefenseRateOption > 0) {
      legacy.add(
        _StatLine(
          icon: Icons.gpp_good,
          label: '크리티컬 방어율',
          valueText:
              '+${(item.critDefenseRateOption * 100).toStringAsFixed(1)}%',
        ),
      );
    }
    return legacy;
  }

  @override
  Widget build(BuildContext context) {
    final Equipment equipment = widget.equipment;

    final ItemGrade grade = equipment.grade;
    final Color gradeColor = getGradeColor(grade);
    final String name = equipment.name;
    final bool isEquipped = equipment.isEquipped;
    final String descriptionText =
        '${equipment.grade.displayName} 등급 ${equipment.type.displayName} 아이템입니다.';

    final _StatLine mainStat = _equipmentMainStat(equipment);
    final List<_StatLine> subStats = _equipmentSubStats(equipment);

    // 레벨업 시 실제로 자라는 건 statMultiplier뿐이라, 화면에 보이는 메인
    // 스탯이 statMultiplier 기반(=레거시 아이템)일 때만 "다음 레벨 증가치"를
    // 함께 보여준다 — mainStat이 따로 있는 신규 아이템은 레벨업과 무관하다.
    final bool showLevelUpGain = equipment.mainStat == null && !equipment.isMaxLevel;
    final int statGain = showLevelUpGain
        ? ((equipment.nextLevelStatMultiplier * 100).round() -
              (equipment.statMultiplier * 100).round())
        : 0;

    return Dialog(
      backgroundColor: const Color(0xFF1B1B26),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: gradeColor, width: 1.5),
      ),
      // LR 등급은 서브 옵션이 최대 5개까지 나올 수 있어 내용이 다이얼로그
      // 높이를 넘길 수 있다 — 화면 높이의 85%로 캡을 씌우고 넘치는 만큼은
      // 스크롤되게 해서 하단 버튼이 잘리거나 오버플로 에러가 나지 않게 한다.
      child: Stack(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── 상단: 이미지, 이름, 등급, 레벨, 설명 ─────────────────────
                    // 장비/펫/캐릭터 전부 인벤토리 그리드가 쓰는
                    // InventorySlot을 그대로 재사용하고, 크기도 고정 픽셀
                    // (예: 72)이 아니라 InventoryArea.tileSizeFor로 그 순간
                    // 실제 인벤토리 그리드 타일 크기를 그대로 가져온다 —
                    // 화면 폭에 따라 그리드 타일 크기 자체가 달라지므로,
                    // 고정값을 쓰면 기기에 따라 미묘하게 어긋나 보인다.
                    // 모서리 라운딩·등급색 테두리·좌측 상단 등급 배지(N1
                    // 등)/우측 상단 레벨 배지/하단 성급(★) 배지까지
                    // 인벤토리와 100% 같은 컴포넌트라 저절로 동일하게
                    // 보인다.
                    SizedBox(
                      width: InventoryArea.tileSizeFor(context),
                      height: InventoryArea.tileSizeFor(context),
                      child: InventorySlot(item: equipment),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: gradeColor.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        grade.displayName,
                        style: TextStyle(
                          color: gradeColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Lv. ${equipment.level}/${Equipment.maxLevel}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      descriptionText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                    if (equipment.setId != null) ...[
                      const SizedBox(height: 12),
                      _SetInfoCard(setId: equipment.setId!),
                    ],
                    const SizedBox(height: 20),

                    // ── 중단: 휘장은 전용 버프 안내 카드, 그 외엔 기존
                    // 메인 스탯(부위/카테고리에 맞게 동적으로) + 서브 옵션 ──
                    if (equipment.type == EquipType.badge)
                      _BadgeBuffCard(equipment: equipment)
                    else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF20202C),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                mainStat.icon,
                                color: Colors.orangeAccent,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${mainStat.label} ${mainStat.valueText}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              if (showLevelUpGain) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '(+ $statGain)',
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (subStats.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Divider(color: Colors.white24, height: 1),
                            ),
                            Column(
                              children: [
                                for (final _StatLine stat in subStats)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 3,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          stat.icon,
                                          color: Colors.white54,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '- ${stat.label}: ${stat.valueText}',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── 캐릭터 전용: 복잡한 개별 스탯 나열(구
                    // _CharacterCoreStatsCard, HP/ATK/DEF/ASPD 4줄 카드) 대신
                    // 모든 능력치를 한 값으로 합산한 총 전투력을 크고 화려하게
                    // 강조한다(요구사항 — 스탯 UI를 없애고 총 전투력을 부각).
                    // 이 다이얼로그 자체는 GameManager/ConfigManager를
                    // 구독하지 않으므로(레벨업 등은 로컬 setState로만
                    // 처리), 이 배너만 AnimatedBuilder로 감싸서 전투력
                    // 가중치가 인게임 중 다시 로드돼도 자동으로 갱신되게
                    // 한다(요구사항: "UI 실시간 반영").
                    if (equipment.type == EquipType.character) ...[
                      AnimatedBuilder(
                        animation: Listenable.merge([GameManager.instance, ConfigManager.instance]),
                        builder: (context, _) => TotalCombatPowerBanner(
                          combatPower: GameManager.instance.totalCombatPower,
                          fontSize: 30,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // ── 하단: 장착/해제, (장비 한정) 레벨업 버튼 — 휘장은
                    // 강화/장착 해제가 불가능해야 하므로(요구사항) 이 Row
                    // 자체를 그리지 않는다.
                    if (equipment.type != EquipType.badge)
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _toggleEquip,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B7DD8),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              isEquipped ? '장착 해제' : '장착',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: equipment.isMaxLevel ? null : _levelUp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2ECC71),
                              foregroundColor: Colors.black,
                              disabledBackgroundColor: const Color(0xFF3A3A4A),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  equipment.isMaxLevel ? 'MAX' : '레벨업',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                if (!equipment.isMaxLevel) ...[
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.monetization_on,
                                        color: Colors.black87,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        '${equipment.levelUpCost}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    // ── 최하단: 캐릭터 전용 성급(★0~5) 일러스트 갤러리 ───────────
                    if (equipment.type == EquipType.character) ...[
                      const SizedBox(height: 20),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '일러스트 갤러리',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _StarIllustrationGallery(character: equipment),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // 우측 상단 제작/합성 바로가기 — 이 팝업을 닫고, 열려 있던
          // 아이템의 카테고리(장비/펫/캐릭터)에 맞는 제작 화면 탭으로 바로
          // 진입한다([_navigateToCrafting] 참고).
          if (equipment.type != EquipType.badge)
            Positioned(
              top: 8,
              right: 8,
              child: _CraftingShortcutButton(onTap: _navigateToCrafting),
            ),
          // 좌측에 나란히 놓이는 호감도(하트) 바로가기 — 캐릭터 상세에서만
          // 보인다([_navigateToAffection] 참고).
          if (equipment.type == EquipType.character)
            Positioned(
              top: 8,
              right: 50,
              child: _AffectionShortcutButton(onTap: _navigateToAffection),
            ),
        ],
      ),
    );
  }
}

/// 상세 팝업 우측 상단 코너의 제작/합성 바로가기 — 장비/펫/캐릭터 상세
/// 어디서든 같은 모양으로 뜬다([ItemDetailDialog.build] 참고).
class _CraftingShortcutButton extends StatelessWidget {
  const _CraftingShortcutButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '제작/합성 화면으로 이동',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.black45,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFC9A24B), width: 1.2),
          ),
          child: const Icon(Icons.build, color: Color(0xFFC9A24B), size: 18),
        ),
      ),
    );
  }
}

/// 상세 팝업 우측 상단, 제작 바로가기 왼쪽에 놓이는 호감도 바로가기 —
/// 캐릭터 상세에서만 뜬다([ItemDetailDialog.build] 참고).
class _AffectionShortcutButton extends StatelessWidget {
  const _AffectionShortcutButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '호감도 화면으로 이동',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.black45,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFF6FA5), width: 1.2),
          ),
          child: const Icon(Icons.favorite, color: Color(0xFFFF6FA5), size: 18),
        ),
      ),
    );
  }
}

/// 캐릭터 상세 팝업 하단의 가로 스크롤 성급 일러스트 갤러리 — ★0(기본,
/// 보유만 해도 항상 해금)부터 ★5까지, 캐릭터의 현재 성급([Equipment.star])과
/// 같거나 낮은 슬롯은 전부 해금돼 보인다. 언락된 슬롯을 탭하면
/// [CharacterIllustrationDialog]를 그 성급부터 열어서 스와이프로 다른
/// 해금 성급도 이어서 볼 수 있다.
class _StarIllustrationGallery extends StatelessWidget {
  const _StarIllustrationGallery({required this.character});

  final Equipment character;

  static const int maxStarLevel = 5;

  // 하단 탭 바 위에 뜨던 기존 SnackBar(ScaffoldMessenger) 대신, 팝업창
  // 중앙(레벨업 버튼 부근)에 짧게 떴다 사라지는 토스트로 안내한다.
  void _onTapLocked(BuildContext context, int level) {
    showCenterToast(context, '$level성을 달성하여 해금하세요');
  }

  void _onTapUnlocked(BuildContext context, int level) {
    showDialog<void>(
      context: context,
      builder: (context) => CharacterIllustrationDialog(
        character: character,
        initialLevel: level,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String characterId = character.gradeBadgeLabel;
    final int currentStarLevel = character.star;

    return SizedBox(
      height: _StarIllustrationSlot.height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: maxStarLevel + 1,
        separatorBuilder: (context, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final int level = index;
          final bool unlocked = level <= currentStarLevel;
          return _StarIllustrationSlot(
            level: level,
            // 썸네일은 항상 정지 .png만 — 확대해서 크게 볼 때(카드 팝업/
            // 전체화면)만 .webp 애니메이션을 우선 시도한다
            // (CharacterIllustrationDialog 쪽). 작은 카드까지 애니메이션이
            // 돌면 시선이 분산되고, CachedNetworkImage의 디스크 캐싱도
            // 못 받는다(.webp는 애니메이션 재생을 위해 Image.network로
            // 직행하도록 CustomSafeImage가 분기해 둔 상태라 — safe_image.dart
            // 참고).
            imagePath: AppImages.characterStarFallback(characterId, level),
            heroTag: CharacterIllustrationDialog.heroTag(characterId, level),
            unlocked: unlocked,
            onTap: unlocked
                ? () => _onTapUnlocked(context, level)
                : () => _onTapLocked(context, level),
          );
        },
      ),
    );
  }
}

/// 갤러리 한 칸 — 해금(원본), 기본 미해금(흑백), 고스포일러(4·5성) 미해금
/// (흑백 + 블러) 세 상태를 표현한다.
class _StarIllustrationSlot extends StatelessWidget {
  const _StarIllustrationSlot({
    required this.level,
    required this.imagePath,
    required this.heroTag,
    required this.unlocked,
    required this.onTap,
  });

  final int level;

  /// 항상 정지 .png 경로 — 애니메이션 .webp는 카드 팝업/전체화면에서만
  /// 시도한다([_StarIllustrationGallery] 참고).
  final String imagePath;

  /// [CharacterIllustrationDialog.heroTag]와 정확히 같은 문자열이어야
  /// 썸네일→카드 팝업 Hero 전환이 매끄럽게 이어진다(확장자가 .png↔.webp로
  /// 달라도 태그는 characterId+level로만 정해지므로 무관하다).
  final Object heroTag;
  final bool unlocked;
  final VoidCallback onTap;

  /// 표준 휘도 기반 흑백 변환 행렬.
  static const ColorFilter _grayscaleFilter = ColorFilter.matrix(<double>[
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);

  /// 4성/5성처럼 스포일러성이 강한 상위 일러스트는 미해금 상태일 때 흑백만
  /// 으로는 부족해서 블러까지 추가로 얹어 형태만 간신히 보이게 한다.
  bool get _isHighSpoiler => level >= 4;

  /// 기존 72x92 대비 약 20% 축소 — 슬롯이 6개(★0~5)로 늘어난 뒤 다음 슬롯이
  /// 오른쪽 끝에 살짝 걸쳐 보이도록(스크롤 가능함을 시각적으로 암시) 하기
  /// 위함.
  static const double width = 58;
  static const double height = 74;

  @override
  Widget build(BuildContext context) {
    Widget content = Hero(
      tag: heroTag,
      child: CustomSafeImage(
        path: imagePath,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.none,
      ),
    );

    if (!unlocked) {
      content = ColorFiltered(colorFilter: _grayscaleFilter, child: content);
      if (_isHighSpoiler) {
        content = ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: content,
        );
      }
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: width,
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: unlocked ? Colors.amberAccent : const Color(0xFF3A3A4A),
            width: 1.2,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            if (!unlocked)
              const Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: ColoredBox(
                  color: Colors.black54,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 2),
                    child: Icon(Icons.lock, color: Colors.white70, size: 12),
                  ),
                ),
              ),
            Positioned(
              top: 2,
              left: 3,
              child: Text(
                Equipment.starText(level),
                style: TextStyle(
                  color: unlocked ? Colors.amberAccent : Colors.white54,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 휘장([EquipType.badge]) 전용 버프 안내 카드 — 요구사항 문구 그대로
/// "승리자의 기운: 골드 획득 +20%, 크리티컬 데미지 +10% (남은 기간: X일
/// X시간)"을 보여준다. 퍼센트 수치는 [GuildWarManager.config](DB
/// `guild_war_config`)에서, 남은 기간은 [Equipment.expiresAt]에서 매번
/// 다시 계산한다 — 팝업이 떠 있는 동안 시간이 흘러도 다음에 다시 열 때
/// 정확한 값을 보여준다(실시간 카운트다운까지는 아니다).
class _BadgeBuffCard extends StatelessWidget {
  const _BadgeBuffCard({required this.equipment});

  final Equipment equipment;

  String get _remainingLabel {
    final DateTime? expiresAt = equipment.expiresAt;
    if (expiresAt == null) {
      return '기간 정보 없음';
    }
    final Duration remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative) {
      return '만료됨';
    }
    final int days = remaining.inDays;
    final int hours = remaining.inHours % 24;
    return '$days일 $hours시간';
  }

  @override
  Widget build(BuildContext context) {
    final GuildWarConfig config = GuildWarManager.instance.config;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4A3B0A), Color(0xFF20202C)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD54F).withValues(alpha: 0.7)),
      ),
      child: Column(
        children: [
          const Icon(Icons.military_tech, color: Color(0xFFFFD54F), size: 28),
          const SizedBox(height: 8),
          const Text(
            '승리자의 기운',
            style: TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 10),
          Text(
            '골드 획득 +${(config.badgeBuffGoldRate * 100).toStringAsFixed(0)}%, '
            '크리티컬 데미지 +${(config.badgeBuffCritDmg * 100).toStringAsFixed(0)}%',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            '(남은 기간: $_remainingLabel)',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// 세트 장비([Equipment.setId] != null)일 때만 상세 팝업 상단에 뜨는
/// 카드 — 세트 이름, 지금 장착 부위 수, 2부위/4부위 효과를 나열하고
/// 실제로 발동 중인 줄만 강조색+체크 아이콘으로 표시한다.
class _SetInfoCard extends StatelessWidget {
  const _SetInfoCard({required this.setId});

  final String setId;

  EquipmentSetBonus? _bonus() {
    for (final EquipmentSetBonus bonus in EquipmentSetManager.instance.catalog) {
      if (bonus.setId == setId) {
        return bonus;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final EquipmentSetBonus? bonus = _bonus();
    final int equippedCount = EquipmentManager.instance.equippedSetCounts[setId] ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF6C4FCE).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6C4FCE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Color(0xFF8A6FE0), size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  bonus?.name ?? setId,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                '$equippedCount부위 장착 중',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
          if (bonus != null) ...[
            const SizedBox(height: 8),
            _SetTierLine(
              requiredCount: 2,
              equippedCount: equippedCount,
              stat: bonus.twoPieceStat,
              value: bonus.twoPieceValue,
            ),
            if (bonus.fourPieceStat != null) ...[
              const SizedBox(height: 4),
              _SetTierLine(
                requiredCount: 4,
                equippedCount: equippedCount,
                stat: bonus.fourPieceStat!,
                value: bonus.fourPieceValue,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SetTierLine extends StatelessWidget {
  const _SetTierLine({
    required this.requiredCount,
    required this.equippedCount,
    required this.stat,
    required this.value,
  });

  final int requiredCount;
  final int equippedCount;
  final String stat;
  final double value;

  @override
  Widget build(BuildContext context) {
    final bool active = equippedCount >= requiredCount;
    return Row(
      children: [
        Icon(
          active ? Icons.check_circle : Icons.radio_button_unchecked,
          color: active ? Colors.greenAccent : Colors.white38,
          size: 14,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$requiredCount세트: ${EquipmentSetStat.displayName(stat)} '
            '+${(value * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              color: active ? Colors.white : Colors.white54,
              fontSize: 11,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}

