import 'package:flutter/widgets.dart';
import 'package:pure_live/app/app_focus_node.dart';
import 'package:pure_live/common/models/live_room.dart';

/// Page-owned focus nodes survive detail refreshes and room reordering.
class RoomFocusNodes {
  final Map<(String?, String?), AppFocusNode> _nodes = {};
  Set<(String?, String?)> _rooms = {};
  bool _disposed = false;

  AppFocusNode forRoom(LiveRoom room) =>
      _nodes.putIfAbsent((room.platform, room.roomId), AppFocusNode.new);

  void retainRooms(Iterable<LiveRoom> rooms) {
    _rooms = {for (final room in rooms) (room.platform, room.roomId)};
    // Old widgets must detach before their nodes are disposed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      _nodes.removeWhere((key, node) {
        if (_rooms.contains(key)) return false;
        node.dispose();
        return true;
      });
    });
  }

  void dispose() {
    _disposed = true;
    for (final node in _nodes.values) {
      node.dispose();
    }
    _nodes.clear();
  }
}
