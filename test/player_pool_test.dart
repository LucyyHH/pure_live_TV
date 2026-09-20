import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/player/core/player_pool.dart';
import 'package:pure_live/player/interface/unified_player_interface.dart';
import 'package:pure_live/player/models/player_engine.dart';
import 'package:pure_live/player/models/player_exception.dart';
import 'package:pure_live/player/models/player_state.dart';

class FakePlayer implements UnifiedPlayer {
  final initGate = Completer<void>();
  int disposeCalls = 0;

  @override
  Future<void> init() => initGate.future;

  @override
  Future<void> hardDispose() async {
    disposeCalls++;
  }

  @override
  bool get isInitialized => initGate.isCompleted;

  @override
  bool get isPlayingNow => false;

  @override
  bool get isReusable => true;

  @override
  Stream<bool> get onComplete => const Stream.empty();

  @override
  Stream<PlayerException> get onError => const Stream.empty();

  @override
  Stream<bool> get onLoading => const Stream.empty();

  @override
  Stream<bool> get onPlaying => const Stream.empty();

  @override
  Stream<PlayerState> get onStateChanged => const Stream.empty();

  @override
  Stream<int?> get width => const Stream.empty();

  @override
  Stream<int?> get height => const Stream.empty();

  @override
  Widget getVideoWidget() => const SizedBox();

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> setDataSource(
    String url,
    List<String> playUrls,
    Map<String, String> headers, {
    LiveRoom? room,
  }) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> softStop() async {}

  @override
  Future<void> stop() async {}
}

void main() {
  test('cancelled pending creation is disposed and never cached', () async {
    final first = FakePlayer();
    final second = FakePlayer();
    var factoryCalls = 0;
    final pool = PlayerPool(
      factory: (_) async => factoryCalls++ == 0 ? first : second,
    );

    final stale = pool.getPlayer(PlayerEngine.mediaKit);
    await Future<void>.delayed(Duration.zero);
    await pool.removeFromCache(PlayerEngine.mediaKit);

    final fresh = pool.getPlayer(PlayerEngine.mediaKit);
    await Future<void>.delayed(Duration.zero);
    first.initGate.complete();
    second.initGate.complete();

    await expectLater(stale, throwsStateError);
    expect(await fresh, same(second));
    expect(first.disposeCalls, 1);
    expect(await pool.getPlayer(PlayerEngine.mediaKit), same(second));
  });

  test(
    'late disposal cannot evict a newer player of the same engine',
    () async {
      final first = FakePlayer()..initGate.complete();
      final second = FakePlayer()..initGate.complete();
      var factoryCalls = 0;
      final pool = PlayerPool(
        factory: (_) async => factoryCalls++ == 0 ? first : second,
      );

      expect(await pool.getPlayer(PlayerEngine.mediaKit), same(first));
      await pool.removePlayer(PlayerEngine.mediaKit, first);
      expect(await pool.getPlayer(PlayerEngine.mediaKit), same(second));
      await pool.removePlayer(PlayerEngine.mediaKit, first);
      expect(await pool.getPlayer(PlayerEngine.mediaKit), same(second));
    },
  );
}
