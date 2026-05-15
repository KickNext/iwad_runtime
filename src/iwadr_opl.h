#ifndef IWADR_OPL_H_
#define IWADR_OPL_H_

#include "iwadr.h"

void iwadr_opl_mix_float(float* output, unsigned int frame_count);
FFI_PLUGIN_EXPORT int iwadr_opl_mixed_frame_count(void);
FFI_PLUGIN_EXPORT int iwadr_opl_nonzero_mix_count(void);
FFI_PLUGIN_EXPORT int iwadr_opl_peak_sample(void);
FFI_PLUGIN_EXPORT int iwadr_opl_peak_output_milli(void);

#endif  // IWADR_OPL_H_
