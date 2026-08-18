import 'dart:convert';

import 'package:flutter/services.dart';

/// 1×1 투명 PNG 원본 바이트 — 실제 파일 없이도 [Image.asset]/[precacheImage]
/// 등이 "정상적으로 디코딩 가능한 이미지"를 돌려받아야 하는 테스트에서 쓴다.
final Uint8List kDummyPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

/// pubspec.yaml에는 등록돼 있지만 아직 실제 파일이 없는(예: 아트팀이 아직
/// 전달하지 않은) 로컬 에셋 키만 더미 PNG로 가로채고, 그 외 나머지는 전부
/// 원래 [rootBundle]에 그대로 위임하는 테스트 전용 자산 번들.
///
/// [HeroManager.heroImagePath]처럼 실물 파일이 아직 준비되지 않은 로컬
/// 에셋을 참조하는 위젯을, 실제 파일을 저장소에 커밋하지 않고도 "정상
/// 로드" 경로로 테스트하고 싶을 때 `DefaultAssetBundle(bundle: ..., child:
/// ...)`로 감싸 쓴다 — 파일이 여전히 없으므로 프로덕션 동작(로드 실패 시
/// [HeroManager.buildHeroSprite]의 errorBuilder가 대체 아이콘을 그리는 것)
/// 에는 전혀 영향을 주지 않는다.
class FakeAssetBundle extends CachingAssetBundle {
  FakeAssetBundle(this._dummyKeys);

  /// 더미 PNG로 응답할 asset 키 집합 — 이 목록에 없는 키는 항상
  /// [rootBundle]로 그대로 넘어간다.
  final Set<String> _dummyKeys;

  @override
  Future<ByteData> load(String key) {
    if (_dummyKeys.contains(key)) {
      return Future.value(ByteData.sublistView(kDummyPngBytes));
    }
    return rootBundle.load(key);
  }
}
