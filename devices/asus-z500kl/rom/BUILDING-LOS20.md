# Building LineageOS 20 for ASUS_P00I

Where the experiment described in [`../ROADMAP.md`](../ROADMAP.md) stands: milestone L2
reached, L3 begun. The tree builds, `mka bacon` produces a flashable zip, and on the
tablet that image starts and gets through the LineageOS setup wizard. **Little has been
used beyond that**: Wi-Fi connects, also again with the screen off, the browser plays
video, the camera takes photos and video, Bluetooth headphones connect and play, the
GPS has had a fix at a window, it charges, from a Quick Charge 3 adapter at 9 V and
with the system off too, and SELinux is enforcing.
[`README.md`](README.md) still describes LineageOS 16, the release that does work.

## What the host needs

- Python 3 as `python` and `python3` (the Android 9 tree wanted 2.7; this one must not
  find it first).
- `git-lfs`, for WebView.
- `libncurses.so.5` and `libtinfo.so.5`. One prebuilt compiler in the tree, the clang
  RenderScript still uses, links against them. Where the distribution no longer ships
  them they can be unpacked anywhere and named in `LD_LIBRARY_PATH`;
  `tools/tree-patches/build/soong/0002` is what lets that variable reach the compiler.
- `LEX` and `YACC` unset. Some distributions export `LEX=flex`, and the build stops
  with *Soong variable check failed*.
- Memory. The analysis step (`soong_build`) peaks at 21.9 GB as it comes. With
  `SOONG_GOGC=25` in the environment it peaks at 15.9 GB and takes 24 seconds longer;
  `tools/tree-patches/build/soong/0001` is what makes the build read that variable.
  This was built on 23 GB with six parallel jobs.

## Steps

```sh
# 1. the LineageOS-UL manifest: LineageOS 20 with the forks that keep it running on a
#    kernel without eBPF
repo init -u https://github.com/LineageOS-UL/android.git -b lineage-20.0 --depth=1

# 1b. three local manifests. lineage-20-forks.xml moves 17 projects to LineageOS' forks
#     and adds vendor/apn: the LineageOS-UL manifest stopped in April 2025 and still
#     points them at AOSP.
#     lineage-20-camera.xml takes frameworks/av from LineageOS instead of UL (the file
#     says why). asus-p00i-lineage-20.xml adds the MSM8952 audio, display and media
#     HALs, which LineageOS 20 no longer carries.
mkdir -p .repo/local_manifests
cp devices/asus-z500kl/rom/local_manifests/*.xml <tree>/.repo/local_manifests/
repo sync -c -j4 --no-clone-bundle

# 1c. WebView is in Git LFS and repo leaves a 134-byte pointer in its place.
( cd external/chromium-webview/prebuilt/arm64 && git lfs install --local && git lfs pull )

# 2. this device tree
rsync -a devices/asus-z500kl/rom/device/ <tree>/device/

# 3. the kernel: the same sources and patches as for 16, plus patches/0014 to 0017
devices/asus-z500kl/kernel/tools/setup-kernel.sh      # KERNEL_TREE=<tree>/kernel/asus/msm8956

# 4. the vendor blobs and ASUS' init scripts, and the GPS HAL source
cd <tree>/device/asus/ASUS_P00I
./tools/extract-files.sh --from-dumps /path/to/system.img /path/to/boot.img
./tools/setup-gps.sh

# 5. bring ten of LineageOS-UL's forks up to LineageOS (the script and
#    tools/lineage-merges.txt say why), then the changes to the tree's own sources. In
#    this order: the merge wants a clean project.
./tools/merge-lineage.sh
./tools/apply-tree-patches.sh

# 5b. SQLite 3.44.5 in place of 3.42.1 (the script says why)
./tools/setup-sqlite.sh

# 6. build. WITH_ADB_INSECURE is for bring-up: adb on from the first boot and with no
#    key to accept on the screen, so that a system that starts halfway still gives a
#    root shell. Not for an image meant to be used.
cd <tree> && source build/envsetup.sh && lunch lineage_ASUS_P00I-userdebug
WITH_ADB_INSECURE=true SOONG_GOGC=25 mka bacon
```

After a `repo sync`, steps 5 and 5b again: the sync puts the projects they change back
as the manifest has them.

