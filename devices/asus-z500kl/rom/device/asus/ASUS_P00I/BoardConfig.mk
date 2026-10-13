#
# Copyright (C) 2026 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#
# ASUS ZenPad 3S 10 LTE (Z500KL / ASUS_P00I) - MSM8956, kernel 3.10, pre-Treble.
#
# This is the LineageOS 20 (Android 13) branch. The tree came from LineageOS 16, and a
# comment that says "Pie" describes what was found there; where Android 13 differs the
# comment says so.
#
# Everything here that is not self-evident is either measured on the device or
# explained. The partition map comes from the GPT, the kernel settings from the stock
# boot image, and the crypto settings from the footer in the last 16 KB of userdata.
# See ../../../../NOTES.md and ../../../../kernel/README.md.
#

DEVICE_PATH := device/asus/ASUS_P00I

# Architecture. 64-bit with a 32-bit second arch, because a Nougat vendor ships
# plenty of 32-bit-only blobs (audio HAL, camera daemon).
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_VARIANT := cortex-a53

TARGET_2ND_ARCH := arm
# armv8-a and not armv7-a-neon: the build warns that "cortex-a53 is armv8-a" and
# overrides it anyway, so saying it here just removes a warning that would otherwise sit
# at the top of every build and train us to ignore warnings.
TARGET_2ND_ARCH_VARIANT := armv8-a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := cortex-a53

TARGET_USES_64_BIT_BINDER := true

# Platform. ro.board.platform is msm8952 even though the SoC is an MSM8956, and the
# HAL modules on the stock system are named *.msm8952.so to match. LineageOS has no
# family entry for msm8952, so vendor/lineage/config/BoardConfigQcom.mk falls into its
# final else branch and sets QCOM_HARDWARE_VARIANT := msm8952 -- which is what we want:
# hardware/qcom/{audio,display,media}-caf/msm8952 all exist. It also leaves
# TARGET_USES_QCOM_BSP and the UM-family flags off, the right place for a Nougat-era,
# pre-Treble platform.
#
# BOARD_USES_QCOM_HARDWARE is what switches LineageOS onto the CAF trees at all. The
# whole variant selection in vendor/lineage/build/core/qcom_target.mk lives inside
# `ifeq ($(BOARD_USES_QCOM_HARDWARE),true)`; without it the else branch picks the
# historical hardware/qcom/{display,media}/$(TARGET_BOARD_PLATFORM) instead, and the
# legacy media tree then falls back to its msm8974 sources -- it only overrides
# QCOM_MEDIA_ROOT for 8996, 8998 and sdm845 -- so the first build failed with
# "libOmxVdec missing libqdMetaData" from a directory that has nothing to do with this
# tablet. One line, and a confusing error.
BOARD_USES_QCOM_HARDWARE := true
TARGET_BOARD_PLATFORM := msm8952
TARGET_BOOTLOADER_BOARD_NAME := msm8952
TARGET_NO_BOOTLOADER := true
TARGET_OTA_ASSERT_DEVICE := ASUS_P00I,P00I,Z500KL

# Pre-Treble: no vendor partition exists, so /vendor lives inside system, as it does
# on the stock ROM.
TARGET_COPY_OUT_VENDOR := system/vendor

# The vendor blobs reach the image as plain file copies (vendor/asus/ASUS_P00I), ELF
# files included. Android 13 refuses that by default and wants each one declared as a
# prebuilt module, so that it can check what they link against; Nougat blobs would not
# pass that check anyway.
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true

# The eleven executables that are declared as prebuilt modules (the daemons the init
# scripts start) list no shared libraries, and the build checks each DT_NEEDED entry
# against that list. Their libraries are blobs too, copied as files.
BUILD_BROKEN_PREBUILT_ELF_FILES := true

# The GPS HAL in gps/ (tools/setup-gps.sh) is Qualcomm's code of 2016 and installs its
# headers with LOCAL_COPY_HEADERS, which Android 13 calls obsolete.
BUILD_BROKEN_USES_BUILD_COPY_HEADERS := true

