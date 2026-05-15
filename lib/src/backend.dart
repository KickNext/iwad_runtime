import 'dart:typed_data';

final class IwadMouseDelta {
  const IwadMouseDelta(this.x, this.y);

  final int x;
  final int y;
}

abstract interface class IwadBackend {
  bool get isSupported;
  bool get isStarted;
  bool get hasQuit;
  int get width;
  int get height;
  String get lastError;
  int get currentWeaponSlot;
  int get ownedWeaponSlotsMask;
  bool get isGameplayActive;
  bool get isPlayerDead;
  bool get isAdvanceActive;
  bool get isMenuActive;
  bool get isMenuPromptActive;
  bool get isSaveNameActive;
  bool get isQuitConfirmActive;

  Future<void> start(String iwadPath);
  Future<void> startBytes(Uint8List iwadBytes, {String fileName = 'game.wad'});
  Future<void> startNewGame({int skill = 2, int episode = 1, int map = 1});
  Future<void> saveGame(int slot, {String description = 'IWAD Runtime'});
  Future<void> loadGame(int slot);
  bool tick();
  int copyFrameRgba(Uint8List out);
  void keyEvent(int inputKey, bool pressed);
  void requestWeaponSlot(int slot);
  void mouseEvent({
    required int buttons,
    required int deltaX,
    required int deltaY,
  });
  void setSuspended(bool suspended);
  void shutdown();
  bool setMouseCapture(bool enabled);
  bool get isMouseCaptureActive;
  bool get usesPolledMouseCapture;
  IwadMouseDelta? pollMouseDelta();
}
