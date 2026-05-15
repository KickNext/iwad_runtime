import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/gestures.dart';

import 'controller.dart';
import 'desktop_controls.dart';
import 'input_key.dart';
import 'exceptions.dart';
import 'fullscreen_controller.dart';

const double _defaultMouseSensitivity = 14;

/// High-level widget that starts an IWAD runtime and renders it.
final class IwadScreen extends StatefulWidget {
  /// Creates a screen that starts from [iwadPath], [iwadBytes], or a controller.
  const IwadScreen({
    super.key,
    this.controller,
    this.iwadPath,
    this.iwadBytes,
    this.iwadFileName = 'iwad.wad',
    this.backgroundColor = Colors.black,
    this.showMobileControls = true,
    this.mouseSensitivity = _defaultMouseSensitivity,
    this.maxMouseDeltaPerTick = IwadController.defaultMaxMouseDeltaPerTick,
    this.touchLookSensitivity = 36,
    this.desktopControlScheme = IwadDesktopControlScheme.modern,
    this.showDesktopControls = true,
    this.desktopFullscreen = false,
    this.fit = BoxFit.contain,
    this.loading,
    this.errorBuilder,
    this.onDesktopControlSchemeChanged,
    this.fullscreenController,
    this.onFullscreenToggle,
    this.onExitRequested,
  });

  /// Optional controller to use instead of creating one internally.
  final IwadController? controller;

  /// Path to an IWAD file to start automatically.
  final String? iwadPath;

  /// IWAD bytes to start automatically.
  final Uint8List? iwadBytes;

  /// File name used for byte-backed IWAD identity and save scoping.
  final String iwadFileName;

  /// Background color behind the rendered engine frame.
  final Color backgroundColor;

  /// Whether touch controls are shown on mobile-sized layouts.
  final bool showMobileControls;

  /// Multiplier applied to desktop mouse movement.
  final double mouseSensitivity;

  /// Maximum accumulated mouse delta sent per engine tick.
  final double maxMouseDeltaPerTick;

  /// Multiplier applied to touch-look movement.
  final double touchLookSensitivity;

  /// Keyboard control layout used for desktop input.
  final IwadDesktopControlScheme desktopControlScheme;

  /// Whether desktop overlay controls are shown.
  final bool showDesktopControls;

  /// Initial desktop fullscreen state.
  final bool desktopFullscreen;

  /// How the engine framebuffer fits inside the widget bounds.
  final BoxFit fit;

  /// Widget displayed before the first frame is available.
  final Widget? loading;

  /// Builds an error widget when startup fails.
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  /// Called when the desktop control scheme is toggled.
  final ValueChanged<IwadDesktopControlScheme>? onDesktopControlSchemeChanged;

  /// Platform fullscreen adapter used by the fullscreen shortcut/control.
  final IwadFullscreenController? fullscreenController;

  /// Called when fullscreen is requested without a fullscreen controller.
  final VoidCallback? onFullscreenToggle;

  /// Called once when the engine reports a quit request.
  final VoidCallback? onExitRequested;

  @override
  State<IwadScreen> createState() => _IwadScreenState();
}

final class _IwadScreenState extends State<IwadScreen> {
  late final IwadController _controller;
  late final bool _ownsController;
  Object? _startError;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? IwadController();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      if (_controller.isStarted) {
        return;
      }
      final Uint8List? iwadBytes = widget.iwadBytes;
      final String? iwadPath = widget.iwadPath;
      if (iwadBytes != null) {
        await _controller.startBytes(iwadBytes, fileName: widget.iwadFileName);
      } else if (iwadPath != null && iwadPath.trim().isNotEmpty) {
        await _controller.start(iwadPath);
      } else {
        throw const IwadRuntimeException(
          'IWAD is required. Pass iwadPath, iwadBytes, or start the controller before building IwadScreen.',
        );
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _startError = error);
      }
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Object? error = _startError;
    return IwadView(
      controller: _controller,
      fit: widget.fit,
      backgroundColor: widget.backgroundColor,
      showMobileControls: widget.showMobileControls,
      mouseSensitivity: widget.mouseSensitivity,
      maxMouseDeltaPerTick: widget.maxMouseDeltaPerTick,
      touchLookSensitivity: widget.touchLookSensitivity,
      desktopControlScheme: widget.desktopControlScheme,
      showDesktopControls: widget.showDesktopControls,
      desktopFullscreen: widget.desktopFullscreen,
      onDesktopControlSchemeChanged: widget.onDesktopControlSchemeChanged,
      fullscreenController: widget.fullscreenController,
      onFullscreenToggle: widget.onFullscreenToggle,
      onExitRequested: widget.onExitRequested,
      placeholder: error == null
          ? widget.loading ??
                const SizedBox.square(
                  dimension: 32,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
          : widget.errorBuilder?.call(context, error) ??
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
    );
  }
}

/// Renders an already configured [IwadController].
final class IwadView extends StatefulWidget {
  /// Creates a runtime view for [controller].
  const IwadView({
    required this.controller,
    super.key,
    this.autofocus = true,
    this.fit = BoxFit.contain,
    this.backgroundColor = Colors.black,
    this.placeholder,
    this.showMobileControls = true,
    this.mouseSensitivity = _defaultMouseSensitivity,
    this.maxMouseDeltaPerTick = IwadController.defaultMaxMouseDeltaPerTick,
    this.touchLookSensitivity = 36,
    this.desktopControlScheme = IwadDesktopControlScheme.modern,
    this.showDesktopControls = true,
    this.desktopFullscreen = false,
    this.captureMouse = true,
    this.onDesktopControlSchemeChanged,
    this.fullscreenController,
    this.onFullscreenToggle,
    this.onExitRequested,
  });

  /// Controller that owns the runtime session.
  final IwadController controller;

  /// Whether the view requests keyboard focus when built.
  final bool autofocus;

  /// How the engine framebuffer fits inside the widget bounds.
  final BoxFit fit;

  /// Background color behind the rendered engine frame.
  final Color backgroundColor;

  /// Widget displayed before the first frame is available.
  final Widget? placeholder;

  /// Whether touch controls are shown on mobile-sized layouts.
  final bool showMobileControls;

  /// Multiplier applied to desktop mouse movement.
  final double mouseSensitivity;

  /// Maximum accumulated mouse delta sent per engine tick.
  final double maxMouseDeltaPerTick;

  /// Multiplier applied to touch-look movement.
  final double touchLookSensitivity;

  /// Keyboard control layout used for desktop input.
  final IwadDesktopControlScheme desktopControlScheme;

