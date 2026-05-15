#include "iwadr_opl.h"

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "iwadr.h"
#include "miniaudio.h"
#include "opl/opl.h"
#include "opl/opl3.h"
#include "opl/opl_queue.h"

#define IWADR_OPL_SAMPLE_RATE 48000
#define IWADR_OPL_MIX_CHUNK 1024
#define IWADR_OPL_GAIN 2.8f
#define IWADR_OPL_FILTER_CUTOFF_HZ 11000.0f
#define IWADR_OPL_PI 3.14159265358979323846f

unsigned int opl_sample_rate = IWADR_OPL_SAMPLE_RATE;

static opl3_chip iwadr_opl_chip;
static opl_callback_queue_t* iwadr_opl_callback_queue = NULL;
static ma_mutex iwadr_opl_callback_mutex;
static ma_mutex iwadr_opl_queue_mutex;
static int iwadr_opl_mutexes_initialized = 0;
static int iwadr_opl_initialized = 0;
static int iwadr_opl_register_num = 0;
static int iwadr_opl_paused = 0;
static int iwadr_opl_mixed_frames = 0;
static int iwadr_opl_nonzero_mixes = 0;
static int iwadr_opl_peak_sample_value = 0;
static int iwadr_opl_peak_output_milli_value = 0;
static int iwadr_opl_max_jump_milli_value = 0;
static float iwadr_opl_filter_alpha = 0.0f;
static float iwadr_opl_filter_left = 0.0f;
static float iwadr_opl_filter_right = 0.0f;
static float iwadr_opl_previous_left = 0.0f;
static float iwadr_opl_previous_right = 0.0f;
static uint64_t iwadr_opl_current_time = 0;
static uint64_t iwadr_opl_pause_offset = 0;

static int iwadr_opl_float_to_milli(float value) {
  if (value < 0.0f) {
    value = -value;
  }
  return (int)(value * 1000.0f);
}

static void iwadr_opl_update_filter(void) {
  const float sample_rate =
      opl_sample_rate == 0 ? (float)IWADR_OPL_SAMPLE_RATE : (float)opl_sample_rate;
  const float decay =
      expf((-2.0f * IWADR_OPL_PI * IWADR_OPL_FILTER_CUTOFF_HZ) / sample_rate);
  iwadr_opl_filter_alpha = 1.0f - decay;
}

static void iwadr_opl_reset_filter_state(void) {
  iwadr_opl_filter_left = 0.0f;
  iwadr_opl_filter_right = 0.0f;
  iwadr_opl_previous_left = 0.0f;
  iwadr_opl_previous_right = 0.0f;
}

void OPL_SetSampleRate(unsigned int rate) {
  opl_sample_rate = rate == 0 ? IWADR_OPL_SAMPLE_RATE : rate;
  iwadr_opl_update_filter();
}

opl_init_result_t OPL_Init(unsigned int port_base) {
  (void)port_base;

  if (iwadr_opl_initialized) {
    return OPL_INIT_OPL3;
  }

  iwadr_opl_callback_queue = OPL_Queue_Create();
  if (iwadr_opl_callback_queue == NULL) {
    return OPL_INIT_NONE;
  }

  if (ma_mutex_init(&iwadr_opl_callback_mutex) != MA_SUCCESS ||
      ma_mutex_init(&iwadr_opl_queue_mutex) != MA_SUCCESS) {
    OPL_Queue_Destroy(iwadr_opl_callback_queue);
    iwadr_opl_callback_queue = NULL;
    return OPL_INIT_NONE;
  }

  iwadr_opl_mutexes_initialized = 1;
  iwadr_opl_current_time = 0;
  iwadr_opl_pause_offset = 0;
  iwadr_opl_paused = 0;
  iwadr_opl_register_num = 0;
  iwadr_opl_mixed_frames = 0;
  iwadr_opl_nonzero_mixes = 0;
  iwadr_opl_peak_sample_value = 0;
  iwadr_opl_peak_output_milli_value = 0;
  iwadr_opl_max_jump_milli_value = 0;
  iwadr_opl_update_filter();
  iwadr_opl_reset_filter_state();

  OPL3_Reset(&iwadr_opl_chip, opl_sample_rate);
  iwadr_opl_initialized = 1;
  return OPL_INIT_OPL3;
}

