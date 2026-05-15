#include "iwadr.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "doomgeneric/doomtype.h"
#include "doomgeneric/i_sound.h"
#include "doomgeneric/w_wad.h"
#include "doomgeneric/z_zone.h"
#include "iwadr_opl.h"
#include "miniaudio.h"

#define IWADR_AUDIO_DEFAULT_SAMPLE_RATE 48000
#define IWADR_AUDIO_CHANNEL_COUNT 16
#define IWADR_AUDIO_SFX_GAIN 0.30f

typedef struct IwadrCachedSfx {
  sfxinfo_t* sfxinfo;
  uint8_t* samples;
  uint32_t sample_count;
  uint32_t sample_rate;
  struct IwadrCachedSfx* next;
} IwadrCachedSfx;

typedef struct IwadrVoice {
  int active;
  const IwadrCachedSfx* sfx;
  double position;
  float left_gain;
  float right_gain;
} IwadrVoice;

static ma_device iwadr_audio_device;
static ma_mutex iwadr_audio_lock;
static int iwadr_audio_lock_initialized = 0;
static int iwadr_audio_initialized = 0;
static int iwadr_audio_started = 0;
static int iwadr_audio_suspended = 0;
static int iwadr_audio_use_sfx_prefix = 1;
static int iwadr_audio_start_count = 0;
static int iwadr_audio_callback_count_value = 0;
static int iwadr_audio_max_callback_frames = 0;
static int iwadr_audio_clip_count_value = 0;
static int iwadr_audio_peak_output_milli_value = 0;
static int iwadr_audio_max_jump_milli_value = 0;
static float iwadr_audio_previous_left = 0.0f;
static float iwadr_audio_previous_right = 0.0f;
static uint32_t iwadr_audio_sample_rate_value = IWADR_AUDIO_DEFAULT_SAMPLE_RATE;
static IwadrVoice iwadr_audio_voices[IWADR_AUDIO_CHANNEL_COUNT];
static IwadrCachedSfx* iwadr_audio_cached_sfx = NULL;

int use_libsamplerate = 0;
float libsamplerate_scale = 0.65f;

static snddevice_t iwadr_audio_devices[] = {
    SNDDEVICE_SB,
    SNDDEVICE_PAS,
    SNDDEVICE_GUS,
    SNDDEVICE_WAVEBLASTER,
    SNDDEVICE_SOUNDCANVAS,
    SNDDEVICE_GENMIDI,
    SNDDEVICE_AWE32,
};

static float iwadr_audio_clamp(float value, float min, float max) {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}

static int iwadr_audio_float_to_milli(float value) {
  if (value < 0.0f) {
    value = -value;
  }
  return (int)(value * 1000.0f);
}

static void iwadr_audio_reset_diagnostics(void) {
  iwadr_audio_callback_count_value = 0;
  iwadr_audio_max_callback_frames = 0;
  iwadr_audio_clip_count_value = 0;
  iwadr_audio_peak_output_milli_value = 0;
  iwadr_audio_max_jump_milli_value = 0;
  iwadr_audio_previous_left = 0.0f;
  iwadr_audio_previous_right = 0.0f;
}

static void iwadr_audio_set_voice_params(IwadrVoice* voice, int vol, int sep) {
  const float volume = iwadr_audio_clamp((float)vol / 127.0f, 0.0f, 1.0f);
  const float left = iwadr_audio_clamp((float)(254 - sep) / 127.0f, 0.0f, 1.0f);
  const float right = iwadr_audio_clamp((float)sep / 127.0f, 0.0f, 1.0f);
  voice->left_gain = volume * left * IWADR_AUDIO_SFX_GAIN;
  voice->right_gain = volume * right * IWADR_AUDIO_SFX_GAIN;
}

static void iwadr_audio_get_sfx_lump_name(sfxinfo_t* sfx, char* buffer,
                                          size_t buffer_len) {
  if (sfx->link != NULL) {
    sfx = sfx->link;
  }

  if (iwadr_audio_use_sfx_prefix) {
    snprintf(buffer, buffer_len, "ds%s", sfx->name);
  } else {
    snprintf(buffer, buffer_len, "%s", sfx->name);
  }
}

static int iwadr_audio_get_sfx_lump_num(sfxinfo_t* sfx) {
  char name[9];
  iwadr_audio_get_sfx_lump_name(sfx, name, sizeof(name));
  return W_GetNumForName(name);
}