# Kernel, built from ASUS' published sources with the configuration recovered from the
# stock image. See ../../../../kernel/README.md for the whole story.
#
# The hook is TARGET_KERNEL_ADDITIONAL_FLAGS, and only that one. KERNEL_MAKE_FLAGS looks
# like a hook -- kernel.mk uses it and never defines it -- but
# vendor/lineage/config/BoardConfigKernel.mk clears it with `KERNEL_MAKE_FLAGS :=`
# ("to prevent accidental poisoning from env") and rebuilds it, appending
# $(TARGET_KERNEL_ADDITIONAL_FLAGS) at the end. Setting KERNEL_MAKE_FLAGS here is
# silently discarded, which is how the first build failed: the -fcommon below never
# arrived and scripts/dtc would not link.
#
# Four things go through it:
#
#   TARGET_PROJECT=Z500KL  arch/arm64/boot/dts/qcom/Makefile builds
#                          msm8956-v1.1-cdp-$(TARGET_PROJECT).dtb. Without it this
#                          tablet's device tree is never compiled and the kernel has no
#                          matching board, so it does not boot.
#   CC=...real-...-gcc     the tree routes CC through scripts/gcc-wrapper.py, a Python 2
#                          script. Pointing CC at the real driver binary skips it; all
#                          it does is promote some warnings to errors. In LineageOS 20's
#                          prebuilts that binary is real-aarch64-linux-android-gcc (the
#                          one without "real-" is a Python wrapper around it); the
#                          aarch64-linux-android-gcc-4.9.x that LineageOS 16 used is
#                          still there but no longer executable.
#   HOSTCFLAGS with        the host tools are built by the *system* gcc. Since gcc 10
#   -fcommon               -fno-common is the default, and scripts/dtc declares yylloc
#                          in both its lexer and its parser, so it fails to link. The
#                          other flags are the tree's own defaults, kept as they are.
#   KBUILD_BUILD_USER,     /proc/version, and Settings' "Kernel version", name the user
#   KBUILD_BUILD_HOST      and machine that built the kernel. Fixed, so a published image
#                          does not carry the name of whoever's computer built it.
#
# Changing any of these does not rebuild a kernel that is already built: nothing in
# kernel.mk depends on them. Delete obj/KERNEL_OBJ/arch/arm64/boot/Image.gz-dtb in
# $OUT first.
#
# TARGET_KERNEL_CLANG_COMPILE stays false (the default), which leaves KERNEL_CC empty
# so our CC is the only one in play. A current clang cannot build a 3.10 kernel anyway.
TARGET_KERNEL_SOURCE := kernel/asus/msm8956
TARGET_KERNEL_CONFIG := asus_P00I_defconfig
TARGET_KERNEL_CLANG_COMPILE := false
TARGET_KERNEL_ARCH := arm64

KERNEL_TOOLCHAIN_BIN := prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin
TARGET_KERNEL_ADDITIONAL_FLAGS := TARGET_PROJECT=Z500KL
TARGET_KERNEL_ADDITIONAL_FLAGS += CC=$(abspath $(KERNEL_TOOLCHAIN_BIN)/real-aarch64-linux-android-gcc)
TARGET_KERNEL_ADDITIONAL_FLAGS += HOSTCFLAGS="-Wall -Wmissing-prototypes -Wstrict-prototypes -O2 -fomit-frame-pointer -std=gnu89 -fcommon"
TARGET_KERNEL_ADDITIONAL_FLAGS += KBUILD_BUILD_USER=payne1982 KBUILD_BUILD_HOST=droid-salvage

# Boot image. Taken from the stock header: version 0, 2048-byte pages, dt_size 0,
# because the DTBs are appended to Image.gz rather than carried in a QCDT section.
BOARD_KERNEL_IMAGE_NAME := Image.gz-dtb
BOARD_KERNEL_BASE := 0x80000000
BOARD_KERNEL_PAGESIZE := 2048
BOARD_RAMDISK_OFFSET := 0x01000000
BOARD_KERNEL_TAGS_OFFSET := 0x00000100
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_KERNEL_TAGS_OFFSET)

