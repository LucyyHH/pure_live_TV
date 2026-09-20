import 'package:pure_live/common/widgets/room_grid_delegate.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/widgets/button/highlight_button.dart';
import 'package:pure_live/modules/history/history_rooms_controller.dart';

class HistoryPage extends GetView<HistoryPageController> {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      child: Column(
        children: [
          AppStyle.vGap32,
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppStyle.hGap48,
              HighlightButton(
                focusNode: controller.backFocusNode,
                iconData: Icons.arrow_back,
                text: "返回",
                autofocus: true,
                onTap: () {
                  Navigator.of(Get.context!).pop();
                },
              ),
              AppStyle.hGap32,
              Text(
                "观看记录",
                style: AppStyle.titleStyleWhite.copyWith(
                  fontSize: 36.w,
                  fontWeight: FontWeight.bold,
                ),
              ),
              AppStyle.hGap24,
              const Spacer(),
              HighlightButton(
                focusNode: controller.clearFocusNode,
                iconData: Icons.delete_outline_rounded,
                text: "清空",
                onTap: () {
                  controller.clean();
                },
              ),
              AppStyle.hGap48,
            ],
          ),
          AppStyle.vGap24,
          Expanded(
            child: Obx(
              () => GridView.builder(
                padding: AppStyle.edgeInsetsA48,
                itemCount: controller.list.length,
                gridDelegate: RoomGridDelegate(
                  crossAxisSpacing: 24.w,
                  mainAxisSpacing: 20.w,
                ),
                controller: controller.scrollController,
                itemBuilder: (_, i) {
                  var item = controller.list[i];
                  return RoomCard(
                    key: ValueKey((item.platform, item.roomId)),
                    room: item,
                    dense: true,
                    useDefaultLongTapEvent: false,
                    focusNode: controller.roomFocusNodes.forRoom(item),
                    roomTypePage: EnterRoomTypePage.historyPage,
                    onLongTap: () {
                      controller.removeItem(item);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
