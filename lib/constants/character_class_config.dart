import 'package:flutter/material.dart';

import '../models/equipment.dart';

/// 투사체의 겉모습 — 실제 스프라이트 아트가 준비되면 [spriteAssetPath]만
/// 채우면 되고, 아직 없는(또는 로드 실패한) 캐릭터는 [fallbackColor]/
/// [fallbackRadius]로 그린 단순한 도형으로 조용히 대체된다
/// (CustomSafeImage의 placeholder-fallback 관례와 동일한 철학).
class ProjectileVisual {
  const ProjectileVisual({
    this.spriteAssetPath,
    this.fallbackColor = const Color(0xFF7EE8FA),
    this.fallbackRadius = 6,
  });

  /// 예: `AppImages.resolve('assets/images/projectile/arrow.png')` —
  /// null이면 처음부터 스프라이트를 시도하지 않고 fallback 도형만 그린다.
  final String? spriteAssetPath;
  final Color fallbackColor;
  final double fallbackRadius;

  static const ProjectileVisual arrow = ProjectileVisual(
    fallbackColor: Color(0xFFD8C58A),
    fallbackRadius: 4,
  );

  static const ProjectileVisual fireball = ProjectileVisual(
    fallbackColor: Color(0xFFFF7043),
    fallbackRadius: 8,
  );
}

/// 직업([CharacterClass])별 투사체 비주얼 — 근접(warrior)은 투사체를 아예
/// 쏘지 않으므로 다루지 않는다. 궁수는 화살, 마법사는 화염구로 구분해서
/// 같은 원거리라도 시각적으로 다르게 보이게 한다.
ProjectileVisual visualFor(CharacterClass classType) {
  switch (classType) {
    case CharacterClass.archer:
      return ProjectileVisual.arrow;
    case CharacterClass.mage:
      return ProjectileVisual.fireball;
    case CharacterClass.warrior:
      return ProjectileVisual.arrow;
  }
}
