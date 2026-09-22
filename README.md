# middle_click_autoscroll

**Middle-click autoscroll for Flutter desktop & web.** This package brings
browser-style middle-mouse-button autoscroll to Flutter scrollables through
one widget, `MiddleClickAutoscroll`. Press the mouse wheel, move the pointer away from the anchor
and the content scrolls, faster the further you move. Click again (or release
after dragging) to stop.

Flutter's scrollables do not do this on their own; this package fills the gap
reported in [flutter/flutter#66537](https://github.com/flutter/flutter/issues/66537).
It is pure Dart: no platform channels, no native code.

## Features

- Wraps any subtree: `ListView`, `GridView`, `CustomScrollView`,
  `SingleChildScrollView`, `PageView`, `TwoDimensionalScrollView`, or drives a
  `ScrollController` you pass.
- Both axes at once, independently.
- Nested scrollables: the innermost scrollable under the pointer that can move
  in the requested direction wins; when it reaches its end, the next outer one
  takes over.
- Modes: `auto` (what Chrome does), `toggle`, `hold`.
- Dead zone (default 15 px, as in Chromium), pluggable speed curve (default
  modeled on Chromium: `0.011 · d^2.2` px/s), max speed.
- Frame-based scrolling with a `Ticker` and clamped `jumpTo`: never overscrolls,
  respects `NeverScrollableScrollPhysics`, lets physics settle when it stops.
- Stops on Escape, focus loss, pointer leaving the window, mouse wheel, any
  click (the stopping click is swallowed, like in browsers).
- Classic anchor indicator (circle with arrows) or your own via a builder.
- Directional mouse cursors (`allScroll`, `resizeUp`, `resizeDownLeft`, ...).
- Web: blocks the browser's own middle-click autoscroll and the Linux
  primary-selection paste inside the Flutter view (best effort).
- Only mouse input with exactly the middle button starts it; touch, stylus and
  trackpad are ignored.

## Install

```yaml
dependencies:
  middle_click_autoscroll: ^0.1.0
```

## Usage

```dart
import 'package:middle_click_autoscroll/middle_click_autoscroll.dart';

MiddleClickAutoscroll(
  child: ListView.builder(
    itemCount: 1000,
    itemBuilder: (context, i) => ListTile(title: Text('Item $i')),
  ),
);
```

Wrap high in the tree (for example around a whole page) and every scrollable
below gets autoscroll; the one under the pointer is chosen at press time.

### Options

```dart
MiddleClickAutoscroll(
  mode: AutoscrollMode.toggle,          // auto | toggle | hold
  deadZoneRadius: 20,                   // px
  speedCurve: const LinearAutoscrollSpeedCurve(pixelsPerSecondPerPixel: 8),
  maxSpeed: 4000,                       // px/s per axis
  controller: myScrollController,       // optional: drive this instead
  indicatorBuilder: (context, details) => MyAnchor(details: details),
  cursorResolver: (details) => SystemMouseCursors.move,
  preventBrowserDefaults: true,         // web only
  onAutoscrollStart: (details) {},
  onAutoscrollEnd: () {},
  child: ...,
);
```

| Mode | Press + release without moving | Press, drag out of the dead zone, release |
|------|-------------------------------|-------------------------------------------|
| `auto` (default) | keeps scrolling until next click | stops |
| `toggle` | keeps scrolling until next click | keeps scrolling until next click |
| `hold` | stops | stops |

Speed curves: `AutoscrollSpeedCurve.chrome`, `LinearAutoscrollSpeedCurve`,
`PowerAutoscrollSpeedCurve`, `CallbackAutoscrollSpeedCurve((d) => ...)` or
your own subclass. The pure helpers `computeAutoscrollVelocity` and
`computeAutoscrollDirection` are exported for custom indicators.

`AutoscrollDetails` (given to builders and callbacks) contains the anchor,
pointer, current velocity, snapped `AutoscrollDirection`, which axes can
scroll and whether the autoscroll is latched.

## Platform support

| Platform | Autoscroll | Cursors | Stops when pointer leaves window | Browser default blocking |
|----------|:---------:|:-------:|:--------------------------------:|:------------------------:|
| macOS | yes | yes | yes | n/a |
| Windows | yes | yes | yes | n/a |
| Linux | yes | yes | yes | n/a |
| Web | yes | yes | yes | best effort |
| Android / iOS | with a mouse (tablets, ChromeOS, DeX) | where the OS shows cursors | embedder dependent | n/a |

## Limitations

- The widget only sees scrollables **below** it in the tree.
- `NestedScrollView`'s coordinated header/body scrolling is not reproduced:
  its inner and outer positions are scrolled independently.
- While the button is **held**, desktop OSes keep delivering drag events
  outside the window, so hold mode continues there (as in browsers). Latched
  autoscroll stops when the pointer leaves the window.
- Web: the browser has the final word. The package cancels middle-button
  `mousedown`/`mouseup` and any `paste` within 500 ms of a middle click inside
  the `flutter-view`, which stops Chrome's and Firefox's autoscroll and the
  Linux primary-selection paste in current browsers, but extensions, browser
  settings or future browser changes may still act. It cannot affect other
  apps or the X11/Wayland primary selection itself.
- Without an `Overlay` ancestor the indicator is drawn over the widget itself
  and a stopping click outside the widget is not swallowed.
- `onAutoscrollEnd` is not called when the widget is disposed mid-scroll.
- Indicator widgets must have a finite size.

## Example

`example/` contains a desktop/web app with vertical, horizontal, 2D grid,
nested and controller-driven tabs, and live controls for every option.
