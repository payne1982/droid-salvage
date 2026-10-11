# From recovery to a ROM — the plan for ASUS_P00I

TWRP works, so the tablet is no longer a one-way street: anything that fails can be
restored. That is the precondition for trying a ROM at all, and it is now met.

## The target: LineageOS 16.0 (Android 9)

Not the newest thing that exists — the newest thing this hardware can actually run.
The reasons are measured, not guessed:

1. **Android 10+ needs `bpf()`, and Linux 3.10 does not have it.** The syscall landed
   in 3.18; Android 10's `netd` builds traffic accounting on eBPF. Verified absent
   from the published kernel tree, not merely unset in the configuration.
2. **Android 10 also removed the FUSE `sdcard` daemon**, and this kernel has no
   `sdcardfs`. *Corrected later: Pie's daemon cannot do without sdcardfs either, so it
   was backported (`kernel/patches/0007`). Android 10 still needs `bpf()`.*
3. **There is no `vendor` partition** — this tablet is pre-Treble, and the partition
   table is not something to rewrite on a device whose bootloader is locked. LineageOS
   16.0 is the last branch with genuine non-Treble support, so a GSI is out and a
   full device tree is in.
4. **The vendor blobs are Nougat, and Pie can use them as they are.** Android 9 binds
   HIDL interfaces to legacy HAL modules through the AOSP `@N.N-impl` wrappers, and
   the wrappers load exactly the `*.msm8952.so` files already on the tablet —
   `hwcomposer`, `gralloc`, `sensors`, `lights`, `memtrack`, `power`, `gatekeeper`,
   `keystore`. Pie is the last version where that is a supported path rather than a
   fight.
5. **The recovery is already a Pie tree**, so everything learned getting TWRP to work
   — the `bootdevice` symlinks, `property_contexts`, the keymaster loading by
   `ro.board.platform`, the `qseecom` permissions — carries over instead of being
   relearned, and the build host is already set up for a tree of that vintage.

Android 9 is two releases up from stock, keeps Vulkan (the tablet ships
`vulkan.msm8952.so`), and gets a current WebView. If it boots and proves solid,
Android 10 becomes a question about backporting `bpf()` and `sdcardfs` — worth asking
then, not now.

## Milestones

Each one is independently verifiable, and nothing moves to the next until the current
one is proven on the hardware. That discipline is not caution for its own sake: on
this tablet every unverified change costs a reboot cycle, and two changes at once
already cost a day once.

### M0 — a kernel we build ourselves, running on the tablet
Build `Image.gz-dtb` from the ASUS sources with `asus_P00I_defconfig` — same sources,
same configuration as the shipped kernel, only compiled by us — and swap it into the
**TWRP recovery image**, leaving everything else in that image alone.

Nothing about the ROM is in play here. It answers the one question everything else
rests on: can this tree produce a kernel that runs on this hardware? If the toolchain
or the configuration is wrong, this is where it shows, on a change with exactly one
variable, rather than inside a first ROM boot where a hundred things could be the
cause.

Recovery rather than `boot`, for two reasons. The recovery image already carries the
kernel copied out of `boot`, so replacing just the kernel really is a single change.
And if the kernel does not come up, `boot` is untouched: the tablet still starts the
stock Android with root, which is a far more comfortable place to recover from than
the reverse.

Pass criteria: TWRP starts, `adb` comes up, `/proc/version` names our build, the
configuration embedded in the image matches what we built, `dmesg` shows no new
failures, and touch, mounts and `/data` decryption still work exactly as in the
released `payne_13`.

**Done, 6 October 2026.** See `kernel/README.md`.

One wrinkle: the touchscreen fix currently lives as a 3-byte patch of the *compiled*
stock kernel. `tools/patch-kernel.py` locates the site by scanning for code rather
than at a fixed offset, so it should find it in our build too — and whether it does
is itself a useful test of the tool. If it does not, the fix moves into the driver
source, which is M1's job anyway.

The foundations are in `kernel/` and the configuration is proven to round-trip; what
is left is the compile and the test on the hardware.

### M1 — the same kernel, ready for a modern userspace
Add the options in `kernel/README.md` — the cgroup controllers an Android 8+ init
expects, plus `/proc/config.gz` so the running kernel can be inspected on the device —
and move the touchscreen fix from a 3-byte patch of the compiled image to where it
belongs, the `mxt_probe` guard in the driver source. Still has to run: the changes are
additive, so if anything stops working we broke it.

**Done, 6 October 2026.** Six options, three patches, all confirmed on the tablet —
`cpuset` and `memory` now appear in `/proc/cgroups`, `/proc/config.gz` reports exactly
what we built, and touch, mounts, `/data` decryption and `adb` are unaffected. One of
the patches fixes a bug in ASUS's tree: with `CONFIG_MEMCG` on, `mm/memcontrol.c` does
not compile. See `kernel/README.md`.

### M1b — three binder devices
Android 8 split binder into three domains — `/dev/binder`, `/dev/hwbinder`,
`/dev/vndbinder` — and this kernel registers exactly one. `drivers/android/binder.c`
has a single `misc_register(&binder_miscdev)` with `.name = "binder"`, and there is no
`CONFIG_ANDROID_BINDER_DEVICES`: multi-device support arrived in 4.11 and was
backported into Google's android-3.x branches for devices moving to Oreo. Without it
`hwservicemanager` has nothing to open, and HIDL is how Android 9 talks to every HAL.