The result is `out/target/product/ASUS_P00I/lineage-20.0-<date>-UNOFFICIAL-ASUS_P00I.zip`.
Its install script writes `system` and `boot` and nothing else. The zip also carries a
`recovery.img`, which the script does not install.

**The recovery partition.** Left to itself, Android 13 would also put
`/vendor/bin/install-recovery.sh` and a copy of LineageOS' recovery inside the system
image, and LineageOS' setup wizard and Updater would offer to "update the recovery"
with them. On this tablet that partition must not be rewritten. `BoardConfig.mk` sets
`TARGET_NO_RECOVERY_PATCH`, a switch added by `tools/tree-patches/build/make/0001`, and
neither file is in the image: checked in the target files the zip is made from, where
the only mentions of the recovery partition left are the two copies of `fstab.qcom` and
the SELinux label of the device node.

## What is not done, or not verified

- Development builds are signed with AOSP's test keys, and every build is `userdebug`.
  A release is built with `tools/release-build.sh <name>`, moved to this version on 18
  October: it gives the build its own fingerprint, the same in the nine property files
  that carry one, and stops if adb is open or the build is signed with the test keys.
  One test release went through it on 18 October and was not installed. The release
  `payne_32` was, on 20 October, after *Format Data*: it starts, the setup wizard goes
  through, adb stays closed until it is switched on in the developer options and the
  computer's key accepted, and root over adb needs the developer option as well. With
  adb off the USB port answers as MTP, which on 16 had needed a fix.

  Signing works as on 16 (`README.md`, "Signing"), with more keys: `releasekey`,
  `platform`, `shared`, `media`, `networkstack`, `bluetooth`, `sdk_sandbox`, `testkey`
  and `testcert`, in `vendor/lineage-priv/keys/`. All can be RSA 4096: Android 13
  checks updates against X.509 certificates, and the 2048-bit limit of 16's `dumpkey`
  is gone. The APEXes are flattened here, so they need no keys of their own. To keep
  development builds installable over a system that runs on the test keys, the
  `keys.mk` used here signs only builds with a release name:

  ```make
  ifneq ($(filter-out dev,$(P00I_RELEASE)),)
  PRODUCT_DEFAULT_DEV_CERTIFICATE := vendor/lineage-priv/keys/releasekey
  endif
  ```

  A release then goes on after *Format Data*, or after the migration of
  `packages.xml` described for 16.
- Once, on 19 October, the tablet could not suspend for a quarter of an hour after the
  cable came out: every attempt stopped at the last step, because the PMI8950's voltage
  ADC said a conversion was pending. It did not happen on the next try or in the night
  that followed, and why it happened is not known.
- `/data` is not encrypted. Android 13 removed full-disk encryption, which 16 uses
  here, and the file-based kind needs kernel support a 3.10 does not have.
- The boot image carries the signature the bootloader of this tablet checks, appended
  by `boot_signer` as on 16; Android 13 still has the tool, and the 1320-byte trailer
  is there. The bootloader accepts it: every development build since 13 October was
  installed from its zip, boot image included, and started, and so did the release
  `payne_32`.
- SELinux is enforcing from boot since 15 October. Until 20 October it also denied,
  some three hundred times a boot, the vendor processes looking up the Nougat blobs'
  own switches (the media codecs, the sensors, camera, composer and GNSS HALs, the
  radio daemons): names Android 13 leaves unlabelled, which vendor code may not read.
  None of them is set, so the denials changed nothing, but they buried any real one.
  `sepolicy/property_contexts` labels them now, the names taken from the blobs and
  from bionic's "Access denied finding property" lines; three that the graphics
  libraries read inside every process that draws, apps included, have a label of
  their own the system may read. What is left, on build L3zf after a boot, the
  camera and the video encoder: three reads by Android's own processes
  (`ro.bootimage.build.fingerprint` by system_server, a LineageOS camera property by
  cameraserver, one by audioserver). A SIM and mobile data have not been tried under
  enforcing.
- Photos taken in Aperture, LineageOS' camera application, came out turned by 90
  degrees when the screen's rotation was locked in landscape: Aperture then seems to
  take the orientation from the screen, not the accelerometer. With rotation left
  automatic and the tablet turned normally, they come out the right way up. Open
  Camera saved them the right way up either way.

