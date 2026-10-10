# LineageOS 16 on the Z500KL: what it took, and why

The recovery's [NOTES](../NOTES.md) found that a Pie TWRP on this tablet is a Nougat
userspace rebuilt inside Android 9. The ROM is the same problem at full size: Android 9's
framework on top of ASUS' Nougat blobs and a 3.10 kernel. Nearly everything below is one
of three things — a Nougat binary meeting a Pie assumption, a 3.10 kernel missing
something Pie takes for granted, or a stock behaviour nobody wrote down because the
stock ROM never needed it to be.

The method was the same as for the recovery: one change per boot, and every conclusion
read off a log rather than inferred from a symptom. Each section says what the symptom
was, because the symptom is what the next person will search for.

---

## 1. First boot: six boots, six missing pieces

The first boot's goal was observability, not a working tablet. It took six attempts, and
each one stopped on exactly one thing.

1. **ASUS logo, no USB.** Pie's `init.rc` leaves `mount_all` to the device's
   `init.${ro.hardware}.rc`, and there was none yet, so nothing mounted. The pstore
   console was no help: 256 KB filled up with USB connect/disconnect events from an
   unconfigured gadget. The fix was our own `init.qcom.rc` and `init.qcom.usb.rc`
   rather than ASUS' Nougat ones.
2. **Same logo.** `wait /dev/block/bootdevice` timed out and `mount_all` skipped every
   entry, 20 s each. Nougat's init made that link from `androidboot.bootdevice`; Pie's
   does not. Pie's ueventd does create `/dev/block/platform/soc.0/7824900.sdhci/by-name/`,
   so one line in `init.qcom.rc` is enough:
   `symlink /dev/block/platform/soc.0/${ro.boot.bootdevice} /dev/block/bootdevice`.
   The recovery had met the same missing link from the other side (its NOTES §3).
3. **To the bootloader after a minute.** Every HIDL service failed `registerAsService`
   with `UNKNOWN_ERROR`, healthd crashed four times, and init rebooted to the bootloader.
   The cause was binder: the M1b backport had given the kernel three binder devices but
   not the **scatter-gather transactions** HIDL is built on (`BC_TRANSACTION_SG`,
   `BINDER_TYPE_PTR`, `BINDER_TYPE_FDA`). Google's android-3.10 series did not apply to
   ASUS' CAF tree; LineageOS' kernel for the Xiaomi kenzo, same SoC and same CAF base,
   had a `binder.c` identical to ASUS' save for whitespace, and its 14 commits replayed
   without a conflict (`kernel/patches/0004`). Lesson: three device nodes in `/dev`
   proved the devices, not the protocol.
4. **LineageOS logo, forever.** With no audio HAL, `audioserver` crashed in a loop and
   `system_server` waited for `media.audio_policy` indefinitely. The AOSP stub HAL got
   past it until the real one came.
5. **Still the logo.** `system_server` died in TrustManagerService on a null keystore.
   `qseecomd` was not running — on stock it is started from `init.target.rc` — and once
   started it failed `RPMB_INIT` for want of four libraries it only `dlopen`s, which no
   `NEEDED` scan finds. With them the keymaster trustlet loaded, and LineageOS reached the
   launcher.
6. **No `/sdcard`.** Pie's `sdcard` daemon in LineageOS 16 has no FUSE path left; it
   wants sdcardfs or esdfs, and this kernel had neither. sdcardfs came from kenzo, 89
   commits (`kernel/patches/0007`), and the first boot with it looped on an oops in
   `__kmalloc`. The corrupted freelist pointer decoded to `mask=6, gid=1015` — sdcardfs'
   own mount options — which pointed at a **double free** of the private mount data in
   the 3.10 port, reached because Pie deliberately fails its first mounts with options
   this sdcardfs does not know. Kenzo's Android 8 never took that path. Fixed in
   `kernel/patches/0008`.

Useful during a boot loop: `adb logcat -b all` streams kernel messages too, without root,
as long as adbd comes up at all.

---