void OPL_Shutdown(void) {
  iwadr_opl_initialized = 0;

  if (iwadr_opl_mutexes_initialized) {
    ma_mutex_lock(&iwadr_opl_queue_mutex);
    if (iwadr_opl_callback_queue != NULL) {
      OPL_Queue_Clear(iwadr_opl_callback_queue);
    }
    ma_mutex_unlock(&iwadr_opl_queue_mutex);
  }

  if (iwadr_opl_callback_queue != NULL) {
    OPL_Queue_Destroy(iwadr_opl_callback_queue);
    iwadr_opl_callback_queue = NULL;
  }

  if (iwadr_opl_mutexes_initialized) {
    ma_mutex_uninit(&iwadr_opl_queue_mutex);
    ma_mutex_uninit(&iwadr_opl_callback_mutex);
    iwadr_opl_mutexes_initialized = 0;
  }
}

void OPL_WritePort(opl_port_t port, unsigned int value) {
  if (!iwadr_opl_initialized) {
    return;
  }

  if (port == OPL_REGISTER_PORT) {
    iwadr_opl_register_num = (int)value;
  } else if (port == OPL_REGISTER_PORT_OPL3) {
    iwadr_opl_register_num = (int)value | 0x100;
  } else if (port == OPL_DATA_PORT) {
    OPL3_WriteRegBuffered(&iwadr_opl_chip, (Bit16u)iwadr_opl_register_num,
                          (Bit8u)value);
  }
}

unsigned int OPL_ReadPort(opl_port_t port) {
  if (port == OPL_REGISTER_PORT_OPL3) {
    return 0xff;
  }
  return 0;
}

unsigned int OPL_ReadStatus(void) { return OPL_ReadPort(OPL_REGISTER_PORT); }

void OPL_WriteRegister(int reg, int value) {
  if (!iwadr_opl_initialized) {
    return;
  }

  if (reg & 0x100) {
    OPL_WritePort(OPL_REGISTER_PORT_OPL3, (unsigned int)reg);
  } else {
    OPL_WritePort(OPL_REGISTER_PORT, (unsigned int)reg);
  }
  OPL_WritePort(OPL_DATA_PORT, (unsigned int)value);
}

opl_init_result_t OPL_Detect(void) { return OPL_INIT_OPL3; }

void OPL_InitRegisters(int opl3) {
  int r;

  for (r = OPL_REGS_LEVEL; r <= OPL_REGS_LEVEL + OPL_NUM_OPERATORS; ++r) {
    OPL_WriteRegister(r, 0x3f);
  }

  for (r = OPL_REGS_ATTACK; r <= OPL_REGS_WAVEFORM + OPL_NUM_OPERATORS; ++r) {
    OPL_WriteRegister(r, 0x00);
  }

  for (r = 1; r < OPL_REGS_LEVEL; ++r) {
    OPL_WriteRegister(r, 0x00);
  }

  OPL_WriteRegister(OPL_REG_TIMER_CTRL, 0x60);
  OPL_WriteRegister(OPL_REG_TIMER_CTRL, 0x80);
  OPL_WriteRegister(OPL_REG_WAVEFORM_ENABLE, 0x20);

  if (opl3) {
    OPL_WriteRegister(OPL_REG_NEW, 0x01);

    for (r = OPL_REGS_LEVEL; r <= OPL_REGS_LEVEL + OPL_NUM_OPERATORS; ++r) {
      OPL_WriteRegister(r | 0x100, 0x3f);
    }

    for (r = OPL_REGS_ATTACK; r <= OPL_REGS_WAVEFORM + OPL_NUM_OPERATORS;
         ++r) {
      OPL_WriteRegister(r | 0x100, 0x00);
    }

    for (r = 1; r < OPL_REGS_LEVEL; ++r) {
      OPL_WriteRegister(r | 0x100, 0x00);
    }
  }

  OPL_WriteRegister(OPL_REG_FM_MODE, 0x40);

  if (opl3) {
    OPL_WriteRegister(OPL_REG_NEW, 0x01);
  }
}

