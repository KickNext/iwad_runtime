import 'dart:typed_data';

import 'package:iwad_runtime/src/backend.dart';
import 'package:iwad_runtime/src/controller.dart';
import 'package:iwad_runtime/src/input_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('releaseInput releases held keyboard and mouse state', () async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);

    await controller.startBytes(Uint8List(4));
    controller.setKeyPressed(IwadInputKey.up, true);
    controller.setKeyPressed(IwadInputKey.up, true);
    controller.setMouseButton(0, true);
    controller.addMouseDelta(4, -2);

    controller.releaseInput();

    expect(backend.keyEvents, <String>['173:true', '173:false']);
    expect(backend.mouseEvents.last, '0:0:0');
  });

  test('start requires a non-empty IWAD path', () async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);

    await expectLater(controller.start(''), throwsA(isA<Exception>()));

    expect(controller.isStarted, isFalse);
  });

  test('mouse delta coalesces per tick and normalizes by view scale', () async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);

    await controller.startBytes(Uint8List(4));
    controller.addMouseDelta(1, 0, sensitivity: 1, viewScale: 2);
    controller.addMouseDelta(1, 0, sensitivity: 1, viewScale: 2);
    controller.addMouseDelta(0, -1, sensitivity: 1, viewScale: 2);
    controller.addMouseDelta(0, -1, sensitivity: 1, viewScale: 2);
    await controller.tick();

    expect(backend.mouseEvents, <String>['0:1:1']);
  });

  test('polled mouse delta is forwarded with sensitivity', () async {
    final backend = _FakeBackend()
      ..polledMouseDeltas.add(const IwadMouseDelta(3, -2));
    final controller = IwadController(backend: backend);

    await controller.startBytes(Uint8List(4));
    controller.pollMouseDelta(sensitivity: 10);
    await controller.tick();

    expect(backend.mouseEvents, <String>['0:30:20']);
  });

  test('mouse delta is clamped per tick to ignore capture spikes', () async {
    final backend = _FakeBackend()
      ..polledMouseDeltas.add(const IwadMouseDelta(1000, -1000));
    final controller = IwadController(backend: backend);

    await controller.startBytes(Uint8List(4));
    controller.pollMouseDelta(sensitivity: 10);
    await controller.tick();

    expect(backend.mouseEvents, <String>['0:220:220']);
  });

  test('mouse delta cap applies to accumulated movement before tick', () async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);

    await controller.startBytes(Uint8List(4));
    controller.addMouseDelta(10, 0, maxMouseDeltaPerTick: 12);
    controller.addMouseDelta(10, 0, maxMouseDeltaPerTick: 12);
    await controller.tick();

    expect(backend.mouseEvents, <String>['0:12:0']);
  });

  test('weapon slot request is forwarded without keyboard events', () async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);

    await controller.startBytes(Uint8List(4));
    controller.requestWeaponSlot(4);
    controller.requestWeaponSlot(0);

    expect(backend.weaponSlotRequests, <int>[4]);
    expect(backend.keyEvents, isEmpty);
  });

  test('save and load requests are forwarded to the backend', () async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);

    await controller.startBytes(Uint8List(4));
    await controller.saveGame(2, description: 'checkpoint');
    await controller.loadGame(2);

    expect(backend.savedGames, <String>['2:checkpoint']);
    expect(backend.loadedGames, <int>[2]);
  });

  test('start new game request is forwarded to the backend', () async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);

    await controller.startBytes(Uint8List(4));
    await controller.startNewGame(skill: 2, episode: 1, map: 1);

    expect(backend.newGames, <String>['2:1:1']);
  });

  test('save and load reject slots outside engine save range', () async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);

    await controller.startBytes(Uint8List(4));

    await expectLater(controller.saveGame(10), throwsA(isA<Exception>()));
    await expectLater(controller.loadGame(-1), throwsA(isA<Exception>()));
  });

  test('tick records game quit without turning it into an error', () async {
    final backend = _FakeBackend()..quitOnTick = true;
    final controller = IwadController(backend: backend);

    await controller.startBytes(Uint8List(4));
    await controller.tick();

    expect(controller.hasQuit, isTrue);
    expect(controller.error, isNull);
  });

  test(
    'tick records frame copy errors instead of hanging on loading',
    () async {
      final backend = _FakeBackend()..throwOnCopyFrame = true;
      final controller = IwadController(backend: backend);

      await controller.startBytes(Uint8List(4));
      await controller.tick();

      expect(controller.error, contains('copy failed'));
    },
  );

  test('dispose shuts down the backend runtime', () async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);

    await controller.startBytes(Uint8List(4));
    controller.setKeyPressed(IwadInputKey.up, true);
    controller.dispose();

    expect(backend.keyEvents, <String>['173:true', '173:false']);
    expect(backend.shutdownCount, 1);
    expect(backend.isStarted, isFalse);
  });
}

