import 'package:flutter/material.dart';

import '../game/idle_game.dart';
import '../managers/collection_manager.dart';
import '../managers/encyclopedia_manager.dart';
import '../managers/equipment_manager.dart';
import '../managers/equipment_set_manager.dart';
import '../managers/game_manager.dart';
import '../models/equipment.dart';
import '../models/equipment_set_model.dart';
import '../utils/number_formatter.dart';
import '../widgets/center_toast.dart';
import '../widgets/character_face_portrait.dart';
import '../widgets/character_idle_preview.dart';
import 'collection_screen.dart';
import 'consumable_inventory_screen.dart';
import 'crafting_screen.dart';
import 'item_detail_dialog.dart';
import 'rune_screen.dart';

class CharacterScreen extends StatefulWidget {
  const CharacterScreen({super.key});

  @override
  State<CharacterScreen> createState() => _CharacterScreenState();
}

class _CharacterScreenState extends State<CharacterScreen> {
  final EquipmentManager _manager = EquipmentManager.instance;

  // 0: 캐릭터, 1: 장비, 2: 펫
  int _selectedInventoryTab = 1;

  /// 합성으로 성급을 많이 올린 아이템이 항상 그리드 맨 앞에 오도록 항상
  /// [Equipment.compareForDisplay](성급→레벨→등급 내림차순)로 정렬해서
  /// 반환한다 — 캐릭터/장비/펫 탭 전부 이 getter 하나를 거치므로 세 종류
  /// 모두 자동으로 같은 규칙을 따른다.
  List<Equipment> get _filteredInventory {
    final List<Equipment> unequipped =
        _manager.inventory.where((item) => !item.isEquipped).toList();

    final List<Equipment> filtered;
    switch (_selectedInventoryTab) {
      case 0: // 캐릭터
        filtered = unequipped.where((item) => item.type == EquipType.character).toList();
      case 2: // 펫
        filtered = unequipped.where((item) => item.type == EquipType.pet).toList();
      case 1: // 장비 — 펫/캐릭터를 제외한 나머지 전부.
      default:
        filtered = unequipped
            .where((item) => item.type != EquipType.pet && item.type != EquipType.character)
            .toList();
    }
    filtered.sort(Equipment.compareForDisplay);
    return filtered;
  }

  void _autoEquip() {
    _manager.autoEquipBestItems();
    showCenterToast(context, '더 좋은 장비로 자동 장착되었습니다!');
  }

