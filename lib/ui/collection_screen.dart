import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/story_data.dart';
import '../managers/collection_manager.dart';
import '../managers/encyclopedia_manager.dart';
import '../managers/equipment_manager.dart';
import '../managers/main_story_manager.dart';
import '../managers/sound_manager.dart';
import '../managers/story_manager.dart';
import '../models/collection_model.dart';
import '../models/encyclopedia_model.dart';
import '../models/equipment.dart';
import '../models/story_model.dart';
import '../widgets/center_toast.dart';
import '../widgets/character_face_portrait.dart';
import '../widgets/story_dialog_widget.dart';
import 'affection_screen.dart';
import 'top_bar.dart';

class CollectionScreen extends StatelessWidget {
  const CollectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
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
                        '수집',
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
              // 1Depth — 카테고리(캐릭터/장비/펫). 진행도 배지는 2Depth의
              // "컬렉션" 서브 탭 쪽에 있지만, 하위(도감/컬렉션) 어느 쪽이든
              // 알림이 있으면 여기도 레드닷이 떠야 하므로 두 매니저를 함께
              // 구독해서 카테고리별로 연쇄 판정한다.
              AnimatedBuilder(
                animation: Listenable.merge([
                  CollectionManager.instance,
                  EncyclopediaManager.instance,
                  EquipmentManager.instance,
                ]),
                builder: (context, _) {
                  return TabBar(
                    indicatorColor: const Color(0xFF8A6FE0),
                    indicatorWeight: 3,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    unselectedLabelStyle:
                        const TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
                    tabs: [
                      Tab(child: _buildCategoryTabLabel('캐릭터', CollectionCategory.character)),
                      Tab(child: _buildCategoryTabLabel('장비', CollectionCategory.equipment)),
                      Tab(child: _buildCategoryTabLabel('펫', CollectionCategory.pet)),
                      const Tab(text: '스토리'),
                    ],
                  );
                },
              ),
              Expanded(
                child: TabBarView(
                  children: const [
                    _CategoryTabHost(category: CollectionCategory.character),
                    _CategoryTabHost(category: CollectionCategory.equipment),
                    _CategoryTabHost(category: CollectionCategory.pet),
                    _StoryReplayTab(),
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

/// 1Depth 탭 라벨 — hasCharacterNoti류 연쇄 판정: 이 카테고리의 도감
/// (hasEncyclopediaNoti)이나 컬렉션(hasCollectionNoti) 중 하나라도 알림이
/// 있으면 레드닷을 띄운다. 호출부(TabBar)가 이미 두 매니저를 구독하는
/// AnimatedBuilder 아래에 있으므로 이 함수 자체는 상태를 구독하지 않고
/// 매 빌드마다 최신값을 그대로 읽기만 한다.
Widget _buildCategoryTabLabel(String name, CollectionCategory category) {
  final bool hasEncyclopediaNoti =
      EncyclopediaManager.instance.hasClaimableInCategory(category);
  final bool hasCollectionNoti =
      CollectionManager.instance.hasRegistrableInCategory(category);
  final bool hasCharacterNoti = hasEncyclopediaNoti || hasCollectionNoti;

  return Badge(
    isLabelVisible: hasCharacterNoti,
    backgroundColor: Colors.redAccent,
    smallSize: 8,
    child: Text(name),
  );
}

/// 2Depth 서브 탭(도감/컬렉션) 공용 호스트 — crafting_screen.dart의
/// _CategoryTabHost와 같은 패턴: 알약 모양 [_SegmentedSubTabs] 버튼이
/// [TabController]를 직접 움직이고, 실제 화면 전환은 [TabBarView]가 맡는다.
class _CategoryTabHost extends StatefulWidget {
  const _CategoryTabHost({required this.category});

  final CollectionCategory category;

  @override
  State<_CategoryTabHost> createState() => _CategoryTabHostState();
}

class _CategoryTabHostState extends State<_CategoryTabHost>
    with SingleTickerProviderStateMixin {
  late final TabController _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: 2, vsync: this)
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

  (int completed, int total) _collectionProgress() {
    final List<CollectionModel> items =
        CollectionManager.instance.byCategory(widget.category);
    final int completed = items.where((c) => c.isCompleted).length;
    return (completed, items.length);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          // 도감 보상 알림/컬렉션 진행도·등록 가능 레드닷 둘 다 인벤토리
          // 변화에 반응해야 하므로 세 매니저를 함께 구독한다.
          child: AnimatedBuilder(
            animation: Listenable.merge([
              CollectionManager.instance,
              EncyclopediaManager.instance,
              EquipmentManager.instance,
            ]),
            builder: (context, _) {
              final (int completed, int total) = _collectionProgress();
              final bool hasEncyclopediaNoti =
                  EncyclopediaManager.instance.hasClaimableInCategory(widget.category);
              final bool hasCollectionNoti =
                  CollectionManager.instance.hasRegistrableInCategory(widget.category);
              return _SegmentedSubTabs(
                index: _index,
                labels: ['도감', '컬렉션 ($completed/$total)'],
                redDotTabs: {
                  if (hasEncyclopediaNoti) 0,
                  if (hasCollectionNoti) 1,
                },
                onChanged: _select,
              );
            },
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _controller,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _EncyclopediaGrid(category: widget.category),
              _CollectionListView(category: widget.category),
            ],
          ),
        ),
      ],
    );
  }
}

