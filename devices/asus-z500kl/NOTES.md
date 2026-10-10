# Z500KL: what it took, and why

Written so the next person does not have to rediscover any of it. The recurring theme is
simple to state and was expensive to learn:

> A Pie-based TWRP on this tablet is a **Nougat userspace reconstructed inside an
> Android 9 recovery**. Almost every problem was a stock binary finding one of its
> assumptions no longer true — not anything to do with encryption, kernels or hardware.

---

## 1. The bootloader: locked, but it does not pin a key

The important finding, because it decides what is possible at all.

- `fastboot flash` and `fastboot boot` are **disabled** (`oem unlock is not allowed`,
  `fastboot boot command is not available`, `Partition flashing is not allowed`). The
  only way in is `dd` from a root shell, so there is no "try it without writing" step.
- Images use **AVB 1.0**: an ASN.1 signature appended after the ramdisk, carrying the
  signing certificate and the target partition name.
- The stock recovery is signed by ASUS ("QCT Root CA 1", SW4 BSP). Our images are signed
  with the **public AOSP test key**. Both boot, both report
  `androidboot.verifiedbootstate=yellow`.

So the bootloader verifies an image against the certificate **embedded in that image**
and reports yellow because the key is not the OEM's. It does not check the key against
anything. A private key would buy nothing here; the public test key keeps builds
reproducible by anyone. The target name *is* checked — sign for `/recovery`, or you get
`boot_verifier: verification failure due to target name mismatch`.

### The bootloader does not hash the kernel either

Worth stating because it looks otherwise at first. A kernel blob recompressed with a
different gzip (29,459,901 bytes instead of 29,457,161) boots fine. An image with two
bytes changed in the kernel's version banner boots fine.

An earlier patch *did* fail — reboot, then a hang on the ASUS logo — and it was tempting
to read that as the bootloader rejecting a modified kernel. It was not: it was a **kernel
panic**. That patch changed `entry_mode` globally (below), which the charger, display and
sensor drivers also branch on. **A modified kernel boots on this device**, so a custom
ROM is not blocked by the bootloader.

Note for debugging: a *warm* reboot preserves the previous boot's kernel log in
`/sys/fs/pstore/console-ramoops-0`. A forced power-off loses it, because RAM loses power.

---

## 2. The touchscreen is not broken, the driver parks it

In recovery the digitiser is dead. LK always appends `androidboot.mode=recovery` when it
boots the recovery partition; ASUS' `start_kernel()` turns that into `entry_mode=2`, and
the tail of `mxt_probe()` in `drivers/input/touchscreen/atmel_z500` (source line 6163)
does:

```c
if (entry_mode != 1) {
        msleep(1000);
        mxt_set_t7_power_cfg(data, MXT_POWER_CFG_DEEPSLEEP);
        touch_ic_status = false;
        return 0;
}
```

With `touch_ic_status` false the IRQ handler drops every event. The only place that sets
it back to true is `mxt_read_info_block()`, reachable from userspace only through
`update_fw`, which **reflashes the touch controller firmware** — too risky for a fix.

So the kernel has to be patched, but **not** by changing `entry_mode`: that is what
caused the panic above. `tools/patch-kernel.py` turns the single guard branch in
`mxt_probe` into an unconditional one:

```
0x5b7b18:  0x540005e0  (b.eq +47)  ->  0x1400002f  (b +47)
```

**3 bytes** in the whole image, inside `mxt_probe` only. `entry_mode` stays correct for
every other driver, and behaviour in Android is unchanged — there `entry_mode` is already
1, so the block was skipped anyway.

The script locates the site from the code rather than from a fixed offset: it finds the
`" ATMEL Touch DEEPSLEEP ... \n"` literal, the `adrp`/`add` pair that references it
followed by the `strb wzr` that clears `touch_ic_status`, then the `b.eq` above it,
asserting that the preceding instruction is `cmp wN, #1`.