  void _showItemDetail(Equipment item) {
    showDialog<void>(
      context: context,
      builder: (context) => ItemDetailDialog(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14141C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B1B26),
        elevation: 0,
        // 뒤로 가기 버튼처럼 별도 색을 안 준 아이콘이 어두운 배경에
        // 묻히지 않도록 명시한다.
        foregroundColor: Colors.white,
        title: const Text(
          '캐릭터',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildCharacterBody(),
    );
  }

  Widget _buildCharacterBody() {
    return AnimatedBuilder(
      // 인벤토리(_manager)뿐 아니라 컬렉션 등록/도감 보상 상태 변화로도
      // [수집] 버튼의 레드닷이 즉시 바뀌어야 하므로 두 매니저 모두 함께
      // 구독한다 — hasAnyCollectionReward 자체는 EncyclopediaManager에만
      // notifyListeners를 요구하지 않지만, 그 안에서 CollectionManager의
      // 상태도 읽으므로 CollectionManager 쪽 변경 이벤트도 받아야 한다.
      animation: Listenable.merge([
        _manager,
        CollectionManager.instance,
        EncyclopediaManager.instance,
      ]),
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            children: [
              SizedBox(
                height: 340,
                child: EquipArea(
                  equippedItems: _manager.equippedItems,
                  onSlotTap: _showItemDetail,
                ),
              ),
              // 기존 8슬롯 그리드(EquipArea)는 손대지 않고, 그 바로 아래에
              // 길드 전쟁 승리 휘장 전용 "특수 장비" 자리를 별도 Row로
              // 추가한다 — EquipArea는 부모가 고정 높이(340)로 감싸고 있어
              // 안에 슬롯을 더 끼워 넣으면 기존 좌우 4슬롯 레이아웃이
              // 깨질 위험이 있지만, 이 화면 전체는 SingleChildScrollView라
              // 바깥에 새 Row를 추가하는 건 완전히 안전하다.
              _SpecialEquipRow(
                badge: _manager.equippedItems[EquipType.badge],
                onTap: _showItemDetail,
              ),
              const StatPanel(),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.backpack,
                        label: '인벤토리',
                        accentColor: const Color(0xFF4F8FE0),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) =>
                                const ConsumableInventoryScreen(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.auto_awesome,
                        label: '자동 장착',
                        accentColor: const Color(0xFF3FBF94),
                        onTap: _autoEquip,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.construction,
                        label: '제작',
                        accentColor: const Color(0xFF8A6FE0),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const CraftingScreen(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      // 도감 보상/컬렉션 등록 알림 체인의 최종 집계 지점
                      // (EncyclopediaManager.hasAnyCollectionReward)을 그대로
                      // 구독 — 하위 슬롯 어디서든 알림이 생기면 여기도 켜진다.
                      child: Badge(
                        isLabelVisible: EncyclopediaManager.instance.hasAnyCollectionReward,
                        backgroundColor: Colors.redAccent,
                        smallSize: 12,
                        child: _ActionButton(
                          icon: Icons.collections_bookmark,
                          label: '수집',
                          accentColor: const Color(0xFF3FBFBF),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const CollectionScreen(),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.hexagon,
                        label: '룬',
                        accentColor: const Color(0xFF3FBF6E),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const RuneScreen(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: _InventoryTabButton(
                        label: '캐릭터',
                        selected: _selectedInventoryTab == 0,
                        onTap: () => setState(() => _selectedInventoryTab = 0),
                      ),
                    ),
                    Expanded(
                      child: _InventoryTabButton(
                        label: '장비',
                        selected: _selectedInventoryTab == 1,
                        onTap: () => setState(() => _selectedInventoryTab = 1),
                      ),
                    ),
                    Expanded(
                      child: _InventoryTabButton(
                        label: '펫',
                        selected: _selectedInventoryTab == 2,
                        onTap: () => setState(() => _selectedInventoryTab = 2),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              InventoryArea(
                inventory: _filteredInventory,
                onSlotTap: _showItemDetail,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 알록달록한 그라데이션 대신, 배경은 전체 테마와 같은 다크 그레이로
/// 통일하고 버튼마다 다른 [accentColor]만 테두리·아이콘·텍스트에 입힌다
/// (OutlinedButton 스타일 — 포인트 컬러는 윤곽선으로만 드러난다).
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: const Color(0xFF1E1E28),
        side: BorderSide(color: accentColor, width: 1.2),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: accentColor, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accentColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryTabButton extends StatelessWidget {
  const _InventoryTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? const Color(0xFF8A6FE0) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white54,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _EquipSlotInfo {
  const _EquipSlotInfo(this.type, this.label, this.icon);

  final EquipType type;
  final String label;
  final IconData icon;
}

// 좌측: 무기/투구/갑옷/벨트 4개.
// 우측: 방패/장갑/신발/반지 4개.
// 유물/펫은 더 이상 좌우 Column에 없다 — 중앙 캐릭터 카드 바로 아래
// Row로 옮겨졌다(EquipArea.build() 참고).
const List<_EquipSlotInfo> _leftEquipSlots = [
  _EquipSlotInfo(EquipType.weapon, '무기', Icons.gavel),
  _EquipSlotInfo(EquipType.helmet, '투구', Icons.sports_motorsports),
  _EquipSlotInfo(EquipType.armor, '갑옷', Icons.shield_moon),
  _EquipSlotInfo(EquipType.belt, '벨트', Icons.horizontal_rule),
];

const List<_EquipSlotInfo> _rightEquipSlots = [
  _EquipSlotInfo(EquipType.shield, '방패', Icons.security),
  _EquipSlotInfo(EquipType.glove, '장갑', Icons.back_hand),
  _EquipSlotInfo(EquipType.boots, '신발', Icons.directions_walk),
  _EquipSlotInfo(EquipType.ring, '반지', Icons.circle_outlined),
];

/// 좌/우 4칸 + 중앙 하단(유물/펫) 슬롯이 공유하는 크기 — 기존 46px보다
/// 약 50% 커졌다. 이 값을 바꾸면 세 곳의 슬롯 크기가 함께 조정된다.
const double _sideSlotSize = 70;

class EquipArea extends StatefulWidget {
  const EquipArea({
    super.key,
    required this.equippedItems,
    required this.onSlotTap,
  });

  final Map<EquipType, Equipment?> equippedItems;

  /// 장착된 아이템이 있는 슬롯(중앙 캐릭터·펫/장비 8개)을 탭했을 때 호출된다 —
  /// 빈 슬롯은 애초에 호출되지 않는다.
  final ValueChanged<Equipment> onSlotTap;

  @override
  State<EquipArea> createState() => _EquipAreaState();
}

class _EquipAreaState extends State<EquipArea> {
  // SingleChildScrollView로 감싸지 않는다 — Column이 Row(고정 높이)의
  // 세로 폭을 그대로 이어받아야 spaceEvenly가 슬롯 사이 간격을 화면
  // 크기에 맞춰 실제로 줄여준다(스크롤 뷰 안에서는 세로가 무한이라
  // mainAxisAlignment가 아무 효과가 없다).
  Widget _buildSideColumn(List<_EquipSlotInfo> slots) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: slots.map((info) {
        final Equipment? item = widget.equippedItems[info.type];
        return EquipSlot(
          label: info.label,
          icon: info.icon,
          item: item,
          size: _sideSlotSize,
          onTap: item == null ? null : () => widget.onSlotTap(item),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Equipment? equippedCharacter = widget.equippedItems[EquipType.character];
    final Equipment? equippedPet = widget.equippedItems[EquipType.pet];
    final Equipment? equippedRelic = widget.equippedItems[EquipType.relic];

    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSideColumn(_leftEquipSlots),
          // 중앙 열: 캐릭터 카드는 고정 높이 없이 Expanded로 감싸 하단
          // 유물/펫 슬롯(고정 높이)을 뺀 나머지 세로 공간만 정확히
          // 차지한다 — 예전 AspectRatio는 폭 기준으로 높이를 역산해서
          // 화면이 좁을 때 카드가 남은 공간보다 커져 세로 오버플로를
          // 냈었다.
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: equippedCharacter == null
                          ? null
                          : () => widget.onSlotTap(equippedCharacter),
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          // 은은하게 중앙에서 퍼져나가는 원형 조명 —
                          // 기존 단색 세로 그라데이션 대신, 캐릭터가 스포트
                          // 라이트를 받는 듯한 느낌을 준다.
                          gradient: const RadialGradient(
                            center: Alignment.center,
                            radius: 0.9,
                            colors: [
                              Color(0xFF4E3A8C),
                              Color(0xFF2E2350),
                              Color(0xFF1C1730),
                            ],
                            stops: [0.0, 0.6, 1.0],
                          ),
                          border: Border.all(color: const Color(0xFF6C4FCE), width: 1.5),
                        ),
                        // 캐릭터는 제자리에 고정된 정적 이미지로 보여준다
                        // (예전엔 sin() 기반 상하 bobbing이 있었으나 제거함).
                        // 펫은 아래 슬롯 Row로 옮겨갔다.
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // 캐릭터 발밑 타원형 그림자 — Stack 맨 아래(뒤)
                            // 레이어라 캐릭터 이미지가 그 위에 자연스럽게
                            // 겹쳐 보인다.
                            Positioned(
                              bottom: 28,
                              child: Container(
                                width: 110,
                                height: 26,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.45),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.4),
                                      blurRadius: 18,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            equippedCharacter == null
                                ? const Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.person,
                                        size: 112,
                                        color: Colors.white70,
                                      ),
                                      SizedBox(height: 6),
                                      Text(
                                        '캐릭터 이미지',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      // 펫을 착용 중이면 캐릭터 바로 왼쪽에
                                      // 캐릭터보다 살짝 작은 비율(0.65배)로
                                      // 나란히 세운다 — Stack.alignment가
                                      // 이 Row 전체를 다시 카드 중앙에
                                      // 맞춰주므로 별도 좌표 계산이 필요
                                      // 없다.
                                      if (equippedPet != null) ...[
                                        _PetPreviewAvatar(
                                          pet: equippedPet,
                                          size: PlayerAnimationComponent.boxSize * 0.65,
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // 인게임 전투 스케일과 동일하게
                                          // [PlayerAnimationComponent.boxSize]를
                                          // 그대로 재사용한다(기존 128 →
                                          // 180). CharacterIdlePreview가
                                          // 내부적으로 FilterQuality.none을
                                          // 이미 적용하므로 픽셀 아트가
                                          // 흐려지지 않고, 512x512 캔버스
                                          // 여백도 자체적으로 잘라내
                                          // 캐릭터 알맹이가 상자를 꽉
                                          // 채운다. 정적 정면 이미지 대신
                                          // 대기(wait) 모션을 반복 재생해
                                          // 캐릭터가 살아있는 느낌을 준다.
                                          CharacterIdlePreview(
                                            characterId:
                                                equippedCharacter.gradeBadgeLabel,
                                            size: PlayerAnimationComponent.boxSize,
                                            borderRadius: 12,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            equippedCharacter.name,
                                            textAlign: TextAlign.center,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: getGradeColor(equippedCharacter.grade),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                          // 합성으로 성급이 1 이상 오른
                                          // 캐릭터만 이름 아래에 골드색
                                          // 별 뱃지를 보여준다 — 인벤토리
                                          // 그리드/장착 슬롯(EquipSlot,
                                          // InventorySlot)의 _StarBadge와
                                          // 같은 위젯이라 표기가 항상
                                          // 통일된다.
                                          if (equippedCharacter.star > 0) ...[
                                            const SizedBox(height: 2),
                                            _StarBadge(star: equippedCharacter.star),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                            if (equippedCharacter != null)
                              Positioned(
                                top: 4,
                                left: 4,
                                child: _GradeBadge(item: equippedCharacter, compact: true),
                              ),
                            if (equippedCharacter != null && equippedCharacter.level > 0)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: _LevelBadge(
                                  level: equippedCharacter.level,
                                  compact: true,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    EquipSlot(
                      label: '유물',
                      icon: Icons.token,
                      item: equippedRelic,
                      size: _sideSlotSize,
                      onTap: equippedRelic == null
                          ? null
                          : () => widget.onSlotTap(equippedRelic),
                    ),
                    const SizedBox(width: 14),
                    EquipSlot(
                      label: '펫',
                      icon: Icons.pets,
                      item: equippedPet,
                      size: _sideSlotSize,
                      onTap: equippedPet == null
                          ? null
                          : () => widget.onSlotTap(equippedPet),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildSideColumn(_rightEquipSlots),
        ],
      ),
    );
  }
}

/// 캐릭터 프리뷰 카드에서 캐릭터 바로 왼쪽에 세우는 펫 아바타 — 아직 펫
/// 전용 아트가 없어([ItemPoolConfig] 참고, 아이콘/텍스트로만 표시하는 게
/// 프로젝트 전체 관례) 등급색 원형 배지 + paw 아이콘으로 표현한다. 인게임
/// 전투 화면의 [PetComponent]와 같은 시각 언어(등급색 대신 고정 오렌지
/// 톤 — 등급별로 구분해야 할 만큼 펫 종류가 아직 많지 않다)를 쓴다.
class _PetPreviewAvatar extends StatelessWidget {
  const _PetPreviewAvatar({required this.pet, required this.size});

  final Equipment pet;
  final double size;

  static const Color _petColor = Color(0xFFFF9800);
  static const Color _petBorderColor = Color(0xFFE65100);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: _petColor.withValues(alpha: 0.22),
              shape: BoxShape.circle,
              border: Border.all(color: _petBorderColor, width: 2),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.pets, color: _petColor, size: size * 0.5),
          ),
          Positioned(
            top: -2,
            left: -2,
            child: _GradeBadge(item: pet, compact: true),
          ),
        ],
      ),
    );
  }
}

/// 기존 8슬롯 그리드([EquipArea])와 완전히 분리된 가로로 긴 "특수 장비"
/// 영역 — 지금은 길드 전쟁 승리 휘장([EquipType.badge]) 전용 자리 하나뿐
/// 이지만, 이름 그대로 나중에 다른 기간제/특수 장비가 추가돼도 이 Row에
/// 슬롯만 더 얹으면 된다. 휘장은 유저의 가장 큰 명예이자 스펙업 수단이라
/// (요구사항) 슬롯이 차 있을 때는 금색 글로우로 항상 상시 눈에 띄게
/// 강조한다 — [RookieAttendanceManager] 7일차 타일과 같은 "특별한 걸
/// 손에 넣었다" 강조 관례.
class _SpecialEquipRow extends StatelessWidget {
  const _SpecialEquipRow({required this.badge, required this.onTap});

  final Equipment? badge;
  final ValueChanged<Equipment> onTap;

  @override
  Widget build(BuildContext context) {
    final bool hasBadge = badge != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF20202C),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasBadge ? const Color(0xFFFFD54F) : const Color(0xFF3A3A4A),
            width: hasBadge ? 1.5 : 1,
          ),
          boxShadow: hasBadge
              ? [
                  BoxShadow(
                    color: const Color(0xFFFFD54F).withValues(alpha: 0.5),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            const Icon(Icons.workspace_premium, color: Color(0xFFFFD54F), size: 18),
            const SizedBox(width: 8),
            const Text(
              '특수 장비',
              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const Spacer(),
            EquipSlot(
              label: '휘장',
              icon: Icons.military_tech,
              item: badge,
              size: 56,
              onTap: hasBadge ? () => onTap(badge!) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class EquipSlot extends StatelessWidget {
  const EquipSlot({
    super.key,
    required this.label,
    required this.icon,
    this.item,
    this.onTap,
    this.size = 64,
  });

  final String label;
  final IconData icon;
  final Equipment? item;
  final VoidCallback? onTap;

  /// 슬롯 한 변의 길이 — 아이콘/글자 크기는 이 값에 비례해 함께 줄어든다.
  final double size;

  @override
  Widget build(BuildContext context) {
    final Equipment? equipped = item;
    final bool hasItem = equipped != null;
    final Color gradeColor = hasItem ? getGradeColor(equipped.grade) : Colors.white24;
    final Gradient? gradeGradient =
        hasItem ? getGradeBorderStyle(equipped.grade).gradient : null;
    // 텍스트(등급명/부위명) 없이, 부위에 맞는 아이콘 하나를 슬롯 중앙에
    // 크게 배치한다 — 비어있으면 연한 회색, 장착 중이면 등급색.
    final double iconSize = size * (34 / 64);

    final Widget innerContent = Stack(
      children: [
        Center(
          child: Icon(icon, color: hasItem ? gradeColor : Colors.white38, size: iconSize),
        ),
        if (hasItem)
          Positioned(
            top: 4,
            left: 4,
            child: _GradeBadge(item: equipped, compact: true),
          ),
        if (hasItem && equipped.level > 0)
          Positioned(
            top: 4,
            right: 4,
            child: _LevelBadge(level: equipped.level, compact: true),
          ),
        if (hasItem && equipped.star > 0)
          Positioned(
            bottom: 2,
            left: 0,
            right: 0,
            child: _StarBadge(star: equipped.star, compact: true),
          ),
      ],
    );

    // 안쪽으로 파인 느낌을 주는 인셋(네거티브) 그림자 — BlurStyle.inner로
    // 슬롯 안쪽 테두리를 따라 그림자가 지도록 해서 "움푹 들어간 소켓"
    // 느낌을 낸다. 모든 슬롯(빈 슬롯 포함)에 동일하게 적용해 배경이
    // 일관되게 어둡다.
    final List<BoxShadow> insetShadow = [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.7),
        blurRadius: 6,
        spreadRadius: -2,
        blurStyle: BlurStyle.inner,
      ),
    ];
    const Color slotBackground = Color(0xFF0C0C11);

    // UR/LR(그라데이션 등급)만 얇은 그라데이션 링이 필요해 중첩 Container를
    // 쓴다 — 그 외(빈 슬롯 포함)는 배경이 짙은 단색이고 Border.all() 선만
    // 두르는 훨씬 가벼운 구조다.
    final Widget tile = gradeGradient != null
        ? Container(
            width: size,
            height: size,
            padding: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              gradient: gradeGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: slotBackground,
                borderRadius: BorderRadius.circular(9),
                boxShadow: insetShadow,
              ),
              child: innerContent,
            ),
          )
        : Container(
            width: size,
            height: size,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: slotBackground,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: gradeColor, width: 1.5),
              boxShadow: insetShadow,
            ),
            child: innerContent,
          );

    // 아이콘만 남기고 텍스트 라벨을 지웠으니, 스크린 리더에는 여전히
    // 부위 이름(label)이 읽히도록 Semantics로 보존한다.
    return Semantics(
      label: hasItem ? '$label, ${equipped.grade.displayName} 등급' : label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: tile,
      ),
    );
  }
}

class StatPanel extends StatelessWidget {
  const StatPanel({super.key});

  /// 스탯 수치를 강조하는 메인 네온 컬러 3종 — 공격 계열은 청록, 크리티컬
  /// 계열은 노랑, 방어/생존 계열은 민트그린으로 묶어서 잡다한 팔레트 대신
  /// 통일감을 준다.
  static const Color _neonCyan = Color(0xFF22E5D8);
  static const Color _neonYellow = Color(0xFFFFE14D);
  static const Color _neonMint = Color(0xFF4DFFB0);

  @override
  Widget build(BuildContext context) {
    final GameManager manager = GameManager.instance;

    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        // 예전엔 이 Container를 고정 높이(140) SizedBox 안에 넣고 Column을
        // spaceEvenly로 4행에 억지로 펼쳐서, 좁은 화면/큰 글꼴 설정에서
        // 실제 필요한 높이가 그 140을 넘으면 "Bottom Overflowed" 경고가
        // 났었다. 높이를 강제하지 않는 것만으로도 대부분의 경우 해결되지만
        // (바깥 CharacterScreen 본문이 이미 SingleChildScrollView라 스스로
        // 스크롤을 감당함), 이 패널이 나중에 높이가 제한된 다이얼로그 등
        // 다른 곳에 재사용될 가능성까지 방어하기 위해 Column 자체를
        // SingleChildScrollView로 한 번 더 감싼다 — 부모가 준 세로 공간이
        // 얼마든(무제한이든 특정 값으로 제한되든) 절대 노란 빗금 오버플로가
        // 나지 않고, 정말 모자랄 때만 조용히 스크롤된다. 평소(공간이 충분할
        // 때)는 스크롤이 필요 없도록 행 사이 간격/여백도 함께 줄였다.
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF24242E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF34344A), width: 1),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StatItem(
                        label: '총 공격력',
                        value: NumberFormatter.format(manager.attackPower),
                        icon: Icons.local_fire_department,
                        color: _neonCyan,
                      ),
                    ),
                    Expanded(
                      child: _StatItem(
                        label: '공격 속도',
                        value: '${manager.effectiveAttackSpeed.toStringAsFixed(2)}/s',
                        icon: Icons.bolt,
                        color: _neonCyan,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _StatItem(
                        label: '크리티컬 확률',
                        value:
                            '${(manager.criticalRate * 100).toStringAsFixed(0)}%',
                        icon: Icons.flash_on,
                        color: _neonYellow,
                      ),
                    ),
                    Expanded(
                      child: _StatItem(
                        label: '크리티컬 데미지',
                        value:
                            '${(manager.criticalMultiplier * 100).toStringAsFixed(0)}%',
                        icon: Icons.whatshot,
                        color: _neonYellow,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _StatItem(
                        label: '방어력',
                        value: NumberFormatter.format(manager.defensePower),
                        icon: Icons.shield,
                        color: _neonMint,
                      ),
                    ),
                    Expanded(
                      child: _StatItem(
                        label: '방어율',
                        value: '${(manager.effectiveDefenseRate * 100).toStringAsFixed(0)}%',
                        icon: Icons.security,
                        color: _neonMint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _StatItem(
                        label: '회피율',
                        value: '${(manager.effectiveEvasionRate * 100).toStringAsFixed(0)}%',
                        icon: Icons.directions_run,
                        color: _neonMint,
                      ),
                    ),
                    Expanded(
                      child: _StatItem(
                        label: '크리티컬 방어율',
                        value:
                            '${(manager.effectiveCritDefenseRate * 100).toStringAsFixed(0)}%',
                        icon: Icons.gpp_good,
                        color: _neonMint,
                      ),
                    ),
                  ],
                ),
                const _ActiveSetBonusRow(),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 지금 발동 중인 세트 효과를 칩으로 나열 — 하나도 없으면(장착 중인 세트
/// 장비가 2부위 미만이면) 자리 자체를 차지하지 않는다.
class _ActiveSetBonusRow extends StatelessWidget {
  const _ActiveSetBonusRow();

  @override
  Widget build(BuildContext context) {
    final List<ActiveSetBonus> bonuses = EquipmentSetManager.instance
        .activeBonuses(EquipmentManager.instance.equippedSetCounts);
    if (bonuses.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final ActiveSetBonus bonus in bonuses)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF6C4FCE).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF8A6FE0)),
              ),
              child: Text(
                bonus.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class InventoryArea extends StatelessWidget {
  const InventoryArea({
    super.key,
    required this.inventory,
    this.onSlotTap,
  });

  final List<Equipment> inventory;
  final ValueChanged<Equipment>? onSlotTap;

  static const int _minSlotCount = 20;

  // ── 그리드 타일 크기 계산에 쓰는 상수 — build()의 gridDelegate와
  // [tileSizeFor]가 반드시 같은 값을 참조해야 한다(하나만 고치고 다른
  // 쪽을 잊으면 다시 어긋난다).
  static const int _crossAxisCount = 6;
  static const double _crossAxisSpacing = 8.0;
  static const double _containerPadding = 12.0;

  /// 인벤토리 그리드의 실제 타일 한 변 길이 — 이 위젯은 화면 폭을 꽉 채워
  /// 그려지므로([_CharacterScreenState._buildCharacterBody]에서 좌우
  /// Padding 없이 바로 배치됨), `SliverGridDelegateWithFixedCrossAxisCount`
  /// 가 매 프레임 실제로 계산하는 타일 크기를 여기서 그대로 역산한다.
  /// 화면 폭이 기기마다 다르므로 타일도 기기마다 다른데, 상세 팝업 헤더
  /// 썸네일처럼 "인벤토리 타일과 완전히 같은 크기"가 필요한 다른 화면은
  /// 고정 픽셀값(예: 72) 대신 반드시 이 함수를 호출해야 실제로 일치한다.
  static double tileSizeFor(BuildContext context) {
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final double gridWidth = screenWidth - _containerPadding * 2;
    final double totalSpacing = _crossAxisSpacing * (_crossAxisCount - 1);
    return (gridWidth - totalSpacing) / _crossAxisCount;
  }

  @override
  Widget build(BuildContext context) {
    final int totalSlots =
        inventory.length > _minSlotCount ? inventory.length : _minSlotCount;

    return Container(
      padding: const EdgeInsets.all(_containerPadding),
      decoration: const BoxDecoration(
        color: Color(0xFF1B1B26),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: GridView.builder(
        itemCount: totalSlots,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _crossAxisCount,
          crossAxisSpacing: _crossAxisSpacing,
          mainAxisSpacing: 8.0,
          childAspectRatio: 1.0,
        ),
        itemBuilder: (context, index) {
          final Equipment? item =
              index < inventory.length ? inventory[index] : null;
          return InventorySlot(
            item: item,
            onTap: item == null ? null : () => onSlotTap?.call(item),
          );
        },
      ),
    );
  }
}

class InventorySlot extends StatelessWidget {
  const InventorySlot({
    super.key,
    required this.item,
    this.onTap,
  });

  final Equipment? item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Equipment? currentItem = item;
    final bool hasItem = currentItem != null;
    final bool isCharacter = hasItem && currentItem.type == EquipType.character;
    final Color gradeColor = hasItem ? getGradeColor(currentItem.grade) : Colors.white24;
    final Gradient? gradeGradient =
        hasItem ? getGradeBorderStyle(currentItem.grade).gradient : null;

    // 캐릭터 아이템은 타입 이름 텍스트 대신 정면 이미지를 슬롯 전체에 꽉
    // 채워서 보여준다(아직 그림이 없는 등급은 CustomSafeImage가 알아서
    // placeholder로 대체). 그 외 타입은 기존처럼 흰 텍스트 + 검정 이중
    // 그림자만으로 가독성을 준다. 아이템이 없을 때는 흐릿한 자리표시
    // 아이콘만 보여준다.
    final Widget innerContent = hasItem
        ? Stack(
            children: [
              if (isCharacter)
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: CharacterFacePortrait(
                      characterId: currentItem.gradeBadgeLabel,
                      borderRadius: 6,
                    ),
                  ),
                )
              else
                Center(
                  child: Text(
                    currentItem.type.displayName,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(color: Colors.black, blurRadius: 3.0, offset: Offset(1.0, 1.0)),
                        Shadow(color: Colors.black, blurRadius: 3.0, offset: Offset(-1.0, -1.0)),
                      ],
                    ),
                  ),
                ),
              Positioned(
                top: 4,
                left: 4,
                child: _GradeBadge(item: currentItem),
              ),
              if (currentItem.level > 0)
                Positioned(
                  top: 4,
                  right: 4,
                  child: _LevelBadge(level: currentItem.level),
                ),
              if (currentItem.star > 0)
                Positioned(
                  bottom: 2,
                  left: 0,
                  right: 0,
                  child: _StarBadge(star: currentItem.star),
                ),
            ],
          )
        : const Center(
            child: Icon(Icons.category, color: Colors.white24, size: 22),
          );

    // UR/LR(그라데이션 등급)만 얇은 그라데이션 링이 필요해 중첩 Container를
    // 쓴다 — 그 외(빈 슬롯 포함)는 배경이 검정/투명이고 Border.all() 선만
    // 두르는 훨씬 가벼운 구조라 "네모난 회색 박스"가 생기지 않는다.
    final Widget tile = gradeGradient != null
        ? Container(
            padding: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              gradient: gradeGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(7),
              ),
              child: innerContent,
            ),
          )
        : Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: hasItem ? Colors.black87 : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: gradeColor, width: 1.5),
            ),
            child: innerContent,
          );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: tile,
    );
  }
}

