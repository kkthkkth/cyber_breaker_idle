import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../constants/app_images.dart';
import '../managers/affection_manager.dart';
import '../managers/consumable_manager.dart';
import '../managers/potion_manager.dart';
import '../models/consumable_item_model.dart';
import '../models/equipment.dart';
import '../models/shop_consumable_model.dart';
import '../widgets/center_toast.dart';
import '../widgets/illustration_viewer.dart';
import '../widgets/safe_image.dart';

/// 서브컬처(미연시)풍 캐릭터 호감도 화면 — [ItemDetailDialog]의 하트
/// 버튼에서 진입한다. 상단 진행 바+하트, 좌측 레벨 탭(잠금 포함), 중앙
/// 일러스트+'대화' 버튼, 하단 선물 슬롯 그리드로 구성된다.
///
/// 상태는 전부 [AffectionManager]/[ConsumableManager] 싱글턴이 들고 있고,
/// 이 위젯은 그 둘을 조작한 뒤 로컬 [setState]로 다시 그리기만 한다 —
/// 프로젝트 전체가 Provider 없이 이 패턴을 쓴다([ItemDetailDialog._toggleEquip]
/// 등 참고).
class AffectionScreen extends StatefulWidget {
  const AffectionScreen({super.key, required this.character});

  final Equipment character;

  @override
  State<AffectionScreen> createState() => _AffectionScreenState();
}

class _AffectionScreenState extends State<AffectionScreen> {
  final AffectionManager _manager = AffectionManager.instance;

  late int _selectedLevel;

  /// 오늘 남은 대화 횟수 — 화면을 열 때 한 번, 그리고 실제로 대화를
  /// "시작"했을 때([_openChat])만 갱신되는 독립된 State 필드다. 일러스트
  /// 재생/일시정지 토글은 이제 [IllustrationViewer] 내부에만 있는 상태라
  /// 이 화면은 그 값을 알지도 못한다 — 재생 버튼이 이 필드를 건드리는 일은
  /// 구조적으로 불가능하다(전에 있었던 "재생 누르면 대화 횟수가 사라지는"
  /// 버그의 재발 방지).
  late int _remainingChats;

  /// 대화 시작([_openChat]) 처리 중 잠금 — `await Navigator.push(...)`로
  /// 이어지는 비동기 구간이 있어서, 이 락이 없으면 그 구간 동안 대화
  /// 버튼을 연타했을 때 채팅 오버레이 라우트가 여러 장 겹쳐 쌓일 수 있다.
  /// 처리 중엔 버튼을 아예 비활성화해 추가 탭 자체를 막는다.
  bool _isChatInFlight = false;

  /// 선물([_gift]) 처리 중 잠금 — 지금은 동기적으로 끝나는 로직이라
  /// 실질적인 경쟁 상태는 없지만, 요구사항대로 명시적인 상태 잠금을 두어
  /// 연타 시 버튼이 반응하지 않게 하고, 앞으로 서버 호출 등 비동기 작업이
  /// 추가되더라도 안전하게 유지되도록 한다.
  bool _isGiftInFlight = false;

  /// 파티클이 날아가는 목적지 — 상단 하트 배지.
  final GlobalKey _heartKey = GlobalKey();

  /// 선물 슬롯 인덱스별 위치 조회용 — 파티클 출발점.
  final Map<int, GlobalKey> _giftSlotKeys = {};

  /// 상점에서 구매한 호감도 아이템([_ShopGiftGrid]) 전용 슬롯 키 —
  /// [_giftSlotKeys]와 인덱스 공간이 겹치면 안 되므로 별도 맵을 쓴다.
  final Map<int, GlobalKey> _shopGiftSlotKeys = {};

  String get _characterId => widget.character.gradeBadgeLabel;

  @override
  void initState() {
    super.initState();
    _selectedLevel = _manager
        .levelFor(_characterId)
        .clamp(1, AffectionManager.maxLevel);
    _remainingChats = _manager.remainingChatsToday(_characterId);
  }

  String _illustrationHeroTag(int level) =>
      'affection-illustration-$_characterId-$level';

  /// 서약(Oath) 완료 캐릭터는 전용 스킨 일러스트를 우선 시도한다 — 그
  /// 아트가 아직 없는 캐릭터는 [_staticFallbackImagePath]/
  /// [IllustrationViewer.staticFallbackImagePath]가 평소 일러스트로
  /// 조용히 대체해 준다.
  String _staticImagePath(int level) => _manager.isOathed(_characterId)
      ? AppImages.oathIllustration(_characterId, level)
      : AppImages.affectionIllustration(_characterId, level);