One more thing is needed: `/etc/firmware/mTX1666T2_cfg.raw` in the ramdisk. 15 s after
probe the driver re-checks its configuration, and without that file it gives the chip
five soft resets looking for it.

---

## 3. `/dev/block/bootdevice` does not exist under TWRP

This single missing symlink caused three separate symptoms over two days.

This kernel is 3.10 and reports old-style `/devices/soc.0/...` device paths. TWRP's
ueventd does not build `/dev/block/platform/soc.0/7824900.sdhci/by-name/` from them, and
nothing creates the `/dev/block/bootdevice` symlink that the stock vendor init normally
makes.

Symptoms, in the order they appeared:

1. **Nothing mounts.** Every `recovery.fstab` entry pointed at `by-name`. In the Mount
   menu the row flashed on touch but no checkbox appeared — touch was fine, the mount
   was failing. Fixed by naming the raw `mmcblk0pN` nodes instead.
2. **No PIN prompt.** TWRP looks for the crypto footer through the same path, fails to
   find it, has no password type to ask for, and skips the decrypt page. Same fix.
   (A second mistake of mine compounded this: the fstab had `length=-16384` but not the
   `encryptable=footer` flag. `Crypto_Key_Location` starts empty in `partition.cpp` and
   only that flag sets it, so `cryptfs_check_footer()` could not work either.)
3. **`qseecomd` dies.** Stock binaries have the path *compiled in* and cannot be pointed
   elsewhere, so raw nodes in a config file do not help them:

   ```
   E/rpmb: Error finding /dev/block/bootdevice (error no: 2)
   E/rpmb: No RPMB device found - exiting!!
   E/QSEECOMD: ERROR: RPMB_INIT failed, shall not start listener services
   ```

   `librpmb.so` stats it to tell eMMC from UFS; `libssd.so` opens `by-name/ssd` under it.

`recovery/root/sbin/bootdevice-links.sh` rebuilds the whole tree, reading partition names
from `PARTNAME=` in each partition's sysfs uevent rather than hardcoding a table, and
also creates the `/dev/block/mmcblk0rpmb` node if ueventd has not.

### A chown, not a chmod

twrpdtgen copies the stock `ueventd.qcom.rc` into the tree, and it turns out to be
load-bearing for exactly two lines: it makes `/dev/qseecom` `system:drmrpc` and
`/dev/ion` `system:system`. Since `qseecomd` drops to uid 1000 before forking, a `chmod`
alone leaves those nodes `root:root` and it cannot open them. Those two `chown`s now live
in `init.recovery.qcom.rc`, which let the vendor file be dropped entirely — verified by
building without it and decrypting successfully. Nothing else in its 240 lines (camera,
LEDs, i2c sysfs, FRP) matters to a recovery that runs as root.

### Reading `qseecomd`'s exit status correctly

`init` reports `Service 'sys_qseecomd' exited with status 255` and throws the daemon's
own output away. 255 is **not** the error. Disassembly of `main` shows:

```
prctl(PR_SET_KEEPCAPS); setgid(1000); setuid(1000); capset(); fork()
  parent: log, wait(child), return -1      <- the 255 init sees
  child : dlopen the listener libs, RPMB_INIT, SSD_INIT, load the keymaster trustlet
```

So 255 means *the child died immediately*. In a healthy run the child stays alive as a
daemon and the parent blocks in `wait()` forever.

And the child's reasons were invisible because `setuid(1000)` happens **before** the
fork: everything it logs goes through logd as uid 1000. Under TWRP logd is not even
started by init — start it by hand and make `/dev/socket/logd*` writable, or you get an
empty `logcat` and conclude, wrongly, that nothing was logged.

---

## 4. Nougat binaries cannot read properties under TWRP

The subtle one, and the cause of the last failure.

