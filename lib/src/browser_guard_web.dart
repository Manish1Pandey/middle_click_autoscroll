import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// How long after a middle press/release a `paste` event is attributed to the
/// middle click (Linux primary-selection paste) and cancelled.
const Duration _pasteWindow = Duration(milliseconds: 500);

class _BrowserGuard {
  _BrowserGuard(this.preventDefaults, this.onPointerLeftView);

  final bool preventDefaults;
  final void Function() onPointerLeftView;
  final List<(web.EventTarget, String, JSFunction)> _listeners =
      <(web.EventTarget, String, JSFunction)>[];
  DateTime _lastMiddle = DateTime.fromMillisecondsSinceEpoch(0);

  static bool _insideFlutterView(web.EventTarget? target) {
    if (target == null || !target.isA<web.Element>()) {
      return false;
    }
    return (target as web.Element).closest('flutter-view') != null;
  }

  void _listen(
    web.EventTarget target,
    String type,
    void Function(web.Event) f,
  ) {
    final JSFunction js = f.toJS;
    target.addEventListener(type, js, true.toJS);
    _listeners.add((target, type, js));
  }

  void install() {
    if (preventDefaults) {
      void recordMiddle(web.Event event) {
        final web.MouseEvent mouse = event as web.MouseEvent;
        if (mouse.button == 1 && _insideFlutterView(event.target)) {
          _lastMiddle = DateTime.now();
        }
      }

      void cancelMiddle(web.Event event) {
        final web.MouseEvent mouse = event as web.MouseEvent;
        if (mouse.button == 1 && _insideFlutterView(event.target)) {
          _lastMiddle = DateTime.now();
          // Stops the browser's own autoscroll (mousedown) and, in Chromium,
          // the primary-selection paste performed on mouseup.
          event.preventDefault();
        }
      }

      // Flutter itself cancels `pointerdown`, which suppresses the
      // compatibility mouse events in some browsers, so pointer events are
      // recorded too for the paste window.
      _listen(web.document, 'pointerdown', recordMiddle);
      _listen(web.document, 'pointerup', recordMiddle);
      _listen(web.document, 'mousedown', cancelMiddle);
      _listen(web.document, 'mouseup', cancelMiddle);
      _listen(web.document, 'paste', (web.Event event) {
        if (DateTime.now().difference(_lastMiddle) <= _pasteWindow) {
          event.preventDefault();
        }
      });
    }
    _listen(web.document, 'pointerleave', (web.Event event) {
      final web.EventTarget? target = event.target;
      if (target == null || !target.isA<web.Element>()) {
        return;
      }
      final web.Element element = target as web.Element;
      final web.PointerEvent pointer = event as web.PointerEvent;
      if (element.tagName.toLowerCase() == 'flutter-view' &&
          pointer.pointerType == 'mouse' &&
          pointer.buttons == 0) {
        onPointerLeftView();
      }
    });
    _listen(web.window, 'blur', (web.Event _) => onPointerLeftView());
  }

  void uninstall() {
    for (final (web.EventTarget target, String type, JSFunction js)
        in _listeners) {
      target.removeEventListener(type, js, true.toJS);
    }
    _listeners.clear();
  }
}

/// Web implementation: installs capture-phase DOM listeners that suppress the
/// browser's middle-click defaults inside Flutter views (when
/// [preventDefaults] is true) and report the mouse leaving a Flutter view or
/// the window losing focus through [onPointerLeftView].
Object? installBrowserGuard({
  required bool preventDefaults,
  required void Function() onPointerLeftView,
}) {
  final _BrowserGuard guard = _BrowserGuard(preventDefaults, onPointerLeftView)
    ..install();
  return guard;
}

/// Removes the listeners added by [installBrowserGuard].
void uninstallBrowserGuard(Object? handle) {
  if (handle is _BrowserGuard) {
    handle.uninstall();
  }
}