/// 2Depth 전용 캡슐형 세그먼트 버튼 — [redDotTabs]에 포함된 인덱스에는
/// 작은 레드닷을 얹는다(현재는 "컬렉션" 탭의 등록 가능 알림에 쓰임).
class _SegmentedSubTabs extends StatelessWidget {
  const _SegmentedSubTabs({
    required this.index,
    required this.labels,
    required this.onChanged,
    this.redDotTabs = const {},
  });

  final int index;
  final List<String> labels;
  final ValueChanged<int> onChanged;
  final Set<int> redDotTabs;

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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: index == i ? const Color(0xFF6C4FCE) : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Text(
                      labels[i],
                      style: TextStyle(
                        color: index == i ? Colors.white : Colors.white54,
                        fontWeight: index == i ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                    if (redDotTabs.contains(i))
                      Positioned(
                        top: -4,
                        right: -8,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 도감(개별 아이템 보유/보상) 그리드 — [EncyclopediaManager]가 미리 만들어
/// 둔 항목 풀 중 이 카테고리에 속하는 것만 보여준다.
class _EncyclopediaGrid extends StatelessWidget {
  const _EncyclopediaGrid({required this.category});

  final CollectionCategory category;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        EncyclopediaManager.instance,
        EquipmentManager.instance,
      ]),
      builder: (context, _) {
        final List<EncyclopediaEntry> items =
            EncyclopediaManager.instance.byCategory(category);
        // N→LR 순서(ItemGrade.values 선언 순서와 동일)로 등급별 섹션을
        // 만든다 — 항목이 하나도 없는 등급은 섹션 자체를 만들지 않는다.
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final ItemGrade grade in ItemGrade.values)
              if (items.any((entry) => entry.grade == grade))
                _EncyclopediaGradeSection(
                  grade: grade,
                  entries: items.where((entry) => entry.grade == grade).toList(),
                ),
          ],
        );
      },
    );
  }
}

/// 도감 등급 섹션 — "N 등급" 같은 부제 헤더 + 그 등급 항목들의 Wrap.
class _EncyclopediaGradeSection extends StatelessWidget {
  const _EncyclopediaGradeSection({required this.grade, required this.entries});

  final ItemGrade grade;
  final List<EncyclopediaEntry> entries;

