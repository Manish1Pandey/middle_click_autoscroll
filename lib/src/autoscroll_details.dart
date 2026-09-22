import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'speed_curve.dart';

/// How pressing and releasing the middle button controls autoscroll.
enum AutoscrollMode {
  /// Browser behaviour (Chrome, Firefox on Windows): releasing the button
  /// before the pointer left the dead zone keeps autoscroll running until the
  /// next click; releasing after dragging out of the dead zone stops it.
  auto,

  /// Click-release starts autoscroll; it keeps running after release until
  /// any mouse button is pressed again.
  toggle,

  /// Autoscroll runs only while the middle button is held down.
  hold,
}

/// The direction the pointer points to relative to the anchor, snapped to
/// one of eight 45° sectors, restricted to the axes that can scroll.
enum AutoscrollDirection {
  /// Inside the dead zone: no scrolling.
  none,

  /// Content scrolls toward the top.
  up,

  /// Content scrolls toward the bottom.
  down,

  /// Content scrolls toward the left.
  left,

  /// Content scrolls toward the right.
  right,

  /// Diagonal up and left.
  upLeft,

  /// Diagonal up and right.
  upRight,

  /// Diagonal down and left.
  downLeft,

  /// Diagonal down and right.
  downRight,
}

/// A snapshot of an active autoscroll, passed to indicator builders, cursor
/// resolvers and `onAutoscrollStart`.
@immutable
class AutoscrollDetails {
  /// Creates a snapshot.
  const AutoscrollDetails({
    required this.anchor,
    required this.pointer,
    required this.velocity,
    required this.direction,
    required this.canScrollHorizontally,
    required this.canScrollVertically,
    required this.deadZoneRadius,
    required this.isLatched,
  });

  /// Global position where the middle button was pressed.
  final Offset anchor;

  /// Current global pointer position.
  final Offset pointer;

  /// Pointer position relative to [anchor].
  Offset get offset => pointer - anchor;

  /// Current screen-space scroll velocity in logical pixels per second.
  ///
  /// Positive `dx` reveals content to the right, positive `dy` reveals
  /// content further down, regardless of each scrollable's axis direction.
  final Offset velocity;

  /// The snapped direction of the current movement.
  final AutoscrollDirection direction;

  /// Whether at least one scrollable under the anchor scrolls horizontally.
  final bool canScrollHorizontally;

  /// Whether at least one scrollable under the anchor scrolls vertically.
  final bool canScrollVertically;

  /// The dead zone radius in logical pixels.
  final double deadZoneRadius;

  /// Whether the middle button has been released and autoscroll continues
  /// until the next click (toggle state).
  final bool isLatched;