  String _animatedImagePath(int level) => _manager.isOathed(_characterId)
      ? AppImages.oathIllustrationAnimated(_characterId, level)
      : AppImages.affectionIllustrationAnimated(_characterId, level);

  /// 서약 상태가 아니면 애초에 [_staticImagePath]가 이미 평소 이미지라
  /// null(불필요) — 서약 상태일 때만 "전용 스킨이 없으면 평소 그림으로"
  /// 대체하는 fallback을 넘긴다.
  String? _staticFallbackImagePath(int level) => _manager.isOathed(_characterId)
      ? AppImages.affectionIllustration(_characterId, level)
      : null;

  void _selectLevel(int level) {
    if (!_manager.isLevelUnlocked(_characterId, level)) {
      showCenterToast(context, '아직 잠긴 레벨이에요. 호감도를 올려 해금해 보세요!');
      return;
    }
    setState(() => _selectedLevel = level);
  }

  Future<void> _openChat() async {
    // 연타 방지 — await Navigator.push 구간이 끝나기 전까지는 추가 탭을
    // 전부 무시한다. 버튼도 _isChatInFlight일 때 onPressed가 null이 되어
    // 애초에 눌리지 않지만, 그 사이 프레임 하나 정도의 틈까지 이중으로
    // 막기 위해 로직 진입부에서도 한 번 더 확인한다.
    if (_isChatInFlight) {
      return;
    }
    setState(() => _isChatInFlight = true);

    try {
      final String? line = _manager.beginChat(_characterId);
      if (line == null) {
        // 정상 흐름에서는 남은 횟수가 0이 되는 즉시 버튼이 비활성화(회색)
        // 되므로 이 분기를 탈 수 없어야 한다 — 그래도 혹시 [_remainingChats]
        // 캐시가 실제 상태와 어긋난 경우(예: 자정을 넘겨 화면이 계속
        // 떠있던 경우)에 대비해 여기서도 강제로 다시 동기화해 라벨/버튼
        // 색이 항상 실제 남은 횟수와 일치하도록 만든다.
        setState(() => _remainingChats = _manager.remainingChatsToday(_characterId));
        showCenterToast(
          context,
          '오늘은 더 대화할 수 없어요 (하루 최대 ${AffectionManager.maxChatsPerDay}회)',
        );
        return;
      }
      // 실제로 대화를 "시작"했을 때만 남은 횟수를 갱신한다 — 재생/일시정지
      // 토글([IllustrationViewer])은 이 필드를 아예 모른다.
      setState(() => _remainingChats = _manager.remainingChatsToday(_characterId));

      await Navigator.of(context).push(
        PageRouteBuilder<void>(
          opaque: false,
          barrierColor: Colors.black,
          transitionDuration: const Duration(milliseconds: 280),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (context, animation, secondaryAnimation) => _AffectionChatPage(
            characterName: widget.character.name,
            imagePath: _animatedImagePath(_selectedLevel),
            fallbackImagePath: _staticImagePath(_selectedLevel),
            heroTag: _illustrationHeroTag(_selectedLevel),
            line: line,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );

      // 실제로 게이지에 반영된 양 — 이미 만렙이었다면 0이 돌아온다
      // ([AffectionManager._applyGain] 참고). 그럴 땐 거짓으로 "+N%
      // 올랐어요"를 띄우지 않는다.
      final double gain = _manager.completeChat(_characterId);
      if (!mounted) {
        return;
      }
      setState(() {});
      showCenterToast(
        context,
        gain > 0 ? '호감도가 +${gain.toStringAsFixed(0)}% 올랐어요!' : '이미 최고 레벨이에요!',
      );
    } finally {
      if (mounted) {
        setState(() => _isChatInFlight = false);
      } else {
        _isChatInFlight = false;
      }
    }
  }

  Future<void> _gift(int slotIndex, ConsumableItem item) async {
    if (_isGiftInFlight) {
      return;
    }
    if (_manager.isMaxLevel(_characterId)) {
      // 만렙이면 아이템을 소모하지도 않고 그 자리에서 거절한다
      // ([AffectionManager.giftItem] 참고) — 여기서도 미리 걸러서 불필요한
      // 매니저 호출 자체를 생략한다.
      showCenterToast(context, '이미 최고 레벨이에요!');
      return;
    }

    // 상승 전 레벨을 미리 잡아 둬야 _manager.giftItem() 이후 값과 비교해
    // "이번 선물로 레벨이 실제로 올랐는지"(oldLevel < newLevel)를 판정할
    // 수 있다 — 한 번의 큰 상승치로 레벨이 여러 단계 오를 수도 있지만
    // (AffectionManager._applyGain 참고), 연출은 "올랐다/안 올랐다"만
    // 보여주면 되므로 최종 레벨 하나만 비교하면 충분하다.
    final int oldLevel = _manager.levelFor(_characterId);

    setState(() => _isGiftInFlight = true);
    try {
      final double? gain = _manager.giftItem(_characterId, item.type);
      if (gain == null) {
        // 재고 부족 등으로 거절된 경우 — 그리드가 재고 기준으로 그려지므로
        // 정상 흐름에서는 도달하기 어렵지만, 방어적으로 조용히 무시한다.
        return;
      }
      // setState보다 먼저 파티클 시작 좌표를 잡아야 한다 — 선물 후 재고가
      // 0이 되면 그리드에서 그 슬롯이 사라지며 뒤 슬롯들이 한 칸씩
      // 당겨지는데, setState 이후에는 같은 GlobalKey가 이미 다른 아이템
      // 위치를 가리키게 된다.
      _flyHeartParticles(fromKey: _giftSlotKeys[slotIndex]);
      setState(() {});
      showCenterToast(context, '호감도가 +${gain.toStringAsFixed(0)}% 올랐어요!');
      final int newLevel = _manager.levelFor(_characterId);
      if (newLevel > oldLevel) {
        _showLevelUpEffect(newLevel);
      }
    } finally {
      if (mounted) {
        setState(() => _isGiftInFlight = false);
      } else {
        _isGiftInFlight = false;
      }
    }
  }

  /// [_gift]와 같은 모양의 상점 호감도 아이템 선물 처리 — 재고 출처만
  /// [PotionManager]로 다르다([AffectionManager.giftShopItem] 참고). 같은
  /// [_isGiftInFlight] 락을 공유해서, 두 그리드 중 어느 쪽을 연타해도 한
  /// 번에 하나씩만 처리된다.
  Future<void> _giftShop(int slotIndex, ShopConsumableEntry entry) async {
    if (_isGiftInFlight) {
      return;
    }
    if (_manager.isMaxLevel(_characterId)) {
      showCenterToast(context, '이미 최고 레벨이에요!');
      return;
    }

    final int oldLevel = _manager.levelFor(_characterId);

    setState(() => _isGiftInFlight = true);
    try {
      final double? gain = await _manager.giftShopItem(_characterId, entry);
      if (!mounted) {
        return;
      }
      if (gain == null) {
        return;
      }
      _flyHeartParticles(fromKey: _shopGiftSlotKeys[slotIndex]);
      setState(() {});
      showCenterToast(context, '호감도가 +${gain.toStringAsFixed(0)}% 올랐어요!');
      final int newLevel = _manager.levelFor(_characterId);
      if (newLevel > oldLevel) {
        _showLevelUpEffect(newLevel);
      }
    } finally {
      if (mounted) {
        setState(() => _isGiftInFlight = false);
      } else {
        _isGiftInFlight = false;
      }
    }
  }

  /// 서약([_tryOath]) 처리 중 잠금 — 다른 액션들과 같은 연타 방지 패턴.
  bool _isOathInFlight = false;

  /// 만렙에서 노출되는 "[서약하기]" 버튼의 동작 — 인벤토리의 서약 반지를
  /// 1개 소모해 [AffectionData.isOathed]를 영구 true로 바꾼다. 성공하면
  /// 스킨 일러스트가 곧바로 서약 전용 아트로 바뀐다([_staticImagePath]가
  /// [AffectionManager.isOathed]를 다시 읽으므로 별도 상태 동기화가
  /// 필요 없다 — setState 한 번으로 전부 갱신됨).
  Future<void> _tryOath() async {
    if (_isOathInFlight) {
      return;
    }
    if (!_manager.canOath(_characterId)) {
      // 정상 흐름에서는 조건 충족일 때만 버튼 자체가 보이므로 도달하기
      // 어렵지만, 방어적으로 조용히 무시한다.
      return;
    }

    setState(() => _isOathInFlight = true);
    try {
      final bool success = _manager.tryOath(_characterId);
      if (!success) {
        showCenterToast(context, '서약의 반지가 없어요.');
        return;
      }
      setState(() {});
      showCenterToast(context, '${widget.character.name}와(과) 서약했어요!');
    } finally {
      if (mounted) {
        setState(() => _isOathInFlight = false);
      } else {
        _isOathInFlight = false;
      }
    }
  }

  void _flyHeartParticles({required GlobalKey? fromKey}) {
    final RenderBox? fromBox =
        fromKey?.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? toBox =
        _heartKey.currentContext?.findRenderObject() as RenderBox?;
    if (fromBox == null || toBox == null || !fromBox.attached || !toBox.attached) {
      return;
    }

    final Offset start = fromBox.localToGlobal(fromBox.size.center(Offset.zero));
    final Offset end = toBox.localToGlobal(toBox.size.center(Offset.zero));

    final OverlayState overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) =>
          _HeartBurst(start: start, end: end, onDone: () => entry.remove()),
    );
    overlay.insert(entry);
  }

