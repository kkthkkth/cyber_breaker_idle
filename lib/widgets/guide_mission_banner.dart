import 'package:flutter/material.dart';

import '../managers/guide_mission_manager.dart';
import '../models/guide_mission_model.dart';
import 'center_toast.dart';

/// 인게임 홈 화면 최상단에 떠 있는 얇은 배너 — 지금 진행 중인 단일 메인
/// 가이드 미션([GuideMissionManager.currentMission])의 설명/진행도/보상을
/// 보여준다. 목표를 채우면 [받기] 버튼으로 바뀌고, 탭하면 보상을 수령하며
/// 자동으로 다음 번호의 미션이 노출된다([GuideMissionManager.claimCurrent]).
/// 미완료 상태에서 이 미션이 홈 탭 밖의 화면(예: 샵의 가챠 버튼)에서
/// 진행되는 것이면 [바로가기] 버튼으로 그 탭으로 이동한다
/// ([GuideMission.shortcut]이 null이면 이미 홈 탭 안에서 진행되는 미션이라
/// 버튼 자체를 그리지 않는다). 전체 시퀀스를 다 끝내면
/// ([GuideMissionManager.isAllCompleted]) 자리 자체를 차지하지 않도록
/// [SizedBox.shrink]를 그린다 — 신규 유저 온보딩이 끝나면 화면에서 자연히
/// 사라진다.
class GuideMissionBanner extends StatelessWidget {
  const GuideMissionBanner({super.key});

  Future<void> _claim(BuildContext context) async {
    final GuideMission? claimed = await GuideMissionManager.instance.claimCurrent();
    if (!context.mounted || claimed == null) {
      return;
    }
    showCenterToast(context, '가이드 미션 완료! ${claimed.rewardLabel} 획득!');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: GuideMissionManager.instance,
      builder: (context, _) {
        final GuideMission? mission = GuideMissionManager.instance.currentMission;
        if (mission == null) {
          return const SizedBox.shrink();
        }
        final int count = GuideMissionManager.instance.currentCount;
        final bool complete = count >= mission.targetCount;
        final Color accent = complete ? Colors.amberAccent : const Color(0xFF4F8FE0);

        return Container(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF20202C),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent, width: 1.2),
          ),
          child: Row(
            children: [
              const Text('🧭', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${mission.description} ($count/${mission.targetCount})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: mission.targetCount <= 0
                            ? 0
                            : (count / mission.targetCount).clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation(accent),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  mission.rewardLabel,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              if (complete)
                _BannerActionButton(
                  label: '받기',
                  color: Colors.amberAccent,
                  onTap: () => _claim(context),
                )
              else if (mission.shortcut != null)
                _BannerActionButton(
                  label: '바로가기',
                  color: const Color(0xFF6C4FCE),
                  onTap: () => GuideMissionManager.instance.onRequestTabSwitch
                      ?.call(mission.shortcut!.tabIndex),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BannerActionButton extends StatelessWidget {
  const _BannerActionButton({required this.label, required this.color, required this.onTap});

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}