  @override
  Widget build(BuildContext context) {
    final Color gradeColor = getGradeColor(grade);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10, left: 2),
            child: Row(
              children: [
                Container(width: 4, height: 16, color: gradeColor),
                const SizedBox(width: 8),
                Text(
                  '${grade.displayName} 등급',
                  style: TextStyle(
                    color: gradeColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final EncyclopediaEntry entry in entries) _EncyclopediaSlot(entry: entry),
            ],
          ),
        ],
      ),
    );
  }
}

/// 도감 한 칸 — 미보유(회색조 + 터치 비활성화), 보유했지만 미수령(원색 +
/// 레드닷 + 탭하면 보상 수령), 수령 완료(원색 + 완료 체크) 세 상태를 표현한다.
class _EncyclopediaSlot extends StatelessWidget {
  const _EncyclopediaSlot({required this.entry});

  final EncyclopediaEntry entry;

  /// 표준 휘도 기반 흑백 변환 행렬 — R/G/B 채널을 전부 같은 가중합으로
  /// 채워 완전한 무채색으로 만든다. 알파 채널은 그대로 통과시킨다.
  static const ColorFilter _grayscaleFilter = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  Future<void> _onTap(BuildContext context) async {
    final bool isOwned = EncyclopediaManager.instance.isOwned(entry);
    if (!isOwned) {
      final String message = entry.type == EquipType.character
          ? '캐릭터를 먼저 획득해 주세요'
          : '아직 획득하지 않은 ${entry.category.displayName}입니다.';
      showCenterToast(context, message);
      return;
    }

    // 처음 보유가 확인된 순간(=보상 미수령)이면 먼저 1회성 보석 보상을
    // 챙겨준다 — 그 뒤(이미 받았어도) 캐릭터라면 호감도 화면으로 이어서
    // 이동한다. 그래서 "첫 탭=보상, 그다음 탭부터=호감도 이동"이 아니라
    // 캐릭터는 소유하고 있는 한 항상 탭 한 번으로 호감도 화면까지 간다.
    if (!entry.isRewarded) {
      final bool claimed = EncyclopediaManager.instance.claimReward(entry);
      if (claimed) {
        showCenterToast(context, '보석 ${entry.gemReward}개 획득!');
      }
    }

    if (!context.mounted || entry.type != EquipType.character) {
      return;
    }
    _openAffectionScreen(context);
  }

  /// 도감 항목(type+grade+subId)과 일치하는 실제 [Equipment] 인스턴스를
  /// 인벤토리에서 찾아 [AffectionScreen]으로 넘긴다 — 캐릭터 ID/이름/등급
  /// 등 필요한 정보가 이미 그 안에 다 있으므로 별도 파라미터 없이 객체
  /// 하나만 넘기면 된다(AffectionScreen이 character.gradeBadgeLabel로
  /// heart1~10 일러스트, 남은 대화 횟수, 호감도 게이지를 알아서 불러온다).
  void _openAffectionScreen(BuildContext context) {
    // 연타 방지 — 이 위젯의 라우트가 이미 최상단이 아니면(=직전 탭으로
    // 이미 다른 화면이 push된 상태) 중복으로 또 push하지 않는다. 도감
    // 그리드는 StatelessWidget이라 별도 상태 필드 대신 이 방식으로
    // 어뷰징을 막는다.
    final ModalRoute<dynamic>? currentRoute = ModalRoute.of(context);
    if (currentRoute != null && !currentRoute.isCurrent) {
      return;
    }

    Equipment? match;
    for (final Equipment item in EquipmentManager.instance.inventory) {
      if (item.type == entry.type && item.grade == entry.grade && item.subId == entry.subId) {
        match = item;
        break;
      }
    }
    if (match == null) {
      showCenterToast(context, '캐릭터 정보를 찾을 수 없어요.');
      return;
    }

    final Equipment character = match;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AffectionScreen(character: character)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isOwned = EncyclopediaManager.instance.isOwned(entry);
    final bool isRewarded = entry.isRewarded;
    final bool canClaim = isOwned && !isRewarded;

    final Widget tile = entry.type == EquipType.character
        ? CharacterFacePortrait(
            characterId: entry.gradeBadgeLabel,
            size: _CollectionItemTile.size,
            borderRadius: 8,
          )
        : _CollectionItemTile(
            requirement: RequiredCollectionItem(
              type: entry.type,
              grade: entry.grade,
              subId: entry.subId,
            ),
          );

    final Widget colored =
        isOwned ? tile : ColorFiltered(colorFilter: _grayscaleFilter, child: tile);

    final Widget withBadges = Stack(
      clipBehavior: Clip.none,
      children: [
        colored,
        if (!isOwned)
          const Positioned(
            bottom: 2,
            right: 2,
            child: Icon(Icons.lock, color: Colors.white70, size: 16),
          ),
        if (isOwned && isRewarded)
          const Positioned(
            bottom: 2,
            right: 2,
            child: Icon(Icons.check_circle, color: Colors.amberAccent, size: 16),
          ),
        if (canClaim)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black87, width: 1.5),
              ),
            ),
          ),
      ],
    );

    // 미보유 상태도 이제 탭 가능 — _onTap이 안내 토스트를 보여준다. 이미
    // 보상을 받은 상태는 claimReward가 내부에서 false를 반환해 조용히
    // 아무 일도 일어나지 않는다.
    return InkWell(
      onTap: () => _onTap(context),
      borderRadius: BorderRadius.circular(8),
      child: withBadges,
    );
  }
}

