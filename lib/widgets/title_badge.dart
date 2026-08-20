import 'package:flutter/material.dart';

import '../models/title_model.dart';
import 'safe_image.dart';

/// 칭호 하나를 시각적으로 표현하는 위젯 — [PlayerTitle.webpPath]가 있으면
/// 움직이는 WebP 이미지를 그대로 재생하고([CustomSafeImage]가 애니메이션
/// WebP를 네이티브로 재생), 없거나 로드에 실패하면(파일 삭제/네트워크
/// 오류 등) 이름 텍스트에 그라디언트 배경을 덧댄 배지로 조용히
/// 대체한다(요구사항: "폴백 로직").
class TitleBadge extends StatelessWidget {
  const TitleBadge({super.key, required this.title, this.height = 22});

  final PlayerTitle title;
  final double height;

  Widget _textFallback(BuildContext context) {
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: height * 0.45),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFC9A24B), Color(0xFF6C4FCE)]),
        borderRadius: BorderRadius.circular(height / 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        title.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: height * 0.55,
          shadows: const [Shadow(color: Colors.black54, blurRadius: 2)],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? webp = title.webpPath;
    if (webp == null || webp.trim().isEmpty) {
      return _textFallback(context);
    }
    return SizedBox(
      height: height,
      child: CustomSafeImage(
        path: webp,
        height: height,
        fit: BoxFit.contain,
        fallbackBuilder: _textFallback,
      ),
    );
  }
}
