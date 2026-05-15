import 'dart:js_interop';
import 'dart:async';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'backend.dart';
import 'exceptions.dart';

@JS('iwadRuntimeCreate')
external JSPromise<_WebIwadModule> _iwadRuntimeCreate(
  JSString scriptUrl,
  JSString wasmUrl,
);

extension type _WebIwadModule(JSObject _) implements JSObject {
  external JSNumber startBytes(JSUint8Array bytes, JSString fileName);
  external JSNumber startNewGame(
    JSNumber skill,
    JSNumber episode,
    JSNumber map,
  );
  external JSPromise<JSNumber> saveGame(JSNumber slot, JSString description);
  external JSPromise<JSNumber> loadGame(JSNumber slot);
  external JSNumber tick();
  external JSNumber copyFrame(JSUint8Array out);
  external JSUint8Array copyFrameBytes(JSNumber length);
  external void keyEvent(JSNumber inputKey, JSNumber pressed);
  external void requestWeaponSlot(JSNumber slot);
  external void mouseEvent(JSNumber buttons, JSNumber deltaX, JSNumber deltaY);
  external void setSuspended(JSNumber suspended);
  external void shutdown();
  external JSBoolean get isStarted;
  external JSBoolean get hasQuit;
  external JSString get lastError;
  external JSNumber get currentWeaponSlot;
  external JSNumber get ownedWeaponSlotsMask;
  external JSBoolean get isGameplayActive;
  external JSBoolean get isPlayerDead;
  external JSBoolean get isAdvanceActive;
  external JSBoolean get isMenuActive;
  external JSBoolean get isMenuPromptActive;
  external JSBoolean get isSaveNameActive;
  external JSBoolean get isQuitConfirmActive;
}

IwadBackend createIwadBackend() => WebIwadBackend();

final class WebIwadBackend implements IwadBackend {
  static const String _assetBase = 'assets/packages/iwad_runtime/assets';

  _WebIwadModule? _module;
  Future<_WebIwadModule>? _moduleFuture;
  JSFunction? _mouseMoveListener;
  int _pendingMouseDeltaX = 0;
  int _pendingMouseDeltaY = 0;

  @override
  bool get isSupported => true;

  @override
  bool get isStarted => _module?.isStarted.toDart ?? false;

  @override
  bool get hasQuit => _module?.hasQuit.toDart ?? false;

  @override
  int get width => 640;

  @override
  int get height => 400;

  @override
  String get lastError => _module?.lastError.toDart ?? '';

  @override
  int get currentWeaponSlot => _module?.currentWeaponSlot.toDartInt ?? 0;

  @override
  int get ownedWeaponSlotsMask => _module?.ownedWeaponSlotsMask.toDartInt ?? 0;

  @override
  bool get isGameplayActive => _module?.isGameplayActive.toDart ?? false;

  @override
  bool get isPlayerDead => _module?.isPlayerDead.toDart ?? false;

  @override
  bool get isAdvanceActive => _module?.isAdvanceActive.toDart ?? false;

  @override
  bool get isMenuActive => _module?.isMenuActive.toDart ?? false;

  @override
  bool get isMenuPromptActive => _module?.isMenuPromptActive.toDart ?? false;

  @override
  bool get isSaveNameActive => _module?.isSaveNameActive.toDart ?? false;

  @override
  bool get isQuitConfirmActive => _module?.isQuitConfirmActive.toDart ?? false;

  @override
  Future<void> start(String iwadPath) async {
    final web.Response response = await web.window.fetch(iwadPath.toJS).toDart;
    if (!response.ok) {
      throw IwadRuntimeException('Failed to fetch IWAD: $iwadPath');
    }
    final JSArrayBuffer buffer = await response.arrayBuffer().toDart;
    final bytes = Uint8List.view(buffer.toDart);
    await startBytes(bytes, fileName: _fileNameFromPath(iwadPath));
  }

  @override
  Future<void> startBytes(
    Uint8List iwadBytes, {
    String fileName = 'game.wad',
  }) async {
    final _WebIwadModule module = await _loadModule();
    final int result = module
        .startBytes(iwadBytes.toJS, fileName.toJS)
        .toDartInt;
    if (result == 0) {
      throw IwadRuntimeException(lastError);
    }
  }

  @override
  Future<void> startNewGame({
    int skill = 2,
    int episode = 1,
    int map = 1,
  }) async {
    final _WebIwadModule module = await _loadModule();
    final int result = module
        .startNewGame(skill.toJS, episode.toJS, map.toJS)
        .toDartInt;
    if (result == 0) {
      throw IwadRuntimeException(lastError);
    }
  }

  @override
  Future<void> saveGame(int slot, {String description = 'IWAD Runtime'}) async {
    final _WebIwadModule module = await _loadModule();
    final int result =
        (await module.saveGame(slot.toJS, description.toJS).toDart).toDartInt;
    if (result == 0) {
      throw IwadRuntimeException(lastError);
    }
  }

