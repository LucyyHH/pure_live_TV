import 'dart:async';
import 'dart:developer';
import 'player_pool.dart';
import 'line_fallback_manager.dart';
import '../models/player_state.dart';
import 'preload_player_manager.dart';
import '../models/player_engine.dart';
import 'engine_fallback_manager.dart';
import '../models/player_exception.dart';
import '../models/player_error_type.dart';
import 'package:rxdart/rxdart.dart' hide Rx;
import 'package:flutter/material.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/common/models/live_room.dart';
import '../interface/unified_player_interface.dart';

class PlayerManager {
  final PlayerPool playerPool;

  final EngineFallbackManager fallbackManager;

  final PreloadPlayerManager preloadManager;

  final LineFallbackManager lineManager;
  final PlayerEngine Function() preferredEngine;
  final bool Function() hardStopOnExit;
  _PlaybackSession _session = _PlaybackSession();
  Future<void>? _closeFuture;
  bool _active(_PlaybackSession session) =>
      !_disposed && identical(session, _session) && !session.cancelled;

  PlayerManager({
    required this.playerPool,
    required this.fallbackManager,
    required this.preloadManager,
    required this.lineManager,
    required this.preferredEngine,
    required this.hardStopOnExit,
  });

  // =========================
  // player
  // =========================

  UnifiedPlayer? _currentPlayer;

  PlayerEngine? _runtimeEngine;

  PlayerEngine? _defaultEngine;

  // =========================
  // play info
  // =========================

  String? _currentUrl;

  List<String> _currentPlayUrls = [];

  Map<String, String> _currentHeaders = {};

  // =========================
  // rx state
  // =========================

  final RxBool isInitialized = false.obs;

  final RxBool hasError = false.obs;

  final RxBool isVerticalVideo = false.obs;

  final RxBool isInPip = false.obs;

  final RxBool isFloating = false.obs;

  final RxBool isHovered = false.obs;

  final RxInt videoFitIndex = 0.obs;

  Rx<ValueKey> videoKey = Rx<ValueKey>(const ValueKey("video_0"));

  // =========================
  // stream state
  // =========================

  final _stateSubject = BehaviorSubject<PlayerState>.seeded(PlayerState.idle);

  final _playingSubject = BehaviorSubject<bool>.seeded(false);

  final _loadingSubject = BehaviorSubject<bool>.seeded(false);

  final _completeSubject = BehaviorSubject<bool>.seeded(false);

  final _errorSubject = PublishSubject<PlayerException>();

  final _widthSubject = BehaviorSubject<int?>.seeded(null);

  final _heightSubject = BehaviorSubject<int?>.seeded(null);

  // =========================
  // subscriptions
  // =========================

  final List<StreamSubscription> _subscriptions = [];

  // =========================
  // misc
  // =========================

  bool _disposed = false;

  bool _isSwitchingDueToFallback = false;
  bool _isHandlingError = false;

  Timer? _hideTimer;

  LiveRoom? currentFloatRoom;

  // =========================
  // getter
  // =========================

  UnifiedPlayer? get currentPlayer => _currentPlayer;

  PlayerEngine get currentEngine =>
      _runtimeEngine ?? _defaultEngine ?? PlayerEngine.mediaKit;

  Stream<PlayerState> get onStateChanged => _stateSubject.stream;

  Stream<bool> get onPlaying => _playingSubject.stream;

  Stream<bool> get onLoading => _loadingSubject.stream;

  Stream<bool> get onComplete => _completeSubject.stream;

  Stream<PlayerException> get onError => _errorSubject.stream;

  Stream<int?> get width => _widthSubject.stream;

  Stream<int?> get height => _heightSubject.stream;

  bool get isPlayingNow => _playingSubject.value;

  double get currentVideoRatio {
    final w = _widthSubject.value?.toDouble() ?? 1920;

    final h = _heightSubject.value?.toDouble() ?? 1080;

    if (w <= 0 || h <= 0) {
      return 16 / 9;
    }

    return w / h;
  }

  // =========================
  // initialize
  // =========================

  Future<void> initialize({PlayerEngine engine = PlayerEngine.mediaKit}) async {
    if (_disposed) return;

    final session = _session;
    if (!_active(session)) return;
    _stateSubject.add(PlayerState.initializing);

    try {
      _defaultEngine = engine;

      _runtimeEngine = engine;

      final player = await session.wait(playerPool.getPlayer(engine));
      if (!_active(session)) return;
      _currentPlayer = player;
      await _bindPlayerStreams(player);
      if (!_active(session)) return;
      isInitialized.value = true;
      _stateSubject.add(PlayerState.initialized);
    } catch (e, s) {
      if (!_active(session)) return;
      hasError.value = true;

      final exception = PlayerException(
        message: 'Initialize player failed',
        type: PlayerErrorType.initialization,
        error: e,
        stackTrace: s,
      );

      _errorSubject.add(exception);

      _stateSubject.add(PlayerState.error);

      throw exception;
    }
  }

