import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/app/app_focus_node.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/base/base_controller.dart';

class AreaRoomsController extends BasePageController<LiveRoom> {
  final Site site;
  final LiveArea subCategory;
  var currentNodeIndex = 1.obs;
  // button列表再加上设置最近观看
  List<AppFocusNode> focusNodes = [];
  StreamSubscription<List<LiveRoom>>? _roomsSubscription;
  AreaRoomsController({required this.site, required this.subCategory});

  @override
  void onInit() {
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
    var result = await site.liveSite.getCategoryRooms(subCategory, page: page);
    for (var element in result.items) {
      element.area = subCategory.areaName;
    }
    return result.items;
  }
}
