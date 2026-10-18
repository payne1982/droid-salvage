# What this tablet actually has, and where each piece comes from

Everything below is read off the device: the `/system` dump, the board DTS in ASUS'
kernel sources, and the recovered kernel configuration. Nothing here is from a spec
sheet or from memory, because both lie. Where something is still unverified it says so.

The column that matters is the last one. A subsystem LineageOS builds from source is
work we can do and debug; a subsystem that exists only as a Nougat binary is work we
can only wire up and hope. The split turned out better than expected.

| subsystem | the hardware | built from source | needed as blobs |
|---|---|---|---|
| **platform** | MSM8956 (Snapdragon 650), `ro.board.platform=msm8952`, rev 1.1 | — | — |
| **display** | 2048×1536 dual-MIPI behind a Pixelworks **iris2** bridge. The board DTS carries six candidate panels; the one actually fitted, read off the running kernel, is **`boe nt35523 dualmipi 1536x2048 cmd`** | kernel driver (`mdss_dsi_iris2*.c`), `hwcomposer`/`gralloc`/`libqdutils`/`libmemalloc` from `display-caf/msm8952` | `libirisConfigure.so`, `libiris_ioctl_wrapper.so`, and the calibration data `DE.o.msm8952`, `Phone_LUT`, `Phone_Vivid`, `Splendid` |
| **GPU** | Adreno 510 | — | the whole Adreno userspace: `libEGL_adreno`, `libGLESv1_CM_adreno`, `libGLESv2_adreno`, `libgsl`, `libadreno_utils`, `libllvm-glnext/qcom/qgl`, `libOpenCL`, `libRSDriver_adreno`, plus `a530_pfp.fw`/`a530_pm4.fw` |
| **video codecs** | Venus, revision 1 (`/sys/devices/soc.0/1d00000.qcom,vidc/version`): H.264, HEVC, VP8, VP9 decode up to 4K, H.264 encode up to 4K | `libOmxVdec`, `libOmxVenc`, `libOmxCore`, `libstagefrighthw`, `libc2dcolorconvert` from `media-caf/msm8952`; the kernel's `msm_vidc` | the Venus firmware (`venus-v1.mdt`, `venus-v1.b00`–`b04`), the C2D backend `libc2d30-a5xx`/`libc2d30_bltlib`, stock's `media_codecs_performance_8956_v1.xml` |
| **audio** | WCD codec on MSM8956; the card registers as `msm8952-snd-card`, which confirms the audio-caf variant | `audio.primary.msm8952.so` from `audio-caf/msm8952` | `libacdbloader`, `libacdbmapper`, `libacdb-fts`, `libacdbrtac`, `libaudcal`, and `/system/etc/acdbdata/` |
| **wifi** | WCNSS **Pronto**, integrated | userspace from `wlan-caf` (`wcnss-service`, `cld80211-lib`, `qcwcn` HAL) | `WCNSS_qcom_cfg.ini`, `WCNSS_qcom_wlan_nv.bin`. **The kernel driver is a problem — see below.** |
| **bluetooth** | WCNSS, same chip | `libbt-vendor` from `bt-caf` | the BT firmware on the firmware partition |
| **modem** | single-SIM **LTE** (`ro.telephony.default_network=12` = LTE/GSM/WCDMA, `persist.radio.multisim.config=ss`). Not 5G: this is a 2016 device and the MSM8956 carries an X8 LTE modem | — | `libril-qc-qmi-1.so` (the path `rild.libpath` names), `rild`, `netmgrd`, `qmuxd`, `rmt_storage`, `ipacm`, the IMS daemons |
| **cameras** | **rear: Toshiba T4K35** (8 MP, 4-lane MIPI), with a dw9714 autofocus actuator and the `le2464c` eeprom. **Front: OmniVision OV5670** (5 MP), `sunny_8865` eeprom. Both read from the kernel log, not from a spec sheet | the provider wrapper, and a shim for one symbol | the whole stack, HAL included: ASUS changed both the HAL and the daemon (their DIT framework), so a HAL from source would have to match their versions of the shared structures. 137 files of the 531 ASUS shipped **— see the caveat below** |
| **sensors** | on the sensor DSP | — | `sensors.msm8952.so`, `libsensor1`, `libsensor_reg`, the `sensors.qcom` daemon, `/system/etc/sensors/` |
| **GPS** | gnss on the modem, GPS + GLONASS | the LA.BR.1.3.6 loc_api HAL (`gps.msm8952`, `libloc_eng`, `libloc_core`, `libgps.utils`), fetched by `tools/setup-gps.sh`: `hardware/qcom/gps` is an older loc_api the blob below does not fit | `libloc_api_v02`, `libloc_ds_api`; not the IZat stack (network location, geofencing, FLP) |
| **storage crypto** | FDE in hardware: `aes-xts` through Qualcomm ICE, master key wrapped by keymaster in the TrustZone | `cryptfs_hw` (synced as `vendor/qcom/opensource/cryptfs_hw`) | `keystore.msm8952.so`, `libQSEEComAPI`, `qseecomd`; the keymaster trustlet lives on the `modem` partition, mounted as `/firmware` |
| **touch** | Atmel maXTouch 1666T2 | kernel driver, with our one-line fix | the controller config `mTX1666T2_cfg.raw` |
| **microSD** | slot on the side | kernel `mmc`/`sdhci` driver and `vold`, both ours | none |
| **USB — charging** | hvdcp-capable charger on the PMI8950 | kernel `qpnp-smbcharger`, which is in the sources | `hvdcp_opti` on stock; not shipped. The driver waited for it before taking a cable plugged in after the boot; `kernel/patches/0018` drops the wait. Without it a Quick Charge adapter stays at 5 V |
| **USB — file transfer** | legacy `android_usb` gadget, not ConfigFS; the FUSB302 Type-C controller | MTP is AOSP, and the gadget driver is in the kernel; LineageOS' basic USB HAL. Pie's platform init only defines adb and the accessory modes for this gadget, so `init.qcom.usb.rc` defines MTP, PTP, tethering and MIDI with ASUS' product IDs; and ASUS' bootloader calls an ordinary boot `androidboot.mode=main`, which Pie's USB service took for a factory mode until `init/` renamed it | none |
| **USB — host / OTG** | OTG on the same port | kernel host mode and the framework | none |
| **mic / speakers** | on the WCD codec | part of the audio HAL above | the ACDB calibration above |