/// "스토리 다시보기" 탭 — 프롤로그 + 시즌1 메인 스토리(챕터 1~10) 중 이미
/// 클리어한(보스를 처치한) 챕터만 다시 재생할 수 있다. 아직 클리어하지
/// 못한 챕터는 잠금 아이콘과 함께 비활성 상태로 표시된다(스포일러 방지).
/// 챕터 하나를 재생하면 오프닝 → 보스 대화 순서로 이어서 보여준다.
class _StoryReplayTab extends StatelessWidget {
  const _StoryReplayTab();

  static const List<(int chapter, String title)> _chapterTitles = [
    (1, '1장. 잿빛 숲의 방어선'),
    (2, '2장. 버섯 숲의 방랑 기사'),
    (3, '3장. 고대 신전의 수호자'),
    (4, '4장. 타락한 항구'),
    (5, '5장. 설원의 대검'),
    (6, '6장. 화산 지대의 대장장이'),
    (7, '7장. 대나무 숲의 암살자'),
    (8, '8장. 타락한 기사단장'),
    (9, '9장. 천문대의 현자'),
    (10, '10장. 차원 균열 최심부'),
  ];

  Future<void> _replayStory(BuildContext context, StoryModel story) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (routeContext) => StoryDialogWidget(
          story: story,
          onComplete: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
  }

  /// 프롤로그 다시보기는 닉네임 입력 UI 없이 전/후반부([prologueBeforeName]
  /// → [prologueAfterName])를 이어서 보여준다 — 다시보기 시점엔 이미 닉네임이
  /// 정해져 있으므로({nickname} 치환도 정상 동작) 다시 물을 필요가 없다.
  Future<void> _replayPrologue(BuildContext context) async {
    await _replayStory(context, prologueBeforeName);
    if (!context.mounted) {
      return;
    }
    await _replayStory(context, prologueAfterName);
  }

  Future<void> _replayChapter(BuildContext context, ChapterStory chapterStory) async {
    await _replayStory(context, chapterStory.opening);
    if (!context.mounted) {
      return;
    }
    await _replayStory(context, chapterStory.bossIntro);
  }

