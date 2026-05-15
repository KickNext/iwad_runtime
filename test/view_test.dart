import 'dart:ui' as ui;

import 'package:iwad_runtime/src/backend.dart';
import 'package:iwad_runtime/src/controller.dart';
import 'package:iwad_runtime/src/desktop_controls.dart';
import 'package:iwad_runtime/src/fullscreen_controller.dart';
import 'package:iwad_runtime/src/input_key.dart';
import 'package:iwad_runtime/src/view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile look drag sends mouse delta without firing', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await _pumpMobileIwadView(tester, controller);
    await tester.dragFrom(const Offset(900, 360), const Offset(90, 40));
    await tester.pump();

    expect(backend.keyEvents, isEmpty);
    expect(backend.mouseEvents, isNotEmpty);
    final List<String> lastMouseEvent = backend.mouseEvents.last.split(':');
    expect(lastMouseEvent[0], '0');
    expect(int.parse(lastMouseEvent[1]).abs(), greaterThan(1500));
    expect(lastMouseEvent[2], '0');
  });

  testWidgets('mobile move stick strafes horizontally instead of turning', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await _pumpMobileIwadView(tester, controller);
    await tester.dragFrom(const Offset(104, 696), const Offset(70, 0));
    await tester.pump();

    expect(
      backend.keyEvents,
      containsAllInOrder(<String>[
        '${IwadInputKey.strafeRight}:true',
        '${IwadInputKey.strafeRight}:false',
      ]),
    );
    expect(backend.keyEvents, isNot(contains('${IwadInputKey.right}:true')));
  });

  testWidgets('mobile move stick outer ring does not trigger run', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await _pumpMobileIwadView(tester, controller);
    await tester.dragFrom(const Offset(120, 680), const Offset(86, 0));
    await tester.pump();

    expect(backend.keyEvents, isNot(contains('${IwadInputKey.shift}:true')));
    expect(backend.keyEvents, contains('${IwadInputKey.strafeRight}:true'));
    expect(backend.keyEvents, contains('${IwadInputKey.strafeRight}:false'));
  });

  testWidgets('mobile run button toggles shift and belongs to the dpad', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await _pumpMobileIwadView(tester, controller);
    final Offset runCenter = tester.getCenter(
      find.byKey(const ValueKey<String>('iwad_runtime_run_button')),
    );
    final Offset stickCenter = tester.getCenter(
      find.byKey(const ValueKey<String>('iwad_runtime_move_stick')),
    );
    expect(runCenter.dx, lessThan(stickCenter.dx));
    expect(runCenter.dy, lessThan(stickCenter.dy));
    expect((runCenter - stickCenter).distance, lessThan(160));

    await tester.tap(
      find.byKey(const ValueKey<String>('iwad_runtime_run_button')),
    );
    await tester.pump(const Duration(milliseconds: 60));
    expect(backend.keyEvents, <String>['${IwadInputKey.shift}:true']);
    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_run_button_active')),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 200));
    expect(backend.keyEvents, <String>['${IwadInputKey.shift}:true']);

    await tester.tap(
      find.byKey(const ValueKey<String>('iwad_runtime_run_button')),
    );
    await tester.pump(const Duration(milliseconds: 60));
    expect(backend.keyEvents, <String>[
      '${IwadInputKey.shift}:true',
      '${IwadInputKey.shift}:false',
    ]);
  });

  testWidgets('mobile gameplay controls stay light over the game view', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await _pumpMobileIwadView(tester, controller);

    final Color idleStickBase = _moveStickColorAt(tester, 0);
    final Color idleStickKnob = _moveStickColorAt(tester, 1);
    final Color actionButton = _buttonColorAroundText(tester, 'A');
    expect(idleStickBase.a, lessThanOrEqualTo(0.22));
    expect(idleStickKnob.a, lessThanOrEqualTo(0.14));
    expect(actionButton.a, lessThanOrEqualTo(0.34));

    final Offset stickCenter = tester.getCenter(
      find.byKey(const ValueKey<String>('iwad_runtime_move_stick')),
    );
    final TestGesture gesture = await tester.startGesture(stickCenter);
    await gesture.moveTo(stickCenter + const Offset(70, 0));
    await tester.pump();

    final Color activeStickBase = _moveStickColorAt(tester, 0);
    final Color activeStickKnob = _moveStickColorAt(tester, 1);
    expect(activeStickBase.a, lessThan(idleStickBase.a));
    expect(activeStickKnob.a, lessThan(idleStickKnob.a));
    await gesture.up();
  });

  testWidgets('mobile controls avoid debug shortcuts and use clear actions', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await _pumpMobileIwadView(tester, controller);

    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_move_stick')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_run_button')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(find.byIcon(Icons.menu), findsNothing);
    expect(find.byIcon(Icons.keyboard_return), findsNothing);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.map_outlined), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
    expect(find.byIcon(Icons.meeting_room), findsNothing);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('ENTER'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_weapon_current_slot')),
      findsOneWidget,
    );
    expect(find.text('2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_weapon_switcher')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_weapon_deck_panel')),
      findsNothing,
    );
    expect(find.text('FST'), findsNothing);
    expect(find.text('PST'), findsOneWidget);
    expect(find.text('SG'), findsNothing);
    expect(find.text('CG'), findsNothing);
    expect(find.text('RKT'), findsNothing);
    expect(find.text('PLS'), findsNothing);
    expect(find.text('BFG'), findsNothing);
  });

  testWidgets('mobile automap button sends tab only during gameplay', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await _pumpMobileIwadView(tester, controller);
    await tester.tap(find.byIcon(Icons.map_outlined));
    await tester.pump(const Duration(milliseconds: 60));

    expect(backend.keyEvents, <String>[
      '${IwadInputKey.tab}:true',
      '${IwadInputKey.tab}:false',
    ]);

    final menuBackend = _FakeBackend()
      ..gameplayActive = false
      ..menuActive = true;
    final menuController = IwadController(backend: menuBackend);
    await menuController.startBytes(Uint8List(4));
    await _pumpMobileIwadView(tester, menuController);
    expect(find.byIcon(Icons.map_outlined), findsNothing);
  });

  testWidgets(
    'mobile menu uses authentic cross navigation instead of gameplay overlay',
    (WidgetTester tester) async {
      final backend = _FakeBackend()
        ..gameplayActive = false
        ..menuActive = true;
      final controller = IwadController(backend: backend);
      await controller.startBytes(Uint8List(4));

      await _pumpMobileIwadView(tester, controller);

      expect(
        find.byKey(const ValueKey<String>('iwad_runtime_move_stick')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('iwad_runtime_menu_dpad')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('iwad_runtime_menu_dpad_cross')),
        findsOneWidget,
      );
      final Offset dpadCenter = tester.getCenter(
        find.byKey(const ValueKey<String>('iwad_runtime_menu_dpad')),
      );
      final Offset upCenter = tester.getCenter(
        find.byKey(const ValueKey<String>('iwad_runtime_menu_dpad_up')),
      );
      final Offset downCenter = tester.getCenter(
        find.byKey(const ValueKey<String>('iwad_runtime_menu_dpad_down')),
      );
      final Offset leftCenter = tester.getCenter(
        find.byKey(const ValueKey<String>('iwad_runtime_menu_dpad_left')),
      );
      final Offset rightCenter = tester.getCenter(
        find.byKey(const ValueKey<String>('iwad_runtime_menu_dpad_right')),
      );
      expect(upCenter.dy, lessThan(dpadCenter.dy - 42));
      expect(downCenter.dy, greaterThan(dpadCenter.dy + 42));
      expect(leftCenter.dx, lessThan(dpadCenter.dx - 42));
      expect(rightCenter.dx, greaterThan(dpadCenter.dx + 42));
      expect((leftCenter.dy - rightCenter.dy).abs(), lessThan(2));
      expect((upCenter.dx - downCenter.dx).abs(), lessThan(2));
      expect(find.byIcon(Icons.map_outlined), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('iwad_runtime_weapon_switcher')),
        findsNothing,
      );
      expect(find.text('A'), findsNothing);
      expect(find.text('B'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey<String>('iwad_runtime_menu_dpad_right')),
      );
      await tester.pump();

      expect(backend.keyEvents, <String>[
        '${IwadInputKey.right}:true',
        '${IwadInputKey.right}:false',
      ]);
    },
  );

  testWidgets('mobile menu supports swipe navigation and right tap confirm', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend()
      ..gameplayActive = false
      ..menuActive = true;
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await _pumpMobileIwadView(tester, controller);
    await tester.dragFrom(const Offset(620, 360), const Offset(0, -90));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(const Offset(940, 360));
    await tester.pump(const Duration(milliseconds: 60));

    expect(backend.keyEvents, <String>[
      '${IwadInputKey.up}:true',
      '${IwadInputKey.up}:false',
      '${IwadInputKey.enter}:true',
      '${IwadInputKey.enter}:false',
    ]);
    expect(backend.mouseEvents, isEmpty);
  });

  testWidgets('mobile menu prompt cluster sends escape yes and no', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend()
      ..gameplayActive = false
      ..menuActive = true
      ..menuPromptActive = true;
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await _pumpMobileIwadView(tester, controller);
    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsNothing);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('ENTER'), findsNothing);
    await tester.tap(find.text('Y').last);
    await tester.pump();
    await tester.tap(find.text('N').last);
    await tester.pump();

    expect(
      backend.keyEvents,
      containsAll(<String>[
        '${IwadInputKey.escape}:true',
        '${IwadInputKey.escape}:false',
        '${IwadInputKey.y}:true',
        '${IwadInputKey.y}:false',
        '${IwadInputKey.n}:true',
        '${IwadInputKey.n}:false',
      ]),
    );
  });

  testWidgets('mobile save-name entry exposes text controls', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend()
      ..gameplayActive = true
      ..menuActive = true
      ..saveNameActive = true;
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await _pumpMobileIwadView(tester, controller);

    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_save_name_keyboard')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_menu_dpad')),
      findsNothing,
    );
    expect(find.text('ENTER'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('iwad_runtime_save_key_D')),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(
      find.byKey(const ValueKey<String>('iwad_runtime_save_key_O')),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(
      find.byKey(const ValueKey<String>('iwad_runtime_save_key_M')),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(
      find.byKey(const ValueKey<String>('iwad_runtime_save_key_backspace')),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(
      find.byKey(const ValueKey<String>('iwad_runtime_save_key_ok')),
    );
    await tester.pump(const Duration(milliseconds: 60));

    expect(backend.keyEvents, <String>[
      '100:true',
      '100:false',
      '111:true',
      '111:false',
      '109:true',
      '109:false',
      '${IwadInputKey.backspace}:true',
      '${IwadInputKey.backspace}:false',
      '${IwadInputKey.enter}:true',
      '${IwadInputKey.enter}:false',
    ]);

    backend.keyEvents.clear();
    await tester.tap(
      find.byKey(const ValueKey<String>('iwad_runtime_save_key_cancel')),
    );
    await tester.pump(const Duration(milliseconds: 60));

    expect(backend.keyEvents, <String>[
      '${IwadInputKey.escape}:true',
      '${IwadInputKey.escape}:false',
    ]);
  });

  testWidgets('desktop save-name entry sends WASD as text characters', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend()
      ..gameplayActive = false
      ..menuActive = true
      ..saveNameActive = true;
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: IwadView(controller: controller),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);

    expect(backend.keyEvents, <String>[
      '${'w'.codeUnitAt(0)}:true',
      '${'w'.codeUnitAt(0)}:false',
      '${'a'.codeUnitAt(0)}:true',
      '${'a'.codeUnitAt(0)}:false',
      '${'s'.codeUnitAt(0)}:true',
      '${'s'.codeUnitAt(0)}:false',
      '${'d'.codeUnitAt(0)}:true',
      '${'d'.codeUnitAt(0)}:false',
    ]);
    expect(backend.keyEvents, isNot(contains('${IwadInputKey.up}:true')));
    expect(
      backend.keyEvents,
      isNot(contains('${IwadInputKey.strafeLeft}:true')),
    );
    expect(backend.keyEvents, isNot(contains('${IwadInputKey.down}:true')));
    expect(
      backend.keyEvents,
      isNot(contains('${IwadInputKey.strafeRight}:true')),
    );
  });

  testWidgets('mobile menu state wins over overlapping gameplay state', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend()
      ..gameplayActive = true
      ..menuActive = true;
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await _pumpMobileIwadView(tester, controller);

    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_menu_dpad')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_move_stick')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_run_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_weapon_switcher')),
      findsNothing,
    );
    expect(find.byIcon(Icons.map_outlined), findsNothing);
    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsNothing);

    await tester.dragFrom(const Offset(620, 360), const Offset(90, 0));
    await tester.pump(const Duration(milliseconds: 60));

    expect(backend.mouseEvents, isEmpty);
    expect(backend.keyEvents, <String>[
      '${IwadInputKey.right}:true',
      '${IwadInputKey.right}:false',
    ]);
  });

  testWidgets('mobile inactive game state opens menu by tapping the screen', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend()
      ..gameplayActive = false
      ..menuActive = false;
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await _pumpMobileIwadView(tester, controller);

    expect(find.byIcon(Icons.pause), findsNothing);
    expect(find.byIcon(Icons.map_outlined), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_idle_tap_to_menu_area')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_move_stick')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_run_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_menu_dpad')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_weapon_switcher')),
      findsNothing,
    );
    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsNothing);
    expect(find.text('ENTER'), findsNothing);

    await tester.tapAt(const Offset(620, 360));
    await tester.pump(const Duration(milliseconds: 60));

    expect(backend.keyEvents, <String>[
      '${IwadInputKey.escape}:true',
      '${IwadInputKey.escape}:false',
    ]);
  });

  testWidgets('mobile intermission tap advances instead of opening menu', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend()
      ..gameplayActive = false
      ..menuActive = false
      ..advanceActive = true;
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await _pumpMobileIwadView(tester, controller);

    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_idle_tap_to_menu_area')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_advance_tap_area')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.pause), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_weapon_switcher')),
      findsNothing,
    );

    await tester.tapAt(const Offset(620, 360));
    await tester.pump(const Duration(milliseconds: 60));

    expect(backend.keyEvents, <String>[
      '${IwadInputKey.fire}:true',
      '${IwadInputKey.fire}:false',
    ]);
  });

  testWidgets(
    'mobile death state hides gameplay controls and sends use on tap',
    (WidgetTester tester) async {
      final backend = _FakeBackend()..playerDead = true;
      final controller = IwadController(backend: backend);
      await controller.startBytes(Uint8List(4));

      await _pumpMobileIwadView(tester, controller);

      expect(
        find.byKey(const ValueKey<String>('iwad_runtime_death_tap_area')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('iwad_runtime_move_stick')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('iwad_runtime_run_button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('iwad_runtime_weapon_switcher')),
        findsNothing,
      );
      expect(find.byIcon(Icons.map_outlined), findsNothing);
      expect(find.text('A'), findsNothing);
      expect(find.text('ENTER'), findsNothing);
      expect(find.text('B'), findsOneWidget);

      await tester.tapAt(const Offset(640, 360));
      await tester.pump(const Duration(milliseconds: 60));

      expect(backend.keyEvents, <String>[
        '${IwadInputKey.use}:true',
        '${IwadInputKey.use}:false',
      ]);
    },
  );

  testWidgets('app lifecycle pause releases input and suspends runtime', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await _pumpMobileIwadView(tester, controller);
    backend.tickCount = 0;
    controller.setKeyPressed(IwadInputKey.up, true);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 60));

    expect(backend.keyEvents, <String>[
      '${IwadInputKey.up}:true',
      '${IwadInputKey.up}:false',
    ]);
    expect(backend.suspendEvents, <bool>[true]);
    expect(backend.tickCount, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 60));

    expect(backend.suspendEvents, <bool>[true, false]);
    expect(backend.tickCount, greaterThan(0));
  });

  testWidgets('desktop keeps keyboard and mouse capture path active', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: IwadView(controller: controller),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_move_stick')),
      findsNothing,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);

    final TestGesture mouse = await tester.createGesture(
      kind: ui.PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: const Offset(600, 360));
    await tester.pump();
    await mouse.down(const Offset(600, 360));
    await mouse.moveBy(const Offset(18, 0));
    await tester.pump(const Duration(milliseconds: 60));
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 80));

    expect(backend.keyEvents, <String>[
      '${IwadInputKey.up}:true',
      '${IwadInputKey.up}:false',
      '${IwadInputKey.fire}:true',
      '${IwadInputKey.fire}:false',
    ]);
    expect(backend.mouseCaptureEvents, contains(true));
    expect(backend.mouseEvents, isNotEmpty);
  });

  testWidgets('desktop left click fires through engine key input', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: IwadView(controller: controller),
      ),
    );

    final TestGesture mouse = await tester.createGesture(
      kind: ui.PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: const Offset(600, 360));
    await tester.pump();
    await mouse.down(const Offset(600, 360));
    await tester.pump();

    expect(backend.keyEvents, <String>['${IwadInputKey.fire}:true']);
    expect(backend.mouseCaptureEvents, contains(true));
    expect(backend.mouseEvents, isEmpty);

    await mouse.up();
    await tester.pump(const Duration(milliseconds: 80));

    expect(backend.keyEvents, <String>[
      '${IwadInputKey.fire}:true',
      '${IwadInputKey.fire}:false',
    ]);
    expect(backend.mouseEvents, isEmpty);
  });

  testWidgets('desktop mouse exit releases input without suspending runtime', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: IwadView(controller: controller),
      ),
    );

    final TestGesture mouse = await tester.createGesture(
      kind: ui.PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: const Offset(600, 360));
    await tester.pump();
    await mouse.down(const Offset(600, 360));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await mouse.moveTo(const Offset(-20, -20));
    await tester.pump();

    expect(backend.keyEvents, <String>[
      '${IwadInputKey.fire}:true',
      '${IwadInputKey.up}:true',
      '${IwadInputKey.fire}:false',
      '${IwadInputKey.up}:false',
    ]);
    expect(backend.mouseCaptureEvents, containsAllInOrder(<bool>[true, false]));
    expect(backend.suspendEvents, isEmpty);
  });

  testWidgets('desktop pointer lock keeps mouse active after region exit', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend()..mouseCaptureActive = true;
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: IwadView(controller: controller),
      ),
    );

    final TestGesture mouse = await tester.createGesture(
      kind: ui.PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: const Offset(600, 360));
    await tester.pump();
    await mouse.down(const Offset(600, 360));
    await mouse.moveTo(const Offset(-20, -20));
    await tester.pump();
    await mouse.moveBy(const Offset(16, 0));
    await tester.pump(const Duration(milliseconds: 60));

    expect(backend.mouseCaptureEvents, <bool>[true]);
    expect(_lastNonZeroMouseDelta(backend)[0].abs(), greaterThan(0));
    expect(backend.suspendEvents, isEmpty);
  });

  testWidgets('desktop polled pointer lock keeps mouse active after exit', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend()
      ..mouseCaptureActive = true
      ..usePolledMouseCapture = true;
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: IwadView(controller: controller),
      ),
    );

    final TestGesture mouse = await tester.createGesture(
      kind: ui.PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: const Offset(600, 360));
    await tester.pump();
    await mouse.down(const Offset(600, 360));
    await mouse.moveTo(const Offset(-20, -20));
    backend.polledMouseDeltas.add(const IwadMouseDelta(7, 5));
    await tester.pump(const Duration(milliseconds: 60));

    expect(backend.mouseCaptureEvents, <bool>[true]);
    expect(backend.mouseEvents, contains('0:98:0'));
    expect(backend.suspendEvents, isEmpty);
  });

  testWidgets(
    'desktop web capture request keeps mouse fire during exit churn',
    (WidgetTester tester) async {
      final backend = _FakeBackend()..usePolledMouseCapture = true;
      final controller = IwadController(backend: backend);
      await controller.startBytes(Uint8List(4));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: IwadView(controller: controller),
        ),
      );

      final TestGesture mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: const Offset(600, 360));
      await tester.pump();
      await mouse.down(const Offset(600, 360));
      await mouse.moveTo(const Offset(-20, -20));
      await tester.pump();

      expect(backend.mouseCaptureEvents, <bool>[true]);
      expect(backend.keyEvents, <String>['${IwadInputKey.fire}:true']);
      expect(
        backend.mouseEvents.every((String event) => event.startsWith('0:')),
        isTrue,
      );
      expect(backend.suspendEvents, isEmpty);

      await mouse.up();
      await tester.pump(const Duration(milliseconds: 80));

      expect(backend.keyEvents, <String>[
        '${IwadInputKey.fire}:true',
        '${IwadInputKey.fire}:false',
      ]);
      expect(
        backend.mouseEvents.every((String event) => event.startsWith('0:')),
        isTrue,
      );
    },
  );

  testWidgets('desktop web fallback uses Flutter mouse moves without lock', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend()..usePolledMouseCapture = true;
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: IwadView(controller: controller),
      ),
    );

    final TestGesture mouse = await tester.createGesture(
      kind: ui.PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: const Offset(600, 360));
    await tester.pump();
    await mouse.down(const Offset(600, 360));
    await mouse.moveBy(const Offset(16, 0));
    await tester.pump(const Duration(milliseconds: 60));

    expect(backend.mouseCaptureEvents, <bool>[true]);
    expect(_lastNonZeroMouseDelta(backend)[0].abs(), greaterThan(0));
    expect(backend.suspendEvents, isEmpty);
  });

  testWidgets('desktop original controls keep AD as turning', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: IwadView(
          controller: controller,
          desktopControlScheme: IwadDesktopControlScheme.original,
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);

    expect(backend.keyEvents, <String>[
      '${IwadInputKey.left}:true',
      '${IwadInputKey.left}:false',
      '${IwadInputKey.right}:true',
      '${IwadInputKey.right}:false',
    ]);
  });

  testWidgets('desktop modern controls map AD to strafe', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: IwadView(
          controller: controller,
          desktopControlScheme: IwadDesktopControlScheme.modern,
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);

    expect(backend.keyEvents, <String>[
      '${IwadInputKey.strafeLeft}:true',
      '${IwadInputKey.strafeLeft}:false',
      '${IwadInputKey.strafeRight}:true',
      '${IwadInputKey.strafeRight}:false',
    ]);
  });

  testWidgets('desktop defaults to modern controls', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: IwadView(controller: controller),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);

    expect(backend.keyEvents, <String>[
      '${IwadInputKey.strafeLeft}:true',
      '${IwadInputKey.strafeLeft}:false',
    ]);
  });

  testWidgets('desktop mouse only turns without forward movement', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: IwadView(controller: controller),
      ),
    );

    final TestGesture mouse = await tester.createGesture(
      kind: ui.PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: const Offset(600, 360));
    await tester.pump();
    await mouse.down(const Offset(600, 360));
    await mouse.moveBy(const Offset(18, 12));
    await tester.pump(const Duration(milliseconds: 60));
    await mouse.up();
    await tester.pump();

    final List<int> delta = _lastNonZeroMouseDelta(backend);
    expect(delta[0].abs(), greaterThan(0));
    expect(delta[1], 0);
  });

  testWidgets('desktop controls are hidden from the game view', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: IwadView(controller: controller),
      ),
    );

    expect(
      find.byKey(
        const ValueKey<String>('iwad_runtime_desktop_controls_original'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey<String>('iwad_runtime_desktop_controls_modern'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey<String>('iwad_runtime_desktop_fullscreen_toggle'),
      ),
      findsNothing,
    );
  });

  testWidgets('desktop F11 fullscreen hotkey does not reach engine', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));
    var fullscreenToggleCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: IwadView(
          controller: controller,
          onFullscreenToggle: () => fullscreenToggleCount++,
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.f11);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f11);

    expect(fullscreenToggleCount, 1);
    expect(backend.keyEvents, isEmpty);
  });

  testWidgets('fullscreen controller toggles on F11 and exits on engine quit', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);
    final fullscreenEvents = <bool>[];
    var exitRequested = false;
    await controller.startBytes(Uint8List(4));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: IwadView(
          controller: controller,
          fullscreenController: IwadCallbackFullscreenController(
            fullscreenEvents.add,
          ),
          onExitRequested: () => exitRequested = true,
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.f11);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f11);
    await tester.pump();

    expect(fullscreenEvents, <bool>[true]);

    backend.quitOnTick = true;
    await tester.pump(const Duration(milliseconds: 20));

    expect(controller.hasQuit, isTrue);
    expect(exitRequested, isTrue);
    expect(fullscreenEvents, <bool>[true, false]);
  });

  testWidgets('fullscreen controller exits when view is disposed', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);
    final fullscreenEvents = <bool>[];
    await controller.startBytes(Uint8List(4));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: IwadView(
          controller: controller,
          fullscreenController: IwadCallbackFullscreenController(
            fullscreenEvents.add,
          ),
        ),
      ),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f11);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f11);
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());

    expect(fullscreenEvents, <bool>[true, false]);
  });

  testWidgets('desktop control scheme hotkeys do not reach engine', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));
    final List<IwadDesktopControlScheme> modes = <IwadDesktopControlScheme>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: IwadView(
          controller: controller,
          desktopControlScheme: IwadDesktopControlScheme.modern,
          onDesktopControlSchemeChanged: modes.add,
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.f12);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f12);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyM);

    expect(modes, <IwadDesktopControlScheme>[
      IwadDesktopControlScheme.original,
      IwadDesktopControlScheme.original,
    ]);
    expect(backend.keyEvents, isEmpty);
  });

  testWidgets('mobile B button sends use', (WidgetTester tester) async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await _pumpMobileIwadView(tester, controller);
    await tester.tap(find.text('B'));
    await tester.pump();

    expect(backend.keyEvents, <String>[
      '${IwadInputKey.use}:true',
      '${IwadInputKey.use}:false',
    ]);
  });

  testWidgets('mobile A button sends fire', (WidgetTester tester) async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await _pumpMobileIwadView(tester, controller);
    await tester.tap(find.text('A'));
    await tester.pump();

    expect(backend.keyEvents, <String>[
      '${IwadInputKey.fire}:true',
      '${IwadInputKey.fire}:false',
    ]);
  });

  testWidgets('mobile weapon switcher requests ticcmd weapon slot', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend()..ownedMask = 0x7f;
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await _pumpMobileIwadView(tester, controller);
    final Offset hubCenter = tester.getCenter(
      find.byKey(const ValueKey<String>('iwad_runtime_weapon_current_slot')),
    );
    final TestGesture gesture = await tester.startGesture(hubCenter);
    await gesture.moveTo(hubCenter + const Offset(-32, 0));
    await tester.pump();

    final Offset weaponCenter = tester.getCenter(
      find.byKey(const ValueKey<String>('iwad_runtime_weapon_current_slot')),
    );
    final Offset actionCenter = tester.getCenter(find.text('A'));
    final Rect useRect = _buttonRectAroundText(tester, 'B');
    final Rect weaponRect = tester.getRect(
      find.byKey(const ValueKey<String>('iwad_runtime_weapon_current_slot')),
    );
    final Rect actionRect = _buttonRectAroundText(tester, 'A');
    expect(weaponCenter.dy, greaterThan(380));
    expect(weaponCenter.dy, lessThan(actionCenter.dy));
    expect(actionCenter.dy - weaponCenter.dy, lessThan(280));
    expect(weaponRect.overlaps(actionRect), isFalse);
    expect(weaponRect.overlaps(useRect), isFalse);
    expect(weaponRect.left, greaterThanOrEqualTo(actionRect.right + 24));
    expect(weaponRect.bottom, lessThanOrEqualTo(useRect.top - 24));

    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_weapon_radial_panel')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_weapon_deck_panel')),
      findsOneWidget,
    );
    expect(find.text('PISTOL'), findsOneWidget);

    await gesture.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey<String>('iwad_runtime_weapon_slot_3')),
      ),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(backend.weaponSlotRequests, <int>[3]);
    expect(backend.keyEvents, isEmpty);
  });

  testWidgets('mobile weapon switcher only exposes owned weapon slots', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend()
      ..ownedMask = 0x03
      ..weaponSlot = 2;
    final controller = IwadController(backend: backend);
    await controller.startBytes(Uint8List(4));

    await _pumpMobileIwadView(tester, controller);
    final Offset hubCenter = tester.getCenter(
      find.byKey(const ValueKey<String>('iwad_runtime_weapon_current_slot')),
    );
    final TestGesture gesture = await tester.startGesture(hubCenter);
    await gesture.moveTo(hubCenter + const Offset(-32, 0));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_weapon_slot_1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_weapon_slot_2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_weapon_slot_3')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_weapon_slot_4')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('iwad_runtime_weapon_deck_panel')),
      findsOneWidget,
    );
    expect(find.text('FST'), findsOneWidget);
    expect(find.text('PST'), findsWidgets);

    await gesture.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey<String>('iwad_runtime_weapon_slot_1')),
      ),
    );
    await gesture.up();
    await tester.pump();

    expect(backend.weaponSlotRequests, <int>[1]);
    expect(backend.keyEvents, isEmpty);
  });

  testWidgets('mobile look scales down on larger viewports', (
    WidgetTester tester,
  ) async {
    final compactBackend = _FakeBackend();
    final compactController = IwadController(backend: compactBackend);
    await compactController.startBytes(Uint8List(4));
    await _pumpMobileIwadView(
      tester,
      compactController,
      physicalSize: const Size(1200, 480),
    );
    await tester.dragFrom(const Offset(900, 240), const Offset(90, 0));
    await tester.pump();
    final int compactDelta = _lastMouseDeltaX(compactBackend).abs();

    final largeBackend = _FakeBackend();
    final largeController = IwadController(backend: largeBackend);
    await largeController.startBytes(Uint8List(4));
    await _pumpMobileIwadView(
      tester,
      largeController,
      physicalSize: const Size(1200, 800),
    );
    await tester.dragFrom(const Offset(900, 360), const Offset(90, 0));
    await tester.pump();
    final int largeDelta = _lastMouseDeltaX(largeBackend).abs();

    expect(largeDelta, lessThan(compactDelta));
  });

  testWidgets('escape is sent to engine instead of leaving the Flutter route', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend();
    final controller = IwadController(backend: backend);
    var exitRequested = false;
    await controller.startBytes(Uint8List(4));

    await _pumpMobileIwadView(
      tester,
      controller,
      onExitRequested: () => exitRequested = true,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(exitRequested, isFalse);
    expect(backend.keyEvents, <String>[
      '${IwadInputKey.escape}:true',
      '${IwadInputKey.escape}:false',
    ]);
  });

  testWidgets('native engine quit is the only path that requests route exit', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackend()..quitOnTick = true;
    final controller = IwadController(backend: backend);
    var exitRequested = false;
    await controller.startBytes(Uint8List(4));

    await _pumpMobileIwadView(
      tester,
      controller,
      onExitRequested: () => exitRequested = true,
    );
    await tester.pump(const Duration(milliseconds: 20));

    expect(controller.hasQuit, isTrue);
    expect(exitRequested, isTrue);
  });
}

