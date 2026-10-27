#!/bin/sh
# Build the 4.9 kernel for ASUS_P00I: $KERNEL_OUT/arch/arm64/boot/Image.gz-dtb,
# with this tablet's device tree appended.
#
# The toolchain is the AOSP prebuilt gcc 4.9 for aarch64, as for the 3.10 kernel
# (../kernel/tools/build-kernel.sh); the one in LineageOS 20's prebuilts does. The
# prebuilts are x86_64-only, so this has to run on an x86_64 host.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
repo_root=$(CDPATH= cd -- "$here/../../.." && pwd)
[ -f "$repo_root/local.conf" ] && . "$repo_root/local.conf"

KERNEL_TREE=${KERNEL_TREE:-$HOME/droid-salvage-build/kernel-4.9}
KERNEL_OUT=${KERNEL_OUT:-$KERNEL_TREE/out}
KERNEL_TOOLCHAIN=${KERNEL_TOOLCHAIN:-}
JOBS=${JOBS:-$(nproc)}

if [ -z "$KERNEL_TOOLCHAIN" ]; then
    echo "KERNEL_TOOLCHAIN is not set. Point it at the bin/ directory of an" >&2
    echo "aarch64-linux-android-4.9 prebuilt, e.g. inside a LineageOS tree:" >&2
    echo "  <tree>/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin" >&2
    exit 1
fi

PATH=$KERNEL_TOOLCHAIN:$PATH
export PATH
set -- -C "$KERNEL_TREE" O="$KERNEL_OUT" ARCH=arm64 \
    CROSS_COMPILE=aarch64-linux-android- \
    KBUILD_BUILD_USER=payne1982 KBUILD_BUILD_HOST=droid-salvage

make "$@" z500kl_defconfig
make "$@" -j"$JOBS"

echo
echo "Built: $KERNEL_OUT/arch/arm64/boot/Image.gz-dtb"
