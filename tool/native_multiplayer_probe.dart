import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:iwad_runtime/iwad_runtime_bindings_generated.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'usage: dart run tool/native_multiplayer_probe.dart <library> <iwad>',
    );
    exitCode = 64;
    return;
  }

  final bindings = IwadRuntimeBindings(DynamicLibrary.open(args[0]));
  final iwad = args[1].toNativeUtf8();
  try {
    _expect(
      bindings.iwadr_multiplayer_is_supported() != 0,
      'multiplayer hooks unsupported',
    );
    _expect(
      bindings.iwadr_start_multiplayer(
            iwad.cast<Char>(),
            2,
            0,
            0,
            1,
            1,
            2,
            0,
            0,
            0,
            1,
          ) !=
          0,
      'start failed',
    );

    final size = bindings.iwadr_ticcmd_size();
    final command = calloc<Uint8>(size);
    final commands = calloc<Uint8>(size * 2);
    final present = calloc<Int>(2);
    try {
      present[0] = 1;
      present[1] = 1;
      for (var i = 0; i < 35; i++) {
        final copied = bindings.iwadr_build_local_ticcmd(command, size);
        _expect(copied == size, 'local command size mismatch');
        final commandBytes = command.asTypedList(size);
        final commandSet = commands.asTypedList(size * 2);
        commandSet.setRange(0, size, commandBytes);
        commandSet.setRange(size, size * 2, Uint8List(size));
        final result = bindings.iwadr_run_synchronized_tic(
          commands,
          present,
          2,
        );
        _expect(result == 1, 'synchronized tick did not advance: $result');
      }
      stdout.writeln(
        'multiplayer_probe checksum=${bindings.iwadr_sync_checksum()} '
        'ticcmd_size=$size',
      );
    } finally {
      calloc.free(command);
      calloc.free(commands);
      calloc.free(present);
    }
  } finally {
    bindings.iwadr_shutdown();
    calloc.free(iwad);
  }
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
