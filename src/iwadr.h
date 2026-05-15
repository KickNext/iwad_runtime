#ifndef IWADR_H_
#define IWADR_H_

#include <stdint.h>

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define IWADR_SCREEN_WIDTH 640
#define IWADR_SCREEN_HEIGHT 400
#define IWADR_BYTES_PER_PIXEL 4

FFI_PLUGIN_EXPORT int iwadr_screen_width(void);
FFI_PLUGIN_EXPORT int iwadr_screen_height(void);
FFI_PLUGIN_EXPORT int iwadr_is_started(void);
FFI_PLUGIN_EXPORT int iwadr_has_quit(void);
FFI_PLUGIN_EXPORT const char* iwadr_last_error(void);
FFI_PLUGIN_EXPORT void iwadr_set_temp_dir(const char* temp_dir);
FFI_PLUGIN_EXPORT void iwadr_shutdown(void);
FFI_PLUGIN_EXPORT int iwadr_start(const char* iwad_path);
FFI_PLUGIN_EXPORT int iwadr_multiplayer_is_supported(void);
FFI_PLUGIN_EXPORT int iwadr_ticcmd_size(void);
FFI_PLUGIN_EXPORT int iwadr_max_players(void);
FFI_PLUGIN_EXPORT int iwadr_start_multiplayer(const char* iwad_path,
                                              int player_count,
                                              int local_player,
                                              int deathmatch,
                                              int episode,
                                              int map,
                                              int skill,
                                              int no_monsters,
                                              int fast_monsters,
                                              int respawn_monsters,
                                              int ticdup_value);
FFI_PLUGIN_EXPORT int iwadr_build_local_ticcmd(uint8_t* out, int out_len);
FFI_PLUGIN_EXPORT int iwadr_run_synchronized_tic(const uint8_t* commands,
                                                 const int* present,
                                                 int player_count);
FFI_PLUGIN_EXPORT uint32_t iwadr_sync_checksum(void);
FFI_PLUGIN_EXPORT int iwadr_start_new_game(int skill, int episode, int map);
FFI_PLUGIN_EXPORT int iwadr_save_game(int slot, const char* description);
FFI_PLUGIN_EXPORT int iwadr_load_game(int slot);
FFI_PLUGIN_EXPORT int iwadr_save_game_exists(int slot);
FFI_PLUGIN_EXPORT int iwadr_save_game_size(int slot);
FFI_PLUGIN_EXPORT int iwadr_save_generation(void);
FFI_PLUGIN_EXPORT int iwadr_tick(void);
FFI_PLUGIN_EXPORT int iwadr_copy_frame_rgba(uint8_t* out, int out_len);
FFI_PLUGIN_EXPORT void iwadr_key_event(int input_key, int pressed);
FFI_PLUGIN_EXPORT void iwadr_request_weapon_slot(int slot);
FFI_PLUGIN_EXPORT int iwadr_current_weapon_slot(void);
FFI_PLUGIN_EXPORT int iwadr_owned_weapon_slots_mask(void);
FFI_PLUGIN_EXPORT int iwadr_is_gameplay_active(void);
FFI_PLUGIN_EXPORT int iwadr_is_player_dead(void);
FFI_PLUGIN_EXPORT int iwadr_is_advance_active(void);
FFI_PLUGIN_EXPORT int iwadr_is_menu_active(void);
FFI_PLUGIN_EXPORT int iwadr_is_menu_prompt_active(void);
FFI_PLUGIN_EXPORT int iwadr_is_save_name_active(void);
FFI_PLUGIN_EXPORT int iwadr_is_quit_confirm_active(void);
FFI_PLUGIN_EXPORT void iwadr_mouse_event(int buttons, int delta_x, int delta_y);
FFI_PLUGIN_EXPORT void iwadr_set_suspended(int suspended);
FFI_PLUGIN_EXPORT int iwadr_set_mouse_capture(int enabled);
FFI_PLUGIN_EXPORT int iwadr_poll_mouse_delta(int* delta_x, int* delta_y);
FFI_PLUGIN_EXPORT int iwadr_audio_is_started(void);
FFI_PLUGIN_EXPORT void iwadr_audio_set_suspended(int suspended);
FFI_PLUGIN_EXPORT int iwadr_audio_is_suspended(void);
FFI_PLUGIN_EXPORT int iwadr_audio_started_sound_count(void);
FFI_PLUGIN_EXPORT int iwadr_audio_active_voice_count(void);
FFI_PLUGIN_EXPORT int iwadr_audio_sample_rate(void);
FFI_PLUGIN_EXPORT int iwadr_audio_callback_count(void);
FFI_PLUGIN_EXPORT int iwadr_audio_max_callback_frame_count(void);
FFI_PLUGIN_EXPORT int iwadr_audio_clip_count(void);
FFI_PLUGIN_EXPORT int iwadr_audio_peak_output_milli(void);
FFI_PLUGIN_EXPORT int iwadr_audio_max_jump_milli(void);
FFI_PLUGIN_EXPORT int iwadr_music_is_initialized(void);
FFI_PLUGIN_EXPORT int iwadr_music_register_count(void);
FFI_PLUGIN_EXPORT int iwadr_music_play_count(void);
FFI_PLUGIN_EXPORT int iwadr_opl_mixed_frame_count(void);
FFI_PLUGIN_EXPORT int iwadr_opl_nonzero_mix_count(void);
FFI_PLUGIN_EXPORT int iwadr_opl_peak_sample(void);
FFI_PLUGIN_EXPORT int iwadr_opl_peak_output_milli(void);
FFI_PLUGIN_EXPORT int iwadr_opl_max_jump_milli(void);

#ifdef __cplusplus
}
#endif

#endif  // IWADR_H_
