/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef IRIS2_CMD_VALIDATE_H
#define IRIS2_CMD_VALIDATE_H

#include <linux/errno.h>

/* ASUS bundle format: count, count one-byte lengths, dtype/payload blocks. */
static inline int iris2_validate_multi(const unsigned char *data,
		unsigned int length, unsigned int tx_capacity)
{
	unsigned int count, pos, i, bytes, encoded = 0;

	if (!data || !length)
		return -EINVAL;
	count = data[0];
	if (!count || count > length - 1)
		return -EINVAL;
	pos = count + 1;
	for (i = 0; i < count; i++) {
		bytes = data[i + 1];
		if (!bytes || bytes > length - pos)
			return -EINVAL;
		/* A long DSI packet adds a four-byte header and aligns its payload. */
		encoded += ((bytes - 1 + 3) & ~3U) + 4;
		if (encoded > tx_capacity)
			return -EINVAL;
		pos += bytes;
	}
	return count;
}
#endif
