import 'dart:ui' as ui;
import 'package:pure_live/pkg/canvas_danmaku/models/danmaku_content_item.dart';

class DanmakuItem {
  final DanmakuContentItem content;
  final int creationTime;
  final double width;
  final double height;
  double xPosition;
  double yPosition;
  int? lastDrawTick;

  ui.Paragraph? paragraph;
  ui.Paragraph? strokeParagraph;

  double? cachedWidth;

  DanmakuItem({
    required this.content,
    required this.creationTime,
    required this.height,
    required this.width,
    this.xPosition = 0,
    this.yPosition = 0,
    this.paragraph,
    this.strokeParagraph,
    this.lastDrawTick,
    this.cachedWidth,
  });

  void dispose() {
    paragraph = null;
    strokeParagraph = null;
    for (final mc in content.mixedContent) {
      mc.cachedPainter?.dispose();
      mc.cachedStrokePainter?.dispose();
      mc.clearPainterCache();
    }
    if (content is SpecialDanmakuContentItem) {
      (content as SpecialDanmakuContentItem).painterCache?.dispose();
      (content as SpecialDanmakuContentItem).painterCache = null;
    }
  }
}