  @override
  Widget build(BuildContext context) {
    final bool prologueUnlocked = StoryManager.instance.isPrologueCleared;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _StoryReplayTile(
          title: '프롤로그',
          isUnlocked: prologueUnlocked,
          onTap: prologueUnlocked ? () => _replayPrologue(context) : null,
        ),
        for (final (chapter, title) in _chapterTitles)
          _StoryReplayTile(
            title: title,
            isUnlocked: MainStoryManager.instance.isChapterCleared(chapter),
            onTap: MainStoryManager.instance.isChapterCleared(chapter) &&
                    seasonOneMainStory[chapter] != null
                ? () => _replayChapter(context, seasonOneMainStory[chapter]!)
                : null,
          ),
      ],
    );
  }
}

/// 스토리 다시보기 목록 한 줄 — 잠금(미해금) 상태는 회색조 텍스트 + 잠금
/// 아이콘, 해금 상태는 재생 아이콘 + 탭 가능.
class _StoryReplayTile extends StatelessWidget {
  const _StoryReplayTile({
    required this.title,
    required this.isUnlocked,
    required this.onTap,
  });

  final String title;
  final bool isUnlocked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF20202C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3A4A)),
      ),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(
          isUnlocked ? Icons.play_circle_fill : Icons.lock,
          color: isUnlocked ? const Color(0xFF8A6FE0) : Colors.white38,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isUnlocked ? Colors.white : Colors.white38,
            fontWeight: FontWeight.bold,
          ),
        ),
        trailing: isUnlocked
            ? const Icon(Icons.chevron_right, color: Colors.white54)
            : const Text('미해금', style: TextStyle(color: Colors.white38, fontSize: 12)),
      ),
    );
  }
}

/// 기존 "컬렉션"(세트 수집) 탭 콘텐츠 — 카드 목록 + 등록 다이얼로그 플로우.
class _CollectionListView extends StatefulWidget {
  const _CollectionListView({required this.category});

  final CollectionCategory category;

  @override
  State<_CollectionListView> createState() => _CollectionListViewState();
}

class _CollectionListViewState extends State<_CollectionListView> {
  final CollectionManager _manager = CollectionManager.instance;

  Future<void> _tryRegister(CollectionModel collection) async {
    if (collection.isCompleted) {
      showCenterToast(context, '이미 등록된 도감입니다.');
      return;
    }
    if (!_manager.canRegister(collection)) {
      showCenterToast(context, '재료가 부족합니다.');
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _CollectionRegisterDialog(collection: collection),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    if (_manager.register(collection)) {
      // 등록 성공 "띠링!" 효과음(요구사항) — 실패해도(에셋 미비 등)
      // SoundManager 내부에서 조용히 넘어가므로 등록 자체에는 영향이 없다.
      unawaited(SoundManager.instance.playGachaReveal());
      showCenterToast(context, '${collection.title} 등록 완료!');
    } else {
      showCenterToast(context, '등록에 실패했습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_manager, EquipmentManager.instance]),
      builder: (context, _) {
        // 완료된 항목은 맨 아래로 — 진행 중인 항목이 항상 상단에 먼저
        // 보이도록 정렬한다. byCategory()가 매번 새 리스트를 반환하므로
        // 여기서 정렬해도 매니저가 들고 있는 원본 순서는 바뀌지 않는다.
        final List<CollectionModel> items = _manager.byCategory(widget.category)
          ..sort((a, b) {
            if (a.isCompleted == b.isCompleted) {
              return 0;
            }
            return a.isCompleted ? 1 : -1;
          });
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final CollectionModel collection = items[index];
            return _CollectionCard(
              collection: collection,
              onRegister: () => _tryRegister(collection),
            );
          },
        );
      },
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.collection, required this.onRegister});

