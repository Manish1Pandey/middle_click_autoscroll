## 0.1.0

* Initial release of `middle_click_autoscroll` (middle-click autoscroll for Flutter
  desktop & web).
* `MiddleClickAutoscroll` widget: middle-mouse-button autoscroll for any
  `Scrollable` below it, or for a given `ScrollController`.
* Both axes, nested scrollable selection with hand-off at the edges,
  `TwoDimensionalScrollView` support.
* Modes `auto` (browser behaviour), `toggle` and `hold`; dead zone, pluggable
  speed curves (Chrome-like default, linear, power, callback) and max speed.
* Clamped `jumpTo` per frame via a `Ticker`: no overscroll, physics settle on
  stop.
* Stops on Escape, app/window focus loss, pointer leaving the window, mouse
  wheel, any click while latched, disable or dispose.
* Default anchor indicator (circle with arrows), custom `indicatorBuilder`,
  directional mouse cursors with a custom `cursorResolver`.
* Web: best-effort suppression of native middle-click autoscroll and Linux
  primary-selection paste inside the Flutter view.
