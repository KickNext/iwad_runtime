import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:iwad_runtime/iwad_runtime_bindings_generated.dart';

void main(List<String> args) {
  if (args.length != 4 || (args[0] != 'save' && args[0] != 'load')) {
    stderr.writeln(
      'Usage: dart run tool/native_save_smoke.dart <save|load> '
      '<iwad_runtime library> <iwad> <data-dir>',
    );
    exitCode = 64;
    return;
  }

  final String mode = args[0];
  final bindings = IwadRuntimeBindings(DynamicLibrary.open(args[1]));
  final Directory dataDirectory = Directory(args[3])
    ..createSync(recursive: true);
  final Pointer<Utf8> dataDir = dataDirectory.path.toNativeUtf8();
  final Pointer<Utf8> iwad = args[2].toNativeUtf8();
  final Pointer<Utf8> description = 'IWAD Runtime Smoke'.toNativeUtf8();

  try {
    bindings.iwadr_set_temp_dir(dataDir.cast<Char>());
    _expect(bindings.iwadr_start(iwad.cast<Char>()) != 0, 'start failed');

    if (mode == 'save') {
      _expect(
        bindings.iwadr_start_new_game(2, 1, 1) != 0,
        'new game failed: ${_lastError(bindings)}',
      );
      _tick(bindings, 8);
      final generationBefore = bindings.iwadr_save_generation();
      _expect(
        bindings.iwadr_save_game(0, description.cast<Char>()) != 0,
        'save failed: ${_lastError(bindings)}',
      );
      _expect(
        bindings.iwadr_save_generation() > generationBefore,
        'save generation did not advance',
      );
      _expect(bindings.iwadr_save_game_exists(0) != 0, 'save file missing');
      _expect(bindings.iwadr_save_game_size(0) > 0, 'save file is empty');
      stdout.writeln(
        'native save smoke saved size=${bindings.iwadr_save_game_size(0)} '
        'generation=${bindings.iwadr_save_generation()}',
      );
      return;
    }

    _expect(bindings.iwadr_save_game_exists(0) != 0, 'save file missing');
    _expect(bindings.iwadr_save_game_size(0) > 0, 'save file is empty');
    _expect(
      bindings.iwadr_load_game(0) != 0,
      'load failed: ${_lastError(bindings)}',
    );
    _tick(bindings, 4);
    _expect(bindings.iwadr_is_gameplay_active() != 0, 'loaded game inactive');
    stdout.writeln(
      'native save smoke loaded size=${bindings.iwadr_save_game_size(0)}',
    );
  } finally {
    bindings.iwadr_shutdown();
    malloc.free(description);
    malloc.free(iwad);
    malloc.free(dataDir);
  }
}

void _tick(IwadRuntimeBindings bindings, int count) {
  for (var i = 0; i < count; i++) {
    bindings.iwadr_tick();
  }
}

String _lastError(IwadRuntimeBindings bindings) {
  final Pointer<Char> message = bindings.iwadr_last_error();
  if (message == nullptr) {
    return '';
  }
  return message.cast<Utf8>().toDartString();
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
