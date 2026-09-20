import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/pkg/canvas_danmaku/danmaku_controller.dart';
import 'package:pure_live/pkg/canvas_danmaku/danmaku_screen.dart';
import 'package:pure_live/pkg/canvas_danmaku/models/danmaku_content_item.dart';
import 'package:pure_live/pkg/canvas_danmaku/models/danmaku_option.dart';
import 'package:pure_live/pkg/canvas_danmaku/scroll_danmaku_painter.dart';

void main() {
  testWidgets('expired scrolling items are removed and idle frames stop', (
    tester,
  ) async {
    final controller = DanmakuController();
    await tester.pumpWidget(
      MaterialApp(
        home: DanmakuScreen(
          controller: controller,
          option: DanmakuOption(duration: 1),
        ),
      ),
    );
    ScrollDanmakuPainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.painter)
        .whereType<ScrollDanmakuPainter>()
        .single;
    expect(tester.binding.hasScheduledFrame, isFalse);
    final originalPainter = painter();
    controller.addDanmaku(DanmakuContentItem('test', selfSend: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(painter().scrollDanmakuByTrack, isNotEmpty);
    expect(
      identical(painter(), originalPainter),
      isTrue,
      reason: 'ticks should repaint without rebuilding',
    );
    controller.pause();
    await tester.pump(const Duration(seconds: 5));
    expect(
      painter().scrollDanmakuByTrack,
      isNotEmpty,
      reason: 'pause freezes lifetime',
    );
    controller.resume();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(painter().scrollDanmakuByTrack, isEmpty);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    controller.addDanmaku(DanmakuContentItem('again'));
    await tester.pump();
    expect(painter().scrollDanmakuByTrack, isNotEmpty);
    controller.clear();
    await tester.pump();
    expect(painter().scrollDanmakuByTrack, isEmpty);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
    controller.addDanmaku(DanmakuContentItem('after dispose'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing an old view does not detach the replacement view', (
    tester,
  ) async {
    final controller = DanmakuController();

    Future<void> show(int generation) => tester.pumpWidget(
      MaterialApp(
        home: DanmakuScreen(
          key: ValueKey(generation),
          controller: controller,
          option: DanmakuOption(),
        ),
      ),
    );

    await show(1);
    await show(2);
    controller.addDanmaku(DanmakuContentItem('after player fallback'));
    await tester.pump();

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.painter)
        .whereType<ScrollDanmakuPainter>()
        .single;
    expect(painter.scrollDanmakuByTrack, isNotEmpty);
  });
}