# The installable zip has to carry the signed boot image (device.mk, "Boot image
# signature"), and by default it did not: the release tools rebuild boot.img from the
# target files, and sign it only when misc_info.txt names a verity key, which the build
# writes only with PRODUCT_SUPPORTS_VERITY -- off here on purpose. So the zip flashed an
# unsigned image the bootloader refuses, and every install needed the signed one written
# by hand afterwards. BOARD_CUSTOM_BOOTIMG makes the build put its own boot.img, signed,
# into the target files (BOOTABLE_IMAGES), and the release tools take it as it is.
# (It copies recovery.img there too, and the zip carries it; nothing uses it: the zip
# writes only system and boot.)
BOARD_CUSTOM_BOOTIMG := true

# Nothing this build installs may write the recovery partition: it holds the tool the
# tablet is repaired with, and the bootloader is locked. Left alone, Android 13 puts
# /vendor/bin/install-recovery.sh and a copy of LineageOS' recovery into the system
# image, and the setup wizard and the Updater then offer to "update the recovery". The
# switch is ours: tools/tree-patches/build/make/0001 says why TARGET_NO_RECOVERY could
# not be used instead.
TARGET_NO_RECOVERY_PATCH := true

# The stock command line, kept as it is. androidboot.bootdevice is what makes the
# by-name symlink tree appear; losing it cost real time while getting TWRP to work.
BOARD_KERNEL_CMDLINE := console=ttyHSL0,115200,n8 androidboot.console=ttyHSL0
BOARD_KERNEL_CMDLINE += androidboot.hardware=qcom msm_rtb.filter=0x237 ehci-hcd.park=3
BOARD_KERNEL_CMDLINE += androidboot.bootdevice=7824900.sdhci lpm_levels.sleep_disabled=1
BOARD_KERNEL_CMDLINE += earlyprintk

# SELinux permissive, for the first boots of this version. sepolicy/ is the policy
# written for LineageOS 16, where the same line came out once every daemon had its
# domain; nobody has yet seen what it denies on Android 13. init honours the argument
# on userdebug builds. It comes out again when the denials have been read and answered.
BOARD_KERNEL_CMDLINE += androidboot.selinux=permissive

# Mount points in the root directory, for the three partitions fstab.qcom mounts there.
# The root is the system image and nothing can be created in it at boot. Without them
# mount_all fails on the first of the three, init never learns that /data is not
# encrypted, and the boot stays on the logo with zygote not started (first boot of this
# version). fs_mgr also answers a failed mount by running e2fsck -y on the partition.
BOARD_ROOT_EXTRA_FOLDERS := firmware persist dsp

# Partitions, straight from the GPT (backup/gpt_primary.bin):
#   p41 boot 64 MiB, p43 recovery 64 MiB, p44 system 3700 MiB,
#   p36 cache 250 MiB, p45 userdata 112 GiB.
# system at 3.7 GB is roomy enough that no repartitioning is needed, which matters on
# a device whose GPT can only be repaired through EDL.
BOARD_FLASH_BLOCK_SIZE := 131072
BOARD_BOOTIMAGE_PARTITION_SIZE := 67108864
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 67108864
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 3879731200
BOARD_CACHEIMAGE_PARTITION_SIZE := 262144000
BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_HAS_LARGE_FILESYSTEM := true
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true

# No encryption of /data on this branch. Stock and LineageOS 16 can use full-disk
# encryption in hardware (Qualcomm ICE, key wrapped by keymaster); Android 13 removed
# full-disk encryption altogether, and file-based encryption needs fscrypt, which this
# kernel does not have.

# SELinux. sepolicy-legacy, not sepolicy: the latter targets the UM platforms, and
# this is a pre-UM Nougat vendor.
include device/qcom/sepolicy-legacy/sepolicy.mk
BOARD_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy

# Recovery: the same fstab the ROM uses, so there is one description of the layout.
TARGET_RECOVERY_PIXEL_FORMAT := "RGBX_8888"
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/rootdir/etc/fstab.qcom