Future<void> _pumpMobileIwadView(
  WidgetTester tester,
  IwadController controller, {
  VoidCallback? onExitRequested,
  Size physicalSize = const Size(1200, 800),
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.android),
      home: IwadView(controller: controller, onExitRequested: onExitRequested),
    ),
  );
}

Color _moveStickColorAt(WidgetTester tester, int index) {
  final Iterable<DecoratedBox> boxes = tester.widgetList<DecoratedBox>(
    find.descendant(
      of: find.byKey(const ValueKey<String>('iwad_runtime_move_stick')),
      matching: find.byType(DecoratedBox),
    ),
  );
  final BoxDecoration decoration =
      boxes.elementAt(index).decoration as BoxDecoration;
  return decoration.color!;
}

Color _buttonColorAroundText(WidgetTester tester, String text) {
  final DecoratedBox box = tester.widget<DecoratedBox>(
    find
        .ancestor(of: find.text(text), matching: find.byType(DecoratedBox))
        .last,
  );
  final BoxDecoration decoration = box.decoration as BoxDecoration;
  return decoration.color!;
}

Rect _buttonRectAroundText(WidgetTester tester, String text) {
  return tester.getRect(
    find
        .ancestor(of: find.text(text), matching: find.byType(DecoratedBox))
        .last,
  );
}

