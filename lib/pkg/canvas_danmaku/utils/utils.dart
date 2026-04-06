import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pure_live/plugins/emoji_manager.dart';
import 'package:pure_live/pkg/canvas_danmaku/models/danmaku_content_item.dart';

class Utils {
  static final Paint _emojiPaint = Paint()..filterQuality = FilterQuality.high;

  static final Paint _strokeForeground = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.8
    ..color = Colors.black54;

  static void drawMixedContent(
    Canvas canvas,
    DanmakuContentItem content,
    Offset offset,
    double fontSize,
    int fontWeight,
    bool showStroke,
    bool selfSend,
    Paint? selfSendPaint,
  ) {
    double currentX = offset.dx;
    final currentY = offset.dy;
    final emojiSize = fontSize * 1.2;

    if (selfSend && selfSendPaint != null) {
      double totalWidth = 0;
      for (final item in content.mixedContent) {
        if (item.type == ContentType.text) {
          final painter = _ensurePainterCached(item, content.color, fontSize, fontWeight);
          totalWidth += painter.width;
        } else {
          totalWidth += emojiSize;
        }
      }
      canvas.drawRect(Rect.fromLTWH(currentX, currentY, totalWidth, fontSize), selfSendPaint);
    }

    for (final item in content.mixedContent) {
      if (item.type == ContentType.text) {
        final textPainter = _ensurePainterCached(item, content.color, fontSize, fontWeight);
        final strokePainter = _ensureStrokePainterCached(item, fontSize, fontWeight);
        strokePainter.paint(canvas, Offset(currentX, currentY));
        textPainter.paint(canvas, Offset(currentX, currentY));
        currentX += textPainter.width;
      } else {
        final image = EmojiManager.getEmoji(item.value);
        if (image != null) {
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
            Rect.fromLTWH(currentX, currentY, emojiSize, emojiSize),
            _emojiPaint,
          );
        } else {
          final textPainter = _ensurePainterCached(item, content.color, fontSize, fontWeight);
          textPainter.paint(canvas, Offset(currentX, currentY));
        }
        currentX += emojiSize;
      }
    }
  }

  static TextPainter _ensurePainterCached(MixedContent item, Color color, double fontSize, int fontWeight) {
    if (item.cachedPainter != null) return item.cachedPainter!;
    item.cachedPainter = TextPainter(
      text: TextSpan(
        text: item.value,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.values[fontWeight]),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return item.cachedPainter!;
  }

  static TextPainter _ensureStrokePainterCached(MixedContent item, double fontSize, int fontWeight) {
    if (item.cachedStrokePainter != null) return item.cachedStrokePainter!;
    item.cachedStrokePainter = TextPainter(
      text: TextSpan(
        text: item.value,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.values[fontWeight],
          foreground: _strokeForeground,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return item.cachedStrokePainter!;
  }

  static ui.Paragraph generateParagraph(
    DanmakuContentItem content,
    double danmakuWidth,
    double fontSize,
    int fontWeight,
  ) {
    final ui.ParagraphBuilder builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: TextAlign.left,
              fontSize: fontSize,
              fontWeight: FontWeight.values[fontWeight],
              textDirection: TextDirection.ltr,
            ),
          )
          ..pushStyle(ui.TextStyle(color: content.color))
          ..addText(content.text);
    return builder.build()..layout(ui.ParagraphConstraints(width: danmakuWidth));
  }

  static ui.Paragraph generateStrokeParagraph(
    DanmakuContentItem content,
    double danmakuWidth,
    double fontSize,
    int fontWeight,
  ) {
    final Paint strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black;

    final ui.ParagraphBuilder strokeBuilder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: TextAlign.left,
              fontSize: fontSize,
              fontWeight: FontWeight.values[fontWeight],
              textDirection: TextDirection.ltr,
            ),
          )
          ..pushStyle(ui.TextStyle(foreground: strokePaint))
          ..addText(content.text);

    return strokeBuilder.build()..layout(ui.ParagraphConstraints(width: danmakuWidth));
  }
}
