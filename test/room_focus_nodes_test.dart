import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/app/room_focus_nodes.dart';
import 'package:pure_live/common/models/live_room.dart';

void main() {
  testWidgets(
    'refresh and reorder reuse focus; removal disposes after detach',
    (tester) async {
      final nodes = RoomFocusNodes();
      final first = LiveRoom(platform: 'a', roomId: '1');
      final second = LiveRoom(platform: 'b', roomId: '1');
      nodes.retainRooms([first, second]);
      final firstNode = nodes.forRoom(first);
      final secondNode = nodes.forRoom(second);
      expect(identical(firstNode, secondNode), isFalse);
      nodes.retainRooms([second, first.copyWith(title: 'updated')]);
      await tester.pumpWidget(const SizedBox());
      expect(identical(nodes.forRoom(first.copyWith()), firstNode), isTrue);
      nodes.retainRooms([second]);
      await tester.pump();
      expect(() => firstNode.addListener(() {}), throwsFlutterError);
      nodes.dispose();
      first.focusNode.dispose();
      second.focusNode.dispose();
    },
  );
}
