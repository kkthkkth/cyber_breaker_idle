import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../managers/consumable_manager.dart';
import '../managers/dungeon_manager.dart';
import '../managers/game_manager.dart';
import '../managers/skill_manager.dart';
import '../models/consumable_item_model.dart';
import '../models/craft_recipe_model.dart';
import 'disassemble_screen.dart';
import 'synthesis_screen.dart';
import 'top_bar.dart';

/// 제작 화면 소모 재화 — 탭마다 어떤 재화를 소모하는지가 다르므로 레시피가
/// 아닌 탭(스크린) 레벨에서 결정한다.
enum CraftCurrency { dust, pawprint, gem }

extension CraftCurrencyX on CraftCurrency {
  String get label => switch (this) {
    CraftCurrency.dust => '가루',
    CraftCurrency.pawprint => '발바닥',
    CraftCurrency.gem => '보석',
  };

  IconData get icon => switch (this) {
    CraftCurrency.dust => Icons.grain,
    CraftCurrency.pawprint => Icons.pets,
    CraftCurrency.gem => Icons.diamond,
  };
}

/// 2Depth 서브 탭(합성/제작[/분해]) 공용 호스트 — 1Depth(장비/펫/캐릭터)
/// 카테고리 탭 안에서 쓰인다. 알약 모양 [_SegmentedSubTabs] 버튼이
/// [TabController]를 직접 움직이고, 실제 화면 전환은 [TabBarView]가 맡아
/// 스와이프 없이도 슬라이드 크로스페이드 애니메이션이 그대로 적용된다.
/// [disassembleView]를 준 카테고리(장비/펫)만 '분해' 탭이 3번째로 붙고,
/// 안 준 카테고리(캐릭터 — 분해 대상이 아님)는 예전처럼 2탭 그대로다.
class _CategoryTabHost extends StatefulWidget {
  const _CategoryTabHost({
    required this.synthesisView,
    required this.craftView,
    this.disassembleView,
  });

  final Widget synthesisView;
  final Widget craftView;
  final Widget? disassembleView;

  @override
  State<_CategoryTabHost> createState() => _CategoryTabHostState();
}

class _CategoryTabHostState extends State<_CategoryTabHost>
    with SingleTickerProviderStateMixin {
  late final TabController _controller;
  int _index = 0;

  static const List<String> _labelsWithoutDisassemble = ['합성', '제작'];
  static const List<String> _labelsWithDisassemble = ['합성', '제작', '분해'];

  List<String> get _labels =>
      widget.disassembleView == null ? _labelsWithoutDisassemble : _labelsWithDisassemble;

  List<Widget> get _pages => [
    widget.synthesisView,
    widget.craftView,
    if (widget.disassembleView != null) widget.disassembleView!,
  ];

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: _labels.length, vsync: this)
      ..addListener(() {
        if (_controller.indexIsChanging || _controller.index == _index) {
          return;
        }
        setState(() => _index = _controller.index);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (_index == index) {
      return;
    }
    setState(() => _index = index);
    _controller.animateTo(index);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: _SegmentedSubTabs(
            index: _index,
            labels: _labels,
            onChanged: _select,
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _controller,
            physics: const NeverScrollableScrollPhysics(),
            children: _pages,
          ),
        ),
      ],
    );
  }
}

/// 2Depth 전용 캡슐형 세그먼트 버튼 — 1Depth의 굵은 텍스트 + 언더라인
/// [TabBar]와 시각적으로 확실히 구분되도록, 알약 배경 안에서 선택된
/// 라벨만 색이 채워지는 형태로 그린다.
class _SegmentedSubTabs extends StatelessWidget {
  const _SegmentedSubTabs({
    required this.index,
    required this.labels,
    required this.onChanged,
  });