## What the first boots asked for

13 October 2026, three boots. Each row is a commit on this branch.

| What happened | What was done |
|---|---|
| Bootloader logo, nothing more. `mount_all` failed: `/firmware`, `/persist` and `/dsp` do not exist and cannot be made in a root directory that is now the system image. init never learned that `/data` is not encrypted and never started zygote | `BOARD_ROOT_EXTRA_FOLDERS` |
| `adb root` hangs on a system in that state: it waits for a binder service that starts with the rest of Android | `rootdir/init/init.p00i.bringup.rc`, on builds made with `WITH_ADB_INSECURE` |
| SurfaceFlinger aborts every 18 seconds, priming its shader cache on a texture format the Adreno driver of 2017 does not make | `service.sf.prime_shader_cache=0` |
| Boot completed, then `system_server` dies in a loop: keystore2 gets no SELinux context for its callers from the kernel's binder | `kernel/patches/0015` |

A warning that comes with the first row. When a mount fails, fs_mgr runs `e2fsck -y` on
the partition, whether or not the fstab asks for a check. On that first boot it did so
on `persist` and `dsp` and changed both (the padding of the inode bitmap, nothing else).
`persist` holds what cannot be had again; a copy of it belongs among the backups before
an image of this kind is started for the first time.

The fourth boot, the same day, had three more, each for something the third one showed
crashing or not starting:

| What happened | What was done |
|---|---|
| `pm-proxy`, Qualcomm's peripheral manager client, dies with *stack corruption detected*. Its library of 2017 keeps `Parcel` objects on the stack and reserves 104 bytes for each; Android 13's are 120. The camera HAL does the same in 32 bits, 52 against 60 | `tools/tree-patches/frameworks/native/0001` |
| The radio daemon does not load: `libril-qc-qmi-1.so` wants `AudioSystem::setErrorCallback`, which Android 13 replaced | `shims/ril` |
| The Bluetooth application aborts on its first timer: no thread may become real-time | `CONFIG_RT_GROUP_SCHED` off, [`../kernel/README.md`](../kernel/README.md) |

With these the radio daemon reads the modem's version and reports no SIM (there was
none in the tablet) and `pm-proxy` stays up. The fifth and sixth boots:

| What happened | What was done |
|---|---|
| Bluetooth still aborts: *Unable to get a Bluetooth service after 500ms*. On a build that does not enforce its VINTF manifest every HIDL `getService` sleeps one second, 291 times in that boot, and the stack asks for a HAL version this tablet does not have before the one it has | `PRODUCT_ENFORCE_VINTF_MANIFEST_OVERRIDE` |
| Wi-Fi never comes on, and `system_server` waits forever for the supplicant: Android 13 asks init for whoever declares the AIDL interface, and the service still declared the HIDL ones | `rootdir/init/init.qcom.rc` |
| Bluetooth aborts once more, on the answer to a vendor command Android 13 added: *Waiting for 0xfd57 (LE_ADV_FILTER), got 0x157* | `bluetooth.le.disable_apcf_extended_features` |

The first of these also took the boot from 160 seconds to 47.

Where that left the hardware early on 14 October, before anyone used it: Bluetooth and
Wi-Fi switch on, and a Wi-Fi scan lists networks; nothing had been paired or connected.
The sensor, camera, audio, GPS and radio HALs register, the accelerometer gives
readings, the hardware H.264 encoder encodes the screen. None of this is use: no
picture taken, no sound played, no fix, no SIM.

The first time someone used it, 14 October, through the setup wizard to a connected
Wi-Fi and a web page:

