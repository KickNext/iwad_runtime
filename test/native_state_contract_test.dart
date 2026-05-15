import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native gameplay state excludes demo playback and advanced demo', () {
    final source = File('src/iwadr.c').readAsStringSync();
    final function = _functionBody(source, 'iwadr_is_gameplay_active');

    expect(function, contains('gamestate == GS_LEVEL'));
    expect(function, contains('!menuactive'));
    expect(function, contains('!demoplayback'));
    expect(function, contains('!advancedemo'));
  });

  test('native menu prompt state tracks any input prompt', () {
    final source = File('src/iwadr.c').readAsStringSync();
    final function = _functionBody(source, 'iwadr_is_menu_prompt_active');

    expect(function, contains('menuactive'));
    expect(function, contains('messageToPrint'));
    expect(function, contains('messageNeedsInput'));
    expect(function, isNot(contains('M_QuitResponse')));
  });

  test('native save-name state tracks save string entry', () {
    final source = File('src/iwadr.c').readAsStringSync();
    final function = _functionBody(source, 'iwadr_is_save_name_active');

    expect(function, contains('menuactive'));
    expect(function, contains('saveStringEnter'));
  });

  test('native advance state tracks intermission and finale only', () {
    final source = File('src/iwadr.c').readAsStringSync();
    final function = _functionBody(source, 'iwadr_is_advance_active');

    expect(function, contains('GS_INTERMISSION'));
    expect(function, contains('GS_FINALE'));
    expect(function, isNot(contains('GS_DEMOSCREEN')));
  });

  test('native player-dead state tracks player state during gameplay', () {
    final source = File('src/iwadr.c').readAsStringSync();
    final function = _functionBody(source, 'iwadr_is_player_dead');

    expect(function, contains('iwadr_is_gameplay_active()'));
    expect(function, contains('players[consoleplayer].playerstate'));
    expect(function, contains('PST_DEAD'));
  });

  test('native suspend state pauses ticks and audio', () {
    final source = File('src/iwadr.c').readAsStringSync();
    final tickFunction = _functionBody(source, 'iwadr_tick');
    final suspendFunction = _functionBody(source, 'iwadr_set_suspended');

    expect(tickFunction, contains('iwadr_suspended'));
    expect(
      tickFunction.indexOf('if (iwadr_suspended)'),
      lessThan(tickFunction.indexOf('doomgeneric_Tick();')),
    );
    expect(suspendFunction, contains('iwadr_audio_set_suspended'));
  });

  test('native audio suspend stops and restarts miniaudio device', () {
    final source = File('src/iwadr_audio.c').readAsStringSync();
    final function = _functionBody(source, 'iwadr_audio_set_suspended');

    expect(function, contains('ma_device_stop'));
    expect(function, contains('ma_device_start'));
    expect(function, contains('iwadr_audio_started'));
  });

  test('native shutdown delegates to engine exit path', () {
    final source = File('src/iwadr.c').readAsStringSync();
    final function = _functionBody(source, 'iwadr_shutdown');

    expect(function, contains('I_Quit()'));
  });

  test('native default config dir follows Flutter writable temp dir', () {
    final source = File('src/doomgeneric/m_config.c').readAsStringSync();
    final function = _functionBody(source, 'GetDefaultConfigDir');

    expect(function, contains('getenv("IWADR_TEMP")'));
    expect(function, contains("tempdir[0] != '\\0'"));
    expect(function, contains('M_StringDuplicate(tempdir)'));
  });

  test('native multiplayer hooks are declared in the public C header', () {
    final header = File('src/iwadr.h').readAsStringSync();

    expect(header, contains('iwadr_multiplayer_is_supported'));
    expect(header, contains('iwadr_ticcmd_size'));
    expect(header, contains('iwadr_max_players'));
    expect(header, contains('iwadr_start_multiplayer'));
    expect(header, contains('iwadr_build_local_ticcmd'));
    expect(header, contains('iwadr_run_synchronized_tic'));
    expect(header, contains('iwadr_sync_checksum'));
  });

  test('native save hooks are declared in the public C header', () {
    final header = File('src/iwadr.h').readAsStringSync();

    expect(header, contains('iwadr_save_game'));
    expect(header, contains('iwadr_load_game'));
    expect(header, contains('iwadr_start_new_game'));
    expect(header, contains('iwadr_save_game_exists'));
    expect(header, contains('iwadr_save_game_size'));
    expect(header, contains('iwadr_save_generation'));
  });

  test('native savegame directory is scoped by IWAD content hash', () {
    final source = File('src/doomgeneric/m_config.c').readAsStringSync();
    final function = _functionBody(source, 'M_GetSaveGameDir');
    final scopeFunction = _functionBody(source, 'M_SaveGameIWADScope');
    final hashFunction = _functionBody(source, 'M_IWADContentHash');

    expect(scopeFunction, contains('basename'));
    expect(scopeFunction, contains('M_IWADContentHash'));
    expect(hashFunction, contains('fopen'));
    expect(hashFunction, contains('SHA1_Init'));
    expect(hashFunction, contains('SHA1_Update'));
    expect(function, contains('M_SaveGameIWADScope'));
    expect(function, contains('"savegame"'));
    expect(function, isNot(contains('".savegame/"')));
  });

  test('native savegame directory receives the concrete IWAD file path', () {
    final source = File('src/doomgeneric/d_main.c').readAsStringSync();
    final function = _functionBody(source, 'D_DoomMain');

    expect(function, contains('M_GetSaveGameDir(iwadfile)'));
    expect(function, isNot(contains('M_GetSaveGameDir(D_SaveGameIWADName')));
  });

  test('native synchronized tick does not advance with missing commands', () {
    final source = File('src/iwadr.c').readAsStringSync();
    final body = _functionBody(source, 'iwadr_run_synchronized_tic');

    expect(body, contains('present[i] == 0'));
    expect(body, contains('return 0;'));
    expect(body, contains('iwadr_external_tic_mode'));
  });
}

String _functionBody(String source, String name) {
  final pattern = RegExp(
    '(?:int|void|(?:static\\s+)?char\\s*\\*)\\s*$name\\s*\\([^)]*\\)\\s*\\{(?<body>.*?)\\n\\}',
    dotAll: true,
  );
  final match = pattern.firstMatch(source);
  expect(match, isNotNull, reason: '$name should exist in src/iwadr.c');
  return match!.namedGroup('body')!;
}