Android 8 changed how properties are stored. A Nougat binary looks for
**`/property_contexts`** — the prefix→context index — to know which file under
`/dev/__properties__/` holds a given property. Pie ships `plat_property_contexts`
instead, so that index is missing and **every `property_get` returns empty**.

Writing still works, because `property_set` goes through a socket whose protocol did not
change. That asymmetry is genuinely confusing in the logs: `qseecomd` successfully *sets*
`sys.listeners.registered`, while `vold` reads empty strings.

The binary format of the per-context files is compatible, so dropping the stock Nougat
`/property_contexts` into the ramdisk is enough. Consequences of its absence:

- `vold` builds its fstab path as `"/fstab." + ro.hardware` and so looked for the literal
  **`/fstab.`**: `Failed to open default fstab /fstab.: No such file or directory`.
  (`bootdevice-links.sh` still creates that alias as a belt-and-braces.)
- `cryptfs_check_passwd` aborts early with
  `encrypted fs already validated or not running with encryption` because it reads
  `ro.crypto.state` as empty rather than `encrypted`.
- and the one that cost the most, next.

---

## 5. Why a correct PIN was rejected

With everything above fixed, TrustZone still refused the right PIN:

```
E/QSEECOMAPI: Error::ioctl call to create encryption key for usage 4 failed with ret = -1, errno = 22
QSEECOM: __qseecom_set_clear_ce_key: process_incomplete_cmd FAILED, resp.result -71
QSEECOM: qseecom_create_key: Failed to create key: pipe 2, ce 0: -22
```

The names for those numbers are in the kernel's `include/soc/qcom/qseecomi.h`:

```c
#define QSEOS_RESULT_FAIL_KEY_ID_EXISTS   -65   /* benign, the driver ignores it */
#define QSEOS_RESULT_FAIL_INCORRECT_PSWD  -71
#define QSEOS_RESULT_FAIL_MAX_ATTEMPT     -72
```

So `-71` is literally "wrong password", and the `EINVAL` reaching `vold` was only the
consequence. Also note: in those kernel messages `lstr=<n>` is the **last listener
involved**, not the culprit (12288 = SSD, 8192 = RPMB, 10 = drmfs, 16384 = secure UI,
28672 = gpfs). `usage 4` is `QSEOS_KM_USAGE_SDCC_ICE_DISK_ENCRYPTION`, which is correct
here: `/dev/icesdcc` exists, so this tablet really does use the inline crypto engine.

The cause: `vold` picks its keymaster module with `hw_get_module_by_class`, which tries
`keystore.<ro.hardware>.so`, then `<ro.product.board>`, then `<ro.board.platform>`, then
`default`. The middle two come from `/system/build.prop`, which **recovery never loads**,
so they were empty and the lookup fell through to:

```
/system/lib64/hw/keystore.default.so            6 KB   software keymaster
/system/vendor/lib64/hw/keystore.msm8952.so    51 KB   the one that talks to QSEE
```

The software keymaster cannot reach the key held inside the chip, so the value derived
from the PIN did not match what TrustZone had stored. Two properties fix it:

```
setprop ro.product.board  msm8952
setprop ro.board.platform msm8952
```

### The decryption chain, for reference

```
PIN -> scrypt -> signed by keymaster inside TrustZone -> unwraps the master key
    -> master key sets up dm-crypt (aes-xts, ICE)
```

The footer (last 16 KB of `userdata`) says `aes-xts`, 128-bit, `crypt_type = PIN`,
`kdf = scrypt+keymaster`, with a 1408-byte keymaster blob. **The PIN alone is
mathematically insufficient** — the hardware is part of the key. Which also means that
eMMC, read in a card reader, is unreadable for good.

Back up those 16 KB before touching anything. They are the one part of the device that
cannot be reconstructed, they are not in any partition dump that skips `userdata`, and
they contain the wrapped master key, so treat the file as a secret.

### Configuration that makes it work

