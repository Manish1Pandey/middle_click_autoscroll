import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:middle_click_autoscroll/middle_click_autoscroll.dart';
import 'package:middle_click_autoscroll_example/main.dart';

void main() {
  testWidgets('middle click in the demo autoscrolls the vertical tab', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const AutoscrollDemoApp());
    expect(find.textContaining('Idle'), findsOneWidget);

    final Offset anchor = tester.getCenter(find.text('Row 3'));
    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await mouse.addPointer(location: anchor);
    await mouse.down(anchor);
    await mouse.up();
    await tester.pump();
    expect(find.byType(DefaultAutoscrollIndicator), findsOneWidget);
    expect(find.textContaining('Autoscrolling (vertical)'), findsOneWidget);

    await mouse.moveTo(anchor + const Offset(0, 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Row 0'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Stopped.'), findsOneWidget);
    expect(find.byType(DefaultAutoscrollIndicator), findsNothing);
  });
}
