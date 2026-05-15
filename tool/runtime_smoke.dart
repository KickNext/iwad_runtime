// ignore_for_file: avoid_print

import 'dart:typed_data';

import 'package:iwad_runtime/src/backend_native.dart';

void main(List<String> args) {
  if (args.length != 1) {
    throw ArgumentError('Usage: dart run tool/runtime_smoke.dart <iwad-path>');
  }

  final backend = NativeIwadBackend();
  backend.start(args.single);

  for (var i = 0; i < 4; i++) {
    backend.tick();
  }

  final frame = Uint8List(backend.width * backend.height * 4);
  final copied = backend.copyFrameRgba(frame);
  var coloredPixels = 0;
  var checksum = 0;

  for (var i = 0; i < frame.length; i += 4) {
    final r = frame[i];
    final g = frame[i + 1];
    final b = frame[i + 2];
    if (r != 0 || g != 0 || b != 0) {
      coloredPixels++;
    }
    checksum = (checksum + r * 3 + g * 5 + b * 7) & 0x7fffffff;
  }

  print('started=${backend.isStarted}');
  print('frame=${backend.width}x${backend.height}');
  print('copied=$copied');
  print('coloredPixels=$coloredPixels');
  print('checksum=$checksum');
}
