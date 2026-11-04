/* SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note */
#ifndef __MSM_VIDC_Z500KL_H__
#define __MSM_VIDC_Z500KL_H__

#include <linux/videodev2.h>

/* Explicit session close for the source-built msm8952 OMX components.
 * Native decoder STOP keeps its 4.9 EOS semantics. Event +4 is already used
 * by BITDEPTH_CHANGED_INSUFFICIENT and must never be reused as CLOSE_DONE.
 */
#define MSM_VIDC_Z500KL_CMD_SESSION_CLOSE 0x7f000001U
#define MSM_VIDC_Z500KL_EVENT_SESSION_CLOSE_DONE \
	(V4L2_EVENT_MSM_VIDC_START + 0x100)

#endif
