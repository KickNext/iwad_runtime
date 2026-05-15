import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

import '../iwad_runtime_bindings_generated.dart';
import 'backend.dart';
import 'exceptions.dart';
import 'multiplayer.dart';

const String _libName = 'iwad_runtime_native';
const String _appleLibName = 'iwad_runtime';

IwadBackend createIwadBackend() => NativeIwadBackend();

final class NativeIwadBackend implements IwadBackend, IwadMultiplayerBackend {
  NativeIwadBackend({IwadRuntimeBindings? bindings}) : _bindings = bindings;

  IwadRuntimeBindings? _bindings;
  Directory? _tempDirectory;
  bool _mouseCaptureActive = false;

  IwadRuntimeBindings get _nativeBindings =>
      _bindings ??= IwadRuntimeBindings(_openLibrary());

  @override
  bool get isSupported => true;

  @override
  bool get isStarted => (_bindings?.iwadr_is_started() ?? 0) != 0;

  @override
  bool get hasQuit => (_bindings?.iwadr_has_quit() ?? 0) != 0;

  @override
  int get width => 640;

  @override
  int get height => 400;

  @override
  String get lastError {
    final IwadRuntimeBindings? bindings = _bindings;
    if (bindings == null) {
      return '';
    }
    final Pointer<Char> message = bindings.iwadr_last_error();
    if (message == nullptr) {
      return '';
    }
    return message.cast<Utf8>().toDartString();
  }

  @override
  int get currentWeaponSlot => _bindings?.iwadr_current_weapon_slot() ?? 0;

  @override
  int get ownedWeaponSlotsMask =>
      _bindings?.iwadr_owned_weapon_slots_mask() ?? 0;

  @override
  bool get isGameplayActive =>
      (_bindings?.iwadr_is_gameplay_active() ?? 0) != 0;

  @override
  bool get isPlayerDead => (_bindings?.iwadr_is_player_dead() ?? 0) != 0;

  @override
  bool get isAdvanceActive => (_bindings?.iwadr_is_advance_active() ?? 0) != 0;

  @override
  bool get isMenuActive => (_bindings?.iwadr_is_menu_active() ?? 0) != 0;

  @override
  bool get isMenuPromptActive =>
      (_bindings?.iwadr_is_menu_prompt_active() ?? 0) != 0;

  @override
  bool get isSaveNameActive =>
      (_bindings?.iwadr_is_save_name_active() ?? 0) != 0;

  @override
  bool get isQuitConfirmActive =>
      (_bindings?.iwadr_is_quit_confirm_active() ?? 0) != 0;

  @override
  bool get isMultiplayerSupported =>
      _nativeBindings.iwadr_multiplayer_is_supported() != 0;

  @override
  int get ticCommandSize => _nativeBindings.iwadr_ticcmd_size();

  @override
  int get syncChecksum => _nativeBindings.iwadr_sync_checksum();

  @override
  Future<void> start(String iwadPath) async {
    await _configureNativeTempDir();
    final Pointer<Utf8> path = iwadPath.toNativeUtf8();
    try {
      final int result = _nativeBindings.iwadr_start(path.cast<Char>());
      if (result == 0) {
        throw IwadRuntimeException(lastError);
      }
    } finally {
      calloc.free(path);
    }
  }

  @override
  Future<void> startBytes(
    Uint8List iwadBytes, {
    String fileName = 'game.wad',
  }) async {
    final Directory directory = await _configureNativeTempDir();
    final File file = File(
      '${directory.path}${Platform.pathSeparator}$fileName',
    );
    await file.writeAsBytes(iwadBytes, flush: true);
    await start(file.path);
  }

  @override
  Future<void> startMultiplayer(
    String iwadPath,
    IwadMultiplayerSettings settings,
  ) async {
    await _configureNativeTempDir();
    final Pointer<Utf8> path = iwadPath.toNativeUtf8();
    try {
      final int result = _nativeBindings.iwadr_start_multiplayer(
        path.cast<Char>(),
        settings.playerCount,
        settings.localPlayerIndex,
        settings.deathmatch ? 1 : 0,
        settings.episode,
        settings.map,
        settings.skill,
        settings.noMonsters ? 1 : 0,
        settings.fastMonsters ? 1 : 0,
        settings.respawnMonsters ? 1 : 0,
        settings.ticdup,
      );
      if (result == 0) {
        throw IwadRuntimeException(lastError);
      }
    } finally {
      calloc.free(path);
    }
  }

  @override
  Future<void> startMultiplayerBytes(
    Uint8List iwadBytes,
    IwadMultiplayerSettings settings, {
    String fileName = 'game.wad',
  }) async {
    final Directory directory = await _configureNativeTempDir();
    final File file = File(
      '${directory.path}${Platform.pathSeparator}$fileName',
    );
    await file.writeAsBytes(iwadBytes, flush: true);
    await startMultiplayer(file.path, settings);
  }

  @override
  Future<void> startNewGame({
    int skill = 2,
    int episode = 1,
    int map = 1,
  }) async {
    final int result = _nativeBindings.iwadr_start_new_game(
      skill,
      episode,
      map,
    );
    if (result == 0) {
      throw IwadRuntimeException(lastError);
    }
  }