  /// Whether desktop overlay controls are shown.
  final bool showDesktopControls;

  /// Initial desktop fullscreen state.
  final bool desktopFullscreen;

  /// Whether the view should request mouse capture after desktop clicks.
  final bool captureMouse;

  /// Called when the desktop control scheme is toggled.
  final ValueChanged<IwadDesktopControlScheme>? onDesktopControlSchemeChanged;

  /// Platform fullscreen adapter used by the fullscreen shortcut/control.
  final IwadFullscreenController? fullscreenController;

  /// Called when fullscreen is requested without a fullscreen controller.
  final VoidCallback? onFullscreenToggle;

  /// Called once when the engine reports a quit request.
  final VoidCallback? onExitRequested;

  @override
  State<IwadView> createState() => _IwadViewState();
}

final class _IwadViewState extends State<IwadView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const Duration _minimumMouseActionHold = Duration(milliseconds: 70);

  late final FocusNode _focusNode;
  late final Ticker _ticker;
  final Map<int, DateTime> _mouseActionPressedAt = <int, DateTime>{};
  final Map<int, Timer> _mouseActionReleaseTimers = <int, Timer>{};
  int _activeMouseButtons = 0;
  bool _mouseCaptured = false;
  bool _mouseInside = false;
  late bool _fullscreenEnabled;
  bool _tickInFlight = false;
  bool _exitNotified = false;
  bool _suspended = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focusNode = FocusNode(debugLabel: 'iwad_runtime');
    _fullscreenEnabled = widget.desktopFullscreen;
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(IwadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.desktopFullscreen != oldWidget.desktopFullscreen) {
      _fullscreenEnabled = widget.desktopFullscreen;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setFullscreenEnabled(false);
    _cancelMouseActionReleaseTimers();
    widget.controller.setSuspended(false);
    widget.controller.releaseInput();
    _mouseCaptured = false;
    _ticker.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool shouldSuspend = switch (state) {
      AppLifecycleState.resumed => false,
      AppLifecycleState.inactive ||
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached => true,
    };
    _setSuspended(shouldSuspend);
  }

  void _onTick(Duration elapsed) {
    if (_exitNotified || _suspended) {
      return;
    }
    if (_mouseCaptured && widget.controller.usesPolledMouseCapture) {
      widget.controller.pollMouseDelta(
        sensitivity: widget.mouseSensitivity,
        includeVerticalMovement: _shouldShowMobileControls(context),
        maxMouseDeltaPerTick: widget.maxMouseDeltaPerTick,
      );
    }
    unawaited(_tickAndHandleExit());
  }

  Future<void> _tickAndHandleExit() async {
    if (_tickInFlight || _suspended) {
      return;
    }
    _tickInFlight = true;
    try {
      await widget.controller.tick();
    } finally {
      _tickInFlight = false;
    }
    if (!mounted || _exitNotified || !widget.controller.hasQuit) {
      return;
    }
    _exitNotified = true;
    _setFullscreenEnabled(false);
    widget.onExitRequested?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (bool hasFocus) {
        if (!hasFocus && !_shouldKeepPointerStateForMouseCapture()) {
          _releasePointerState();
        }
      },
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (!_shouldShowMobileControls(context) && _isFullscreenHotkey(event)) {
          if (event is KeyDownEvent) {
            _toggleFullscreen();
          }
          return KeyEventResult.handled;
        }
        if (!_shouldShowMobileControls(context) &&
            !widget.controller.isSaveNameActive &&
            _isControlSchemeHotkey(event)) {
          if (event is KeyDownEvent) {
            final IwadDesktopControlScheme nextScheme =
                widget.desktopControlScheme == IwadDesktopControlScheme.modern
                ? IwadDesktopControlScheme.original
                : IwadDesktopControlScheme.modern;
            widget.onDesktopControlSchemeChanged?.call(nextScheme);
          }
          return KeyEventResult.handled;
        }
        final int? key = widget.controller.isSaveNameActive
            ? IwadInputKey.fromSaveNameKeyEvent(event)
            : IwadInputKey.fromLogicalKey(
                event.logicalKey,
                desktopControlScheme: widget.desktopControlScheme,
              );
        if (key == null) {
          return KeyEventResult.ignored;
        }
        if (event is KeyDownEvent) {
          widget.controller.setKeyPressed(key, true);
        } else if (event is KeyUpEvent) {
          widget.controller.setKeyPressed(key, false);
        }
        return KeyEventResult.handled;
      },
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Size viewSize = constraints.biggest;
          final double frameScale = _frameScaleForSize(viewSize);
          return MouseRegion(
            cursor: _mouseCaptured
                ? SystemMouseCursors.none
                : SystemMouseCursors.basic,
            onEnter: (PointerEnterEvent event) {
              if (_isMousePointer(event.kind)) {
                _mouseInside = true;
              }
            },
            onExit: (PointerExitEvent event) {
              if (_isMousePointer(event.kind)) {
                if (_shouldKeepPointerStateForMouseCapture()) {
                  _mouseInside = true;
                  return;
                }
                _mouseInside = false;
                _releasePointerState();
              }
            },
            child: Listener(
              onPointerDown: (PointerDownEvent event) {
                if (!_isMousePointer(event.kind)) {
                  return;
                }
                _mouseInside = true;
                _focusNode.requestFocus();
                _setMouseCaptured(true);
                final int? buttonIndex = _buttonIndex(event.buttons);
                if (buttonIndex != null) {
                  _activeMouseButtons |= 1 << buttonIndex;
                  _setMouseActionButton(buttonIndex, true);
                }
              },
              onPointerUp: (PointerUpEvent event) {
                if (!_isMousePointer(event.kind)) {
                  return;
                }
                for (var i = 0; i < 3; i++) {
                  final int mask = 1 << i;
                  if ((_activeMouseButtons & mask) != 0 &&
                      (event.buttons & mask) == 0) {
                    _setMouseActionButton(i, false);
                  }
                }
                _activeMouseButtons = event.buttons & 0x7;
              },
              onPointerCancel: (_) {
                _releasePointerState();
              },
              onPointerHover: (PointerHoverEvent event) {
                if (_isMousePointer(event.kind) &&
                    (_mouseInside || widget.controller.isMouseCaptureActive) &&
                    _shouldUseFlutterMouseDeltas()) {
                  _addMouseDelta(event.delta, frameScale);
                }
              },
              onPointerMove: (PointerMoveEvent event) {
                if (_isMousePointer(event.kind) &&
                    (_mouseInside || widget.controller.isMouseCaptureActive) &&
                    _shouldUseFlutterMouseDeltas()) {
                  _addMouseDelta(event.delta, frameScale);
                }
              },
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (BuildContext context, Widget? child) {
                  final ui.Image? image = widget.controller.image;
                  final Widget frame = image == null
                      ? Center(child: _placeholderForController(context))
                      : CustomPaint(
                          painter: _IwadFramePainter(
                            image: image,
                            fit: widget.fit,
                          ),
                          child: const SizedBox.expand(),
                        );

                  return ColoredBox(
                    color: widget.backgroundColor,
                    child: Stack(
                      children: [
                        Positioned.fill(child: frame),
                        if (widget.showMobileControls &&
                            _shouldShowMobileControls(context) &&
                            widget.controller.isGameplayActive &&
                            !widget.controller.isPlayerDead &&
                            !widget.controller.isMenuActive)
                          _TouchLookArea(
                            controller: widget.controller,
                            sensitivity: widget.touchLookSensitivity,
                            viewScale: _touchLookScaleForSize(viewSize),
                            onTouchStarted: _focusNode.requestFocus,
                          ),
                        if (widget.showMobileControls &&
                            _shouldShowMobileControls(context) &&
                            widget.controller.isMenuActive &&
                            !widget.controller.isSaveNameActive)
                          _MenuGestureArea(controller: widget.controller),
                        if (widget.showMobileControls &&
                            _shouldShowMobileControls(context) &&
                            widget.controller.isAdvanceActive)
                          _AdvanceTapArea(controller: widget.controller),
                        if (widget.showMobileControls &&
                            _shouldShowMobileControls(context) &&
                            widget.controller.isGameplayActive &&
                            widget.controller.isPlayerDead &&
                            !widget.controller.isMenuActive)
                          _DeathTapArea(controller: widget.controller),
                        if (widget.showMobileControls &&
                            _shouldShowMobileControls(context) &&
                            widget.controller.isStarted &&
                            !widget.controller.isGameplayActive &&
                            !widget.controller.isAdvanceActive &&
                            !widget.controller.isMenuActive)
                          _IdleTapToMenuArea(controller: widget.controller),
                        if (widget.showMobileControls &&
                            _shouldShowMobileControls(context))
                          _MobileControls(controller: widget.controller),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  bool _isMousePointer(ui.PointerDeviceKind kind) {
    return kind == ui.PointerDeviceKind.mouse;
  }

  bool _isFullscreenHotkey(KeyEvent event) {
    return event.logicalKey == LogicalKeyboardKey.f11;
  }

  bool _isControlSchemeHotkey(KeyEvent event) {
    return event.logicalKey == LogicalKeyboardKey.f12 ||
        event.logicalKey == LogicalKeyboardKey.keyM;
  }

  void _toggleFullscreen() {
    final IwadFullscreenController? controller = widget.fullscreenController;
    if (controller == null) {
      widget.onFullscreenToggle?.call();
      return;
    }
    _setFullscreenEnabled(!_fullscreenEnabled);
  }

  void _setFullscreenEnabled(bool enabled) {
    final IwadFullscreenController? controller = widget.fullscreenController;
    if (controller == null || _fullscreenEnabled == enabled) {
      return;
    }
    _fullscreenEnabled = enabled;
    unawaited(
      Future<void>.sync(() => controller.setFullscreen(enabled)).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'iwad_runtime',
            context: ErrorDescription('while changing fullscreen state'),
          ),
        );
      }),
    );
  }

  void _addMouseDelta(Offset delta, double frameScale) {
    widget.controller.addMouseDelta(
      delta.dx,
      delta.dy,
      sensitivity: widget.mouseSensitivity,
      viewScale: frameScale,
      includeVerticalMovement: _shouldShowMobileControls(context),
      maxMouseDeltaPerTick: widget.maxMouseDeltaPerTick,
    );
  }

  bool _shouldUseFlutterMouseDeltas() {
    return !widget.controller.usesPolledMouseCapture ||
        !widget.controller.isMouseCaptureActive;
  }

  bool _shouldKeepPointerStateForMouseCapture() {
    return widget.controller.isMouseCaptureActive ||
        (widget.controller.usesPolledMouseCapture && _mouseCaptured);
  }

  void _setMouseActionButton(int buttonIndex, bool pressed) {
    final int? inputKey = _inputKeyForMouseButton(buttonIndex);
    if (inputKey == null) {
      widget.controller.setMouseButton(buttonIndex, pressed);
      return;
    }
    if (pressed) {
      _mouseActionReleaseTimers.remove(inputKey)?.cancel();
      _mouseActionPressedAt[inputKey] = DateTime.now();
      widget.controller.setKeyPressed(inputKey, true);
      return;
    }
    _releaseMouseActionButton(inputKey);
  }

  int? _inputKeyForMouseButton(int buttonIndex) {
    return switch (buttonIndex) {
      0 => IwadInputKey.fire,
      1 => IwadInputKey.use,
      _ => null,
    };
  }

  void _releaseMouseActionButton(int inputKey) {
    final DateTime? pressedAt = _mouseActionPressedAt[inputKey];
    if (pressedAt == null) {
      widget.controller.setKeyPressed(inputKey, false);
      return;
    }
    final Duration elapsed = DateTime.now().difference(pressedAt);
    final Duration remaining = _minimumMouseActionHold - elapsed;
    if (remaining <= Duration.zero) {
      _releaseMouseActionButtonNow(inputKey);
      return;
    }
    _mouseActionReleaseTimers[inputKey]?.cancel();
    _mouseActionReleaseTimers[inputKey] = Timer(remaining, () {
      _mouseActionReleaseTimers.remove(inputKey);
      _releaseMouseActionButtonNow(inputKey);
    });
  }

  void _releaseMouseActionButtonNow(int inputKey) {
    _mouseActionPressedAt.remove(inputKey);
    widget.controller.setKeyPressed(inputKey, false);
  }

  void _cancelMouseActionReleaseTimers() {
    for (final Timer timer in _mouseActionReleaseTimers.values) {
      timer.cancel();
    }
    _mouseActionReleaseTimers.clear();
    _mouseActionPressedAt.clear();
  }

  void _setMouseCaptured(bool captured) {
    if (!widget.captureMouse || _shouldShowMobileControls(context)) {
      captured = false;
    }
    if (_mouseCaptured == captured) {
      return;
    }
    final bool applied = widget.controller.setMouseCapture(captured);
    if (mounted) {
      setState(() => _mouseCaptured = applied && captured);
    } else {
      _mouseCaptured = applied && captured;
    }
  }

  void _setSuspended(bool suspended) {
    if (_suspended == suspended) {
      return;
    }
    _suspended = suspended;
    if (suspended) {
      _releasePointerState();
    }
    widget.controller.setSuspended(suspended);
  }

  void _releasePointerState() {
    _activeMouseButtons = 0;
    _cancelMouseActionReleaseTimers();
    _mouseInside = false;
    _setMouseCaptured(false);
    widget.controller.releaseInput();
  }

  double _frameScaleForSize(Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return 1;
    }
    final FittedSizes sizes = applyBoxFit(
      widget.fit,
      Size(
        widget.controller.width.toDouble(),
        widget.controller.height.toDouble(),
      ),
      size,
    );
    if (sizes.source.width <= 0 || sizes.source.height <= 0) {
      return 1;
    }
    final double scaleX = sizes.destination.width / sizes.source.width;
    final double scaleY = sizes.destination.height / sizes.source.height;
    final double scale = (scaleX + scaleY) / 2;
    return scale <= 0 ? 1 : scale;
  }

  double _touchLookScaleForSize(Size size) {
    if (size.shortestSide <= 0) {
      return 1;
    }
    final double scale = size.shortestSide / 480;
    return scale.clamp(1, 1.3).toDouble();
  }

  int? _buttonIndex(int buttons) {
    if ((buttons & kPrimaryMouseButton) != 0) {
      return 0;
    }
    if ((buttons & kSecondaryMouseButton) != 0) {
      return 1;
    }
    if ((buttons & kMiddleMouseButton) != 0) {
      return 2;
    }
    return null;
  }

  bool _shouldShowMobileControls(BuildContext context) {
    final TargetPlatform platform = Theme.of(context).platform;
    return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  }

  Widget _placeholderForController(BuildContext context) {
    final String? error = widget.controller.error;
    if (error == null || error.isEmpty) {
      return widget.placeholder ?? const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        error,
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

final class _IwadFramePainter extends CustomPainter {
  const _IwadFramePainter({required this.image, required this.fit});

  final ui.Image image;
  final BoxFit fit;

  @override
  void paint(Canvas canvas, Size size) {
    final FittedSizes sizes = applyBoxFit(
      fit,
      Size(image.width.toDouble(), image.height.toDouble()),
      size,
    );
    final Rect input = Alignment.center.inscribe(
      sizes.source,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
    );
    final Rect output = Alignment.center.inscribe(
      sizes.destination,
      Offset.zero & size,
    );
    canvas.drawImageRect(image, input, output, Paint());
  }

  @override
  bool shouldRepaint(_IwadFramePainter oldDelegate) {
    return image != oldDelegate.image || fit != oldDelegate.fit;
  }
}

final class _MobileControls extends StatelessWidget {
  const _MobileControls({required this.controller});

  final IwadController controller;

  @override
  Widget build(BuildContext context) {
    final bool gameplayActive = controller.isGameplayActive;
    final bool playerDead = controller.isPlayerDead;
    final bool menuActive = controller.isMenuActive;
    final bool effectiveGameplayActive =
        gameplayActive && !playerDead && !menuActive;
    final bool deathActive = gameplayActive && playerDead && !menuActive;
    final bool menuPromptActive = menuActive && controller.isMenuPromptActive;
    final bool saveNameActive = menuActive && controller.isSaveNameActive;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Stack(
              children: [
                if (effectiveGameplayActive || menuActive)
                  Align(
                    alignment: Alignment.topLeft,
                    child: _SystemButtonColumn(
                      controller: controller,
                      gameplayActive: effectiveGameplayActive,
                      menuActive: menuActive,
                    ),
                  ),
                if (effectiveGameplayActive)
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Transform.translate(
                      offset: const Offset(16, -16),
                      child: _MoveControlCluster(controller: controller),
                    ),
                  ),
                if (menuActive && !saveNameActive)
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Transform.translate(
                      offset: const Offset(10, -10),
                      child: _MenuDpad(controller: controller),
                    ),
                  ),
                if (effectiveGameplayActive)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Transform.translate(
                      offset: const Offset(-16, -16),
                      child: _ActionButtonCluster(controller: controller),
                    ),
                  ),
                if (effectiveGameplayActive)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Transform.translate(
                      offset: const Offset(-16, -230),
                      child: _WeaponGestureSwitch(controller: controller),
                    ),
                  ),
                if (deathActive)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Transform.translate(
                      offset: const Offset(-16, -106),
                      child: _DeathActionCluster(controller: controller),
                    ),
                  ),
                if (menuActive && !saveNameActive)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Transform.translate(
                      offset: const Offset(-16, -16),
                      child: _MenuActionCluster(
                        controller: controller,
                        menuPromptActive: menuPromptActive,
                      ),
                    ),
                  ),
                if (saveNameActive)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: _SaveNameKeyboard(controller: controller),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _MoveControlCluster extends StatelessWidget {
  const _MoveControlCluster({required this.controller});

  final IwadController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 244,
      height: 228,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            bottom: 0,
            child: _MoveStick(controller: controller),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: _RunToggleButton(controller: controller),
          ),
        ],
      ),
    );
  }
}

