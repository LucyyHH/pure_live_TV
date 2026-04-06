import 'dart:math';
import 'package:flutter/material.dart';
import 'package:pure_live/pkg/canvas_danmaku/models/danmaku_item.dart';
import 'package:pure_live/pkg/canvas_danmaku/models/danmaku_content_item.dart';

class SpecialDanmakuPainter extends CustomPainter {
  final double progress;
  final List<DanmakuItem> specialDanmakuItems;
  final double fontSize;
  final int fontWeight;
  final bool running;
  final int tick;
  final double opacity;

  static final Paint _layerPaint = Paint();

  SpecialDanmakuPainter(
    this.progress,
    this.specialDanmakuItems,
    this.fontSize,
    this.fontWeight,
    this.running,
    this.tick, {
    this.opacity = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity < 1.0) {
      _layerPaint.color = Color.fromRGBO(0, 0, 0, opacity);
      canvas.saveLayer(null, _layerPaint);
    }
    for (final item in specialDanmakuItems) {
      final elapsed = tick - item.creationTime;
      final content = item.content as SpecialDanmakuContentItem;
      if (elapsed >= 0 && elapsed < content.duration) {
        _paintSpecialDanmaku(canvas, content, size, elapsed);
      }
    }
    if (opacity < 1.0) {
      canvas.restore();
    }
  }

  void _paintSpecialDanmaku(Canvas canvas, SpecialDanmakuContentItem item, Size size, int elapsed) {
    late final alpha = item.alphaTween?.transform(elapsed / item.duration) ?? item.color.a;

    final color = item.alphaTween == null ? item.color : item.color.withValues(alpha: alpha);
    if (color != item.painterCache?.text?.style?.color) {
      item.painterCache!.text = TextSpan(
        text: item.text,
        style: TextStyle(
          color: color,
          fontSize: item.fontSize,
          fontWeight: FontWeight.values[fontWeight],
          shadows: item.hasStroke ? [Shadow(color: Colors.black.withValues(alpha: alpha), blurRadius: 2)] : null,
        ),
      );
      item.painterCache!.layout();
    }

    late double dx, dy;
    if (elapsed > item.translationStartDelay) {
      late double translateProgress = item.easingType.transform(
        min(1.0, (elapsed - item.translationStartDelay) / item.translationDuration),
      );

      double getOffset(Tween<double> tween) =>
          tween is ConstantTween ? tween.begin! : tween.transform(translateProgress);

      dx = getOffset(item.translateXTween) * size.width;
      dy = getOffset(item.translateYTween) * size.height;
    } else {
      dx = item.translateXTween.begin! * size.width;
      dy = item.translateYTween.begin! * size.height;
    }

    if (item.matrix != null) {
      canvas.save();
      canvas.translate(dx, dy);
      canvas.transform(item.matrix!.storage);
      item.painterCache!.paint(canvas, Offset.zero);
      canvas.restore();
    } else {
      item.painterCache!.paint(canvas, Offset(dx, dy));
    }
  }

  @override
  bool shouldRepaint(covariant SpecialDanmakuPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        specialDanmakuItems.length != oldDelegate.specialDanmakuItems.length ||
        tick != oldDelegate.tick ||
        fontSize != oldDelegate.fontSize ||
        opacity != oldDelegate.opacity;
  }
}
