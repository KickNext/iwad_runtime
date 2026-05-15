import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:iwad_runtime/iwad_runtime_bindings_generated.dart';

const int _inputKeyF10 = 0x80 + 0x44;
const int _inputKeyY = 121;

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/native_quit_smoke.dart <iwad_runtime_native.dll> <iwad>',
    );
    exitCode = 64;
    return;
  }

  final bindings = IwadRuntimeBindings(DynamicLibrary.open(args[0]));
  final iwad = args[1].toNativeUtf8();
  try {
    _expect(bindings.iwadr_start(iwad.cast<Char>()) != 0, 'start failed');
    _tick(bindings, 70);
    _expect(
      bindings.iwadr_audio_is_started() != 0,
      'audio device did not start',
    );
    _expect(
      bindings.iwadr_music_is_initialized() != 0,
      'OPL music module did not initialize',
    );
    _expect(
      bindings.iwadr_music_register_count() > 0,
      'engine did not register title music',
    );
    _expect(
      bindings.iwadr_music_play_count() > 0,
      'engine did not start title music',
    );
    _pumpAudio(bindings);
    _expect(
      bindings.iwadr_opl_mixed_frame_count() > 0,
      'OPL mixer did not receive audio callback frames',
    );
    _expect(
      bindings.iwadr_opl_nonzero_mix_count() > 0,
      'OPL mixer produced only silence',
    );
    _expect(
      bindings.iwadr_opl_peak_sample() > 512,
      'OPL mixer produced inaudibly low music',
    );
    _expect(
      bindings.iwadr_opl_peak_output_milli() > 180,
      'OPL music is too quiet in the final mix',
    );
    _expect(
      bindings.iwadr_audio_clip_count() == 0,
      'title music clipped before sound effects entered the mix',
    );
    _verifyAudioSuspendResume(bindings);
    stdout.writeln(
      'music: registered=${bindings.iwadr_music_register_count()} '
      'played=${bindings.iwadr_music_play_count()} '
      'sampleRate=${bindings.iwadr_audio_sample_rate()} '
      'callbacks=${bindings.iwadr_audio_callback_count()} '
      'maxCallbackFrames=${bindings.iwadr_audio_max_callback_frame_count()} '
      'frames=${bindings.iwadr_opl_mixed_frame_count()} '
      'nonzero=${bindings.iwadr_opl_nonzero_mix_count()} '
      'peak=${bindings.iwadr_opl_peak_sample()} '
      'oplOutputMilli=${bindings.iwadr_opl_peak_output_milli()} '
      'oplJumpMilli=${bindings.iwadr_opl_max_jump_milli()} '
      'mixOutputMilli=${bindings.iwadr_audio_peak_output_milli()} '
      'mixJumpMilli=${bindings.iwadr_audio_max_jump_milli()} '
      'clips=${bindings.iwadr_audio_clip_count()}',
    );
    final audioStartsBeforeQuit = bindings.iwadr_audio_started_sound_count();

    _tap(bindings, _inputKeyF10);
    _tick(bindings, 4);
    _tap(bindings, _inputKeyY);
    _tick(bindings, 4);

    _expect(
      bindings.iwadr_audio_started_sound_count() > audioStartsBeforeQuit,
      'menu key path did not trigger any sound effects',
    );
    _expect(bindings.iwadr_has_quit() != 0, 'quit flag was not set');
    _expect(bindings.iwadr_is_started() == 0, 'engine still reports started');

    _expect(bindings.iwadr_start(iwad.cast<Char>()) != 0, 'restart failed');
    _tick(bindings, 4);
    _expect(bindings.iwadr_is_started() != 0, 'engine did not restart');

    stdout.writeln('native quit/restart smoke passed');
  } finally {
    malloc.free(iwad);
  }
}

void _verifyAudioSuspendResume(IwadRuntimeBindings bindings) {
  final callbacksBeforeSuspend = bindings.iwadr_audio_callback_count();
  bindings.iwadr_set_suspended(1);
  sleep(const Duration(milliseconds: 300));
  final callbacksWhileSuspended = bindings.iwadr_audio_callback_count();
  _expect(
    bindings.iwadr_audio_is_suspended() != 0,
    'audio did not report suspended state',
  );
  _expect(
    callbacksWhileSuspended <= callbacksBeforeSuspend + 1,
    'audio callbacks continued while suspended: '
    '$callbacksBeforeSuspend -> $callbacksWhileSuspended',
  );

  bindings.iwadr_set_suspended(0);
  _expect(
    bindings.iwadr_audio_is_suspended() == 0,
    'audio did not leave suspended state',
  );

  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline) &&
      bindings.iwadr_audio_callback_count() <= callbacksWhileSuspended + 1) {
    _tick(bindings, 1);
    sleep(const Duration(milliseconds: 20));
  }
  _expect(
    bindings.iwadr_audio_callback_count() > callbacksWhileSuspended + 1,
    'audio callbacks did not resume after suspend',
  );
  stdout.writeln(
    'audio suspend/resume: callbacks=$callbacksBeforeSuspend'
    '->$callbacksWhileSuspended'
    '->${bindings.iwadr_audio_callback_count()}',
  );
}

void _tick(IwadRuntimeBindings bindings, int count) {
  for (var i = 0; i < count; i++) {
    bindings.iwadr_tick();
  }
}

void _pumpAudio(IwadRuntimeBindings bindings) {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline) &&
      bindings.iwadr_opl_mixed_frame_count() == 0) {
    _tick(bindings, 1);
    sleep(const Duration(milliseconds: 20));
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