  /// 선물로 호감도 레벨이 실제로 올랐을 때(`oldLevel < newLevel`)만
  /// [_gift]/[_giftShop]이 호출한다 — [_flyHeartParticles]와 같은
  /// self-removing [OverlayEntry] 패턴으로, 화면 전체(rootOverlay)를 덮는
  /// 최상단에 잠깐 떴다가 애니메이션이 끝나면 스스로 사라진다.
  void _showLevelUpEffect(int newLevel) {
    final OverlayState overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) =>
          _LevelUpCelebration(newLevel: newLevel, onDone: () => entry.remove()),
    );
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    final double percent = _manager.percentFor(_characterId);

    return Scaffold(
      backgroundColor: const Color(0xFF14141C),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          '${widget.character.name} · 호감도',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _ProgressHeader(heartKey: _heartKey, percent: percent),
            const SizedBox(height: 4),
            // 상단(캐릭터 일러스트+레벨 탭)과 아래 선물 영역이 각자
            // 고정된 flex 비중으로 화면 높이를 나눠 가진다 — 예전엔 이
            // 위쪽 Expanded 하나가 남는 공간을 전부 차지하고, 선물
            // 그리드는 shrinkWrap으로 내용물 크기만큼 그대로 밀어 넣는
            // 구조였다. 그래서 선물 종류가 늘어나 그리드가 2줄을 넘어가면
            // 그만큼 위쪽 Expanded가 눌려 일러스트/게이지 영역이
            // 찌그러졌다. 이제 선물 영역도 자기만의 Expanded 안에서
            // 독립적으로 스크롤되므로([_GiftSection]), 선물 종류가 아무리
            // 늘어나도 위쪽 캐릭터 영역 크기는 항상 그대로 고정된다.
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LevelTabColumn(
                      characterId: _characterId,
                      manager: _manager,
                      selectedLevel: _selectedLevel,
                      onSelect: _selectLevel,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B1B26),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: IllustrationViewer(
                            heroTag: _illustrationHeroTag(_selectedLevel),
                            staticImagePath: _staticImagePath(_selectedLevel),
                            staticFallbackImagePath: _staticFallbackImagePath(_selectedLevel),
                            animatedImagePath: _animatedImagePath(_selectedLevel),
                            fit: BoxFit.cover,
                            overlays: [
                              Positioned(
                                right: 12,
                                bottom: 12,
                                child: _ChatButton(
                                  remainingChats: _remainingChats,
                                  enabled: !_isChatInFlight,
                                  onChat: _openChat,
                                ),
                              ),
                              // 서약 완료 캐릭터는 항상 우측 상단에 반지
                              // 뱃지를 띄운다 — 다른 화면(캐릭터 그리드,
                              // 상세 팝업 등)에도 같은 표시를 넣고 싶다면
                              // AffectionManager.isOathed(characterId)를
                              // 그대로 재사용하면 된다.
                              if (_manager.isOathed(_characterId))
                                const Positioned(
                                  top: 10,
                                  right: 10,
                                  child: _OathBadge(),
                                ),
                              // 만렙 + 아직 서약 안 함일 때만 중앙에 노출.
                              if (_manager.canOath(_characterId))
                                Positioned.fill(
                                  child: Align(
                                    alignment: Alignment.center,
                                    child: _OathButton(
                                      enabled: !_isOathInFlight,
                                      onTap: _tryOath,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 3,
              // 처리 중(_isGiftInFlight)에는 영역 전체 터치 무시 — 연타로
              // 여러 슬롯을 동시에 두들겨도 한 번에 하나씩만 처리된다.
              child: IgnorePointer(
                ignoring: _isGiftInFlight,
                child: _GiftSection(
                  giftSlotKeys: _giftSlotKeys,
                  shopGiftSlotKeys: _shopGiftSlotKeys,
                  onTapGift: _gift,
                  onTapShopGift: _giftShop,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 상단 진행 바 + 우측 끝 호감도% 하트 배지.
class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.heartKey, required this.percent});

  final GlobalKey heartKey;
  final double percent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 16,
                child: Stack(
                  children: [
                    Container(color: const Color(0xFF2A2A38)),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (percent / 100).clamp(0, 1),
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFFFF9EC4), Color(0xFFFF3D71)],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _HeartPercentBadge(key: heartKey, percent: percent),
        ],
      ),
    );
  }
}

class _HeartPercentBadge extends StatelessWidget {
  const _HeartPercentBadge({super.key, required this.percent});

  final double percent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(Icons.favorite, color: Color(0xFFFF6FA5), size: 40),
          Text(
            '${percent.toInt()}%',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 10,
              shadows: [Shadow(color: Colors.black87, blurRadius: 3)],
            ),
          ),
        ],
      ),
    );
  }
}