  // =========================
  // play
  // =========================

  Future<void> play(
    String url,
    List<String> playUrls,
    Map<String, String> headers, {
    LiveRoom? room,
  }) async {
    if (_disposed) return;
    if (_closeFuture != null) await _closeFuture;
    if (_disposed) return;
    if (_session.cancelled) _session = _PlaybackSession();
    final session = _session;
    session.preparing++;
    try {
      if (room != currentFloatRoom) lineManager.reset();
      _defaultEngine ??= preferredEngine();
      if (_currentPlayer == null || _runtimeEngine == null) {
        await initialize(engine: _defaultEngine!);
      } else if (_runtimeEngine != _defaultEngine &&
          !_isSwitchingDueToFallback) {
        await switchEngine(_defaultEngine!, isManual: false);
      }
      if (!_active(session)) return;
      final player = _currentPlayer;
      if (player == null) throw StateError('Current player is null');
      _currentUrl = url;
      _currentPlayUrls = playUrls;
      _currentHeaders = headers;
      currentFloatRoom = room;
      hasError.value = false;
      _stateSubject.add(PlayerState.preparing);
      await session.wait(
        player.setDataSource(url, playUrls, headers, room: room),
      );
      if (!_active(session)) return;
      videoKey.value = ValueKey(
        "video_${DateTime.now().millisecondsSinceEpoch}",
      );
      _stateSubject.add(PlayerState.ready);
    } catch (error, stack) {
      if (!_active(session)) return;
      final exception = error is PlayerException
          ? error
          : PlayerException(
              message: 'Play failed',
              type: PlayerErrorType.unknown,
              error: error,
              stackTrace: stack,
            );
      if (!_isHandlingError) await _handleError(exception);
    } finally {
      session.preparing--;
      if (_active(session)) _isSwitchingDueToFallback = false;
    }
  }

  // =========================
  // replay
  // =========================

  Future<void> replay() async {
    if (_currentUrl == null) return;
    await play(
      _currentUrl!,
      _currentPlayUrls,
      _currentHeaders,
      room: currentFloatRoom,
    );
  }

  // =========================
  // switch engine
  // =========================

  Future<void> switchEngine(
    PlayerEngine engine, {
    bool isManual = false,
  }) async {
    final session = _session;
    if (!_active(session)) return;

    if (_runtimeEngine == engine && _currentPlayer != null) {
      return;
    }

    try {
      final oldPlayer = _currentPlayer;

      final oldEngine = _runtimeEngine;

      await _clearSubscriptions();

      if (!_active(session)) return;
      final newPlayer = await session.wait(playerPool.getPlayer(engine));
      if (!_active(session)) return;

      _currentPlayer = newPlayer;

      _runtimeEngine = engine;

      if (isManual) {
        _defaultEngine = engine;
      }

      await _bindPlayerStreams(newPlayer);
      if (!_active(session)) return;
      if (oldPlayer != null && oldEngine != null) {
        await _safeDestroyPlayer(oldPlayer, oldEngine);
      }

      if (!_active(session)) return;
      videoKey.value = ValueKey(
        "video_${DateTime.now().millisecondsSinceEpoch}",
      );
    } catch (e, s) {
      if (!_active(session)) return;
      final exception = PlayerException(
        message: 'Switch engine failed',
        type: PlayerErrorType.lifecycle,
        error: e,
        stackTrace: s,
      );

      _errorSubject.add(exception);

      rethrow;
    }
  }

  Future<void> _safeDestroyPlayer(
    UnifiedPlayer player,
    PlayerEngine engine,
  ) async {
    try {
      await playerPool.removePlayer(engine, player);
    } catch (e, s) {
      log("destroy player error: $e", stackTrace: s);
    }
  }

  // =========================
  // preload
  // =========================

  Future<void> preload(
    String url,
    List<String> playUrls,
    Map<String, String> headers,
  ) async {
    if (_disposed) return;

    final standby = await playerPool.getPlayer(_runtimeEngine!);

    await preloadManager.preload(standby, url, playUrls, headers);
  }

  // =========================
  // seamless switch
  // =========================

  Future<void> seamlessSwitch() async {
    if (_disposed) return;

    await preloadManager.switchToStandby();

    final player = preloadManager.current;

    if (player == null) return;

    await _clearSubscriptions();

    _currentPlayer = player;

    await _bindPlayerStreams(player);
  }

