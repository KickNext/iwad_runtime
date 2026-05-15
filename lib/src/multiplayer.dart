import 'dart:typed_data';

import 'backend.dart';
import 'backend_factory.dart';
import 'exceptions.dart';

/// Settings used to start a synchronized multiplayer runtime.
final class IwadMultiplayerSettings {
  /// Creates validated multiplayer startup settings.
  IwadMultiplayerSettings({
    this.playerCount = 2,
    this.localPlayerIndex = 0,
    this.deathmatch = false,
    this.episode = 1,
    this.map = 1,
    this.skill = 2,
    this.noMonsters = false,
    this.fastMonsters = false,
    this.respawnMonsters = false,
    this.ticdup = 1,
  }) {
    if (playerCount < 2 || playerCount > 4) {
      throw ArgumentError.value(
        playerCount,
        'playerCount',
        'must be 2 through 4',
      );
    }
    if (localPlayerIndex < 0 || localPlayerIndex >= playerCount) {
      throw ArgumentError.value(
        localPlayerIndex,
        'localPlayerIndex',
        'must be inside playerCount',
      );
    }
    if (episode < 1 || episode > 4) {
      throw ArgumentError.value(episode, 'episode', 'must be 1 through 4');
    }
    if (map < 1 || map > 32) {
      throw ArgumentError.value(map, 'map', 'must be 1 through 32');
    }
    if (skill < 0 || skill > 4) {
      throw ArgumentError.value(skill, 'skill', 'must be 0 through 4');
    }
    if (ticdup < 1 || ticdup > 4) {
      throw ArgumentError.value(ticdup, 'ticdup', 'must be 1 through 4');
    }
  }

  /// Number of synchronized players, from 2 through 4.
  final int playerCount;

  /// Zero-based index of the local player.
  final int localPlayerIndex;

  /// Whether deathmatch rules should be enabled.
  final bool deathmatch;

  /// Episode number to start.
  final int episode;

  /// Map number to start.
  final int map;

  /// Engine skill level, from 0 through 4.
  final int skill;

  /// Whether monsters should be disabled.
  final bool noMonsters;

  /// Whether fast monster behavior should be enabled.
  final bool fastMonsters;

  /// Whether monsters should respawn.
  final bool respawnMonsters;

  /// Engine tic duplication factor, from 1 through 4.
  final int ticdup;
}

/// Serialized local player command for one synchronized engine tic.
final class IwadTicCommand {
  /// Creates a tic command from raw engine command bytes.
  const IwadTicCommand(this.bytes);

  /// Raw engine command bytes.
  final Uint8List bytes;
}

/// Result of attempting to advance a synchronized multiplayer tick.
enum IwadSynchronizedTickResult {
  /// The engine advanced one synchronized tick.
  advanced,

  /// The engine is waiting for missing remote player commands.
  blocked,

  /// The engine reported a quit request.
  quit,
}

/// Backend contract for synchronized multiplayer support.
abstract interface class IwadMultiplayerBackend implements IwadBackend {
  /// Whether multiplayer startup and synchronized ticks are available.
  bool get isMultiplayerSupported;

  /// Number of bytes in one player tic command.
  int get ticCommandSize;

  /// Engine synchronization checksum for the current tick.
  int get syncChecksum;

  /// Starts multiplayer from an IWAD file path.
  Future<void> startMultiplayer(
    String iwadPath,
    IwadMultiplayerSettings settings,
  );

  /// Starts multiplayer from IWAD bytes.
  Future<void> startMultiplayerBytes(
    Uint8List iwadBytes,
    IwadMultiplayerSettings settings, {
    String fileName = 'game.wad',
  });

  /// Builds the local player command for the next synchronized tick.
  Uint8List buildLocalTicCommand();

  /// Runs one synchronized tick using one command per player.
  IwadSynchronizedTickResult runSynchronizedTick(List<Uint8List?> commands);
}

/// Convenience wrapper around an [IwadMultiplayerBackend].
final class IwadNetworkSession {
  /// Creates a network session backed by the current platform implementation.
  IwadNetworkSession({IwadBackend? backend})
    : _backend = backend ?? createIwadBackend();

  final IwadBackend _backend;

  IwadMultiplayerBackend? get _multiplayerBackend =>
      _backend is IwadMultiplayerBackend ? _backend : null;

  /// Whether multiplayer support is available on this backend.
  bool get isSupported => _multiplayerBackend?.isMultiplayerSupported ?? false;

  /// Whether a multiplayer runtime session has been started.
  bool get isStarted => _backend.isStarted;

  /// Number of bytes in one player tic command.
  int get ticCommandSize => _multiplayerBackend?.ticCommandSize ?? 0;

  /// Engine synchronization checksum for the current tick.
  int get syncChecksum => _multiplayerBackend?.syncChecksum ?? 0;

  /// Last backend error message.
  String get lastError => _backend.lastError;

  /// Starts multiplayer from an IWAD file path.
  Future<void> start(String iwadPath, IwadMultiplayerSettings settings) async {
    final IwadMultiplayerBackend backend = _requireMultiplayerBackend();
    await backend.startMultiplayer(iwadPath, settings);
  }

  /// Starts multiplayer from IWAD bytes.
  Future<void> startBytes(
    Uint8List iwadBytes,
    IwadMultiplayerSettings settings, {
    String fileName = 'game.wad',
  }) async {
    final IwadMultiplayerBackend backend = _requireMultiplayerBackend();
    await backend.startMultiplayerBytes(
      iwadBytes,
      settings,
      fileName: fileName,
    );
  }

  /// Builds the local player command for the next synchronized tick.
  IwadTicCommand buildLocalTicCommand() {
    final IwadMultiplayerBackend backend = _requireMultiplayerBackend();
    return IwadTicCommand(backend.buildLocalTicCommand());
  }

  /// Runs one synchronized tick using one command per player.
  IwadSynchronizedTickResult runSynchronizedTick(
    List<IwadTicCommand?> commands,
  ) {
    final IwadMultiplayerBackend backend = _requireMultiplayerBackend();
    return backend.runSynchronizedTick(
      commands.map((command) => command?.bytes).toList(growable: false),
    );
  }

  /// Stops the runtime and releases backend resources.
  void shutdown() => _backend.shutdown();

  IwadMultiplayerBackend _requireMultiplayerBackend() {
    final IwadMultiplayerBackend? backend = _multiplayerBackend;
    if (backend == null || !backend.isMultiplayerSupported) {
      throw const IwadRuntimeException(
        'Multiplayer support is not available on this backend.',
      );
    }
    return backend;
  }
}
