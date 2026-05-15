#include "iwadr.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#if _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <errno.h>
#include <sys/time.h>
#include <unistd.h>
#if defined(IWADR_HAS_X11)
#include <X11/Xlib.h>
#endif
#endif

#include "doomgeneric/d_event.h"
#include "doomgeneric/d_loop.h"
#include "doomgeneric/d_main.h"
#include "doomgeneric/d_ticcmd.h"
#include "doomgeneric/doomgeneric.h"
#include "doomgeneric/doomstat.h"
#include "doomgeneric/g_game.h"
#include "doomgeneric/i_system.h"
#include "doomgeneric/i_video.h"
#include "doomgeneric/m_menu.h"
#include "doomgeneric/p_saveg.h"
#include "doomgeneric/s_sound.h"

extern int messageToPrint;
extern boolean messageNeedsInput;
extern void (*messageRoutine)(int response);
extern boolean advancedemo;
extern int saveStringEnter;
void M_QuitResponse(int key);
void D_Display(void);

#define IWADR_EVENT_QUEUE_CAPACITY 128

typedef struct IwadrKeyEvent {
  int pressed;
  unsigned char key;
} IwadrKeyEvent;

static IwadrKeyEvent iwadr_events[IWADR_EVENT_QUEUE_CAPACITY];
static int iwadr_event_head = 0;
static int iwadr_event_tail = 0;
static int iwadr_started = 0;
static int iwadr_quit_requested = 0;
static int iwadr_frame_ready = 0;
static int iwadr_suspended = 0;
static int iwadr_pending_mouse_event = 0;
static int iwadr_pending_mouse_buttons = 0;
static int iwadr_pending_mouse_delta_x = 0;
static int iwadr_pending_mouse_delta_y = 0;
static int iwadr_pending_weapon_slot = -1;
static int iwadr_save_generation_value = 0;
static int iwadr_external_tic_mode = 0;
static int iwadr_multiplayer_player_count = 1;
static int iwadr_multiplayer_local_player = 0;
static ticcmd_t iwadr_multiplayer_cmds[MAXPLAYERS];
static boolean iwadr_multiplayer_ingame[MAXPLAYERS];
static char iwadr_iwad_path_arg[4096] = "";
static char iwadr_temp_dir_arg[4096] = "";
static char iwadr_last_error_buffer[512] = "";
#if _WIN32
static int iwadr_mouse_capture_enabled = 0;
static HWND iwadr_capture_hwnd = NULL;
#elif defined(IWADR_HAS_X11)
static Display* iwadr_x11_display = NULL;
static Window iwadr_x11_window = 0;
static int iwadr_mouse_capture_enabled = 0;
#endif
#if _WIN32 || defined(IWADR_HAS_X11)
static int iwadr_discard_next_mouse_delta = 0;
#endif

static char* iwadr_argv[] = {
    "iwadr",
    "-iwad",
    iwadr_iwad_path_arg,
    "-nogui",
    "-gfxmode",
    "rgba8888",
};

static void iwadr_set_error(const char* message) {
  if (message == NULL) {
    iwadr_last_error_buffer[0] = '\0';
    return;
  }
  snprintf(iwadr_last_error_buffer, sizeof(iwadr_last_error_buffer), "%s",
           message);
}

static int iwadr_file_exists(const char* path) {
  FILE* file = fopen(path, "rb");
  if (file == NULL) {
    return 0;
  }
  fclose(file);
  return 1;
}

static void iwadr_reset_mouse_event(void) {
  iwadr_pending_mouse_event = 0;
  iwadr_pending_mouse_buttons = 0;
  iwadr_pending_mouse_delta_x = 0;
  iwadr_pending_mouse_delta_y = 0;
}

static void iwadr_flush_mouse_event(void) {
  if (!iwadr_pending_mouse_event) {
    return;
  }

  event_t event;
  event.type = ev_mouse;
  event.data1 = iwadr_pending_mouse_buttons;
  event.data2 = iwadr_pending_mouse_delta_x;
  event.data3 = iwadr_pending_mouse_delta_y;
  event.data4 = 0;
  D_PostEvent(&event);
  iwadr_reset_mouse_event();
}

