#
# Copyright (C) 2026 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#
# ASUS ZenPad 3S 10 LTE (Z500KL / ASUS_P00I) - MSM8956, kernel 3.10
# Base: twrpdtgen output, adapted for the twrp-9.0 minimal manifest.
#

DEVICE_PATH := device/asus/ASUS_P00I

# For building with minimal manifest
ALLOW_MISSING_DEPENDENCIES := true

# Architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := cortex-a53

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv7-a-neon
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := cortex-a53

# Bootloader / platform
TARGET_BOOTLOADER_BOARD_NAME := msm8952
TARGET_NO_BOOTLOADER := true
TARGET_BOARD_PLATFORM := msm8952
TARGET_OTA_ASSERT_DEVICE := ASUS_P00I,P00I,Z500KL

# Kernel: stock Image.gz-dtb (no QCDT section) with the entry_mode needle patched
# by tools/patch-kernel.py so the ASUS touch driver stays enabled in recovery.
BOARD_KERNEL_BASE := 0x80000000
BOARD_KERNEL_CMDLINE := console=ttyHSL0,115200,n8 androidboot.console=ttyHSL0 androidboot.hardware=qcom msm_rtb.filter=0x237 ehci-hcd.park=3 androidboot.bootdevice=7824900.sdhci lpm_levels.sleep_disabled=1 earlyprintk build_version=3
BOARD_KERNEL_PAGESIZE := 2048
BOARD_RAMDISK_OFFSET := 0x01000000
BOARD_KERNEL_TAGS_OFFSET := 0x00000100
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_KERNEL_TAGS_OFFSET)
BOARD_KERNEL_IMAGE_NAME := Image.gz-dtb
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/kernel

# Partitions
BOARD_FLASH_BLOCK_SIZE := 131072 # (BOARD_KERNEL_PAGESIZE * 64)
BOARD_BOOTIMAGE_PARTITION_SIZE := 67108864
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 67108864
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 3879731200
BOARD_CACHEIMAGE_PARTITION_SIZE := 262144000
BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_HAS_LARGE_FILESYSTEM := true
BOARD_HAS_NO_SELECT_BUTTON := true
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true

# Recovery
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery.fstab
TARGET_RECOVERY_PIXEL_FORMAT := "RGBX_8888"
RECOVERY_GRAPHICS_USE_LINELENGTH := true
BOARD_SUPPRESS_SECURE_ERASE := true

# Avoid anti-rollback checks on decryption (later)
PLATFORM_SECURITY_PATCH := 2099-12-31

# TWRP Configuration
TW_THEME := portrait_hdpi
TW_EXTRA_LANGUAGES := true
TW_SCREEN_BLANK_ON_BOOT := true
TW_INPUT_BLACKLIST := "hbtp_vm"
TW_BRIGHTNESS_PATH := "/sys/class/leds/lcd-backlight/brightness"
TW_MAX_BRIGHTNESS := 255
TW_DEFAULT_BRIGHTNESS := 150
TARGET_RECOVERY_QCOM_RTC_FIX := true
TW_NO_SCREEN_TIMEOUT := false
TW_USE_TOOLBOX := true
TW_INCLUDE_NTFS_3G := true
TW_EXCLUDE_TWRPAPP := true
# MTP off on purpose. TWRP's MTP server is the FunctionFS one (mtp/ffs/MtpServer.cpp)
# and wants its own functionfs instance at /dev/usb-ffs/mtp; this legacy android_usb
# gadget would then have to multiplex two ffs instances through f_ffs/aliases, which
# risks the adb path that took real work to get going. adb push/pull covers the same
# ground, and the tablet has a microSD slot and OTG. Without this it just logs
# "E:[MTP] Failed to start usb driver!" at every boot.
TW_EXCLUDE_MTP := true
TWRP_INCLUDE_LOGCAT := true
TARGET_USES_LOGD := true
TW_DEVICE_VERSION := payne_16

# Encryption: FDE with the master key wrapped by QSEE/keymaster
# (stock has libcryptfs_hw.so, /system/bin/qseecomd, keystore.msm8952.so).
# TWRP's own crypto code on this 9.0 base wants the keymaster HIDL HALs, which a
# Nougat vendor does not provide, so run the stock vold instead: it is the Nougat
# binary talking to the Nougat keymaster, with its libs from the mounted /system.
# qseecomd loads the keymaster trustlet from /firmware/image (the modem
# partition), so /firmware has to be mounted while decrypting.
TW_INCLUDE_CRYPTO := true
TW_CRYPTO_USE_SYSTEM_VOLD := qseecomd
TW_CRYPTO_SYSTEM_VOLD_MOUNT := firmware
TW_CRYPTO_SYSTEM_VOLD_DEBUG := false