  @override
  Future<void> loadGame(int slot) async {
    final _WebIwadModule module = await _loadModule();
    final int result = (await module.loadGame(slot.toJS).toDart).toDartInt;
    if (result == 0) {
      throw IwadRuntimeException(lastError);
    }
  }

  @override
  bool tick() => (_module?.tick().toDartInt ?? 0) != 0;

  @override
  int copyFrameRgba(Uint8List out) {
    final _WebIwadModule? module = _module;
    if (module == null) {
      return 0;
    }
    final JSUint8Array frame = module.copyFrameBytes(out.length.toJS);
    final Uint8List bytes = frame.toDart;
    if (bytes.isEmpty) {
      return 0;
    }
    out.setAll(0, bytes);
    return bytes.length;
  }

  @override
  void keyEvent(int inputKey, bool pressed) {
    _module?.keyEvent(inputKey.toJS, (pressed ? 1 : 0).toJS);
  }

  @override
  void requestWeaponSlot(int slot) {
    _module?.requestWeaponSlot(slot.toJS);
  }

  @override
  void mouseEvent({
    required int buttons,
    required int deltaX,
    required int deltaY,
  }) {
    _module?.mouseEvent(buttons.toJS, deltaX.toJS, deltaY.toJS);
  }

  @override
  void setSuspended(bool suspended) {
    _module?.setSuspended((suspended ? 1 : 0).toJS);
  }

  @override
  void shutdown() {
    _removeMouseMoveListener();
    _module?.shutdown();
  }

  @override
  bool setMouseCapture(bool enabled) {
    if (enabled) {
      final web.HTMLElement? body = web.document.body;
      if (body == null) {
        return false;
      }
      _pendingMouseDeltaX = 0;
      _pendingMouseDeltaY = 0;
      _installMouseMoveListener();
      body.requestPointerLock();
      return true;
    }
    _pendingMouseDeltaX = 0;
    _pendingMouseDeltaY = 0;
    web.document.exitPointerLock();
    return true;
  }

  @override
  bool get isMouseCaptureActive => web.document.pointerLockElement != null;

  @override
  bool get usesPolledMouseCapture => true;

  @override
  IwadMouseDelta? pollMouseDelta() {
    if (!isMouseCaptureActive) {
      _pendingMouseDeltaX = 0;
      _pendingMouseDeltaY = 0;
      return null;
    }
    if (_pendingMouseDeltaX == 0 && _pendingMouseDeltaY == 0) {
      return null;
    }
    final IwadMouseDelta delta = IwadMouseDelta(
      _pendingMouseDeltaX,
      _pendingMouseDeltaY,
    );
    _pendingMouseDeltaX = 0;
    _pendingMouseDeltaY = 0;
    return delta;
  }

  void _installMouseMoveListener() {
    if (_mouseMoveListener != null) {
      return;
    }
    _mouseMoveListener = ((web.Event event) {
      if (!isMouseCaptureActive) {
        return;
      }
      final web.MouseEvent mouseEvent = event as web.MouseEvent;
      _pendingMouseDeltaX += mouseEvent.movementX.round();
      _pendingMouseDeltaY += mouseEvent.movementY.round();
    }).toJS;
    web.document.addEventListener('mousemove', _mouseMoveListener);
  }

  void _removeMouseMoveListener() {
    final JSFunction? listener = _mouseMoveListener;
    if (listener == null) {
      return;
    }
    web.document.removeEventListener('mousemove', listener);
    _mouseMoveListener = null;
    _pendingMouseDeltaX = 0;
    _pendingMouseDeltaY = 0;
  }

  Future<_WebIwadModule> _loadModule() {
    final _WebIwadModule? module = _module;
    if (module != null) {
      return Future<_WebIwadModule>.value(module);
    }
    return _moduleFuture ??= _loadModuleFromAssets();
  }

  Future<_WebIwadModule> _loadModuleFromAssets() async {
    await _loadScript('$_assetBase/iwad_runtime_web_loader.js');
    final _WebIwadModule module = await _iwadRuntimeCreate(
      '$_assetBase/iwad_runtime_web.js'.toJS,
      '$_assetBase/iwad_runtime_web.wasm'.toJS,
    ).toDart;
    _module = module;
    return module;
  }

  Future<void> _loadScript(String url) {
    final Completer<void> completer = Completer<void>();
    final web.HTMLScriptElement script =
        web.document.createElement('script') as web.HTMLScriptElement;
    script.src = url;
    script.async = true;
    script.onload = ((web.Event event) {
      completer.complete();
      return null;
    }).toJS;
    script.onerror = ((web.Event event) {
      completer.completeError(IwadRuntimeException('Failed to load $url'));
      return null;
    }).toJS;
    web.document.head!.append(script);
    return completer.future;
  }

  String _fileNameFromPath(String path) {
    final Uri? uri = Uri.tryParse(path);
    final String name = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : path.split('/').last;
    return name.isEmpty ? 'game.wad' : name;
  }
}
