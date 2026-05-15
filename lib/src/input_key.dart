import 'package:flutter/services.dart';

import 'desktop_controls.dart';

/// Original engine key codes.
abstract final class IwadInputKey {
  /// Turn or move right, depending on the current control scheme.
  static const int right = 0xae;

  /// Turn or move left, depending on the current control scheme.
  static const int left = 0xac;

  /// Move forward.
  static const int up = 0xad;

  /// Move backward.
  static const int down = 0xaf;

  /// Strafe left.
  static const int strafeLeft = 0xa0;

  /// Strafe right.
  static const int strafeRight = 0xa1;

  /// Use/open action.
  static const int use = 0xa2;

  /// Fire action.
  static const int fire = 0xa3;

  /// Escape/menu key.
  static const int escape = 27;

  /// Enter/confirm key.
  static const int enter = 13;

  /// Tab key.
  static const int tab = 9;

  /// Backspace key.
  static const int backspace = 0x7f;

  /// Pause key.
  static const int pause = 0xff;

  /// F10 key used by the original engine quit flow.
  static const int f10 = 0x80 + 0x44;

  /// Equals key.
  static const int equals = 0x3d;

  /// Minus key.
  static const int minus = 0x2d;

  /// Shift modifier key.
  static const int shift = 0x80 + 0x36;

  /// Control modifier key.
  static const int control = 0x80 + 0x1d;

  /// Alt modifier key.
  static const int alt = 0x80 + 0x38;

  /// Y key used by confirmation prompts.
  static const int y = 121;

  /// N key used by confirmation prompts.
  static const int n = 110;

  /// Maps a Flutter logical key to an engine key code.
  static int? fromLogicalKey(
    LogicalKeyboardKey key, {
    IwadDesktopControlScheme desktopControlScheme =
        IwadDesktopControlScheme.modern,
  }) {
    if (key == LogicalKeyboardKey.keyD &&
        desktopControlScheme == IwadDesktopControlScheme.modern) {
      return strafeRight;
    }
    if (key == LogicalKeyboardKey.keyA &&
        desktopControlScheme == IwadDesktopControlScheme.modern) {
      return strafeLeft;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyD) {
      return right;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyA) {
      return left;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyW) {
      return up;
    }
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.keyS) {
      return down;
    }
    if (key == LogicalKeyboardKey.space) {
      return use;
    }
    if (key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight) {
      return fire;
    }
    if (key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight) {
      return shift;
    }
    if (key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight) {
      return alt;
    }
    if (key == LogicalKeyboardKey.escape) {
      return escape;
    }
    if (key == LogicalKeyboardKey.enter) {
      return enter;
    }
    if (key == LogicalKeyboardKey.tab) {
      return tab;
    }
    if (key == LogicalKeyboardKey.backspace) {
      return backspace;
    }
    if (key == LogicalKeyboardKey.f10) {
      return f10;
    }
    if (key == LogicalKeyboardKey.minus) {
      return minus;
    }
    if (key == LogicalKeyboardKey.equal) {
      return equals;
    }

    final String? character = key.keyLabel.length == 1 ? key.keyLabel : null;
    if (character == null) {
      return null;
    }
    return character.toLowerCase().codeUnitAt(0);
  }

  /// Maps a key event while the engine is editing a save-game name.
  static int? fromSaveNameKeyEvent(KeyEvent event) {
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      return escape;
    }
    if (key == LogicalKeyboardKey.enter) {
      return enter;
    }
    if (key == LogicalKeyboardKey.backspace) {
      return backspace;
    }
    if (key == LogicalKeyboardKey.space) {
      return ' '.codeUnitAt(0);
    }

    final String character = event.character ?? key.keyLabel;
    if (character.length != 1) {
      return null;
    }
    final int codeUnit = character.toLowerCase().codeUnitAt(0);
    if (codeUnit < 32 || codeUnit > 127) {
      return null;
    }
    return codeUnit;
  }
}
