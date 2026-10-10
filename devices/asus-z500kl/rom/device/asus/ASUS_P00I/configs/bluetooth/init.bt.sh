#!/system/bin/sh
# Bring up the Bluetooth core of the WCNSS for ASUS_P00I. Ours; it does the part of
# Qualcomm's init.qcom.bt.sh that matters on this device.
#
# Bluetooth on the WCNSS Pronto runs over SMD (/dev/smd2 for ACL, /dev/smd3 for
# commands), not a UART. libbt-vendor (hardware/qcom/bt-caf) does not power anything
# itself on that path: it sets vendor.bluetooth.hciattach=true and waits for
# vendor.bluetooth.status=on. This is what answers. hci_qcomm_init configures the core
# over /dev/smd3 (power classes, and the BD address from the NV when it can get it);
# "-e" makes it print the result as shell assignments.

log -t init.bt "configuring the WCNSS Bluetooth core"
eval $(/system/vendor/bin/hci_qcomm_init -e -P 1 && echo "rc=0" || echo "rc=1")

if [ "$rc" = 0 ]; then
    log -t init.bt "hci_qcomm_init done: $BTS_DEVICE $BTS_TYPE $BTS_ADDRESS"
    setprop vendor.bluetooth.status on
else
    log -t init.bt "hci_qcomm_init failed"
    setprop vendor.bluetooth.status off
    exit 1
fi
