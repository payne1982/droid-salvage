# ASUS ZenPad 3S 10 LTE — TWRP 3.7

|  |  |
|---|---|
| model | Z500KL (project id **P00I**) |
| `ro.product.device` | `ASUS_P00I` — the device tree directory must be named this |
| SoC | Qualcomm MSM8956 (Snapdragon 650), arm64 |
| RAM | 4 GB (3.55 GiB usable) |
| display | 2048×1536, MIPI command mode behind a Pixelworks **iris2** bridge |
| touch | Atmel maXTouch 1666T2 |
| stock | Android 7.0 (NRD90M), kernel 3.10.84, **not** Treble |
| bootloader | locked; `fastboot flash` and `fastboot boot` are both disabled |

As far as the XDA threads for this tablet go, this is the first working TWRP for it.

## What works

- boots and runs, with a working **touchscreen** (a 3-byte kernel patch — see NOTES)
- mounts every partition: system, cache, data, persist, firmware, microSD, USB-OTG
- **decrypts `/data`** (Qualcomm hardware FDE, `aes-xts`, PIN, keymaster-wrapped key)
- backup and restore, including `/data` once decrypted
- **adb** over USB

## What does not

- **MTP is disabled on purpose.** TWRP's MTP server is the FunctionFS one and wants its
  own functionfs instance; making this legacy `android_usb` gadget multiplex two ffs
  instances would put the adb path at risk, and `adb push`/`adb pull` does the same job.
  The tablet also has a microSD slot and OTG.
- Two harmless lines appear at every decryption:

  ```
  Failed to init keymaster 0/1
  Decrypt process ended with signal: 6
  ```

  This is TWRP trying its own crypto first. On a Pie base it wants the keymaster
  **HIDL** HALs, which a Nougat vendor does not provide, so the forked child aborts and
  TWRP falls back to the stock `vold`, which succeeds. In `Decrypt_Device` the native
  attempt is unconditional — there is no flag to skip it — so removing those lines would
  mean patching TWRP itself, outside this tree and lost on every `repo sync`. Documented
  rather than papered over.

## Flashing

`fastboot flash` is disabled on this bootloader, so the image is written from a root
shell with `dd`, and it **must be AVB1-signed** or the bootloader will not take it:

```sh
magiskboot sign twrp.img /recovery          # AOSP test key, bundled in magiskboot
dd if=twrp.img of=/dev/block/mmcblk0p43 bs=1048576
```

Always read the partition back and compare hashes afterwards.

The target name `/recovery` matters: the bootloader checks it and refuses an image
signed for a different partition. On the key, see NOTES — the bootloader does not pin
one, so the public AOSP test key is the right choice and keeps builds reproducible.

Expect the yellow "the bootloader is unlocked" warning screen at boot. It was already
there if your boot image is Magisk-patched.

## Building

The TWRP tree does not build on ARM, so you need an x86_64 Linux box.

```sh
# 1. TWRP minimal manifest
repo init -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_omni.git \
          -b twrp-9.0 --depth=1
repo sync -c -j8 --no-tags --no-clone-bundle

# 2. this device tree
rsync -a devices/asus-z500kl/twrp/ <twrp-tree>/

# 3. the vendor pieces, straight off your tablet (adb, in TWRP or rooted Android)
cd <twrp-tree>/device/asus/ASUS_P00I
./tools/extract-from-device.sh

# 4. build
cd <twrp-tree>
source build/envsetup.sh
lunch omni_ASUS_P00I-eng
mka recoveryimage
```

### Gotchas on a modern distribution

This is an Android 9 tree; on Debian 13 (and anything comparable) it needs:

- **Python 2.7.** Not packaged any more. A local conda/micromamba environment is
  enough. Soong's `python_binary_host` looks for an executable literally named
  `python2.7` on `PATH`, so provide that name as well as `python`.
- **`libtinfo.so.5` and `libncurses.so.5`**, for the prebuilt clang. Extract them from
  Debian 11 `.deb`s into a local directory and point `LD_LIBRARY_PATH` at it.
- **Shebang fixes.** Many in-tree scripts start with `#!/usr/bin/python`. Rewrite them
  to `#!/usr/bin/env python`; `prebuilts/gcc/linux-x86/*/*/bin/*-gcc` and `*-g++` are
  wrappers that matter most. `repo sync` restores them, so redo it afterwards:

  ```sh
  grep -rlI --exclude-dir=.git --exclude-dir=.repo --exclude-dir=out \
       -m1 '^#!/usr/bin/python$' . \
    | xargs -r sed -i '1s|^#!/usr/bin/python$|#!/usr/bin/env python|'
  ```

### Adding strace for debugging

Not shipped, so that the committed tree builds exactly the published image. To add it:

```sh
m strace
cp $OUT/system/bin/strace device/asus/ASUS_P00I/recovery/root/sbin/
```

Then patch its `PT_INTERP` from `/system/bin/linker64` to `/sbin/linker64` — otherwise
under TWRP it would use the tablet's *Nougat* linker. The replacement string is shorter,
so it can be overwritten in place. Its libraries (`libc++`, `libc`, `libm`, `libdl`) are
already in TWRP's `/sbin`.

## Credits

Kernel sources published by ASUS, mirrored at
<https://github.com/6ccg/android_kernel_asus_z500kl>. The device tree started from
[twrpdtgen](https://github.com/twrpdtgen/twrpdtgen) output.
