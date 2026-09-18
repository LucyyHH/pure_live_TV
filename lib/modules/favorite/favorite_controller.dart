import 'dart:async';
import 'package:pool/pool.dart';
import 'package:pure_live/app/utils.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/app/app_focus_node.dart';

class FavoriteController extends GetxController {
  final SettingsService settings = Get.find<SettingsService>();

  final tabBottomIndex = 0.obs;

  final onlineRoomsNodes = AppFocusNode();

  final offlineRoomsNodes = AppFocusNode();

  bool isFirstLoad = true;
  StreamSubscription<List<LiveRoom>>? _favoriteRoomsSubscription;
  int _refreshGeneration = 0;
  bool _isClosed = false;

  var loading = true.obs;

  @override
  void onInit() {
    super.onInit();
    onlineRoomsNodes.requestFocus();
    syncRooms();

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
    loading.value = true;
    onlineRooms.clear();
    offlineRooms.clear();
    onlineRooms.addAll(
      settings.favoriteRooms.where(
        (room) => room.liveStatus == LiveStatus.live,
      ),
    );
    offlineRooms.addAll(
      settings.favoriteRooms.where(
        (room) => room.liveStatus != LiveStatus.live,
      ),
    );
    for (var room in onlineRooms) {
      if (int.tryParse(room.watching!) == null) {
        room.watching = "0";
      }
    }
    onlineRooms.sort(
      (a, b) => int.parse(b.watching!).compareTo(int.parse(a.watching!)),
    );
    loading.value = false;
  }

  @override
  void onClose() {
    _isClosed = true;
    _refreshGeneration++;
    _favoriteRoomsSubscription?.cancel();
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
    syncRooms();
  }

  Future<bool> onRefresh() async {
    final refreshGeneration = ++_refreshGeneration;
    final Pool refreshPool = Pool(settings.maxConcurrentRefresh.value);
    if (_isClosed) return false;
    loading.value = true;
    try {
      final rooms = settings.favoriteRooms.value.where((room) {
        return room.roomId != null &&
            room.roomId!.isNotEmpty &&
            room.platform != null &&
            room.platform!.isNotEmpty;
      }).toList();

      if (rooms.isEmpty) {
        debugPrint('没有有效的收藏房间需要刷新');
        if (!_isClosed && refreshGeneration == _refreshGeneration) {
          loading.value = false;
        }
        return false;
      }

      final List<Future<void>> tasks = rooms.map((room) {
        return refreshPool.withResource(() async {
          try {
            if (room.platform == null || room.roomId == null) {
              debugPrint('跳过无效房间数据');
              return;
            }

            final liveRoom = await Sites.of(room.platform!).liveSite
                .getRoomDetail(roomId: room.roomId!, platform: room.platform!);

            if (_isClosed || refreshGeneration != _refreshGeneration) return;
            settings.updateRoom(liveRoom);
          } catch (e, stack) {
            debugPrint('================ 刷新失败记录 ================');
            debugPrint('平台 (Platform): ${room.platform}');
            debugPrint('房间号 (RoomID): ${room.roomId}');
            debugPrint('昵称 (Nickname): ${room.nick}');
            debugPrint('原始标题 (Title): ${room.title}');
            debugPrint('具体错误类型: $e');
            debugPrint('堆栈追踪: $stack');
            debugPrint('============================================');
          }
        });
      }).toList();

      //  并发启动所有任务并等待它们全部执行完毕
      await Future.wait(tasks);
    } catch (e) {
      debugPrint('刷新过程中发生全局错误: $e');
    } finally {
      if (!_isClosed && refreshGeneration == _refreshGeneration) {
        syncRooms();
        isFirstLoad = false;
        loading.value = false;
      }
    }
    return !_isClosed && refreshGeneration == _refreshGeneration;
  }
}