final class _RunToggleButton extends StatefulWidget {
  const _RunToggleButton({required this.controller});

  final IwadController controller;

  @override
  State<_RunToggleButton> createState() => _RunToggleButtonState();
}

final class _RunToggleButtonState extends State<_RunToggleButton> {
  bool _active = false;

  @override
  void dispose() {
    if (_active) {
      widget.controller.setKeyPressed(IwadInputKey.shift, false);
    }
    super.dispose();
  }

  void _toggle() {
    setState(() => _active = !_active);
    widget.controller.setKeyPressed(IwadInputKey.shift, _active);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey<String>('iwad_runtime_run_button'),
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 90),
        scale: _active ? 0.96 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _active
                ? const Color(0xffd6a15c).withValues(alpha: 0.34)
                : Colors.black.withValues(alpha: 0.30),
            shape: BoxShape.circle,
            border: Border.all(
              color: _active
                  ? const Color(0xffffddb0).withValues(alpha: 0.62)
                  : Colors.white.withValues(alpha: 0.18),
              width: _active ? 2 : 1,
            ),
          ),
          child: SizedBox.square(
            dimension: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_active)
                  Positioned(
                    key: const ValueKey<String>(
                      'iwad_runtime_run_button_active',
                    ),
                    right: 8,
                    top: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xffffddb0),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const SizedBox.square(dimension: 7),
                    ),
                  ),
                const Text(
                  'RUN',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _SystemButtonColumn extends StatelessWidget {
  const _SystemButtonColumn({
    required this.controller,
    required this.gameplayActive,
    required this.menuActive,
  });

  final IwadController controller;
  final bool gameplayActive;
  final bool menuActive;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _InputPadButton(
          icon: menuActive ? Icons.close : Icons.pause,
          size: 46,
          onChanged: (bool pressed) {
            if (!pressed) {
              return;
            }
            unawaited(controller.tapKey(IwadInputKey.escape));
          },
        ),
        if (gameplayActive) ...[
          const SizedBox(height: 12),
          _InputPadButton(
            icon: Icons.map_outlined,
            size: 46,
            onChanged: (bool pressed) {
              if (!pressed) {
                return;
              }
              unawaited(controller.tapKey(IwadInputKey.tab));
            },
          ),
        ],
      ],
    );
  }
}

