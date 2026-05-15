import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iwad_runtime/iwad_runtime.dart';
import 'package:iwad_runtime/src/backend.dart';

void main() {
  test('multiplayer settings reject invalid player counts and indexes', () {
    expect(
      () => IwadMultiplayerSettings(playerCount: 1, localPlayerIndex: 0),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => IwadMultiplayerSettings(playerCount: 5, localPlayerIndex: 0),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => IwadMultiplayerSettings(playerCount: 2, localPlayerIndex: 2),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('network session reports unsupported backend before start', () {
    final session = IwadNetworkSession(backend: _SinglePlayerOnlyBackend());

    expect(session.isSupported, isFalse);
    expect(
      () => session.startBytes(Uint8List(4), IwadMultiplayerSettings()),
      throwsA(isA<IwadRuntimeException>()),
    );
  });

  test(
    'network session forwards full command sets to multiplayer backend',
    () async {
      final backend = _FakeMultiplayerBackend();
      final session = IwadNetworkSession(backend: backend);
      final settings = IwadMultiplayerSettings(
        playerCount: 2,
        localPlayerIndex: 1,
      );

      await session.startBytes(Uint8List.fromList(<int>[1, 2, 3]), settings);
      final local = session.buildLocalTicCommand();
      final result = session.runSynchronizedTick(<IwadTicCommand?>[
        IwadTicCommand(Uint8List.fromList(<int>[9, 9, 9, 9])),
        local,
      ]);

      expect(result, IwadSynchronizedTickResult.advanced);
      expect(backend.startedSettings, same(settings));
      expect(backend.startedBytesLength, 3);
      expect(backend.lastSubmittedCommandCount, 2);
    },
  );
}

final class _SinglePlayerOnlyBackend implements IwadBackend {
  @override
  bool get isSupported => true;

  @override
  bool get isStarted => false;

  @override
  bool get hasQuit => false;

  @override
  int get width => 640;

  @override
  int get height => 400;

  @override
  String get lastError => '';

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
  Future<void> start(String iwadPath) async {}

  @override
  Future<void> startBytes(
    Uint8List iwadBytes, {
    String fileName = 'game.wad',
  }) async {}

  @override
  Future<void> startNewGame({
    int skill = 2,
    int episode = 1,
    int map = 1,
  }) async {}

  @override
  Future<void> saveGame(
    int slot, {
    String description = 'IWAD Runtime',
  }) async {}

  @override
  Future<void> loadGame(int slot) async {}

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

final class _FakeMultiplayerBackend extends _SinglePlayerOnlyBackend
    implements IwadMultiplayerBackend {
  IwadMultiplayerSettings? startedSettings;
  int? startedBytesLength;
  int lastSubmittedCommandCount = 0;

  @override
  bool get isMultiplayerSupported => true;

  @override
  int get ticCommandSize => 4;

  @override
  int get syncChecksum => 1234;

  @override
  Future<void> startMultiplayer(
    String iwadPath,
    IwadMultiplayerSettings settings,
  ) async {
    startedSettings = settings;
  }

  @override
  Future<void> startMultiplayerBytes(
    Uint8List iwadBytes,
    IwadMultiplayerSettings settings, {
    String fileName = 'game.wad',
  }) async {
    startedSettings = settings;
    startedBytesLength = iwadBytes.length;
  }

  @override
  Uint8List buildLocalTicCommand() => Uint8List.fromList(<int>[1, 2, 3, 4]);

  @override
  IwadSynchronizedTickResult runSynchronizedTick(List<Uint8List?> commands) {
    lastSubmittedCommandCount = commands.length;
    return IwadSynchronizedTickResult.advanced;
  }
}
