#!/bin/sh
# Check out the ASUS kernel sources and make them buildable.
#
# ASUS published the sources but not the per-project _diffconfig their build
# system expects, so a plain checkout cannot be configured at all. This script
# applies the one patch that fixes that and installs the recovered defconfig.
#
# Run it from anywhere; it writes only into $KERNEL_TREE.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
repo_root=$(CDPATH= cd -- "$here/../../.." && pwd)
[ -f "$repo_root/local.conf" ] && . "$repo_root/local.conf"

KERNEL_TREE=${KERNEL_TREE:-$HOME/droid-salvage-build/kernel}
KERNEL_REMOTE=${KERNEL_REMOTE:-https://github.com/6ccg/android_kernel_asus_z500kl.git}

# The WLAN driver. ASUS built theirs out of tree from a repository they did not
# publish, and the stock wlan.ko will not load on a kernel we build (vermagic). This is
# Qualcomm's prima for the WCNSS Pronto core, as LineageOS carries it in-tree for the
# Xiaomi Redmi Note 3 Pro (kenzo): same SoC, same CAF 3.10 base, CAF tag
# LA.BR.1.3.6_rb1.19. 28 MB of driver, so it is fetched at a pinned commit rather than
# committed here as a patch; patches/0009 wires it into drivers/staging.
PRIMA_REMOTE=${PRIMA_REMOTE:-https://github.com/LineageOS/android_kernel_xiaomi_msm8956.git}
PRIMA_COMMIT=${PRIMA_COMMIT:-07cdc182da45ce1edc6a589e20eb3e72d0b9792e}

# The exFAT driver. Stock used Tuxera's closed texfat.ko, which will not load on a
# kernel we build either, and Linux has its own only from 5.4. This is exfat-nofuse,
# the GPLv2 driver Samsung published in its Android kernels, version 1.2.9; it is a
# separate repository, so it is fetched at a pinned commit, and patches/0013 wires it
# into fs/.
EXFAT_REMOTE=${EXFAT_REMOTE:-https://github.com/dorimanx/exfat-nofuse.git}
EXFAT_COMMIT=${EXFAT_COMMIT:-01c30ad52625a7261e1b0d874553b6ca7af25966}

if [ ! -d "$KERNEL_TREE/.git" ]; then
    echo "==> cloning $KERNEL_REMOTE into $KERNEL_TREE"
    git clone --depth=1 --single-branch "$KERNEL_REMOTE" "$KERNEL_TREE"
else
    echo "==> reusing $KERNEL_TREE"
fi

cd "$KERNEL_TREE"

if [ ! -f drivers/staging/prima/Kconfig ]; then
    echo "==> fetching prima from $PRIMA_REMOTE at $PRIMA_COMMIT"
    tmp=$(mktemp -d)
    git -C "$tmp" init -q
    git -C "$tmp" remote add origin "$PRIMA_REMOTE"
    git -C "$tmp" sparse-checkout set --no-cone /drivers/staging/prima/
    git -C "$tmp" fetch -q --depth=1 --filter=blob:none origin "$PRIMA_COMMIT"
    git -C "$tmp" checkout -q FETCH_HEAD
    cp -r "$tmp/drivers/staging/prima" drivers/staging/prima
    rm -rf "${tmp:?}"
else
    echo "==> reusing drivers/staging/prima"
fi

if [ ! -f fs/exfat/Kconfig ]; then
    echo "==> fetching exfat from $EXFAT_REMOTE at $EXFAT_COMMIT"
    tmp=$(mktemp -d)
    git -C "$tmp" init -q
    git -C "$tmp" remote add origin "$EXFAT_REMOTE"
    git -C "$tmp" fetch -q --depth=1 origin "$EXFAT_COMMIT"
    git -C "$tmp" checkout -q FETCH_HEAD
    mkdir fs/exfat
    # the kernel sources and the licence; not the DKMS and standalone-module files
    cp "$tmp"/*.c "$tmp"/*.h "$tmp"/Kconfig "$tmp"/Makefile "$tmp"/LICENSE fs/exfat/
    rm -rf "${tmp:?}"
else
    echo "==> reusing fs/exfat"
fi

echo "==> applying patches"
for p in "$here"/patches/*.patch; do
    if git apply -p0 --check "$p" 2>/dev/null; then
        git apply -p0 "$p"
        echo "    applied $(basename "$p")"
    elif git apply -p0 --reverse --check "$p" 2>/dev/null; then
        echo "    already applied $(basename "$p")"
    else
        echo "    FAILED $(basename "$p")" >&2
        exit 1
    fi
done

echo "==> installing asus_P00I_defconfig"
cp "$here/asus_P00I_defconfig" arch/arm64/configs/asus_P00I_defconfig

echo
echo "Ready. Next: $here/tools/build-kernel.sh"
