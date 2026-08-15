import 'package:flame/components.dart';

import '../constants/player_n1_assets.dart';
import 'remote_sprite_loader.dart';

/// [PlayerN1Assets]에 등록된 원격 URL들을 실제 Flame [Sprite]/
/// [SpriteAnimation]으로 불러오는 예시/유틸리티 함수 모음.
///
/// N1의 run 프레임(`run1~run3.png`)은 한 장짜리 스프라이트 시트가 아니라
/// **개별 PNG 파일 3장**이므로, 시트 한 장을 잘라 쓰는
/// [RemoteSpriteLoader.loadSpriteAnimation](`SpriteAnimationData.sequenced`
/// 기반)은 맞지 않는다 — 프레임마다 각각 [RemoteSpriteLoader.loadSprite]로
/// 내려받은 뒤 [SpriteAnimation.spriteList]로 이어 붙인다. 이 방식은
/// [PlayerAnimationComponent]가 캐릭터 프레임 시퀀스를 불러올 때 쓰는 것과
/// 동일한 패턴이다.
Future<SpriteAnimation> loadN1RunAnimation({double stepTime = 0.1}) async {
  final List<Sprite> frames = await Future.wait(
    PlayerN1Assets.runFrames.map(RemoteSpriteLoader.loadSprite),
  );
  return SpriteAnimation.spriteList(frames, stepTime: stepTime, loop: true);
}

/// 개별 파츠 하나(`armored_foot_l.png`)를 단독 [Sprite]로 불러오는 예시 —
/// 지금 당장은 이 [Sprite]를 [SpriteComponent]에 그대로 꽂아 화면에
/// 띄워볼 수 있고(`SpriteComponent(sprite: await loadN1FootSprite())`),
/// 나중에 뼈대 라이브러리(Spine 등)를 붙이면 이 [Sprite]가 특정 뼈(bone)
/// 의 attachment로 대신 들어가게 된다 — 로딩 자체는 지금 코드를 그대로
/// 재사용할 수 있다.
Future<Sprite> loadN1FootSprite() => RemoteSpriteLoader.loadSprite(PlayerN1Assets.footL);

/// N1의 스킨 파츠 12장을 전부 병렬로 내려받아 "슬롯 이름 → Sprite" 맵으로
/// 돌려준다([PlayerN1Assets.partsBySlot] 참고) — 뼈대 애니메이션 라이브러리를
/// 통합했을 때, 스켈레톤의 각 슬롯에 어떤 이미지를 입힐지(스킨 적용)
/// 결정하는 로직이 정확히 "슬롯 이름으로 Sprite를 찾는" 형태가 되므로,
/// 그 시점에 이 함수가 반환하는 맵을 그대로 룩업 테이블로 쓸 수 있다.
Future<Map<String, Sprite>> loadN1SkinParts() async {
  final List<String> slots = PlayerN1Assets.partsBySlot.keys.toList();
  final List<Sprite> sprites = await Future.wait(
    PlayerN1Assets.partsBySlot.values.map(RemoteSpriteLoader.loadSprite),
  );
  return Map<String, Sprite>.fromIterables(slots, sprites);
}
