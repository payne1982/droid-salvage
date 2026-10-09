#!/system/bin/sh
# Give WiFi and Bluetooth the addresses ASUS assigned this tablet at the factory.
# Ours. Run once at boot, as root, before either is switched on (init.qcom.rc).
#
# Both are in /persist, written at the factory:
#   wifi_mac.txt   the WiFi MAC as twelve hex digits ("88d7f6xxxxxx")
#   .bt_nv.bin     a Qualcomm NV item: 01 01 06, then the BD address, bytes reversed
# Stock read them through the modem (wcnss_service and btnvtool over QMI). Reading
# the files needs nothing but /persist, so it works without the RIL.
#
# WiFi: prima takes the MAC from the WCNSS platform driver when it is set, and only
# falls back to the placeholder in WCNSS_qcom_cfg.ini when it is not. Without this,
# every tablet running the ROM would share one MAC.
# Bluetooth: the AOSP HAL aborts without an address ("Open: No Bluetooth Address!");
# it reads it as text from the file ro.bt.bdaddr_path names.

WCNSS_MAC=/sys/devices/soc.0/a000000.qcom,wcnss-wlan/wcnss_mac_addr
BT_ADDR_FILE=/data/vendor/bluetooth/bdaddr

if [ -r /persist/wifi_mac.txt ]; then
    m=$(tr -dc '0-9A-Fa-f' < /persist/wifi_mac.txt | tr 'A-F' 'a-f')
    if [ ${#m} -eq 12 ]; then
        mac=$(echo "$m" | sed 's/\(..\)/\1:/g; s/:$//')
        echo "$mac" > "$WCNSS_MAC" && log -t macaddr "WiFi MAC set from /persist"
    else
        log -t macaddr "wifi_mac.txt is not a MAC, leaving the WiFi MAC alone"
    fi
fi

if [ -r /persist/.bt_nv.bin ]; then
    hdr=$(od -An -tx1 -N3 /persist/.bt_nv.bin | tr -d ' \n')
    if [ "$hdr" = 010106 ]; then
        set -- $(od -An -tx1 -j3 -N6 /persist/.bt_nv.bin)
        if [ $# -eq 6 ]; then
            echo "$6:$5:$4:$3:$2:$1" > "$BT_ADDR_FILE"
            chown bluetooth:bluetooth "$BT_ADDR_FILE"
            chmod 0644 "$BT_ADDR_FILE"
            log -t macaddr "Bluetooth address set from /persist"
        fi
    else
        log -t macaddr ".bt_nv.bin has an unexpected header ($hdr), leaving it alone"
    fi
fi