final class _IdleTapToMenuArea extends StatelessWidget {
  const _IdleTapToMenuArea({required this.controller});

  final IwadController controller;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        key: const ValueKey<String>('iwad_runtime_idle_tap_to_menu_area'),
        behavior: HitTestBehavior.translucent,
        onTap: () => unawaited(controller.tapKey(IwadInputKey.escape)),
      ),
    );
  }
}

final class _AdvanceTapArea extends StatelessWidget {
  const _AdvanceTapArea({required this.controller});

  final IwadController controller;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        key: const ValueKey<String>('iwad_runtime_advance_tap_area'),
        behavior: HitTestBehavior.translucent,
        onTap: () => unawaited(controller.tapKey(IwadInputKey.fire)),
      ),
    );
  }
}

final class _DeathTapArea extends StatelessWidget {
  const _DeathTapArea({required this.controller});

  final IwadController controller;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        key: const ValueKey<String>('iwad_runtime_death_tap_area'),
        behavior: HitTestBehavior.translucent,
        onTap: () => unawaited(controller.tapKey(IwadInputKey.use)),
      ),
    );
  }
}

final class _MenuGestureArea extends StatefulWidget {
  const _MenuGestureArea({required this.controller});

  final IwadController controller;

  @override
  State<_MenuGestureArea> createState() => _MenuGestureAreaState();
}