void OPL_SetCallback(uint64_t us, opl_callback_t callback, void* data) {
  if (!iwadr_opl_initialized || callback == NULL) {
    return;
  }

  ma_mutex_lock(&iwadr_opl_queue_mutex);
  OPL_Queue_Push(iwadr_opl_callback_queue, callback, data,
                 iwadr_opl_current_time - iwadr_opl_pause_offset + us);
  ma_mutex_unlock(&iwadr_opl_queue_mutex);
}

void OPL_AdjustCallbacks(float factor) {
  if (!iwadr_opl_initialized) {
    return;
  }

  ma_mutex_lock(&iwadr_opl_queue_mutex);
  OPL_Queue_AdjustCallbacks(iwadr_opl_callback_queue, iwadr_opl_current_time,
                            factor);
  ma_mutex_unlock(&iwadr_opl_queue_mutex);
}

void OPL_ClearCallbacks(void) {
  if (!iwadr_opl_initialized) {
    return;
  }

  ma_mutex_lock(&iwadr_opl_queue_mutex);
  OPL_Queue_Clear(iwadr_opl_callback_queue);
  ma_mutex_unlock(&iwadr_opl_queue_mutex);
}

void OPL_Lock(void) {
  if (iwadr_opl_mutexes_initialized) {
    ma_mutex_lock(&iwadr_opl_callback_mutex);
  }
}

void OPL_Unlock(void) {
  if (iwadr_opl_mutexes_initialized) {
    ma_mutex_unlock(&iwadr_opl_callback_mutex);
  }
}

void OPL_Delay(uint64_t us) { (void)us; }

void OPL_SetPaused(int paused) { iwadr_opl_paused = paused ? 1 : 0; }

static void iwadr_opl_advance_time(unsigned int frame_count) {
  opl_callback_t callback;
  void* callback_data;
  uint64_t us;

  if (!iwadr_opl_initialized) {
    return;
  }

  ma_mutex_lock(&iwadr_opl_queue_mutex);

  us = ((uint64_t)frame_count * OPL_SECOND) / opl_sample_rate;
  iwadr_opl_current_time += us;

  if (iwadr_opl_paused) {
    iwadr_opl_pause_offset += us;
  }

  while (!OPL_Queue_IsEmpty(iwadr_opl_callback_queue) &&
         iwadr_opl_current_time >=
             OPL_Queue_Peek(iwadr_opl_callback_queue) +
                 iwadr_opl_pause_offset) {
    if (!OPL_Queue_Pop(iwadr_opl_callback_queue, &callback, &callback_data)) {
      break;
    }

    ma_mutex_unlock(&iwadr_opl_queue_mutex);
    ma_mutex_lock(&iwadr_opl_callback_mutex);
    callback(callback_data);
    ma_mutex_unlock(&iwadr_opl_callback_mutex);
    ma_mutex_lock(&iwadr_opl_queue_mutex);
  }

  ma_mutex_unlock(&iwadr_opl_queue_mutex);
}

static unsigned int iwadr_opl_frames_until_next_callback(
    unsigned int max_frames) {
  uint64_t next_callback_time;
  uint64_t delta;
  uint64_t frames;

  ma_mutex_lock(&iwadr_opl_queue_mutex);
  if (iwadr_opl_paused || OPL_Queue_IsEmpty(iwadr_opl_callback_queue)) {
    ma_mutex_unlock(&iwadr_opl_queue_mutex);
    return max_frames;
  }

  next_callback_time =
      OPL_Queue_Peek(iwadr_opl_callback_queue) + iwadr_opl_pause_offset;
  if (next_callback_time <= iwadr_opl_current_time) {
    ma_mutex_unlock(&iwadr_opl_queue_mutex);
    return 0;
  }

  delta = next_callback_time - iwadr_opl_current_time;
  frames = (delta * opl_sample_rate + OPL_SECOND - 1) / OPL_SECOND;
  ma_mutex_unlock(&iwadr_opl_queue_mutex);

  if (frames > max_frames) {
    return max_frames;
  }
  return (unsigned int)frames;
}

