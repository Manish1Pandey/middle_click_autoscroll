import 'package:web/web.dart' as web;

/// Publishes the demo state as `<body data-autoscroll-demo="...">` so
/// browser automation (e.g. a Chrome DevTools Protocol script) can read the
/// scroll offset and autoscroll status without OCR.
void publishDemoState(String json) {
  web.document.body?.setAttribute('data-autoscroll-demo', json);
}
