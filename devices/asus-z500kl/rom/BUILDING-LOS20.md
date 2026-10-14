# Building LineageOS 20 for ASUS_P00I

Where the experiment described in [`../ROADMAP.md`](../ROADMAP.md) stands: milestone L2
reached, L3 begun. The tree builds, `mka bacon` produces a flashable zip, and on the
tablet that image starts and gets through the LineageOS setup wizard. **Little has been
used beyond that**: Wi-Fi connects and the browser works, the camera shows a preview,
Bluetooth switches on, and SELinux is permissive.
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

# 1b. three local manifests. lineage-20-forks.xml moves 17 projects to LineageOS' forks:
#     the LineageOS-UL manifest stopped in April 2025 and still points them at AOSP.
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

# 3. the kernel: the same sources and patches as for 16, plus patches/0014 to 0016
devices/asus-z500kl/kernel/tools/setup-kernel.sh      # KERNEL_TREE=<tree>/kernel/asus/msm8956

# 4. the vendor blobs and ASUS' init scripts, and the GPS HAL source
cd <tree>/device/asus/ASUS_P00I
./tools/extract-files.sh --from-dumps /path/to/system.img /path/to/boot.img
./tools/setup-gps.sh

# 5. bring frameworks/base up to LineageOS (the script says why), then the changes to
#    the tree's own sources. In this order: the merge wants a clean project.
./tools/merge-lineage.sh
./tools/apply-tree-patches.sh

# 6. build. WITH_ADB_INSECURE is for bring-up: adb on from the first boot and with no
#    key to accept on the screen, so that a system that starts halfway still gives a
#    root shell. Not for an image meant to be used.
cd <tree> && source build/envsetup.sh && lunch lineage_ASUS_P00I-userdebug
WITH_ADB_INSECURE=true SOONG_GOGC=25 mka bacon
```

After a `repo sync`, steps 5 again: the sync puts the projects they change back as the
manifest has them.

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

- The image is signed with AOSP's test keys and is a `userdebug` build. `release-build.sh`
  has not been moved to this version.
- `/data` is not encrypted. Android 13 removed full-disk encryption, which 16 uses
  here, and the file-based kind needs kernel support a 3.10 does not have.
- The boot image carries the signature the bootloader of this tablet checks, appended
  by `boot_signer` as on 16; Android 13 still has the tool, and the 1320-byte trailer
  is there. That the bootloader accepts it has not been tried.
- SELinux policy is the one written for 16 and compiles. Nobody has seen what it denies
  on 13, so the kernel command line carries `androidboot.selinux=permissive` for now:
  this image does not enforce it.

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

The second fix has been tried: the preview runs. The first one only acts at the end of
a setup wizard, and no wizard has been run since; on the tablet the copy left over was
stopped by hand.

Not looked at yet: netd on a kernel without eBPF. The forks this tree uses tolerate the
missing maps, but the log is full of them, and the iptables rules that refer to eBPF
programs (data usage limits, data saver) are not installed.

`tools/missing-symbols.py` lists what the blobs import that the image does not have,
all at once instead of one failed `dlopen` per boot. On this image it finds 38 symbols
in 13 files; only the radio one has been dealt with.

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
