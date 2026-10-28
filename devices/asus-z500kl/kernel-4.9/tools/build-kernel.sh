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

CROSS=$KERNEL_TOOLCHAIN/aarch64-linux-android-

# CC is given explicitly, as for 3.10. The tree's Makefile runs the compiler
# through scripts/gcc-wrapper.py, a Python 2 script that crashes under Python 3
# on the first warning it has to print; and in the prebuilts "<prefix>gcc" is a
# wrapper script too. The first real executable of these is the compiler.
CC_REAL=
for cand in "${CROSS}gcc-4.9.x" "$KERNEL_TOOLCHAIN/real-aarch64-linux-android-gcc" "${CROSS}gcc"; do
    [ -x "$cand" ] || continue
    case $(head -c2 "$cand") in
        '#!') continue ;;   # a script wrapper, skip it
    esac
    CC_REAL=$cand
    break
done
[ -n "$CC_REAL" ] || { echo "no usable gcc under $KERNEL_TOOLCHAIN" >&2; exit 1; }
echo "==> compiler: $CC_REAL ($("$CC_REAL" -dumpversion))"

PATH=$KERNEL_TOOLCHAIN:$PATH
export PATH
set -- -C "$KERNEL_TREE" O="$KERNEL_OUT" ARCH=arm64 \
    CROSS_COMPILE=aarch64-linux-android- CC="$CC_REAL" \
    KBUILD_BUILD_USER=payne1982 KBUILD_BUILD_HOST=droid-salvage

make "$@" z500kl_defconfig
make "$@" -j"$JOBS"

echo
echo "Built: $KERNEL_OUT/arch/arm64/boot/Image.gz-dtb"
