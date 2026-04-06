import 'dart:math';
import 'dart:ui' as ui;
import 'danmaku_controller.dart';
import 'models/danmaku_item.dart';
import 'models/danmaku_option.dart';
import 'scroll_danmaku_painter.dart';
import 'static_danmaku_painter.dart';
import 'special_danmaku_painter.dart';
import 'package:flutter/material.dart';
import 'package:pure_live/pkg/canvas_danmaku/utils/utils.dart';
import 'package:pure_live/pkg/canvas_danmaku/models/danmaku_content_item.dart';

class DanmakuScreen extends StatefulWidget {
  final DanmakuController controller;
  final DanmakuOption option;

  const DanmakuScreen({required this.controller, required this.option, super.key});

  @override
  State<DanmakuScreen> createState() => _DanmakuScreenState();
}

class _DanmakuScreenState extends State<DanmakuScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  double _viewWidth = 0;

  late DanmakuController _controller;

  late AnimationController _animationController;
  late AnimationController _staticAnimationController;

  DanmakuOption _option = DanmakuOption();

  final Map<double, List<DanmakuItem>> _scrollDanmakuByTrack = {};
  final List<DanmakuItem> _topDanmakuItems = [];
  final List<DanmakuItem> _bottomDanmakuItems = [];
  final List<DanmakuItem> _specialDanmakuItems = [];

  double _danmakuHeight = 0;
  double _cachedFontSize = 0;

  final List<DanmakuItem> _flatScrollDanmakus = [];
  bool _flatListDirty = true;

  late int _trackCount;
  final List<double> _trackYPositions = [];

  late final _random = Random();

  int get _tick => _stopwatch.elapsedMilliseconds;
  final _stopwatch = Stopwatch();

  bool _running = true;
  bool _tickActive = false;

  static const int _maxScrollDanmakus = 80;
  static const int _cleanupIntervalMs = 50;

  /// 复用的测量用 TextPainter，避免每条弹幕都新建
  static final TextPainter _measurePainter = TextPainter(textDirection: TextDirection.ltr);

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _option = widget.option;
    _controller.option = _option;
    _bindControllerCallbacks();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: _option.duration),
    );

    _staticAnimationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: _option.duration),
    );

    WidgetsBinding.instance.addObserver(this);
  }

  void _bindControllerCallbacks() {
    _controller.onAddDanmaku = addDanmaku;
    _controller.onUpdateOption = updateOption;
    _controller.onPause = pause;
    _controller.onResume = resume;
    _controller.onClear = clearDanmakus;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      pause();
    }
  }

  @override
  void dispose() {
    _running = false;
    WidgetsBinding.instance.removeObserver(this);

    _disposeAllItems();

    _animationController.dispose();
    _staticAnimationController.dispose();
    _stopwatch.stop();
    super.dispose();
  }

  void _disposeAllItems() {
    _scrollDanmakuByTrack.forEach((_, items) {
      for (final item in items) {
        item.dispose();
      }
    });
    _scrollDanmakuByTrack.clear();
    for (final item in _topDanmakuItems) {
      item.dispose();
    }
    _topDanmakuItems.clear();
    for (final item in _bottomDanmakuItems) {
      item.dispose();
    }
    _bottomDanmakuItems.clear();
    for (final item in _specialDanmakuItems) {
      item.dispose();
    }
    _specialDanmakuItems.clear();
    _flatScrollDanmakus.clear();
    _flatListDirty = true;
  }

  @override
  void didUpdateWidget(covariant DanmakuScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller == _controller) {
      _bindControllerCallbacks();
    } else {
      _controller = widget.controller;
      _bindControllerCallbacks();
    }
  }

  int get _totalScrollDanmakuCount {
    int count = 0;
    _scrollDanmakuByTrack.forEach((_, items) => count += items.length);
    return count;
  }

  void addDanmaku(DanmakuContentItem content) {
    if (!_running || !mounted) {
      return;
    }
    if (content.type == DanmakuItemType.special) {
      if (!_option.hideSpecial) {
        (content as SpecialDanmakuContentItem).painterCache = TextPainter(
          text: TextSpan(
            text: content.text,
            style: TextStyle(
              color: content.color,
              fontSize: content.fontSize,
              fontWeight: FontWeight.values[_option.fontWeight],
              shadows: content.hasStroke
                  ? [
                      Shadow(
                        color: Colors.black.withAlpha((255 * (content.alphaTween?.begin ?? content.color.a)).toInt()),
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
          ),
        );
      } else {
        return;
      }
    } else {
      _measurePainter.text = TextSpan(
        text: content.text,
        style: TextStyle(fontSize: _option.fontSize, fontWeight: FontWeight.values[_option.fontWeight]),
      );
      _measurePainter.layout();
      final danmakuWidth = _measurePainter.width;
      final danmakuHeight = _measurePainter.height;

      // 只为静态弹幕（顶部/底部）创建 Paragraph，滚动弹幕使用 TextPainter 绘制不需要
      final bool isScroll = content.type == DanmakuItemType.scroll;
      ui.Paragraph? paragraph;
      ui.Paragraph? strokeParagraph;
      if (!isScroll) {
        paragraph = Utils.generateParagraph(content, danmakuWidth, _option.fontSize, _option.fontWeight);
        if (_option.showStroke) {
          strokeParagraph = Utils.generateStrokeParagraph(content, danmakuWidth, _option.fontSize, _option.fontWeight);
        }
      }

      int idx = 1;
      for (double yPosition in _trackYPositions) {
        if (content.type == DanmakuItemType.scroll && !_option.hideScroll) {
          if (_totalScrollDanmakuCount >= _maxScrollDanmakus) break;

          bool scrollCanAddToTrack = _scrollCanAddToTrack(yPosition, danmakuWidth);

          if (scrollCanAddToTrack) {
            if (!_scrollDanmakuByTrack.containsKey(yPosition)) {
              _scrollDanmakuByTrack[yPosition] = [];
            }
            _scrollDanmakuByTrack[yPosition]!.add(
              DanmakuItem(
                yPosition: yPosition,
                xPosition: _viewWidth,
                width: danmakuWidth,
                height: danmakuHeight,
                creationTime: _tick,
                content: content,
                cachedWidth: danmakuWidth,
              ),
            );
            break;
          }

          if (content.selfSend && idx == _trackCount) {
            if (!_scrollDanmakuByTrack.containsKey(yPosition)) {
              _scrollDanmakuByTrack[yPosition] = [];
            }
            _scrollDanmakuByTrack[yPosition]!.add(
              DanmakuItem(
                yPosition: _trackYPositions[0],
                xPosition: _viewWidth,
                width: danmakuWidth,
                height: danmakuHeight,
                creationTime: _tick,
                content: content,
                cachedWidth: danmakuWidth,
              ),
            );
            break;
          }

          if (_option.massiveMode && idx == _trackCount) {
            var randomYPosition = _trackYPositions[_random.nextInt(_trackYPositions.length)];
            if (!_scrollDanmakuByTrack.containsKey(yPosition)) {
              _scrollDanmakuByTrack[yPosition] = [];
            }
            _scrollDanmakuByTrack[yPosition]!.add(
              DanmakuItem(
                yPosition: randomYPosition,
                xPosition: _viewWidth,
                width: danmakuWidth,
                height: danmakuHeight,
                creationTime: _tick,
                content: content,
                cachedWidth: danmakuWidth,
              ),
            );
            break;
          }
        }

        if (content.type == DanmakuItemType.top && !_option.hideTop) {
          bool topCanAddToTrack = _topCanAddToTrack(yPosition);

          if (topCanAddToTrack) {
            _topDanmakuItems.add(
              DanmakuItem(
                yPosition: yPosition,
                xPosition: _viewWidth,
                width: danmakuWidth,
                height: danmakuHeight,
                creationTime: _tick,
                content: content,
                paragraph: paragraph,
                strokeParagraph: strokeParagraph,
              ),
            );
            break;
          }
        }

        if (content.type == DanmakuItemType.bottom && !_option.hideBottom) {
          bool bottomCanAddToTrack = _bottomCanAddToTrack(yPosition);

          if (bottomCanAddToTrack) {
            _bottomDanmakuItems.add(
              DanmakuItem(
                yPosition: yPosition,
                xPosition: _viewWidth,
                width: danmakuWidth,
                height: danmakuHeight,
                creationTime: _tick,
                content: content,
                paragraph: paragraph,
                strokeParagraph: strokeParagraph,
              ),
            );
            break;
          }
        }
        idx++;
      }
    }

    switch (content.type) {
      case DanmakuItemType.top:
      case DanmakuItemType.bottom:
        _staticAnimationController.value = 0;
        _staticAnimationController.value = 0.01;
        break;
      case DanmakuItemType.scroll:
      case DanmakuItemType.special:
        _flatListDirty = true;
        if (!_animationController.isAnimating &&
            (_scrollDanmakuByTrack.isNotEmpty || _specialDanmakuItems.isNotEmpty)) {
          _animationController.repeat();
        }
        break;
    }

    _ensureTickRunning();
  }

  void pause() {
    if (!mounted) return;
    if (_running) {
      setState(() {
        _running = false;
      });
      if (_animationController.isAnimating) {
        _animationController.stop();
      }
      if (_stopwatch.isRunning) {
        _stopwatch.stop();
      }
    }
  }

  void resume() {
    if (!mounted) return;
    if (!_running) {
      setState(() {
        _running = true;
      });
      _ensureTickRunning();
    }
  }

  void updateOption(DanmakuOption option) {
    bool needRestart = false;
    bool needClearParagraph = false;
    if (_animationController.isAnimating) {
      _animationController.stop();
      needRestart = true;
    }

    if (option.fontSize != _option.fontSize) {
      needClearParagraph = true;
    }

    if (option.hideScroll && !_option.hideScroll) {
      _disposeAndClearScrollDanmakus();
    }
    if (option.hideTop && !_option.hideTop) {
      for (final item in _topDanmakuItems) {
        item.dispose();
      }
      _topDanmakuItems.clear();
    }
    if (option.hideBottom && !_option.hideBottom) {
      for (final item in _bottomDanmakuItems) {
        item.dispose();
      }
      _bottomDanmakuItems.clear();
    }
    _option = option;
    _controller.option = _option;

    if (needClearParagraph) {
      void clearItem(DanmakuItem item) {
        item.paragraph = null;
        item.strokeParagraph = null;
        for (final mc in item.content.mixedContent) {
          mc.cachedPainter?.dispose();
          mc.cachedStrokePainter?.dispose();
          mc.clearPainterCache();
        }
      }
      _scrollDanmakuByTrack.forEach((_, items) {
        for (final item in items) {
          clearItem(item);
        }
      });
      for (final item in _topDanmakuItems) {
        clearItem(item);
      }
      for (final item in _bottomDanmakuItems) {
        clearItem(item);
      }
    }
    if (needRestart) {
      _animationController.repeat();
    }
    if (!mounted) return;
    setState(() {});
  }

  void _disposeAndClearScrollDanmakus() {
    _scrollDanmakuByTrack.forEach((_, items) {
      for (final item in items) {
        item.dispose();
      }
    });
    _scrollDanmakuByTrack.clear();
    _flatScrollDanmakus.clear();
    _flatListDirty = true;
  }

  void clearDanmakus() {
    if (!mounted) return;
    _disposeAllItems();
    setState(() {});
    _animationController.stop();
  }

  bool _scrollCanAddToTrack(double yPosition, double newDanmakuWidth) {
    final trackItems = _scrollDanmakuByTrack[yPosition] ?? [];

    for (var item in trackItems) {
      final existingEndPosition = item.xPosition + item.width;
      if (_viewWidth - existingEndPosition < 0) {
        return false;
      }
      if (item.width < newDanmakuWidth) {
        if ((1 - ((_viewWidth - item.xPosition) / (item.width + _viewWidth))) >
            ((_viewWidth) / (_viewWidth + newDanmakuWidth))) {
          return false;
        }
      }
    }
    return true;
  }

  bool _topCanAddToTrack(double yPosition) {
    for (var item in _topDanmakuItems) {
      if (item.yPosition == yPosition) {
        return false;
      }
    }
    return true;
  }

  bool _bottomCanAddToTrack(double yPosition) {
    for (var item in _bottomDanmakuItems) {
      if (item.yPosition == yPosition) {
        return false;
      }
    }
    return true;
  }

  void _ensureTickRunning() {
    if (!_tickActive && _running && mounted) {
      _startTick();
    }
  }

  void _startTick() async {
    if (_tickActive) return;
    _tickActive = true;
    _stopwatch.start();
    final staticDuration = _option.duration * 1000;

    while (_running && mounted) {
      await Future.delayed(const Duration(milliseconds: _cleanupIntervalMs));

      // 1. 清理已滚出屏幕的弹幕（dispose 原生资源后再移除）
      final tracksToRemove = <double>[];
      _scrollDanmakuByTrack.forEach((trackY, items) {
        final beforeLen = items.length;
        items.removeWhere((item) {
          if (item.xPosition + item.width < 0) {
            item.dispose();
            return true;
          }
          return false;
        });
        if (items.length != beforeLen) _flatListDirty = true;
        if (items.isEmpty) {
          tracksToRemove.add(trackY);
        }
      });
      for (final trackY in tracksToRemove) {
        _scrollDanmakuByTrack.remove(trackY);
      }

      // 2. 清理过期的静态/特殊弹幕
      final topBefore = _topDanmakuItems.length;
      final bottomBefore = _bottomDanmakuItems.length;
      _topDanmakuItems.removeWhere((item) {
        if ((_tick - item.creationTime) >= staticDuration) {
          item.dispose();
          return true;
        }
        return false;
      });
      _bottomDanmakuItems.removeWhere((item) {
        if ((_tick - item.creationTime) >= staticDuration) {
          item.dispose();
          return true;
        }
        return false;
      });
      _specialDanmakuItems.removeWhere((item) {
        if ((_tick - item.creationTime) >= (item.content as SpecialDanmakuContentItem).duration) {
          item.dispose();
          return true;
        }
        return false;
      });

      // 3. 管理动画控制器启停
      final bool hasScrollOrSpecial = _scrollDanmakuByTrack.isNotEmpty || _specialDanmakuItems.isNotEmpty;
      final bool hasStatic = _topDanmakuItems.isNotEmpty || _bottomDanmakuItems.isNotEmpty;

      if (hasScrollOrSpecial) {
        if (!_animationController.isAnimating) _animationController.repeat();
      } else {
        if (_animationController.isAnimating) _animationController.stop();
      }

      // 4. 静态弹幕仅在数量变化时触发一次重绘
      final staticChanged = _topDanmakuItems.length != topBefore || _bottomDanmakuItems.length != bottomBefore;
      if (staticChanged && hasStatic) {
        _staticAnimationController.value = 0;
        _staticAnimationController.value = 0.01;
      } else if (staticChanged && !hasStatic) {
        _staticAnimationController.value = 0;
      }

      if (!hasScrollOrSpecial && !hasStatic) break;
    }

    _stopwatch.stop();
    _tickActive = false;
  }

  void _updateDanmakuHeight() {
    if (_cachedFontSize == _option.fontSize && _danmakuHeight > 0) return;
    _cachedFontSize = _option.fontSize;
    _measurePainter.text = TextSpan(text: '弹', style: TextStyle(fontSize: _option.fontSize));
    _measurePainter.layout();
    _danmakuHeight = _measurePainter.height;
  }

  List<DanmakuItem> _getFlatScrollDanmakus() {
    if (!_flatListDirty) return _flatScrollDanmakus;
    _flatScrollDanmakus.clear();
    _scrollDanmakuByTrack.forEach((_, items) => _flatScrollDanmakus.addAll(items));
    _flatListDirty = false;
    return _flatScrollDanmakus;
  }

  @override
  Widget build(BuildContext context) {
    _updateDanmakuHeight();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth != _viewWidth) {
          _viewWidth = constraints.maxWidth;
        }
        final screenHeight = constraints.maxHeight;
        final topOffset = _option.topAreaDistance;
        final bottomOffset = _option.bottomAreaDistance;
        double displayHeight = (screenHeight - topOffset - bottomOffset) * _option.area;
        _trackCount = (displayHeight / _danmakuHeight).floor();
        _trackCount.clamp(0, (displayHeight / _danmakuHeight).floor());
        _trackYPositions.clear();
        for (int i = 0; i < _trackCount; i++) {
          double trackY = topOffset + (i * _danmakuHeight);
          _trackYPositions.add(trackY);
        }

        final opacity = _option.opacity;

        return Stack(
          children: [
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              right: 0,
              child: ClipRect(
                child: IgnorePointer(
                  child: Stack(
                    children: [
                      RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _animationController,
                          builder: (context, child) {
                            return CustomPaint(
                              painter: ScrollDanmakuPainter(
                                _animationController.value,
                                _getFlatScrollDanmakus(),
                                _option.duration,
                                _option.fontSize,
                                _option.fontWeight,
                                _option.showStroke,
                                _danmakuHeight,
                                _running,
                                _tick,
                                opacity: opacity,
                              ),
                              child: const SizedBox.expand(),
                            );
                          },
                        ),
                      ),
                      RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _staticAnimationController,
                          builder: (context, child) {
                            return CustomPaint(
                              painter: StaticDanmakuPainter(
                                _staticAnimationController.value,
                                _topDanmakuItems,
                                _bottomDanmakuItems,
                                _option.duration,
                                _option.fontSize,
                                _option.fontWeight,
                                _option.showStroke,
                                _danmakuHeight,
                                _running,
                                _tick,
                                opacity: opacity,
                              ),
                              child: const SizedBox.expand(),
                            );
                          },
                        ),
                      ),
                      RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _animationController,
                          builder: (context, child) {
                            return CustomPaint(
                              painter: SpecialDanmakuPainter(
                                _animationController.value,
                                _specialDanmakuItems,
                                _option.fontSize,
                                _option.fontWeight,
                                _running,
                                _tick,
                                opacity: opacity,
                              ),
                              child: const SizedBox.expand(),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