final class _FakeBackend implements IwadBackend {
  final List<String> keyEvents = <String>[];
  final List<String> mouseEvents = <String>[];
  final List<IwadMouseDelta> polledMouseDeltas = <IwadMouseDelta>[];
  final List<int> weaponSlotRequests = <int>[];
  final List<String> savedGames = <String>[];
  final List<int> loadedGames = <int>[];
  final List<String> newGames = <String>[];
  bool _started = false;
  bool quitOnTick = false;
  bool throwOnCopyFrame = false;
  String? startedFileName;
  int? startedBytesLength;
  int shutdownCount = 0;
  int weaponSlot = 2;
  int ownedMask = 0;
  bool gameplayActive = true;
  bool playerDead = false;
  bool menuActive = false;
  bool menuPromptActive = false;

  @override
  int get height => 400;

  @override
  bool get isStarted => _started;

  @override
  bool get hasQuit => quitOnTick;

  @override
  bool get isSupported => true;

  @override
  String get lastError => '';

  @override
  int get currentWeaponSlot => weaponSlot;

  @override
  int get ownedWeaponSlotsMask => ownedMask;

  @override
  bool get isGameplayActive => gameplayActive;

  @override
  bool get isPlayerDead => playerDead;

  @override
  bool get isAdvanceActive => false;

  @override
  bool get isMenuActive => menuActive;

  @override
  bool get isMenuPromptActive => menuPromptActive;

  @override
  bool get isSaveNameActive => false;

  @override
  bool get isQuitConfirmActive => menuPromptActive;

  @override
  int get width => 640;

  @override
  int copyFrameRgba(Uint8List out) {
    if (throwOnCopyFrame) {
      throw StateError('copy failed');
    }
    return 0;
  }

  @override
  void keyEvent(int inputKey, bool pressed) {
    keyEvents.add('$inputKey:$pressed');
  }

  @override
  void requestWeaponSlot(int slot) {
    weaponSlotRequests.add(slot);
  }

  @override
  Future<void> saveGame(int slot, {String description = 'IWAD Runtime'}) async {
    savedGames.add('$slot:$description');
  }

  @override
  Future<void> loadGame(int slot) async {
    loadedGames.add(slot);
  }

  @override
  Future<void> startNewGame({
    int skill = 2,
    int episode = 1,
    int map = 1,
  }) async {
    newGames.add('$skill:$episode:$map');
  }

  @override
  void mouseEvent({
    required int buttons,
    required int deltaX,
    required int deltaY,
  }) {
    mouseEvents.add('$buttons:$deltaX:$deltaY');
  }

  @override
  bool setMouseCapture(bool enabled) => true;

  @override
  bool get isMouseCaptureActive => false;

  @override
  bool get usesPolledMouseCapture => polledMouseDeltas.isNotEmpty;

  @override
  IwadMouseDelta? pollMouseDelta() {
    if (polledMouseDeltas.isEmpty) {
      return null;
    }
    return polledMouseDeltas.removeAt(0);
  }

  @override
  void setSuspended(bool suspended) {}

  @override
  void shutdown() {
    shutdownCount++;
    _started = false;
  }

  @override
  Future<void> start(String iwadPath) async {
    _started = true;
  }

  @override
  Future<void> startBytes(
    Uint8List iwadBytes, {
    String fileName = 'game.wad',
  }) async {
    startedFileName = fileName;
    startedBytesLength = iwadBytes.length;
    _started = true;
  }

  @override
  bool tick() {
    if (quitOnTick) {
      _started = false;
      return false;
    }
    return true;
  }
}