static void iwadr_audio_free_cached_sounds(void) {
  IwadrCachedSfx* current = iwadr_audio_cached_sfx;
  while (current != NULL) {
    IwadrCachedSfx* next = current->next;
    if (current->sfxinfo != NULL) {
      current->sfxinfo->driver_data = NULL;
    }
    free(current->samples);
    free(current);
    current = next;
  }
  iwadr_audio_cached_sfx = NULL;
}

static IwadrCachedSfx* iwadr_audio_cache_sfx(sfxinfo_t* sfxinfo) {
  int lumpnum;
  unsigned int lumplen;
  uint8_t* data;
  uint32_t samplerate;
  uint32_t length;
  IwadrCachedSfx* cached;

  if (sfxinfo->driver_data != NULL) {
    return (IwadrCachedSfx*)sfxinfo->driver_data;
  }

  lumpnum = sfxinfo->lumpnum;
  if (lumpnum < 0) {
    return NULL;
  }

  data = W_CacheLumpNum(lumpnum, PU_STATIC);
  lumplen = W_LumpLength(lumpnum);
  if (data == NULL || lumplen < 8 || data[0] != 0x03 || data[1] != 0x00) {
    W_ReleaseLumpNum(lumpnum);
    return NULL;
  }

  samplerate = ((uint32_t)data[3] << 8) | data[2];
  length = ((uint32_t)data[7] << 24) | ((uint32_t)data[6] << 16) |
           ((uint32_t)data[5] << 8) | data[4];

  if (samplerate == 0 || length > lumplen - 8 || length <= 48) {
    W_ReleaseLumpNum(lumpnum);
    return NULL;
  }

  data += 16;
  length -= 32;

  cached = (IwadrCachedSfx*)calloc(1, sizeof(IwadrCachedSfx));
  if (cached == NULL) {
    W_ReleaseLumpNum(lumpnum);
    return NULL;
  }

  cached->samples = (uint8_t*)malloc(length);
  if (cached->samples == NULL) {
    free(cached);
    W_ReleaseLumpNum(lumpnum);
    return NULL;
  }

  memcpy(cached->samples, data + 8, length);
  cached->sample_count = length;
  cached->sample_rate = samplerate;
  cached->sfxinfo = sfxinfo;
  cached->next = iwadr_audio_cached_sfx;
  iwadr_audio_cached_sfx = cached;
  sfxinfo->driver_data = cached;

  W_ReleaseLumpNum(lumpnum);
  return cached;
}

static void iwadr_audio_data_callback(ma_device* device, void* output,
                                      const void* input,
                                      ma_uint32 frame_count) {
  float* out = (float*)output;
  memset(out, 0, frame_count * 2 * sizeof(float));

  if (!iwadr_audio_initialized) {
    (void)device;
    (void)input;
    return;
  }

  iwadr_audio_callback_count_value++;
  if ((int)frame_count > iwadr_audio_max_callback_frames) {
    iwadr_audio_max_callback_frames = (int)frame_count;
  }

  ma_mutex_lock(&iwadr_audio_lock);
  for (ma_uint32 frame = 0; frame < frame_count; frame++) {
    float left = 0.0f;
    float right = 0.0f;

    for (int channel = 0; channel < IWADR_AUDIO_CHANNEL_COUNT; channel++) {
      IwadrVoice* voice = &iwadr_audio_voices[channel];
      if (!voice->active || voice->sfx == NULL) {
        continue;
      }

      const uint32_t index = (uint32_t)voice->position;
      if (index >= voice->sfx->sample_count) {
        voice->active = 0;
        continue;
      }

      const uint32_t next_index =
          index + 1 < voice->sfx->sample_count ? index + 1 : index;
      const float blend = (float)(voice->position - (double)index);
      const float a = ((float)voice->sfx->samples[index] - 128.0f) / 128.0f;
      const float b =
          ((float)voice->sfx->samples[next_index] - 128.0f) / 128.0f;
      const float sample = a + (b - a) * blend;

      left += sample * voice->left_gain;
      right += sample * voice->right_gain;
      voice->position +=
          (double)voice->sfx->sample_rate / (double)iwadr_audio_sample_rate_value;
    }

    out[frame * 2 + 0] = iwadr_audio_clamp(left, -1.0f, 1.0f);
    out[frame * 2 + 1] = iwadr_audio_clamp(right, -1.0f, 1.0f);
  }
  ma_mutex_unlock(&iwadr_audio_lock);

  iwadr_opl_mix_float(out, frame_count);
  for (ma_uint32 frame = 0; frame < frame_count; frame++) {
    float left = out[frame * 2 + 0];
    float right = out[frame * 2 + 1];
    int left_output_milli = iwadr_audio_float_to_milli(left);
    int right_output_milli = iwadr_audio_float_to_milli(right);
    int output_milli = left_output_milli > right_output_milli
                           ? left_output_milli
                           : right_output_milli;
    int left_jump_milli =
        iwadr_audio_float_to_milli(left - iwadr_audio_previous_left);
    int right_jump_milli =
        iwadr_audio_float_to_milli(right - iwadr_audio_previous_right);
    int jump_milli =
        left_jump_milli > right_jump_milli ? left_jump_milli : right_jump_milli;

    if (left > 1.0f || left < -1.0f || right > 1.0f || right < -1.0f) {
      iwadr_audio_clip_count_value++;
    }
    if (output_milli > iwadr_audio_peak_output_milli_value) {
      iwadr_audio_peak_output_milli_value = output_milli;
    }
    if (jump_milli > iwadr_audio_max_jump_milli_value) {
      iwadr_audio_max_jump_milli_value = jump_milli;
    }

    iwadr_audio_previous_left = left;
    iwadr_audio_previous_right = right;
    out[frame * 2 + 0] = iwadr_audio_clamp(left, -1.0f, 1.0f);
    out[frame * 2 + 1] = iwadr_audio_clamp(right, -1.0f, 1.0f);
  }

  (void)device;
  (void)input;
}

