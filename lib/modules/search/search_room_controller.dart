import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/app/app_focus_node.dart';
import 'package:pure_live/common/base/base_controller.dart';

class SearchRoomController extends BasePageController<LiveRoom> {
  final String keyword;
  late Site site;
  var siteId = ''.obs;
  var currentNodeIndex = 1.obs;
  // button列表再加上设置最近观看
  List<AppFocusNode> focusNodes = [];
  StreamSubscription<List<LiveRoom>>? _roomsSubscription;
  SearchRoomController({required this.keyword});

  @override
  void onInit() {
    if (Sites().availableSites().isNotEmpty) {
      siteId.value = Sites().availableSites()[0].id;
      site = Sites().availableSites()[0];
    }

    focusNodes = [];
    // 分类按钮
    for (var i = 0; i < Sites().availableSites().length; i++) {
      focusNodes.add(AppFocusNode());
    }
    // 返回按钮
    focusNodes.add(AppFocusNode());

    super.onInit();

    _roomsSubscription = list.listen((rooms) {
      if (currentPage != 2 || rooms.isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isClosed && list.isNotEmpty) {
          list.first.focusNode.requestFocus();
        }
      });
    });
    refreshData();
  }

  void setSite(String id) {
    siteId.value = id;
    final pIndex = Sites().availableSites().indexWhere((e) => e.id == id);
    site = Sites().availableSites()[pIndex];
    refreshData();
  }

  @override
  void onClose() {
    _roomsSubscription?.cancel();
    for (final node in focusNodes) {
      node.dispose();
    }
    super.onClose();
  }

  @override
  Future<List<LiveRoom>> getData(int page, int pageSize) async {
    if (keyword.isEmpty || siteId.value.isEmpty) {
      return [];
    }
    var result = await site.liveSite.searchRooms(keyword, page: page);
    return result.items;
  }
}
