/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef Z500KL_CAL_COMPAT_H
#define Z500KL_CAL_COMPAT_H
#ifdef __KERNEL__
#include <linux/string.h>
#include <linux/types.h>
#else
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#endif
/* The user payload may end before fields added by later CAF versions. Clear
 * the entire information area on every update, including reuse of a block. */
static inline bool z500kl_cal_copy_info(void *dest, size_t capacity,
				      const void *source, size_t length)
{
	if (length > capacity || (capacity && !dest) || (length && !source))
		return false;
	if (capacity)
		memset(dest, 0, capacity);
	if (length)
		memcpy(dest, source, length);
	return true;
}
#endif
