import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/modules/favorite/favorite_controller.dart';
import 'support/settings_fixture.dart';

class ControlledFavorites extends FavoriteController {
  final calls = <LiveRoom>[];
  final pending = <Completer<LiveRoom>>[];
  @override
  Future<LiveRoom> fetchRoomDetail(LiveRoom room) {
    calls.add(room);
    final result = Completer<LiveRoom>();
    pending.add(result);
    return result.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'overlapping refresh shares one queue; closed page skips queued requests',
    () async {
      final settings = await createSettingsFixture();
      settings.maxConcurrentRefresh.value = 1;
      settings.favoriteRooms.value = List.generate(
        3,
        (i) => LiveRoom(
          platform: 'huya',
          roomId: '$i',
          liveStatus: LiveStatus.live,
        ),
      );
      final controller = ControlledFavorites();
      final first = controller.onRefresh();
      expect(identical(first, controller.onRefresh()), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(controller.calls.length, 1);
      controller.onClose();
      controller.pending.single.complete(
        controller.calls.single.copyWith(title: 'new'),
      );
      expect(await first, isFalse);
      expect(controller.calls.length, 1);
      expect(settings.favoriteRooms.first.title, isEmpty);
    },
  );

  test(
    'successful refresh publishes one batch after all requests settle',
    () async {
      final settings = await createSettingsFixture();
      settings.maxConcurrentRefresh.value = 2;
      settings.favoriteRooms.value = List.generate(
        2,
        (i) => LiveRoom(
          platform: 'huya',
          roomId: '$i',
          liveStatus: LiveStatus.live,
        ),
      );
      final controller = ControlledFavorites();
      controller.onInit();
      var notifications = 0;
      final subscription = settings.favoriteRooms.listen(
        (_) => notifications++,
      );
      final refresh = controller.onRefresh();
      await Future<void>.delayed(Duration.zero);
      controller.pending[0].complete(
        controller.calls[0].copyWith(title: 'one'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.loading.value, isTrue);
      expect(notifications, 0);
      controller.pending[1].complete(
        controller.calls[1].copyWith(title: 'two'),
      );
      expect(await refresh, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 1);
      expect(controller.loading.value, isFalse);
      expect(controller.onlineRooms.map((room) => room.title), ['one', 'two']);
      controller.onClose();
      await subscription.cancel();
    },
  );

  test(
    'batch merge notifies once and preserves removals and newer room details',
    () async {
      final settings = await createSettingsFixture();
      final rooms = List.generate(
        4,
        (i) => LiveRoom(platform: 'huya', roomId: '$i'),
      );
      settings.favoriteRooms.value = List.of(rooms);
      settings.historyRooms.value = List.of(rooms);
      settings.favoriteRooms.remove(rooms[0]);
      final newest = rooms[1].copyWith(title: 'newest');
      settings.favoriteRooms[0] = newest;
      var notifications = 0;
      final subscription = settings.favoriteRooms.listen(
        (_) => notifications++,
      );
      settings.mergeRoomDetails(
        rooms.map((room) => room.copyWith(title: 'batch')),
        expectedFavorites: rooms,
        expectedHistory: rooms,
      );
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 1);
      expect(settings.favoriteRooms.length, 3);
      expect(identical(settings.favoriteRooms.first, newest), isTrue);
      expect(settings.favoriteRooms.last.title, 'batch');
      expect(settings.historyRooms.first.title, 'batch');
      await subscription.cancel();
    },
  );
}
