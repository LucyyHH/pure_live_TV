import 'package:pure_live/app/room_focus_nodes.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/plugins/utils.dart';
import 'package:pure_live/app/app_focus_node.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/base/base_controller.dart';

class HistoryPageController extends BasePageController<LiveRoom> {
  final backFocusNode = AppFocusNode();
  final clearFocusNode = AppFocusNode();
  var currentNodeIndex = 1.obs;
  // button列表再加上设置最近观看
  final roomFocusNodes = RoomFocusNodes();

  @override
  void onInit() {
    super.onInit();
    stopLoadMore.value = false;
    refreshData();
  }

  @override
  void onClose() {
    roomFocusNodes.dispose();
    backFocusNode.dispose();
    clearFocusNode.dispose();
    super.onClose();
  }

  void clean() async {
    settingsService.historyRooms.value = [];
    roomFocusNodes.retainRooms(const []);
    list.value = [];
  }

  void removeItem(LiveRoom item) async {
    var result = await Utils.showAlertDialog("确定要删除此记录吗?", title: "删除记录");
    if (!result) {
      return;
    }
    settingsService.removeHistoryRoom(item);
    refreshData();
  }

  @override
  Future<List<LiveRoom>> getData(int page, int pageSize) async {
    final rooms = settingsService.historyRooms.toList();
    roomFocusNodes.retainRooms(rooms);
    return rooms;
  }
}