final class _MenuGestureAreaState extends State<_MenuGestureArea> {
  static const double _swipeThreshold = 42;

  Offset _dragDelta = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => _dragDelta = Offset.zero,
        onPanUpdate: (DragUpdateDetails details) {
          _dragDelta += details.delta;
        },
        onPanEnd: (_) {
          final Offset delta = _dragDelta;
          _dragDelta = Offset.zero;
          if (delta.distance < _swipeThreshold) {
            return;
          }
          final int key = delta.dx.abs() > delta.dy.abs()
              ? (delta.dx > 0 ? IwadInputKey.right : IwadInputKey.left)
              : (delta.dy > 0 ? IwadInputKey.down : IwadInputKey.up);
          unawaited(widget.controller.tapKey(key));
        },
        onPanCancel: () => _dragDelta = Offset.zero,
        onTapUp: (TapUpDetails details) {
          final RenderBox box = context.findRenderObject()! as RenderBox;
          final Offset local = box.globalToLocal(details.globalPosition);
          if (local.dx > box.size.width * 0.52) {
            unawaited(widget.controller.tapKey(IwadInputKey.enter));
          }
        },
      ),
    );
  }
}

final class _MenuDpad extends StatelessWidget {
  const _MenuDpad({required this.controller});

  final IwadController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      key: const ValueKey<String>('iwad_runtime_menu_dpad'),
      dimension: 158,
      child: Stack(
        alignment: Alignment.center,
        children: [
          DecoratedBox(
            key: const ValueKey<String>('iwad_runtime_menu_dpad_cross'),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.30),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: SizedBox(
              width: 54,
              height: 154,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.30),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: SizedBox(
              width: 154,
              height: 54,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const SizedBox.square(dimension: 54),
          ),
          Positioned(
            top: 0,
            child: _MenuCrossButton(
              key: const ValueKey<String>('iwad_runtime_menu_dpad_up'),
              icon: Icons.keyboard_arrow_up,
              onChanged: (bool pressed) =>
                  controller.setKeyPressed(IwadInputKey.up, pressed),
            ),
          ),
          Positioned(
            left: 0,
            child: _MenuCrossButton(
              key: const ValueKey<String>('iwad_runtime_menu_dpad_left'),
              icon: Icons.keyboard_arrow_left,
              onChanged: (bool pressed) =>
                  controller.setKeyPressed(IwadInputKey.left, pressed),
            ),
          ),
          Positioned(
            right: 0,
            child: _MenuCrossButton(
              key: const ValueKey<String>('iwad_runtime_menu_dpad_right'),
              icon: Icons.keyboard_arrow_right,
              onChanged: (bool pressed) =>
                  controller.setKeyPressed(IwadInputKey.right, pressed),
            ),
          ),
          Positioned(
            bottom: 0,
            child: _MenuCrossButton(
              key: const ValueKey<String>('iwad_runtime_menu_dpad_down'),
              icon: Icons.keyboard_arrow_down,
              onChanged: (bool pressed) =>
                  controller.setKeyPressed(IwadInputKey.down, pressed),
            ),
          ),
        ],
      ),
    );
  }
}

final class _MenuCrossButton extends StatelessWidget {
  const _MenuCrossButton({
    super.key,
    required this.icon,
    required this.onChanged,
  });

  final IconData icon;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => onChanged(true),
      onTapUp: (_) => onChanged(false),
      onTapCancel: () => onChanged(false),
      child: SizedBox.square(
        dimension: 58,
        child: Center(
          child: Icon(
            icon,
            color: Colors.white.withValues(alpha: 0.74),
            size: 34,
          ),
        ),
      ),
    );
  }
}

final class _MenuActionCluster extends StatelessWidget {
  const _MenuActionCluster({
    required this.controller,
    required this.menuPromptActive,
  });

  final IwadController controller;
  final bool menuPromptActive;

