import 'package:flutter/widgets.dart';

import 'autoscroll_details.dart';

/// Builds the anchor indicator shown while autoscroll is active.
///
/// The returned widget is centered on the anchor point and ignores pointer
/// events. It should have a finite intrinsic size (for example a
/// [SizedBox]).
typedef AutoscrollIndicatorBuilder =
    Widget Function(BuildContext context, AutoscrollDetails details);

/// The default indicator builder: a [DefaultAutoscrollIndicator].
Widget defaultAutoscrollIndicatorBuilder(
  BuildContext context,
  AutoscrollDetails details,
) {
  return DefaultAutoscrollIndicator(details: details);
}

/// The classic browser autoscroll anchor: a circle with a center dot and an
/// arrow for every direction that can scroll. Arrows pointing toward the
/// current scroll direction are highlighted.
class DefaultAutoscrollIndicator extends StatelessWidget {
  /// Creates the indicator for [details].
  const DefaultAutoscrollIndicator({
    super.key,
    required this.details,
    this.diameter = 34,
    this.fillColor = const Color(0xF2FFFFFF),
    this.borderColor = const Color(0xFF5F6368),
    this.arrowColor = const Color(0xFF5F6368),
    this.activeArrowColor = const Color(0xFF1A73E8),
  });

  /// The autoscroll state to render.
  final AutoscrollDetails details;

  /// Outer diameter in logical pixels.
  final double diameter;

  /// Background of the circle.
  final Color fillColor;

  /// Circle outline color.
  final Color borderColor;

  /// Color of arrows (and the center dot) that are not active.
  final Color arrowColor;

  /// Color of arrows pointing toward the current scroll direction.
  final Color activeArrowColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Autoscroll anchor',
      child: SizedBox.square(
        dimension: diameter,
        child: CustomPaint(
          painter: AutoscrollIndicatorPainter(
            direction: details.direction,
            horizontal: details.canScrollHorizontally,
            vertical: details.canScrollVertically,
            fillColor: fillColor,
            borderColor: borderColor,
            arrowColor: arrowColor,
            activeArrowColor: activeArrowColor,
          ),
        ),
      ),
    );
  }
}

/// Paints the [DefaultAutoscrollIndicator]. Public so custom indicators can
/// reuse it (for example inside a larger decoration).
class AutoscrollIndicatorPainter extends CustomPainter {
  /// Creates the painter.
  const AutoscrollIndicatorPainter({
    required this.direction,
    required this.horizontal,
    required this.vertical,
    required this.fillColor,
    required this.borderColor,
    required this.arrowColor,
    required this.activeArrowColor,
  });

  /// Current direction; arrows toward it are highlighted.
  final AutoscrollDirection direction;

  /// Whether to draw left/right arrows.
  final bool horizontal;

  /// Whether to draw up/down arrows.
  final bool vertical;

  /// Background of the circle.
  final Color fillColor;

  /// Circle outline color.
  final Color borderColor;

  /// Inactive arrow color.
  final Color arrowColor;

  /// Active arrow color.
  final Color activeArrowColor;

  bool get _up =>
      direction == AutoscrollDirection.up ||
      direction == AutoscrollDirection.upLeft ||
      direction == AutoscrollDirection.upRight;
  bool get _down =>
      direction == AutoscrollDirection.down ||
      direction == AutoscrollDirection.downLeft ||
      direction == AutoscrollDirection.downRight;
  bool get _left =>
      direction == AutoscrollDirection.left ||
      direction == AutoscrollDirection.upLeft ||
      direction == AutoscrollDirection.downLeft;
  bool get _right =>
      direction == AutoscrollDirection.right ||
      direction == AutoscrollDirection.upRight ||
      direction == AutoscrollDirection.downRight;

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.shortestSide / 2;
    final Offset center = size.center(Offset.zero);
    canvas.drawCircle(center, radius - 1, Paint()..color = fillColor);
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawCircle(center, radius * 0.1, Paint()..color = arrowColor);

    final double tip = radius * 0.78;
    final double base = radius * 0.42;
    final double half = radius * 0.24;
    void arrow(Offset unit, bool active) {
      final Offset normal = Offset(-unit.dy, unit.dx);
      final Path path = Path()
        ..moveTo(center.dx + unit.dx * tip, center.dy + unit.dy * tip)
        ..lineTo(
          center.dx + unit.dx * base + normal.dx * half,
          center.dy + unit.dy * base + normal.dy * half,
        )
        ..lineTo(
          center.dx + unit.dx * base - normal.dx * half,
          center.dy + unit.dy * base - normal.dy * half,
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = active ? activeArrowColor : arrowColor,
      );
    }

    if (vertical) {
      arrow(const Offset(0, -1), _up);
      arrow(const Offset(0, 1), _down);
    }
    if (horizontal) {
      arrow(const Offset(-1, 0), _left);
      arrow(const Offset(1, 0), _right);
    }
  }

  @override
  bool shouldRepaint(AutoscrollIndicatorPainter oldDelegate) =>
      oldDelegate.direction != direction ||
      oldDelegate.horizontal != horizontal ||
      oldDelegate.vertical != vertical ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.arrowColor != arrowColor ||
      oldDelegate.activeArrowColor != activeArrowColor;
}
