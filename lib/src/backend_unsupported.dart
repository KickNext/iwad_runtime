import 'dart:typed_data';

import 'backend.dart';

IwadBackend createIwadBackend() => _UnsupportedIwadBackend();

final class _UnsupportedIwadBackend implements IwadBackend {
  @override
  bool get isSupported => false;

  @override
  bool get isStarted => false;

  @override
  bool get hasQuit => false;

  @override
  int get width => 640;

  @override
  int get height => 400;

  @override
  String get lastError =>
      'This platform does not have an iwad_runtime backend in the current build.';

  @override
  int get currentWeaponSlot => 0;

  @override
  int get ownedWeaponSlotsMask => 0;

  @override
  bool get isGameplayActive => false;

  @override
  bool get isPlayerDead => false;

  @override
  bool get isAdvanceActive => false;

  @override
  bool get isMenuActive => false;

  @override
  bool get isMenuPromptActive => false;

  @override
  bool get isSaveNameActive => false;

  @override
  bool get isQuitConfirmActive => false;

  @override
  Future<void> start(String iwadPath) async =>
      throw UnsupportedError(lastError);

  @override
  Future<void> startBytes(
    Uint8List iwadBytes, {
    String fileName = 'game.wad',
  }) async => throw UnsupportedError(lastError);

  @override
  Future<void> startNewGame({
    int skill = 2,
    int episode = 1,
    int map = 1,
  }) async => throw UnsupportedError(lastError);

  @override
  Future<void> saveGame(
    int slot, {
    String description = 'IWAD Runtime',
  }) async => throw UnsupportedError(lastError);

  @override
  Future<void> loadGame(int slot) async => throw UnsupportedError(lastError);

  @override
  bool tick() => false;

  @override
  int copyFrameRgba(Uint8List out) => 0;

  @override
  void keyEvent(int inputKey, bool pressed) {}

  @override
  void requestWeaponSlot(int slot) {}

  @override
  void mouseEvent({
    required int buttons,
    required int deltaX,
    required int deltaY,
  }) {}

  @override
  void setSuspended(bool suspended) {}

  @override
  void shutdown() {}

  @override
  bool setMouseCapture(bool enabled) => false;

  @override
  bool get isMouseCaptureActive => false;

  @override
  bool get usesPolledMouseCapture => false;

  @override
  IwadMouseDelta? pollMouseDelta() => null;
}
