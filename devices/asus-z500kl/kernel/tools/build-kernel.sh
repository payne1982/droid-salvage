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

# Pick the real compiler. In the AOSP prebuilts "<prefix>gcc" is a Python 2 wrapper
# that re-executes "real-<prefix>gcc"; in some checkouts that real- file is simply
# not there, so the wrapper cannot work at all. "<prefix>gcc-4.9.x" is the actual
# driver binary. Prefer whichever is a real executable, never the wrapper.
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

# ccache pays for itself here: this kernel gets rebuilt for every configuration
# change and every driver patch, and a full build is a long time on a laptop.
if [ "${USE_CCACHE:-0}" = 1 ] && command -v ccache >/dev/null 2>&1; then
    CC_REAL="ccache $CC_REAL"
    echo "==> ccache: $(ccache -s 2>/dev/null | sed -n 's/^  *Cache size.*: *//p' | head -1)"
fi

cd "$KERNEL_TREE"
mkdir -p "$KERNEL_OUT"

# The host tools (scripts/dtc, scripts/mod, ...) are built with the *system* gcc.
# A 2015 tree does not survive a 2026 one unmodified: since gcc 10 the default is
# -fno-common, and scripts/dtc declares yylloc in both the lexer and the parser, so
# it fails to link with "multiple definition of yylloc". Restoring -fcommon fixes
# that whole class of breakage without touching the sources. The flags before it are
# the tree's own defaults, kept as they are.
HOSTCFLAGS="-Wall -Wmissing-prototypes -Wstrict-prototypes -O2 -fomit-frame-pointer -std=gnu89 -fcommon"

set -- ARCH=arm64 SUBARCH=arm64 \
       CROSS_COMPILE="$CROSS" \
       CC="$CC_REAL" \
       HOSTCFLAGS="$HOSTCFLAGS" \
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
echo "Sanity check: the configuration is embedded in the image (CONFIG_IKCONFIG), so"
echo "it can be read back out of it. CONFIG_IKCONFIG_PROC is not set, so there is no"
echo "/proc/config.gz on the device -- compare the images instead:"
echo "  $KERNEL_TREE/scripts/extract-ikconfig $KERNEL_OUT/arch/arm64/boot/Image \\"
echo "    | diff - <($KERNEL_TREE/scripts/extract-ikconfig <stock Image>)"
