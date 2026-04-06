import 'models/danmaku_item.dart';
import 'package:flutter/material.dart';
import 'package:pure_live/pkg/canvas_danmaku/utils/utils.dart';

class ScrollDanmakuPainter extends CustomPainter {
  final double progress;
  final List<DanmakuItem> scrollDanmakuItems;
  final int danmakuDurationInSeconds;
  final double fontSize;
  final int fontWeight;
  final bool showStroke;
  final double danmakuHeight;
  final bool running;
  final int tick;
  final double opacity;

  final double totalDuration;
  static final Paint _selfSendPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.green;

  static final Paint _layerPaint = Paint();

  ScrollDanmakuPainter(
    this.progress,
    this.scrollDanmakuItems,
    this.danmakuDurationInSeconds,
    this.fontSize,
    this.fontWeight,
    this.showStroke,
    this.danmakuHeight,
    this.running,
    this.tick, {
    this.opacity = 1.0,
  }) : totalDuration = danmakuDurationInSeconds * 1000;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity < 1.0) {
      _layerPaint.color = Color.fromRGBO(0, 0, 0, opacity);
      canvas.saveLayer(null, _layerPaint);
    }
    _drawDanmakus(canvas, size, size.width);
    if (opacity < 1.0) {
      canvas.restore();
    }
  }

  void _drawDanmakus(Canvas canvas, Size size, double startPosition) {
    for (var item in scrollDanmakuItems) {
      item.lastDrawTick ??= item.creationTime;
      final currentWidth = item.cachedWidth;
      final endPosition = -currentWidth!;
      final distance = startPosition - endPosition;
      item.xPosition = item.xPosition + (((item.lastDrawTick! - tick) / totalDuration) * distance);
      if (item.xPosition < -currentWidth || item.xPosition > size.width) {
        continue;
      }
      Utils.drawMixedContent(
        canvas,
        item.content,
        Offset(item.xPosition, item.yPosition),
        fontSize,
        fontWeight,
        showStroke,
        item.content.selfSend,
        _selfSendPaint,
      );
      item.lastDrawTick = tick;
    }
  }

  @override
  bool shouldRepaint(covariant ScrollDanmakuPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        scrollDanmakuItems.length != oldDelegate.scrollDanmakuItems.length ||
        tick != oldDelegate.tick ||
        fontSize != oldDelegate.fontSize ||
        showStroke != oldDelegate.showStroke ||
        opacity != oldDelegate.opacity;
  }
}
