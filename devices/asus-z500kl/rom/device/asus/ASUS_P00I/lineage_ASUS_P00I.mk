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
# The tablet shipped with Android 6.0. Saying so (PRODUCT_SHIPPING_API_LEVEL 23) keeps
# Android 13 from applying what it requires only of devices that launched with a recent
# version: a vendor partition, VINTF enforcement, property namespaces.
$(call inherit-product, $(SRC_TARGET_DIR)/product/product_launched_with_m.mk)
# aosp_base and not full_base_telephony: that one is aosp_base plus AOSP's telephony.mk,
# which brings the Phone app. device.mk lists the telephony packages this tablet wants;
# the property is the other thing full_base_telephony sets.
$(call inherit-product, $(SRC_TARGET_DIR)/product/aosp_base.mk)

PRODUCT_PROPERTY_OVERRIDES += \
    keyguard.no_require_sim=true

# The 3.10 kernel has no eBPF. LineageOS-UL asks its devices to say so with this
# property, and both trees this one was compared with set it. In the lineage-20.0
# sources nothing was found that reads it (netd, system/bpf, the Connectivity module,
# the framework's services; nor does the string occur in the built image), so on this
# version it follows the convention and decides nothing.
PRODUCT_PROPERTY_OVERRIDES += \
    ro.kernel.ebpf.supported=false

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
