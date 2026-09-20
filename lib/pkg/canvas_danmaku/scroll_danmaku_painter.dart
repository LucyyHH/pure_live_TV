import 'models/danmaku_item.dart';
import 'package:flutter/material.dart';
import 'package:pure_live/pkg/canvas_danmaku/utils/utils.dart';

class ScrollDanmakuPainter extends CustomPainter {
  final Map<double, List<DanmakuItem>> scrollDanmakuByTrack;
  final int danmakuDurationInSeconds;
  final double fontSize;
  final int fontWeight;
  final bool showStroke;
  final double totalDuration;
  final int Function() clock;

  static final Paint _selfSendPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.green;

  ScrollDanmakuPainter(
    this.scrollDanmakuByTrack,
    this.danmakuDurationInSeconds,
    this.fontSize,
    this.fontWeight,
    this.showStroke, {
    super.repaint,
    required this.clock,
  }) : totalDuration = danmakuDurationInSeconds * 1000;

  @override
  void paint(Canvas canvas, Size size) {
    final now = clock();
    final double startPosition = size.width;

    for (final items in scrollDanmakuByTrack.values) {
      for (final item in items) {
        final currentWidth = item.width;

        final int elapsedTime = now - item.creationTime;
        final double timeProgress = elapsedTime / totalDuration;

        if (timeProgress >= 1.0 || timeProgress < 0) continue;

        final double endPosition = -currentWidth;
        final double currentX =
            startPosition + (endPosition - startPosition) * timeProgress;

        item.xPosition = currentX;

        if (currentX < -currentWidth || currentX > size.width) {
          continue;
        }

        final layout = item.layout ??= Utils.layout(
          item.content,
          fontSize,
          fontWeight,
          showStroke,
        );
        Utils.drawParagraph(
          canvas,
          layout,
          Offset(currentX, item.yPosition),
          item.content.selfSend,
          _selfSendPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant ScrollDanmakuPainter oldDelegate) {
    return scrollDanmakuByTrack.length !=
            oldDelegate.scrollDanmakuByTrack.length ||
        fontSize != oldDelegate.fontSize ||
        fontWeight != oldDelegate.fontWeight ||
        showStroke != oldDelegate.showStroke;
  }
}
