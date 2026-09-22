@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:middle_click_autoscroll/src/browser_guard.dart';
import 'package:web/web.dart' as web;

web.MouseEvent _mouse(String type, int button) => web.MouseEvent(
  type,
  web.MouseEventInit(button: button, bubbles: true, cancelable: true),
);

void main() {
  late web.Element view;
  late web.Element inside;
  late web.Element outside;

  setUp(() {
    view = web.document.createElement('flutter-view');
    inside = web.document.createElement('div');
    outside = web.document.createElement('div');
    view.append(inside);
    web.document.body!
      ..append(view)
      ..append(outside);
  });

  tearDown(() {
    view.remove();
    outside.remove();
  });

  test('cancels middle mousedown/mouseup only inside flutter-view', () {
    final Object? guard = installBrowserGuard(
      preventDefaults: true,
      onPointerLeftView: () {},
    );
    addTearDown(() => uninstallBrowserGuard(guard));

    final web.MouseEvent down = _mouse('mousedown', 1);
    inside.dispatchEvent(down);
    expect(down.defaultPrevented, isTrue);

    final web.MouseEvent up = _mouse('mouseup', 1);
    inside.dispatchEvent(up);
    expect(up.defaultPrevented, isTrue);

    final web.MouseEvent primary = _mouse('mousedown', 0);
    inside.dispatchEvent(primary);
    expect(primary.defaultPrevented, isFalse);

    final web.MouseEvent elsewhere = _mouse('mousedown', 1);
    outside.dispatchEvent(elsewhere);
    expect(elsewhere.defaultPrevented, isFalse);
  });

  test('cancels a paste right after a middle click, not later ones', () async {
    final Object? guard = installBrowserGuard(
      preventDefaults: true,
      onPointerLeftView: () {},
    );
    addTearDown(() => uninstallBrowserGuard(guard));

    web.Event paste() {
      final web.Event e = web.Event(
        'paste',
        web.EventInit(bubbles: true, cancelable: true),
      );
      inside.dispatchEvent(e);
      return e;
    }

    expect(paste().defaultPrevented, isFalse);
    inside.dispatchEvent(_mouse('mouseup', 1));
    expect(paste().defaultPrevented, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(paste().defaultPrevented, isFalse);
  });

  test('reports the mouse leaving the flutter-view and window blur', () {
    int left = 0;
    final Object? guard = installBrowserGuard(
      preventDefaults: false,
      onPointerLeftView: () => left++,
    );
    addTearDown(() => uninstallBrowserGuard(guard));

    view.dispatchEvent(
      web.PointerEvent(
        'pointerleave',
        web.PointerEventInit(pointerType: 'mouse', buttons: 0),
      ),
    );
    expect(left, 1);
    // Held buttons (hold mode drag) do not count.
    view.dispatchEvent(
      web.PointerEvent(
        'pointerleave',
        web.PointerEventInit(pointerType: 'mouse', buttons: 4),
      ),
    );
    expect(left, 1);
    web.window.dispatchEvent(web.Event('blur'));
    expect(left, 2);

    // preventDefaults: false leaves middle clicks alone.
    final web.MouseEvent down = _mouse('mousedown', 1);
    inside.dispatchEvent(down);
    expect(down.defaultPrevented, isFalse);
  });

  test('uninstall removes every listener', () {
    int left = 0;
    final Object? guard = installBrowserGuard(
      preventDefaults: true,
      onPointerLeftView: () => left++,
    );
    uninstallBrowserGuard(guard);
    final web.MouseEvent down = _mouse('mousedown', 1);
    inside.dispatchEvent(down);
    expect(down.defaultPrevented, isFalse);
    web.window.dispatchEvent(web.Event('blur'));
    expect(left, 0);
    expect(guard, isNotNull);
  });
}