  @override
  Widget build(BuildContext context) {
    if (menuPromptActive) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _InputPadButton(
            label: 'N',
            size: 58,
            onChanged: (bool pressed) =>
                controller.setKeyPressed(IwadInputKey.n, pressed),
          ),
          const SizedBox(width: 12),
          _InputPadButton(
            label: 'Y',
            size: 58,
            onChanged: (bool pressed) =>
                controller.setKeyPressed(IwadInputKey.y, pressed),
          ),
        ],
      );
    }

    return _InputPadButton(
      label: 'ENTER',
      size: 58,
      labelScale: 0.22,
      onChanged: (bool pressed) =>
          controller.setKeyPressed(IwadInputKey.enter, pressed),
    );
  }
}

final class _SaveNameKeyboard extends StatelessWidget {
  const _SaveNameKeyboard({required this.controller});

  static const List<String> _topRow = <String>[
    'Q',
    'W',
    'E',
    'R',
    'T',
    'Y',
    'U',
    'I',
    'O',
    'P',
  ];
  static const List<String> _middleRow = <String>[
    'A',
    'S',
    'D',
    'F',
    'G',
    'H',
    'J',
    'K',
    'L',
  ];
  static const List<String> _bottomRow = <String>[
    'Z',
    'X',
    'C',
    'V',
    'B',
    'N',
    'M',
  ];

  final IwadController controller;

  void _tapAscii(String label) {
    unawaited(controller.tapKey(label.toLowerCase().codeUnitAt(0)));
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 740),
      child: DecoratedBox(
        key: const ValueKey<String>('iwad_runtime_save_name_keyboard'),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.48),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SaveNameKeyboardRow(labels: _topRow, onPressed: _tapAscii),
              const SizedBox(height: 6),
              _SaveNameKeyboardRow(labels: _middleRow, onPressed: _tapAscii),
              const SizedBox(height: 6),
              _SaveNameKeyboardRow(labels: _bottomRow, onPressed: _tapAscii),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SaveNameCommandButton(
                    key: const ValueKey<String>('iwad_runtime_save_key_cancel'),
                    label: 'CANCEL',
                    onPressed: () =>
                        unawaited(controller.tapKey(IwadInputKey.escape)),
                  ),
                  const SizedBox(width: 8),
                  _SaveNameCommandButton(
                    key: const ValueKey<String>('iwad_runtime_save_key_space'),
                    label: 'SPACE',
                    width: 142,
                    onPressed: () => unawaited(controller.tapKey(32)),
                  ),
                  const SizedBox(width: 8),
                  _SaveNameCommandButton(
                    key: const ValueKey<String>(
                      'iwad_runtime_save_key_backspace',
                    ),
                    label: 'DEL',
                    onPressed: () =>
                        unawaited(controller.tapKey(IwadInputKey.backspace)),
                  ),
                  const SizedBox(width: 8),
                  _SaveNameCommandButton(
                    key: const ValueKey<String>('iwad_runtime_save_key_ok'),
                    label: 'OK',
                    onPressed: () =>
                        unawaited(controller.tapKey(IwadInputKey.enter)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _SaveNameKeyboardRow extends StatelessWidget {
  const _SaveNameKeyboardRow({required this.labels, required this.onPressed});

  final List<String> labels;
  final ValueChanged<String> onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final String label in labels) ...[
          _SaveNameKeyButton(
            key: ValueKey<String>('iwad_runtime_save_key_$label'),
            label: label,
            onPressed: () => onPressed(label),
          ),
          if (label != labels.last) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

final class _SaveNameKeyButton extends StatelessWidget {
  const _SaveNameKeyButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _SaveNameCommandButton(
      label: label,
      width: 52,
      onPressed: onPressed,
    );
  }
}

final class _SaveNameCommandButton extends StatelessWidget {
  const _SaveNameCommandButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.width = 76,
  });

  final String label;
  final VoidCallback onPressed;
  final double width;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.50),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
        ),
        child: SizedBox(
          width: width,
          height: 38,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _ActionButtonCluster extends StatelessWidget {
  const _ActionButtonCluster({required this.controller});

  final IwadController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 178,
      height: 182,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: 0,
            top: 0,
            child: _InputPadButton(
              label: 'B',
              size: 74,
              onChanged: (bool pressed) =>
                  controller.setKeyPressed(IwadInputKey.use, pressed),
            ),
          ),
          Positioned(
            left: 0,
            top: 44,
            child: _InputPadButton(
              label: 'A',
              size: 74,
              onChanged: (bool pressed) =>
                  controller.setKeyPressed(IwadInputKey.fire, pressed),
            ),
          ),
          Positioned(
            right: 46,
            bottom: 0,
            child: _InputPadButton(
              label: 'ENTER',
              size: 54,
              labelScale: 0.22,
              onChanged: (bool pressed) =>
                  controller.setKeyPressed(IwadInputKey.enter, pressed),
            ),
          ),
        ],
      ),
    );
  }
}

final class _DeathActionCluster extends StatelessWidget {
  const _DeathActionCluster({required this.controller});

  final IwadController controller;

  @override
  Widget build(BuildContext context) {
    return _InputPadButton(
      label: 'B',
      size: 74,
      onChanged: (bool pressed) =>
          controller.setKeyPressed(IwadInputKey.use, pressed),
    );
  }
}

final class _WeaponGestureSwitch extends StatefulWidget {
  const _WeaponGestureSwitch({required this.controller});

  final IwadController controller;

  @override
  State<_WeaponGestureSwitch> createState() => _WeaponGestureSwitchState();
}

final class _WeaponGestureSwitchState extends State<_WeaponGestureSwitch> {
  static const List<_WeaponChoice> _choices = [
    _WeaponChoice(1),
    _WeaponChoice(2),
    _WeaponChoice(3),
    _WeaponChoice(4),
    _WeaponChoice(5),
    _WeaponChoice(6),
    _WeaponChoice(7),
  ];
  static const double _height = 88;
  static const double _width = 344;
  static const double _choiceSize = 42;
  static const double _hubSize = 58;
  static const Offset _hubCenter = Offset(_width - 31, _height / 2);

  int? _hoverSlot;
  bool _expanded = false;

  List<_WeaponChoice> _availableChoices() {
    final int ownedMask = widget.controller.ownedWeaponSlotsMask;
    final int currentSlot = widget.controller.currentWeaponSlot;
    if (ownedMask == 0) {
      return _choices
          .where((_WeaponChoice choice) => choice.slot == currentSlot)
          .toList(growable: false);
    }
    return _choices
        .where(
          (_WeaponChoice choice) => ownedMask & (1 << (choice.slot - 1)) != 0,
        )
        .toList(growable: false);
  }