/// 인벤토리 타일/장착 슬롯(중앙 캐릭터·장비·펫) 공통으로 쓰는 "+N" 레벨
/// 뱃지 — 크기를 한 군데에서만 관리하도록 분리해 뒀다.
class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level, this.compact = false});

  final int level;

  /// true면 장착 슬롯(중앙 캐릭터/장비/펫)용 축소 크기, false면 인벤토리
  /// GridView용 기존 큼직한 크기.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Text(
      '+$level',
      style: TextStyle(
        color: Colors.yellowAccent,
        fontSize: compact ? 13 : 24,
        fontWeight: FontWeight.bold,
        shadows: const [
          Shadow(color: Colors.black, blurRadius: 4.0, offset: Offset(1.0, 1.0)),
          Shadow(color: Colors.black, blurRadius: 4.0, offset: Offset(-1.0, -1.0)),
        ],
      ),
    );
  }
}

/// 인벤토리 타일/장착 슬롯 공통으로 쓰는 "등급+넘버링" 뱃지(예: N1, SSR12,
/// LR5) — [_LevelBadge]와 좌우 대칭 위치(좌측 상단)에 놓이며 같은
/// 그림자-only 스타일을 공유한다.
class _GradeBadge extends StatelessWidget {
  const _GradeBadge({required this.item, this.compact = false});

  final Equipment item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Text(
      item.gradeBadgeLabel,
      style: TextStyle(
        color: getGradeColor(item.grade),
        fontSize: compact ? 9 : 13,
        fontWeight: FontWeight.bold,
        shadows: const [
          Shadow(color: Colors.black, blurRadius: 4.0, offset: Offset(1.0, 1.0)),
          Shadow(color: Colors.black, blurRadius: 4.0, offset: Offset(-1.0, -1.0)),
        ],
      ),
    );
  }
}

/// 타일 하단 중앙에 놓이는 별(성급) 표기 — 0이면 애초에 호출되지 않는다.
class _StarBadge extends StatelessWidget {
  const _StarBadge({required this.star, this.compact = false});

  final int star;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Text(
      Equipment.starText(star),
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.amberAccent,
        fontSize: compact ? 9 : 12,
        fontWeight: FontWeight.bold,
        shadows: const [
          Shadow(color: Colors.black, blurRadius: 4.0, offset: Offset(1.0, 1.0)),
          Shadow(color: Colors.black, blurRadius: 4.0, offset: Offset(-1.0, -1.0)),
        ],
      ),
    );
  }
}
