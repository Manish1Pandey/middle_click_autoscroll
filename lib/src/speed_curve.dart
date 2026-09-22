import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Maps the pointer's distance from the autoscroll anchor along one axis to a
/// scroll speed.
///
/// [speedFor] receives a non-negative distance in logical pixels and returns
/// a non-negative speed in logical pixels per second. The result is clamped
/// by `MiddleClickAutoscroll.maxSpeed`, and it is only consulted when the
/// pointer is outside the dead zone.
@immutable
abstract class AutoscrollSpeedCurve {
  /// Const constructor for subclasses.
  const AutoscrollSpeedCurve();

  /// A curve modeled on Chromium's middle-click autoscroll:
  /// `speed = 0.011 * distance ^ 2.2` pixels per second.
  ///
  /// Slow near the anchor, accelerating quickly further away (about
  /// 280 px/s at 100 px, 3000 px/s at 300 px).
  static const AutoscrollSpeedCurve chrome = PowerAutoscrollSpeedCurve(
    multiplier: 0.011,
    exponent: 2.2,
  );

  /// Returns the speed in logical pixels per second for a pointer that is
  /// [distance] logical pixels away from the anchor along one axis.
  double speedFor(double distance);
}

/// `speed = multiplier * distance ^ exponent` (pixels per second).
class PowerAutoscrollSpeedCurve extends AutoscrollSpeedCurve {
  /// Creates a power curve. Both values must be positive.
  const PowerAutoscrollSpeedCurve({
    required this.multiplier,
    required this.exponent,
  }) : assert(multiplier > 0),
       assert(exponent > 0);

  /// Scale factor applied to `distance ^ exponent`.
  final double multiplier;

  /// Exponent applied to the distance.
  final double exponent;

  @override
  double speedFor(double distance) =>
      multiplier * math.pow(distance.abs(), exponent).toDouble();

  @override
  bool operator ==(Object other) =>
      other is PowerAutoscrollSpeedCurve &&
      other.multiplier == multiplier &&
      other.exponent == exponent;

  @override
  int get hashCode => Object.hash(multiplier, exponent);
}

/// `speed = pixelsPerSecondPerPixel * distance`: speed exactly proportional
/// to the distance from the anchor.
class LinearAutoscrollSpeedCurve extends AutoscrollSpeedCurve {
  /// Creates a linear curve. [pixelsPerSecondPerPixel] must be positive.
  const LinearAutoscrollSpeedCurve({this.pixelsPerSecondPerPixel = 10})
    : assert(pixelsPerSecondPerPixel > 0);

  /// Speed gained (px/s) for every logical pixel of distance.
  final double pixelsPerSecondPerPixel;

  @override
  double speedFor(double distance) => pixelsPerSecondPerPixel * distance.abs();

  @override
  bool operator ==(Object other) =>
      other is LinearAutoscrollSpeedCurve &&
      other.pixelsPerSecondPerPixel == pixelsPerSecondPerPixel;

  @override
  int get hashCode => pixelsPerSecondPerPixel.hashCode;
}

/// A curve defined by an arbitrary function.
///
/// Negative or non-finite results are treated as zero.
class CallbackAutoscrollSpeedCurve extends AutoscrollSpeedCurve {
  /// Wraps [callback], which maps distance (px) to speed (px/s).
  const CallbackAutoscrollSpeedCurve(this.callback);

  /// The mapping from distance (px) to speed (px/s).
  final double Function(double distance) callback;

  @override
  double speedFor(double distance) {
    final double speed = callback(distance.abs());
    if (!speed.isFinite || speed < 0) {
      return 0;
    }
    return speed;
  }
}