| What happened | What was done |
|---|---|
| At the end of the wizard the notification shade does not come down, and home and recents do nothing. The wizard's last activity is recreated when the taskbar goes away, runs its exit twice and crashes on the second (*Receiver not registered*); a second copy of the wizard is left holding the status bar disabled | `tools/tree-patches/packages/apps/SetupWizard/0001` |
| The camera application stops as it opens: cameraserver refuses the stream configuration, *Parcel data not fully consumed, unread size: 24*. LineageOS-UL put the native camera service back to Android 12 for HAL1 devices and left the Java side on Android 13 | `local_manifests/lineage-20-camera.xml`, `tools/tree-patches/frameworks/base/0001` |
| With the preview running, taking a photo, recording or closing the camera kills the camera HAL's process, in gralloc. The HAL of 2017 allocates 8 bytes for an `android::Fence`, Nougat's size; Android 13's has a vtable and is 12, and its constructor writes the fence's fd past the end of the HAL's allocation. Found with GWP-ASan on the provider process | `shims/camera`: the HAL gets every `Fence` function it imports, with Nougat's layout |
| YouTube in the browser stops on the first frame, with no sound: the hardware VP9 decoder gets no output buffers. Android 13 marks them `VIDEO_DECODER` (0x00400000), which this gralloc reads as "take them from the camera ION heap", and the kernel has no such heap (*ION_IOC_ALLOC failed with error - No such device*). The same was found on the Galaxy Tab S2 | [`../kernel/patches/0021`](../kernel/README.md) declares the heap, as system memory; at first a tree patch to gralloc stopped it asking for the heap |

The second and third fixes have been tried: photos from both cameras and a 1080p
video with sound, and malloc debug, which counted 27 writes into freed memory in a few
seconds of preview before the third, finds none after it. So has the fourth: a 720p VP9
video plays in the browser, smoothly and with sound. The first one only acts at
the end of a setup wizard, and no wizard has been run since; on the tablet the copy left
over was stopped by hand.

Not looked at yet: netd on a kernel without eBPF. The forks this tree uses tolerate the
missing maps, but the log is full of them, and the iptables rules that refer to eBPF
programs (data usage limits, data saver) are not installed.

