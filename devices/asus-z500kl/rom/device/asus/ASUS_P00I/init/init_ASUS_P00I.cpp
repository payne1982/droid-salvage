/*
 * ro.bootmode for ASUS' bootloader.
 *
 * The bootloader passes androidboot.mode=main for an ordinary boot (and charger,
 * recovery, fota, ... for the others), and init copies it to ro.bootmode. Pie's
 * UsbDeviceManager counts only "normal" and "unknown" as an ordinary boot; for
 * anything else it takes the factory-mode path, which keeps its functions in
 * persist.sys.usb.<mode>.func and judges them applied when sys.usb.config equals
 * sys.usb.state. After a reboot both are "none" while persist.sys.usb.main.func
 * still says mtp, so the framework believes mtp is set and never sets it: with adb
 * off there is no USB at all, not even a notification. Nothing else on the system
 * cares about "main", so it is renamed to what the framework expects. "charger"
 * and the other modes are left alone; init has already acted on charger by now.
 */

#include <android-base/properties.h>

#define _REALLY_INCLUDE_SYS__SYSTEM_PROPERTIES_H_
#include <sys/_system_properties.h>

#include "vendor_init.h"

void vendor_load_properties() {
    if (android::base::GetProperty("ro.bootmode", "") != "main") return;
    prop_info* pi = const_cast<prop_info*>(__system_property_find("ro.bootmode"));
    if (pi != nullptr) __system_property_update(pi, "normal", 6);
}
