import 'package:flutter/material.dart';

import '../constants/app_images.dart';
import 'safe_image.dart';

/// 캐릭터 이미지를 보여주는 공용 위젯 — [isFullBody]로 어떤 파일을 불러올지만
/// 분기한다(강제 확대/크롭 로직은 없음. 각 파일 자체가 용도에 맞게 이미
/// 잘려있다):
///   - false(기본값): 인벤토리 슬롯, 뽑기 결과 슬롯, 캐릭터 상세 팝업
///     헤더처럼 작은 정사각형 안에서 얼굴~어깨가 예쁘게 잘려있는 전용
///     썸네일([AppImages.playerThumbnail])을 그대로 보여준다.
///   - true: 캐릭터 탭 중앙의 메인 장착 카드처럼 큰 영역에서 정면 전신
///     이미지([AppImages.playerFront])를 보여준다.
/// 두 경우 모두 [BoxFit.cover] + [ClipRRect]로 카드 프레임을 여백 없이
/// 꽉 채우고 둥근 모서리 밖으로 삐져나가지 않게 한다(카드 비율과 이미지
/// 비율이 다르면 위아래/좌우 일부가 잘릴 수 있다 — 여백보다 꽉 찬 프레임을
/// 우선한 의도적 선택). 픽셀 아트라 확대해도 흐려지지 않도록
/// [FilterQuality.none]을 쓴다.
class CharacterFacePortrait extends StatelessWidget {
  const CharacterFacePortrait({
    super.key,
    required this.characterId,
    this.size,
    this.borderRadius = 0,
    this.isFullBody = false,
  });

  final String characterId;

  /// null이면 부모가 준 제약(Positioned.fill, 고정 크기 Container 등)에
  /// 맞춰 채워지고, 값을 주면 그 크기의 정사각형으로 스스로를 감싼다.
  final double? size;
  final double borderRadius;

  /// true면 전신(player_front.png), false면 얼굴 썸네일(player_thumbnail.png).
  final bool isFullBody;

  @override
  Widget build(BuildContext context) {
    final String path = isFullBody
        ? AppImages.playerFront(characterId)
        : AppImages.playerThumbnail(characterId);

    final Widget clipped = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CustomSafeImage(
        path: path,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.none,
      ),
    );

    final double? boxSize = size;
    if (boxSize == null) {
      return clipped;
    }
    return SizedBox(width: boxSize, height: boxSize, child: clipped);
  }
}