int _lastMouseDeltaX(_FakeBackend backend) {
  final List<String> lastMouseEvent = backend.mouseEvents.last.split(':');
  return int.parse(lastMouseEvent[1]);
}

List<int> _lastNonZeroMouseDelta(_FakeBackend backend) {
  for (final String event in backend.mouseEvents.reversed) {
    final List<String> parts = event.split(':');
    final int x = int.parse(parts[1]);
    final int y = int.parse(parts[2]);
    if (x != 0 || y != 0) {
      return <int>[x, y];
    }
  }
  return <int>[0, 0];
}

final class _FakeBackend implements IwadBackend {
  final List<String> keyEvents = <String>[];
  final List<String> mouseEvents = <String>[];
  final List<int> weaponSlotRequests = <int>[];
  final List<bool> suspendEvents = <bool>[];
  final List<bool> mouseCaptureEvents = <bool>[];
  final List<IwadMouseDelta> polledMouseDeltas = <IwadMouseDelta>[];
  bool _started = false;
  bool quitOnTick = false;
  int tickCount = 0;
  int shutdownCount = 0;
  int weaponSlot = 2;
  int ownedMask = 0;
  bool gameplayActive = true;
  bool playerDead = false;
  bool menuActive = false;
  bool menuPromptActive = false;
  bool saveNameActive = false;
  bool advanceActive = false;
  bool mouseCaptureActive = false;
  bool usePolledMouseCapture = false;

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
  bool get isAdvanceActive => advanceActive;

