/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef __Z500KL_ADSP_H__
#define __Z500KL_ADSP_H__

#include <linux/kconfig.h>
#include <linux/types.h>

/*
 * The Z500KL's ADSP firmware, ADSP.8976.2.6 of 2016, was written for the audio
 * driver of ASUS' 3.10 kernel. Commands that driver never sent can make it fail
 * or hang (AFE_MODULE_CLOCK_SET ends in a watchdog bite, PCM v4 in ADSP_EFAILED).
 * On this board the driver sends only the 3.10 protocol: older commands where
 * both exist, and -EOPNOTSUPP for what only the newer protocol can do.
 */
static inline bool z500kl_adsp_2016(void)
{
	return IS_ENABLED(CONFIG_SND_SOC_Z500KL);
}

#endif