# The bootloader refuses an image whose AVB1 signature does not name the partition it
# is being written to, and fastboot flash is disabled on it, so images go on with dd
# from a root shell. Nothing here needs a verity key.
#
# LineageOS 16 also set PLATFORM_SECURITY_PATCH := 2099-12-31 here, a habit carried over
# from the recovery tree, where a patch level in the far future keeps keymaster from
# refusing keys made by a newer system. Android 13 makes that variable read-only, and
# with no encrypted /data to open there is nothing left that needs it.

# A fixed build fingerprint, the same in system, vendor and the boot image whatever an
# incremental build regenerates. The default one carries the build number (user, date
# and time), and an incremental build rewrites vendor/build.prop when its content
# changes but leaves system/build.prop alone: the two ended up with different
# fingerprints, and Pie then shows "There's an internal problem with your device" at
# every boot (Build.isBuildConsistent).
#
# The build-number field is ours instead: P00I_RELEASE, "dev" for everyday builds and
# the release name for published ones (payne_N, the same convention as the recovery).
# Build a release with tools/release-build.sh, which also clears the property files:
#   tools/release-build.sh payne_17
# so every published build has its own fingerprint, and it stays consistent between
# system and vendor even if the release build is an incremental one. Between
# development builds, ro.build.date and ro.lineage.version tell them apart.
#
# It has to be this make variable, read once in build/make/core/Makefile for all three
# property files. PRODUCT_BUILD_PROP_OVERRIDES looks like the obvious place and is
# wrong: it reaches system/build.prop only, which would make the two differ always.
#
# The last field says which keys signed the build, the way ro.build.tags does: test-keys
# for AOSP's public ones, dev-keys when the tree has private ones in
# vendor/lineage-priv/keys (rom/README.md, "Signing").
P00I_RELEASE ?= dev
ifneq ($(filter-out build/target/product/security/testkey,$(PRODUCT_DEFAULT_DEV_CERTIFICATE)),)
P00I_KEYS := dev-keys
else
P00I_KEYS := test-keys
endif
BUILD_FINGERPRINT := asus/lineage_ASUS_P00I/ASUS_P00I:13/TQ3A.230901.001/$(P00I_RELEASE):userdebug/$(P00I_KEYS)

# The HIDL manifest: every HAL this device provides. See the file for why it matters
# even on a non-Treble device.
DEVICE_MANIFEST_FILE := $(DEVICE_PATH)/manifest.xml
# And it is the whole truth: a HAL that is not in it does not exist. Without this, a
# build for a device that launched before Treble looks for any HAL "the legacy way"
# too, and Android 13's libhidl sleeps one second in every getService because that way
# has a race in it (system/libhidl/transport/ServiceManagement.cpp). The Bluetooth
# stack asks for IBluetoothHci 1.1 before 1.0 and aborts if the two take over 500 ms.
PRODUCT_ENFORCE_VINTF_MANIFEST_OVERRIDE := true

# Audio: audio-caf/msm8952 from source. The optional AUDIO_FEATURE_ENABLED_* switches
# (offload, fluence, speaker protection, HFP...) stay off until the base path plays,
# and come in one at a time.
#
# Three are on because the HAL does not compile without them: with them off, what it
# falls back on are unused static functions and variables, which -Werror stops on.
# MULTI_VOICE_SESSIONS is the voice-call path; SND_MONITOR watches the sound card
# across an ADSP restart; PROXY_DEVICE is the AFE proxy used for Wi-Fi Display and USB
# audio, the only user of audio_extn.c's state with every other extension off. Kenzo
# has all three on.
BOARD_USES_ALSA_AUDIO := true
USE_XML_AUDIO_POLICY_CONF := 1
AUDIO_FEATURE_ENABLED_MULTI_VOICE_SESSIONS := true
AUDIO_FEATURE_ENABLED_SND_MONITOR := true
AUDIO_FEATURE_ENABLED_PROXY_DEVICE := true

