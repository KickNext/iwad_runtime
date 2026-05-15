import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'backend.dart';
import 'backend_factory.dart';
import 'exceptions.dart';

/// Drives an IWAD runtime instance and exposes frames, input, saves, and state.
final class IwadController extends ChangeNotifier {
  /// Default per-tick clamp for accumulated mouse movement.
  static const double defaultMaxMouseDeltaPerTick = 220;

  /// Creates a controller backed by the current platform implementation.
  IwadController({IwadBackend? backend})
    : _backend = backend ?? createIwadBackend() {
    _frameRgba = Uint8List(width * height * 4);
  }

  final IwadBackend _backend;
  late Uint8List _frameRgba;
  ui.Image? _image;
  bool _decoding = false;
  bool _hasQuit = false;
  String? _error;
  final Set<int> _pressedKeys = <int>{};
  int _mouseButtons = 0;
  double _mouseRemainderX = 0;
  double _mouseRemainderY = 0;
  int _pendingMouseDeltaX = 0;
  int _pendingMouseDeltaY = 0;

  /// Whether the selected backend can run on the current platform.
  bool get isSupported => _backend.isSupported;

  /// Whether a runtime session has been started.
  bool get isStarted => _backend.isStarted;

  /// Width of the current engine framebuffer in pixels.
  int get width => _backend.width;

  /// Height of the current engine framebuffer in pixels.
  int get height => _backend.height;

  /// Latest decoded frame image, or null before the first frame is available.
  ui.Image? get image => _image;

  /// Whether the engine reported that the user requested quit.
  bool get hasQuit => _hasQuit;

  /// Last runtime error message observed by the controller.
  String? get error => _error;

  /// Currently selected weapon slot reported by the engine.
  int get currentWeaponSlot => _backend.currentWeaponSlot;

  /// Bit mask of weapon slots owned by the local player.
  int get ownedWeaponSlotsMask => _backend.ownedWeaponSlotsMask;

  /// Whether the engine is currently in active gameplay.
  bool get isGameplayActive => _backend.isGameplayActive;

  /// Whether the local player is dead.
  bool get isPlayerDead => _backend.isPlayerDead;

  /// Whether the engine is waiting for an advance/intermission action.
  bool get isAdvanceActive => _backend.isAdvanceActive;

  /// Whether the in-game menu is open.
  bool get isMenuActive => _backend.isMenuActive;

  /// Whether the menu is showing a prompt that expects confirmation.
  bool get isMenuPromptActive => _backend.isMenuPromptActive;

  /// Whether the engine is editing a save-game name.
  bool get isSaveNameActive => _backend.isSaveNameActive;

  /// Whether the engine is showing a quit confirmation prompt.
  bool get isQuitConfirmActive => _backend.isQuitConfirmActive;

  /// Starts the runtime from an IWAD file path.
  Future<void> start(String iwadPath) async {
    if (!_backend.isSupported) {
      throw IwadRuntimeException(_backend.lastError);
    }
    if (iwadPath.trim().isEmpty) {
      throw const IwadRuntimeException('IWAD path is required.');
    }
    await _backend.start(iwadPath);
    _afterStart();
  }

  /// Starts the runtime from IWAD bytes.
  ///
  /// The [fileName] is used to derive the save directory identity together
  /// with the IWAD content hash.
  Future<void> startBytes(
    Uint8List iwadBytes, {
    String fileName = 'game.wad',
  }) async {
    if (!_backend.isSupported) {
      throw IwadRuntimeException(_backend.lastError);
    }
    await _backend.startBytes(iwadBytes, fileName: fileName);
    _afterStart();
  }

  void _afterStart() {
    _error = null;
    _hasQuit = false;
    _frameRgba = Uint8List(width * height * 4);
    _mouseRemainderX = 0;
    _mouseRemainderY = 0;
    _pendingMouseDeltaX = 0;
    _pendingMouseDeltaY = 0;
    notifyListeners();
  }

