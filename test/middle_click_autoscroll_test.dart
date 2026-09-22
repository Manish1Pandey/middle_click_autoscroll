import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:middle_click_autoscroll/middle_click_autoscroll.dart';

import 'two_dimensional_grid.dart';

/// Drives a real mouse [TestPointer] through the binding.
class Mouse {
  Mouse(this.tester, {int pointer = 1})
    : pointer = TestPointer(
        pointer,
        PointerDeviceKind.mouse,
        null,
        kMiddleMouseButton,
      );

  final WidgetTester tester;
  final TestPointer pointer;
  bool _added = false;

  Future<void> _send(PointerEvent e) => tester.sendEventToBinding(e);

  Future<void> hover(Offset at) async {
    if (!_added) {
      _added = true;
      await _send(pointer.addPointer(location: at));
    }
    await _send(pointer.hover(at));
  }

  Future<void> down(Offset at, {int buttons = kMiddleMouseButton}) async {
    await hover(at);
    await _send(pointer.down(at, buttons: buttons));
  }

  Future<void> move(Offset to) => _send(pointer.move(to));
  Future<void> up() => _send(pointer.up());
  Future<void> remove() => _send(pointer.removePointer());
  Future<void> wheel(Offset delta) => _send(pointer.scroll(delta));

  /// Middle click (press + release without moving).
  Future<void> middleClick(Offset at) async {
    await down(at);
    await up();
  }

  /// A complete click with [buttons].
  Future<void> click(Offset at, {int buttons = kPrimaryButton}) async {
    await down(at, buttons: buttons);
    await up();
  }
}

const Offset center = Offset(400, 300);

