import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'autoscroll_details.dart';
import 'browser_guard.dart';
import 'indicator.dart';
import 'speed_curve.dart';

enum _Phase { idle, pressed, latched }

/// Adds browser-style middle-mouse-button autoscroll to the scrollables in
/// [child] (or to the positions of [controller]).
///
/// Press the mouse wheel over a scrollable, move the pointer away from the
/// press point (the anchor) and the content scrolls, faster the further the
/// pointer is from the anchor. See [mode] for how it stops.
///
/// Only mouse events whose buttons are exactly [kMiddleMouseButton] start
/// autoscroll; touch, stylus and trackpad input is ignored.
///
/// ```dart
/// MiddleClickAutoscroll(
///   child: ListView.builder(
///     itemCount: 1000,
///     itemBuilder: (context, i) => ListTile(title: Text('Item $i')),
///   ),
/// )
/// ```
class MiddleClickAutoscroll extends StatefulWidget {
  /// Creates the autoscroll wrapper.
  const MiddleClickAutoscroll({
    super.key,
    required this.child,
    this.enabled = true,
    this.mode = AutoscrollMode.auto,
    this.controller,
    this.deadZoneRadius = 15,
    this.speedCurve = AutoscrollSpeedCurve.chrome,
    this.maxSpeed = 6000,
    this.showIndicator = true,
    this.indicatorBuilder = defaultAutoscrollIndicatorBuilder,
    this.cursorResolver = defaultAutoscrollCursor,
    this.preventBrowserDefaults = true,
    this.onAutoscrollStart,
    this.onAutoscrollEnd,
  }) : assert(deadZoneRadius >= 0),
       assert(maxSpeed > 0);

  /// The subtree containing the scrollables.
  final Widget child;

  /// Whether middle-click autoscroll is active. Setting it to false stops an
  /// ongoing autoscroll.
  final bool enabled;

  /// How pressing and releasing the middle button starts and stops
  /// autoscroll. Defaults to [AutoscrollMode.auto] (browser behaviour).
  final AutoscrollMode mode;

  /// When non-null, autoscroll drives every position attached to this
  /// controller instead of discovering the scrollables under the pointer.
  final ScrollController? controller;

  /// Radius in logical pixels around the anchor inside which nothing
  /// scrolls. Defaults to 15, Chromium's value.
  final double deadZoneRadius;

  /// Maps the per-axis distance from the anchor to a speed.
  final AutoscrollSpeedCurve speedCurve;

  /// Upper bound for the per-axis speed, in logical pixels per second.
  final double maxSpeed;

  /// Whether to draw the anchor indicator.
  final bool showIndicator;

  /// Builds the anchor indicator, centered on the anchor.
  final AutoscrollIndicatorBuilder indicatorBuilder;

  /// Chooses the mouse cursor shown while autoscroll is active.
  final AutoscrollCursorResolver cursorResolver;

  /// On the web, suppress the browser's own middle-click autoscroll and the
  /// Linux primary-selection paste for events inside the Flutter view (best
  /// effort). Ignored on other platforms.
  final bool preventBrowserDefaults;

  /// Called when autoscroll starts, with the initial state.
  final ValueChanged<AutoscrollDetails>? onAutoscrollStart;

  /// Called when autoscroll stops, for any reason.
  final VoidCallback? onAutoscrollEnd;

  @override
  State<MiddleClickAutoscroll> createState() => _MiddleClickAutoscrollState();
}

