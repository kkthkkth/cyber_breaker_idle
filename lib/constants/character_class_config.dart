import 'package:flutter/material.dart';

import '../models/equipment.dart';
import 'app_images.dart';

/// 투사체의 겉모습 — 실제 스프라이트 아트가 준비되면 [spriteAssetPath]/
/// [fallbackSpriteAssetPath]만 채우면 되고, 둘 다 없거나(또는 둘 다 로드
/// 실패한) 캐릭터는 [fallbackColor]/[fallbackRadius]로 그린 단순한 도형으로
/// 조용히 대체된다(CustomSafeImage의 placeholder-fallback 관례와 동일한
/// 철학). [ProjectileComponent.onLoad]가 이 순서(캐릭터 전용 → 직업 공용
/// 기본 → 그려진 도형)로 정확히 이 순서를 시도한다.
class ProjectileVisual {
  const ProjectileVisual({
    this.spriteAssetPath,
    this.fallbackSpriteAssetPath,
    this.fallbackColor = const Color(0xFF7EE8FA),
    this.fallbackRadius = 6,
  });

  /// 1순위 — 캐릭터 전용 투사체 이미지([AppImages.playerProjectile]).
  /// null이면 곧바로 [fallbackSpriteAssetPath]를 시도한다.
  final String? spriteAssetPath;

  /// 2순위 — 직업 공용 기본 투사체 이미지([AppImages.defaultProjectile]).
  /// [spriteAssetPath]가 없거나(404 등) 로드에 실패했을 때만 시도한다.
  final String? fallbackSpriteAssetPath;

  final Color fallbackColor;
  final double fallbackRadius;

  /// 스프라이트 경로가 전혀 없는 순수 도형 전용 프리셋 — 이제 실전
  /// 코드([visualFor])는 항상 캐릭터별 경로를 채워 넣으므로, 이 상수는
  /// [ProjectileComponent]의 생성자 기본값처럼 "일단 안전하게 뭔가는
  /// 있어야 하는" 자리에만 쓰인다.
  static const ProjectileVisual arrow = ProjectileVisual(
    fallbackColor: Color(0xFFD8C58A),
    fallbackRadius: 4,
  );

  static const ProjectileVisual fireball = ProjectileVisual(
    fallbackColor: Color(0xFFFF7043),
    fallbackRadius: 8,
  );
}

/// 직업([CharacterClass])별 투사체 파일명 — [visualFor]가 [AppImages
/// .playerProjectile]/[AppImages.defaultProjectile] 양쪽에 동일하게 이
/// 이름을 써서, "캐릭터 전용 폴더 안의 같은 파일명"과 "공용 기본 폴더 안의
/// 같은 파일명"이 항상 짝을 이루게 한다. 근접(warrior)은 투사체를 아예
/// 쏘지 않으므로 실제로 로드 시도되지 않지만, 형식을 맞추기 위해 화살
/// 파일명을 채워 둔다.
String _projectileFileName(CharacterClass classType) {
  switch (classType) {
    case CharacterClass.archer:
      return 'arrow.png';
    case CharacterClass.mage:
      return 'magic_orb.png';
    case CharacterClass.warrior:
      return 'arrow.png';
  }
}

/// [classType](직업)과 [characterId](예: "N15")로 실제 원거리 공격
/// 투사체 비주얼을 동적으로 조립한다 — 근접(warrior)은 투사체를 아예 쏘지
/// 않으므로 다루지 않는다. 궁수는 화살, 마법사는 마법 구슬로 구분해서 같은
/// 원거리라도 시각적으로 다르게 보이게 한다.
///
/// 로드 우선순위(전부 [ProjectileComponent.onLoad]가 실제로 순서대로
/// 시도한다):
/// 1. 캐릭터 전용 아트 — `assets/images/player/{등급}/{characterId}/
///    {파일명}`(예: `player/N/N15/magic_orb.png`). 이 캐릭터만의 개성 있는
///    투사체를 그려 올렸다면 이걸 쓴다.
/// 2. 직업 공용 기본 아트 — `assets/images/projectile/{파일명}`. 캐릭터
///    전용 아트가 아직 없는(404) 모든 마법사/궁수가 공유하는 기본
///    스프라이트.
/// 3. 둘 다 없으면(공용 기본 아트조차 아직 안 올라간 초기 상태) 색이 있는
///    작은 원 도형으로 최종 대체한다 — 절대 깨진 이미지 아이콘이 보이는
///    일은 없다.
ProjectileVisual visualFor(CharacterClass classType, String characterId) {
  final String fileName = _projectileFileName(classType);
  final String characterSpritePath = AppImages.playerProjectile(characterId, fileName);
  final String defaultSpritePath = AppImages.defaultProjectile(fileName);

  switch (classType) {
    case CharacterClass.archer:
      return ProjectileVisual(
        spriteAssetPath: characterSpritePath,
        fallbackSpriteAssetPath: defaultSpritePath,
        fallbackColor: ProjectileVisual.arrow.fallbackColor,
        fallbackRadius: ProjectileVisual.arrow.fallbackRadius,
      );
    case CharacterClass.mage:
      return ProjectileVisual(
        spriteAssetPath: characterSpritePath,
        fallbackSpriteAssetPath: defaultSpritePath,
        fallbackColor: ProjectileVisual.fireball.fallbackColor,
        fallbackRadius: ProjectileVisual.fireball.fallbackRadius,
      );
    case CharacterClass.warrior:
      return ProjectileVisual.arrow;
  }
}
