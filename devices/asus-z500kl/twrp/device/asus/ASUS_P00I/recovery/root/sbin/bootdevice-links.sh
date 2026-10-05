#!/sbin/sh
# Recreate the /dev/block/bootdevice tree that TWRP's ueventd does not build on this
# device, because this 3.10 kernel reports old-style /devices/soc.0/... paths.
#
# Why it matters: stock Nougat binaries have the path compiled in and cannot be
# pointed elsewhere. librpmb.so stats /dev/block/bootdevice to tell eMMC from UFS, so
# without it qseecomd died with
#     E/rpmb: Error finding /dev/block/bootdevice (error no: 2)
#     E/rpmb: No RPMB device found - exiting!!
#     E/QSEECOMD: ERROR: RPMB_INIT failed, shall not start listener services
# and with no listeners registered the keymaster never signs the key derived from the
# PIN, so vold answered 406 to every `cryptfs checkpw` and /data stayed locked.
#
# The partition names are read from each partition's uevent (PARTNAME=...) instead of
# being hardcoded, so this keeps working if the table ever changes.
# Idempotent: safe to run more than once.

PLAT=/dev/block/platform/soc.0/7824900.sdhci   # matches androidboot.bootdevice

mkdir -p "$PLAT/by-name" 2>/dev/null

for uev in /sys/block/mmcblk0/mmcblk0p*/uevent; do
	[ -r "$uev" ] || continue
	dir=${uev%/uevent}
	node=${dir##*/}
	name=$(sed -n 's/^PARTNAME=//p' "$uev" 2>/dev/null)
	[ -n "$name" ] || continue
	[ -e "/dev/block/$node" ] || continue
	ln -sf "/dev/block/$node" "$PLAT/by-name/$name" 2>/dev/null
done

# whole-disk node, where some stock tools look for it
[ -e "$PLAT/mmcblk0" ] || ln -sf /dev/block/mmcblk0 "$PLAT/mmcblk0" 2>/dev/null

# the symlink librpmb.so and friends actually look for
[ -e /dev/block/bootdevice ] || ln -sf "$PLAT" /dev/block/bootdevice 2>/dev/null

# the eMMC RPMB device itself; ueventd may not have made the node
[ -e /dev/block/mmcblk0rpmb ] || mknod /dev/block/mmcblk0rpmb b 179 32 2>/dev/null
chmod 0600 /dev/block/mmcblk0rpmb 2>/dev/null

# vold builds its fstab path as "/fstab." + ro.hardware. Property reads work once
# /property_contexts is in place, but keep this alias as a belt-and-braces: without it
# a Nougat vold that cannot read properties looks for the literal "/fstab." and fails
# with "Failed to open default fstab /fstab.".
[ -e "/fstab." ] || ln -sf /fstab.qcom "/fstab." 2>/dev/null

exit 0
