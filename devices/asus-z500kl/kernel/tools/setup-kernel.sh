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

if [ ! -d "$KERNEL_TREE/.git" ]; then
    echo "==> cloning $KERNEL_REMOTE into $KERNEL_TREE"
    git clone --depth=1 --single-branch "$KERNEL_REMOTE" "$KERNEL_TREE"
else
    echo "==> reusing $KERNEL_TREE"
fi

cd "$KERNEL_TREE"

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
