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
| **display** | 2048×1536 dual-MIPI behind a Pixelworks **iris2** bridge; panels tianma r63319 / nt35523, auo nt35523, boe nt35523 | kernel driver (`mdss_dsi_iris2*.c`), `hwcomposer`/`gralloc`/`libqdutils`/`libmemalloc` from `display-caf/msm8952` | `libirisConfigure.so`, `libiris_ioctl_wrapper.so`, and the calibration data `DE.o.msm8952`, `Phone_LUT`, `Phone_Vivid`, `Splendid` |
| **GPU** | Adreno 510 | — | the whole Adreno userspace: `libEGL_adreno`, `libGLESv1_CM_adreno`, `libGLESv2_adreno`, `libgsl`, `libadreno_utils`, `libllvm-glnext/qcom/qgl`, `libOpenCL`, `libRSDriver_adreno`, plus `a530_pfp.fw`/`a530_pm4.fw` |
| **video codecs** | Venus | `libOmxVdec`, `libOmxVenc`, `libOmxCore` from `media-caf/msm8952` | the Venus firmware (`venus.mdt`, `venus.b00`–`b04`) |
| **audio** | WCD codec on MSM8956 | `audio.primary.msm8952.so` from `audio-caf/msm8952` | `libacdbloader`, `libacdbmapper`, `libacdb-fts`, `libacdbrtac`, `libaudcal`, and `/system/etc/acdbdata/` |
| **wifi** | WCNSS **Pronto**, integrated | userspace from `wlan-caf` (`wcnss-service`, `cld80211-lib`, `qcwcn` HAL) | `WCNSS_qcom_cfg.ini`, `WCNSS_qcom_wlan_nv.bin`. **The kernel driver is a problem — see below.** |
| **bluetooth** | WCNSS, same chip | `libbt-vendor` from `bt-caf` | the BT firmware on the firmware partition |
| **modem** | single-SIM **LTE** (`ro.telephony.default_network=12` = LTE/GSM/WCDMA, `persist.radio.multisim.config=ss`). Not 5G: this is a 2016 device and the MSM8956 carries an X8 LTE modem | — | `libril-qc-qmi-1.so` (the path `rild.libpath` names), `rild`, `netmgrd`, `qmuxd`, `rmt_storage`, `ipacm`, the IMS daemons |
| **cameras** | two, both declared in the board DTS: rear with an autofocus actuator (eeprom `le2464c`), front (eeprom `sunny_8865`, which points at an OV8865) | the camera HAL is a blob on this generation | 112 `libmmcamera*` and `libchromatix_*` files **— but see the caveat below** |
| **sensors** | on the sensor DSP | — | `sensors.msm8952.so`, `libsensor1`, `libsensor_reg`, the `sensors.qcom` daemon, `/system/etc/sensors/` |
| **GPS** | gnss on the modem | `gps.default.so` from `hardware/qcom/gps` | `liblocationservice`, `libloc_ext`, `loc_launcher` |
| **storage crypto** | FDE in hardware: `aes-xts` through Qualcomm ICE, master key wrapped by keymaster in the TrustZone | `cryptfs_hw` (synced as `vendor/qcom/opensource/cryptfs_hw`) | `keystore.msm8952.so`, `libQSEEComAPI`, `qseecomd`; the keymaster trustlet lives on the `modem` partition, mounted as `/firmware` |
| **touch** | Atmel maXTouch 1666T2 | kernel driver, with our one-line fix | the controller config `mTX1666T2_cfg.raw` |
| **microSD** | slot on the side | kernel `mmc`/`sdhci` driver and `vold`, both ours | none |
| **USB — charging** | hvdcp-capable charger on the PMI8950 | kernel `qpnp-smbcharger`, which is in the sources | `hvdcp_opti` |
| **USB — file transfer** | legacy `android_usb` gadget, not ConfigFS | MTP is AOSP, and the gadget driver is in the kernel | none |
| **USB — host / OTG** | OTG on the same port | kernel host mode and the framework | none |
| **mic / speakers** | on the WCD codec | part of the audio HAL above | the ACDB calibration above |

## Not in the list of things to care about, but present

Worth naming so the choice to skip them is deliberate: **bluetooth** (same WCNSS chip as
wifi), **GPS**, and the **sensor** stack, which is what gives auto-rotation and the
ambient light. There is no NFC and no fingerprint reader on this tablet.

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

The right route is that the driver is **open source** — the `prima`/`qcacld` trees were
released by CodeAurora — so it gets added as an out-of-tree module built against our
kernel, from the branch matching this SoC and vintage. Until then: no wifi.

### The camera blob list cannot be derived from what is present
ASUS shipped the tuning for their whole sensor portfolio, not for this tablet: imx132,
imx135, imx214, imx230, imx258, ov13850 (three variants), ov2685, ov4688, ov5645,
ov5670, ov8858, ov8865, s5k3m2xm, s5k3m2xx, t4k35, hm2051. So the presence of a
`libchromatix_*` file says nothing about what is soldered in.

The sensor identity has to be read off the running device — the kernel log at probe
time, or the camera sysfs nodes — which means the camera blob list is the one thing
here that genuinely has to wait for a booting system. Fitting, since the camera is last
in the plan anyway.

## What this means for the order of work

Display, video, audio and bluetooth are mostly open source on this platform, which is
the opposite of what we assumed when the ROADMAP was written. The blobs we cannot avoid
are the Adreno userspace, the RIL, the sensor and camera stacks, and the ACDB audio
calibration.

So the first boot does not need much: Adreno for anything to appear on screen, and the
crypto path so `/data` mounts. Everything else can come up afterwards, one subsystem at
a time, which is how the recovery was built and the only method that has worked here.
