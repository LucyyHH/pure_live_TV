import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/modules/live_play/live_play_controller.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';
import 'package:pure_live/player/core/player_manager.dart';
import 'package:pure_live/player/global_player_service.dart';
import 'support/settings_fixture.dart';

class PendingVideo implements VideoController {
  final destroyed = Completer<void>();
  int destroyCalls = 0;
  @override
  Future<void> destroy() {
    destroyCalls++;
    return destroyed.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CountingPlayer implements PlayerManager {
  int closeCalls = 0;
  @override
  Future<void> close() async {
    closeCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'cleanup is shared and a new route waits for the old native session',
    () async {
      await createSettingsFixture();
      final player = CountingPlayer();
      GlobalPlayerService.instance.playerManager = player;
      final room = LiveRoom(platform: 'huya', roomId: '1');
      final oldPage = LivePlayController(room: room, site: 'huya');
      final oldVideo = PendingVideo();
      oldPage.videoController = oldVideo;
      final cleanup = oldPage.disPoserPlayer();
      expect(identical(cleanup, oldPage.disPoserPlayer()), isTrue);
      expect(oldPage.videoController, isNull);

      final nextPage = LivePlayController(room: room, site: 'huya');
      nextPage.currentPlayRoom.value = room;
      var initialized = false;
      final next = nextPage.onInitPlayerState().then((_) {
        initialized = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(initialized, isFalse);
      expect(oldVideo.destroyCalls, 1);
      expect(
        player.closeCalls,
        1,
        reason: 'native startup cancellation must begin without waiting',
      );
      // Closing the waiting page invalidates the request before any site API call.
      nextPage.onClose();
      oldVideo.destroyed.complete();
      await cleanup;
      await next;
      expect(player.closeCalls, 1);
      expect(nextPage.videoController, isNull);
      oldPage.onClose();
    },
  );
}