static void iwadr_reset_multiplayer_state(void) {
  iwadr_external_tic_mode = 0;
  iwadr_multiplayer_player_count = 1;
  iwadr_multiplayer_local_player = 0;
  memset(iwadr_multiplayer_cmds, 0, sizeof(iwadr_multiplayer_cmds));
  memset(iwadr_multiplayer_ingame, 0, sizeof(iwadr_multiplayer_ingame));
}

static void iwadr_reset_runtime_state(void) {
  iwadr_event_head = 0;
  iwadr_event_tail = 0;
  iwadr_pending_weapon_slot = -1;
  iwadr_reset_mouse_event();
  iwadr_reset_multiplayer_state();
}

static void iwadr_stop_runtime(void) {
  iwadr_started = 0;
  iwadr_suspended = 0;
  iwadr_reset_runtime_state();
  iwadr_set_mouse_capture(0);
}

static void iwadr_prepare_start(void) {
  iwadr_quit_requested = 0;
  iwadr_suspended = 0;
  iwadr_reset_runtime_state();
}

static void iwadr_finish_shutdown(void) {
  iwadr_stop_runtime();
  doomgeneric_Shutdown();
}

static void iwadr_render_current_frame(void) {
  I_StartFrame();
  S_UpdateSounds(players[consoleplayer].mo);
  D_Display();
}

#if _WIN32
static int iwadr_get_window_center(HWND hwnd, POINT* center) {
  RECT rect;
  if (hwnd == NULL || center == NULL || !GetClientRect(hwnd, &rect)) {
    return 0;
  }

  center->x = (rect.right - rect.left) / 2;
  center->y = (rect.bottom - rect.top) / 2;
  return ClientToScreen(hwnd, center) != 0;
}
#elif defined(IWADR_HAS_X11)
static int iwadr_get_x11_window_center(int* center_x, int* center_y) {
  if (iwadr_x11_display == NULL || iwadr_x11_window == 0 || center_x == NULL ||
      center_y == NULL) {
    return 0;
  }

  XWindowAttributes attrs;
  if (!XGetWindowAttributes(iwadr_x11_display, iwadr_x11_window, &attrs)) {
    return 0;
  }

  Window child = 0;
  int root_x = 0;
  int root_y = 0;
  if (!XTranslateCoordinates(iwadr_x11_display, iwadr_x11_window,
                             DefaultRootWindow(iwadr_x11_display),
                             attrs.width / 2, attrs.height / 2, &root_x,
                             &root_y, &child)) {
    return 0;
  }

  *center_x = root_x;
  *center_y = root_y;
  return 1;
}
#endif

int iwadr_screen_width(void) { return IWADR_SCREEN_WIDTH; }

int iwadr_screen_height(void) { return IWADR_SCREEN_HEIGHT; }

int iwadr_is_started(void) { return iwadr_started; }

int iwadr_has_quit(void) { return iwadr_quit_requested; }

const char* iwadr_last_error(void) { return iwadr_last_error_buffer; }

void iwadr_set_temp_dir(const char* temp_dir) {
  if (temp_dir == NULL || temp_dir[0] == '\0') {
    iwadr_temp_dir_arg[0] = '\0';
    return;
  }

  snprintf(iwadr_temp_dir_arg, sizeof(iwadr_temp_dir_arg), "%s", temp_dir);

#if _WIN32
  SetEnvironmentVariableA("IWADR_TEMP", iwadr_temp_dir_arg);
#else
  setenv("IWADR_TEMP", iwadr_temp_dir_arg, 1);
#endif
}

int iwadr_start(const char* iwad_path) {
  if (iwadr_started) {
    return 1;
  }

  if (iwad_path == NULL || iwad_path[0] == '\0') {
    iwadr_set_error("IWAD path is required.");
    return 0;
  }

  if (!iwadr_file_exists(iwad_path)) {
    iwadr_set_error("IWAD file does not exist.");
    return 0;
  }

  snprintf(iwadr_iwad_path_arg, sizeof(iwadr_iwad_path_arg), "%s", iwad_path);
  iwadr_set_error(NULL);
  iwadr_prepare_start();

  doomgeneric_Create((int)(sizeof(iwadr_argv) / sizeof(iwadr_argv[0])),
                     iwadr_argv);
  iwadr_started = 1;
  return 1;
}