/// 좌측 세로 레벨 탭 — 해금된 레벨은 라벨을, 잠긴 레벨은 자물쇠 아이콘을
/// 보여주고 탭이 막힌다.
class _LevelTabColumn extends StatelessWidget {
  const _LevelTabColumn({
    required this.characterId,
    required this.manager,
    required this.selectedLevel,
    required this.onSelect,
  });

  final String characterId;
  final AffectionManager manager;
  final int selectedLevel;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      child: ListView.builder(
        itemCount: AffectionManager.maxLevel,
        itemBuilder: (context, index) {
          final int level = index + 1;
          final bool unlocked = manager.isLevelUnlocked(characterId, level);
          final bool selected = level == selectedLevel;
          final String label =
              level == AffectionManager.maxLevel ? 'MAX' : 'Lv.$level';

          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              onTap: () => onSelect(level),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFFF6FA5).withValues(alpha: 0.28)
                      : Colors.black38,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? const Color(0xFFFF6FA5) : Colors.white24,
                    width: selected ? 1.6 : 1,
                  ),
                ),
                child: unlocked
                    ? Text(
                        label,
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      )
                    : const Icon(Icons.lock, color: Colors.white38, size: 16),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 우측 하단 '대화' 버튼 — [IllustrationViewer] 내부의 재생/일시정지