The work is not a configuration switch. The context manager state
(`binder_context_mgr_node`, `binder_context_mgr_uid`) is file-scope global in this
version and has to become per-device, which is exactly what the upstream change does —
so this should start from that patch, or from a 3.10 kernel already running LineageOS
16, rather than be written from scratch.

It has one pleasant property: it can be verified in recovery, with no ROM involved.
If `/dev/binder`, `/dev/hwbinder` and `/dev/vndbinder` all appear, it works.

**Done, 6 October 2026.** All three appear, registered as misc devices 56, 57 and 58.
The backport came from Google's own `deprecated/android-3.10` branch rather than from
the upstream 4.11 commit, so it was written for this exact kernel version. Touch,
mounts, the cgroup controllers from M1 and `/proc/config.gz` all still work, and the
running configuration matches what was built. See `kernel/README.md`.

**Not done after all, 9 October 2026.** Three devices are necessary and not sufficient:
HIDL's transactions are scatter-gather ones, which that backport did not include, and
the first LineageOS boot failed on exactly that (every HAL failed to register, healthd
crashed, init went to the bootloader). So the "verifiable in recovery" property above
was a trap: it checks the devices, not the protocol. Redone from LineageOS' kenzo
kernel (same SoC, same CAF base), which has the whole series; see `kernel/README.md`.

### M2 — device tree and vendor blobs
`device/asus/ASUS_P00I` for LineageOS 16.0, and `vendor/asus/ASUS_P00I` extracted
from the stock `/system`. The extraction needs no tablet at all: the full partition
dump is already in hand and `debugfs` reads an ext4 image without root or mounting.

**Done, 8 October 2026,** with the first complete build. The vendor tree is not committed:
`tools/extract-files.sh` produces it from your own dumps. See `rom/README.md`.

### M3 — first boot, measured in logs rather than in hope
The goal of the first boot is not a usable tablet, it is **observability**: `init`
running, `adbd` up, `logcat` and `dmesg` retrievable. Booting permissive — which this
kernel already allows, `CONFIG_SECURITY_SELINUX_DEVELOP` being set in the stock
configuration — with `logcat` redirected to a file early in `init`, and `pstore`
`console-ramoops` as the fallback that survives a warm reboot. A boot that fails
silently teaches nothing; a boot that fails loudly is progress.

**Done, 9 October 2026.** LineageOS 16 boots to the launcher from the installed zip, by
itself, in under a minute, with `/sdcard` mounted and nothing crashing. It took six
boots, each stopped by one missing thing and each found in the logs: no device init to
run `mount_all`; no `/dev/block/bootdevice` link; binder without scatter-gather (the
M1b patch was not enough, see above); no audio HAL, which hangs system_server; no
`qseecomd`, and with it no keystore; no sdcardfs, which Pie's sdcard daemon cannot do
without. The kernel side came from LineageOS' kernel for the Xiaomi kenzo, same SoC
and same CAF base, plus one fix of ours for a double free that kenzo's Android 8 never
reached. Display and GPU, which this roadmap expected to be the hardest part, worked
from the first boot that got that far.

Still open at that point, carried into M4: real audio, Wi-Fi, Bluetooth, sensors, RIL,
camera, GPS; SELinux permissive; `adb` open without authorisation; the boot image inside
the OTA zip unsigned. All of it was closed in M4 and M5.

### M4 — the HALs, one at a time
Expected order of difficulty: display first and hardest (a Pixelworks **iris2**
bridge sits between the SoC and the panel, and the hwcomposer blob is Nougat), then
input, audio, sensors, Wi-Fi, then RIL, with the camera last. Each one shipped only
when it demonstrably works.

**Done, 10 October 2026.** Audio, Wi-Fi, Bluetooth, the modem, sensors, the hardware video
codecs, GPS and both cameras, each confirmed on the tablet, in roughly that order — one
commit per subsystem. The expectations above were wrong in both directions: the display
worked from the first boot, and the camera, expected last and possibly never, works
with ASUS' own HAL and a few bytes patched in two blobs. What each one needed is in the
commit messages and in the comments next to the code; `rom/HARDWARE.md` has the map.

### M5 — release
Same conventions as the recovery: `payne_N`, AVB1-signed with the public AOSP test
key, on GitHub Releases. Unlike the recovery it needs no `dd`: the zip installs from
TWRP and writes a `boot` image that is already signed.

**In progress.** Done: SELinux enforcing, the CPU and low-power settings stock used,
secure adb, the signed boot image inside the zip, and a release build that passes the
whole test round on the tablet. Making the first release build found three more things
development builds had hidden — no USB at all with adb off, the USB mode greyed out, and
a race that could leave the tablet without sensors — all fixed. Left, before a first
image: a test with a SIM and an exFAT card in the slot. `rom/README.md` has those and
everything else that is missing or untested.

## What could still stop this

Worth stating plainly rather than discovering later. Written before the work; kept, with
how each one turned out.

- **Display.** If the Nougat `hwcomposer.msm8952.so` cannot be driven through Pie's
  composer wrapper, the fallback is building the display HAL from the CAF sources
  matching this SoC, and if the iris2 bridge needs vendor code that is only in the
  blob, that is the hard limit. *It was not a problem: the display HAL is built from
  the CAF sources and worked from the first boot.*
- **Camera.** Usually the last thing to work on a legacy port, sometimes never. *It
  works, both cameras, photos and video.*
- **The 3.10 kernel itself.** It sets the ceiling at Android 9 and no amount of
  userspace work changes that. *Still true.*

No dates. The recovery took the time it took.
