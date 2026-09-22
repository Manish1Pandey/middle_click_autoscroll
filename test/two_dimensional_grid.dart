import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A minimal fixed-cell [TwoDimensionalScrollView] used to verify
/// autoscroll on a real two-dimensional scrollable.
class FixedGrid extends TwoDimensionalScrollView {
  const FixedGrid({
    super.key,
    super.verticalDetails,
    super.horizontalDetails,
    required TwoDimensionalChildBuilderDelegate super.delegate,
    this.cellSize = 100,
  });

  final double cellSize;

  @override
  Widget buildViewport(
    BuildContext context,
    ViewportOffset verticalOffset,
    ViewportOffset horizontalOffset,
  ) {
    return _GridViewport(
      verticalOffset: verticalOffset,
      verticalAxisDirection: verticalDetails.direction,
      horizontalOffset: horizontalOffset,
      horizontalAxisDirection: horizontalDetails.direction,
      delegate: delegate as TwoDimensionalChildBuilderDelegate,
      mainAxis: mainAxis,
      cellSize: cellSize,
    );
  }
}

class _GridViewport extends TwoDimensionalViewport {
  const _GridViewport({
    required super.verticalOffset,
    required super.verticalAxisDirection,
    required super.horizontalOffset,
    required super.horizontalAxisDirection,
    required TwoDimensionalChildBuilderDelegate super.delegate,
    required super.mainAxis,
    required this.cellSize,
  });

  final double cellSize;

  @override
  RenderTwoDimensionalViewport createRenderObject(BuildContext context) {
    return _RenderGrid(
      verticalOffset: verticalOffset,
      verticalAxisDirection: verticalAxisDirection,
      horizontalOffset: horizontalOffset,
      horizontalAxisDirection: horizontalAxisDirection,
      delegate: delegate as TwoDimensionalChildBuilderDelegate,
      mainAxis: mainAxis,
      childManager: context as TwoDimensionalChildManager,
      cellSize: cellSize,
    );
  }

  @override
  void updateRenderObject(BuildContext context, _RenderGrid renderObject) {
    renderObject
      ..verticalOffset = verticalOffset
      ..verticalAxisDirection = verticalAxisDirection
      ..horizontalOffset = horizontalOffset
      ..horizontalAxisDirection = horizontalAxisDirection
      ..delegate = delegate
      ..mainAxis = mainAxis
      ..cellSize = cellSize;
  }
}

class _RenderGrid extends RenderTwoDimensionalViewport {
  _RenderGrid({
    required super.verticalOffset,
    required super.verticalAxisDirection,
    required super.horizontalOffset,
    required super.horizontalAxisDirection,
    required TwoDimensionalChildBuilderDelegate super.delegate,
    required super.mainAxis,
    required super.childManager,
    required double cellSize,
  }) : _cellSize = cellSize;

  double _cellSize;
  set cellSize(double value) {
    if (value != _cellSize) {
      _cellSize = value;
      markNeedsLayout();
    }
  }

  @override
  void layoutChildSequence() {
    final TwoDimensionalChildBuilderDelegate builder =
        delegate as TwoDimensionalChildBuilderDelegate;
    final int maxCol = builder.maxXIndex!;
    final int maxRow = builder.maxYIndex!;
    final double h = horizontalOffset.pixels;
    final double v = verticalOffset.pixels;
    final int firstCol = math.max(0, (h / _cellSize).floor());
    final int lastCol = math.min(
      maxCol,
      ((h + viewportDimension.width) / _cellSize).ceil(),
    );
    final int firstRow = math.max(0, (v / _cellSize).floor());
    final int lastRow = math.min(
      maxRow,
      ((v + viewportDimension.height) / _cellSize).ceil(),
    );
    for (int col = firstCol; col <= lastCol; col++) {
      for (int row = firstRow; row <= lastRow; row++) {
        final RenderBox child = buildOrObtainChildFor(
          ChildVicinity(xIndex: col, yIndex: row),
        )!;
        child.layout(BoxConstraints.tight(Size.square(_cellSize)));
        parentDataOf(child).layoutOffset = Offset(
          col * _cellSize - h,
          row * _cellSize - v,
        );
      }
    }
    verticalOffset.applyContentDimensions(
      0,
      math.max(0, (maxRow + 1) * _cellSize - viewportDimension.height),
    );
    horizontalOffset.applyContentDimensions(
      0,
      math.max(0, (maxCol + 1) * _cellSize - viewportDimension.width),
    );
  }
}