/// 상태와는 완전히 무관한, 별개 위젯으로 분리해 뒀다(이 위젯은 그 상태를
/// 아예 알 수도 없다 — 재생 버튼은 IllustrationViewer 자체 State 안에만
/// 있다). 활성화
/// 여부/색상을 결정하는 조건은 오직 [remainingChats]뿐이다 — 이 위젯은
/// `isPlaying` 값을 아예 파라미터로 받지도 않으므로, 구조적으로 재생
/// 상태가 이 버튼에 영향을 줄 수 없다.
class _ChatButton extends StatelessWidget {
  const _ChatButton({
    required this.remainingChats,
    required this.enabled,
    required this.onChat,
  });

  final int remainingChats;

  /// 처리 중(연타 방지 락)에는 false — [remainingChats]가 남아있어도
  /// 눌리지 않는다.
  final bool enabled;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final bool canChat = remainingChats > 0 && enabled;

    return ElevatedButton.icon(
      onPressed: canChat ? onChat : null,
      icon: const Icon(Icons.chat_bubble, size: 18),
      label: Text('대화 ($remainingChats/${AffectionManager.maxChatsPerDay})'),
      style: ElevatedButton.styleFrom(
        // 활성/비활성 색은 Flutter의 disabled-state 색 해석에 기대지 않고
        // canChat 하나로 직접 정한다 — "오늘 남은 대화 횟수가 0회일 때만
        // 회색" 조건을 코드에서 눈으로 바로 확인할 수 있게 하기 위함.
        backgroundColor: canChat ? const Color(0xFFFF6FA5) : Colors.black45,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.black45,
        disabledForegroundColor: Colors.white54,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

/// 만렙 + 아직 서약 안 함일 때 일러스트 중앙에 뜨는 "[서약하기]" 버튼 —
/// [AffectionScreen._tryOath]가 인벤토리의 서약 반지를 소모해
/// [AffectionData.isOathed]를 영구 true로 바꾼다.
class _OathButton extends StatelessWidget {
  const _OathButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: enabled ? onTap : null,
      icon: const Icon(Icons.diamond, size: 20),
      label: const Text('서약하기'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFE0B84D),
        foregroundColor: Colors.black87,
        disabledBackgroundColor: Colors.black45,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 6,
      ),
    );
  }
}

