import 'package:pure_live/app/room_focus_nodes.dart';
import 'dart:async';
import 'package:pool/pool.dart';
import 'package:pure_live/app/utils.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/app/app_focus_node.dart';

class FavoriteController extends GetxController {
  final SettingsService settings = Get.find<SettingsService>();

  final roomFocusNodes = RoomFocusNodes();
  final backFocusNode = AppFocusNode();
  final refreshFocusNode = AppFocusNode();

  final tabBottomIndex = 0.obs;

  final onlineRoomsNodes = AppFocusNode();

  final offlineRoomsNodes = AppFocusNode();

  bool isFirstLoad = true;
  StreamSubscription<List<LiveRoom>>? _favoriteRoomsSubscription;
  Future<bool>? _refreshFuture;
  bool _isClosed = false;

  var loading = true.obs;

  @override
  void onInit() {
    super.onInit();
    onlineRoomsNodes.requestFocus();
    syncRooms();
    loading.value = false;

    _favoriteRoomsSubscription = settings.favoriteRooms.listen(
      (_) => syncRooms(),
    );

    if (settings.autoRefreshFavorite.value) {
      int interval = settings.autoRefreshInterval.value;
      if (interval <= 0) return;

      DateTime now = DateTime.now();
      DateTime last = settings.lastRefreshTime.value > 0
          ? DateTime.fromMillisecondsSinceEpoch(settings.lastRefreshTime.value)
          : now.subtract(const Duration(days: 1));

      if (now.difference(last).inMinutes >= interval) {
        onRefresh();
        int nowMillis = now.millisecondsSinceEpoch;
        settings.lastRefreshTime.value = nowMillis;
      }
    }
  }

  final onlineRooms = <LiveRoom>[].obs;
  final offlineRooms = <LiveRoom>[].obs;

  void syncRooms() {
    if (_isClosed) return;
    roomFocusNodes.retainRooms(settings.favoriteRooms);
    final online = <LiveRoom>[];
    final offline = <LiveRoom>[];
    for (final room in settings.favoriteRooms) {
      (room.liveStatus == LiveStatus.live ? online : offline).add(room);
    }
    online.sort(
      (a, b) => (int.tryParse(b.watching ?? '') ?? 0).compareTo(
        int.tryParse(a.watching ?? '') ?? 0,
      ),
    );
    onlineRooms.value = online;
    offlineRooms.value = offline;
  }

  @override
  void onClose() {
    _isClosed = true;
    _favoriteRoomsSubscription?.cancel();
    roomFocusNodes.dispose();
    backFocusNode.dispose();
    refreshFocusNode.dispose();
    onlineRoomsNodes.dispose();
    offlineRoomsNodes.dispose();
    super.onClose();
  }

  Future<void> handleFollowLongTap(LiveRoom room) async {
    if (settings.isFavorite(room)) {
      var result = await Utils.showAlertDialog("确定要取消关注此房间吗?", title: "取消关注");
      if (!result) {
        return;
      }
      settings.removeRoom(room);
    } else {
      var result = await Utils.showAlertDialog("确定要关注此房间吗?", title: "关注");
      if (!result) {
        return;
      }
      settings.addRoom(room);
    }
  }

  Future<bool> onRefresh() {
    if (_isClosed) return Future.value(false);
    return _refreshFuture ??= _refreshRooms().whenComplete(() {
      _refreshFuture = null;
    });
  }

  Future<LiveRoom> fetchRoomDetail(LiveRoom room) => Sites.of(
    room.platform!,
  ).liveSite.getRoomDetail(roomId: room.roomId!, platform: room.platform!);

  Future<bool> _refreshRooms() async {
    final concurrency = settings.maxConcurrentRefresh.value;
    final pool = Pool(concurrency > 0 ? concurrency : 1);
    final favorites = settings.favoriteRooms.toList();
    final history = settings.historyRooms.toList();
    loading.value = true;
    try {
      final results = await Future.wait(
        favorites.map((room) {
          return pool.withResource<LiveRoom?>(() async {
            // Queued work must not start after the page has closed.
            if (_isClosed ||
                room.roomId == null ||
                room.roomId!.isEmpty ||
                room.platform == null ||
                room.platform!.isEmpty) {
              return null;
            }
            try {
              return await fetchRoomDetail(room);
            } catch (error) {
              debugPrint('刷新 ${room.platform}/${room.roomId} 失败: $error');
              return null;
            }
          });
        }),
      );
      if (_isClosed) return false;
      settings.mergeRoomDetails(
        results.whereType<LiveRoom>(),
        expectedFavorites: favorites,
        expectedHistory: history,
      );
      isFirstLoad = false;
      return results.any((room) => room != null);
    } finally {
      await pool.close();
      if (!_isClosed) loading.value = false;
    }
  }
}
