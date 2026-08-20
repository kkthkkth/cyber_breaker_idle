import 'package:flutter/material.dart';

import '../managers/config_manager.dart';
import '../managers/game_manager.dart';
import '../utils/number_formatter.dart';
import '../widgets/total_combat_power_banner.dart';
import 'settings_dialog.dart';

/// 좌측 상단 '내 프로필' 버튼을 눌렀을 때 뜨는 **종합 스탯 정보창** —
/// 예전엔 이 버튼이 캐릭터 일러스트 팝업([CharacterIllustrationDialog])을
/// 띄웠지만, 그 팝업은 이제 캐릭터 탭의 성급(★) 갤러리에서만 연다(기능은
/// 그대로 남아 있고, 이 버튼의 역할만 바뀐 것). 기존 기본 능력치(공격력/
/// 방어력/체력/공속/크리티컬 등)와 [GameManager]의 "특수 스탯 10종 뼈대"
/// 문서에 정의된 신규 스탯을 카테고리별로 나눠 스크롤 가능한 한 화면에
/// 보여준다 — 여기저기 흩어진 업그레이드 패널을 뒤질 필요 없이 현재
/// 성장 상태를 한눈에 확인할 수 있게 하기 위함이다.
///
/// [GameManager]를 구독하므로, 이 팝업이 떠 있는 동안 골드로 스탯을
/// 올리는 등 값이 바뀌면 닫았다 열 필요 없이 즉시 갱신된다.
class ComprehensiveStatsDialog extends StatelessWidget {
  const ComprehensiveStatsDialog({super.key});

  static String _percent(double value) => '${(value * 100).toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1B1B26),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFC9A24B), width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: AnimatedBuilder(
          // GameManager뿐 아니라 ConfigManager도 함께 구독해야, 전투력
          // 가중치(defWeight/offenseWeight)가 인게임 중 다시 로드돼
          // 바뀌어도 총 전투력 배너가 자동으로 다시 그려진다(요구사항:
          // "UI 실시간 반영").
          animation: Listenable.merge([GameManager.instance, ConfigManager.instance]),
          builder: (context, _) {
            final GameManager manager = GameManager.instance;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Header(onClose: () => Navigator.of(context).pop()),
                // 스크롤 목록 안이 아니라 타이틀 바로 아래 고정 — 아래로
                // 스크롤해도 항상 보이도록 한다(요구사항).
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                  child: TotalCombatPowerBanner(
                    combatPower: manager.totalCombatPower,
                    fontSize: 24,
                  ),
                ),
                const Divider(color: Color(0xFF3A3A4A), height: 1),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                    children: [
                      const _CategoryHeader('기본 능력치'),
                      _StatRow(
                        emoji: '⚔️',
                        label: '공격력',
                        valueText: NumberFormatter.format(manager.attackPower),
                      ),
                      _StatRow(
                        emoji: '🛡️',
                        label: '방어력',
                        valueText: NumberFormatter.format(manager.defensePower),
                      ),
                      _StatRow(
                        emoji: '❤️',
                        label: '체력',
                        valueText: NumberFormatter.format(manager.maxHp),
                      ),
                      _StatRow(
                        emoji: '⚡',
                        label: '공격속도',
                        valueText: '${manager.effectiveAttackSpeed.toStringAsFixed(2)} /s',
                      ),
                      _StatRow(
                        emoji: '🔥',
                        label: '크리티컬 확률',
                        valueText: _percent(manager.effectiveCriticalRate),
                      ),
                      _StatRow(
                        emoji: '💢',
                        label: '크리티컬 피해',
                        valueText: _percent(manager.effectiveCriticalMultiplier),
                      ),
                      _StatRow(
                        emoji: '💨',
                        label: '회피율',
                        valueText: _percent(manager.effectiveEvasionRate),
                      ),
                      _StatRow(
                        emoji: '🔰',
                        label: '방어율',
                        valueText: _percent(manager.effectiveDefenseRate),
                      ),
                      _StatRow(
                        emoji: '🌟',
                        label: '크리티컬 방어율',
                        valueText: _percent(manager.effectiveCritDefenseRate),
                      ),
                      const SizedBox(height: 10),
                      const _CategoryHeader('성장 및 유틸리티'),
                      _StatRow(
                        emoji: '💰',
                        label: '골드 획득량',
                        valueText: _percent(manager.goldGain),
                      ),
                      _StatRow(
                        emoji: '✨',
                        label: '경험치 획득량',
                        valueText: _percent(manager.expGain),
                      ),
                      _StatRow(
                        emoji: '🎁',
                        label: '아이템 드랍률',
                        valueText: _percent(manager.itemDropRate),
                      ),
                      _StatRow(
                        emoji: '👟',
                        label: '이동 속도',
                        valueText: _percent(manager.moveSpeed),
                      ),
                      _StatRow(
                        emoji: '🎯',
                        label: '명중률',
                        valueText: _percent(manager.accuracy),
                      ),
                      const SizedBox(height: 10),
                      const _CategoryHeader('생존 및 유지력'),
                      _StatRow(
                        emoji: '🧛',
                        label: '흡혈',
                        valueText: _percent(manager.lifeSteal),
                      ),
                      _StatRow(
                        emoji: '💚',
                        label: '초당 체력 회복',
                        valueText: NumberFormatter.format(manager.hpRegen),
                      ),
                      const SizedBox(height: 10),
                      const _CategoryHeader('특수 공격 능력'),
                      _StatRow(
                        emoji: '👹',
                        label: '보스 피해 증가',
                        valueText: _percent(manager.bossDamageBonus),
                      ),
                      _StatRow(
                        emoji: '🗡️',
                        label: '방어구 관통',
                        valueText: _percent(manager.armorPenetration),
                      ),
                      _StatRow(
                        emoji: '💥',
                        label: '스킬 피해량',
                        valueText: _percent(manager.skillDamage),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Color(0xFFC9A24B), size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '종합 스탯 정보',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          // 상단 앱바 개편으로 프로필 옆 톱니바퀴(설정) 아이콘이 빠지면서
          // 옮겨온 설정 진입점 — 이 다이얼로그도 프로필 버튼으로 열리므로
          // 유저 입장에서 "프로필 → 설정"이라는 동선 자체는 그대로 남는다.
          IconButton(
            onPressed: () => showSettingsDialog(context),
            icon: const Icon(Icons.settings, color: Colors.white54, size: 20),
            splashRadius: 18,
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, color: Colors.white54, size: 20),
            splashRadius: 18,
          ),
        ],
      ),
    );
  }
}

/// 카테고리 구분선 — [기본 능력치]/[성장 및 유틸리티]/[생존 및 유지력]/
/// [특수 공격 능력] 네 구역을 나눈다(요구사항).
class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFC9A24B),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(child: Divider(color: Color(0xFF3A3A4A), height: 1)),
        ],
      ),
    );
  }
}

/// 스탯 한 줄 — 이모지 아이콘 + 이름 + 값. 어느 카테고리든 같은 모양을
/// 공유한다.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.emoji, required this.label, required this.valueText});

  final String emoji;
  final String label;
  final String valueText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(emoji, style: const TextStyle(fontSize: 15)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          Text(
            valueText,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