  /// Advances the runtime and decodes a frame when one is available.
  Future<void> tick() async {
    if (!isStarted || _decoding) {
      return;
    }

    try {
      _flushPendingMouseDelta();
      final bool ticked = _backend.tick();
      if (!ticked || _backend.hasQuit) {
        if (_backend.hasQuit) {
          _hasQuit = true;
          _error = null;
        } else {
          _error = _backend.lastError;
        }
        notifyListeners();
        return;
      }

      final int copied = _backend.copyFrameRgba(_frameRgba);
      if (copied <= 0) {
        return;
      }

      _decoding = true;
      final Uint8List pixels = Uint8List.fromList(_frameRgba);
      final Completer<void> completer = Completer<void>();
      ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888, (
        ui.Image image,
      ) {
        final ui.Image? oldImage = _image;
        _image = image;
        oldImage?.dispose();
        _decoding = false;
        notifyListeners();
        completer.complete();
      });
      await completer.future;
    } on Object catch (error) {
      _decoding = false;
      _error = error.toString();
      notifyListeners();
      return;
    }
  }

  /// Sends a key press or release using an [IwadInputKey] code.
  void setKeyPressed(int inputKey, bool pressed) {
    if (!isStarted) {
      return;
    }
    if (pressed && !_pressedKeys.add(inputKey)) {
      return;
    }
    if (!pressed) {
      _pressedKeys.remove(inputKey);
    }
    _backend.keyEvent(inputKey, pressed);
  }

  /// Sends a short key press and release.
  Future<void> tapKey(
    int inputKey, {
    Duration hold = const Duration(milliseconds: 50),
  }) async {
    setKeyPressed(inputKey, true);
    await Future<void>.delayed(hold);
    setKeyPressed(inputKey, false);
  }

  /// Requests weapon slot [slot], where valid slots are 1 through 8.
  void requestWeaponSlot(int slot) {
    if (!isStarted || slot < 1 || slot > 8) {
      return;
    }
    _backend.requestWeaponSlot(slot);
  }

  /// Starts a new game with engine skill, episode, and map values.
  Future<void> startNewGame({
    int skill = 2,
    int episode = 1,
    int map = 1,
  }) async {
    if (!isStarted) {
      throw const IwadRuntimeException('Runtime is not started.');
    }
    await _backend.startNewGame(skill: skill, episode: episode, map: map);
  }

  /// Saves the current game into [slot], where valid slots are 0 through 9.
  Future<void> saveGame(int slot, {String description = 'IWAD Runtime'}) async {
    _checkSaveSlot(slot);
    if (!isStarted) {
      throw const IwadRuntimeException('Runtime is not started.');
    }
    await _backend.saveGame(slot, description: description);
  }

  /// Loads a saved game from [slot], where valid slots are 0 through 9.
  Future<void> loadGame(int slot) async {
    _checkSaveSlot(slot);
    if (!isStarted) {
      throw const IwadRuntimeException('Runtime is not started.');
    }
    await _backend.loadGame(slot);
  }

  /// Sends a mouse button state, where button indices are 0 through 2.
  void setMouseButton(int buttonIndex, bool pressed) {
    if (!isStarted || buttonIndex < 0 || buttonIndex > 2) {
      return;
    }
    final int mask = 1 << buttonIndex;
    if (pressed) {
      _mouseButtons |= mask;
    } else {
      _mouseButtons &= ~mask;
    }
    _backend.mouseEvent(buttons: _mouseButtons, deltaX: 0, deltaY: 0);
  }

  /// Suspends or resumes backend ticking and audio output.
  void setSuspended(bool suspended) {
    _backend.setSuspended(suspended);
  }

  /// Whether this backend reports mouse movement through polling.
  bool get usesPolledMouseCapture => _backend.usesPolledMouseCapture;

  /// Adds relative mouse movement to be flushed on the next tick.
  void addMouseDelta(
    double deltaX,
    double deltaY, {
    double sensitivity = 1,
    double viewScale = 1,
    bool includeVerticalMovement = true,
    double maxMouseDeltaPerTick = defaultMaxMouseDeltaPerTick,
  }) {
    if (!isStarted) {
      return;
    }
    final double safeScale = viewScale <= 0 ? 1 : viewScale;
    _mouseRemainderX += (deltaX / safeScale) * sensitivity;
    if (includeVerticalMovement) {
      _mouseRemainderY += (-deltaY / safeScale) * sensitivity;
    }
    final int scaledX = _takeWholeMouseUnitsX();
    final int scaledY = _takeWholeMouseUnitsY();
    _pendingMouseDeltaX = _clampMouseDelta(
      _pendingMouseDeltaX + scaledX,
      maxMouseDeltaPerTick,
    );
    _pendingMouseDeltaY = _clampMouseDelta(
      _pendingMouseDeltaY + scaledY,
      maxMouseDeltaPerTick,
    );
  }

  /// Enables or disables backend-level mouse capture when supported.
  bool setMouseCapture(bool enabled) => _backend.setMouseCapture(enabled);

  /// Whether backend-level mouse capture is currently active.
  bool get isMouseCaptureActive => _backend.isMouseCaptureActive;

  /// Polls backend mouse movement and queues it for the next tick.
  void pollMouseDelta({
    double sensitivity = 1,
    bool includeVerticalMovement = true,
    double maxMouseDeltaPerTick = defaultMaxMouseDeltaPerTick,
  }) {
    if (!isStarted) {
      return;
    }
    final IwadMouseDelta? delta = _backend.pollMouseDelta();
    if (delta == null) {
      return;
    }
    addMouseDelta(
      delta.x.toDouble(),
      delta.y.toDouble(),
      sensitivity: sensitivity,
      includeVerticalMovement: includeVerticalMovement,
      maxMouseDeltaPerTick: maxMouseDeltaPerTick,
    );
  }

  int _clampMouseDelta(int value, double maxMouseDeltaPerTick) {
    if (maxMouseDeltaPerTick <= 0) {
      return value;
    }
    final int limit = maxMouseDeltaPerTick.round();
    return value.clamp(-limit, limit);
  }

  int _takeWholeMouseUnitsX() {
    final int units = _mouseRemainderX.truncate();
    _mouseRemainderX -= units;
    return units;
  }

  int _takeWholeMouseUnitsY() {
    final int units = _mouseRemainderY.truncate();
    _mouseRemainderY -= units;
    return units;
  }

  void _flushPendingMouseDelta() {
    if (_pendingMouseDeltaX == 0 && _pendingMouseDeltaY == 0) {
      return;
    }
    final int deltaX = _pendingMouseDeltaX;
    final int deltaY = _pendingMouseDeltaY;
    _pendingMouseDeltaX = 0;
    _pendingMouseDeltaY = 0;
    _backend.mouseEvent(buttons: _mouseButtons, deltaX: deltaX, deltaY: deltaY);
  }

  /// Releases all pressed keys, mouse buttons, mouse capture, and deltas.
  void releaseInput() {
    if (!isStarted) {
      _pressedKeys.clear();
      _mouseButtons = 0;
      _mouseRemainderX = 0;
      _mouseRemainderY = 0;
      _pendingMouseDeltaX = 0;
      _pendingMouseDeltaY = 0;
      _backend.setMouseCapture(false);
      return;
    }
    for (final int key in List<int>.of(_pressedKeys)) {
      _backend.keyEvent(key, false);
    }
    _pressedKeys.clear();
    if (_mouseButtons != 0) {
      _mouseButtons = 0;
      _backend.mouseEvent(buttons: 0, deltaX: 0, deltaY: 0);
    }
    _mouseRemainderX = 0;
    _mouseRemainderY = 0;
    _pendingMouseDeltaX = 0;
    _pendingMouseDeltaY = 0;
    _backend.setMouseCapture(false);
  }

  void _checkSaveSlot(int slot) {
    if (slot < 0 || slot > 9) {
      throw const IwadRuntimeException('Save slot must be 0 through 9.');
    }
  }

  @override
  void dispose() {
    releaseInput();
    _backend.shutdown();
    _image?.dispose();
    super.dispose();
  }
}
