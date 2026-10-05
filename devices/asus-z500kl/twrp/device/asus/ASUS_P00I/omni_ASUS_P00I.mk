#
# Copyright (C) 2026 The Android Open Source Project
# Copyright (C) 2026 SebaUbuntu's TWRP device tree generator
#
# SPDX-License-Identifier: Apache-2.0
#

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit some common Omni stuff.
$(call inherit-product, vendor/omni/config/common.mk)

# Inherit from ASUS_P00I device
$(call inherit-product, device/asus/ASUS_P00I/device.mk)

PRODUCT_DEVICE := ASUS_P00I
PRODUCT_RELEASE_NAME := ASUS_P00I
PRODUCT_NAME := omni_ASUS_P00I
PRODUCT_BRAND := asus
PRODUCT_MODEL := ASUS_P00I
PRODUCT_MANUFACTURER := asus

PRODUCT_GMS_CLIENTID_BASE := android-asus-tpin

PRODUCT_BUILD_PROP_OVERRIDES += \
    PRIVATE_BUILD_DESC="WW_ASUS_P00I-user 7.0 NRD90M WW_ASUS_P00I-V5.4.6-20170815 release-keys"

BUILD_FINGERPRINT := asus/WW_ASUS_P00I/ASUS_P00I:7.0/NRD90M/WW_ASUS_P00I-V5.4.6-20170815:user/release-keys
