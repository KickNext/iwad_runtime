import 'dart:async';

/// Adapter used by widgets to enter or leave platform fullscreen mode.
abstract interface class IwadFullscreenController {
  /// Applies fullscreen state to the host app or browser.
  FutureOr<void> setFullscreen(bool enabled);
}

/// Fullscreen controller that delegates to a callback.
final class IwadCallbackFullscreenController
    implements IwadFullscreenController {
  /// Creates a controller backed by [onSetFullscreen].
  const IwadCallbackFullscreenController(this.onSetFullscreen);

  /// Callback invoked whenever fullscreen state should change.
  final FutureOr<void> Function(bool enabled) onSetFullscreen;

  @override
  FutureOr<void> setFullscreen(bool enabled) => onSetFullscreen(enabled);
}
