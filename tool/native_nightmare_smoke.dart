import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:iwad_runtime/iwad_runtime_bindings_generated.dart';

const int _inputKeyDown = 0xaf;
const int _inputKeyEnter = 13;
const int _inputKeyEscape = 27;
const int _inputKeyY = 121;

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/native_nightmare_smoke.dart <iwad_runtime_native.dll> <iwad>',
    );
    exitCode = 64;
    return;
  }

  final bindings = IwadRuntimeBindings(DynamicLibrary.open(args[0]));
  final iwad = args[1].toNativeUtf8();
  try {
    _expect(bindings.iwadr_start(iwad.cast<Char>()) != 0, 'start failed');
    _tick(bindings, 70);

    _tap(bindings, _inputKeyEscape);
    _expect(
      _tickUntil(bindings, () => bindings.iwadr_is_menu_active() != 0),
      'main menu did not open from title/demo tap',
    );

    _tap(bindings, _inputKeyEnter); // New Game.
    _tick(bindings, 6);
    _tap(bindings, _inputKeyEnter); // First episode.
    _tick(bindings, 6);
    for (var i = 0; i < 2; i++) {
      _tap(bindings, _inputKeyDown);
      _tick(bindings, 2);
    }
    _tap(bindings, _inputKeyEnter); // Nightmare prompt.
    _expect(
      _tickUntil(bindings, () => bindings.iwadr_is_menu_prompt_active() != 0),
      'Nightmare confirmation prompt did not appear',
    );
    _tap(bindings, _inputKeyY);

    _expect(
      _tickUntil(bindings, () => bindings.iwadr_is_gameplay_active() != 0),
      'Nightmare did not enter gameplay after Y',
    );
    _expect(
      bindings.iwadr_is_menu_active() == 0,
      'menu still active after Nightmare start',
    );

    stdout.writeln('native Nightmare Y smoke passed');
  } finally {
    bindings.iwadr_shutdown();
    malloc.free(iwad);
  }
}

bool _tickUntil(IwadRuntimeBindings bindings, bool Function() predicate) {
  for (var i = 0; i < 90; i++) {
    if (predicate()) {
      return true;
    }
    bindings.iwadr_tick();
    sleep(const Duration(milliseconds: 16));
  }
  return predicate();
}

void _tick(IwadRuntimeBindings bindings, int count) {
  for (var i = 0; i < count; i++) {
    bindings.iwadr_tick();
  }
}

void _tap(IwadRuntimeBindings bindings, int inputKey) {
  bindings.iwadr_key_event(inputKey, 1);
  bindings.iwadr_tick();
  bindings.iwadr_key_event(inputKey, 0);
  bindings.iwadr_tick();
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
