/*
 * The health HAL for ASUS_P00I: AOSP's service, told where this board keeps two numbers
 * and what the charger really gives.
 *
 * The generic service looks for everything under the power supply of type "Battery".
 * Here that is the charger (qpnp-smbcharger), which has the level, the voltage and the
 * current but no charge figures. Those belong to the fuel gauge (qpnp-fg), which
 * registers as "bms" with type "BMS", a type the generic service does not look into. So
 * Android saw a charge counter of 0, and batterystats reported every discharge as 0 mAh.
 *
 *   bms/charge_now_raw  the charge in the battery, in uAh: the gauge's own state of
 *                       charge applied to the design capacity. bms/charge_now is not
 *                       it; that one only counts during a capacity-learning cycle
 *                       and reads 0 the rest of the time.
 *   bms/charge_full     the capacity the gauge has learned for this battery, in uAh.
 *
 * Android tells charging rapidly from slowly by the largest current_max times
 * voltage_max among the online supplies (above 7.5 W and below 5 W). Here those are the
 * USB controller's and the type-C port's figures, 1.5 A at 5 V or none, whatever is
 * plugged in: a Quick Charge 3 adapter at 9 V showed as plain "charging". The board
 * update below puts in the charger's own figures instead:
 *
 *   battery/input_current_max  the input current limit the charger has set, in uA:
 *                              500 mA from a computer, 900 mA or more from an
 *                              adapter.
 *   qpnp-vadc-15/usbin         the input voltage the PMIC measures, "Result:<uV> ...";
 *                              above 7 V the adapter has gone to 9 V, otherwise it is
 *                              taken as 5 V (it reads 4.4 to 4.8 under load).
 */

#include <stdio.h>

#include <android-base/file.h>
#include <android-base/parseint.h>
#include <android-base/strings.h>
#include <health2/service.h>
#include <healthd/healthd.h>

namespace {

constexpr const char* kInputCurrentLimitPath = "/sys/class/power_supply/battery/input_current_max";
constexpr const char* kUsbinPath = "/sys/devices/soc.0/qpnp-vadc-15/usbin";
constexpr int kHighVoltageThresholdUv = 7000000;

bool ReadInputCurrentLimit(int* ua) {
    std::string buf;
    if (!android::base::ReadFileToString(kInputCurrentLimitPath, &buf)) return false;
    return android::base::ParseInt(android::base::Trim(buf), ua) && *ua > 0;
}

bool ReadUsbin(int* uv) {
    std::string buf;
    if (!android::base::ReadFileToString(kUsbinPath, &buf)) return false;
    return sscanf(buf.c_str(), "Result:%d", uv) == 1;
}

}  // namespace

void healthd_board_init(struct healthd_config* config) {
    config->batteryChargeCounterPath = "/sys/class/power_supply/bms/charge_now_raw";
    config->batteryFullChargePath = "/sys/class/power_supply/bms/charge_full";
}

int healthd_board_battery_update(struct android::BatteryProperties* props) {
    int ua, uv;
    if ((props->chargerAcOnline || props->chargerUsbOnline) && ReadInputCurrentLimit(&ua) &&
        ReadUsbin(&uv)) {
        props->maxChargingCurrent = ua;
        props->maxChargingVoltage = uv > kHighVoltageThresholdUv ? 9000000 : 5000000;
    }
    // 0: keep the periodic battery line in the kernel log, as the generic service does.
    return 0;
}

int main() {
    return health_service_main();
}
