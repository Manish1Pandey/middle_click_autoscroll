# middle_click_autoscroll — Specification

Written before implementation. Solves
[flutter/flutter#66537](https://github.com/flutter/flutter/issues/66537):
Flutter scrollables do not support middle-mouse-button ("wheel click")
autoscroll, which every desktop browser and many desktop apps offer.

## 1. Purpose

A pure-Dart widget, `MiddleClickAutoscroll`, that wraps any subtree
containing scrollables (or drives a given `ScrollController`) and adds
browser-style middle-click autoscroll: press the wheel, move the mouse away
from the anchor point, and content scrolls at a speed proportional to the
distance. No platform channels, no native code.

## 2. Functional requirements

| ID | Requirement |
|----|-------------|
| FR1 | Autoscroll starts only on a `PointerDownEvent` whose `kind` is `PointerDeviceKind.mouse` and whose `buttons` equal `kMiddleMouseButton`. Touch, stylus, trackpad and other buttons are ignored. |
| FR2 | Target discovery (default): hit-test the press position and collect every `Scrollable` below the widget whose render object is in the hit path, ordered innermost first. Only scrollables with scrollable content (`maxScrollExtent > minScrollExtent`) whose physics accept user offset (`shouldAcceptUserOffset`) are eligible. If none is eligible, autoscroll does not start and the press is left alone. |
| FR3 | Controller mode: when `controller` is given, discovery is skipped and every `ScrollPosition` attached to it is driven instead. |
| FR4 | Both axes: vertical and horizontal velocity are computed independently from the pointer offset. |
| FR5 | Nested selection: every frame, for each axis with non-zero velocity, the innermost candidate on that axis that can still move in the requested direction is scrolled (so an inner list at its end hands off to its outer list). |
| FR6 | Modes: `auto` (Chrome: release without leaving the dead zone latches, release after dragging stops), `toggle` (release always latches; any later button press stops), `hold` (release always stops). |
| FR7 | Dead zone: no scrolling while the pointer is within `deadZoneRadius` logical pixels (Euclidean) of the anchor. Default 15 px (Chromium's value). |
| FR8 | Speed curve: pluggable `AutoscrollSpeedCurve` mapping per-axis distance (px) to speed (px/s). Presets: `chrome` (0.011 × d^2.2, modeled on Chromium's autoscroll constants), `LinearAutoscrollSpeedCurve`, `PowerAutoscrollSpeedCurve`, `CallbackAutoscrollSpeedCurve`. Result is clamped to `maxSpeed` (default 6000 px/s). |
| FR9 | Bounds and physics: each frame a `Ticker` computes `pixels + v·dt` (respecting reversed axis directions), clamps it to `[minScrollExtent, maxScrollExtent]` and calls `jumpTo`. Never overscrolls; an already-overscrolled position is only moved back toward range. `jumpTo` lets physics settle when scrolling stops (e.g. `PageView` snaps). |
| FR10 | Stop conditions: Escape key (consumed), app/window losing focus (`AppLifecycleState` other than `resumed`), pointer leaving the window (`PointerRemovedEvent`; on web a `pointerleave` of the `flutter-view` / window `blur`), mouse wheel or trackpad gesture, pointer cancel, the widget being disabled or disposed. |
| FR11 | Anchor indicator: drawn in the nearest `Overlay` (fallback: a `Stack` over the child when there is no Overlay). Default is the classic circle with arrows for the available axes, highlighting the current direction. Replaceable through `indicatorBuilder`, can be hidden with `showIndicator: false`. |
| FR12 | Mouse cursor: `allScroll` (both axes) / `resizeUpDown` / `resizeLeftRight` inside the dead zone; `resizeUp`, `resizeDown`, `resizeLeft`, `resizeRight`, `resizeUpLeft`, `resizeUpRight`, `resizeDownLeft`, `resizeDownRight` outside it (8 sectors). Overridable through `cursorResolver`. |
| FR13 | While autoscroll is active a transparent barrier sits above the content, so the click that stops a latched autoscroll is not delivered to the widget below (same as browsers). |
| FR14 | Web: best effort suppression of the browser's own middle-click behaviour for events whose target is inside a `flutter-view`: `preventDefault()` on middle `mousedown` / `mouseup`, and cancel a `paste` event that arrives within 500 ms of a middle press/release (Linux primary-selection paste). Can be turned off with `preventBrowserDefaults: false`. |
| FR15 | Callbacks `onAutoscrollStart(details)` and `onAutoscrollEnd()`. |

## 3. Can / Cannot

| Can | Cannot (honest limits) |
|-----|------------------------|
| Autoscroll any `Scrollable` (ListView, GridView, CustomScrollView, SingleChildScrollView, PageView, TwoDimensionalScrollView) on macOS, Windows, Linux, web, and mouse-equipped iPad/Android/ChromeOS | Do anything without a mouse middle button (touch/stylus/trackpad are intentionally ignored) |
| Pick the innermost scrollable per axis and chain to outer ones at the edge | Coordinate `NestedScrollView` header/body the way its own drag does — inner and outer positions are scrolled independently |
| Clamp to scroll extents, respect `NeverScrollableScrollPhysics`, let physics settle on stop | Keep scrolling while the Flutter window is unfocused (it stops by design) |
| Suppress Chrome/Firefox middle-click autoscroll and Linux paste inside the Flutter view on web (best effort) | Guarantee suppression in every browser: the browser decides; e.g. a browser extension or a policy may still act. Also cannot affect other native apps pasting on Linux desktop (X11/Wayland primary selection is outside Flutter) |
| Detect leaving the window on desktop embedders (they send pointer-remove) and on web (`pointerleave` of `flutter-view`) | Detect leaving the window while the button is held on desktop (the OS keeps delivering drag events; hold mode continues, like browsers) |
| Swallow the stopping click via an overlay barrier | Swallow the stopping click if the widget has no `Overlay` ancestor and the click lands outside the widget's own bounds |

## 4. Public API sketch

```dart
MiddleClickAutoscroll({
  required Widget child,
  bool enabled = true,
  AutoscrollMode mode = AutoscrollMode.auto,
  ScrollController? controller,
  double deadZoneRadius = 15,
  AutoscrollSpeedCurve speedCurve = AutoscrollSpeedCurve.chrome,
  double maxSpeed = 6000,
  bool showIndicator = true,
  AutoscrollIndicatorBuilder indicatorBuilder = defaultAutoscrollIndicatorBuilder,
  AutoscrollCursorResolver cursorResolver = defaultAutoscrollCursor,
  bool preventBrowserDefaults = true,
  ValueChanged<AutoscrollDetails>? onAutoscrollStart,
  VoidCallback? onAutoscrollEnd,
});

enum AutoscrollMode { auto, toggle, hold }
enum AutoscrollDirection { none, up, down, left, right, upLeft, upRight, downLeft, downRight }
class AutoscrollDetails { anchor, pointer, offset, velocity, direction,
  canScrollHorizontally, canScrollVertically, deadZoneRadius, isLatched }
abstract class AutoscrollSpeedCurve { double speedFor(double distance); static chrome; }
class LinearAutoscrollSpeedCurve, PowerAutoscrollSpeedCurve, CallbackAutoscrollSpeedCurve
class DefaultAutoscrollIndicator extends StatelessWidget
typedef AutoscrollIndicatorBuilder = Widget Function(BuildContext, AutoscrollDetails);
typedef AutoscrollCursorResolver = MouseCursor Function(AutoscrollDetails);
MouseCursor defaultAutoscrollCursor(AutoscrollDetails details);
Offset computeAutoscrollVelocity({...});           // pure function, unit-testable
AutoscrollDirection computeAutoscrollDirection({...});
```

## 5. Platform matrix

| Platform | Autoscroll | Cursor | Leave-window stop | Browser default suppression |
|----------|-----------|--------|-------------------|-----------------------------|
| macOS | Yes | Yes | Yes (pointer remove) | n/a |
| Windows | Yes | Yes | Yes (pointer remove) | n/a |
| Linux | Yes | Yes | Yes (pointer remove) | n/a |
| Web | Yes | Yes | Yes (`pointerleave`, `blur`) | Best effort (Chrome, Firefox, Safari) |
| Android / iOS | Yes with a mouse (tablets, ChromeOS, DeX) | Where the OS supports cursors | Engine dependent | n/a |

## 6. Non-goals

Smooth-scroll animation of the wheel itself, keyboard scrolling, or changing
how the platform handles the middle button outside the Flutter view.