int iwadr_multiplayer_is_supported(void) { return 1; }

int iwadr_ticcmd_size(void) { return (int)sizeof(ticcmd_t); }

int iwadr_max_players(void) { return MAXPLAYERS; }

int iwadr_start_multiplayer(const char* iwad_path, int player_count,
                            int local_player, int deathmatch_value,
                            int episode, int map, int skill, int no_monsters,
                            int fast_monsters, int respawn_monsters,
                            int ticdup_value) {
  if (player_count < 2 || player_count > MAXPLAYERS) {
    iwadr_set_error("Player count must be 2 through 4.");
    return 0;
  }
  if (local_player < 0 || local_player >= player_count) {
    iwadr_set_error("Local player index is out of range.");
    return 0;
  }
  if (ticdup_value < 1 || ticdup_value > 4) {
    iwadr_set_error("ticdup must be 1 through 4.");
    return 0;
  }
  if (!iwadr_start(iwad_path)) {
    return 0;
  }

  iwadr_external_tic_mode = 1;
  iwadr_multiplayer_player_count = player_count;
  iwadr_multiplayer_local_player = local_player;
  consoleplayer = local_player;
  displayplayer = local_player;
  deathmatch = deathmatch_value ? 1 : 0;
  netgame = true;
  nomonsters = no_monsters ? 1 : 0;
  fastparm = fast_monsters ? 1 : 0;
  respawnparm = respawn_monsters ? 1 : 0;
  ticdup = ticdup_value;

  memset(iwadr_multiplayer_cmds, 0, sizeof(iwadr_multiplayer_cmds));
  memset(iwadr_multiplayer_ingame, 0, sizeof(iwadr_multiplayer_ingame));
  for (int i = 0; i < MAXPLAYERS; i++) {
    playeringame[i] = i < player_count;
    iwadr_multiplayer_ingame[i] = i < player_count;
  }

  G_InitNew((skill_t)skill, episode, map);
  return 1;
}

int iwadr_build_local_ticcmd(uint8_t* out, int out_len) {
  if (!iwadr_started || !iwadr_external_tic_mode) {
    iwadr_set_error("Runtime is not started in multiplayer mode.");
    return 0;
  }
  if (out == NULL || out_len < (int)sizeof(ticcmd_t)) {
    iwadr_set_error("Tic command buffer is too small.");
    return 0;
  }

  iwadr_flush_mouse_event();
  I_StartTic();
  D_ProcessEvents();
  M_Ticker();

  ticcmd_t cmd;
  memset(&cmd, 0, sizeof(cmd));
  G_BuildTiccmd(&cmd, gametic / ticdup);
  memcpy(out, &cmd, sizeof(cmd));
  return (int)sizeof(cmd);
}

int iwadr_run_synchronized_tic(const uint8_t* commands, const int* present,
                               int player_count) {
  if (!iwadr_started || !iwadr_external_tic_mode) {
    iwadr_set_error("Runtime is not started in multiplayer mode.");
    return -1;
  }
  if (commands == NULL || present == NULL) {
    iwadr_set_error("Synchronized commands are required.");
    return -1;
  }
  if (player_count != iwadr_multiplayer_player_count) {
    iwadr_set_error("Player count does not match the active multiplayer game.");
    return -1;
  }
  for (int i = 0; i < player_count; i++) {
    if (present[i] == 0) {
      return 0;
    }
  }

  memset(iwadr_multiplayer_cmds, 0, sizeof(iwadr_multiplayer_cmds));
  for (int i = 0; i < player_count; i++) {
    memcpy(&iwadr_multiplayer_cmds[i],
           commands + ((size_t)i * sizeof(ticcmd_t)), sizeof(ticcmd_t));
    iwadr_multiplayer_ingame[i] = true;
  }
  for (int i = player_count; i < MAXPLAYERS; i++) {
    iwadr_multiplayer_ingame[i] = false;
  }

  netcmds = iwadr_multiplayer_cmds;
  G_Ticker();
  gametic++;
  iwadr_render_current_frame();
  return iwadr_quit_requested ? -1 : 1;
}