class _MiddleClickAutoscrollState extends State<MiddleClickAutoscroll>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  Ticker? _tickerInstance;
  Ticker get _ticker => _tickerInstance ??= createTicker(_onTick);
  final OverlayPortalController _portal = OverlayPortalController();
  final ValueNotifier<AutoscrollDetails?> _details =
      ValueNotifier<AutoscrollDetails?>(null);

  _Phase _phase = _Phase.idle;
  PointerDownEvent? _startEvent;
  int _device = -1;
  bool _leftDeadZone = false;
  Offset _layerShift = Offset.zero;
  List<ScrollableState> _scrollables = const <ScrollableState>[];
  Duration _lastElapsed = Duration.zero;
  bool _hasOverlay = false;
  Object? _browserGuard;

  bool get _active => _phase != _Phase.idle;

  /// The press most recently claimed by any instance. When instances are
  /// nested, the innermost one receives the press first and claims it, so
  /// outer instances do not start a second, concurrent autoscroll.
  static PointerDownEvent? _claimedPress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _installGuard();
  }

  @override
  void didUpdateWidget(MiddleClickAutoscroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled ||
        widget.controller != oldWidget.controller ||
        widget.deadZoneRadius != oldWidget.deadZoneRadius) {
      _stop(fromBuild: true);
    }
    if (widget.preventBrowserDefaults != oldWidget.preventBrowserDefaults) {
      uninstallBrowserGuard(_browserGuard);
      _installGuard();
    }
    if (_active) {
      _refreshDetails();
    }
  }

  @override
  void dispose() {
    _stop(disposing: true);
    uninstallBrowserGuard(_browserGuard);
    WidgetsBinding.instance.removeObserver(this);
    _tickerInstance?.dispose();
    _details.dispose();
    super.dispose();
  }

  void _installGuard() {
    _browserGuard = installBrowserGuard(
      preventDefaults: widget.preventBrowserDefaults,
      onPointerLeftView: () {
        if (_phase == _Phase.latched) {
          _stop();
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _stop();
    }
  }

  // ---------------------------------------------------------------------------
  // Target discovery

  List<ScrollableState> _scrollablesAt(Offset globalPosition) {
    final HitTestResult result = HitTestResult();
    RendererBinding.instance.hitTestInView(
      result,
      globalPosition,
      View.of(context).viewId,
    );
    final Set<Object> hitTargets = <Object>{
      for (final HitTestEntry entry in result.path) entry.target,
    };

    final List<ScrollableState> found = <ScrollableState>[];
    void visit(Element element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final RenderObject? box = element.renderObject;
        if (box != null && hitTargets.contains(box)) {
          found.add(element.state as ScrollableState);
        }
      }
      element.visitChildElements(visit);
    }

    context.visitChildElements(visit);
    // Pre-order visits ancestors before descendants, so the reversed list is
    // innermost first.
    return found.reversed.toList();
  }

  List<ScrollPosition> _positions() {
    final ScrollController? controller = widget.controller;
    if (controller != null) {
      return controller.hasClients
          ? controller.positions.toList()
          : const <ScrollPosition>[];
    }
    return <ScrollPosition>[
      for (final ScrollableState state in _scrollables)
        if (state.mounted) state.position,
    ];
  }

  static bool _isScrollable(ScrollPosition p) {
    return p.hasPixels &&
        p.hasContentDimensions &&
        p.maxScrollExtent > p.minScrollExtent &&
        p.physics.shouldAcceptUserOffset(p);
  }

  static bool _canMove(ScrollPosition p, double pixelDelta) {
    if (!_isScrollable(p)) {
      return false;
    }
    if (pixelDelta > 0) {
      return p.pixels < p.maxScrollExtent;
    }
    if (pixelDelta < 0) {
      return p.pixels > p.minScrollExtent;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Pointer handling

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.enabled ||
        _active ||
        event.kind != PointerDeviceKind.mouse ||
        event.buttons != kMiddleMouseButton) {
      return;
    }
    final PointerDownEvent original =
        (event.original ?? event) as PointerDownEvent;
    if (identical(original, _claimedPress)) {
      return;
    }
    if (widget.controller == null) {
      _scrollables = _scrollablesAt(event.position);
    }
    final List<ScrollPosition> positions = _positions();
    final bool horizontal = positions.any(
      (ScrollPosition p) => p.axis == Axis.horizontal && _isScrollable(p),
    );
    final bool vertical = positions.any(
      (ScrollPosition p) => p.axis == Axis.vertical && _isScrollable(p),
    );
    if (!horizontal && !vertical) {
      _scrollables = const <ScrollableState>[];
      return;
    }

    // The Listener receives a transformed copy; the global route sees the
    // original object for this same press.
    _startEvent = original;
    _claimedPress = original;
    _device = event.device;
    _leftDeadZone = false;
    _phase = _Phase.pressed;
    _hasOverlay = Overlay.maybeOf(context) != null;
    final RenderObject? layerBox = _hasOverlay
        ? Overlay.of(context).context.findRenderObject()
        : context.findRenderObject();
    _layerShift = layerBox is RenderBox && layerBox.hasSize
        ? layerBox.globalToLocal(Offset.zero)
        : Offset.zero;

    _details.value = AutoscrollDetails(
      anchor: event.position,
      pointer: event.position,
      velocity: Offset.zero,
      direction: AutoscrollDirection.none,
      canScrollHorizontally: horizontal,
      canScrollVertically: vertical,
      deadZoneRadius: widget.deadZoneRadius,
      isLatched: false,
    );
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handleGlobalPointer);
    HardwareKeyboard.instance.addHandler(_handleKey);
    if (_hasOverlay) {
      _portal.show();
    }
    widget.onAutoscrollStart?.call(_details.value!);
  }

  void _handleGlobalPointer(PointerEvent event) {
    if (!_active || identical(event, _startEvent)) {
      return;
    }
    if (event is PointerRemovedEvent) {
      if (event.device == _device) {
        _stop();
      }
      return;
    }
    if (event is PointerSignalEvent || event is PointerPanZoomStartEvent) {
      _stop();
      return;
    }
    if (event is PointerDownEvent) {
      // Any press while latched (or a second device while held) stops. The
      // overlay barrier keeps that click away from the content.
      _stop();
      return;
    }
    if (event.device != _device) {
      return;
    }
    if (event is PointerCancelEvent) {
      _stop();
      return;
    }
    if (event is PointerMoveEvent || event is PointerHoverEvent) {
      _updatePointer(event.position);
      return;
    }
    if (event is PointerUpEvent && _phase == _Phase.pressed) {
      final bool stop = switch (widget.mode) {
        AutoscrollMode.hold => true,
        AutoscrollMode.toggle => false,
        AutoscrollMode.auto => _leftDeadZone,
      };
      if (stop) {
        _stop();
      } else {
        _phase = _Phase.latched;
        _details.value = _details.value?.copyWith(isLatched: true);
      }
    }
  }

  bool _handleKey(KeyEvent event) {
    if (_active &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _stop();
      return true;
    }
    return false;
  }

  void _updatePointer(Offset position) {
    final AutoscrollDetails? current = _details.value;
    if (current == null) {
      return;
    }
    if ((position - current.anchor).distance > widget.deadZoneRadius) {
      _leftDeadZone = true;
    }
    _details.value = _withMotion(current.copyWith(pointer: position));
    _syncTicker();
  }

  void _refreshDetails() {
    final AutoscrollDetails? current = _details.value;
    if (current != null) {
      _details.value = _withMotion(current);
      _syncTicker();
    }
  }

  AutoscrollDetails _withMotion(AutoscrollDetails d) {
    return d.copyWith(
      velocity: computeAutoscrollVelocity(
        offset: d.offset,
        deadZoneRadius: widget.deadZoneRadius,
        curve: widget.speedCurve,
        maxSpeed: widget.maxSpeed,
        horizontal: d.canScrollHorizontally,
        vertical: d.canScrollVertically,
      ),
      direction: computeAutoscrollDirection(
        offset: d.offset,
        deadZoneRadius: widget.deadZoneRadius,
        horizontal: d.canScrollHorizontally,
        vertical: d.canScrollVertically,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Frame loop

  void _syncTicker() {
    final Offset velocity = _details.value?.velocity ?? Offset.zero;
    if (_active && velocity != Offset.zero) {
      if (!_ticker.isActive) {
        _lastElapsed = Duration.zero;
        _ticker.start();
      }
    } else if (_tickerInstance?.isActive ?? false) {
      _tickerInstance!.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final double seconds =
        (elapsed - _lastElapsed).inMicroseconds /
        Duration.microsecondsPerSecond;
    _lastElapsed = elapsed;
    final AutoscrollDetails? details = _details.value;
    if (details == null || seconds <= 0) {
      return;
    }
    final List<ScrollPosition> positions = _positions();
    _scrollAxis(positions, Axis.horizontal, details.velocity.dx * seconds);
    _scrollAxis(positions, Axis.vertical, details.velocity.dy * seconds);
  }

  /// Scrolls the innermost position on [axis] that can move by the
  /// screen-space [screenDelta].
  void _scrollAxis(
    List<ScrollPosition> positions,
    Axis axis,
    double screenDelta,
  ) {
    if (screenDelta == 0) {
      return;
    }
    for (final ScrollPosition p in positions) {
      if (p.axis != axis) {
        continue;
      }
      final double pixelDelta = axisDirectionIsReversed(p.axisDirection)
          ? -screenDelta
          : screenDelta;
      if (!_canMove(p, pixelDelta)) {
        continue;
      }
      final double target = pixelDelta > 0
          ? (p.pixels + pixelDelta).clamp(p.pixels, p.maxScrollExtent)
          : (p.pixels + pixelDelta).clamp(p.minScrollExtent, p.pixels);
      if (target != p.pixels) {
        p.jumpTo(target);
      }
      return;
    }
  }

  // ---------------------------------------------------------------------------
  // Stop

  /// Stops autoscroll. [fromBuild] defers the end callback past the current
  /// frame and leaves the (now empty) overlay in place, because both would
  /// otherwise mutate the tree during a build. [disposing] skips everything
  /// that touches the tree or user code.
  void _stop({bool fromBuild = false, bool disposing = false}) {
    if (!_active) {
      return;
    }
    _phase = _Phase.idle;
    _startEvent = null;
    _device = -1;
    _scrollables = const <ScrollableState>[];
    if (_tickerInstance?.isActive ?? false) {
      _tickerInstance!.stop();
    }
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _handleGlobalPointer,
    );
    HardwareKeyboard.instance.removeHandler(_handleKey);
    if (disposing) {
      return;
    }
    _details.value = null;
    final VoidCallback? onEnd = widget.onAutoscrollEnd;
    if (fromBuild) {
      if (onEnd != null) {
        SchedulerBinding.instance.addPostFrameCallback((Duration _) => onEnd());
      }
      return;
    }
    if (_portal.isShowing) {
      _portal.hide();
    }
    onEnd?.call();
  }

  // ---------------------------------------------------------------------------
  // Build

  Widget _buildLayer(BuildContext context) {
    return ValueListenableBuilder<AutoscrollDetails?>(
      valueListenable: _details,
      builder: (BuildContext context, AutoscrollDetails? details, Widget? _) {
        if (details == null) {
          return const SizedBox();
        }
        final Offset anchor = details.anchor + _layerShift;
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            // Barrier: shows the cursor and keeps the stopping click and
            // hover effects away from the content below.
            Positioned.fill(
              child: MouseRegion(
                cursor: widget.cursorResolver(details),
                child: const _Barrier(),
              ),
            ),
            if (widget.showIndicator)
              Positioned(
                left: anchor.dx,
                top: anchor.dy,
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: IgnorePointer(
                    child: widget.indicatorBuilder(context, details),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget listener = Listener(
      // Translucent so presses on empty areas (for example around a
      // controller-driven list) are seen without blocking anything below.
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      child: widget.child,
    );
    if (Overlay.maybeOf(context) != null) {
      return OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (BuildContext context) =>
            Positioned.fill(child: _buildLayer(context)),
        child: listener,
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        listener,
        Positioned.fill(child: _buildLayer(context)),
      ],
    );
  }
}

/// An opaque, invisible hit target.
class _Barrier extends StatelessWidget {
  const _Barrier();

  @override
  Widget build(BuildContext context) {
    return const Listener(
      behavior: HitTestBehavior.opaque,
      child: SizedBox.expand(),
    );
  }
}