  final CollectionModel collection;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF20202C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: collection.isCompleted ? const Color(0xFFC9A24B) : const Color(0xFF3A3A4A),
          width: collection.isCompleted ? 2 : 1.2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (collection.isCompleted)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.check_circle, color: Colors.amberAccent, size: 24),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  collection.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '완성 시 ${collection.rewardStat.displayText} (영구)',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (!collection.isCompleted) ...[
                  const SizedBox(height: 8),
                  // 요구 조건별 진행도(요구사항: "진행도(예: 3/5)를
                  // 프로그레스 바 등으로") — 등록 자체는 한 번에
                  // 원자적으로 이뤄지지만(부분 등록 없음), 지금 인벤토리에
                  // 몇 개나 들고 있는지를 미리 보여주면 뭘 더 모아야
                  // 하는지 한눈에 알 수 있다.
                  for (final RequiredCollectionItem req in collection.requiredItems)
                    _RequirementProgressRow(requirement: req),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 요구 수량(count)만큼 같은 모양의 타일을 반복해서 1칸=1개로,
          // 텍스트 우측 끝에 오른쪽 정렬로 나열한다. 총 개수는 더미 데이터
          // 생성 단계에서 이미 4개 이하로 제한되어 있어 한 줄에 다 들어간다.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              for (final RequiredCollectionItem req in collection.requiredItems)
                ..._buildRequirementTiles(req, collection.isCompleted, onRegister),
            ],
          ),
        ],
      ),
    );
  }
}

/// [req]가 요구하는 타입/등급/넘버링(subId)/레벨 조건을 만족하는 미장착
/// 인벤토리 아이템 수 — [CollectionManager._matches]와 같은 조건이지만,
/// 이 화면(진행도/레드닷 표시)에서만 쓰는 판정이라 매니저를 건드리지
/// 않고 여기서 직접 인벤토리를 본다.
int _matchedCount(RequiredCollectionItem req) {
  return EquipmentManager.instance.inventory
      .where(
        (item) =>
            !item.isEquipped &&
            item.type == req.type &&
            item.grade == req.grade &&
            (req.subId == null || item.subId == req.subId) &&
            item.level >= req.requiredLevel,
      )
      .length;
}

/// [req]가 요구하는 조건을 만족하는 미장착 인벤토리 아이템이 [req.count]개
/// 이상 있는지 — [_matchedCount]의 bool 버전.
bool _canFulfillRequirement(RequiredCollectionItem req) => _matchedCount(req) >= req.count;

/// 요구 조건 하나의 "N/M" 진행도 한 줄 — 아이템명(타입+등급)과 프로그레스
/// 바를 함께 보여준다. [EquipmentManager]를 구독하지 않는 이유: 부모
/// [_CollectionListView]가 이미 [EquipmentManager.instance]를 구독하고
/// 있어 인벤토리가 바뀌면 이 위젯을 포함한 트리 전체가 다시 그려진다.
class _RequirementProgressRow extends StatelessWidget {
  const _RequirementProgressRow({required this.requirement});

  final RequiredCollectionItem requirement;

  @override
  Widget build(BuildContext context) {
    final int matched = _matchedCount(requirement);
    final int required = requirement.count;
    final bool fulfilled = matched >= required;
    final String label = requirement.subId != null
        ? '${requirement.type.displayName}${requirement.grade.displayName}${requirement.subId}'
        : '${requirement.type.displayName}(${requirement.grade.displayName})';

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: required <= 0 ? 1 : (matched / required).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation(
                  fulfilled ? Colors.amberAccent : const Color(0xFF6C4FCE),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${matched.clamp(0, required)}/$required',
            style: TextStyle(
              color: fulfilled ? Colors.amberAccent : Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// [req] 하나가 요구하는 개수(count)만큼 타일을 만든다. 아직 미완성인
/// 도감이고 이 요구 조건을 인벤토리로 이미 충족했다면(=[_canFulfillRequirement]),
/// 해당 요구 조건에 속한 타일 전부에 레드닷을 띄운다.
List<Widget> _buildRequirementTiles(
  RequiredCollectionItem req,
  bool isCompleted,
  VoidCallback onRegister,
) {
  final bool showRedDot = !isCompleted && _canFulfillRequirement(req);

  return [
    for (int i = 0; i < req.count; i++)
      Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            onTap: onRegister,
            borderRadius: BorderRadius.circular(10),
            child: _CollectionItemTile(requirement: req),
          ),
          if (showRedDot)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black87, width: 1.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 3, offset: Offset(0, 1)),
                  ],
                ),
              ),
            ),
        ],
      ),
  ];
}