/// 서약 완료 캐릭터의 일러스트 우측 상단에 상시로 뜨는 반지 뱃지 — 서약
/// 여부를 다른 화면(캐릭터 그리드, 아이템 상세 등)에도 표시하고 싶다면
/// 이 위젯을 그대로 재사용하거나, 같은 조건(`AffectionManager.instance
/// .isOathed(characterId)`)으로 비슷한 뱃지를 얹으면 된다.
class _OathBadge extends StatelessWidget {
  const _OathBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE0B84D), width: 1.4),
      ),
      child: const Icon(Icons.diamond, color: Color(0xFFE0B84D), size: 15),
    );
  }
}

/// 하단 "선물하기"(+상점에서 산 호감도 아이템) 영역 전체 — 위쪽 캐릭터
/// 일러스트 영역과 화면을 나눠 가지는 자신만의 [Expanded] 안에서, 선물
/// 종류가 아무리 많아져도 그 몫을 넘지 않고 [CustomScrollView]로 내부에서만
/// 세로 스크롤된다(둘 다 6열 그리드라 한 화면에 안 잡히면 함께 스크롤).
/// 그리드 타일 크기/여백은 기본 인벤토리 화면([InventoryArea])의 6열
/// 그리드와 동일하게(`crossAxisCount: 6`, spacing 8) 맞췄다. 보유한 선물이
/// 하나도 없으면(두 리스트 모두 빈 경우) 빈 슬롯을 나열하는 대신 화면
/// 중앙에 안내 문구만 띄운다.
class _GiftSection extends StatelessWidget {
  const _GiftSection({
    required this.giftSlotKeys,
    required this.shopGiftSlotKeys,
    required this.onTapGift,
    required this.onTapShopGift,
  });

  final Map<int, GlobalKey> giftSlotKeys;
  final Map<int, GlobalKey> shopGiftSlotKeys;
  final void Function(int slotIndex, ConsumableItem item) onTapGift;
  final void Function(int slotIndex, ShopConsumableEntry entry) onTapShopGift;

  /// 보유한 선물 종류가 적어도 그리드가 너무 허전해 보이지 않도록 채워
  /// 두는 최소 칸 수 — [InventoryArea._minSlotCount]와 같은 성격이다.
  /// 6열 기준 2줄(12칸). 실제 보유 종류가 이보다 많으면 그만큼 그대로
  /// 늘어난다(예전엔 슬롯 수가 8로 고정돼 있어 9종류 이상 보유하면 뒤쪽
  /// 아이템이 그리드에 아예 표시되지 않는 잠재적 문제가 있었다).
  static const int _minGiftSlots = 12;

  static const SliverGridDelegateWithFixedCrossAxisCount _gridDelegate =
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
      );

  @override
  Widget build(BuildContext context) {
    final List<ConsumableItem> gifts = ConsumableManager.instance.inventory
        .where(
          (item) => AffectionManager.giftTypes.contains(item.type) && item.count > 0,
        )
        .toList();
    final List<ShopConsumableEntry> shopGifts = PotionManager.instance.affectionGifts
        .where((entry) => PotionManager.instance.countOf(entry.id) > 0)
        .toList();

    if (gifts.isEmpty && shopGifts.isEmpty) {
      return const Center(
        child: Text(
          '선물할 아이템이 없습니다',
          style: TextStyle(color: Colors.white38, fontSize: 14, fontWeight: FontWeight.bold),
        ),
      );
    }

    final int giftSlotCount = max(gifts.length, _minGiftSlots);

    return CustomScrollView(
      slivers: [
        if (gifts.isNotEmpty) ...[
          const SliverToBoxAdapter(child: _GiftSectionLabel('선물하기')),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: _gridDelegate,
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index >= gifts.length) {
                    return const _EmptyGiftSlot();
                  }
                  final ConsumableItem item = gifts[index];
                  final GlobalKey key = giftSlotKeys.putIfAbsent(index, () => GlobalKey());
                  return _GiftSlot(
                    key: key,
                    item: item,
                    onTap: () => onTapGift(index, item),
                  );
                },
                childCount: giftSlotCount,
              ),
            ),
          ),
        ],
        if (shopGifts.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          const SliverToBoxAdapter(child: _GiftSectionLabel('상점 선물')),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: _gridDelegate,
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final ShopConsumableEntry entry = shopGifts[index];
                  final GlobalKey key = shopGiftSlotKeys.putIfAbsent(index, () => GlobalKey());
                  return _ShopGiftSlot(
                    key: key,
                    entry: entry,
                    onTap: () => onTapShopGift(index, entry),
                  );
                },
                childCount: shopGifts.length,
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ],
    );
  }
}

class _GiftSectionLabel extends StatelessWidget {
  const _GiftSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
    );
  }
}

