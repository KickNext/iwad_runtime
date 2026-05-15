import 'package:iwad_runtime/src/input_key.dart';
import 'package:iwad_runtime/src/desktop_controls.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps movement keys to engine key codes', () {
    expect(
      IwadInputKey.fromLogicalKey(LogicalKeyboardKey.arrowUp),
      IwadInputKey.up,
    );
    expect(
      IwadInputKey.fromLogicalKey(LogicalKeyboardKey.keyW),
      IwadInputKey.up,
    );
    expect(
      IwadInputKey.fromLogicalKey(LogicalKeyboardKey.arrowLeft),
      IwadInputKey.left,
    );
    expect(
      IwadInputKey.fromLogicalKey(LogicalKeyboardKey.keyA),
      IwadInputKey.strafeLeft,
    );
  });

  test('maps action keys to engine key codes', () {
    expect(
      IwadInputKey.fromLogicalKey(LogicalKeyboardKey.space),
      IwadInputKey.use,
    );
    expect(
      IwadInputKey.fromLogicalKey(LogicalKeyboardKey.controlLeft),
      IwadInputKey.fire,
    );
    expect(
      IwadInputKey.fromLogicalKey(LogicalKeyboardKey.escape),
      IwadInputKey.escape,
    );
    expect(
      IwadInputKey.fromLogicalKey(LogicalKeyboardKey.enter),
      IwadInputKey.enter,
    );
    expect(
      IwadInputKey.fromLogicalKey(LogicalKeyboardKey.keyY),
      IwadInputKey.y,
    );
    expect(
      IwadInputKey.fromLogicalKey(LogicalKeyboardKey.keyN),
      IwadInputKey.n,
    );
    expect(
      IwadInputKey.fromLogicalKey(LogicalKeyboardKey.f10),
      IwadInputKey.f10,
    );
  });

  test('maps desktop movement by selected control scheme', () {
    expect(
      IwadInputKey.fromLogicalKey(
        LogicalKeyboardKey.keyA,
        desktopControlScheme: IwadDesktopControlScheme.original,
      ),
      IwadInputKey.left,
    );
    expect(
      IwadInputKey.fromLogicalKey(
        LogicalKeyboardKey.keyD,
        desktopControlScheme: IwadDesktopControlScheme.original,
      ),
      IwadInputKey.right,
    );

    expect(
      IwadInputKey.fromLogicalKey(
        LogicalKeyboardKey.keyA,
        desktopControlScheme: IwadDesktopControlScheme.modern,
      ),
      IwadInputKey.strafeLeft,
    );
    expect(
      IwadInputKey.fromLogicalKey(
        LogicalKeyboardKey.keyD,
        desktopControlScheme: IwadDesktopControlScheme.modern,
      ),
      IwadInputKey.strafeRight,
    );
  });

  test('maps save-name text input as printable characters', () {
    final KeyDownEvent wEvent = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyW,
      logicalKey: LogicalKeyboardKey.keyW,
      character: 'w',
      timeStamp: Duration.zero,
    );
    final KeyDownEvent aEvent = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyA,
      logicalKey: LogicalKeyboardKey.keyA,
      character: 'a',
      timeStamp: Duration.zero,
    );

    expect(IwadInputKey.fromSaveNameKeyEvent(wEvent), 'w'.codeUnitAt(0));
    expect(IwadInputKey.fromSaveNameKeyEvent(aEvent), 'a'.codeUnitAt(0));
  });
}