uint32_t iwadr_sync_checksum(void) {
  uint32_t hash = 2166136261u;
  hash = (hash ^ (uint32_t)gametic) * 16777619u;
  hash = (hash ^ (uint32_t)gamestate) * 16777619u;
  hash = (hash ^ (uint32_t)consoleplayer) * 16777619u;
  for (int i = 0; i < MAXPLAYERS; i++) {
    hash = (hash ^ (uint32_t)playeringame[i]) * 16777619u;
    hash = (hash ^ (uint32_t)players[i].health) * 16777619u;
    hash = (hash ^ (uint32_t)players[i].armorpoints) * 16777619u;
    hash = (hash ^ (uint32_t)players[i].readyweapon) * 16777619u;
    if (players[i].mo == NULL) {
      hash = (hash ^ 0xffffffffu) * 16777619u;
      continue;
    }
    hash = (hash ^ (uint32_t)players[i].mo->x) * 16777619u;
    hash = (hash ^ (uint32_t)players[i].mo->y) * 16777619u;
    hash = (hash ^ (uint32_t)players[i].mo->angle) * 16777619u;
  }
  return hash;
}

void iwadr_on_save_game_written(void) { iwadr_save_generation_value++; }

int iwadr_save_generation(void) { return iwadr_save_generation_value; }

int iwadr_start_new_game(int skill, int episode, int map) {
  if (!iwadr_started) {
    iwadr_set_error("Runtime is not started.");
    return 0;
  }
  if (skill < sk_baby || skill > sk_nightmare) {
    iwadr_set_error("Skill is out of range.");
    return 0;
  }
  G_InitNew((skill_t)skill, episode, map);
  iwadr_tick();
  iwadr_set_error(NULL);
  return iwadr_is_gameplay_active();
}

int iwadr_save_game_exists(int slot) {
  if (slot < 0 || slot > 9) {
    return 0;
  }
  return iwadr_file_exists(P_SaveGameFile(slot));
}

int iwadr_save_game_size(int slot) {
  if (slot < 0 || slot > 9) {
    return -1;
  }

  FILE* file = fopen(P_SaveGameFile(slot), "rb");
  if (file == NULL) {
    return -1;
  }
  if (fseek(file, 0, SEEK_END) != 0) {
    fclose(file);
    return -1;
  }
  const long size = ftell(file);
  fclose(file);
  if (size < 0 || size > 2147483647L) {
    return -1;
  }
  return (int)size;
}

int iwadr_save_game(int slot, const char* description) {
  if (!iwadr_is_gameplay_active()) {
    iwadr_set_error("Save requires active gameplay.");
    return 0;
  }
  if (slot < 0 || slot > 9) {
    iwadr_set_error("Save slot must be 0 through 9.");
    return 0;
  }

  const int generation_before = iwadr_save_generation_value;
  G_SaveGame(slot, (char*)(description == NULL ? "IWAD Runtime" : description));
  for (int i = 0; i < 8 && iwadr_save_generation_value == generation_before;
       i++) {
    if (!iwadr_tick()) {
      return 0;
    }
  }
  if (iwadr_save_generation_value == generation_before ||
      iwadr_save_game_size(slot) <= 0) {
    iwadr_set_error("Save game was not written.");
    return 0;
  }
  iwadr_set_error(NULL);
  return 1;
}

int iwadr_load_game(int slot) {
  if (!iwadr_started) {
    iwadr_set_error("Runtime is not started.");
    return 0;
  }
  if (!iwadr_save_game_exists(slot)) {
    iwadr_set_error("Save game does not exist.");
    return 0;
  }

  G_LoadGame(P_SaveGameFile(slot));
  for (int i = 0; i < 8 && iwadr_started; i++) {
    if (!iwadr_tick() && !iwadr_quit_requested) {
      return 0;
    }
  }
  iwadr_set_error(NULL);
  return iwadr_started;
}

void iwadr_shutdown(void) {
  if (!iwadr_started) {
    iwadr_set_suspended(0);
    return;
  }

  I_Quit();
  iwadr_finish_shutdown();
}