/// Pumps [frames] frames of [step] each, after one initial frame that
/// starts the ticker at elapsed = 0.
Future<void> run(
  WidgetTester tester, {
  int frames = 5,
  Duration step = const Duration(milliseconds: 100),
}) async {
  await tester.pump();
  for (int i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

Widget verticalList({
  required ScrollController controller,
  int itemCount = 1000,
  ScrollPhysics? physics,
  bool reverse = false,
  ValueChanged<int>? onTap,
}) {
  return ListView.builder(
    controller: controller,
    physics: physics,
    reverse: reverse,
    itemExtent: 50,
    itemCount: itemCount,
    itemBuilder: (BuildContext context, int i) => ListTile(
      title: Text('Item $i'),
      onTap: onTap == null ? null : () => onTap(i),
    ),
  );
}

Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

const AutoscrollSpeedCurve linear10 = LinearAutoscrollSpeedCurve(
  pixelsPerSecondPerPixel: 10,
);

void main() {
  group('pure functions', () {
    test('velocity is zero inside the dead zone', () {
      expect(
        computeAutoscrollVelocity(
          offset: const Offset(10, 10),
          deadZoneRadius: 15,
          curve: linear10,
          maxSpeed: 10000,
        ),
        Offset.zero,
      );
    });

    test('velocity is per-axis, signed and clamped', () {
      expect(
        computeAutoscrollVelocity(
          offset: const Offset(-20, 100),
          deadZoneRadius: 15,
          curve: linear10,
          maxSpeed: 800,
        ),
        const Offset(-200, 800),
      );
      expect(
        computeAutoscrollVelocity(
          offset: const Offset(-20, 100),
          deadZoneRadius: 15,
          curve: linear10,
          maxSpeed: 800,
          horizontal: false,
        ),
        const Offset(0, 800),
      );
    });

    test('chrome curve follows 0.011 * d^2.2', () {
      expect(AutoscrollSpeedCurve.chrome.speedFor(100), closeTo(276.3, 0.5));
      expect(AutoscrollSpeedCurve.chrome.speedFor(300), closeTo(3097.8, 0.5));
      expect(
        AutoscrollSpeedCurve.chrome.speedFor(200),
        greaterThan(AutoscrollSpeedCurve.chrome.speedFor(100) * 2),
      );
    });

    test('callback curve sanitises bad values', () {
      final CallbackAutoscrollSpeedCurve curve = CallbackAutoscrollSpeedCurve(
        (double d) => d < 50 ? -1 : double.nan,
      );
      expect(curve.speedFor(10), 0);
      expect(curve.speedFor(100), 0);
      expect(
        const PowerAutoscrollSpeedCurve(
          multiplier: 2,
          exponent: 2,
        ).speedFor(-3),
        18,
      );
    });

    test('direction snaps to eight sectors and respects axes', () {
      AutoscrollDirection dir(Offset o, {bool h = true, bool v = true}) =>
          computeAutoscrollDirection(
            offset: o,
            deadZoneRadius: 15,
            horizontal: h,
            vertical: v,
          );
      expect(dir(const Offset(5, 5)), AutoscrollDirection.none);
      expect(dir(const Offset(0, 100)), AutoscrollDirection.down);
      expect(dir(const Offset(0, -100)), AutoscrollDirection.up);
      expect(dir(const Offset(100, 0)), AutoscrollDirection.right);
      expect(dir(const Offset(-100, 0)), AutoscrollDirection.left);
      expect(dir(const Offset(100, 100)), AutoscrollDirection.downRight);
      expect(dir(const Offset(-100, -100)), AutoscrollDirection.upLeft);
      expect(dir(const Offset(100, -100)), AutoscrollDirection.upRight);
      expect(dir(const Offset(-100, 100)), AutoscrollDirection.downLeft);
      expect(dir(const Offset(100, 100), h: false), AutoscrollDirection.down);
      expect(dir(const Offset(100, 0), h: false), AutoscrollDirection.none);
    });

    test('default cursor matches direction and axes', () {
      AutoscrollDetails d(AutoscrollDirection dir, {bool h = true}) =>
          AutoscrollDetails(
            anchor: Offset.zero,
            pointer: Offset.zero,
            velocity: Offset.zero,
            direction: dir,
            canScrollHorizontally: h,
            canScrollVertically: true,
            deadZoneRadius: 15,
            isLatched: false,
          );
      expect(
        defaultAutoscrollCursor(d(AutoscrollDirection.none)),
        SystemMouseCursors.allScroll,
      );
      expect(
        defaultAutoscrollCursor(d(AutoscrollDirection.none, h: false)),
        SystemMouseCursors.resizeUpDown,
      );
      expect(
        defaultAutoscrollCursor(d(AutoscrollDirection.downLeft)),
        SystemMouseCursors.resizeDownLeft,
      );
      expect(
        defaultAutoscrollCursor(d(AutoscrollDirection.up)),
        SystemMouseCursors.resizeUp,
      );
    });
  });

  group('toggle and hold', () {
    testWidgets('auto mode: click-release latches, any click stops', (
      WidgetTester tester,
    ) async {
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      int starts = 0, ends = 0;
      final List<int> taps = <int>[];
      await tester.pumpWidget(
        app(
          MiddleClickAutoscroll(
            speedCurve: linear10,
            onAutoscrollStart: (_) => starts++,
            onAutoscrollEnd: () => ends++,
            child: verticalList(controller: controller, onTap: taps.add),
          ),
        ),
      );
      final Mouse mouse = Mouse(tester);
      await mouse.middleClick(center);
      expect(starts, 1);
      expect(find.byType(DefaultAutoscrollIndicator), findsNothing);
      await tester.pump();
      expect(find.byType(DefaultAutoscrollIndicator), findsOneWidget);

      await mouse.hover(center + const Offset(0, 100)); // 1000 px/s
      await run(tester);
      expect(controller.offset, closeTo(500, 0.01));

      // A primary click stops it and is swallowed by the barrier.
      await mouse.click(const Offset(100, 100));
      await tester.pump();
      expect(ends, 1);
      expect(taps, isEmpty);
      final double stoppedAt = controller.offset;
      await mouse.hover(center + const Offset(0, 200));
      await run(tester);
      expect(controller.offset, stoppedAt);
      expect(find.byType(DefaultAutoscrollIndicator), findsNothing);

      // Once stopped, clicks reach the list again.
      await mouse.click(const Offset(100, 125));
      await tester.pump();
      expect(taps, hasLength(1));
    });

    testWidgets('auto mode: release after dragging out of the dead zone '
        'stops', (WidgetTester tester) async {
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      int ends = 0;
      await tester.pumpWidget(
        app(
          MiddleClickAutoscroll(
            speedCurve: linear10,
            onAutoscrollEnd: () => ends++,
            child: verticalList(controller: controller),
          ),
        ),
      );
      final Mouse mouse = Mouse(tester);
      await mouse.down(center);
      await mouse.move(center + const Offset(0, 50)); // 500 px/s
      await run(tester, frames: 2);
      expect(controller.offset, closeTo(100, 0.01));
      await mouse.up();
      expect(ends, 1);
      final double at = controller.offset;
      await run(tester);
      expect(controller.offset, at);
    });

    testWidgets('toggle mode: release after dragging keeps scrolling', (
      WidgetTester tester,
    ) async {
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      int ends = 0;
      await tester.pumpWidget(
        app(
          MiddleClickAutoscroll(
            mode: AutoscrollMode.toggle,
            speedCurve: linear10,
            onAutoscrollEnd: () => ends++,
            child: verticalList(controller: controller),
          ),
        ),
      );
      final Mouse mouse = Mouse(tester);
      await mouse.down(center);
      await mouse.move(center + const Offset(0, 50));
      await mouse.up();
      expect(ends, 0);
      await run(tester, frames: 4);
      expect(controller.offset, closeTo(200, 0.01));
      // A middle click also stops.
      await mouse.middleClick(center);
      expect(ends, 1);
    });

    testWidgets('hold mode: scrolls while held, release stops even without '
        'movement', (WidgetTester tester) async {
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      int ends = 0;
      await tester.pumpWidget(
        app(
          MiddleClickAutoscroll(
            mode: AutoscrollMode.hold,
            speedCurve: linear10,
            onAutoscrollEnd: () => ends++,
            child: verticalList(controller: controller),
          ),
        ),
      );
      final Mouse mouse = Mouse(tester);
      await mouse.middleClick(center);
      expect(ends, 1, reason: 'hold mode never latches');

      await mouse.down(center);
      await mouse.move(center + const Offset(0, 30)); // 300 px/s
      await run(tester, frames: 3);
      expect(controller.offset, closeTo(90, 0.01));
      await mouse.up();
      expect(ends, 2);
      await run(tester);
      expect(controller.offset, closeTo(90, 0.01));
    });
  });

  group('speed', () {
    testWidgets('dead zone: no scrolling inside the radius', (
      WidgetTester tester,
    ) async {
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      AutoscrollDetails? lastDetails;
      await tester.pumpWidget(
        app(
          MiddleClickAutoscroll(
            deadZoneRadius: 40,
            speedCurve: linear10,
            indicatorBuilder: (BuildContext context, AutoscrollDetails d) {
              lastDetails = d;
              return const SizedBox.square(dimension: 10);
            },
            child: verticalList(controller: controller),
          ),
        ),
      );
      final Mouse mouse = Mouse(tester);
      await mouse.middleClick(center);
      await mouse.hover(center + const Offset(0, 39));
      await run(tester);
      expect(controller.offset, 0);
      expect(lastDetails!.direction, AutoscrollDirection.none);
      expect(lastDetails!.velocity, Offset.zero);
      expect(lastDetails!.isLatched, isTrue);

      await mouse.hover(center + const Offset(0, 41));
      await run(tester, frames: 1);
      expect(controller.offset, closeTo(41, 0.01));
      expect(lastDetails!.direction, AutoscrollDirection.down);
    });

    testWidgets('speed is proportional to the distance and clamped', (
      WidgetTester tester,
    ) async {
      Future<double> scrolledFor(double distance, {double max = 1e6}) async {
        final ScrollController controller = ScrollController();
        await tester.pumpWidget(
          app(
            MiddleClickAutoscroll(
              key: UniqueKey(),
              speedCurve: linear10,
              maxSpeed: max,
              child: verticalList(controller: controller),
            ),
          ),
        );
        final Mouse mouse = Mouse(tester);
        await mouse.middleClick(center);
        await mouse.hover(center + Offset(0, distance));
        await run(tester);
        final double offset = controller.offset;
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await mouse.remove();
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        return offset;
      }

      final double at50 = await scrolledFor(50);
      final double at100 = await scrolledFor(100);
      final double at150 = await scrolledFor(150);
      expect(at50, closeTo(250, 0.01));
      expect(at100, closeTo(500, 0.01));
      expect(at150, closeTo(750, 0.01));
      expect(at100 / at50, closeTo(2, 1e-6));
      expect(await scrolledFor(100, max: 300), closeTo(150, 0.01));
    });

    testWidgets('default chrome curve accelerates with distance', (
      WidgetTester tester,
    ) async {
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        app(MiddleClickAutoscroll(child: verticalList(controller: controller))),
      );
      final Mouse mouse = Mouse(tester);
      await mouse.middleClick(center);
      await mouse.hover(center + const Offset(0, 100));
      await run(tester, frames: 10); // 1 s at ~276 px/s
      expect(controller.offset, closeTo(276.3, 0.5));
    });
  });

  group('bounds and physics', () {
    testWidgets('clamps at both ends without overscroll (bouncing physics)', (
      WidgetTester tester,
    ) async {
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      final List<double> seen = <double>[];
      controller.addListener(() => seen.add(controller.offset));
      await tester.pumpWidget(
        app(
          MiddleClickAutoscroll(
            speedCurve: linear10,
            child: verticalList(
              controller: controller,
              itemCount: 20, // 1000 px of content
              physics: const BouncingScrollPhysics(),
            ),
          ),
        ),
      );
      final double max = controller.position.maxScrollExtent;
      expect(max, greaterThan(0));

      final Mouse mouse = Mouse(tester);
      await mouse.middleClick(center);
      await mouse.hover(center + const Offset(0, -200)); // up at 0: no-op
      await run(tester);
      expect(controller.offset, 0);

      await mouse.hover(center + const Offset(0, 250)); // 2500 px/s
      await run(tester, frames: 10);
      expect(controller.offset, max);
      expect(seen.every((double o) => o >= 0 && o <= max), isTrue);
    });

    testWidgets('does not start on non-scrollable physics or content', (
      WidgetTester tester,
    ) async {
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      int starts = 0;
      await tester.pumpWidget(
        app(
          MiddleClickAutoscroll(
            onAutoscrollStart: (_) => starts++,
            child: verticalList(
              controller: controller,
              physics: const NeverScrollableScrollPhysics(),
            ),
          ),
        ),
      );
      final Mouse mouse = Mouse(tester);
      await mouse.middleClick(center);
      expect(starts, 0);

      await tester.pumpWidget(
        app(
          MiddleClickAutoscroll(
            key: UniqueKey(),
            onAutoscrollStart: (_) => starts++,
            child: verticalList(controller: controller, itemCount: 3),
          ),
        ),
      );
      await mouse.middleClick(const Offset(100, 50));
      expect(starts, 0);
    });

    testWidgets('reversed lists scroll toward the pointer on screen', (
      WidgetTester tester,
    ) async {
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        app(
          MiddleClickAutoscroll(
            speedCurve: linear10,
            child: verticalList(controller: controller, reverse: true),
          ),
        ),
      );
      final Mouse mouse = Mouse(tester);
      await mouse.middleClick(center);
      await mouse.hover(center + const Offset(0, 100)); // down: already there
      await run(tester);
      expect(controller.offset, 0);
      await mouse.hover(center - const Offset(0, 100)); // up reveals older
      await run(tester);
      expect(controller.offset, closeTo(500, 0.01));
    });
  });

  group('nested scrollables', () {
    Widget nested({
      required ScrollController outer,
      required ScrollController innerVertical,
      required ScrollController horizontal,
    }) {
      return app(
        MiddleClickAutoscroll(
          speedCurve: linear10,
          child: ListView(
            controller: outer,
            children: <Widget>[
              SizedBox(
                height: 200,
                child: ListView.builder(
                  controller: horizontal,
                  scrollDirection: Axis.horizontal,
                  itemExtent: 100,
                  itemCount: 50,
                  itemBuilder: (_, int i) => Text('H$i'),
                ),
              ),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  controller: innerVertical,
                  itemExtent: 50,
                  itemCount: 6, // 300 px content, 100 px scroll range
                  itemBuilder: (_, int i) => Text('V$i'),
                ),
              ),
              for (int i = 0; i < 40; i++)
                SizedBox(height: 50, child: Text('Row $i')),
            ],
          ),
        ),
      );
    }

    testWidgets('horizontal list under the pointer takes horizontal motion, '
        'outer list takes vertical', (WidgetTester tester) async {
      final ScrollController outer = ScrollController();
      final ScrollController inner = ScrollController();
      final ScrollController horizontal = ScrollController();
      addTearDown(outer.dispose);
      addTearDown(inner.dispose);
      addTearDown(horizontal.dispose);
      await tester.pumpWidget(
        nested(outer: outer, innerVertical: inner, horizontal: horizontal),
      );
      final Mouse mouse = Mouse(tester);
      const Offset onHorizontal = Offset(400, 100);
      await mouse.middleClick(onHorizontal);
      await mouse.hover(onHorizontal + const Offset(100, 0));
      await run(tester, frames: 2);
      expect(horizontal.offset, closeTo(200, 0.01));
      expect(outer.offset, 0);

      await mouse.hover(onHorizontal + const Offset(0, 100));
      await run(tester, frames: 2);
      expect(horizontal.offset, closeTo(200, 0.01));
      expect(outer.offset, closeTo(200, 0.01));
      expect(inner.offset, 0);
    });

    testWidgets('innermost vertical list scrolls first, then hands off to '
        'the outer list at its end', (WidgetTester tester) async {
      final ScrollController outer = ScrollController();
      final ScrollController inner = ScrollController();
      final ScrollController horizontal = ScrollController();
      addTearDown(outer.dispose);
      addTearDown(inner.dispose);
      addTearDown(horizontal.dispose);
      await tester.pumpWidget(
        nested(outer: outer, innerVertical: inner, horizontal: horizontal),
      );
      final Mouse mouse = Mouse(tester);
      const Offset onInner = Offset(400, 300);
      await mouse.middleClick(onInner);
      await mouse.hover(onInner + const Offset(0, 60)); // 600 px/s
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(inner.offset, closeTo(60, 0.01));
      expect(outer.offset, 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(inner.offset, inner.position.maxScrollExtent); // 100, clamped
      expect(outer.offset, 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(outer.offset, closeTo(60, 0.01));
      expect(horizontal.offset, 0);
    });

    testWidgets('both axes of a 2D (nested) scroll view', (
      WidgetTester tester,
    ) async {
      final ScrollController v = ScrollController();
      final ScrollController h = ScrollController();
      addTearDown(v.dispose);
      addTearDown(h.dispose);
      AutoscrollDetails? started;
      await tester.pumpWidget(
        app(
          MiddleClickAutoscroll(
            speedCurve: linear10,
            onAutoscrollStart: (AutoscrollDetails d) => started = d,
            child: SingleChildScrollView(
              controller: v,
              child: SingleChildScrollView(
                controller: h,
                scrollDirection: Axis.horizontal,
                child: const SizedBox(width: 5000, height: 5000),
              ),
            ),
          ),
        ),
      );
      final Mouse mouse = Mouse(tester);
      await mouse.middleClick(center);
      expect(started!.canScrollHorizontally, isTrue);
      expect(started!.canScrollVertically, isTrue);
      await mouse.hover(center + const Offset(30, -20)); // right+up
      await run(tester, frames: 2);
      expect(h.offset, closeTo(60, 0.01));
      expect(v.offset, 0); // up at the top
      await mouse.hover(center + const Offset(-20, 40));
      await run(tester, frames: 2);
      expect(h.offset, closeTo(20, 0.01));
      expect(v.offset, closeTo(80, 0.01));
    });

    testWidgets('TwoDimensionalScrollView: both axes, clamped', (
      WidgetTester tester,
    ) async {
      final ScrollController v = ScrollController();
      final ScrollController h = ScrollController();
      addTearDown(v.dispose);
      addTearDown(h.dispose);
      await tester.pumpWidget(
        app(
          MiddleClickAutoscroll(
            speedCurve: linear10,
            child: FixedGrid(
              verticalDetails: ScrollableDetails.vertical(controller: v),
              horizontalDetails: ScrollableDetails.horizontal(controller: h),
              delegate: TwoDimensionalChildBuilderDelegate(
                maxXIndex: 19,
                maxYIndex: 29,
                builder: (_, ChildVicinity c) =>
                    Text('${c.xIndex},${c.yIndex}'),
              ),
            ),
          ),
        ),
      );
      final Mouse mouse = Mouse(tester);
      await mouse.middleClick(center);
      await mouse.hover(center + const Offset(40, 30));
      await run(tester, frames: 2);
      expect(h.offset, closeTo(80, 0.01));
      expect(v.offset, closeTo(60, 0.01));
      await mouse.hover(center + const Offset(300, 300)); // 3000 px/s
      await run(tester, frames: 20);
      expect(h.offset, h.position.maxScrollExtent); // 2000 - 800
      expect(v.offset, v.position.maxScrollExtent); // 3000 - 600
      expect(find.text('19,29'), findsOneWidget);
    });

    testWidgets('nested MiddleClickAutoscroll widgets: only the innermost '
        'starts', (WidgetTester tester) async {
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      int outerStarts = 0, innerStarts = 0;
      await tester.pumpWidget(
        app(
          MiddleClickAutoscroll(
            speedCurve: linear10,
            onAutoscrollStart: (_) => outerStarts++,
            child: MiddleClickAutoscroll(
              speedCurve: linear10,
              onAutoscrollStart: (_) => innerStarts++,
              child: verticalList(controller: controller),
            ),
          ),
        ),
      );
      final Mouse mouse = Mouse(tester);
      await mouse.middleClick(center);
      await mouse.hover(center + const Offset(0, 100));
      await run(tester, frames: 2);
      expect(innerStarts, 1);
      expect(outerStarts, 0);
      expect(controller.offset, closeTo(200, 0.01)); // not doubled
      await tester.pump();
      expect(find.byType(DefaultAutoscrollIndicator), findsOneWidget);
    });

    testWidgets('controller mode drives the given controller from anywhere '
        'inside the widget', (WidgetTester tester) async {
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        app(
          MiddleClickAutoscroll(
            controller: controller,
            speedCurve: linear10,
            child: Column(
              children: <Widget>[
                const SizedBox(height: 100, child: Text('Header')),
                Expanded(child: verticalList(controller: controller)),
              ],
            ),
          ),
        ),
      );
      final Mouse mouse = Mouse(tester);
      await mouse.middleClick(const Offset(20, 20)); // on the header
      await mouse.hover(const Offset(20, 70));
      await run(tester, frames: 2);
      expect(controller.offset, closeTo(100, 0.01));
    });
  });

  group('stopping and input filtering', () {
    Future<(ScrollController, List<int>)> pumpList(
      WidgetTester tester, {
      bool enabled = true,
    }) async {
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      final List<int> ends = <int>[0];
      await tester.pumpWidget(
        app(
          MiddleClickAutoscroll(
            enabled: enabled,
            speedCurve: linear10,
            onAutoscrollEnd: () => ends[0]++,
            child: verticalList(controller: controller),
          ),
        ),
      );
      return (controller, ends);
    }

    testWidgets('Escape cancels and is consumed', (WidgetTester tester) async {
      final (ScrollController controller, List<int> ends) = await pumpList(
        tester,
      );
      final Mouse mouse = Mouse(tester);
      await mouse.middleClick(center);
      await mouse.hover(center + const Offset(0, 100));
      await run(tester, frames: 1);
      expect(controller.offset, closeTo(100, 0.01));
      final bool handled = await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(handled, isTrue);
      expect(ends[0], 1);
      await run(tester);
      expect(controller.offset, closeTo(100, 0.01));
      expect(find.byType(DefaultAutoscrollIndicator), findsNothing);
    });

    testWidgets('pointer leaving the window stops', (
      WidgetTester tester,
    ) async {
      final (_, List<int> ends) = await pumpList(tester);
      final Mouse mouse = Mouse(tester);
      await mouse.middleClick(center);
      await mouse.remove();
      expect(ends[0], 1);
    });

    testWidgets('app losing focus stops', (WidgetTester tester) async {
      final (_, List<int> ends) = await pumpList(tester);
      await Mouse(tester).middleClick(center);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(ends[0], 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    testWidgets('mouse wheel stops', (WidgetTester tester) async {
      final (_, List<int> ends) = await pumpList(tester);
      final Mouse mouse = Mouse(tester);
      await mouse.middleClick(center);
      await mouse.wheel(const Offset(0, 20));
      expect(ends[0], 1);
    });

    testWidgets('disabling stops and reports the end after the frame', (
      WidgetTester tester,
    ) async {
      final (ScrollController controller, List<int> ends) = await pumpList(
        tester,
      );
      await Mouse(tester).middleClick(center);
      await tester.pumpWidget(
        app(
          MiddleClickAutoscroll(
            enabled: false,
            onAutoscrollEnd: () => ends[0]++,
            child: verticalList(controller: controller),
          ),
        ),
      );
      expect(ends[0], 1);
      expect(find.byType(DefaultAutoscrollIndicator), findsNothing);
    });

    testWidgets('ignores touch, stylus and non-middle mouse buttons', (
      WidgetTester tester,
    ) async {
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      int starts = 0;
      await tester.pumpWidget(
        app(
          MiddleClickAutoscroll(
            onAutoscrollStart: (_) => starts++,
            child: verticalList(controller: controller),
          ),
        ),
      );
      for (final PointerDeviceKind kind in <PointerDeviceKind>[
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
      ]) {
        final TestPointer p = TestPointer(5, kind, null, kMiddleMouseButton);
        await tester.sendEventToBinding(p.down(center));
        await tester.sendEventToBinding(p.up());
      }
      final Mouse mouse = Mouse(tester);
      await mouse.click(center, buttons: kPrimaryButton);
      await mouse.click(center, buttons: kSecondaryButton);
      await mouse.click(center, buttons: kMiddleMouseButton | kPrimaryButton);
      expect(starts, 0);
      await mouse.middleClick(center);
      expect(starts, 1);
    });

    testWidgets('disabled widget never starts', (WidgetTester tester) async {
      final (_, List<int> ends) = await pumpList(tester, enabled: false);
      await Mouse(tester).middleClick(center);
      await tester.pump();
      expect(find.byType(DefaultAutoscrollIndicator), findsNothing);
      expect(ends[0], 0);
    });
  });

  group('indicator and cursor', () {
    testWidgets('cursor follows direction', (WidgetTester tester) async {
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        app(MiddleClickAutoscroll(child: verticalList(controller: controller))),
      );
      MouseCursor? cursor() =>
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);
      final Mouse mouse = Mouse(tester);
      await mouse.middleClick(center);
      await tester.pump();
      await mouse.hover(center + const Offset(1, 1));
      expect(cursor(), SystemMouseCursors.resizeUpDown); // vertical only
      await mouse.hover(center + const Offset(0, 80));
      await tester.pump();
      await mouse.hover(center + const Offset(0, 81));
      expect(cursor(), SystemMouseCursors.resizeDown);
      await mouse.hover(center + const Offset(0, -81));
      await tester.pump();
      await mouse.hover(center + const Offset(0, -80));
      expect(cursor(), SystemMouseCursors.resizeUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await mouse.hover(center);
      expect(cursor(), isNot(SystemMouseCursors.resizeUp));
    });

    testWidgets('custom indicator and cursor, positioned at the anchor', (
      WidgetTester tester,
    ) async {
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      const Key key = Key('custom');
      await tester.pumpWidget(
        app(
          MiddleClickAutoscroll(
            cursorResolver: (_) => SystemMouseCursors.grab,
            indicatorBuilder: (_, AutoscrollDetails d) => SizedBox.square(
              key: key,
              dimension: 20,
              child: Text(d.direction.name),
            ),
            child: verticalList(controller: controller),
          ),
        ),
      );
      final Mouse mouse = Mouse(tester);
      await mouse.middleClick(center);
      await tester.pump();
      expect(find.byKey(key), findsOneWidget);
      expect(tester.getCenter(find.byKey(key)), center);
      await mouse.hover(center + const Offset(0, 100));
      await tester.pump();
      expect(find.text('down'), findsOneWidget);
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.grab,
      );
    });

    testWidgets('showIndicator: false hides it', (WidgetTester tester) async {
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        app(
          MiddleClickAutoscroll(
            showIndicator: false,
            child: verticalList(controller: controller),
          ),
        ),
      );
      await Mouse(tester).middleClick(center);
      await tester.pump();
      expect(find.byType(DefaultAutoscrollIndicator), findsNothing);
    });

    testWidgets('works without an Overlay ancestor', (
      WidgetTester tester,
    ) async {
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MiddleClickAutoscroll(
            speedCurve: linear10,
            child: ListView.builder(
              controller: controller,
              itemExtent: 50,
              itemCount: 200,
              itemBuilder: (_, int i) => Text('$i'),
            ),
          ),
        ),
      );
      final Mouse mouse = Mouse(tester);
      await mouse.middleClick(center);
      await tester.pump();
      expect(find.byType(DefaultAutoscrollIndicator), findsOneWidget);
      expect(tester.getCenter(find.byType(DefaultAutoscrollIndicator)), center);
      await mouse.hover(center + const Offset(0, 100));
      await run(tester, frames: 1);
      expect(controller.offset, closeTo(100, 0.01));
    });

    testWidgets('default indicator paints arrows for available axes', (
      WidgetTester tester,
    ) async {
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        app(MiddleClickAutoscroll(child: verticalList(controller: controller))),
      );
      final Mouse mouse = Mouse(tester);
      await mouse.middleClick(center);
      await mouse.hover(center + const Offset(0, 100));
      await tester.pump();
      final CustomPaint paint = tester.widget(
        find.descendant(
          of: find.byType(DefaultAutoscrollIndicator),
          matching: find.byType(CustomPaint),
        ),
      );
      final AutoscrollIndicatorPainter painter =
          paint.painter! as AutoscrollIndicatorPainter;
      expect(painter.vertical, isTrue);
      expect(painter.horizontal, isFalse);
      expect(painter.direction, AutoscrollDirection.down);
      // 1 circle fill + 1 outline + 1 center dot + 2 arrows.
      expect(
        find.byType(DefaultAutoscrollIndicator),
        paints
          ..circle()
          ..circle()
          ..circle()
          ..path(color: const Color(0xFF5F6368))
          ..path(color: const Color(0xFF1A73E8)),
      );
    });
  });
}
