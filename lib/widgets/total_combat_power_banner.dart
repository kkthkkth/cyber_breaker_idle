import 'package:flutter/material.dart';

import '../utils/number_formatter.dart';

/// "⚔️ 총 전투력: 1,234,567" 배너 — [GameManager.totalCombatPower]를
/// 황금색 + 은은한 발광(Shadow) 효과로 강조해서 보여준다. 메인 캐릭터
/// 화면(item_detail_dialog.dart, 예전 `_CharacterCoreStatsCard` 자리)과
/// 종합 스탯 정보창(comprehensive_stats_dialog.dart) 양쪽에서 디자인을
/// 통일하기 위해 하나로 공유한다 — 색/발광 스타일을 바꿀 일이 생기면 이
/// 파일 하나만 고치면 된다.
///
/// 숫자는 [NumberFormatter.format]의 K/M/B/T 축약이 아니라
/// [NumberFormatter.formatExact](천 단위 쉼표만)로 표시한다 — 자릿수
/// 자체가 위압감을 주도록 정확한 값을 그대로 보여주는 게 이 배너의
/// 연출 의도다(요구사항 예시: "1,234,567").
class TotalCombatPowerBanner extends StatelessWidget {
  const TotalCombatPowerBanner({
    super.key,
    required this.combatPower,
    this.fontSize = 32,
    this.showLabel = true,
  });

  final int combatPower;

  /// 메인 화면은 기존 스탯 텍스트보다 훨씬 크게(요구사항), 다이얼로그
  /// 안에서는 폭이 제한적이라 조금 더 작게 — 호출부가 상황에 맞게 넘긴다.
  final double fontSize;

  /// false면 "총 전투력: " 글씨를 빼고 "⚔️ 1,234,567"처럼 숫자만
  /// 심플하게 보여준다 — 상단 앱바처럼 폭이 좁아 라벨까지 넣으면 부담스러운
  /// 자리에서 쓴다(요구사항). 기본값 true는 기존 화면(캐릭터 탭/종합 스탯
  /// 정보창)의 모습을 그대로 유지한다.
  final bool showLabel;

  static const Color _gold = Color(0xFFFFD700);

  @override
  Widget build(BuildContext context) {
    // FittedBox(scaleDown)로 감싸서, [fontSize]가 좁은 화면/다이얼로그
    // 폭에서 자연스러운 줄바꿈 없이 흘러넘치지 않도록 자동으로 축소한다 —
    // 폭이 넉넉하면 원래 [fontSize] 그대로 "큼직하고 화려하게" 보인다.
    final String label = showLabel ? '총 전투력: ' : '';
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        '⚔️ $label${NumberFormatter.formatExact(combatPower)}',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _gold,
          fontWeight: FontWeight.w900,
          fontSize: fontSize,
          shadows: const [
            // 안쪽의 밝은 발광(작은 blur, 진한 금색)과 바깥쪽의 넓게 퍼지는
            // 발광(큰 blur, 옅은 주황빛 금색)을 겹쳐서 "은은하게 번지는"
            // 느낌을 낸다 — 하나만 쓰면 그냥 흐릿한 그림자로만 보인다.
            Shadow(color: _gold, blurRadius: 10),
            Shadow(color: Color(0xFFFFA500), blurRadius: 28),
            // 밝은 금색 글자가 밝은 배경 위에서도 읽히도록 살짝 어두운
            // 테두리감을 더한다.
            Shadow(color: Colors.black87, blurRadius: 3, offset: Offset(1, 1)),
          ],
        ),
      ),
    );
  }
}
