#!/bin/bash
# Pull the device-specific pieces this tree needs out of the tablet itself, so that no
# vendor binary has to live in the repository and the committed tree still builds the
# exact image that is published.
#
# Usage, with the tablet reachable over adb (TWRP, or Android with root):
#
#   ./tools/extract-from-device.sh
#
# What it takes, and why each piece is needed:
#
#   prebuilt/kernel.stock   The stock Image.gz-dtb, read from the *boot* partition, not
#                           recovery: both carry the same kernel, and boot keeps the
#                           stock one even after Magisk patches it (Magisk only rewrites
#                           the ramdisk), whereas recovery stops being stock the moment
#                           you flash this TWRP.
#   prebuilt/kernel         The same kernel with the 3-byte mxt_probe patch, which is
#                           what makes the digitiser work in recovery. The reasoning is
#                           in tools/patch-kernel.py.
#   .../mTX1666T2_cfg.raw   Atmel touch controller config. 15 s after boot the driver
#                           re-checks its config; without this file it gives the chip
#                           five soft resets looking for it.
#   .../property_contexts   The Nougat prefix->context index. Stock Nougat binaries
#                           cannot read *any* property without it under a Pie-based
#                           recovery, which is what made vold load the software
#                           keymaster and reject a correct PIN. Taken from the stock
#                           boot ramdisk rather than from the live filesystem, because
#                           under TWRP the live copy is the one this tree installed and
#                           extracting it would be circular.
set -euo pipefail
cd "$(dirname "$0")/.."

ADB=${ADB:-adb}
BOOT_PART=/dev/block/mmcblk0p41       # see recovery.fstab for the whole partition map
SYSTEM_PART=/dev/block/mmcblk0p44

say() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# TWRP's adb shell is already root; Android needs su.
if $ADB shell id 2>/dev/null | grep -q 'uid=0'; then
	run() { $ADB shell "$1"; }
elif $ADB shell 'su -c id' 2>/dev/null | grep -q 'uid=0'; then
	run() { $ADB shell "su -c '$1'"; }
else
	die "need a root shell over adb (TWRP, or Android with root)"
fi

mkdir -p prebuilt recovery/root/etc/firmware recovery/root/lib/firmware
trap 'rm -f prebuilt/boot.img.tmp prebuilt/ramdisk.cpio.gz.tmp' EXIT

say "reading the boot partition"
run "dd if=$BOOT_PART bs=1048576 2>/dev/null" > prebuilt/boot.img.tmp

say "splitting out the kernel and the ramdisk"
python3 - prebuilt/boot.img.tmp prebuilt/kernel.stock prebuilt/ramdisk.cpio.gz.tmp <<'PYEOF'
import struct, sys
src, kdst, rdst = sys.argv[1], sys.argv[2], sys.argv[3]
d = open(src, "rb").read()
if d[:8] != b"ANDROID!":
    sys.exit("not an Android boot image - wrong partition?")
kernel_size,  = struct.unpack_from("<I", d, 8)
ramdisk_size, = struct.unpack_from("<I", d, 16)
page_size,    = struct.unpack_from("<I", d, 36)
pad = lambda n: (n + page_size - 1) // page_size * page_size
kernel = d[page_size:page_size + kernel_size]
if kernel[:2] != b"\x1f\x8b":
    sys.exit("kernel is not gzip - unexpected image layout")
open(kdst, "wb").write(kernel)
off = page_size + pad(kernel_size)
open(rdst, "wb").write(d[off:off + ramdisk_size])
print(f"    kernel {len(kernel)} bytes, ramdisk {ramdisk_size} bytes")
PYEOF

say "applying the touch patch"
python3 tools/patch-kernel.py prebuilt/kernel.stock prebuilt/kernel

say "taking property_contexts out of the stock boot ramdisk"
zcat prebuilt/ramdisk.cpio.gz.tmp \
	| cpio -i --quiet --to-stdout property_contexts \
	> recovery/root/property_contexts
grep -q 'u:object_r:' recovery/root/property_contexts \
	|| die "property_contexts does not look like a Nougat contexts file"

say "pulling the Atmel touch config"
run "mount -o ro $SYSTEM_PART /system 2>/dev/null; cat /system/etc/firmware/mTX1666T2_cfg.raw" \
	> recovery/root/etc/firmware/mTX1666T2_cfg.raw
head -c 10 recovery/root/etc/firmware/mTX1666T2_cfg.raw | grep -q 'OBP_RAW' \
	|| die "touch config does not look like an OBP_RAW file"
cp recovery/root/etc/firmware/mTX1666T2_cfg.raw recovery/root/lib/firmware/

say "done"
ls -l prebuilt/kernel prebuilt/kernel.stock \
	recovery/root/property_contexts \
	recovery/root/etc/firmware/mTX1666T2_cfg.raw