/// 기본 인벤토리 화면의 [InventorySlot](비-그라데이션 등급 분기)과 같은
/// 타일 디자인 — padding 3 / radius 8 / border 1.5px. 등급 개념이 없는
/// 소모품이라 테두리 색만 그레이드색 대신 이 화면의 핑크 테마색을 쓴다.
class _GiftSlot extends StatelessWidget {
  const _GiftSlot({super.key, required this.item, required this.onTap});

  final ConsumableItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFF6FA5), width: 1.5),
        ),
        child: Stack(
          children: [
            Center(
              child: Icon(item.type.icon, color: const Color(0xFFFF6FA5), size: 22),
            ),
            Positioned(
              right: 2,
              bottom: 0,
              child: Text(
                'x${item.count}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [InventorySlot]의 빈 슬롯(아이템 없음) 분기와 같은 디자인 —
/// 투명 배경 + 옅은 테두리.
class _EmptyGiftSlot extends StatelessWidget {
  const _EmptyGiftSlot();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24, width: 1.5),
      ),
    );
  }
}

/// [_GiftSlot]과 같은 역할이지만 재고 출처가 [PotionManager](상점에서
/// 구매한 `item_type == 'affection'` 아이템)다. 보유한 개수만큼만
/// 그려지므로(빈 슬롯을 채우지 않음) 아이템이 하나도 없으면
/// [_GiftSection]이 이 위젯 자체를 호출하지 않는다.
class _ShopGiftSlot extends StatelessWidget {
  const _ShopGiftSlot({super.key, required this.entry, required this.onTap});

