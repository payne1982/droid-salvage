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
   `sdcardfs`. Pie still ships the daemon, so Pie works without either.
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
Add the five options in `kernel/README.md`, `CONFIG_SECURITY_SELINUX_BOOTPARAM`
first, and move the touchscreen fix from a 3-byte patch of the compiled image to
where it belongs — the `mxt_probe` guard in the driver source. Still has to boot
Android 7: these are additive, so if it does not, we broke something.

### M2 — device tree and vendor blobs
`device/asus/ASUS_P00I` for LineageOS 16.0, and `vendor/asus/ASUS_P00I` extracted
from the stock `/system`. The extraction needs no tablet at all: the full partition
dump is already in hand and `debugfs` reads an ext4 image without root or mounting.

### M3 — first boot, measured in logs rather than in hope
The goal of the first boot is not a usable tablet, it is **observability**: `init`
running, `adbd` up, `logcat` and `dmesg` retrievable. Booting permissive (M1's
payoff), with `logcat` redirected to a file early in `init`, and `pstore`
`console-ramoops` as the fallback that survives a warm reboot. A boot that fails
silently teaches nothing; a boot that fails loudly is progress.

### M4 — the HALs, one at a time
Expected order of difficulty: display first and hardest (a Pixelworks **iris2**
bridge sits between the SoC and the panel, and the hwcomposer blob is Nougat), then
input, audio, sensors, Wi-Fi, then RIL, with the camera last. Each one shipped only
when it demonstrably works.

### M5 — release
Same conventions as the recovery: `payne_N`, AVB1-signed with the public AOSP test
key, image on GitHub Releases, written with `dd` because `fastboot flash` is
disabled.

## What could still stop this

Worth stating plainly rather than discovering later.

- **Display.** If the Nougat `hwcomposer.msm8952.so` cannot be driven through Pie's
  composer wrapper, the fallback is building the display HAL from the CAF sources
  matching this SoC, and if the iris2 bridge needs vendor code that is only in the
  blob, that is the hard limit.
- **Camera.** Usually the last thing to work on a legacy port, sometimes never.
- **The 3.10 kernel itself.** It sets the ceiling at Android 9 and no amount of
  userspace work changes that.

No dates. The recovery took the time it took.
