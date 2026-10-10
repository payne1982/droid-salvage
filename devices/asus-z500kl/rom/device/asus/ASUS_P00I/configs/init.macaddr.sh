#!/system/bin/sh
# Give WiFi and Bluetooth the addresses ASUS assigned this tablet at the factory.
# Ours. Run once at boot, as root, before either is switched on (init.qcom.rc).
# wcnss_service, which powers the WCNSS core up, is started by init once this has
# exited (init.qcom.rc), so the MAC is set by then.
#
# The addresses are in /persist, written at the factory:
#   wifi_mac.txt   the WiFi MAC as twelve hex digits ("88d7f6xxxxxx")
#   .bt_nv.bin     a Qualcomm NV item: 01 01 06, then the BD address, bytes reversed
#                  (01 00 06 marks a generated address rather than one from the NV)
# That is the only place they are: stock's wifi_init reads wifi_mac.txt and otherwise
# says "MAC has not been set, will use random MAC", and asking the modem's NV gets
# nothing on this tablet (tried: stock wcnss_service over QMI, btnvtool -O).
#
# When a file is missing -- a wiped /persist, say -- this falls back to an address
# derived from the serial number: stable from boot to boot and different from tablet
# to tablet, unlike stock's random one, and locally administered (02:...), as an
# address no manufacturer assigned should be. /persist is never written.
#
# WiFi: prima takes the MAC from the WCNSS platform driver when it is set, and only
# falls back to the placeholder in WCNSS_qcom_cfg.ini, the same on every tablet.
# Bluetooth: the AOSP HAL aborts without an address ("Open: No Bluetooth Address!");
# it reads it as text from the file ro.bt.bdaddr_path names.

WCNSS_MAC=/sys/devices/soc.0/a000000.qcom,wcnss-wlan/wcnss_mac_addr
BT_NV=/persist/.bt_nv.bin
BT_ADDR_FILE=/data/vendor/bluetooth/bdaddr

derived() { # a locally administered address from the serial number and a label
    h=$(echo -n "$(getprop ro.serialno)-$1" | sha1sum | cut -c1-10)
    echo "02${h}" | sed 's/\(..\)/\1:/g; s/:$//'
}

# --- WiFi ---
mac=
if [ -r /persist/wifi_mac.txt ]; then
    m=$(tr -dc '0-9A-Fa-f' < /persist/wifi_mac.txt | tr 'A-F' 'a-f')
    [ ${#m} -eq 12 ] && mac=$(echo "$m" | sed 's/\(..\)/\1:/g; s/:$//') && src=/persist
fi
if [ -z "$mac" ]; then
    mac=$(derived wifi)
    src="the serial number (no usable /persist/wifi_mac.txt)"
fi
echo "$mac" > "$WCNSS_MAC" && log -t macaddr "WiFi MAC set from $src"

# --- Bluetooth ---
bt=
if [ "$(od -An -tx1 -N3 "$BT_NV" 2>/dev/null | tr -d ' \n')" = 010106 ]; then
    set -- $(od -An -tx1 -j3 -N6 "$BT_NV")
    [ $# -eq 6 ] && bt="$6:$5:$4:$3:$2:$1" && src=$BT_NV
fi
if [ -z "$bt" ]; then
    bt=$(derived bluetooth)
    src="the serial number (no usable $BT_NV)"
fi
echo "$bt" > "$BT_ADDR_FILE"
chown bluetooth:bluetooth "$BT_ADDR_FILE"
chmod 0644 "$BT_ADDR_FILE"
log -t macaddr "Bluetooth address set from $src"