  final ShopConsumableEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final int owned = PotionManager.instance.countOf(entry.id);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFF6FA5), width: 1.5),
        ),
        child: Stack(
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CustomSafeImage(path: entry.iconPath, width: 22, height: 22),
              ),
            ),
            Positioned(
              right: 2,
              bottom: 0,
              child: Text(
                'x$owned',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// '대화' 버튼으로 진입하는 미연시풍 전체화면 — 일러스트가 화면을 꽉
/// 채우고, 하단에 반투명 텍스트 박스로 대사가 뜬다. 아무 곳이나 탭하면
/// 닫힌다.
class _AffectionChatPage extends StatelessWidget {
  const _AffectionChatPage({
    required this.characterName,
    required this.imagePath,
    required this.fallbackImagePath,
    required this.heroTag,
    required this.line,
  });

  final String characterName;
  final String imagePath;
  final String fallbackImagePath;
  final Object heroTag;
  final String line;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: Material(
        color: Colors.black,
        child: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: heroTag,
                child: CustomSafeImage(
                  path: imagePath,
                  fallbackPath: fallbackImagePath,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.none,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        characterName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFF9EC4),
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        line,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '탭하여 닫기',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 선물 슬롯에서 상단 하트 배지로 날아가 터지는 하트 파티클 이펙트.
/// 종료되면 [onDone]으로 자기 자신(OverlayEntry)을 제거해 달라고 알린다.
class _HeartBurst extends StatefulWidget {
  const _HeartBurst({required this.start, required this.end, required this.onDone});

  final Offset start;
  final Offset end;
  final VoidCallback onDone;

  @override
  State<_HeartBurst> createState() => _HeartBurstState();
}

class _HeartBurstState extends State<_HeartBurst> with SingleTickerProviderStateMixin {
  static const int _heartCount = 7;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  late final List<double> _delays = List.generate(_heartCount, (i) => i * 0.06);
  late final List<double> _xJitter = List.generate(
    _heartCount,
    (i) => (Random(i).nextDouble() - 0.5) * 60,
  );

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onDone();
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          for (int i = 0; i < _heartCount; i++)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final double delay = _delays[i];
                final double t = ((_controller.value - delay) / (1 - delay))
                    .clamp(0.0, 1.0);
                final double eased = Curves.easeOutCubic.transform(t);
                final double x =
                    lerpDouble(widget.start.dx, widget.end.dx, eased)! +
                    _xJitter[i] * (1 - eased);
                final double y =
                    lerpDouble(widget.start.dy, widget.end.dy, eased)! -
                    sin(eased * pi) * 40;
                final double opacity = t < 0.85 ? 1.0 : (1 - (t - 0.85) / 0.15);
                final double bump = 1 - (eased - 0.5).abs() * 2;
                final double scale = 0.6 + 0.6 * bump.clamp(0.0, 1.0);

                return Positioned(
                  left: x - 12,
                  top: y - 12,
                  child: Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: scale,
                      child: const Icon(
                        Icons.favorite,
                        color: Color(0xFFFF6FA5),
                        size: 24,
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// 선물로 호감도 레벨이 실제로 오른 순간([_AffectionScreenState._showLevelUpEffect])
/// 화면 전체(rootOverlay)를 잠깐 덮는 축하 연출 — 단일 [AnimationController]
/// 하나의 진행률(0.0~1.0)을 [Interval]로 구간을 나눠, 중앙 텍스트 팝업(튕기며
/// 등장 → 유지 → 위로 슬라이드하며 페이드아웃)과 하트 파티클 폭죽을 동시에
/// 굴린다([_HeartBurst]와 같은 self-removing [OverlayEntry] 패턴이지만,
/// 저건 점→점으로 날아가는 연출이고 이건 중심에서 사방으로 터지는 연출이라
/// 별도 위젯으로 뒀다). 컨트롤러가 끝나면(status==completed) [onDone]으로
/// 스스로 제거해 달라고 알리고, 화면을 벗어나도 [dispose]가 컨트롤러를
/// 확실히 해제한다.
class _LevelUpCelebration extends StatefulWidget {
  const _LevelUpCelebration({required this.newLevel, required this.onDone});

  final int newLevel;
  final VoidCallback onDone;

  @override
  State<_LevelUpCelebration> createState() => _LevelUpCelebrationState();
}

class _LevelUpCelebrationState extends State<_LevelUpCelebration>
    with SingleTickerProviderStateMixin {
  // 팝업 등장(0~12%) → 유지 → 위로 슬라이드하며 페이드아웃(73~100%, 총
  // 2.6초 기준 약 1.9초 뒤 시작 — 요구사항의 "1.5~2초 뒤 페이드아웃").
  static const Duration _duration = Duration(milliseconds: 2600);
  static const int _heartCount = 12;

  // 하트들이 중심에서 퍼져나가는 "폭발" 구간 — 전체 타임라인의 앞쪽
  // 45%(약 1.17초) 안에서, 하트마다 [_delays]만큼 어긋나게 시작한다.
  static const double _burstWindow = 0.45;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
  );

  late final Animation<double> _textScale = Tween<double>(begin: 0, end: 1).animate(
    CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.12, curve: Curves.elasticOut),
    ),
  );
  late final Animation<double> _textOpacity = Tween<double>(begin: 1, end: 0).animate(
    CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.73, 1.0, curve: Curves.easeIn),
    ),
  );
  late final Animation<Offset> _textSlide =
      Tween<Offset>(begin: Offset.zero, end: const Offset(0, -0.6)).animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.73, 1.0, curve: Curves.easeIn),
        ),
      );

  // [_HeartBurst]의 Random(i) 시드 패턴과 동일하게 — late final로 한 번만
  // 계산해 매 리빌드에도 값이 안 바뀌게 한다.
  late final List<double> _angles = List.generate(
    _heartCount,
    (i) => Random(i).nextDouble() * 2 * pi,
  );
  late final List<double> _distances = List.generate(
    _heartCount,
    (i) => 70 + Random(i + 100).nextDouble() * 90,
  );
  late final List<double> _sizes = List.generate(
    _heartCount,
    (i) => 16 + Random(i + 200).nextDouble() * 14,
  );
  late final List<double> _heartDelays = List.generate(
    _heartCount,
    (i) => i * (_burstWindow / _heartCount) * 0.6,
  );

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onDone();
      }
    });
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              for (int i = 0; i < _heartCount; i++) _buildHeart(i),
              _buildText(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeart(int index) {
    final double delay = _heartDelays[index];
    final double localT = ((_controller.value - delay) / (_burstWindow - delay))
        .clamp(0.0, 1.0);
    final double eased = Curves.easeOut.transform(localT);

    final double dx = cos(_angles[index]) * _distances[index] * eased;
    final double dy = sin(_angles[index]) * _distances[index] * eased;
    final double opacity = localT < 0.6 ? 1.0 : (1 - (localT - 0.6) / 0.4).clamp(0.0, 1.0);

    return Transform.translate(
      offset: Offset(dx, dy),
      child: Opacity(
        opacity: opacity,
        child: Icon(Icons.favorite, color: const Color(0xFFFF6FA5), size: _sizes[index]),
      ),
    );
  }

  Widget _buildText() {
    return SlideTransition(
      position: _textSlide,
      child: FadeTransition(
        opacity: _textOpacity,
        child: ScaleTransition(
          scale: _textScale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF9EC4), Color(0xFFFF3D71)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 4)),
              ],
            ),
            child: Text(
              '💕 호감도 Lv.${widget.newLevel} 달성! 💕',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                shadows: [Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(1, 1))],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
