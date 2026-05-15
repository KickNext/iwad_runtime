import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iwad_runtime/src/backend_native.dart';

void main() {
  test('native data directory is stable under application support', () async {
    final Directory baseDirectory = await Directory.systemTemp.createTemp(
      'iwad_runtime_native_data_test_',
    );
    addTearDown(() async {
      if (await baseDirectory.exists()) {
        await baseDirectory.delete(recursive: true);
      }
    });

    final Directory first = await nativeIwadDataDirectory(
      baseDirectory: baseDirectory,
    );
    final Directory second = await nativeIwadDataDirectory(
      baseDirectory: baseDirectory,
    );

    expect(first.path, second.path);
    expect(
      first.path,
      '${baseDirectory.path}${Platform.pathSeparator}iwad_runtime',
    );
    expect(await first.exists(), isTrue);
  });
}