# WiFi: the WCNSS Pronto core with Qualcomm's prima driver, built into the kernel (see
# kernel/patches/0009). prima starts when something writes a mode to its fwpath
# parameter, which is what the WiFi HAL does with the three paths below; it needs
# the WCNSS core up first, which is wcnss_service's job (init.qcom.rc).
BOARD_HAS_QCOM_WLAN := true
BOARD_WLAN_DEVICE := qcwcn
WPA_SUPPLICANT_VERSION := VER_0_8_X
BOARD_WPA_SUPPLICANT_DRIVER := NL80211
BOARD_WPA_SUPPLICANT_PRIVATE_LIB := lib_driver_cmd_$(BOARD_WLAN_DEVICE)
BOARD_HOSTAPD_DRIVER := NL80211
BOARD_HOSTAPD_PRIVATE_LIB := lib_driver_cmd_$(BOARD_WLAN_DEVICE)
WIFI_DRIVER_FW_PATH_PARAM := "/sys/module/wlan/parameters/fwpath"
WIFI_DRIVER_FW_PATH_STA := "sta"
WIFI_DRIVER_FW_PATH_AP := "ap"
WIFI_DRIVER_FW_PATH_P2P := "p2p"

# Bluetooth: the WCNSS core again, over SMD. libbt-vendor from bt-caf, which picks the
# SMD path by itself when vendor.qcom.bluetooth.soc is unset.
BOARD_HAVE_BLUETOOTH := true
BOARD_HAVE_BLUETOOTH_QCOM := true

# RIL: on LineageOS 16 this was hardware/ril-caf (TARGET_RIL_VARIANT := caf). That
# tree is gone; libril and rild now come from hardware/ril, LineageOS-UL's fork.
TARGET_SYSTEM_PROP += $(DEVICE_PATH)/system.prop

# Video: the Venus codecs from media-caf/msm8952 (device.mk). TARGET_USES_ION is the
# one switch they need, and nothing else in this tree reads it: it adds -DUSE_ION,
# without which the decoder does not even include <linux/msm_ion.h> and stops on its
# cache-maintenance ioctls. The encoder also needs kernel/patches/0011.
TARGET_USES_ION := true

# The decoder asks for its output buffers with GRALLOC_USAGE_PRIVATE_UNCACHED
# (0x02000000, display-caf's gralloc_priv.h), and Pie's libui rejects usage bits it
# does not know: "buffer descriptor contains invalid usage bits 0x2000000", no buffer,
# and videos played with sound and a black picture. This is LineageOS' switch for
# declaring them; vendor/lineage/config/BoardConfigQcom.mk adds its own bit to it.
TARGET_ADDITIONAL_GRALLOC_10_USAGE_BITS := 0x02000000U

# GPS: Qualcomm's legacy loc_api HAL at LA.BR.1.3.6, fetched into gps/ by
# tools/setup-gps.sh (which says why not hardware/qcom/gps). USE_DEVICE_SPECIFIC_GPS
# points LineageOS' qcom-gps project path there, which also switches hardware/qcom/gps
# off. TARGET_NO_RPC: the modem speaks QMI; the RPC loc_api is for pre-QMI chips.
USE_DEVICE_SPECIFIC_GPS := true
TARGET_NO_RPC := true

# Camera: ASUS' Nougat camera stack, HAL included, as blobs (device.mk says why).
# The HAL needs one symbol Pie's libui no longer exports; the shim provides it, loaded
# into whatever process loads the HAL.
TARGET_LD_SHIM_LIBS := /system/lib/hw/camera.msm8952.so|libshim_camera.so
# And the RIL one that Android 13's AudioSystem no longer has.
TARGET_LD_SHIM_LIBS := $(TARGET_LD_SHIM_LIBS):/system/vendor/lib64/libril-qc-qmi-1.so|libshim_ril.so

# Init: ASUS' bootloader calls an ordinary boot androidboot.mode=main, which Pie's USB
# service takes for a factory mode; init/init_ASUS_P00I.cpp says what that breaks.
TARGET_INIT_VENDOR_LIB := //$(DEVICE_PATH):libinit_ASUS_P00I

# -----------------------------------------------------------------------------------
# Still to be settled. Listed rather than guessed, so nothing silently carries a wrong
# value into a first boot where every symptom has a dozen candidate causes:
#   - graphics:  BOARD_EGL_CFG, TARGET_USES_OVERLAY, gralloc bits
# -----------------------------------------------------------------------------------
