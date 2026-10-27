#!/bin/sh
# Pack the 4.9 kernel into a boot image to try it with: the kernel and the
# ramdisk of this repository's TWRP, which starts far less than Android and
# brings up adb. The image is written to the boot partition only, from TWRP,
# and the LineageOS boot image put back afterwards; README.md says how.
#
#   make-test-image.sh <twrp.img> <output.img>
#
# The ramdisk is TWRP's as it is, followed by a second cpio archive holding its
# init.recovery.qcom.rc with test/configfs-adb.rc appended: the kernel unpacks the
# archives in order, and the later file replaces the earlier one. Header and
# command line are TWRP's. The image is signed as the bootloader requires
# (../rom/device/asus/ASUS_P00I/device.mk, "Boot image signature").
#
# LINEAGE_OUT_HOST is out/host/linux-x86 of a LineageOS 20 build, for
# unpack_bootimg, mkbootimg and boot_signer; LINEAGE_TREE is its source tree,
# for AOSP's verity test key.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
repo_root=$(CDPATH= cd -- "$here/../../.." && pwd)
[ -f "$repo_root/local.conf" ] && . "$repo_root/local.conf"

KERNEL_TREE=${KERNEL_TREE:-$HOME/droid-salvage-build/kernel-4.9}
KERNEL_OUT=${KERNEL_OUT:-$KERNEL_TREE/out}
LINEAGE_TREE=${LINEAGE_TREE:-}
LINEAGE_OUT_HOST=${LINEAGE_OUT_HOST:-${LINEAGE_TREE:+$LINEAGE_TREE/out/host/linux-x86}}

if [ $# -ne 2 ] || [ -z "$LINEAGE_TREE" ]; then
    echo "usage: LINEAGE_TREE=<lineage-20 tree> $0 <twrp.img> <output.img>" >&2
    exit 1
fi
twrp=$1
output=$2
bin=$LINEAGE_OUT_HOST/bin
keys=$LINEAGE_TREE/build/make/target/product/security
kernel=$KERNEL_OUT/arch/arm64/boot/Image.gz-dtb

T=$(mktemp -d)
trap 'rm -rf "${T:?}"' EXIT

"$bin/unpack_bootimg" --boot_img "$twrp" --out "$T/twrp" > "$T/header"
cmdline=$(sed -n 's/^command line args: //p' "$T/header")

mkdir "$T/rootfs" "$T/overlay"
(cd "$T/rootfs" && gzip -dc "$T/twrp/ramdisk" | cpio -idm --quiet init.recovery.qcom.rc)
cat "$T/rootfs/init.recovery.qcom.rc" "$here/test/configfs-adb.rc" \
    > "$T/overlay/init.recovery.qcom.rc"
chmod 0750 "$T/overlay/init.recovery.qcom.rc"

cp "$T/twrp/ramdisk" "$T/ramdisk"
# the second archive starts on a 4-byte boundary
size=$(wc -c < "$T/ramdisk")
head -c $(( (4 - size % 4) % 4 )) /dev/zero >> "$T/ramdisk"
(cd "$T/overlay" && echo init.recovery.qcom.rc | cpio -o -H newc -R 0:0 --quiet) \
    | gzip -9n >> "$T/ramdisk"

"$bin/mkbootimg" --kernel "$kernel" --ramdisk "$T/ramdisk" \
    --base 0x80000000 --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 \
    --second_offset 0x00f00000 --tags_offset 0x00000100 --pagesize 2048 \
    --os_version 16.1.0 --os_patch_level 2099-12 --header_version 0 \
    --cmdline "$cmdline" -o "$T/unsigned.img"
"$bin/boot_signer" /boot "$T/unsigned.img" "$keys/verity.pk8" \
    "$keys/verity.x509.pem" "$output"

sha256sum "$output"