/// 도감/컬렉션 요구 아이템 한 칸을 나타내는 60x60 고정 타일. 캐릭터
/// 타입이면 전용 썸네일 이미지를 꽉 채워 보여주고, 그 외(장비/펫)는 아직
/// 전용 이미지가 없어 기존처럼 타입명 텍스트로 표시한다. 배경은 무조건
/// [Colors.black87] 고정이고, 등급 컬러는 얇은 테두리 선(단색 등급은
/// [Border.all], UR/LR 그라데이션 등급만 별도 처리)으로만 표현한다.
class _CollectionItemTile extends StatelessWidget {
  const _CollectionItemTile({required this.requirement});

  static const double size = 60;

  final RequiredCollectionItem requirement;

  @override
  Widget build(BuildContext context) {
    final Color gradeColor = getGradeColor(requirement.grade);
    final GradeBorderStyle borderStyle = getGradeBorderStyle(requirement.grade);
    final String gradeLabel = requirement.subId != null
        ? '${requirement.grade.displayName}${requirement.subId}'
        : requirement.grade.displayName;
    final bool isCharacter = requirement.type == EquipType.character && requirement.subId != null;

    final Widget content = Stack(
      children: [
        if (isCharacter)
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: CharacterFacePortrait(characterId: gradeLabel, borderRadius: 6),
            ),
          )
        else
          Center(
            child: Text(
              requirement.type.displayName,
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
          child: Text(
            gradeLabel,
            style: TextStyle(
              color: gradeColor,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              shadows: const [
                Shadow(color: Colors.black, blurRadius: 4.0, offset: Offset(1.0, 1.0)),
                Shadow(color: Colors.black, blurRadius: 4.0, offset: Offset(-1.0, -1.0)),
              ],
            ),
          ),
        ),
        if (requirement.requiredLevel > 0)
          Positioned(
            top: 4,
            right: 4,
            child: Text(
              '+${requirement.requiredLevel}',
              style: const TextStyle(
                color: Colors.yellowAccent,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(color: Colors.black, blurRadius: 4.0, offset: Offset(1.0, 1.0)),
                  Shadow(color: Colors.black, blurRadius: 4.0, offset: Offset(-1.0, -1.0)),
                ],
              ),
            ),
          ),
      ],
    );

    // UR/LR(그라데이션 등급)만 얇은 그라데이션 테두리가 필요해 부득이하게
    // 바깥 그라데이션 링 + 안쪽 검정 Container 트릭을 쓴다 — 그 외 5개
    // 단색 등급은 배경이 처음부터 검정이고 Border.all() 선만 두른다.
    if (borderStyle.gradient != null) {
      return Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          gradient: borderStyle.gradient,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(7),
          ),
          child: content,
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderStyle.color!, width: 1.5),
      ),
      child: content,
    );
  }
}

/// 도감 등록 확인 팝업 — 네온 그라데이션 테두리 + 요구 아이템 아이콘
/// 미리보기 + 가로 2버튼([취소]/[등록])으로 구성된 다크 게임 스타일 팝업.
class _CollectionRegisterDialog extends StatelessWidget {
  const _CollectionRegisterDialog({required this.collection});

  final CollectionModel collection;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF8A6FE0), Color(0xFF3FBFBF), Color(0xFFC9A24B), Color(0xFF8A6FE0)],
          ),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          decoration: BoxDecoration(
            color: const Color(0xFF14141C),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome, color: Color(0xFFC9A24B), size: 32),
              const SizedBox(height: 10),
              Text(
                collection.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  for (final RequiredCollectionItem req in collection.requiredItems)
                    _CollectionItemTile(requirement: req),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                '등록 시 아이템이 소모됩니다',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3A3A4A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('취소', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C4FCE),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('등록', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
