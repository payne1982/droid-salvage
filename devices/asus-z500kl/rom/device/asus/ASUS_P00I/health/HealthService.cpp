/*
 * The health HAL for ASUS_P00I: AOSP's service, told where this board keeps two numbers.
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
 */

#include <health2/service.h>
#include <healthd/healthd.h>

void healthd_board_init(struct healthd_config* config) {
    config->batteryChargeCounterPath = "/sys/class/power_supply/bms/charge_now_raw";
    config->batteryFullChargePath = "/sys/class/power_supply/bms/charge_full";
}

int healthd_board_battery_update(struct android::BatteryProperties*) {
    // 0: keep the periodic battery line in the kernel log, as the generic service does.
    return 0;
}

int main() {
    return health_service_main();
}
