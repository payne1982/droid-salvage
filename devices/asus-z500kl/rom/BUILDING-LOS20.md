# Building LineageOS 20 for ASUS_P00I

Where the experiment described in [`../ROADMAP.md`](../ROADMAP.md) stands: milestone L1.
The tree builds and `mka bacon` produces a flashable zip. **That image has never been
booted.** Nothing below says it works on the tablet; installing it is milestone L2, and
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

# 1b. two local manifests. lineage-20-forks.xml moves 17 projects to LineageOS' forks:
#     the LineageOS-UL manifest stopped in April 2025 and still points them at AOSP.
#     asus-p00i-lineage-20.xml adds the MSM8952 audio, display and media HALs, which
#     LineageOS 20 no longer carries.
mkdir -p .repo/local_manifests
cp devices/asus-z500kl/rom/local_manifests/*.xml <tree>/.repo/local_manifests/
repo sync -c -j4 --no-clone-bundle

# 1c. WebView is in Git LFS and repo leaves a 134-byte pointer in its place.
( cd external/chromium-webview/prebuilt/arm64 && git lfs install --local && git lfs pull )

# 2. this device tree
rsync -a devices/asus-z500kl/rom/device/ <tree>/device/

# 3. the kernel: the same sources and patches as for 16, plus patches/0014
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
  on 13, and the kernel command line asks for enforcing: a first boot will want
  `androidboot.selinux=permissive` there.

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