  Map<int, Offset> _choiceCenters(List<_WeaponChoice> choices) {
    if (choices.isEmpty) {
      return const <int, Offset>{};
    }

    final Map<int, Offset> centers = <int, Offset>{};
    for (int i = 0; i < choices.length; i++) {
      centers[choices[i].slot] = Offset(
        22 + (_choiceSize / 2) + (i * 40),
        _height / 2,
      );
    }
    return centers;
  }

  int? _slotForPosition(Offset localPosition, List<_WeaponChoice> choices) {
    if (choices.isEmpty) {
      return null;
    }

    final int currentSlot = widget.controller.currentWeaponSlot;
    final bool currentAvailable = choices.any(
      (_WeaponChoice choice) => choice.slot == currentSlot,
    );
    if (currentAvailable &&
        (localPosition - _hubCenter).distance <= _hubSize * 0.75) {
      return currentSlot;
    }

    int nearestSlot = choices.first.slot;
    double nearestDistance = double.infinity;
    for (final MapEntry<int, Offset> entry in _choiceCenters(choices).entries) {
      final double distance = (localPosition - entry.value).distanceSquared;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestSlot = entry.key;
      }
    }
    return nearestSlot;
  }

  void _updateHover(Offset localPosition) {
    final List<_WeaponChoice> choices = _availableChoices();
    setState(() {
      _expanded = true;
      _hoverSlot = _slotForPosition(localPosition, choices);
    });
  }

  void _commit() {
    final int? slot = _hoverSlot;
    setState(() {
      _expanded = false;
      _hoverSlot = null;
    });
    if (slot != null) {
      widget.controller.requestWeaponSlot(slot);
    }
  }

  void _cancel() {
    setState(() {
      _expanded = false;
      _hoverSlot = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<_WeaponChoice> choices = _availableChoices();
    final int activeSlot = _hoverSlot ?? widget.controller.currentWeaponSlot;
    final Map<int, Offset> centers = _choiceCenters(choices);
    return GestureDetector(
      key: const ValueKey<String>('iwad_runtime_weapon_switcher'),
      behavior: HitTestBehavior.deferToChild,
      onTapDown: (TapDownDetails details) =>
          _updateHover(details.localPosition),
      onTapUp: (_) => _commit(),
      onTapCancel: _cancel,
      onPanStart: (DragStartDetails details) =>
          _updateHover(details.localPosition),
      onPanUpdate: (DragUpdateDetails details) =>
          _updateHover(details.localPosition),
      onPanEnd: (_) => _commit(),
      onPanCancel: _cancel,
      child: SizedBox(
        width: _width,
        height: _height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (_expanded)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: 0,
                child: _WeaponDeckPanel(activeLabel: _weaponLabel(activeSlot)),
              ),
            if (_expanded)
              for (final _WeaponChoice choice in choices)
                Positioned(
                  left: centers[choice.slot]!.dx - (_choiceSize / 2),
                  top: centers[choice.slot]!.dy - (_choiceSize / 2),
                  child: _WeaponDeckChoice(
                    key: ValueKey<String>(
                      'iwad_runtime_weapon_slot_${choice.slot}',
                    ),
                    slot: choice.slot,
                    label: _weaponShortLabel(choice.slot),
                    active: choice.slot == activeSlot,
                  ),
                ),
            Positioned(
              left: _hubCenter.dx - (_hubSize / 2),
              top: _hubCenter.dy - (_hubSize / 2),
              child: _WeaponCurrentSlot(
                key: const ValueKey<String>('iwad_runtime_weapon_current_slot'),
                slot: widget.controller.currentWeaponSlot,
                label: _weaponShortLabel(widget.controller.currentWeaponSlot),
                expanded: _expanded,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _WeaponChoice {
  const _WeaponChoice(this.slot);

  final int slot;
}

String _weaponLabel(int slot) {
  return switch (slot) {
    1 => 'FIST',
    2 => 'PISTOL',
    3 => 'SHOTGUN',
    4 => 'CHAINGUN',
    5 => 'ROCKET',
    6 => 'PLASMA',
    7 => 'BFG',
    _ => 'WEAPON',
  };
}

String _weaponShortLabel(int slot) {
  return switch (slot) {
    1 => 'FST',
    2 => 'PST',
    3 => 'SG',
    4 => 'CG',
    5 => 'RKT',
    6 => 'PLS',
    7 => 'BFG',
    _ => 'WPN',
  };
}

final class _WeaponDeckPanel extends StatelessWidget {
  const _WeaponDeckPanel({required this.activeLabel});

  final String activeLabel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey<String>('iwad_runtime_weapon_deck_panel'),
      decoration: BoxDecoration(
        color: const Color(0xff151412).withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 18,
            right: 72,
            top: 18,
            child: Divider(
              color: const Color(0xffb98955).withValues(alpha: 0.34),
              height: 1,
              thickness: 1,
            ),
          ),
          Positioned(
            left: 18,
            right: 72,
            bottom: 18,
            child: Divider(
              color: Colors.white.withValues(alpha: 0.10),
              height: 1,
              thickness: 1,
            ),
          ),
          Positioned(
            right: 66,
            top: 9,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xffd6a15c).withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: const Color(0xfff0c891).withValues(alpha: 0.34),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  activeLabel,
                  style: const TextStyle(
                    color: Color(0xffffddb0),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _WeaponCurrentSlot extends StatelessWidget {
  const _WeaponCurrentSlot({
    super.key,
    required this.slot,
    required this.label,
    required this.expanded,
  });

  final int slot;
  final String label;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final String label = slot > 0 ? '$slot' : '?';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: expanded
            ? const Color(0xff1b1b1b).withValues(alpha: 0.78)
            : Colors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: expanded
              ? const Color(0xfff0c891).withValues(alpha: 0.66)
              : Colors.white.withValues(alpha: 0.24),
          width: 2,
        ),
        boxShadow: expanded
            ? <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: SizedBox.square(
        dimension: _WeaponGestureSwitchState._hubSize,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                this.label,
                style: TextStyle(
                  color: expanded
                      ? const Color(0xffffddb0)
                      : Colors.white.withValues(alpha: 0.64),
                  fontSize: this.label.length > 2 ? 8 : 9,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _WeaponDeckChoice extends StatelessWidget {
  const _WeaponDeckChoice({
    super.key,
    required this.slot,
    required this.label,
    required this.active,
  });

  final int slot;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      curve: Curves.easeOut,
      width: _WeaponGestureSwitchState._choiceSize,
      height: _WeaponGestureSwitchState._choiceSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active
            ? const Color(0xffd6a15c).withValues(alpha: 0.40)
            : const Color(0xff050505).withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: active
              ? const Color(0xffffddb0).withValues(alpha: 0.78)
              : Colors.white.withValues(alpha: 0.24),
          width: active ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$slot',
            style: TextStyle(
              color: Colors.white,
              fontSize: active ? 16 : 15,
              fontWeight: FontWeight.w900,
              height: 1,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: active
                  ? const Color(0xffffddb0)
                  : Colors.white.withValues(alpha: 0.62),
              fontSize: label.length > 2 ? 8 : 9,
              fontWeight: FontWeight.w800,
              height: 1,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

final class _TouchLookArea extends StatelessWidget {
  const _TouchLookArea({
    required this.controller,
    required this.sensitivity,
    required this.viewScale,
    required this.onTouchStarted,
  });

  final IwadController controller;
  final double sensitivity;
  final double viewScale;
  final VoidCallback onTouchStarted;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Row(
        children: [
          const Expanded(flex: 36, child: SizedBox.expand()),
          Expanded(
            flex: 64,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => onTouchStarted(),
              onPanUpdate: (DragUpdateDetails details) {
                controller.addMouseDelta(
                  details.delta.dx,
                  0,
                  sensitivity: sensitivity,
                  viewScale: viewScale,
                  maxMouseDeltaPerTick: 0,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

final class _MoveStick extends StatefulWidget {
  const _MoveStick({required this.controller});

  final IwadController controller;

  @override
  State<_MoveStick> createState() => _MoveStickState();
}

final class _MoveStickState extends State<_MoveStick> {
  static const double _size = 172;
  static const double _knobSize = 68;
  static const double _deadZone = 0.24;
  static const double _maxInputDistance = 72;

  Offset _knobOffset = Offset.zero;
  Set<int> _activeKeys = <int>{};

  @override
  void dispose() {
    _syncKeys(<int>{});
    super.dispose();
  }

  void _handlePointer(Offset globalPosition) {
    final RenderBox box = context.findRenderObject()! as RenderBox;
    final Offset local = box.globalToLocal(globalPosition);
    final Offset center = Offset(_size / 2, _size / 2);
    final Offset raw = local - center;
    final Offset clamped = raw.distance > _maxInputDistance
        ? Offset.fromDirection(raw.direction, _maxInputDistance)
        : raw;
    final Offset normalized = clamped / _maxInputDistance;
    final Set<int> nextKeys = <int>{};

    if (normalized.dy < -_deadZone) {
      nextKeys.add(IwadInputKey.up);
    } else if (normalized.dy > _deadZone) {
      nextKeys.add(IwadInputKey.down);
    }
    if (normalized.dx < -_deadZone) {
      nextKeys.add(IwadInputKey.strafeLeft);
    } else if (normalized.dx > _deadZone) {
      nextKeys.add(IwadInputKey.strafeRight);
    }

    _syncKeys(nextKeys);
    setState(() => _knobOffset = clamped);
  }

  void _release() {
    _syncKeys(<int>{});
    setState(() => _knobOffset = Offset.zero);
  }

  void _syncKeys(Set<int> nextKeys) {
    for (final int key in _activeKeys.difference(nextKeys)) {
      widget.controller.setKeyPressed(key, false);
    }
    for (final int key in nextKeys.difference(_activeKeys)) {
      widget.controller.setKeyPressed(key, true);
    }
    _activeKeys = nextKeys;
  }

  @override
  Widget build(BuildContext context) {
    final bool active = _activeKeys.isNotEmpty;
    return GestureDetector(
      key: const ValueKey<String>('iwad_runtime_move_stick'),
      behavior: HitTestBehavior.opaque,
      onPanStart: (DragStartDetails details) =>
          _handlePointer(details.globalPosition),
      onPanUpdate: (DragUpdateDetails details) =>
          _handlePointer(details.globalPosition),
      onPanEnd: (_) => _release(),
      onPanCancel: _release,
      child: SizedBox.square(
        dimension: _size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: active ? 0.10 : 0.18),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: active ? 0.10 : 0.16),
                  width: 2,
                ),
              ),
              child: const SizedBox.expand(),
            ),
            Transform.translate(
              offset: _knobOffset,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: active ? 0.06 : 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: active ? 0.18 : 0.28),
                    width: 2,
                  ),
                ),
                child: const SizedBox.square(dimension: _knobSize),
              ),
            ),
            Positioned(
              top: 14,
              child: Icon(
                Icons.keyboard_arrow_up,
                color: Colors.white.withValues(alpha: active ? 0.28 : 0.40),
                size: 26,
              ),
            ),
            Positioned(
              bottom: 14,
              child: Icon(
                Icons.keyboard_arrow_down,
                color: Colors.white.withValues(alpha: active ? 0.28 : 0.40),
                size: 26,
              ),
            ),
            Positioned(
              left: 14,
              child: Icon(
                Icons.keyboard_arrow_left,
                color: Colors.white.withValues(alpha: active ? 0.28 : 0.40),
                size: 26,
              ),
            ),
            Positioned(
              right: 14,
              child: Icon(
                Icons.keyboard_arrow_right,
                color: Colors.white.withValues(alpha: active ? 0.28 : 0.40),
                size: 26,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _InputPadButton extends StatefulWidget {
  const _InputPadButton({
    required this.onChanged,
    this.icon,
    this.label,
    this.size = 56,
    this.labelScale = 0.36,
  }) : assert(icon != null || label != null);

  final IconData? icon;
  final String? label;
  final ValueChanged<bool> onChanged;
  final double size;
  final double labelScale;

  @override
  State<_InputPadButton> createState() => _InputPadButtonState();
}

final class _InputPadButtonState extends State<_InputPadButton> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (_pressed != pressed) {
      setState(() => _pressed = pressed);
    }
    widget.onChanged(pressed);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 70),
        scale: _pressed ? 0.94 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _pressed
                ? const Color(0xffd6a15c).withValues(alpha: 0.34)
                : Colors.black.withValues(alpha: 0.30),
            shape: BoxShape.circle,
            border: Border.all(
              color: _pressed
                  ? const Color(0xffffddb0).withValues(alpha: 0.58)
                  : Colors.white.withValues(alpha: 0.16),
              width: _pressed ? 2 : 1,
            ),
          ),
          child: SizedBox.square(
            dimension: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                widget.icon == null
                    ? Center(
                        child: Text(
                          widget.label!,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: widget.size * widget.labelScale,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                      )
                    : Icon(
                        widget.icon,
                        color: Colors.white,
                        size: widget.size * 0.56,
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