  @override
  Future<void> saveGame(int slot, {String description = 'IWAD Runtime'}) async {
    final Pointer<Utf8> descriptionPointer = description.toNativeUtf8();
    try {
      final int result = _nativeBindings.iwadr_save_game(
        slot,
        descriptionPointer.cast<Char>(),
      );
      if (result == 0) {
        throw IwadRuntimeException(lastError);
      }
    } finally {
      calloc.free(descriptionPointer);
    }
  }

  @override
  Future<void> loadGame(int slot) async {
    final int result = _nativeBindings.iwadr_load_game(slot);
    if (result == 0) {
      throw IwadRuntimeException(lastError);
    }
  }

  @override
  bool tick() => _nativeBindings.iwadr_tick() != 0;

  @override
  int copyFrameRgba(Uint8List out) {
    final Pointer<Uint8> buffer = calloc<Uint8>(out.length);
    try {
      final int copied = _nativeBindings.iwadr_copy_frame_rgba(
        buffer,
        out.length,
      );
      if (copied > 0) {
        out.setAll(0, buffer.asTypedList(copied));
      }
      return copied;
    } finally {
      calloc.free(buffer);
    }
  }

  @override
  void keyEvent(int inputKey, bool pressed) {
    _nativeBindings.iwadr_key_event(inputKey, pressed ? 1 : 0);
  }

  @override
  void requestWeaponSlot(int slot) {
    _nativeBindings.iwadr_request_weapon_slot(slot);
  }

  @override
  void mouseEvent({
    required int buttons,
    required int deltaX,
    required int deltaY,
  }) {
    _nativeBindings.iwadr_mouse_event(buttons, deltaX, deltaY);
  }

  @override
  void setSuspended(bool suspended) {
    _nativeBindings.iwadr_set_suspended(suspended ? 1 : 0);
  }

  @override
  void shutdown() {
    _bindings?.iwadr_shutdown();
  }

  @override
  bool setMouseCapture(bool enabled) {
    final bool applied =
        _nativeBindings.iwadr_set_mouse_capture(enabled ? 1 : 0) != 0;
    _mouseCaptureActive = applied && enabled;
    return applied;
  }

  @override
  bool get isMouseCaptureActive => _mouseCaptureActive;

  @override
  bool get usesPolledMouseCapture => Platform.isWindows || Platform.isLinux;

  @override
  IwadMouseDelta? pollMouseDelta() {
    if (!usesPolledMouseCapture) {
      return null;
    }
    final Pointer<Int> deltaX = calloc<Int>();
    final Pointer<Int> deltaY = calloc<Int>();
    try {
      final int result = _nativeBindings.iwadr_poll_mouse_delta(deltaX, deltaY);
      if (result == 0) {
        return null;
      }
      return IwadMouseDelta(deltaX.value, deltaY.value);
    } finally {
      calloc.free(deltaX);
      calloc.free(deltaY);
    }
  }

  @override
  Uint8List buildLocalTicCommand() {
    final int size = ticCommandSize;
    final Pointer<Uint8> buffer = calloc<Uint8>(size);
    try {
      final int copied = _nativeBindings.iwadr_build_local_ticcmd(buffer, size);
      if (copied <= 0) {
        throw IwadRuntimeException(lastError);
      }
      return Uint8List.fromList(buffer.asTypedList(copied));
    } finally {
      calloc.free(buffer);
    }
  }

  @override
  IwadSynchronizedTickResult runSynchronizedTick(List<Uint8List?> commands) {
    final int size = ticCommandSize;
    final int count = commands.length;
    final Pointer<Uint8> commandBuffer = calloc<Uint8>(size * count);
    final Pointer<Int> presentBuffer = calloc<Int>(count);
    try {
      final Uint8List commandBytes = commandBuffer.asTypedList(size * count);
      for (int i = 0; i < count; i++) {
        final Uint8List? command = commands[i];
        if (command == null) {
          presentBuffer[i] = 0;
          continue;
        }
        if (command.length != size) {
          throw IwadRuntimeException(
            'Tic command has ${command.length} bytes, expected $size.',
          );
        }
        presentBuffer[i] = 1;
        commandBytes.setRange(i * size, (i + 1) * size, command);
      }
      final int result = _nativeBindings.iwadr_run_synchronized_tic(
        commandBuffer,
        presentBuffer,
        count,
      );
      if (result > 0) {
        return IwadSynchronizedTickResult.advanced;
      }
      if (result == 0) {
        return IwadSynchronizedTickResult.blocked;
      }
      if (_nativeBindings.iwadr_has_quit() != 0) {
        return IwadSynchronizedTickResult.quit;
      }
      throw IwadRuntimeException(lastError);
    } finally {
      calloc.free(commandBuffer);
      calloc.free(presentBuffer);
    }
  }

  Future<Directory> _configureNativeTempDir() async {
    final Directory directory = _tempDirectory ??=
        await nativeIwadDataDirectory();
    final Pointer<Utf8> path = directory.path.toNativeUtf8();
    try {
      _nativeBindings.iwadr_set_temp_dir(path.cast<Char>());
    } finally {
      calloc.free(path);
    }
    return directory;
  }
}

Future<Directory> nativeIwadDataDirectory({Directory? baseDirectory}) async {
  final Directory base =
      baseDirectory ?? await getApplicationSupportDirectory();
  final Directory directory = Directory(
    '${base.path}${Platform.pathSeparator}iwad_runtime',
  );
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return directory;
}

DynamicLibrary _openLibrary() {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('$_appleLibName.framework/$_appleLibName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}
