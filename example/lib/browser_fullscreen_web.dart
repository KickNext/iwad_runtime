import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<void> setBrowserFullscreen(bool enabled) async {
  if (enabled) {
    final web.Element? root = web.document.documentElement;
    if (root == null || web.document.fullscreenElement != null) {
      return;
    }
    await root.requestFullscreen().toDart;
    return;
  }
  if (web.document.fullscreenElement == null) {
    return;
  }
  await web.document.exitFullscreen().toDart;
}