  final int index;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF20202C),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < labels.length; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                decoration: BoxDecoration(
                  color: index == i ? const Color(0xFF6C4FCE) : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    color: index == i ? Colors.white : Colors.white54,
                    fontWeight: index == i ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CraftingScreen extends StatelessWidget {
  const CraftingScreen({super.key, this.initialCategoryIndex = 0});

  /// 1Depth 탭(장비=0, 펫=1, 캐릭터=2, 소모품/아이템=3) 중 처음부터 선택돼
  /// 있을 탭 — 장비/펫/캐릭터 상세 팝업의 제작/합성 바로가기(망치 아이콘)가
  /// 자신이 보여주던 아이템의 카테고리를 그대로 넘겨준다
  /// ([ItemDetailDialog._navigateToCrafting] 참고). 기본값 0(장비)은 하단
  /// 네비게이션의 '제작' 탭에서 직접 진입할 때처럼 별도 지정이 없는 경우다.
  final int initialCategoryIndex;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      initialIndex: initialCategoryIndex,
      child: Scaffold(
        backgroundColor: const Color(0xFF14141C),
        body: SafeArea(
          child: Column(
            children: [
              const TopBar(),
              SizedBox(
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Align(
                      alignment: Alignment.center,
                      child: Text(
                        '제작',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ],
                ),
              ),
              // 1Depth — 기능 중심(합성/제작 뒤섞임) 대신 카테고리 중심으로
              // 개편: 굵은 텍스트 + 언더라인으로 2Depth 캡슐 버튼과 구분한다.
              const TabBar(
                indicatorColor: Color(0xFF8A6FE0),
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                unselectedLabelStyle: TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
                tabs: [
                  Tab(text: '장비'),
                  Tab(text: '펫'),
                  Tab(text: '캐릭터'),
                  Tab(text: '소모품/아이템'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _CategoryTabHost(
                      synthesisView: const SynthesisView(category: SynthesisCategory.equipment),
                      craftView: const _RecipeCraftTab(
                        recipes: CraftRecipe.equipmentCraftRecipes,
                        currency: CraftCurrency.dust,
                      ),
                      // 장비/펫 카테고리만 분해 대상 — 캐릭터는 분해가
                      // 불가능하므로 아래 캐릭터 탭에는 이 파라미터를
                      // 아예 주지 않는다(2탭 그대로 유지).
                      disassembleView: const DisassembleView(category: SynthesisCategory.equipment),
                    ),
                    _CategoryTabHost(
                      synthesisView: const SynthesisView(category: SynthesisCategory.pet),
                      craftView: const _RecipeCraftTab(
                        recipes: CraftRecipe.petCraftRecipes,
                        currency: CraftCurrency.pawprint,
                      ),
                      disassembleView: const DisassembleView(category: SynthesisCategory.pet),
                    ),
                    _CategoryTabHost(
                      synthesisView: const SynthesisView(category: SynthesisCategory.character),
                      craftView: const _RecipeCraftTab(
                        recipes: CraftRecipe.characterCraftRecipes,
                        currency: CraftCurrency.gem,
                      ),
                    ),
                    // 소모품/아이템 — 합성 대상이 없으므로 2Depth 없이 제작
                    // 리스트를 바로 보여준다(요구사항의 "합성 불필요 시 생략").
                    const _RecipeCraftTab(
                      recipes: CraftRecipe.defaultRecipes,
                      currency: CraftCurrency.gem,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 레시피 리스트 + 소모 재화 표시를 공통화한 탭 바디. [currency]에 따라
/// 재화 조회/차감 대상만 달라지고 나머지 제작 플로우(연출/결과 다이얼로그)는
/// 동일하다.
class _RecipeCraftTab extends StatefulWidget {
  const _RecipeCraftTab({required this.recipes, required this.currency});

  final List<CraftRecipe> recipes;
  final CraftCurrency currency;

  @override
  State<_RecipeCraftTab> createState() => _RecipeCraftTabState();
}

class _RecipeCraftTabState extends State<_RecipeCraftTab> {
  final Random _random = Random();
  bool _effectVisible = false;
  CraftRecipe? _activeRecipe;
  int _craftNonce = 0;

  bool get _isCrafting => _activeRecipe != null;

  int _ownedAmount() {
    switch (widget.currency) {
      case CraftCurrency.dust:
        return ConsumableManager.instance.countOf(ConsumableType.dust);
      case CraftCurrency.pawprint:
        return ConsumableManager.instance.countOf(ConsumableType.pawprint);
      case CraftCurrency.gem:
        return GameManager.instance.gems;
    }
  }

  bool _spend(int amount) {
    switch (widget.currency) {
      case CraftCurrency.dust:
        return ConsumableManager.instance.consume(
          ConsumableType.dust,
          amount: amount,
        );
      case CraftCurrency.pawprint:
        return ConsumableManager.instance.consume(
          ConsumableType.pawprint,
          amount: amount,
        );
      case CraftCurrency.gem:
        return GameManager.instance.spendGems(amount);
    }
  }

  Future<void> _craft(CraftRecipe recipe) async {
    if (_isCrafting) {
      return;
    }
    if (!_spend(recipe.requiredAmount)) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text('${widget.currency.label}이(가) 부족합니다.')),
        );
      return;
    }

    setState(() {
      _activeRecipe = recipe;
      _effectVisible = true;
      _craftNonce++;
    });

    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) {
      return;
    }

    final bool success = _random.nextDouble() < recipe.successRate;
    if (success) {
      switch (recipe.rewardType) {
        case CraftRewardType.item:
          ConsumableManager.instance.addItem(recipe.targetItemType!, 1);
          break;
        case CraftRewardType.characterSp:
          SkillManager.instance.addSkillPoints(1);
          break;
        case CraftRewardType.petSp:
          SkillManager.instance.addPetSkillPoints(1);
          break;
        case CraftRewardType.petDungeonTicket:
          DungeonManager.instance.addPetDungeonTicket();
          break;
      }
    }

    setState(() {
      _effectVisible = false;
      _activeRecipe = null;
    });

    _showResultDialog(recipe, success);
  }

  void _showResultDialog(CraftRecipe recipe, bool success) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFF1B1B26),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: success
                  ? const Color(0xFFC9A24B)
                  : const Color(0xFF3A3A4A),
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  success ? '✨ 제작 성공!' : '💦 제작 실패...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: success ? Colors.amberAccent : Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  success
                      ? '${recipe.displayName}을(를) 획득했습니다.'
                      : '${widget.currency.label}만 날아갔습니다.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C4FCE),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '확인',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        ConsumableManager.instance,
        GameManager.instance,
      ]),
      builder: (context, _) {
        final int owned = _ownedAmount();

        return Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        widget.currency.icon,
                        color: Colors.amberAccent,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '보유 ${widget.currency.label}: $owned',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: widget.recipes.length,
                    itemBuilder: (context, index) {
                      final CraftRecipe recipe = widget.recipes[index];
                      return _RecipeTile(
                        recipe: recipe,
                        ownedAmount: owned,
                        currencyLabel: widget.currency.label,
                        crafting: _isCrafting,
                        onCraft: () => _craft(recipe),
                      );
                    },
                  ),
                ),
              ],
            ),
            IgnorePointer(
              child: Center(
                child: _CraftEffect(
                  key: ValueKey(_craftNonce),
                  visible: _effectVisible,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RecipeTile extends StatelessWidget {
  const _RecipeTile({
    required this.recipe,
    required this.ownedAmount,
    required this.currencyLabel,
    required this.crafting,
    required this.onCraft,
  });

  final CraftRecipe recipe;
  final int ownedAmount;
  final String currencyLabel;
  final bool crafting;
  final VoidCallback onCraft;

  @override
  Widget build(BuildContext context) {
    final bool affordable = ownedAmount >= recipe.requiredAmount;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF20202C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF3A3A4A)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF6C4FCE).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              recipe.icon,
              color: const Color(0xFF8A6FE0),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recipe.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '필요 $currencyLabel ${recipe.requiredAmount} · 성공 확률 ${(recipe.successRate * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: affordable && !crafting ? onCraft : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C4FCE),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF3A3A4A),
            ),
            child: const Text('제작하기'),
          ),
        ],
      ),
    );
  }
}

/// Magic-circle craft effect: always mounted so the very first cast still
/// fades/scales in instead of popping in instantly (an implicit-animation
/// needs a prior value to interpolate from).
class _CraftEffect extends StatelessWidget {
  const _CraftEffect({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      child: AnimatedScale(
        scale: visible ? 1.3 : 0.3,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutBack,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF8A6FE0).withValues(alpha: 0.6),
                    const Color(0xFF6C4FCE).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
            // 1.5초 동안 채워지며 회전하는 노란색 띠 — visible이 유지되는
            // 동안 계속 떠 있다가 craft가 끝나면 바깥 Opacity/Scale로 사라진다.
            SizedBox(
              width: 130,
              height: 130,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: visible ? 1.0 : 0.0),
                duration: const Duration(milliseconds: 1500),
                builder: (context, value, child) {
                  return Transform.rotate(
                    angle: value * 2 * pi,
                    child: CircularProgressIndicator(
                      value: value,
                      strokeWidth: 6,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation(
                        Colors.amberAccent,
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
            const Icon(Icons.auto_fix_high, color: Colors.white, size: 40),
          ],
        ),
      ),
    );
  }
}