  @override
  bool get isMenuActive => menuActive;

  @override
  bool get isMenuPromptActive => menuPromptActive;

  @override
  bool get isSaveNameActive => saveNameActive;

  @override
  bool get isQuitConfirmActive => menuPromptActive;

  @override
  int get width => 640;

  @override
  int copyFrameRgba(Uint8List out) => 0;

  @override
  void keyEvent(int inputKey, bool pressed) {
    keyEvents.add('$inputKey:$pressed');
  }

  @override
  void requestWeaponSlot(int slot) {
    weaponSlotRequests.add(slot);
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
  bool setMouseCapture(bool enabled) {
    mouseCaptureEvents.add(enabled);
    if (!enabled) {
      mouseCaptureActive = false;
    }
    return true;
  }

  @override
  bool get isMouseCaptureActive => mouseCaptureActive;

  @override
  bool get usesPolledMouseCapture => usePolledMouseCapture;

  @override
  IwadMouseDelta? pollMouseDelta() {
    if (polledMouseDeltas.isEmpty) {
      return null;
    }
    return polledMouseDeltas.removeAt(0);
  }

  @override
  void setSuspended(bool suspended) {
    suspendEvents.add(suspended);
  }

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
    _started = true;
  }

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
  bool tick() {
    tickCount++;
    if (quitOnTick) {
      _started = false;
      return false;
    }
    return true;
  }
}
