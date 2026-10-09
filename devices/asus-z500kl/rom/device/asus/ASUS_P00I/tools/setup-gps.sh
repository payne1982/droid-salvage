#!/bin/sh
#
# Fetch the GPS HAL source into this device tree (gps/), at a pinned commit.
#
# Run from the device directory inside the LineageOS tree:
#   cd <tree>/device/asus/ASUS_P00I && ./tools/setup-gps.sh
#
# Why not hardware/qcom/gps: that tree is an older loc_api than ASUS shipped. The
# stock libloc_api_v02.so -- the closed QMI bridge to the modem's location engine,
# which has to stay a blob -- is a subclass of LocApiBase from LA.BR.1.3.6, and links
# against a libloc_core with that class's layout: reportSv() taking a GnssSvStatus,
# getBestAvailableZppFix(), setLPPeProtocol() and more that hardware/qcom/gps lacks.
# Built from there, libloc_core would load the blob and call into the wrong vtable
# slots.
#
# This is the same HAL at the right version: CAF LA.BR.1.3.6_rb1.10, as LineageOS
# carries it for the Xiaomi Redmi Note 3 Pro (kenzo), same SoC. BoardConfig.mk points
# the build at it with USE_DEVICE_SPECIFIC_GPS. About a hundred files of Qualcomm's
# code, so it is fetched rather than committed here, the same way the kernel fetches
# prima.
#
# Not its etc/: those are kenzo's configuration files (a Chinese SUPL server from
# MIUI), and its gps.conf module would collide with ASUS' gps.conf, which
# proprietary-files.txt installs. What changes in the code to build on Pie is in
# tools/gps-patches/, applied here.

set -e

GPS_REMOTE=${GPS_REMOTE:-https://github.com/LineageOS/android_device_xiaomi_msm8956-common.git}
GPS_COMMIT=${GPS_COMMIT:-743eb8bba4e5bd2018c523bb556ea7df237dc09b}

here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$here"

if [ -f gps/Android.mk ]; then
    echo "==> reusing $here/gps"
    exit 0
fi

echo "==> fetching gps/ from $GPS_REMOTE at $GPS_COMMIT"
tmp=$(mktemp -d)
git -C "$tmp" init -q
git -C "$tmp" remote add origin "$GPS_REMOTE"
git -C "$tmp" sparse-checkout set --no-cone /gps/Android.mk /gps/core/ /gps/utils/ /gps/loc_api/
git -C "$tmp" fetch -q --depth=1 --filter=blob:none origin "$GPS_COMMIT"
git -C "$tmp" checkout -q FETCH_HEAD
cp -r "$tmp/gps" gps
rm -rf "${tmp:?}"

echo "==> applying patches"
for p in "$here"/tools/gps-patches/*.patch; do
    git apply --directory=gps -p1 "$p"
    echo "    applied $(basename "$p")"
done
echo "==> $(find gps -type f | wc -l) files in $here/gps"
