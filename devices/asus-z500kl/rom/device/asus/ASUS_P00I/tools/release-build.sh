#!/bin/bash
# Build a release of LineageOS for ASUS_P00I with its own fingerprint.
#
#   device/asus/ASUS_P00I/tools/release-build.sh payne_17
#
# Run from the top of the Android tree, after `source build/envsetup.sh` and
# `lunch lineage_ASUS_P00I-userdebug`.
#
# The fingerprint's build-number field is P00I_RELEASE (see BoardConfig.mk). Setting
# it is not enough on an incremental tree: no property file depends on the
# fingerprint, so build.prop, vendor/build.prop and default.prop would keep the old
# value -- or worse, some would be regenerated for other reasons and some not, and the
# two halves would disagree, which is the "internal problem with your device" dialog
# the fixed fingerprint exists to prevent. So they are removed first, and the build
# has to write all of them with the new name.
set -euo pipefail
release=${1:?usage: $0 <release name, e.g. payne_17>}
case $release in *[!A-Za-z0-9_.-]*|dev) echo "error: bad release name: $release" >&2; exit 2 ;; esac
[ -n "${ANDROID_PRODUCT_OUT:-}" ] || { echo "error: run lunch first" >&2; exit 2; }
out=$ANDROID_PRODUCT_OUT

for f in system/build.prop system/vendor/build.prop system/product/build.prop \
         root/default.prop recovery/root/default.prop \
         obj/ETC/system_build_prop_intermediates/build.prop; do
    rm -f "${out:?}/$f"
done

P00I_RELEASE=$release mka bacon

echo "fingerprints in the result:"
grep -h 'build.fingerprint=' "$out/system/build.prop" "$out/system/vendor/build.prop" "$out/root/default.prop"
if [ "$(grep -h 'build.fingerprint=' "$out/system/build.prop" "$out/system/vendor/build.prop" "$out/root/default.prop" | sed 's/^[^=]*=//' | sort -u | wc -l)" -ne 1 ]; then
    echo "error: the fingerprints differ" >&2
    exit 1
fi
