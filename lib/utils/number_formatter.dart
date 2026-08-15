/// 데미지/체력/스탯처럼 값이 커질수록 화면을 가리는 숫자를 K(천)/M(백만)
/// 단위로 축약하는 유틸리티 — 데미지 텍스트, HP 바 수치, 업그레이드 패널,
/// 캐릭터 스탯 패널 등 큰 숫자가 나오는 모든 곳에서 공용으로 쓴다.
class NumberFormatter {
  const NumberFormatter._();

  /// 100만 이상은 "1.2M", 1천 이상은 "10.5K", 그 미만은 정수 그대로
  /// ("999") 표기한다.
  static String format(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toInt().toString();
  }
}
