import 'dart:math';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:pure_live/pkg/canvas_danmaku/utils/utils.dart';
import 'package:pure_live/pkg/canvas_danmaku/danmaku_controller.dart';
import 'package:pure_live/pkg/canvas_danmaku/models/danmaku_item.dart';
import 'package:pure_live/pkg/canvas_danmaku/models/danmaku_option.dart';
import 'package:pure_live/pkg/canvas_danmaku/scroll_danmaku_painter.dart';
import 'package:pure_live/pkg/canvas_danmaku/models/danmaku_content_item.dart';

class DanmakuScreen extends StatefulWidget {
  final DanmakuController controller;
  final DanmakuOption option;

  const DanmakuScreen({
    required this.controller,
    required this.option,
    super.key,
  });

  @override
  State<DanmakuScreen> createState() => _DanmakuScreenState();
}

class _DanmakuScreenState extends State<DanmakuScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  double _viewWidth = 0;
  double _viewHeight = 0;
  late DanmakuController _controller;
  late Ticker _ticker;
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  DanmakuOption _option = DanmakuOption();

  final Map<double, List<DanmakuItem>> _scrollDanmakuByTrack = {};
  final List<DanmakuItem> _topDanmakuItems = [];
  final List<DanmakuItem> _bottomDanmakuItems = [];
  final List<DanmakuItem> _specialDanmakuItems = [];
  static final List<FontWeight> _fontWeights = FontWeight.values;
  late double _danmakuHeight;
  late int _trackCount;
  final List<double> _trackYPositions = [];
  final _random = Random();
  int _tick = 0;
  int _tickerStart = 0;
  int _lastCleanup = 0;
  bool _running = true;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _option = widget.option;
    _running = _controller.running;
    _controller.option = _option;
    _bindControllerCallbacks();
    _ticker = createTicker((elapsed) {
      _tick = _tickerStart + elapsed.inMilliseconds;
      if (_tick - _lastCleanup >= 250) {
        _lastCleanup = _tick;
        _removeExpired();
      }
      _repaint.value++;
      if (!_hasItems) _ticker.stop();
    });

    WidgetsBinding.instance.addObserver(this);
    _calculateTracksGeometry();
  }

  void _bindControllerCallbacks() {
    _controller.bind(
      owner: this,
      onAddDanmaku: addDanmaku,
      onUpdateOption: updateOption,
      onPause: pause,
      onResume: resume,
      onClear: clearDanmakus,
    );
  }

  void _calculateTracksGeometry() {
    final textPainter = TextPainter(
      text: TextSpan(
        text: "danmaku",
        style: TextStyle(fontSize: _option.fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _danmakuHeight = textPainter.height;
    textPainter.dispose();

    if (_viewWidth <= 0 || _viewHeight <= 0) return;

    final topOffset = _option.topAreaDistance;
    final bottomOffset = _option.bottomAreaDistance;
    double displayHeight =
        (_viewHeight - topOffset - bottomOffset) * _option.area;

    _trackCount = (displayHeight / _danmakuHeight).floor().clamp(0, 999);
    _trackYPositions.clear();
    for (int i = 0; i < _trackCount; i++) {
      _trackYPositions.add(topOffset + (i * _danmakuHeight));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      pause();
    } else if (state == AppLifecycleState.resumed && _controller.running) {
      resume();
    }
  }

  @override
  void dispose() {
    _running = false;
    WidgetsBinding.instance.removeObserver(this);
    _controller.detach(this);
    _ticker.dispose();
    _repaint.dispose();
    _disposeSpecialItems();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DanmakuScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != _controller) {
      _controller.detach(this);
      _controller = widget.controller;
      if (_controller.running) {
        resume();
      } else {
        pause();
      }
    }
    _controller.option = _option;
    _bindControllerCallbacks();
  }

  void addDanmaku(DanmakuContentItem content) {
    if (!_running || !mounted || _trackYPositions.isEmpty) return;
    if (content.type == DanmakuItemType.special) {
      if (!_option.hideSpecial) {
        final special = content as SpecialDanmakuContentItem;
        special.painterCache = TextPainter(
          text: TextSpan(
            text: content.text,
            style: TextStyle(
              color: content.color,
              fontSize: content.fontSize,
              fontWeight:
                  _fontWeights[_option.fontWeight.clamp(
                    0,
                    _fontWeights.length - 1,
                  )],
              shadows: content.hasStroke
                  ? [
                      Shadow(
                        color: Colors.black.withAlpha(
                          (255 * (special.alphaTween?.begin ?? content.color.a))
                              .toInt(),
                        ),
                        blurRadius: 2,
                      ),
                    ]
                  : null,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        _specialDanmakuItems.add(
          DanmakuItem(
            width: 0,
            height: 0,
            creationTime: _tick,
            content: content,
            paragraph: null,
            strokeParagraph: null,
          ),
        );
      }
      _startTick();
      return;
    }

    final layout = Utils.layout(
      content,
      _option.fontSize,
      _option.fontWeight,
      _option.showStroke,
    );
    final danmakuWidth = layout.width;
    final danmakuHeight = _danmakuHeight;
    final paragraph = layout.mainParagraph;
    final strokeParagraph = layout.strokeParagraph;

    int idx = 1;
    for (double yPosition in _trackYPositions) {
      if (content.type == DanmakuItemType.scroll && !_option.hideScroll) {
        if (_scrollCanAddToTrack(yPosition, danmakuWidth)) {
          _scrollDanmakuByTrack
              .putIfAbsent(yPosition, () => [])
              .add(
                DanmakuItem(
                  yPosition: yPosition,
                  xPosition: _viewWidth,
                  width: danmakuWidth,
                  height: danmakuHeight,
                  creationTime: _tick,
                  content: content,
                  paragraph: paragraph,
                  layout: layout,
                  strokeParagraph: strokeParagraph,
                  cachedWidth: danmakuWidth,
                ),
              );
          break;
        }
        if (content.selfSend && idx == _trackCount) {
          final targetY = _trackYPositions.isNotEmpty
              ? _trackYPositions[0]
              : 0.0;
          _scrollDanmakuByTrack
              .putIfAbsent(targetY, () => [])
              .add(
                DanmakuItem(
                  yPosition: targetY,
                  xPosition: _viewWidth,
                  width: danmakuWidth,
                  height: danmakuHeight,
                  creationTime: _tick,
                  content: content,
                  paragraph: paragraph,
                  layout: layout,
                  strokeParagraph: strokeParagraph,
                  cachedWidth: danmakuWidth,
                ),
              );
          break;
        }
        if (_option.massiveMode && idx == _trackCount) {
          final randomY =
              _trackYPositions[_random.nextInt(_trackYPositions.length)];
          _scrollDanmakuByTrack
              .putIfAbsent(randomY, () => [])
              .add(
                DanmakuItem(
                  yPosition: randomY,
                  xPosition: _viewWidth,
                  width: danmakuWidth,
                  height: danmakuHeight,
                  creationTime: _tick,
                  content: content,
                  paragraph: paragraph,
                  layout: layout,
                  strokeParagraph: strokeParagraph,
                  cachedWidth: danmakuWidth,
                ),
              );
          break;
        }
      }

      if (content.type == DanmakuItemType.top && !_option.hideTop) {
        if (_topCanAddToTrack(yPosition)) {
          _topDanmakuItems.add(
            DanmakuItem(
              yPosition: yPosition,
              xPosition: _viewWidth,
              width: danmakuWidth,
              height: danmakuHeight,
              creationTime: _tick,
              content: content,
              paragraph: paragraph,
              layout: layout,
              strokeParagraph: strokeParagraph,
            ),
          );
          break;
        }
      }

      if (content.type == DanmakuItemType.bottom && !_option.hideBottom) {
        if (_bottomCanAddToTrack(yPosition)) {
          _bottomDanmakuItems.add(
            DanmakuItem(
              yPosition: yPosition,
              xPosition: _viewWidth,
              width: danmakuWidth,
              height: danmakuHeight,
              creationTime: _tick,
              content: content,
              paragraph: paragraph,
              layout: layout,
              strokeParagraph: strokeParagraph,
            ),
          );
          break;
        }
      }
      idx++;
    }

    _startTick();
  }

  bool get _hasItems =>
      _scrollDanmakuByTrack.isNotEmpty ||
      _topDanmakuItems.isNotEmpty ||
      _bottomDanmakuItems.isNotEmpty ||
      _specialDanmakuItems.isNotEmpty;

  void _startTick() {
    if (_running && _hasItems && !_ticker.isActive) {
      _tickerStart = _tick;
      _ticker.start();
    }
  }

  void pause() {
    if (!mounted) return;
    _running = false;
    _ticker.stop();
  }

  void resume() {
    if (!mounted) return;
    _running = true;
    _startTick();
  }

  void updateOption(DanmakuOption option) {
    final layoutChanged =
        option.fontSize != _option.fontSize ||
        option.fontWeight != _option.fontWeight ||
        option.showStroke != _option.showStroke;
    _option = option;
    _controller.option = option;
    if (option.hideScroll) _scrollDanmakuByTrack.clear();
    if (option.hideTop) _topDanmakuItems.clear();
    if (option.hideBottom) _bottomDanmakuItems.clear();
    if (option.hideSpecial) _disposeSpecialItems();
    _calculateTracksGeometry();
    if (layoutChanged) {
      for (final item in [
        ..._scrollDanmakuByTrack.values.expand((items) => items),
        ..._topDanmakuItems,
        ..._bottomDanmakuItems,
      ]) {
        final layout = Utils.layout(
          item.content,
          option.fontSize,
          option.fontWeight,
          option.showStroke,
        );
        item.layout = layout;
        item.width = layout.width;
        item.cachedWidth = layout.width;
        item.paragraph = layout.mainParagraph;
        item.strokeParagraph = layout.strokeParagraph;
      }
    }
    _removeExpired();
    if (!_hasItems) _ticker.stop();
    _startTick();
    if (mounted) setState(() {});
  }

  void _disposeSpecialItems() {
    for (final item in _specialDanmakuItems) {
      (item.content as SpecialDanmakuContentItem).painterCache?.dispose();
    }
    _specialDanmakuItems.clear();
  }

  void clearDanmakus() {
    if (!mounted) return;
    _scrollDanmakuByTrack.clear();
    _topDanmakuItems.clear();
    _bottomDanmakuItems.clear();
    _disposeSpecialItems();
    _ticker.stop();
    _repaint.value++;
  }

  bool _scrollCanAddToTrack(double yPosition, double newDanmakuWidth) {
    final trackItems = _scrollDanmakuByTrack[yPosition];
    if (trackItems == null || trackItems.isEmpty) return true;

    final item = trackItems.last;

    final int elapsedTime = _tick - item.creationTime;
    final double timeProgress = elapsedTime / (_option.duration * 1000);
    final double currentX =
        _viewWidth + ((-item.width) - _viewWidth) * timeProgress;

    final existingEndPosition = currentX + item.width;

    if (_viewWidth - existingEndPosition < 0) return false;
    if (item.width < newDanmakuWidth) {
      if ((1 - ((_viewWidth - currentX) / (item.width + _viewWidth))) >
          (_viewWidth / (_viewWidth + newDanmakuWidth))) {
        return false;
      }
    }
    return true;
  }

  bool _topCanAddToTrack(double yPosition) {
    for (var item in _topDanmakuItems) {
      if (item.yPosition == yPosition) return false;
    }
    return true;
  }

  bool _bottomCanAddToTrack(double yPosition) {
    for (var item in _bottomDanmakuItems) {
      if (item.yPosition == yPosition) return false;
    }
    return true;
  }

  void _removeExpired() {
    final duration = _option.duration * 1000;
    bool expired(DanmakuItem item) => _tick - item.creationTime >= duration;
    for (final items in _scrollDanmakuByTrack.values) {
      items.removeWhere(expired);
    }
    _scrollDanmakuByTrack.removeWhere((_, items) => items.isEmpty);
    _topDanmakuItems.removeWhere(expired);
    _bottomDanmakuItems.removeWhere(expired);
    _specialDanmakuItems.removeWhere((item) {
      final content = item.content as SpecialDanmakuContentItem;
      if (_tick - item.creationTime < content.duration) return false;
      content.painterCache?.dispose();
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth != _viewWidth ||
            constraints.maxHeight != _viewHeight) {
          _viewWidth = constraints.maxWidth;
          _viewHeight = constraints.maxHeight;
          _calculateTracksGeometry();
        }

        return RepaintBoundary(
          child: ClipRect(
            child: IgnorePointer(
              child: Opacity(
                opacity: _option.opacity,
                child: CustomPaint(
                  size: Size(_viewWidth, _viewHeight),
                  painter: ScrollDanmakuPainter(
                    _scrollDanmakuByTrack,
                    _option.duration,
                    _option.fontSize,
                    _option.fontWeight,
                    _option.showStroke,
                    repaint: _repaint,
                    clock: () => _tick,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
