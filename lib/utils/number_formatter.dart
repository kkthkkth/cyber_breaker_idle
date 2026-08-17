/// 데미지/체력/스탯/재화처럼 값이 커질수록 화면을 가리는 숫자를
/// K(천)/M(백만)/B(십억)/T(조) 단위로 축약하는 유틸리티 — 데미지 텍스트,
/// HP 바 수치, 업그레이드 패널, 캐릭터 스탯 패널, 상단 재화(골드/보석)
/// 표시 등 큰 숫자가 나오는 모든 곳에서 공용으로 쓴다.
class NumberFormatter {
  const NumberFormatter._();

  static const double _thousand = 1000;
  static const double _million = 1000000;
  static const double _billion = 1000000000;
  static const double _trillion = 1000000000000;

  /// 1000 미만은 정수 그대로("999"), 그 이상은 K/M/B/T로 축약한다.
  /// 소수점은 "필요한 만큼만"(최대 둘째 자리까지) 보여준다 — 둘째 자리가
  /// 0이면 첫째 자리까지만, 그마저 0이면 정수만("1,000" → "1K",
  /// "10,000,000" → "10M") 표기하고, 불필요한 0은 전부 잘라낸다(예:
  /// "1,234,000" → "1.23M", "10,500,000" → "10.5M").
  static String format(double value) {
    final bool isNegative = value < 0;
    final double absValue = value.abs();

    final double divisor;
    final String suffix;
    if (absValue >= _trillion) {
      divisor = _trillion;
      suffix = 'T';
    } else if (absValue >= _billion) {
      divisor = _billion;
      suffix = 'B';
    } else if (absValue >= _million) {
      divisor = _million;
      suffix = 'M';
    } else if (absValue >= _thousand) {
      divisor = _thousand;
      suffix = 'K';
    } else {
      return value.toInt().toString();
    }

    final String trimmed = _trimTrailingZeros((absValue / divisor).toStringAsFixed(2));
    return '${isNegative ? '-' : ''}$trimmed$suffix';
  }

  /// "10.00" → "10", "10.50" → "10.5", "9.97" → "9.97"(변화 없음) —
  /// 소수점 뒤 불필요한 0(과, 전부 지워졌다면 소수점 자체)만 제거한다.
  static String _trimTrailingZeros(String fixed) {
    if (!fixed.contains('.')) {
      return fixed;
    }
    String result = fixed;
    while (result.endsWith('0')) {
      result = result.substring(0, result.length - 1);
    }
    if (result.endsWith('.')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
