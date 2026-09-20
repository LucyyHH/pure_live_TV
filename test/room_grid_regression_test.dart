import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/widgets/room_grid_delegate.dart';

void main() {
  testWidgets('room reorder after route return leaves no empty grid cells', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final rooms = List.generate(15, (i) => i);
    late StateSetter update;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(1920, 1080),
        builder: (_, _) => MaterialApp(
          navigatorKey: navigator,
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Scaffold(
                body: GridView.builder(
                  gridDelegate: RoomGridDelegate(
                    crossAxisSpacing: 24,
                    mainAxisSpacing: 20,
                  ),
                  itemCount: rooms.length,
                  itemBuilder: (_, i) => SizedBox(
                    key: ValueKey(rooms[i]),
                    child: Hero(
                      tag: rooms[i],
                      child: const ColoredBox(color: Colors.blue),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var round = 0; round < 3; round++) {
      final watched = rooms[1];
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: Hero(
              tag: watched,
              child: const ColoredBox(color: Colors.blue),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      update(() {
        rooms.remove(watched);
        rooms.insert(0, watched);
      });
      await tester.pump();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        final position = tester.getTopLeft(find.byKey(ValueKey(rooms[i])));
        expect(position.dy, 0);
        expect(position.dx, closeTo(i * 824 / 5, 0.01));
      }
      expect(tester.takeException(), isNull);
    }
  });
}
