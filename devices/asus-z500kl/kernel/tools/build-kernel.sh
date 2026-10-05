#!/bin/sh
# Build the kernel for ASUS_P00I: arch/arm64/boot/Image.gz-dtb, ready to be
# packed into a boot or recovery image.
#
# Two things about this tree are not obvious:
#
#   * TARGET_PROJECT must be set. arch/arm64/boot/dts/qcom/Makefile builds
#     msm8956-v1.1-cdp-$(TARGET_PROJECT).dtb, and without it the DTB for this
#     tablet is simply not built -- the kernel then boots on nothing.
#
#   * CC must be overridden. The top-level Makefile sets
#       CC = $(srctree)/scripts/gcc-wrapper.py $(REAL_CC)
#     and that wrapper is a Python 2 script. Pointing CC straight at gcc skips
#     it; all it does is promote a list of warnings to errors.
#
# The toolchain is the AOSP prebuilt gcc 4.9 for aarch64. A 2026 gcc will not
# compile a 3.10 kernel, and the prebuilts are x86_64-only, so this has to run
# on an x86_64 host.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
repo_root=$(CDPATH= cd -- "$here/../../.." && pwd)
[ -f "$repo_root/local.conf" ] && . "$repo_root/local.conf"

KERNEL_TREE=${KERNEL_TREE:-$HOME/droid-salvage-build/kernel}
KERNEL_OUT=${KERNEL_OUT:-$KERNEL_TREE/out}
KERNEL_TOOLCHAIN=${KERNEL_TOOLCHAIN:-}
JOBS=${JOBS:-$(nproc)}

if [ -z "$KERNEL_TOOLCHAIN" ]; then
    echo "KERNEL_TOOLCHAIN is not set. Point it at the bin/ directory of an" >&2
    echo "aarch64-linux-android-4.9 prebuilt, e.g. inside a TWRP/LineageOS tree:" >&2
    echo "  <tree>/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin" >&2
    exit 1
fi

CROSS=$KERNEL_TOOLCHAIN/aarch64-linux-android-
[ -x "${CROSS}gcc" ] || { echo "no ${CROSS}gcc" >&2; exit 1; }

cd "$KERNEL_TREE"
mkdir -p "$KERNEL_OUT"

set -- ARCH=arm64 SUBARCH=arm64 \
       CROSS_COMPILE="$CROSS" \
       CC="${CROSS}gcc" \
       TARGET_PROJECT=Z500KL \
       O="$KERNEL_OUT"

echo "==> configuring (asus_P00I_defconfig)"
make "$@" asus_P00I_defconfig

echo "==> building with $JOBS jobs"
make "$@" -j"$JOBS" Image.gz-dtb

img=$KERNEL_OUT/arch/arm64/boot/Image.gz-dtb
ls -l "$img"
echo
if command -v python3 >/dev/null 2>&1; then
    echo "appended DTBs: $(python3 -c 'import sys;d=open(sys.argv[1],"rb").read();print(d.count(b"\xd0\x0d\xfe\xed"))' "$img")"
fi
echo
echo "Sanity check once it is running on the tablet:"
echo "  zcat /proc/config.gz | diff - $KERNEL_OUT/.config"
echo "should show nothing but CONFIG_IKCONFIG-related noise."
