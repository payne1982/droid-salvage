#
# Copyright (C) 2026 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#
# ASUS ZenPad 3S 10 LTE (Z500KL / ASUS_P00I)
#

# 64-bit with a 32-bit second arch: the vendor blobs are Nougat and plenty of them
# are 32-bit only, audio and the camera daemon among them.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

$(call inherit-product, device/asus/ASUS_P00I/device.mk)

# common_full_phone, not common_full_tablet_wifionly: this is the LTE model, and the
# wifionly tablet target leaves telephony out entirely.
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

PRODUCT_NAME := lineage_ASUS_P00I
PRODUCT_DEVICE := ASUS_P00I
PRODUCT_BRAND := asus
PRODUCT_MODEL := ASUS_P00I
PRODUCT_MANUFACTURER := asus

PRODUCT_GMS_CLIENTID_BASE := android-asus

# The stock fingerprint. Several Nougat blobs and the DRM/keymaster path read these,
# and the OTA assert in BoardConfig matches the same names.
PRODUCT_BUILD_PROP_OVERRIDES += \
    PRODUCT_NAME=WW_Z500KL \
    TARGET_DEVICE=ASUS_P00I