int iwadr_tick(void) {
  if (!iwadr_started) {
    if (iwadr_quit_requested) {
      return 0;
    }
    iwadr_set_error("Runtime is not started.");
    return 0;
  }

  if (iwadr_suspended) {
    return 1;
  }

  if (iwadr_external_tic_mode) {
    iwadr_set_error("Use iwadr_run_synchronized_tic in multiplayer mode.");
    return 0;
  }

  iwadr_flush_mouse_event();
  doomgeneric_Tick();
  if (iwadr_quit_requested) {
    iwadr_finish_shutdown();
    return 0;
  }
  return 1;
}

int iwadr_copy_frame_rgba(uint8_t* out, int out_len) {
  if (!iwadr_started || DG_ScreenBuffer == NULL || out == NULL) {
    return 0;
  }

  const int required =
      IWADR_SCREEN_WIDTH * IWADR_SCREEN_HEIGHT * IWADR_BYTES_PER_PIXEL;
  if (out_len < required) {
    iwadr_set_error("Frame buffer is too small.");
    return 0;
  }

  const uint32_t* src = (const uint32_t*)DG_ScreenBuffer;
  for (int i = 0; i < IWADR_SCREEN_WIDTH * IWADR_SCREEN_HEIGHT; i++) {
    const uint32_t pixel = src[i];
    out[i * 4 + 0] = (uint8_t)((pixel >> 16) & 0xff);
    out[i * 4 + 1] = (uint8_t)((pixel >> 8) & 0xff);
    out[i * 4 + 2] = (uint8_t)(pixel & 0xff);
    out[i * 4 + 3] = 0xff;
  }

  iwadr_frame_ready = 0;
  return required;
}

void iwadr_key_event(int input_key, int pressed) {
  const int next_tail = (iwadr_event_tail + 1) % IWADR_EVENT_QUEUE_CAPACITY;
  if (next_tail == iwadr_event_head) {
    return;
  }

  iwadr_events[iwadr_event_tail].pressed = pressed ? 1 : 0;
  iwadr_events[iwadr_event_tail].key = (unsigned char)(input_key & 0xff);
  iwadr_event_tail = next_tail;
}

void iwadr_request_weapon_slot(int slot) {
  if (!iwadr_started || slot < 1 || slot > 8) {
    return;
  }

  iwadr_pending_weapon_slot = slot - 1;
}

static int iwadr_weapon_to_slot(weapontype_t weapon) {
  switch (weapon) {
    case wp_fist:
    case wp_chainsaw:
      return 1;
    case wp_pistol:
      return 2;
    case wp_shotgun:
    case wp_supershotgun:
      return 3;
    case wp_chaingun:
      return 4;
    case wp_missile:
      return 5;
    case wp_plasma:
      return 6;
    case wp_bfg:
      return 7;
    default:
      return 0;
  }
}

int iwadr_current_weapon_slot(void) {
  if (!iwadr_is_gameplay_active()) {
    return 0;
  }

  const player_t* player = &players[consoleplayer];
  const weapontype_t weapon = player->pendingweapon == wp_nochange
                                  ? player->readyweapon
                                  : player->pendingweapon;
  return iwadr_weapon_to_slot(weapon);
}

int iwadr_owned_weapon_slots_mask(void) {
  if (!iwadr_started || gamestate != GS_LEVEL) {
    return 0;
  }

  const player_t* player = &players[consoleplayer];
  int mask = 0;
  for (int i = 0; i < NUMWEAPONS; i++) {
    if (!player->weaponowned[i]) {
      continue;
    }
    const int slot = iwadr_weapon_to_slot((weapontype_t)i);
    if (slot > 0) {
      mask |= 1 << (slot - 1);
    }
  }
  return mask;
}

int iwadr_is_gameplay_active(void) {
  return iwadr_started && gamestate == GS_LEVEL && !menuactive &&
         !demoplayback && !advancedemo;
}

int iwadr_is_player_dead(void) {
  return iwadr_is_gameplay_active() &&
         players[consoleplayer].playerstate == PST_DEAD;
}

int iwadr_is_advance_active(void) {
  return iwadr_started && !menuactive &&
         (gamestate == GS_INTERMISSION || gamestate == GS_FINALE);
}