static boolean iwadr_audio_init(boolean use_sfx_prefix) {
  ma_device_config config;

  if (iwadr_audio_initialized) {
    return true;
  }

  iwadr_audio_use_sfx_prefix = use_sfx_prefix ? 1 : 0;
  memset(iwadr_audio_voices, 0, sizeof(iwadr_audio_voices));
  iwadr_audio_reset_diagnostics();
  snd_samplerate = IWADR_AUDIO_DEFAULT_SAMPLE_RATE;

  if (ma_mutex_init(&iwadr_audio_lock) != MA_SUCCESS) {
    return false;
  }
  iwadr_audio_lock_initialized = 1;

  config = ma_device_config_init(ma_device_type_playback);
  config.playback.format = ma_format_f32;
  config.playback.channels = 2;
  config.sampleRate = IWADR_AUDIO_DEFAULT_SAMPLE_RATE;
  config.periodSizeInMilliseconds =
      snd_maxslicetime_ms > 0 ? (ma_uint32)snd_maxslicetime_ms : 28;
  config.periods = 3;
  config.performanceProfile = ma_performance_profile_conservative;
  config.dataCallback = iwadr_audio_data_callback;

  if (ma_device_init(NULL, &config, &iwadr_audio_device) != MA_SUCCESS) {
    ma_mutex_uninit(&iwadr_audio_lock);
    iwadr_audio_lock_initialized = 0;
    return false;
  }

  if (iwadr_audio_device.sampleRate > 0) {
    iwadr_audio_sample_rate_value = iwadr_audio_device.sampleRate;
    snd_samplerate = (int)iwadr_audio_device.sampleRate;
  } else {
    iwadr_audio_sample_rate_value = config.sampleRate;
  }

  if (ma_device_start(&iwadr_audio_device) != MA_SUCCESS) {
    ma_device_uninit(&iwadr_audio_device);
    ma_mutex_uninit(&iwadr_audio_lock);
    iwadr_audio_lock_initialized = 0;
    return false;
  }

  iwadr_audio_initialized = 1;
  iwadr_audio_started = 1;
  iwadr_audio_suspended = 0;
  return true;
}

static void iwadr_audio_shutdown(void) {
  if (iwadr_audio_initialized) {
    ma_device_uninit(&iwadr_audio_device);
    iwadr_audio_initialized = 0;
    iwadr_audio_started = 0;
    iwadr_audio_suspended = 0;
  }

  if (iwadr_audio_lock_initialized) {
    ma_mutex_lock(&iwadr_audio_lock);
    memset(iwadr_audio_voices, 0, sizeof(iwadr_audio_voices));
    ma_mutex_unlock(&iwadr_audio_lock);
    ma_mutex_uninit(&iwadr_audio_lock);
    iwadr_audio_lock_initialized = 0;
  }

  iwadr_audio_free_cached_sounds();
}

static void iwadr_audio_update(void) {}

static void iwadr_audio_update_sound_params(int channel, int vol, int sep) {
  if (!iwadr_audio_initialized || channel < 0 ||
      channel >= IWADR_AUDIO_CHANNEL_COUNT) {
    return;
  }

  ma_mutex_lock(&iwadr_audio_lock);
  if (iwadr_audio_voices[channel].active) {
    iwadr_audio_set_voice_params(&iwadr_audio_voices[channel], vol, sep);
  }
  ma_mutex_unlock(&iwadr_audio_lock);
}

