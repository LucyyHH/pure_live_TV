import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Fixed rows avoid retaining masonry column offsets when rooms are reordered.
class RoomGridDelegate extends SliverGridDelegate {
  RoomGridDelegate({
    required this.crossAxisSpacing,
    required this.mainAxisSpacing,
  }) : footerHeight = 76.w + 40.h;

  final double footerHeight;

  final double crossAxisSpacing;
  final double mainAxisSpacing;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    const columns = 5;
    final width =
        (constraints.crossAxisExtent - crossAxisSpacing * (columns - 1)) /
        columns;
    // RoomCard: cover + vertical gaps + title + avatar row.
    final height = width * 9 / 16 + footerHeight;
    return SliverGridRegularTileLayout(
      crossAxisCount: columns,
      mainAxisStride: height + mainAxisSpacing,
      crossAxisStride: width + crossAxisSpacing,
      childMainAxisExtent: height,
      childCrossAxisExtent: width,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(covariant RoomGridDelegate oldDelegate) =>
      oldDelegate.crossAxisSpacing != crossAxisSpacing ||
      oldDelegate.mainAxisSpacing != mainAxisSpacing ||
      oldDelegate.footerHeight != footerHeight;
}