void iwadr_opl_mix_float(float* output, unsigned int frame_count) {
  int16_t pcm[IWADR_OPL_MIX_CHUNK * 2];
  unsigned int filled = 0;

  if (!iwadr_opl_initialized || output == NULL) {
    return;
  }

  while (filled < frame_count) {
    unsigned int frames =
        iwadr_opl_frames_until_next_callback(frame_count - filled);

    if (frames > IWADR_OPL_MIX_CHUNK) {
      frames = IWADR_OPL_MIX_CHUNK;
    }

    if (frames > 0) {
      memset(pcm, 0, frames * 2 * sizeof(int16_t));
      OPL3_GenerateStream(&iwadr_opl_chip, pcm, frames);

      for (unsigned int i = 0; i < frames; i++) {
        float left_sample;
        float right_sample;
        int left_output_milli;
        int right_output_milli;
        int output_milli;
        int left_jump_milli;
        int right_jump_milli;
        int jump_milli;
        int left_abs = pcm[i * 2 + 0] < 0 ? -pcm[i * 2 + 0] : pcm[i * 2 + 0];
        int right_abs = pcm[i * 2 + 1] < 0 ? -pcm[i * 2 + 1] : pcm[i * 2 + 1];
        int sample_abs = left_abs > right_abs ? left_abs : right_abs;
        if (sample_abs != 0) {
          iwadr_opl_nonzero_mixes++;
        }
        if (sample_abs > iwadr_opl_peak_sample_value) {
          iwadr_opl_peak_sample_value = sample_abs;
        }

        left_sample = ((float)pcm[i * 2 + 0] / 32768.0f) * IWADR_OPL_GAIN;
        right_sample = ((float)pcm[i * 2 + 1] / 32768.0f) * IWADR_OPL_GAIN;
        iwadr_opl_filter_left +=
            iwadr_opl_filter_alpha * (left_sample - iwadr_opl_filter_left);
        iwadr_opl_filter_right +=
            iwadr_opl_filter_alpha * (right_sample - iwadr_opl_filter_right);

        left_output_milli = iwadr_opl_float_to_milli(iwadr_opl_filter_left);
        right_output_milli = iwadr_opl_float_to_milli(iwadr_opl_filter_right);
        output_milli =
            left_output_milli > right_output_milli ? left_output_milli
                                                   : right_output_milli;
        if (output_milli > iwadr_opl_peak_output_milli_value) {
          iwadr_opl_peak_output_milli_value = output_milli;
        }

        left_jump_milli =
            iwadr_opl_float_to_milli(iwadr_opl_filter_left - iwadr_opl_previous_left);
        right_jump_milli =
            iwadr_opl_float_to_milli(iwadr_opl_filter_right - iwadr_opl_previous_right);
        jump_milli =
            left_jump_milli > right_jump_milli ? left_jump_milli : right_jump_milli;
        if (jump_milli > iwadr_opl_max_jump_milli_value) {
          iwadr_opl_max_jump_milli_value = jump_milli;
        }
        iwadr_opl_previous_left = iwadr_opl_filter_left;
        iwadr_opl_previous_right = iwadr_opl_filter_right;

        output[(filled + i) * 2 + 0] += iwadr_opl_filter_left;
        output[(filled + i) * 2 + 1] += iwadr_opl_filter_right;
      }

      iwadr_opl_mixed_frames += (int)frames;
      filled += frames;
      iwadr_opl_advance_time(frames);
    } else {
      iwadr_opl_advance_time(0);
    }
  }
}

FFI_PLUGIN_EXPORT int iwadr_opl_mixed_frame_count(void) {
  return iwadr_opl_mixed_frames;
}

FFI_PLUGIN_EXPORT int iwadr_opl_nonzero_mix_count(void) {
  return iwadr_opl_nonzero_mixes;
}

FFI_PLUGIN_EXPORT int iwadr_opl_peak_sample(void) {
  return iwadr_opl_peak_sample_value;
}

FFI_PLUGIN_EXPORT int iwadr_opl_peak_output_milli(void) {
  return iwadr_opl_peak_output_milli_value;
}

FFI_PLUGIN_EXPORT int iwadr_opl_max_jump_milli(void) {
  return iwadr_opl_max_jump_milli_value;
}
