import '../models/player_engine.dart';
import '../interface/unified_player_interface.dart';

class PlayerPool {
  final Map<PlayerEngine, UnifiedPlayer> _cache = {};
  final Map<PlayerEngine, Future<UnifiedPlayer>> _pending = {};
  final Map<PlayerEngine, int> _versions = {};
  final Future<UnifiedPlayer> Function(PlayerEngine) factory;

  PlayerPool({required this.factory});

  Future<UnifiedPlayer> getPlayer(PlayerEngine engine) {
    final cached = _cache[engine];
    if (cached != null) return Future.value(cached);
    return _pending[engine] ??= _startCreation(engine);
  }

  Future<UnifiedPlayer> _startCreation(PlayerEngine engine) {
    final version = _versions[engine] ?? 0;
    late final Future<UnifiedPlayer> future;
    future = _create(engine, version).whenComplete(() {
      if (identical(_pending[engine], future)) _pending.remove(engine);
    });
    return future;
  }

  Future<UnifiedPlayer> _create(PlayerEngine engine, int version) async {
    final player = await factory(engine);
    try {
      if ((_versions[engine] ?? 0) != version) {
        throw StateError('Player creation cancelled');
      }
      await player.init();
      if ((_versions[engine] ?? 0) != version) {
        throw StateError('Player creation cancelled');
      }
      _cache[engine] = player;
      return player;
    } catch (_) {
      await player.hardDispose();
      rethrow;
    }
  }

  Future<void> removeFromCache(PlayerEngine engine) {
    _versions[engine] = (_versions[engine] ?? 0) + 1;
    _pending.remove(engine);
    // Detach before awaiting disposal: a late cleanup must not remove a new player.
    final player = _cache.remove(engine);
    return player?.hardDispose() ?? Future.value();
  }

  Future<void> removePlayer(PlayerEngine engine, UnifiedPlayer player) {
    if (identical(_cache[engine], player)) _cache.remove(engine);
    return player.hardDispose();
  }

  Future<void> disposeAll() {
    final players = _cache.values.toList();
    _cache.clear();
    _pending.clear();
    for (final engine in PlayerEngine.values) {
      _versions[engine] = (_versions[engine] ?? 0) + 1;
    }
    return Future.wait(players.map((player) => player.hardDispose()));
  }
}
