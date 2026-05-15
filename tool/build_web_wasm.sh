#!/usr/bin/env bash
set -euo pipefail

mkdir -p assets

sources="$(find src/doomgeneric -maxdepth 1 -name '*.c' \
  | grep -Ev 'doomgeneric_(xlib|win|sosox|soso|sdl|linuxvt|emscripten|allegro)\.c|i_(sdlmusic|sdlsound|allegromusic|allegrosound)\.c|gusconf\.c|icon\.c' \
  | sort \
  | tr '\n' ' ')"

emcc src/iwadr.c src/iwadr_audio.c src/iwadr_opl.c src/miniaudio.c src/opl/opl3.c src/opl/opl_queue.c $sources \
  -Isrc \
  -Isrc/doomgeneric \
  -Isrc/opl \
  -O2 \
  --profiling-funcs \
  -DNORMALUNIX \
  -DFEATURE_SOUND \
  -D_DEFAULT_SOURCE \
  -sMODULARIZE=1 \
  -sEXPORT_NAME=createIwadrModule \
  -sENVIRONMENT=web \
  -sALLOW_MEMORY_GROWTH=1 \
  -sFILESYSTEM=1 \
  -sEXPORTED_FUNCTIONS='["_malloc","_free","_iwadr_screen_width","_iwadr_screen_height","_iwadr_is_started","_iwadr_has_quit","_iwadr_last_error","_iwadr_set_temp_dir","_iwadr_shutdown","_iwadr_start","_iwadr_start_new_game","_iwadr_save_game","_iwadr_load_game","_iwadr_save_game_exists","_iwadr_save_game_size","_iwadr_save_generation","_iwadr_tick","_iwadr_copy_frame_rgba","_iwadr_key_event","_iwadr_request_weapon_slot","_iwadr_current_weapon_slot","_iwadr_owned_weapon_slots_mask","_iwadr_is_gameplay_active","_iwadr_is_player_dead","_iwadr_is_advance_active","_iwadr_is_menu_active","_iwadr_is_menu_prompt_active","_iwadr_is_save_name_active","_iwadr_is_quit_confirm_active","_iwadr_mouse_event","_iwadr_set_suspended","_iwadr_set_mouse_capture","_iwadr_poll_mouse_delta","_iwadr_audio_is_started","_iwadr_audio_set_suspended","_iwadr_audio_is_suspended","_iwadr_audio_started_sound_count","_iwadr_audio_active_voice_count","_iwadr_audio_sample_rate","_iwadr_audio_callback_count","_iwadr_audio_max_callback_frame_count","_iwadr_audio_clip_count","_iwadr_audio_peak_output_milli","_iwadr_audio_max_jump_milli","_iwadr_music_is_initialized","_iwadr_music_register_count","_iwadr_music_play_count","_iwadr_opl_mixed_frame_count","_iwadr_opl_nonzero_mix_count","_iwadr_opl_peak_sample","_iwadr_opl_peak_output_milli","_iwadr_opl_max_jump_milli"]' \
  -sEXPORTED_RUNTIME_METHODS='["ccall","FS","UTF8ToString","HEAPU8"]' \
  -lidbfs.js \
  -o assets/iwad_runtime_web.js

# Multiplayer hooks are intentionally not exported in the first support slice.
# The Dart web backend remains single-player until the external-tic boundary is
# validated natively and mirrored in the JS loader.