## 2. Audio: firmware from the wrong place, and an XML file Android ignored

- **No sound card at all.** The ADSP was not started: stock writes
  `/sys/kernel/boot_adsp/boot` in `early-boot`. Done by hand, it failed with
  `Invalid firmware metadata`, because ASUS' kernel loads the ADSP image from
  `/system/etc/firmware/adsp.*` (ASUS' own set, `b00`–`b12`), not from the modem
  partition's (`b00`–`b14`). With those files the card registers as `msm8952-snd-card`.
- **The HAL is from source** (`audio-caf/msm8952`), and does not compile without
  `MULTI_VOICE_SESSIONS`, `SND_MONITOR` and `PROXY_DEVICE`: `-Werror` trips on the unused
  stubs the others leave behind. Calibration (ACDB) is ASUS' blobs, 32-bit only.
- **Nothing played, not even a WAV.** Two missing files: `media_codecs.xml` (raw PCM goes
  through `OMX.google.raw.decoder` too) and the HIDL manifest (`IOmx` not found).
- **Watch the comments.** `--` inside an XML comment makes the file invalid, and Android
  discards an invalid `media_codecs.xml` or `manifest.xml` **silently**. It happened to
  both. Validate every XML file before building.

---

## 3. Wi-Fi, Bluetooth and their addresses

- **Wi-Fi** needs Qualcomm's `prima` driver, which ASUS built out of tree and never
  published. It is open source, and kenzo carries it in-tree (`kernel/patches/0009`).
  The chain, for whoever meets it next: `wcnss_service` opens `/dev/wcnss_wlan` to power
  the core; the HAL writes `sta` to `/sys/module/wlan/parameters/fwpath`, which must be
  owned by the wifi user; prima then loads. The HAL needs `NET_ADMIN`, which Pie's init
  grants only through **ambient capabilities**, a 4.3 feature (`kernel/patches/0010`).
- **Bluetooth** on the WCNSS goes over SMD, not a UART. Without
  `ro.qualcomm.bt.hci_transport=smd`, `hci_qcomm_init` waits for a `/dev/ttyHS0` that does
  not exist.
- **The addresses** are not in the modem, whatever the RIL tools suggest: ASUS wrote them
  to `/persist` at the factory (`wifi_mac.txt`, and the NV item `.bt_nv.bin`). A script
  hands them to the drivers. If they are missing, a stable address is derived from the
  serial number; `/persist` is never written.

---

## 4. Sensors: a missing user, and a race

- **No sensors.** `sensors.qcom` starts as root and drops to the user `sensors` by name.
  Pie has no such user, so it fell to `nobody`, and the IPC router refused it: the stock
  `sec_config` lets only group 3011 talk to the sensor services on the ADSP. Giving the
  service that group in init keeps it across the drop.
- **No sensors again, sometimes.** Found only on the first release build. The HAL asks
  the daemon for the sensor list once, at start, and keeps the answer. In Nougat the HAL
  lived inside `system_server`, long after the daemon; in Pie it is its own service in
  class `hal`, which init starts **before** `late_start`, where the daemon is. Whether the
  tablet had sensors depended on timing. Init now restarts the HAL once the daemon's
  socket exists.

---

## 5. Hardware video (Venus): four separate refusals

Each one only showed after the previous one was fixed.

1. **Build:** `TARGET_USES_ION`, and a V4L2 control (`IFRAME_SIZE`) the encoder expects
   from a newer `msm_vidc` (`kernel/patches/0011`, from kenzo).
2. **Every codec died on open.** seccomp: `blocked syscall: pselect6`, from the message
   threads of the Qualcomm decoder and encoder. Pie's `mediacodec` policy does not allow
   it; the device's own policy file adds it.
3. **Black picture, sound playing.** `Gralloc2: invalid usage bits 0x2000000` — the
   decoder asks for a private uncached buffer flag Pie's gralloc does not know.
   `TARGET_ADDITIONAL_GRALLOC_10_USAGE_BITS := 0x02000000U` tells it.
4. **Recording failed after hours of uptime:** `Failed to allocate relocatable region`.
   The Venus firmware is unloaded 15 s after the last use and reloaded on the next one,
   into a 5 MB CMA region, and after long enough that reload could no longer get its
   memory. Keeping the firmware loaded (`firmware_unload_delay` at its maximum) removes
   the reload; recording has worked since.

---

## 6. GPS: a blob that wants a null

- `hardware/qcom/gps` in LineageOS 16 is an **older** `loc_api` than ASUS', and ASUS'
  `libloc_api_v02` does not fit it. Kenzo's HAL, from the same CAF branch as ASUS, does
  (`tools/setup-gps.sh` fetches it at a pinned commit).
- It still did not start, because ASUS' `createLocApiV02` **refuses a non-null
  `MsgTask`** and only creates the API object when given null. On stock the caller was
  Qualcomm's IZat proxy, which passes null. Read off the disassembly; the patch in
  `tools/gps-patches` passes null and lets the base class use the context's task.
- Pie does not read `gps.conf` for the assistance servers: the framework's
  `config_gpsParameters` overlay overrides the HAL.

---

## 7. Cameras: ASUS' own stack, and a few bytes

The camera was expected last and possibly never. ASUS changed both the HAL and the
daemon (their "DIT" framework), so a HAL from source would have to match their private
structures; the whole stock stack is used instead, HAL included. Each failure below was
found in a tombstone or a log, in this order:

- **Missing symbol.** The HAL calls `android::Fence::~Fence()`, which Pie made an inline
  default and stopped exporting. A one-function shim (`shims/camera`) provides it.
- **Zygote aborted at boot.** ASUS' `media_profiles` uses Qualcomm's `vga` and
  `timelapsevga` quality names, which Pie's parser rejects with a `CHECK`.
  `extract-files.sh` drops those blocks.
- **Provider crash** in the DIT library: it needs three data files from
  `/system/lib/DataSet`.
- **Daemon abort:** `pthread_mutex_destroy called on a destroyed mutex`. A teardown
  block in the ISP library runs twice; Pie's bionic aborts on the second destroy, and in
  this bionic the check cannot be turned off. The two calls are replaced by no-ops.
- **HAL1 crashed in preview**: Pie's `camera.device@1.0` passes a different cookie to
  `get_memory` than ASUS' HAL expects. **HAL3** works, except that the provider first
  probes `openLegacy`, and ASUS' HAL1 constructor crashes on that probe. `open_legacy`
  now returns `-ENOSYS` at once.

The blob patches are applied by `extract-files.sh`, only to a file whose SHA-256 and
original bytes match exactly. The camera blob list was cut from the 531 files ASUS
shipped — tuning for their whole sensor range — to 137, by reading which sensors the
running kernel actually probed (`rom/HARDWARE.md`).

---

## 8. Things that were wrong all along, and only showed later

- **Apps had a 16 MB heap.** No `dalvik.vm.heap*` was set, so every app got the default.
  Found through an app from F-Droid. The stock values are those of the AOSP
  `tablet-10in-xhdpi-2048` heap configuration.
- **The CPUs never slept.** The low-power modes were off (`sleep_disabled`) and the
  governor fixed at maximum, because stock's `init.qcom.post_boot.sh` does that tuning
  and nothing here ran it. Now it is in `init.qcom.rc`, with stock's values.
- **The kernel log was flooded.** Pie calls `getrandom()` all the time, and on 3.10 each
  call to an unknown syscall prints a register dump. Backported from kenzo
  (`kernel/patches/0012`).
- **"There's an internal problem with your device"** at boot: the system and vendor
  fingerprints differed, because incremental builds regenerate one `build.prop` and not
  the other. The fingerprint is fixed in `BoardConfig.mk`, and changing it means
  deleting the property files first — `tools/release-build.sh` does that.
- **exFAT cards would not mount.** Stock read them with Tuxera's closed module, and 3.10
  has no exFAT of its own. Samsung's GPL driver is built in now (`kernel/patches/0013`);
  NTFS already worked, through ntfs-3g. To test either without a card: put a formatted
  image at `/data/misc/vold/virtual_disk` and run `sm set-virtual-disk true`. Android
  then treats it as a card, check and mount included. A plain loop mount of an image
  elsewhere fails with "Invalid argument", because SELinux does not let the kernel's
  loop thread read the file. `sm set-virtual-disk false` deletes the image.

---

## 9. SELinux enforcing

- In permissive, almost every Qualcomm daemon was running **as init**: the binaries were
  in `/system/bin`, where nothing labels them, so there was no domain transition.
  Enforcing Pie refuses to start a service without one. Installed in
  `/system/vendor/bin` instead, they are labelled by `sepolicy-legacy` into their proper
  domains.
- Two failures showed only when enforcing **from boot**, not when switching at runtime:
  a script starting a service through `ctl.start` (denied — Wi-Fi never came up), and
  `hci_qcomm_init` reading `/firmware`. Test enforcing from a cold boot.

---

## 10. Release builds, and three things development builds hid

- **The boot image inside the zip was unsigned.** Pie's OTA tools sign it only when
  `verity_key` is in `misc_info`, which happens only with `PRODUCT_SUPPORTS_VERITY` —
  i.e. "sign the boot image without dm-verity" falls through a gap. `BOARD_CUSTOM_BOOTIMG`
  makes the build put its own signed image into the zip.
- **No USB at all with adb off.** Pie's platform `init.usb.rc` handles only adb and the
  accessory modes on the legacy gadget; MTP, PTP, tethering and MIDI are the device's to
  define. On Pie, "charging only" is MTP with data locked, so with adb off nothing
  answered. Development builds never showed it: with adb on, the default is plain adb.
- **Still no USB.** ASUS' bootloader calls an ordinary boot `androidboot.mode=main`.
  Pie's USB service treats anything but `normal` or `unknown` as a factory mode, where it
  compared the wrong properties and concluded MTP was already set. A small library in
  init (`TARGET_INIT_VENDOR_LIB`) renames `main` to `normal`; `charger` and the other
  modes are untouched.
- **USB mode greyed out** in Settings: they need a port reporting the device role, and
  ports come from a USB HAL. LineageOS' basic one is enough.
- And the sensor race in §4.

---

## 11. Building it

- **WebView is in Git LFS**, and `repo` leaves a 134-byte pointer: the build fails at
  ~94% with `zip END header not found`. See `rom/README.md`.
- **GitHub rate-limits unauthenticated git downloads**, and `repo` reports it as "git
  requires authentication". `GIT_TRACE_CURL` shows the real `x-github-edge-message`.
  Authenticating (SSH, or a token with no scopes) finishes the sync.
- **`KERNEL_MAKE_FLAGS` is not a hook**: LineageOS clears it. Use
  `TARGET_KERNEL_ADDITIONAL_FLAGS`.
- **Kernel headers are cached by Soong** (`generated_kernel_includes`). After changing a
  uapi header, delete that intermediate, or the HALs keep compiling against the old one.
- **After a crash mid-build, look for empty object files.** A power cut left a `.o` at
  zero bytes with a fresh timestamp; ninja considered it up to date and the link failed
  an hour and a half later with `file is empty`.

---

## 12. Mistakes worth repeating out loud

- **Write partitions by name, never by number.** One restore was once typed with the
  partition number from memory, and the number was wrong: it overwrote a small
  TrustZone partition instead. Caught before any reboot and restored from the backup —
  which is the case for the full backup the READMEs insist on. Use
  `/dev/block/bootdevice/by-name/<name>`, and check where it points before `dd`.
- **A log that is quiet is not a log that says "fine".** The camera daemon, the sensor
  daemon and `qseecomd` all failed without a word in places where the reason was only
  visible elsewhere — a tombstone, the IPC router, a `dlopen`.
- **Development builds hide release bugs.** adb on by default masked three USB problems
  and luck masked a sensor race. Build a release early and run the whole test round on
  it.