  // =========================
  // play control
  // =========================

  Future<void> togglePlayPause() async {
    if (_currentPlayer == null) return;

    if (isPlayingNow) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> pause() async {
    await _currentPlayer?.pause();
  }

  Future<void> resume() async {
    await _currentPlayer?.play();
  }

  Future<void> stop() async {
    await close();
  }

  // =========================
  // volume
  // =========================

  Future<void> setVolume(double volume) async {
    await _currentPlayer?.setVolume(volume.clamp(0.0, 1.0));
  }

  // =========================
  // fit
  // =========================

  void changeVideoFit(int index) {
    videoFitIndex.value = index;
  }

  Widget getVideoWidget(
    int fitIndex, {
    Widget? controls,
    required List<BoxFit> fitList,
  }) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(0),
      child: StreamBuilder<bool>(
        stream: onPlaying,
        initialData: isPlayingNow,
        builder: (context, snapshot) {
          if (_currentPlayer == null) {
            return _buildPlaceholder();
          }
          final boxFit = fitList[fitIndex];
          return KeyedSubtree(
            key: videoKey.value,
            child: Container(
              color: Colors.black,
              width: double.infinity,
              height: double.infinity,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: Colors.black,
                      child: FittedBox(
                        fit: boxFit,
                        clipBehavior: Clip.hardEdge,
                        child: StreamBuilder<List<int?>>(
                          stream: CombineLatestStream.list([width, height]),
                          builder: (context, snapshot) {
                            // 动态使用视频的真实宽高
                            final vW = snapshot.data?[0]?.toDouble() ?? 1920.0;
                            final vH = snapshot.data?[1]?.toDouble() ?? 1080.0;
                            return SizedBox(
                              width: vW,
                              height: vH,
                              child: _currentPlayer!.getVideoWidget(),
                            );
                          },
                        ),
                      ),
                    ),
                  ),

                  if (controls != null) Positioned.fill(child: controls),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 4, color: Colors.white70),
      ),
    );
  }

  // =========================
  // close
  // =========================

  Future<void> close() => _closeFuture ??= _close().whenComplete(() {
    _closeFuture = null;
  });

  Future<void> _close() async {
    final session = _session;
    final player = _currentPlayer;
    final hard =
        hardStopOnExit() ||
        session.preparing > 0 ||
        _isHandlingError ||
        _isSwitchingDueToFallback ||
        player == null;
    session.cancel();
    _currentPlayer = null;
    _runtimeEngine = null;
    _currentUrl = null;
    _isHandlingError = false;
    _isSwitchingDueToFallback = false;
    lineManager.reset();
    isInitialized.value = false;
    _stateSubject.add(PlayerState.idle);
    _playingSubject.add(false);
    _loadingSubject.add(false);
    final subscriptions = _clearSubscriptions();
    // disposeAll removes cache entries before returning its disposal Future.
    final cleanup = hard ? playerPool.disposeAll() : player.softStop();
    try {
      await Future.wait([
        subscriptions,
        cleanup,
      ]).timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // A timed-out soft stop must also be removed before a later room can reuse it.
      unawaited(
        playerPool.disposeAll().catchError((Object error) {
          log('Background player disposal failed: $error');
        }),
      );
      log(
        'Player disposal continues in background after detaching the old session',
      );
    }
  }

  Future<void> softStop() => close();

  Future<void> hardDispose() async {
    _session.cancel();
    _currentPlayer = null;
    _runtimeEngine = null;
    isInitialized.value = false;
    await Future.wait([_clearSubscriptions(), playerPool.disposeAll()]);
  }

  // =========================
  // retry
  // =========================

  Future<void> retry() async {
    await replay();
  }

  // =========================
  // error
  // =========================
  Future<void> _handleError(PlayerException error) async {
    final session = _session;
    if (!_active(session)) return;
    if (_isHandlingError) {
      log("skip duplicated error handling: ${error.message}");
      return;
    }
    _isHandlingError = true;

    try {
      hasError.value = true;
      _errorSubject.add(error);
      _stateSubject.add(PlayerState.error);

      bool lineSwitched = false;

      if ((error.type == PlayerErrorType.network ||
              error.type == PlayerErrorType.source) &&
          _currentPlayUrls.length > 1) {
        lineManager.markFailed(_currentUrl!);

        if (!lineManager.hasAvailable(_currentPlayUrls)) {
          log("no available lines, fallback engine");
        } else {
          final nextLine = lineManager.next(_currentPlayUrls);

          if (nextLine != _currentUrl) {
            lineSwitched = true;

            log("switch line => $nextLine");

            await session.wait(Future.delayed(const Duration(seconds: 2)));
            if (!_active(session)) return;

            await play(
              nextLine,
              _currentPlayUrls,
              _currentHeaders,
              room: currentFloatRoom,
            );

            return;
          }
        }
      }
      log(error.type.toString());
      // =========================
      // 2. 再尝试切播放器
      // =========================

      if (!lineSwitched && fallbackManager.shouldFallback(error)) {
        final nextEngine = await fallbackManager.fallback(
          _runtimeEngine!,
          error,
        );
        if (!_active(session)) return;

        // 防止重复切换
        if (nextEngine == _runtimeEngine) {
          log(
            "skip fallback: nextEngine(${nextEngine.name}) == currentEngine(${_runtimeEngine?.name})",
          );
          return;
        }

        log(
          "fallback engine: "
          "${_runtimeEngine?.name} -> ${nextEngine.name}",
        );
        _isSwitchingDueToFallback = true;

        // 给底层播放器一点释放时间
        await session.wait(Future.delayed(const Duration(milliseconds: 1200)));
        if (!_active(session)) return;

        await switchEngine(nextEngine, isManual: false);
        if (!_active(session)) return;

        await session.wait(Future.delayed(const Duration(milliseconds: 500)));
        if (!_active(session)) return;

        await replay();

        return;
      }
    } catch (e, s) {
      if (_active(session)) log("_handleError failed: $e", stackTrace: s);
    } finally {
      if (_active(session)) _isHandlingError = false;
    }
  }
  // =========================
  // bind
  // =========================

  Future<void> _bindPlayerStreams(UnifiedPlayer player) async {
    final session = _session;
    await _clearSubscriptions();
    bool active() => _active(session) && identical(player, _currentPlayer);
    if (!active()) return;
    _subscriptions.add(
      player.onPlaying.listen((event) async {
        if (!active()) return;
        _playingSubject.add(event);
        if (event) {
          hasError.value = false;
          _stateSubject.add(PlayerState.playing);
          if (_isSwitchingDueToFallback) {
            _isSwitchingDueToFallback = false;
          }
        } else {
          _stateSubject.add(PlayerState.paused);
        }
      }),
    );

    _subscriptions.add(
      player.onLoading.listen((event) {
        if (!active()) return;
        _loadingSubject.add(event);
        if (event && _stateSubject.value != PlayerState.buffering) {
          _stateSubject.add(PlayerState.buffering);
        }
      }),
    );

    _subscriptions.add(
      player.onComplete.listen((event) {
        if (!active()) return;
        _completeSubject.add(event);
      }),
    );

    _subscriptions.add(
      player.onStateChanged.listen((event) {
        if (!active()) return;
        _stateSubject.add(event);
      }),
    );

    _subscriptions.add(
      player.onError.listen((error) {
        if (!active()) return;
        if (!_isHandlingError) {
          _handleError(error);
        }
      }),
    );

    _subscriptions.add(
      player.width.listen((event) {
        if (!active()) return;
        _widthSubject.add(event);
      }),
    );

    _subscriptions.add(
      player.height.listen((event) {
        if (!active()) return;
        _heightSubject.add(event);
      }),
    );

    _subscriptions.add(
      CombineLatestStream.combine2<int?, int?, bool>(
        width.where((w) => w != null && w > 0),
        height.where((h) => h != null && h > 0),
        (w, h) => h! >= w!,
      ).distinct().listen((event) {
        if (!active()) return;
        isVerticalVideo.value = event;
      }),
    );
  }

  // =========================
  // clear subscriptions
  // =========================

  Future<void> _clearSubscriptions() async {
    if (_subscriptions.isEmpty) return;
    final subscriptions = _subscriptions.toList();
    _subscriptions.clear();
    await Future.wait(subscriptions.map((item) => item.cancel()));
  }

  // =========================
  // dispose
  // =========================

  Future<void> dispose() async {
    if (_disposed) return;

    _disposed = true;
    _session.cancel();

    _hideTimer?.cancel();

    await _clearSubscriptions();

    await playerPool.disposeAll();

    await Future.wait([
      _stateSubject.close(),
      _playingSubject.close(),
      _loadingSubject.close(),
      _completeSubject.close(),
      _errorSubject.close(),
      _widthSubject.close(),
      _heightSubject.close(),
    ]);
  }
}

class _PlaybackSession {
  final Completer<void> _cancelled = Completer<void>();
  int preparing = 0;
  bool get cancelled => _cancelled.isCompleted;
  void cancel() {
    if (!cancelled) _cancelled.complete();
  }

  Future<T> wait<T>(Future<T> operation) => Future.any([
    operation,
    _cancelled.future.then<T>((_) => throw StateError('Playback cancelled')),
  ]);
}