```make
TW_INCLUDE_CRYPTO := true
TW_CRYPTO_USE_SYSTEM_VOLD := qseecomd
TW_CRYPTO_SYSTEM_VOLD_MOUNT := firmware
```

TWRP's own crypto code on a 9.0 base wants the keymaster **HIDL** HALs, which a Nougat
vendor does not provide, so the stock `vold` runs instead, with its libraries from the
mounted `/system`. `qseecomd` loads the keymaster trustlet from `/firmware/image` on the
modem partition, hence the `firmware` mount. A `fstab.qcom` in fs_mgr format is also
needed in the ramdisk: `vold_decrypt` hides TWRP's own fstab, which fs_mgr cannot parse.

---

## 6. adb in recovery: two separate causes

1. **`adbd` logs `aio: got error submitting read: Invalid argument` in a loop** and the
   host sees the device as permanently `offline`. Pie's `adbd` drives FunctionFS through
   AIO, which a 3.10 kernel does not implement. Google anticipated this; `daemon/usb.cpp`
   has the fallback, keyed on a property:

   ```
   setprop sys.usb.ffs.aio_compat true
   ```

   The comment there reads: *"Devices on older kernels (< 3.18) will not have aio support
   for ffs unless backported. Fall back on the non-aio functions instead."*

2. Then **no device appeared on the USB bus at all**. Nothing copies
   `persist.sys.usb.config` into `sys.usb.config` under TWRP, so the gadget was never
   configured or enabled. `setprop sys.usb.config adb` in `on boot` fires TWRP's own
   `on property:sys.usb.config=adb` action, which sets the functions, enables the gadget
   and starts adbd. The device then shows up as `18d1:d001`.

After any USB reconfiguration, run `adb kill-server` on the host — otherwise it looks as
though the tablet vanished.

Getting adb working changed the pace of everything else: a shell inside TWRP replaces a
reboot-and-read-logs cycle per hypothesis.

---

## 7. Mistakes worth repeating out loud

- **The diagnostic became the bug.** A script that ran `qseecomd` twice to measure it
  took the TrustZone listeners for itself; `vold`'s instance was then refused them
  (`Register listener ioctl failed for lstnr ID 8192`). Remove instrumentation from the
  next test build.
- **Measuring the wrong thing and not noticing.** The first version of that script ran on
  the `boot` trigger, in parallel with TWRP starting up — and TWRP unmounts `/system` on
  its way up. Two of its three test cases never ran, and the result was worthless. Mount
  what you need inside each attempt.
- **Changing two things at once.** The failed `entry_mode` patch and a gzip
  recompression went into the same image, and the failure could not be attributed to
  either. Isolating them (recompress only, then two harmless bytes, then the real patch)
  is what produced the finding in §1.
- Hypotheses that looked strong and were wrong: libraries unreachable (TWRP's
  `/sbin/ld.config.txt` does include `/vendor/${LIB}`); `enable ${service.adb.root}`
  writing an empty value (that property is 1); `exec_background` unsupported in Pie init
  (it is supported).

## 8. What came next

This file is about the recovery. The ROM it made possible is in [`rom/`](rom/): LineageOS
16.0, Android 9, on a kernel built from ASUS' sources ([`kernel/`](kernel/)), with the
plan and how each step went in [`ROADMAP.md`](ROADMAP.md), and its own findings in
[`rom/NOTES.md`](rom/NOTES.md).

Two guesses written here before that work, and how they turned out:

- *Carving a `vendor` partition out of `userdata`* turned out unnecessary: LineageOS 16.0
  is the last branch that supports a non-Treble device properly, so the partition table
  was never touched — which, with a locked bootloader and EDL as the only way back from
  a broken GPT, is the best outcome there was.
- *The kernel lacks `MEMCG`* — it did, and turning it on exposed a bug in ASUS' tree
  (`kernel/README.md`). `bpf()` is still missing, and that is what keeps this tablet on
  Android 9.
