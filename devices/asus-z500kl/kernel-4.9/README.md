# Kernel 4.9 for ASUS_P00I — an experiment

LineageOS 20 runs on ASUS' 3.10 kernel ([../kernel](../kernel)), with what Android 13
needs from newer kernels brought back to it by hand. This branch tries the other way
round: a 4.9 kernel that already has all of that (binder as Android 13 wants it,
`memfd_create`, eBPF, ext4 encryption), taught about this tablet.

It is an experiment. Nothing here is in a release, and the tablet is only ever
started on it for a test, from the boot partition, with the LineageOS boot image put
back afterwards.

## The base

The MSM8956 never had a 4.9 kernel from Qualcomm. Sony's Open Devices program had one
for the Xperia X family (Loire), the same SoC, and its maintainer carried it on to
Qualcomm's LA.UM.9.8 tag: [bartcubbins/kernel_loire](https://github.com/bartcubbins/kernel_loire),
branch `LA.UM.9.8.r1-03400-SDM710.0`, pinned here at `ec3c488d`. It has booted on real
MSM8956 hardware, and its display driver is the same family as ASUS' 3.10 one, which
matters for the display bridge this tablet has.

## What is here

- `files/` — this tablet's own files, copied into the tree as they are:
  - `arch/arm64/boot/dts/asus/msm8956-v1.1-z500kl.dts`, the device tree. The SoC is
    described by the tree's own `msm8956-v1.1.dtsi`; the board comes from ASUS'
    3.10 device tree (`msm8956-v1.1-cdp-Z500KL.dts` and what it includes). Each
    value that differs from Qualcomm's says where it comes from.
  - the battery profile ASUS' 3.10 tree carries for this tablet's 7800 mAh cell;
  - `arch/arm64/configs/z500kl_defconfig`: Sony's `loire_suzu_defconfig` without
    the drivers for the Xperia's own hardware, Sony's panel driver among them;
  - the two panels the Z500KL was built with, BOE and Tianma, as in ASUS' tree
    (`dsi-panel-*.dtsi`); GPIO 126 says which one is fitted (`patches/0006`);
  - `drivers/video/fbdev/msm/`: from ASUS' 3.10, the light-up driver of the
    Pixelworks iris2 bridge, the bridge's power driver and the LP8557 backlight
    driver, with what was particular to ASUS' other tablets taken out.
- `patches/` — changes to the kernel's own files, one per change, each saying why.
- `tools/setup-kernel.sh`, `tools/build-kernel.sh` — fetch the base and the exFAT
  driver, copy `files/` into it and apply `patches/`, build `Image.gz-dtb`.
- `tools/make-test-image.sh`, `test/configfs-adb.rc` — a boot image to try the kernel
  with (below).

## Building

```sh
tools/setup-kernel.sh
KERNEL_TOOLCHAIN=<lineage-20>/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin \
    tools/build-kernel.sh
LINEAGE_TREE=<lineage-20> tools/make-test-image.sh twrp-3.7.0_9-Z500KL-payne_17.img k49-test.img
```

The tree goes to `~/droid-salvage-build/kernel-4.9` unless `KERNEL_TREE` says
otherwise, as for the 3.10 kernel.

## Trying it

The test image is the 4.9 kernel with the ramdisk of this repository's TWRP, which
starts far less than Android, with no display needed, and brings up adb. A kernel
without the `android_usb` gadget needs adb set up through ConfigFS, which
`test/configfs-adb.rc` adds.

1. In TWRP, check the recovery's hash, and that the boot partition holds the
   LineageOS boot image you will put back.
2. Write the test image to `boot` (TWRP's `dd` wants `bs=1048576`; it refuses `1M`)
   and read it back.
3. Reboot to the system. The screen stays on the ASUS logo.
4. To get out, hold the power key for 10 seconds: this kernel then panics on
   purpose (`CONFIG_POWERKEY_FORCECRASH`) and restarts after 5, which keeps RAM
   powered. Go straight into TWRP with the key combination; the kernel's log is in
   `/sys/fs/pstore`. The device tree lays out that area as ASUS' 3.10 does, so
   TWRP can read it.
5. Write the LineageOS boot image back and check it, and the recovery.

## Where it stands

| | |
|---|---|
| ASUS' bootloader takes the image | yes |
| the kernel starts on this device tree, all CPUs, 3.4 GB of RAM | yes |
| persistent RAM log, read back by TWRP's 3.10 | yes |
| eMMC | yes — HS400 enhanced strobe, command queueing, all 45 partitions |
| TWRP's userspace: init, SELinux, ueventd, logd, adbd; system, persist, cache and data mounted | yes, stable for over a minute |
| microSD | yes, with `patches/0003` — a 256 GB card in UHS SDR104, raw reads at 72 MB/s |
| battery: the fuel gauge with ASUS' profile for the 7800 mAh cell | yes — the profile is recognised, level and temperature read |
| charging, from a computer's USB port | yes — some 630 mA into the battery, at 24.5 °C |
| adb over USB, through ConfigFS | yes |
| I²C buses | yes — at first deferred until the clock driver is up, then all four by 0.36 s |
| display: the panel (BOE or Tianma) behind the Pixelworks iris2 bridge, the LP8557 backlight | described, with the iris2 light-up driver from ASUS' 3.10 (`patches/0004` to `0006`); not tried yet |
| touch: Atmel maXTouch mXT1666T2 | described, with the kernel's own `atmel_mxt_ts` in place of ASUS' driver; not tried yet |
| audio, Wi-Fi, cameras, modem | not yet |

## The 3.10 patches

Of the patches in [../kernel/patches](../kernel/patches):

- **already in 4.9:** 0003, 0004, 0005, 0006, 0007, 0010, 0011, 0012, 0015,
  0017, 0028 (binder and its security context, sdcardfs, the I-frame size hint
  for the video encoder, `getrandom`, ambient capabilities, `memfd_create`,
  `O_TMPFILE`, the cgroup permission), and 0029 in effect: this kernel's
  read-ahead is 512 KB for every disk;
- **for building 3.10 only:** 0001, 0014, 0016;
- **to look at again:** 0008, 0027;
- **for ASUS' touch driver, which this kernel does without** (it uses its own
  `atmel_mxt_ts`): 0002, 0026. The controller keeps its configuration; ASUS'
  `mTX1666T2_cfg.raw` is in the OBP_RAW format this driver reads as
  `maxtouch.cfg`, rewriting the controller only when the two differ, so a ROM
  on this kernel can carry it under that name;
- **brought over:** 0013 (exFAT, as `patches/0009` and the same exfat-nofuse),
  0020 (`0010`), 0021 (the camera heap, in the device tree), 0022 and 0023
  (`0007`, `0008`), 0025 (`0011` and the device tree);
- **for ASUS' charger driver, which this kernel does without** (Qualcomm's own,
  which neither holds a cable back for Quick Charge 3 nor reports a status of
  ASUS' own): 0018, 0019;
- **still to bring over:** 0009 (prima, the Wi-Fi driver).
