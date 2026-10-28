#!/bin/sh
# Check out the 4.9 kernel this port starts from and make it this tablet's:
# copy in the files in files/ (device tree, battery profile, defconfig) and
# apply the patches in patches/, which are the changes to the kernel's own files.
#
# The base is the kernel of Sony's Open Devices program for the Xperia X family
# (Loire, MSM8956), as its maintainer carried it on to 4.9 on Qualcomm's
# LA.UM.9.8 tag. It is pinned at a commit, so the patches always meet the tree
# they were made against.
#
# Run it from anywhere; it writes only into $KERNEL_TREE. Running it again on a
# tree it has already prepared copies the files again and applies only what is new.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
repo_root=$(CDPATH= cd -- "$here/../../.." && pwd)
[ -f "$repo_root/local.conf" ] && . "$repo_root/local.conf"

KERNEL_TREE=${KERNEL_TREE:-$HOME/droid-salvage-build/kernel-4.9}
KERNEL_REMOTE=${KERNEL_REMOTE:-https://github.com/bartcubbins/kernel_loire.git}
KERNEL_COMMIT=${KERNEL_COMMIT:-ec3c488d0b7150e8421aa9f1d2337697391ce1b6}

# The exFAT driver, as for the 3.10 kernel (../kernel/tools/setup-kernel.sh):
# exfat-nofuse, the GPLv2 driver Samsung published in its Android kernels, at a
# pinned commit; Linux has its own only from 5.4. patches/0009 wires it into fs/.
EXFAT_REMOTE=${EXFAT_REMOTE:-https://github.com/dorimanx/exfat-nofuse.git}
EXFAT_COMMIT=${EXFAT_COMMIT:-01c30ad52625a7261e1b0d874553b6ca7af25966}

# The WLAN driver for the WCNSS Pronto core, Qualcomm's prima. Not in this tree,
# whose phone has a Broadcom chip; LineageOS carries it in-tree in its 4.9 kernel
# for MSM8953 devices, 4.9.227 like this one. 26 MB of driver, so it is fetched at
# a pinned commit, as for the 3.10 kernel; patches/0012 wires it into
# drivers/staging.
PRIMA_REMOTE=${PRIMA_REMOTE:-https://github.com/LineageOS/android_kernel_xiaomi_msm8953.git}
PRIMA_COMMIT=${PRIMA_COMMIT:-0ac2c6831eabb90d18f49081bc2221a715763e50}

if [ ! -d "$KERNEL_TREE/.git" ]; then
    echo "==> fetching $KERNEL_REMOTE at $KERNEL_COMMIT into $KERNEL_TREE"
    mkdir -p "$KERNEL_TREE"
    git -C "$KERNEL_TREE" init -q
    git -C "$KERNEL_TREE" remote add origin "$KERNEL_REMOTE"
    git -C "$KERNEL_TREE" fetch -q --depth=1 origin "$KERNEL_COMMIT"
    git -C "$KERNEL_TREE" checkout -q FETCH_HEAD
else
    echo "==> reusing $KERNEL_TREE"
fi

cd "$KERNEL_TREE"

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

echo "==> copying files/"
cp -r "$here/files/." .

echo "==> applying patches"
# As in ../kernel: the ones already in the tree are the first few, and the last of
# those is the one that reverses cleanly.
set -- "$here"/patches/*.patch
applied=0
n=0
for p; do
    n=$((n + 1))
    if git apply -p0 --reverse --check "$p" 2>/dev/null; then
        applied=$n
    fi
done
n=0
for p; do
    n=$((n + 1))
    if [ "$n" -le "$applied" ]; then
        echo "    already applied $(basename "$p")"
    elif git apply -p0 --check "$p" 2>/dev/null; then
        git apply -p0 "$p"
        echo "    applied $(basename "$p")"
    else
        echo "    FAILED $(basename "$p")" >&2
        exit 1
    fi
done

echo
echo "Ready. Next: $here/tools/build-kernel.sh"