  /// Returns a copy with the given fields replaced.
  AutoscrollDetails copyWith({
    Offset? pointer,
    Offset? velocity,
    AutoscrollDirection? direction,
    bool? isLatched,
  }) {
    return AutoscrollDetails(
      anchor: anchor,
      pointer: pointer ?? this.pointer,
      velocity: velocity ?? this.velocity,
      direction: direction ?? this.direction,
      canScrollHorizontally: canScrollHorizontally,
      canScrollVertically: canScrollVertically,
      deadZoneRadius: deadZoneRadius,
      isLatched: isLatched ?? this.isLatched,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AutoscrollDetails &&
      other.anchor == anchor &&
      other.pointer == pointer &&
      other.velocity == velocity &&
      other.direction == direction &&
      other.canScrollHorizontally == canScrollHorizontally &&
      other.canScrollVertically == canScrollVertically &&
      other.deadZoneRadius == deadZoneRadius &&
      other.isLatched == isLatched;

  @override
  int get hashCode => Object.hash(
    anchor,
    pointer,
    velocity,
    direction,
    canScrollHorizontally,
    canScrollVertically,
    deadZoneRadius,
    isLatched,
  );

  @override
  String toString() =>
      'AutoscrollDetails(anchor: $anchor, pointer: $pointer, '
      'velocity: $velocity, direction: ${direction.name}, '
      'latched: $isLatched)';
}

/// Computes the screen-space autoscroll velocity (px/s) for a pointer that is
/// [offset] away from the anchor.
///
/// Returns [Offset.zero] inside the circular dead zone. Outside it each axis
/// is computed independently with [curve], clamped to [maxSpeed], signed like
/// [offset], and zeroed for axes that cannot scroll.
Offset computeAutoscrollVelocity({
  required Offset offset,
  required double deadZoneRadius,
  required AutoscrollSpeedCurve curve,
  required double maxSpeed,
  bool horizontal = true,
  bool vertical = true,
}) {
  if (offset.distance <= deadZoneRadius) {
    return Offset.zero;
  }
  double component(double distance, bool enabled) {
    if (!enabled || distance == 0) {
      return 0;
    }
    final double raw = curve.speedFor(distance.abs());
    final double speed = raw.isFinite ? raw.clamp(0.0, maxSpeed) : maxSpeed;
    return speed * distance.sign;
  }

  return Offset(
    component(offset.dx, horizontal),
    component(offset.dy, vertical),
  );
}

/// Snaps [offset] (pointer minus anchor) to one of eight directions, taking
/// into account which axes can scroll. Returns [AutoscrollDirection.none]
/// inside the dead zone.
AutoscrollDirection computeAutoscrollDirection({
  required Offset offset,
  required double deadZoneRadius,
  bool horizontal = true,
  bool vertical = true,
}) {
  final Offset effective = Offset(
    horizontal ? offset.dx : 0,
    vertical ? offset.dy : 0,
  );
  if (offset.distance <= deadZoneRadius || effective == Offset.zero) {
    return AutoscrollDirection.none;
  }
  // Angle in degrees, 0 = right, 90 = down (screen coordinates).
  final double degrees =
      (math.atan2(effective.dy, effective.dx) * 180 / math.pi + 360) % 360;
  final int sector = ((degrees + 22.5) ~/ 45) % 8;
  const List<AutoscrollDirection> sectors = <AutoscrollDirection>[
    AutoscrollDirection.right,
    AutoscrollDirection.downRight,
    AutoscrollDirection.down,
    AutoscrollDirection.downLeft,
    AutoscrollDirection.left,
    AutoscrollDirection.upLeft,
    AutoscrollDirection.up,
    AutoscrollDirection.upRight,
  ];
  return sectors[sector];
}

/// Signature of a function choosing the mouse cursor during autoscroll.
typedef AutoscrollCursorResolver =
    MouseCursor Function(AutoscrollDetails details);

/// The default cursor: `allScroll` / `resizeUpDown` / `resizeLeftRight` in
/// the dead zone (depending on the scrollable axes), otherwise the
/// directional resize cursor matching [AutoscrollDetails.direction].
MouseCursor defaultAutoscrollCursor(AutoscrollDetails details) {
  switch (details.direction) {
    case AutoscrollDirection.none:
      if (details.canScrollHorizontally && details.canScrollVertically) {
        return SystemMouseCursors.allScroll;
      }
      if (details.canScrollVertically) {
        return SystemMouseCursors.resizeUpDown;
      }
      return SystemMouseCursors.resizeLeftRight;
    case AutoscrollDirection.up:
      return SystemMouseCursors.resizeUp;
    case AutoscrollDirection.down:
      return SystemMouseCursors.resizeDown;
    case AutoscrollDirection.left:
      return SystemMouseCursors.resizeLeft;
    case AutoscrollDirection.right:
      return SystemMouseCursors.resizeRight;
    case AutoscrollDirection.upLeft:
      return SystemMouseCursors.resizeUpLeft;
    case AutoscrollDirection.upRight:
      return SystemMouseCursors.resizeUpRight;
    case AutoscrollDirection.downLeft:
      return SystemMouseCursors.resizeDownLeft;
    case AutoscrollDirection.downRight:
      return SystemMouseCursors.resizeDownRight;
  }
}