`tools/missing-symbols.py` lists what the blobs import that the image does not have,
all at once instead of one failed `dlopen` per boot. On this image it found 38 symbols
in 13 files. The radio one has been dealt with; the other 37 belong to libraries
nothing here loads or that fail the same way on 16 (Adreno's RenderScript driver,
which Android 13 loads only when asked by name, so RenderScript runs on the CPU;
TrustZone's secure display; parts of IMS), and are left as they are.

15 October, a day of use with the tablet on the desk, one HAL at a time:

| What happened | What was done |
|---|---|
| Every process that ends costs about 200 ms (*Failed to kill ... 1 processes remain*), and `system_server` cannot move apps between cpusets (*AddTidToCgroup failed ... Permission denied*). Android 13 keeps each process in a cgroup of its own in the cgroup v2 hierarchy; a 3.10 kernel has no cgroup v2, and the groups were plain directories in a tmpfs | `tools/tree-patches/system/core/0001` mounts a v1 hierarchy (cpuacct) in its place, `configs/cgroups/cgroups.json`, `kernel/patches/0017` |
| qcril keeps its database in `/data/misc/radio`, a path written into its library, which Android 13 keeps from vendor code | `tools/extract-files.sh` rewrites it to `/data/vendor/ril`, `rootdir/init/init.qcom.rc`, `sepolicy/file_contexts` |
| What the policy of 16 is denied on 13: `init.qcom.rc` runs as `vendor_init`, its triggers on plain service names are dropped (`per_proxy` never started), and the QSEE, radio and data daemons share properties that were `default_prop` | `sepolicy/`, `rootdir/init/init.qcom.rc` |
| With the screen off, a dropped Wi-Fi connection comes back after 21 minutes: the chip's background scan (PNO) is refused as *not supported*. Android 13 reads that setting from the Wi-Fi module's resources, not from framework-res | `rro_overlays/WifiOverlay` |
| No XTRA file is downloaded, so a first fix takes about ten minutes; once one is named, the modem refuses it. Android 13 reads only `LONGTERM_PSDS_SERVER_*`, and the servers in ASUS' `gps.conf` now give XTRA2 files under the name of the XTRA3 ones, which this modem does not take | `tools/tree-patches/frameworks/base/0002`: Qualcomm's xtracloud.net servers |

All five have been tried. Processes are killed in 0 to 5 ms and neither error comes
back; qcril creates its database in the new place; with the policy switched to
enforcing on the running system, Wi-Fi, sensors, camera, audio and GNSS work with no
denial; Wi-Fi turned off and on with the screen off is connected again after 10 s; the
XTRA file is taken by the modem about 40 s after boot.

15 to 17 October, Bluetooth headphones, a slow start, a cable and a search:

| What happened | What was done |
|---|---|
| Headphones pair and are dropped at once. Android 13 starts a Bluetooth profile only if a property says so, and none did but GATT | `bluetooth.profile.*.enabled` in `device.mk` |
| Connected, they stay silent and the sound comes from the speakers. The audio policy file named a device type Android 13 does not know (`AUDIO_DEVICE_OUT_ALL_SCO`), and the whole file was thrown away for it: only the primary output was left, with no A2DP and no USB. The A2DP module, `audio.a2dp.default`, was not in the image, LineageOS 20 building it only for the Bluetooth APEX, and the audio HAL was not allowed to reach the Bluetooth stack's sockets | `configs/audio/audio_policy_configuration.xml`, `tools/tree-patches/packages/modules/Bluetooth/0001`, `sepolicy/hal_audio.te` |
| The sound runs 0.3 to 1 s ahead of the picture. With the headphones' delay report the module told players of about 650 ms of latency, for headphones that report 179 | `persist.bluetooth.disabledelayreports` |
| Five minutes on the ASUS logo, on a start with no USB cable. BoringSSL's self-test waits for the kernel's random pool, which here filled from interrupts alone: the kernel was built without the chip's random number generator | `CONFIG_FIPS_ENABLE` off, [`../kernel/README.md`](../kernel/README.md) |
| `prng_seeder` gives up at every boot: ASUS' `ueventd.qcom.rc` keeps `/dev/hw_random` for root, and the daemon starts before the node exists | `tools/extract-files.sh`, `rootdir/init/init.qcom.rc` |
| A USB cable plugged in after the start gives neither charging nor USB. ASUS' charger driver holds every insertion until told that Quick Charge 3 is supported, which Qualcomm's `hvdcp_opti` did on stock and nothing did here | [`../kernel/patches/0018`](../kernel/README.md); at first `init.qcom.rc` told the driver itself, which kept Quick Charge adapters at 5 V (below) |
| F-Droid's search looks hung: 88 s for "gp". The query planner of SQLite 3.42.1, the version Android 13 has, runs a full-text match once for every app in a join | `tools/setup-sqlite.sh`: SQLite 3.44.5, from LineageOS 22.2 |

All have been tried, under enforcing: headphones play AAC, in step with the picture
with the delay-report property set by hand (the image has it since, and with it the
headphones have not been tried again); on a start without a cable the self-test waits
0.1 s where it had waited 152; `prng_seeder` holds `/dev/hw_random` open; a cable
unplugged and plugged back is charged from and seen by the computer; the same F-Droid
search takes 0.13 s, and in a round of use nothing else looked different.

18 October, charging:

| What happened | What was done |
|---|---|
| Quick Charge adapters charge at 5 V. Telling the driver from init that Quick Charge 3 is supported, as was done for the cable above, also tells it to leave the voltage to `hvdcp_opti`, which was not there | `hvdcp_opti` from stock: `proprietary-files.txt`, `rootdir/init/init.qcom.rc`; the policy is sepolicy-legacy's, with what stock's allowed it besides in `sepolicy/hvdcp.te`, and labels for the ADCs and the parallel charger in `sepolicy/genfs_contexts`. Without the last one the daemon sleeps for good |
| Plugged in with the system off, the tablet shows the bootloader's battery picture with the screen on for good. Android 13 leaves the charger service to the device, and there was none | `vendor.charger` in `rootdir/init/init.qcom.rc`: AOSP's charger with LineageOS' animation |
| The lock screen says plain "charging" whatever is plugged in, a computer or a Quick Charge 3 adapter at 9 V. Android goes by the largest current_max times voltage_max among the supplies, and here those figures are the type-C port's, 1.5 A at 5 V, not the charger's | `health/HealthService.cpp`, `sepolicy/hal_health.te` |
| On an adapter ASUS' driver takes for ASUS' own 9 V one, the lock screen stops saying the tablet is charging a few seconds after it goes in. The driver reports "Quick charging" or "Not Quick charging", values of its own that Android takes for an unknown status | [`../kernel/patches/0019`](../kernel/README.md) |

Tried, under enforcing: a Xiaomi MDY-11-EZ (Quick Charge 3) goes from 5 to 8.5 V in
the steps of `hvdcp_opti`, and the battery takes 1.2 to 1.4 A at 77% where it took
0.8 to 1.1; the driver holds its input to 900 mA.
ASUS' AD2068020 is a Quick Charge 2 adapter, and ASUS' driver asks it for 9 V in the
wrong bits, so it stays at 5 V, with 1.6 to 1.9 A into the battery; that is ASUS'
code and is left as it is. Off-mode charging shows the animation and the level,
turns the screen off, shows them again at a press of the power key and starts
Android when the key is held. The lock screen says "charging slowly" on a
computer, and with the time to full on the Raspberry Pi's port (900 mA at 5 V); on
the Xiaomi "slowly" for the first seconds, then "rapidly" once it is at 9 V; with
`patches/0019` that stays when the driver takes the adapter for ASUS'.

The same day two workarounds went from Android to the kernel, where their causes
are: [`../kernel/patches/0020`](../kernel/README.md) keeps the Venus firmware loaded,
which `init.qcom.rc` had done through debugfs, and `patches/0021` gives the kernel the
camera heap the decoders ask for, which a tree patch to gralloc had stopped them
asking for. Tried on build L3zb: VP9 and H.264 at 1080p play in hardware, 181 frames
at 30 fps, the VP9 decoder taking its 15 MB from the new heap and giving them back
at the end; the camera takes a photo and records a video.

19 October, standby. A night on standby, 18 to 19 October, had taken about 4% in nine
hours, but only because idle cores power down on their own: the kernel counted 581
attempts to suspend and none that went through. At each one it caches again the
firmware it has handed out, found none of the files where it looked (`/lib/firmware`)
and asked `ueventd` for them, and the uevents aborted the freezing of user space.
[`../kernel/patches/0022` and `0023`](../kernel/README.md) make it look in
`/system/etc/firmware` and read the files as the kernel. Tried on build L3zd, the
night of 19 to 20 October, unplugged and with the screen off: in eight hours the
tablet suspended 108 times, woken mostly by Android's alarms every ten minutes and by
the modem, and the battery gave 82 mAh, about 1%.

21 and 22 October, with the Google apps, and what stock set that this tree did not:

| What happened | What was done |
|---|---|
| The Play Store calls the tablet incompatible with Chrome, YouTube and most apps, and leaves them out of its search. Nothing set `ro.opengles.version`, so Android told apps of no OpenGL ES version at all | `ro.opengles.version` in `device.mk`, 3.2 as on stock |
| Scrolling jumps, in Android's own screens too. SurfaceFlinger drew every layer with the GPU on every frame: the display HAL lets the display hardware compose only when `persist.hwc.mdpcomp.enable` is set | the property in `device.mk`, as on stock |
| A crash of the modem would restart the whole tablet: every subsystem had the restart level SYSTEM. Stock set the modem's to RELATED with `ssr_setup` | [`../kernel/patches/0025`](../kernel/README.md) |
| After a restart with no network the time is June 1978. The PMIC's clock may not be set; stock kept the time with Qualcomm's `time_daemon` and TimeService. A kernel that made the clock writable reset the tablet 25 to 30 s after every start, when the network gave the time and Android wrote it into the clock, and was withdrawn | `timekeep` and its receiver (`hardware/sony/timekeep`) in `device.mk`, `sepolicy/timekeep.te`, `sepolicy/system_app.te` |

Tried on release `payne_32`, under enforcing: the Play Store offers apps at its first
start, and those installed run; Android's screens scroll without jumping, the layers
going to the display hardware (`mdpCount: 3`, none to the GPU); the modem reads
RELATED and the other subsystems SYSTEM (a crash has not been provoked); with WiFi off
and no mobile connection the time after a restart is right to the second, with nothing
denied to `timekeep` or its receiver. Music already went to the DSP: an MP3 in Eleven
played through an offload output, with nothing changed for it.

24 October, the JIT. An app deriving a key with PBKDF2 took 33 s on the tablet for
what is nearly instant elsewhere: no process compiled anything while running.

| What happened | What was done |
|---|---|
| ART turns its JIT off on kernels older than 3.12: before upstream commit db6f41063cbd an arm64 kernel took a fault on a cache-maintenance instruction for a write | [`../kernel/patches/0027`](../kernel/README.md), that one-line fix; `tree-patches/art/0001` lowers ART's minimum to 3.10 |
| With the JIT allowed, system_server restarted in a loop: the JIT wants its code in memory from `memfd_create()`, a 3.17 system call, and system_server may not fall back to memory both writable and executable | [`../kernel/patches/0028`](../kernel/README.md), `memfd_create()` and file sealing from 3.17; `TARGET_HAS_MEMFD_BACKPORT` in `BoardConfig.mk` |

Tried on release `payne_32i`: system_server, the system UI, the launcher and the
Google services each have a JIT thread and its code cache, with no crash; the same key
takes about 1 s. Scrolling in Prime Video and Google News is not perfectly smooth, but
without tearing or visible slowdowns.

25 October, a SIM and a microSD card:

| What happened | What was done |
|---|---|
| Leaving airplane mode brought up "SIM card added" and a dialog whose only button restarts the tablet. qcril powered the card down in airplane mode, it read absent, and the framework took its return for a new card. Stock kept it powered and declared the slot hot-swappable | `persist.radio.apm_sim_not_pwdn=1` in `system.prop`, `config_hotswapCapable` in the framework overlay |
| A 256 GB microSD card read at 40 MB/s, from exFAT and from the raw device alike, on a bus at UHS SDR104 and 160 MHz. Every block device starts with a read-ahead of 128 KB; with 512 KB the card reads at 68 MB/s | [`../kernel/patches/0029`](../kernel/README.md), for SD cards only |
| Bars and text fields flickered black for a frame, Messaging's toolbar and Chrome's address bar among them, with apps redrawing only what had changed | `debug.hwui.use_buffer_age=false` in `system.prop`: apps redraw their whole window |

Tried on release `payne_32i`, with each property set by hand: the PIN, mobile data on
LTE and SMS; airplane mode on and off with the card loaded throughout and LTE back in
about 2.5 s, no dialog; the card mounted as portable storage, ejected, taken out and
put back; no flicker in Messaging.

17 October, what had not been used yet, with nothing changed for it: a first GPS fix
outdoors in 15 s; H.264, HEVC (also at 3840x2160), MPEG-4, VP8 and VP9 decoded by the
hardware at 30 frames a second; the microphone; the light sensor; Widevine at L3,
provisioned by Google's server, as on 16. The same day, on the tablet: a PIN on the
lock screen, asked for again after a restart; wired headphones, with their
microphone; file transfer (MTP) to a Windows PC; the cover's magnet switching the
screen off.

## What had to change to get here

In the order the build asked for it. Each is a commit on this branch.

| Where it stopped | What was done |
|---|---|
| Analysis: `libdng_sdk` wants a `libjpeg` variant that is not there | `local_manifests/lineage-20-forks.xml` |
| `PLATFORM_SECURITY_PATCH` is read-only; packages that no longer exist; `LOCAL_COPY_HEADERS` | `BoardConfig.mk`, `device.mk` |
| `/system` has to be mounted before `init` can run from it | `fstab.qcom` in the ramdisk, `first_stage_mount` |
| `wpa_supplicant` driver library: `-Wformat` on three 64-bit values | `tree-patches/hardware/qcom-caf/wlan/0001` |
| RenderScript's clang cannot find `libncurses.so.5` | `tree-patches/build/soong/0002` |
| Vendor manifest: `<sepolicy>` clashes with the board's version; HALs that now bring their own fragment | `manifest.xml` |
| Kernel: output directory does not exist; the GCC wrapper is not executable | `kernel/patches/0014`, `BoardConfig.mk` |
| Eleven vendor executables fail the check on their `DT_NEEDED` entries | `BUILD_BROKEN_PREBUILT_ELF_FILES` |
| GPS: `set_sched_policy` undefined | `tools/gps-patches/0003` |
| Six applications do not compile against a framework of April 2025 | `tools/merge-lineage.sh` |
| Nothing stops, but the kernel modules go into the image unsigned and seven of fifteen not at all: the 3.10 kernel signs them with a perl script, and the perl LineageOS builds with has no `Getopt::Std` | `tree-patches/prebuilts/tools-lineage/0001`; `kernel/patches/0016` is what lets the kernel then load them |