static int iwadr_audio_start_sound(sfxinfo_t* sfxinfo, int channel, int vol,
                                   int sep) {
  IwadrCachedSfx* cached;

  if (!iwadr_audio_initialized || channel < 0 ||
      channel >= IWADR_AUDIO_CHANNEL_COUNT) {
    return -1;
  }

  cached = iwadr_audio_cache_sfx(sfxinfo);
  if (cached == NULL) {
    return -1;
  }

  ma_mutex_lock(&iwadr_audio_lock);
  iwadr_audio_voices[channel].active = 1;
  iwadr_audio_voices[channel].sfx = cached;
  iwadr_audio_voices[channel].position = 0.0;
  iwadr_audio_set_voice_params(&iwadr_audio_voices[channel], vol, sep);
  iwadr_audio_start_count++;
  ma_mutex_unlock(&iwadr_audio_lock);

  return channel;
}

static void iwadr_audio_stop_sound(int channel) {
  if (!iwadr_audio_initialized || channel < 0 ||
      channel >= IWADR_AUDIO_CHANNEL_COUNT) {
    return;
  }

  ma_mutex_lock(&iwadr_audio_lock);
  iwadr_audio_voices[channel].active = 0;
  ma_mutex_unlock(&iwadr_audio_lock);
}

static boolean iwadr_audio_sound_is_playing(int channel) {
  boolean result;

  if (!iwadr_audio_initialized || channel < 0 ||
      channel >= IWADR_AUDIO_CHANNEL_COUNT) {
    return false;
  }

  ma_mutex_lock(&iwadr_audio_lock);
  result = iwadr_audio_voices[channel].active ? true : false;
  ma_mutex_unlock(&iwadr_audio_lock);
  return result;
}

static void iwadr_audio_cache_sounds(sfxinfo_t* sounds, int num_sounds) {
  (void)sounds;
  (void)num_sounds;
}

int iwadr_audio_is_started(void) { return iwadr_audio_started; }

void iwadr_audio_set_suspended(int suspended) {
  if (!iwadr_audio_initialized) {
    iwadr_audio_suspended = suspended ? 1 : 0;
    iwadr_audio_started = 0;
    return;
  }

  if (suspended) {
    if (!iwadr_audio_suspended) {
      ma_device_stop(&iwadr_audio_device);
      iwadr_audio_suspended = 1;
      iwadr_audio_started = 0;
    }
    return;
  }

  if (iwadr_audio_suspended) {
    if (ma_device_start(&iwadr_audio_device) == MA_SUCCESS) {
      iwadr_audio_started = 1;
    }
    iwadr_audio_suspended = 0;
  }
}

int iwadr_audio_is_suspended(void) { return iwadr_audio_suspended; }

int iwadr_audio_started_sound_count(void) { return iwadr_audio_start_count; }

int iwadr_audio_sample_rate(void) { return (int)iwadr_audio_sample_rate_value; }

int iwadr_audio_callback_count(void) { return iwadr_audio_callback_count_value; }

int iwadr_audio_max_callback_frame_count(void) {
  return iwadr_audio_max_callback_frames;
}

int iwadr_audio_clip_count(void) { return iwadr_audio_clip_count_value; }

int iwadr_audio_peak_output_milli(void) {
  return iwadr_audio_peak_output_milli_value;
}

int iwadr_audio_max_jump_milli(void) { return iwadr_audio_max_jump_milli_value; }

int iwadr_audio_active_voice_count(void) {
  int count = 0;
  if (!iwadr_audio_initialized) {
    return 0;
  }

  ma_mutex_lock(&iwadr_audio_lock);
  for (int channel = 0; channel < IWADR_AUDIO_CHANNEL_COUNT; channel++) {
    if (iwadr_audio_voices[channel].active) {
      count++;
    }
  }
  ma_mutex_unlock(&iwadr_audio_lock);
  return count;
}

sound_module_t DG_sound_module = {
    iwadr_audio_devices,
    arrlen(iwadr_audio_devices),
    iwadr_audio_init,
    iwadr_audio_shutdown,
    iwadr_audio_get_sfx_lump_num,
    iwadr_audio_update,
    iwadr_audio_update_sound_params,
    iwadr_audio_start_sound,
    iwadr_audio_stop_sound,
    iwadr_audio_sound_is_playing,
    iwadr_audio_cache_sounds,
};

void I_InitTimidityConfig(void) {}
