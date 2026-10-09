#!/bin/sh
# Build vendor/asus/ASUS_P00I from the stock Android 7.0 system, and bring ASUS' init
# scripts into the device tree.
#
# Two sources, and the dump is the better one:
#
#   --from-dumps <system.img> <boot.img>   reads the partition images directly with
#                                          debugfs. No root, no mounting, no device --
#                                          which matters, because the people who need
#                                          this most are the ones whose tablet does not
#                                          boot. It is also reproducible: the same dump
#                                          gives the same output every time.
#
#   --from-device                          pulls from a running tablet over adb, in
#                                          recovery or in a rooted Android.
#
# Nothing here is committed to the repository: the blobs are not ours to redistribute,
# and ASUS' init scripts are theirs. Both are reproduced from your own tablet.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
device=ASUS_P00I
list=$here/proprietary-files.txt

# Where the Android tree starts. Inside one, this directory is <top>/device/asus/<dev>,
# so the top is three levels up -- but ANDROID_BUILD_TOP is what the build itself uses,
# so prefer it when envsetup.sh has been sourced.
if [ -n "${ANDROID_BUILD_TOP:-}" ]; then
    top=$ANDROID_BUILD_TOP
else
    top=$(CDPATH= cd -- "$here/../../.." && pwd)
fi
vendor_dir=$top/vendor/asus/$device
[ -d "$top/build" ] || printf 'warning: %s does not look like an Android tree\n' "$top" >&2

# ASUS' own init scripts. Deliberately not the AOSP ones (init.rc, init.environ.rc,
# init.usb.rc, init.zygote*.rc): those belong to the platform and the build provides
# them. fstab.qcom is excluded too -- ours is in rootdir/etc and is not a copy.
INIT_FILES="init.qcom.rc init.target.rc init.qcom.usb.rc init.carrier.rc
            init.logtool.rc init.qcom.factory.rc init.largeram.rc init.normalram.rc
            init.smallram.rc ueventd.qcom.rc init.class_main.sh init.mdm.sh
            init.qcom.bms.sh init.qcom.class_core.sh init.qcom.early_boot.sh
            init.qcom.sh init.qcom.syspart_fixup.sh init.qcom.usb.sh"

say() { printf '==> %s\n' "$1"; }
die() { printf 'error: %s\n' "$1" >&2; exit 1; }

mode=
sys_img=
boot_img=
case "${1:-}" in
    --from-dumps)
        mode=dumps
        sys_img=${2:-}; boot_img=${3:-}
        [ -f "$sys_img" ] || die "system image not found: ${sys_img:-<missing>}"
        [ -f "$boot_img" ] || die "boot image not found: ${boot_img:-<missing>}"
        command -v debugfs >/dev/null || die "debugfs not found (install e2fsprogs)"
        ;;
    --from-device)
        mode=device
        command -v adb >/dev/null || die "adb not found"
        adb get-state >/dev/null 2>&1 || die "no device over adb"
        ;;
    *)
        cat >&2 <<USAGE
usage: $0 --from-dumps <system.img> <boot.img>
       $0 --from-device
USAGE
        exit 2
        ;;
esac

# ---------------------------------------------------------------------------------
# 1. the blobs
# ---------------------------------------------------------------------------------
[ -f "$list" ] || die "missing $list"
# An entry is a path under the stock /system, optionally followed by ":destination"
# when the file has to land somewhere else in our system (the LineageOS convention):
#   etc/mixer_paths.xml:vendor/etc/mixer_paths.xml
# The stock file is read from the first path; everything after that -- where it is
# kept under proprietary/, where it is installed -- uses the destination.
entries=$(grep -vE '^\s*(#|$)' "$list")
src_of() { printf '%s' "${1%%:*}"; }
dst_of() { case $1 in *:*) printf '%s' "${1#*:}" ;; *) printf '%s' "$1" ;; esac; }
files=$(printf '%s\n' $entries | while read -r e; do [ -n "$e" ] && dst_of "$e" && echo; done)
count=$(printf '%s\n' "$entries" | grep -c .)
say "extracting $count proprietary files into vendor/asus/$device/proprietary"

rm -rf "$vendor_dir/proprietary"
mkdir -p "$vendor_dir/proprietary"

# create the directory tree first, so one debugfs run can do every file
printf '%s\n' $files | while read -r f; do
    [ -n "$f" ] || continue
    mkdir -p "$vendor_dir/proprietary/$(dirname "$f")"
done

if [ "$mode" = dumps ]; then
    cmds=$(mktemp)
    printf '%s\n' $entries | while read -r e; do
        [ -n "$e" ] || continue
        printf 'dump -p /%s %s\n' "$(src_of "$e")" "$vendor_dir/proprietary/$(dst_of "$e")"
    done > "$cmds"
    debugfs -f "$cmds" "$sys_img" >/dev/null 2>&1 || true
    rm -f "$cmds"