int iwadr_is_menu_active(void) {
  return iwadr_started && menuactive;
}

int iwadr_is_menu_prompt_active(void) {
  return iwadr_started && menuactive && messageToPrint && messageNeedsInput;
}

int iwadr_is_save_name_active(void) {
  return iwadr_started && menuactive && saveStringEnter;
}

int iwadr_is_quit_confirm_active(void) {
  return iwadr_started && menuactive && messageToPrint &&
         messageRoutine == M_QuitResponse;
}

void iwadr_mouse_event(int buttons, int delta_x, int delta_y) {
  if (!iwadr_started) {
    return;
  }

  iwadr_pending_mouse_event = 1;
  iwadr_pending_mouse_buttons = buttons;
  iwadr_pending_mouse_delta_x += delta_x;
  iwadr_pending_mouse_delta_y += delta_y;
}

void iwadr_set_suspended(int suspended) {
  iwadr_suspended = suspended ? 1 : 0;
  iwadr_audio_set_suspended(iwadr_suspended);
}

int iwadr_set_mouse_capture(int enabled) {
#if _WIN32
  if (enabled) {
    HWND hwnd = GetForegroundWindow();
    if (hwnd == NULL) {
      return 0;
    }

    RECT rect;
    if (!GetClientRect(hwnd, &rect)) {
      return 0;
    }

    POINT upper_left = {rect.left, rect.top};
    POINT lower_right = {rect.right, rect.bottom};
    ClientToScreen(hwnd, &upper_left);
    ClientToScreen(hwnd, &lower_right);

    RECT clip = {
        upper_left.x,
        upper_left.y,
        lower_right.x,
        lower_right.y,
    };

    if (!ClipCursor(&clip)) {
      return 0;
    }

    POINT center;
    if (iwadr_get_window_center(hwnd, &center)) {
      SetCursorPos(center.x, center.y);
    }
    iwadr_discard_next_mouse_delta = 1;

    if (!iwadr_mouse_capture_enabled) {
      while (ShowCursor(FALSE) >= 0) {
      }
    }
    iwadr_capture_hwnd = hwnd;
    iwadr_mouse_capture_enabled = 1;
    return 1;
  }

  ClipCursor(NULL);
  if (iwadr_mouse_capture_enabled) {
    while (ShowCursor(TRUE) < 0) {
    }
  }
  iwadr_capture_hwnd = NULL;
  iwadr_mouse_capture_enabled = 0;
  iwadr_discard_next_mouse_delta = 0;
  return 1;
#elif defined(IWADR_HAS_X11)
  if (enabled) {
    if (iwadr_mouse_capture_enabled) {
      return 1;
    }

    iwadr_x11_display = XOpenDisplay(NULL);
    if (iwadr_x11_display == NULL) {
      return 0;
    }

    Window root = DefaultRootWindow(iwadr_x11_display);
    Window root_return = 0;
    Window child_return = 0;
    int root_x = 0;
    int root_y = 0;
    int win_x = 0;
    int win_y = 0;
    unsigned int mask = 0;
    Window target = root;
    if (XQueryPointer(iwadr_x11_display, root, &root_return, &child_return,
                      &root_x, &root_y, &win_x, &win_y, &mask) &&
        child_return != None) {
      target = child_return;
    }

    const int result = XGrabPointer(
        iwadr_x11_display, target, True,
        PointerMotionMask | ButtonPressMask | ButtonReleaseMask, GrabModeAsync,
        GrabModeAsync, target, None, CurrentTime);
    if (result != GrabSuccess) {
      XCloseDisplay(iwadr_x11_display);
      iwadr_x11_display = NULL;
      return 0;
    }

    iwadr_x11_window = target;
    int center_x = 0;
    int center_y = 0;
    if (iwadr_get_x11_window_center(&center_x, &center_y)) {
      XWarpPointer(iwadr_x11_display, None, root, 0, 0, 0, 0, center_x,
                   center_y);
    }
    iwadr_discard_next_mouse_delta = 1;
    iwadr_mouse_capture_enabled = 1;
    XFlush(iwadr_x11_display);
    return 1;
  }

  if (iwadr_x11_display != NULL) {
    XUngrabPointer(iwadr_x11_display, CurrentTime);
    XFlush(iwadr_x11_display);
    XCloseDisplay(iwadr_x11_display);
    iwadr_x11_display = NULL;
  }
  iwadr_x11_window = 0;
  iwadr_mouse_capture_enabled = 0;
  iwadr_discard_next_mouse_delta = 0;
  return 1;
#else
  (void)enabled;
  return 0;
#endif
}

