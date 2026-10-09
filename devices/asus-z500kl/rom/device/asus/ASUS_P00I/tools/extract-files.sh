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
# Fixups. Some stock XML files carry a licence comment before the <?xml ...?>
# declaration, which XML forbids (the declaration must come first). Nougat's parsers
# did not care; Pie's build runs xmllint on every XML it copies and stops on them
# ("XML declaration allowed only at the start of the document": etc/data's
# netmgr_config.xml and qmi_config.xml). The declaration is optional, so where it is
# not on the first line it is dropped and the rest of the file left as it was.
for x in $(find "$vendor_dir/proprietary" -type f -name '*.xml'); do
    if ! head -n 1 "$x" | grep -q '^<?xml' && grep -q '^[[:space:]]*<?xml' "$x"; then
        sed -i '/^[[:space:]]*<?xml[^>]*?>[[:space:]]*$/d' "$x"
        printf '    fixed the XML declaration in %s\n' "${x#"$vendor_dir"/proprietary/}"
    fi
done

# Nougat's protobuf, for the two blobs that were built against it: libsettings
# (qcril) links libprotobuf-cpp-full, libcneapiclient (netmgrd) links
# libprotobuf-cpp-lite. Pie ships libraries of the same names with a different ABI, so
# those blobs failed to load on missing symbols (qcril did not start, netmgrd did not
# link). The stock libraries are installed renamed -- fl26/lt26, same length, so the
# binaries keep their layout -- and the two blobs, and the libraries' own SONAMEs, are
# pointed at the new names. Pie's protobuf stays as it is for everything else.
pb_fix() { # file, old name, new name
    [ -f "$vendor_dir/proprietary/$1" ] || return 0
    if grep -q "$2" "$vendor_dir/proprietary/$1"; then
        LC_ALL=C sed -i "s/$2/$3/g" "$vendor_dir/proprietary/$1"
        printf '    %s: %s -> %s\n' "$1" "$2" "$3"
    fi
}
pb_fix vendor/lib64/libsettings.so libprotobuf-cpp-full.so libprotobuf-cpp-fl26.so
pb_fix vendor/lib64/libprotobuf-cpp-fl26.so libprotobuf-cpp-full.so libprotobuf-cpp-fl26.so
pb_fix vendor/lib64/libcneapiclient.so libprotobuf-cpp-lite.so libprotobuf-cpp-lt26.so
pb_fix vendor/lib64/libprotobuf-cpp-lt26.so libprotobuf-cpp-lite.so libprotobuf-cpp-lt26.so

# Stock's camcorder profiles carry two qualities that only Qualcomm's framework
# knew, "vga" and "timelapsevga". Pie's MediaProfiles does not, and meeting an
# unknown quality it does not skip the entry but fails a CHECK: zygote parses this
# file while preloading (CamcorderProfile), so it aborted at every start and the
# tablet never finished booting. Those EncoderProfile blocks are dropped; every
# other profile (qcif, qvga, 480p, 720p, 1080p and their timelapse twins) stays.
# The camera daemon's ISP module destroys two mutexes twice when a session stops:
# the teardown block in module_isp (0x6f8c-0x6ffc) runs once for each of two
# hardware streams (r4 = 0, then 1), and while the buffers it frees are indexed by
# the stream, the two mutexes (+0x2dc, +0x2e0) and the condition variable are the
# session's own, the same both times. Nougat's bionic let the second destroy pass;
# Pie's aborts ("FORTIFY: pthread_mutex_destroy called on a destroyed mutex") and
# the daemon died every time the camera was closed or switched. Both calls become
# a Thumb-2 nop.w: in bionic a destroy only marks the mutex unusable, and the
# memory holding them is freed with the session. Patched only on the exact stock
# file, recognised by its hash, and only where the two original blx are found.
isp=vendor/lib/libmmcamera2_isp_modules.so
isp_sha=f811b169a1b8067d42d841243224983ad97f0ed224cc133b53b65288a95578d8
if [ -f "$vendor_dir/proprietary/$isp" ] &&
   [ "$(sha256sum "$vendor_dir/proprietary/$isp" | cut -d' ' -f1)" = "$isp_sha" ]; then
    for at in 0x6fd4:fef7aaeb 0x6fe2:fef7a4eb; do
        off=$((${at%%:*}))
        [ "$(od -An -tx1 -j "$off" -N4 "$vendor_dir/proprietary/$isp" | tr -d ' \n')" = "${at#*:}" ] ||
            { printf 'error: unexpected bytes in %s at %s\n' "$isp" "${at%%:*}" >&2; exit 1; }
        printf '\257\363\000\200' |
            dd of="$vendor_dir/proprietary/$isp" bs=1 seek="$off" conv=notrunc 2>/dev/null
    done
    printf '    %s: no double pthread_mutex_destroy at session stop\n' "$isp"
fi

# The camera HAL runs in HAL3 mode (persist.camera.HAL3.enabled, device.mk), the
# only one that works here: in HAL1 mode the HAL hands get_memory its own memory
# object as the cookie, which Nougat's framework ignored and Pie's camera.device@1.0
# takes for its CameraDevice ("camera HAL request memory while camera is not
# opened!"), and preview crashed. But for a HAL3 device whose module has an
# open_legacy, Pie's provider opens it once in HAL1 mode at start to see whether it
# could, and ASUS' HAL1 constructor (ASUSDITInterface) crashed there, so the provider
# never came up. QCamera2Factory::open_legacy is made to answer -ENOSYS straight
# away (mvn.w r0, #37; bx lr), which the provider takes as "no HAL1" -- true of the
# HAL as it is used. Same safeguards as above.
hal=lib/hw/camera.msm8952.so
hal_sha=5ba00a95a4c311bff1af104f63a85bbed716ba4dc8487af46af44a03bc308cf4
if [ -f "$vendor_dir/proprietary/$hal" ] &&
   [ "$(sha256sum "$vendor_dir/proprietary/$hal" | cut -d' ' -f1)" = "$hal_sha" ]; then
    off=$((0x385b4 - 0x1000))   # the text segment is mapped at 0x1000, from offset 0
    [ "$(od -An -tx1 -j "$off" -N6 "$vendor_dir/proprietary/$hal" | tr -d ' \n')" = 2de9f3410646 ] ||
        { printf 'error: unexpected bytes in %s at 0x385b4\n' "$hal" >&2; exit 1; }
    printf '\157\360\045\000\160\107' |
        dd of="$vendor_dir/proprietary/$hal" bs=1 seek="$off" conv=notrunc 2>/dev/null
    printf '    %s: open_legacy returns -ENOSYS\n' "$hal"
fi

mp=vendor/etc/media_profiles_V1_0.xml
if [ -f "$vendor_dir/proprietary/$mp" ] && grep -q 'quality="\(timelapse\)\{0,1\}vga"' "$vendor_dir/proprietary/$mp"; then
    awk '/<EncoderProfile quality="(timelapse)?vga"/ { skip = 1 }
         !skip { print }
         skip && /<\/EncoderProfile>/ { skip = 0 }' \
        "$vendor_dir/proprietary/$mp" > "$vendor_dir/proprietary/$mp.tmp"
    mv "$vendor_dir/proprietary/$mp.tmp" "$vendor_dir/proprietary/$mp"
    printf '    %s: dropped the vga and timelapsevga profiles\n' "$mp"
fi

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