else
    printf '%s\n' $entries | while read -r e; do
        [ -n "$e" ] || continue
        adb pull "/system/$(src_of "$e")" "$vendor_dir/proprietary/$(dst_of "$e")" >/dev/null 2>&1 || true
    done
fi

# An empty file is worse than an absent one: an empty .so fails at load time with
# nothing to point at, and a zero-byte firmware blob fails silently. The usual cause is
# a symlink in the stock system -- debugfs dumps nothing for those -- so count only
# files with content, and remove the empty ones rather than leaving them behind.
printf '%s\n' $files | while read -r f; do
    [ -n "$f" ] || continue
    if [ ! -s "$vendor_dir/proprietary/$f" ]; then
        printf '    EMPTY OR MISSING: %s\n' "$f" >&2
        rm -f "$vendor_dir/proprietary/$f"
    fi
done
got=$(find "$vendor_dir/proprietary" -type f -size +0 | wc -l)
say "got $got of $count"
if [ "$got" -ne "$count" ]; then
    printf 'error: %d file(s) did not come out -- listed above.\n' "$((count-got))" >&2
    printf '       If one is a symlink in the stock system, take it out of\n' >&2
    printf '       proprietary-files.txt and keep its target instead.\n' >&2
    exit 1
fi

# ---------------------------------------------------------------------------------
# 2. the makefiles
# ---------------------------------------------------------------------------------
# Libraries and firmware go through PRODUCT_COPY_FILES, which is enough for anything
# loaded with dlopen. Files under bin/ cannot: PRODUCT_COPY_FILES installs them 0644 and
# they would never run, so those become prebuilt modules, which keeps the execute bit.
say "generating the vendor makefiles"
{
    printf '# Generated by %s -- do not edit.\n\n' "$(basename "$0")"
    # No PRODUCT_SOONG_NAMESPACES here: Soong requires an Android.bp in any directory
    # declared as a namespace, and this one has only an Android.mk. Declaring it would
    # fail the build. That line belongs to Treble device trees, not to this one.
    printf 'PRODUCT_COPY_FILES += \\\n'
    printf '%s\n' $files | grep -v '^bin/' | while read -r f; do
        [ -n "$f" ] || continue
        printf '    vendor/asus/%s/proprietary/%s:$(TARGET_COPY_OUT_SYSTEM)/%s \\\n' "$device" "$f" "$f"
    done
    printf '\n'
    bins=$(printf '%s\n' $files | grep '^bin/' | sed 's|^bin/||' || true)
    if [ -n "$bins" ]; then
        printf 'PRODUCT_PACKAGES += \\\n'
        for b in $bins; do printf '    %s \\\n' "$b"; done
        printf '\n'
    fi
} > "$vendor_dir/$device-vendor.mk"

{
    printf '# Generated by %s -- do not edit.\n\n' "$(basename "$0")"
    printf 'LOCAL_PATH := $(call my-dir)\n\n'
    printf 'ifeq ($(TARGET_DEVICE),%s)\n\n' "$device"
    printf '%s\n' $files | grep '^bin/' | while read -r f; do
        b=${f#bin/}
        printf 'include $(CLEAR_VARS)\n'
        printf 'LOCAL_MODULE := %s\n' "$b"
        printf 'LOCAL_MODULE_OWNER := asus\n'
        printf 'LOCAL_SRC_FILES := proprietary/%s\n' "$f"
        printf 'LOCAL_MODULE_CLASS := EXECUTABLES\n'
        printf 'LOCAL_MODULE_SUFFIX :=\n'
        printf 'LOCAL_MODULE_TAGS := optional\n'
        printf 'LOCAL_PROPRIETARY_MODULE := false\n'
        printf 'include $(BUILD_PREBUILT)\n\n'
    done
    printf 'endif\n'
} > "$vendor_dir/Android.mk"

printf '# Generated by %s -- do not edit.\n' "$(basename "$0")" > "$vendor_dir/BoardConfigVendor.mk"

# ---------------------------------------------------------------------------------
# 3. ASUS' init scripts
# ---------------------------------------------------------------------------------
say "taking ASUS' init scripts into rootdir/etc"
mkdir -p "$here/rootdir/etc"
if [ "$mode" = dumps ]; then
    python3 "$here/tools/unpack-boot-ramdisk.py" "$boot_img" "$here/rootdir/etc" $INIT_FILES
else
    for f in $INIT_FILES; do
        adb pull "/$f" "$here/rootdir/etc/$f" >/dev/null 2>&1 && printf '    %s\n' "$f" || true
    done
fi

printf '\n'
say "done"
cat <<'NOTE'

Two things to keep in mind:

  * The init scripts are written for Nougat's init. Pie's is stricter about what it
    accepts, so expect to adapt them -- that is part of M3, not a surprise.
  * rootdir/etc/fstab.qcom is ours and is not touched by this script. Do not replace it
    with the stock one: the stock file marks /system `verify,rebooterr`, and our system
    carries no dm-verity hash tree.
NOTE
