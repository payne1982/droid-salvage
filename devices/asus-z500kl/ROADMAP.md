# From Android 9 to Android 13 — the plan for ASUS_P00I

LineageOS 16 for this tablet is released (`payne_31`) and stays on the branch
`L1_DEV_LOS16`; how it got there is in [`ROADMAP-LOS16.md`](ROADMAP-LOS16.md). This
branch, `L1_DEV_LOS20`, is an experiment on top of it: the same tablet, the same 3.10
kernel, the same Nougat vendor files, under LineageOS 20. Nothing here is promised to
work. What does not work will be written down as carefully as what does.

## Why this is possible after all

The first roadmap said the 3.10 kernel fixes the ceiling at Android 9. Two of its
reasons do not hold, and both were checked on 11 October 2026.

**eBPF.** `netd` counts traffic per application, and since Android 9 it can do it with
eBPF programs, which need the `bpf()` system call this kernel does not have. In
Android 10 and 11 it still falls back to the older `xt_qtaguid` when eBPF is missing
(`server/TrafficController.cpp`: `BpfLevel::NONE` in 10, `if (!mBpfEnabled)` in 11).
Android 12 removed the fallback: `TrafficController::start()` loads its maps and
programs with no alternative. LineageOS calls adding eBPF to a kernel this old close to
impossible, and no 3.10 kernel that was looked at has it. What the devices that went
further do instead is put the fallback back on the Android side:
[LineageOS-UL](https://github.com/LineageOS-UL/android) ("ultra legacy") is LineageOS
with forks of `netd`, `system/bpf`, the Connectivity module and some thirty other
projects, and a device opts in with `ro.kernel.ebpf.supported=false`. The kernel keeps
using `xt_qtaguid`, which ours has.

**The vendor partition.** Treble asks for one of a device that *launches* with
Android 8 or later. A ROM built for one device can keep the vendor files in
`/system/vendor`, as `payne_31` does.

Two devices show it running:

| | SoC | kernel | Android |
|---|---|---|---|
| Samsung Galaxy Tab S2 (2016), `gts210velte` | MSM8976 | 3.10.108, no `kernel/bpf` | LineageOS 20, unofficial, built on LineageOS-UL |
| Sony Xperia Z5 family, `kitakami` | MSM8994 | 3.10.108, no `kernel/bpf` | up to `lineage-23.2`, maintained today |

The first is the closest relative this tablet has: MSM8976 is MSM8956 with two more
cores, it is a tablet with LTE and a 1536x2048 panel, and it has no vendor partition.

## The target: LineageOS 20 (Android 13), from the LineageOS-UL manifest

Android 13 because that is where the reference device is, so there is something to
compare with at every step. LineageOS-UL also has `lineage-21.0`; that is a question
for later, and depends on how the tablet carries 13.

## What the reference device changed between 16 and 20

From comparing `android_device_samsung_msm8976-common` at `lineage-16.0` (LineageOS) and
at `lineage-20` ([ronnz98](https://github.com/ronnz98/android_device_samsung_msm8976-common)).
This is the list of what to expect here too.

- **No kernel change of its own.** The tree for 20 uses the same kernel repository,
  whose current branch is still called `lineage-16.0`. Compared with ours, option by
  option: binder, cgroups, `xt_qtaguid`, sdcardfs, seccomp, FUSE, dm-verity, swap on
  zram and the USB gadget are the same, and ours has `MEMCG` and the three binder
  devices on top. Theirs has a few things ours lacks, none of them a backport: the
  netfilter matches tethering uses (`rpfilter`, `TCPMSS`, IPv6 NAT), `PSTORE_PMSG`,
  which keeps the last `logcat` across a reboot, and F2FS, which this tablet does not
  need since its `/data` is ext4.
- **`/system` mounted by the first stage of init.** From Android 10 `init` itself
  lives in `/system`, so the ramdisk has to mount it before anything else. Their
  kernel declares it in the device tree (`firmware/android/fstab`); their `fstab.qcom`
  marks `/system` as `recoveryonly`. Ours mounts `/system` from `on fs` today: this has
  to change, in the device tree or with an fstab in the ramdisk. It also ends the
  problem of the `.rc` files read too late, which 16 worked around.
- **`ro.kernel.ebpf.supported=false`**, and `product_launched_with_m.mk`.
- **Audio** from the 2.0 HAL wrappers to 7.0, with a service of its own, and a
  Bluetooth audio HAL.
- **Camera**: the provider built 32-bit only, with `camera.device@1.0-impl`.
- **Keymaster and gatekeeper**: the hardware-backed 3.0 keymaster is replaced by the
  AOSP `keymaster@4.1-service`, and gatekeeper by the software service. On 16 this
  tablet has hardware-backed keys; whether it keeps them is open.
- **Graphics**: the same `gralloc.msm8952` and `hwcomposer.msm8952` built from the CAF
  sources, mapper `2.0-impl-2.1`; memtrack and copybit dropped.
- **Lights, Wi-Fi, health**: lights as an AIDL service, the legacy Wi-Fi service,
  health 2.0.
- **SELinux permissive**: `androidboot.selinux=permissive` is on their kernel command
  line. `payne_31` is enforcing, so enforcing on 20 is work nobody has done for us.
- A handful of `BUILD_BROKEN_*` switches, a `PRODUCT_SOONG_NAMESPACES` entry, the
  private sepolicy directory, one VNDK library copied from the v29 prebuilts.

Users of the Samsung builds report a camera that does not load its HAL and no audio on
headphones on some models. Those are the two places to expect trouble first.

## Milestones

As before: each one is verified on its own, and nothing moves on until it is.

### L0 — the tree and the host
The LineageOS-UL `lineage-20.0` sources on the build machine, and a host that can
build them: Python 3 where the Android 9 tree wanted 2.7, and 23 GB of memory, which
means fewer parallel jobs. Pass: `lunch` accepts a product.

**Done, 11 October 2026.** The analysis of the whole tree peaks at 21.9 GB as it comes
and at 15.9 GB with Go's collector told to work harder, which a small patch to the build
system lets the environment ask for.

### L1 — the device tree builds
`device/asus/ASUS_P00I` moved to the Android 13 build system: the product and board
makefiles, the VINTF manifest, the sepolicy split, the properties, the eBPF switch,
first-stage mount. The vendor files stay the ones `tools/extract-files.sh` produces
from the stock image. The patches under `tools/tree-patches` are checked one by one.
The keyguard one is gone: Google fixed the same race in July 2025 (`handleShow()` now
drops a pending hide), and the fix arrives with the merge described under L5. Pass:
`mka bacon` produces a zip.

**Done, 12 October 2026.** The build completes and produces the zip; its install script
writes `system` and `boot` only. Nothing of it has run on the tablet yet. The steps, and
the ten places where the build stopped on the way, are in
[`rom/BUILDING-LOS20.md`](rom/BUILDING-LOS20.md).

### L2 — first boot, for the logs
Permissive, `adb` open, `logcat` and `dmesg` retrievable, `pstore` as the fallback: the
same goal as M3 on 16, observability and nothing more. Written to `boot` and `system`
only. The recovery is not touched, and going back to `payne_31` is a Format Data and
an install from TWRP.

**Done, 13 October 2026.** The third boot reaches the LineageOS setup wizard and stays
there, SELinux permissive, 1536x2048 at 320 dpi, with a root `adb`. The first stayed on
the bootloader logo and the second completed the boot and lost `system_server` a second
later; what each asked for is in [`rom/BUILDING-LOS20.md`](rom/BUILDING-LOS20.md), and
one of the answers is a kernel patch (`kernel/patches/0015`). The recovery partition
has the hash it had before. Nothing has been tried beyond seeing the first screen.

### L3 — the HALs, one at a time
Display and GPU first, because nothing else can be judged without a screen; then
audio, Wi-Fi, Bluetooth, sensors, the modem (data and SMS, as on 16), the video
codecs, GPS, the cameras, keymaster and gatekeeper, DRM. `rom/HARDWARE.md` is the map
of what each one needed on 16.

**Begun, 13 October 2026.** What stopped them from starting is dealt with: six changes,
listed in [`rom/BUILDING-LOS20.md`](rom/BUILDING-LOS20.md). They all start, Bluetooth
and Wi-Fi switch on, the boot takes 47 seconds.

**In use, 17 October 2026.** Under enforcing: Wi-Fi, Bluetooth headphones, audio,
sensors, the video codecs, GPS, the cameras, the microphone, Widevine at L3, a USB
cable plugged in at any time; and since 18 October charging from a Quick Charge 3
adapter at 9 V and with the system off; with nothing changed for them, a PIN across a
restart (keymaster and gatekeeper), wired headphones, MTP and the cover's magnet. What
each needed is in [`rom/BUILDING-LOS20.md`](rom/BUILDING-LOS20.md). Not tried yet: the
modem with a SIM and a microSD card. Since 20 October the tablet suspends on standby:
a night unplugged took about 1%.

### L4 — what a release has
SELinux enforcing, secure adb, the signed boot image, the fixed fingerprint. Each of
these exists on 16 and has to be redone, not copied.

**Done, 20 October 2026.** The release `payne_32`, signed with this version's own keys,
went on after *Format Data*: enforcing, with no denial left from the vendor files and a
few from Android's own; adb closed, the USB port answering as MTP without it; the boot
image signed for the bootloader; the same fingerprint in the nine files that carry one.
The setup wizard went through; on its Wi-Fi page the word "Internet" is cut short.

### L5 — the test round, and a decision
The round `payne_31` passed, on a clean installation, then with Google apps. Only then
the question whether this is worth publishing next to 16 or instead of it.

**Begun, 20 October 2026.** The release `payne_32` went on after *Format Data* (see L4),
then once more after another *Format Data*, this time followed by MindTheGapps
13.0.0-arm64 (25 October 2023, the package LineageOS' wiki names for 20) before the
first start. Google's setup wizard went through; the recovery partition was the same
after each install. The headphones connect, and the Assistant opens on a long press of
*home*. The Play Store said the device was not certified, and after its ID was
registered with Google it still called it incompatible with Chrome and YouTube, which it
also left out of its search. The device tree had never set `ro.opengles.version`, so
Android told apps of no OpenGL ES version at all; `payne_32` was built again with 3.2,
stock's value (21 October), and installed over the previous one, the Google apps kept.
With the Play Store's data cleared, it now offers apps at its first start, and those
installed run. Scrolling jumped, in Android's own screens too: SurfaceFlinger drew
every layer with the GPU on every frame, because the display hardware composes only
when `persist.hwc.mdpcomp.enable` is set, as stock did and neither tree had. With it,
scrolling stops jumping. Apps from the Play Store run uncompiled until Android compiles
them overnight; Prime Video ran a little better once compiled by hand. Nothing was
compiled while running either, because ART kept its JIT off on a kernel older than 3.12;
with two kernel patches (24 October) it runs in every process, and scrolling in Prime
Video and Google News shows no tearing or visible slowdowns. Not tried yet: the wizard's options
left switched off.

**Before anything is published: bring the LineageOS-UL forks up to date ourselves.**
They stopped on 4 April 2025, and LineageOS has kept patching `lineage-20.0` since. Measured
on 11 October 2026, the fork of `frameworks/base` carries 59 changes of its own and lacks
184 of LineageOS'; `frameworks/av` 55 and 15; `frameworks/native` 30 and 13; the
Connectivity module 8 and 5. An image built from them as they are has the security level
of April 2025 in exactly the parts that matter most. The work is merging LineageOS'
branch into each fork and resolving what collides.

For `frameworks/base` it could not wait: the projects LineageOS-UL does not fork follow
LineageOS, and six of them (ContactsProvider, Settings, Telephony, MmsService,
IntentResolver, Trebuchet) stopped compiling against a framework of April 2025.
`tools/merge-lineage.sh` merges LineageOS' branch into the fork at a fixed commit; the
184 commits went in without a conflict.

**20 October 2026: the other forks.** The tree takes 37 projects from LineageOS-UL.
Measured against LineageOS' `lineage-20.0` on full histories: nine lacked LineageOS
commits, `frameworks/native` (11), `packages/modules/Bluetooth` (20),
`frameworks/opt/telephony` (6), `packages/apps/Nfc` (4), `vendor/lineage` (4),
`packages/modules/adb` (3), `Connectivity` (2), `Wifi` (2) and `bionic` (1), mostly
security fixes (Bluetooth's SDP, A2DP, AVRCP and SMP, binder's `Parcel`, adb's TLS). All
nine merged without a conflict and are lines in `tools/lineage-merges.txt`. The others
lack nothing, or are UL's own branches (the CAF ones, `sepolicy-legacy`) or forks of AOSP
projects LineageOS builds at AOSP's tag. `vendor/lineage` now takes its APNs from
`vendor/apn`, a project LineageOS added in November 2025, which
`rom/local_manifests/lineage-20-forks.xml` brings in. Build L3zg, with all of it, starts
and works under enforcing: Wi-Fi, Bluetooth, the APNs, one known denial. One of the
Bluetooth fixes broke headphones: after pairing, the audio and call channels were never
opened. `tools/tree-patches/packages/modules/Bluetooth/0002` says why and takes out the
one line at fault; with it the Galaxy Buds pair, connect and play in AAC again.

## What could stop this

- **The Nougat vendor files under Android 13.** On 16 they load through wrappers Pie
  still supports. Four versions later each one is a separate question, and graphics is
  the one everything else waits on.
- **Memory.** 4 GB and a 2048x1536 screen. Android 13 on the Tab S2, which has 3 GB,
  says it starts; it does not say it is pleasant.
- **LineageOS-UL stopped moving.** Its `lineage-20.0` repositories were last pushed in
  April 2025, while the rest of the tree follows LineageOS to this day. Its manifest
  needed 17 projects redirected before the tree would even be analysed
  (`rom/local_manifests/lineage-20-forks.xml`), and its `frameworks/base` had to be
  brought forward before six applications would compile. What that means for security,
  and what is still to do, is under L5.
- **The kernel is still 3.10.** eBPF is the requirement that was known. Others may
  appear only when something fails to start; each goes on this page when found.
- **The build machine.** It built `payne_31`. A tree four versions newer asks for
  more memory than it has, which is paid in build time.

## Not in this plan

- **A mainline kernel.** [msm8956-mainline](https://codeberg.org/msm8956-mainline/linux)
  has Linux 7.2 running on three devices with this SoC, without modem, audio, camera,
  video decoding or sensors, and on four cores. This tablet would also need a driver for
  its display path (dual DSI in command mode behind a Pixelworks iris2 bridge) and for
  its charger. With such a kernel none of the vendor files apply, so it is a different
  project from this ROM, not a step of it.
- **A vendor partition and generic system images.** It means rewriting the partition
  table of a tablet whose bootloader is locked, the one operation here that is only
  undone through EDL. Not needed for anything above.

No dates.