## Not in the first list of things to care about, but present

**Bluetooth** (same WCNSS chip as wifi), **GPS**, and the **sensor** stack, which is what
gives auto-rotation and the ambient light, were first left out of scope. All three work
now. There is no NFC and no fingerprint reader on this tablet.

## The prebuilt kernel modules are all lost on a kernel we build

The stock system loads five modules: `wlan`, `core_ctl`, `texfat`, `tntfs`,
`qdrbg_module`, `qcrypto_module`. Every one of them carries a vermagic naming the stock
kernel release:

```
vermagic: 3.10.84-perf-g3eaf16a77f6-00007-g55252291255 SMP preempt mod_unload modversions aarch64
```

So none of them load on a kernel we built, and that is not a thing to work around — see
the wifi note below. Where each one stands:

| module | what it does | where it comes from |
|---|---|---|
| `wlan` | the WiFi driver | **not in ASUS' sources.** Open source at CodeAurora; has to be built against our kernel |
| `qcrypto_module`, `qdrbg_module` | Qualcomm crypto offload | in the tree (`drivers/crypto/msm`); the recovered config even has `CONFIG_CRYPTO_DEV_QCRYPTO=y` |
| `core_ctl` | CPU core control | in the tree (`drivers/soc/qcom`) |
| `texfat`, `tntfs` | **Tuxera** exFAT and NTFS | proprietary, no source, so both are replaced rather than copied. exFAT, the factory format of microSD cards over 32 GB, is the GPL driver Samsung published, built into the kernel ([`kernel/patches/0013`](../kernel/)). NTFS needs nothing from the kernel but FUSE: LineageOS mounts it with ntfs-3g |

## Two findings that are real work, not wiring

### The WLAN kernel driver is not in ASUS' sources
The kernel carries only the platform glue — `drivers/net/wireless/{cnss,cnss_prealloc,wcnss}`.
The driver itself builds `wlan.ko` out of tree, from a separate Qualcomm repository that
ASUS did not publish, and the stock `/system/lib/modules/wlan.ko` **will not load on a
kernel we built**: the module's vermagic carries the kernel release string, and ours is
`3.10.84-perf-g68a4f29d-dirty` against the stock
`3.10.84-perf-g3eaf16a77f6-00007-g55252291255`.

Forcing the vermagic to match would be the wrong fix twice over: the string is not the
only thing that has to agree, and a module built against a differently-configured kernel
can load and then misbehave, which is the worst failure mode to debug.

**Solved, 9 October 2026.** The driver is **open source** -- Qualcomm's prima -- and
LineageOS carries it in-tree in the kernel for the Xiaomi kenzo, the same SoC on the
same CAF base. It is built into our kernel now (`kernel/patches/0009` and the fetch in
`setup-kernel.sh`), and WiFi works, 5 GHz included. The rest of the path, for whoever
meets it next: `wcnss_service` has to open `/dev/wcnss_wlan` to power the core up
before prima will start; prima starts when the HAL writes the mode to
`/sys/module/wlan/parameters/fwpath`, which has to be the wifi user's; and the HAL
needs `NET_ADMIN`, which Pie's init can only grant through ambient capabilities
(`kernel/patches/0010`). The MAC address is the tablet's own: ASUS wrote it to
`/persist/wifi_mac.txt` at the factory, and `init.macaddr.sh` hands it to the driver,
which prefers it over the placeholder in `WCNSS_qcom_cfg.ini`. The Bluetooth address
comes the same way, from the NV item in `/persist/.bt_nv.bin`.

### The camera blob list cannot be derived from what is present
ASUS shipped the tuning for their whole sensor portfolio, not for this tablet: imx132,
imx135, imx214, imx230, imx258, ov13850 (three variants), ov2685, ov4688, ov5645,
ov5670, ov8858, ov8865, s5k3m2xm, s5k3m2xx, t4k35, hm2051. So the presence of a
`libchromatix_*` file says nothing about what is soldered in.

**Settled by reading the running kernel**, which is why this had to wait for a booting
system:

```
t4k35_4lane probe succeeded      <- rear, 8 MP
ov5670 probe succeeded           <- front, 5 MP
```

That reduces the camera blobs from the 486 files ASUS shipped to **48** sensor-specific
ones — the `t4k35_4lane` and `ov5670` chromatix sets and their three `libmmcamera_*`
drivers — plus the `le2464c` and `sunny_8865` eeprom readers named in the board DTS, and
the common ISP pipeline (`libmmcamera2_*`, `libmmcamera_isp_*`) which is needed whatever
the sensors are. Tractable, where the full set was not.

## What this means for the order of work

Display, video, audio and bluetooth are mostly open source on this platform, which is
the opposite of what we assumed when the ROADMAP was written. The blobs we cannot avoid
are the Adreno userspace, the RIL, the sensor and camera stacks, and the ACDB audio
calibration.

So the first boot does not need much: Adreno for anything to appear on screen, and the
crypto path so `/data` mounts. Everything else can come up afterwards, one subsystem at
a time, which is how the recovery was built and the only method that has worked here.