int iwadr_poll_mouse_delta(int* delta_x, int* delta_y) {
  if (delta_x == NULL || delta_y == NULL) {
    return 0;
  }

  *delta_x = 0;
  *delta_y = 0;

#if _WIN32
  if (!iwadr_mouse_capture_enabled || iwadr_capture_hwnd == NULL) {
    return 0;
  }

  POINT center;
  POINT cursor;
  if (!iwadr_get_window_center(iwadr_capture_hwnd, &center) ||
      !GetCursorPos(&cursor)) {
    return 0;
  }

  *delta_x = cursor.x - center.x;
  *delta_y = cursor.y - center.y;
  if (iwadr_discard_next_mouse_delta) {
    iwadr_discard_next_mouse_delta = 0;
    SetCursorPos(center.x, center.y);
    return 0;
  }
  if (*delta_x == 0 && *delta_y == 0) {
    return 0;
  }

  SetCursorPos(center.x, center.y);
  return 1;
#elif defined(IWADR_HAS_X11)
  if (!iwadr_mouse_capture_enabled || iwadr_x11_display == NULL ||
      iwadr_x11_window == 0) {
    return 0;
  }

  int center_x = 0;
  int center_y = 0;
  if (!iwadr_get_x11_window_center(&center_x, &center_y)) {
    return 0;
  }

  Window root = DefaultRootWindow(iwadr_x11_display);
  Window root_return = 0;
  Window child_return = 0;
  int root_x = 0;
  int root_y = 0;
  int win_x = 0;
  int win_y = 0;
  unsigned int mask = 0;
  if (!XQueryPointer(iwadr_x11_display, root, &root_return, &child_return,
                     &root_x, &root_y, &win_x, &win_y, &mask)) {
    return 0;
  }

  *delta_x = root_x - center_x;
  *delta_y = root_y - center_y;
  if (iwadr_discard_next_mouse_delta) {
    iwadr_discard_next_mouse_delta = 0;
    XWarpPointer(iwadr_x11_display, None, root, 0, 0, 0, 0, center_x,
                 center_y);
    XFlush(iwadr_x11_display);
    return 0;
  }
  if (*delta_x == 0 && *delta_y == 0) {
    return 0;
  }

  XWarpPointer(iwadr_x11_display, None, root, 0, 0, 0, 0, center_x, center_y);
  XFlush(iwadr_x11_display);
  return 1;
#else
  return 0;
#endif
}

void DG_Init(void) {}

void DG_DrawFrame(void) { iwadr_frame_ready = 1; }

void DG_SleepMs(uint32_t ms) {
#if _WIN32
  Sleep(ms);
#else
  usleep(ms * 1000);
#endif
}

uint32_t DG_GetTicksMs(void) {
#if _WIN32
  return (uint32_t)GetTickCount();
#else
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return (uint32_t)((tv.tv_sec * 1000) + (tv.tv_usec / 1000));
#endif
}

int DG_GetKey(int* pressed, unsigned char* key) {
  if (iwadr_event_head == iwadr_event_tail) {
    return 0;
  }

  const IwadrKeyEvent event = iwadr_events[iwadr_event_head];
  iwadr_event_head = (iwadr_event_head + 1) % IWADR_EVENT_QUEUE_CAPACITY;
  *pressed = event.pressed;
  *key = event.key;
  return 1;
}

int DG_ConsumeWeaponSlotRequest(void) {
  const int slot = iwadr_pending_weapon_slot;
  iwadr_pending_weapon_slot = -1;
  return slot;
}

void DG_SetWindowTitle(const char* title) {
  (void)title;
}

void DG_Quit(void) {
  iwadr_quit_requested = 1;
}
